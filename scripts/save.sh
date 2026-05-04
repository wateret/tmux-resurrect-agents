#!/usr/bin/env bash
# tmux-resurrect post-save hook — discovers AI agent sessions from all tmux panes.
# Writes a sidecar JSON file alongside resurrect's save files.
#
# Supported tools: Claude Code, Codex CLI
# Detection: walks the process tree under each tmux pane looking for agent binaries.
# Session IDs: read from tool-native files (no hooks or settings.json modifications).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

CLAUDE_SESSIONS_DIR="${CLAUDE_SESSIONS_DIR:-${HOME}/.claude/sessions}"
CODEX_HOME="${CODEX_HOME:-${HOME}/.codex}"
OUTPUT_FILE="${DATA_DIR}/agent-sessions.json"
LOG_FILE="${DATA_DIR}/agent-save.log"

mkdir -p "$DATA_DIR"

if [ -f "$LOG_FILE" ]; then
	tail -n 500 "$LOG_FILE" >"${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" || true
fi

# Extract CLI args, stripping binary name/path and tool-specific session args.
extract_cli_args() {
	local raw_args="$1"
	local tool="${2:-}"

	local args="${raw_args#* }"
	if [ "$args" = "$raw_args" ]; then
		echo ""
		return
	fi

	# Node.js processes may show a second token that is the script path
	local first_arg="${args%% *}"
	case "$first_arg" in
	*/claude | */codex)
		args="${args#"$first_arg"}"
		args="${args# }"
		;;
	esac

	# Strip tool-specific session/resume args
	case "$tool" in
	codex)
		args=$(echo "$args" | sed -E 's/resume  *[^ ]*//')
		;;
	*)
		args=$(echo "$args" | sed -E 's/--resume[= ] *[^ ]*//; s/(^| )-c( |$)/ /')
		;;
	esac

	# Normalize whitespace
	echo "$args" | sed -E 's/  +/ /g; s/^ //; s/ $//'
}

# --- Main ---

main() {
	PS_FILE=$(mktemp)
	PANE_FILE=$(mktemp)
	PARTS_FILE=$(mktemp)
	trap 'rm -f "$PS_FILE" "$PANE_FILE" "$PARTS_FILE"' EXIT INT TERM

	local SAVE_TS
	SAVE_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

	log "save started"

	# Snapshot process table and pane info
	ps -eo pid=,ppid=,args= >"$PS_FILE" 2>/dev/null
	if [ ! -s "$PS_FILE" ]; then
		log "ps snapshot failed or empty, skipping save"
		return 1
	fi
	tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}|#{pane_pid}|#{pane_current_path}" >"$PANE_FILE"
	log "snapshot done (ps + pane list)"

	# Single awk pass: detect agent processes across all pane process trees
	log "scanning process trees"
	local MATCHES
	MATCHES=$(awk '
		NR == FNR {
			split($0, p, "|")
			pane_target[p[2]] = p[1]
			pane_cwd[p[2]] = p[3]
			pane_list[++pane_count] = p[2]
			next
		}
		{
			pid = $1+0; ppid = $2+0
			line = $0
			sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*/, "", line)

			proc_args[pid] = line
			child_list[ppid] = (ppid in child_list) ? child_list[ppid] SUBSEP pid : "" pid

			if (line ~ /(^claude( |$)|\/claude( |$))/) proc_tool[pid] = "claude"
			else if (line ~ /(^codex( |$)|\/codex( |$))/) proc_tool[pid] = "codex"
		}
		END {
			for (i = 1; i <= pane_count; i++) {
				root = pane_list[i]+0
				target = pane_target[pane_list[i]]
				cwd = pane_cwd[pane_list[i]]

				if (root in proc_tool && proc_tool[root] != "") {
					printf "%s\t%s\t%d\t%s\t%s\n", target, proc_tool[root], root, proc_args[root], cwd
				}

				delete queue
				qs = 1; qe = 0
				if (root in child_list) {
					nc = split(child_list[root], kids, SUBSEP)
					for (j = 1; j <= nc; j++) {
						k = kids[j]+0
						if (k > 0) { queue[++qe] = k }
					}
				}

				while (qs <= qe) {
					cur = queue[qs++]+0
					if (cur in proc_tool && proc_tool[cur] != "") {
						printf "%s\t%s\t%d\t%s\t%s\n", target, proc_tool[cur], cur, proc_args[cur], cwd
					}
					if (cur in child_list) {
						nc = split(child_list[cur], kids, SUBSEP)
						for (j = 1; j <= nc; j++) {
							k = kids[j]+0
							if (k > 0) { queue[++qe] = k }
						}
					}
				}
			}
		}
	' "$PANE_FILE" "$PS_FILE")

	rm -f "$PS_FILE" "$PANE_FILE"
	log "process tree scan done"

	# Deduplicate: keep first match per pane (BFS order)
	local CANDIDATES=""
	if [ -n "$MATCHES" ]; then
		local resolved_targets=""
		while IFS=$'\t' read -r target tool cpid cargs cwd; do
			[ -z "$target" ] && continue
			case "$resolved_targets" in
			*"|${target}|"*) continue ;;
			esac
			resolved_targets="${resolved_targets}|${target}|"
			CANDIDATES="${CANDIDATES}${target}"$'\t'"${tool}"$'\t'"${cpid}"$'\t'"${cargs}"$'\t'"${cwd}"$'\n'
		done <<<"$MATCHES"
	fi

	# Batch resolve all sessions in a single python3 call
	local detected=0 failed=0
	if [ -n "$CANDIDATES" ]; then
		local RESOLVED
		RESOLVED=$(CANDIDATES="$CANDIDATES" python3 "$SCRIPT_DIR/resolve_sessions.py" "$CLAUDE_SESSIONS_DIR" "$CODEX_HOME")

		# Process resolved results
		while IFS=$'\t' read -r target tool cpid session_id session_cwd cargs; do
			[ -z "$target" ] && continue
			[ "$session_id" = "-" ] && session_id=""
			[ "$session_cwd" = "-" ] && session_cwd=""
			detected=$((detected + 1))

			local tool_fmt
			printf -v tool_fmt '%-6s' "$tool"

			if [ -n "$session_id" ]; then
				local cli_args
				cli_args=$(extract_cli_args "$cargs" "$tool")

				[ -z "$session_cwd" ] && session_cwd="$cwd"

				printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
					"$target" "$tool" "$session_id" "$session_cwd" "$cpid" "$cli_args" >>"$PARTS_FILE"
				log "resolved  $tool_fmt in $target -> session $session_id"
			else
				failed=$((failed + 1))
				log "detected  $tool_fmt in $target (pid $cpid) but no session ID available"
			fi
		done <<<"$RESOLVED"
	fi

	# Convert TSV parts to final JSON output
	local count=0
	if [ -s "$PARTS_FILE" ]; then
		jq -Rs --arg ts "$SAVE_TS" '
			split("\n") | map(select(length > 0) | split("\t") |
			{pane:.[0], tool:.[1], session_id:.[2], cwd:.[3], pid:.[4], cli_args:.[5]})
			| {timestamp: $ts, sessions: .}
		' "$PARTS_FILE" >"$OUTPUT_FILE"
		count=$(jq '.sessions | length' "$OUTPUT_FILE")
	else
		jq -n --arg ts "$SAVE_TS" '{timestamp: $ts, sessions: []}' >"$OUTPUT_FILE"
	fi

	log "saved $count of $detected agent session(s) ($failed failed) to $OUTPUT_FILE"
}

# Allow sourcing without executing main (for tests)
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	main "$@"
fi
