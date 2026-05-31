#!/usr/bin/env bash
# tmux-resurrect post-restore hook — re-launches AI agent sessions.
# Reads the sidecar JSON written by save.sh.
# Supported tools: Claude Code, Codex CLI

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

INPUT_FILE="$(agent_sessions_file)"
LOG_FILE="${DATA_DIR}/agent-restore.log"

if [ -f "$LOG_FILE" ]; then
	tail -n 500 "$LOG_FILE" >"${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" || true
fi

# --- Main ---

if [ ! -f "$INPUT_FILE" ]; then
	log "no saved sessions found at $INPUT_FILE"
	exit 0
fi

sessions=$(jq -r '.sessions // []' "$INPUT_FILE")
count=$(echo "$sessions" | jq 'length')

if [ "$count" -eq 0 ]; then
	log "no agent sessions to restore"
	exit 0
fi

log "restoring $count agent session(s)..."

# Parse all entries at once (one jq call instead of 5 per entry)
parsed=$(echo "$sessions" | jq -r '.[] | [.pane, (.tool // "claude"), .session_id, .cwd, (.cli_args // "")] | @tsv')

# Single ps snapshot for all guard checks
PS_SNAPSHOT=$(ps -eo pid=,ppid=,args= 2>/dev/null)

# Collect pane info in one tmux call
PANE_INFO=$(tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index}|#{pane_current_command}|#{pane_pid}" 2>/dev/null)

restored=0
skipped=0
while IFS=$'\t' read -r pane tool session_id cwd cli_args; do
	[ -z "$pane" ] && continue

	# Guard: check pane exists and is running a shell (from cached pane info)
	pane_line=$(echo "$PANE_INFO" | grep "^${pane}|" || true)
	if [ -z "$pane_line" ]; then
		log "pane $pane does not exist, skipping"
		skipped=$((skipped + 1))
		continue
	fi

	pane_cmd=$(echo "$pane_line" | cut -d'|' -f2)
	pane_cmd="${pane_cmd#-}"
	case "$pane_cmd" in
	bash | zsh | fish | sh | dash | ksh | tcsh | csh | nu) ;;
	*)
		log "pane $pane is running '$pane_cmd' (not a shell), skipping"
		skipped=$((skipped + 1))
		continue
		;;
	esac

	# Guard: skip if pane already has a running agent
	pane_shell_pid=$(echo "$pane_line" | cut -d'|' -f3)
	if [ -n "$pane_shell_pid" ]; then
		existing=$(pane_has_agent "$pane_shell_pid" "$PS_SNAPSHOT" || true)
		if [ -n "$existing" ]; then
			log "pane $pane already has a running agent (pid $existing), skipping"
			skipped=$((skipped + 1))
			continue
		fi
	fi

	# Build the resume command per tool
	safe_sid=$(posix_quote "$session_id")

	safe_cli_args=""
	if [ -n "$cli_args" ]; then
		set -f
		for _arg in $cli_args; do
			safe_cli_args="${safe_cli_args} $(posix_quote "$_arg")"
		done
		set +f
	fi

	resume_cmd=""
	case "$tool" in
	claude)
		if [ -n "$safe_cli_args" ]; then
			resume_cmd="command claude${safe_cli_args} --resume ${safe_sid}"
		else
			resume_cmd="command claude --resume ${safe_sid}"
		fi
		;;
	codex)
		if [ -n "$safe_cli_args" ]; then
			resume_cmd="command codex${safe_cli_args} resume ${safe_sid}"
		else
			resume_cmd="command codex resume ${safe_sid}"
		fi
		;;
	*)
		log "unknown tool '$tool' for pane $pane, skipping"
		skipped=$((skipped + 1))
		continue
		;;
	esac

	tool_fmt=""
	printf -v tool_fmt '%-6s' "$tool"
	log "restoring $tool_fmt in $pane (session: $session_id, cmd: $resume_cmd)"

	# Clear and send resume command
	tmux send-keys -t "$pane" "clear" Enter
	tmux clear-history -t "$pane"

	if [ -n "$cwd" ] && [ "$cwd" != "null" ]; then
		safe_cwd=$(posix_quote "$cwd")
		tmux send-keys -t "$pane" "cd ${safe_cwd} 2>/dev/null; ${resume_cmd}" Enter
	else
		tmux send-keys -t "$pane" "${resume_cmd}" Enter
	fi

	restored=$((restored + 1))
done <<<"$parsed"

log "restored $restored of $count agent session(s) ($skipped skipped)"
