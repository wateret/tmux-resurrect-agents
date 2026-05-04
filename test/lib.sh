#!/usr/bin/env bash
# Shared test library — assert functions, tmux helpers, environment setup.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_SHELL="${TEST_SHELL:-bash}"

case "$TEST_SHELL" in
zsh)
	SCRIPT_RUNNER="bash"
	PANE_SHELL="zsh"
	;;
*)
	SCRIPT_RUNNER="$TEST_SHELL"
	PANE_SHELL="bash"
	;;
esac

PASS=0
FAIL=0
ERRORS=""

# --- Assert functions ---

pass() {
	PASS=$((PASS + 1))
	echo "  PASS: $1"
}

fail() {
	FAIL=$((FAIL + 1))
	ERRORS="${ERRORS}\n  FAIL: $1"
	echo "  FAIL: $1"
}

assert_eq() {
	local desc="$1" expected="$2" actual="$3"
	if [ "$expected" = "$actual" ]; then
		pass "$desc"
	else
		fail "$desc (expected '$expected', got '$actual')"
	fi
}

assert_contains() {
	local desc="$1" haystack="$2" needle="$3"
	if echo "$haystack" | grep -qF -- "$needle"; then
		pass "$desc"
	else
		fail "$desc (expected to contain '$needle')"
	fi
}

assert_file_exists() {
	local desc="$1" path="$2"
	if [ -f "$path" ]; then
		pass "$desc"
	else
		fail "$desc (file not found: $path)"
	fi
}

# --- Run helpers ---

run_save() {
	"$SCRIPT_RUNNER" "$REPO_DIR/scripts/save.sh" "$@"
}

run_restore() {
	"$SCRIPT_RUNNER" "$REPO_DIR/scripts/restore.sh" "$@"
}

# --- tmux helpers ---

wait_for_child() {
	local ppid="$1" pattern="$2" timeout="${3:-10}"
	local deadline=$((SECONDS + timeout))
	while [ "$SECONDS" -lt "$deadline" ]; do
		local cpid
		cpid=$(ps -eo pid=,ppid=,args= | awk -v ppid="$ppid" -v pat="$pattern" \
			'$2 == ppid && $0 ~ pat {print $1; exit}')
		if [ -n "$cpid" ]; then
			echo "$cpid"
			return 0
		fi
		sleep 0.5
	done
	return 1
}

wait_for_pane_ready() {
	local target="$1" timeout="${2:-10}"
	local marker="__TMUX_READY_${RANDOM}_${RANDOM}__"
	local deadline=$((SECONDS + timeout))

	tmux send-keys -t "$target" "printf '%s\n' '$marker'" Enter
	while [ "$SECONDS" -lt "$deadline" ]; do
		if tmux capture-pane -pt "$target" 2>/dev/null | grep -qF "$marker"; then
			return 0
		fi
		sleep 0.2
	done
	return 1
}

get_pane_agent_pid() {
	local tool="$1" target="$2" timeout="${3:-15}"
	local pane_pid pattern

	case "$tool" in
	claude) pattern='(^claude( |$)|/claude( |$))' ;;
	codex)  pattern='(^codex( |$)|/codex( |$))' ;;
	*)      return 1 ;;
	esac

	pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || true)

	if [ -n "$pane_pid" ]; then
		local deadline=$((SECONDS + timeout))
		while [ "$SECONDS" -lt "$deadline" ]; do
			local found_pid
			found_pid=$(ps -eo pid=,ppid=,args= | awk -v root="$pane_pid" -v pat="$pattern" '
				{
					pid = $1 + 0
					ppid = $2 + 0
					line = $0
					sub(/^[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*/, "", line)
					proc_args[pid] = line
					child_list[ppid] = (ppid in child_list) ? child_list[ppid] SUBSEP pid : "" pid
				}
				END {
					if (root in proc_args && proc_args[root] ~ pat) {
						print root
						exit
					}

					qs = 1
					qe = 0
					if (root in child_list) {
						nc = split(child_list[root], kids, SUBSEP)
						for (i = 1; i <= nc; i++) {
							k = kids[i] + 0
							if (k > 0) queue[++qe] = k
						}
					}

					while (qs <= qe) {
						cur = queue[qs++] + 0
						if (cur in proc_args && proc_args[cur] ~ pat) {
							print cur
							exit
						}
						if (cur in child_list) {
							nc = split(child_list[cur], kids, SUBSEP)
							for (i = 1; i <= nc; i++) {
								k = kids[i] + 0
								if (k > 0) queue[++qe] = k
							}
						}
					}
				}
			')
			if [ -n "$found_pid" ]; then
				echo "$found_pid"
				return 0
			fi
			sleep 0.5
		done
	fi

	return 1
}

dump_pane_diagnostics() {
	local target="$1"
	echo "--- pane diagnostics: $target ---"
	echo "pane_current_command=$(tmux display-message -t "$target" -p '#{pane_current_command}' 2>/dev/null || true)"
	echo "pane_pid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || true)"
	echo "--- capture-pane ---"
	tmux capture-pane -pt "$target" 2>/dev/null || true
	echo "--- process snapshot ---"
	ps -eo pid=,ppid=,args= | grep -E 'claude|[[:space:]]zsh|[[:space:]]bash' || true
}

kill_pane_children() {
	local target="$1" kill_session="${2:-false}"
	tmux send-keys -t "$target" C-c 2>/dev/null || true
	local spid
	spid=$(tmux display-message -t "$target" -p '#{pane_pid}' 2>/dev/null || true)
	if [ -n "$spid" ]; then
		sleep 0.5
		ps -eo pid=,ppid= | awk -v root="$spid" '
			BEGIN { pids[root]=1 }
			{ if ($2 in pids) { pids[$1]=1; print $1 } }
		' | while read -r cpid; do kill -9 "$cpid" 2>/dev/null || true; done
	fi
	if [ "$kill_session" = "true" ]; then
		sleep 0.3
		tmux kill-session -t "$target" 2>/dev/null || true
	fi
}

# --- Environment setup ---

MOCK_SESSIONS_DIR=$(mktemp -d)
export CLAUDE_SESSIONS_DIR="$MOCK_SESSIONS_DIR"

TEST_DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
mkdir -p "$TEST_DATA_DIR"

RESTORE_LOG="$TEST_DATA_DIR/agent-restore.log"

# Source save script for unit-testable functions (detect_tool, extract_cli_args, posix_quote)
source "$REPO_DIR/scripts/save.sh"
