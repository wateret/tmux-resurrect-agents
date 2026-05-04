#!/usr/bin/env bash
# Shared library for tmux-resurrect-agents save/restore scripts.

# --- Data directory selection ---

# Pick the resurrect data dir that was most recently updated
_dir1="${HOME}/.tmux/resurrect"
_dir2="${XDG_DATA_HOME:-${HOME}/.local/share}/tmux/resurrect"
if [ -d "$_dir1" ] && [ -d "$_dir2" ]; then
	if [ "$_dir1/last" -nt "$_dir2/last" ] 2>/dev/null; then
		DATA_DIR="$_dir1"
	else
		DATA_DIR="$_dir2"
	fi
elif [ -d "$_dir1" ]; then
	DATA_DIR="$_dir1"
else
	DATA_DIR="$_dir2"
fi

# --- Logging ---

# Epoch millis at script start (used for elapsed time in log messages)
if command -v python3 >/dev/null 2>&1; then
	_LOG_START_MS=$(python3 -c 'import time; print(int(time.time()*1000))')
elif date --version >/dev/null 2>&1; then
	_LOG_START_MS=$(date +%s%3N)
else
	_LOG_START_MS=$(perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000' 2>/dev/null || echo 0)
fi

_elapsed_ms() {
	local now
	if command -v python3 >/dev/null 2>&1; then
		now=$(python3 -c 'import time; print(int(time.time()*1000))')
	elif date --version >/dev/null 2>&1; then
		now=$(date +%s%3N)
	else
		now=$(perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000' 2>/dev/null || echo 0)
	fi
	echo $(( now - _LOG_START_MS ))
}

log() {
	local elapsed
	elapsed=$(_elapsed_ms)
	local padded
	padded=$(printf '%5d' "$elapsed")
	local msg="[$(date -u +%Y-%m-%dT%H:%M:%SZ)] [${padded}ms] $*"
	echo "$msg" >&2
	echo "$msg" >>"$LOG_FILE"
}

# --- Shared utilities ---

# Detect if a command line is an agent process.
# Returns tool name ("claude", "codex") or empty.
detect_tool() {
	local args="$1"
	case "$args" in
	claude | claude\ * | */claude | */claude\ *) echo "claude" ;;
	codex | codex\ * | */codex | */codex\ *) echo "codex" ;;
	esac
}

# POSIX-safe single-quote escaping.
posix_quote() {
	local val="$1"
	val="${val//\'/\'\"\'\"\'}"
	printf "'%s'" "$val"
}

# Check if a pane has a running agent anywhere in its process tree.
pane_has_agent() {
	local shell_pid="$1"
	local snapshot="${2:-$(ps -eo pid=,ppid=,args= 2>/dev/null)}"

	local pane_args
	pane_args=$(echo "$snapshot" | awk -v pid="$shell_pid" '$1 == pid {print substr($0, index($0,$3)); exit}')
	if [ -n "$(detect_tool "$pane_args")" ]; then
		echo "$shell_pid"
		return 0
	fi

	local found_pid
	found_pid=$(echo "$snapshot" | awk -v root="$shell_pid" '
		BEGIN { pids[root]=1 }
		{ if ($2 in pids) { pids[$1]=1; print $1, substr($0, index($0,$3)) } }
	' | while read -r cpid cargs; do
		if [ -n "$(detect_tool "$cargs")" ]; then
			echo "$cpid"
			break
		fi
	done)

	if [ -n "$found_pid" ]; then
		echo "$found_pid"
		return 0
	fi

	return 1
}
