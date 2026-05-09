#!/usr/bin/env bash
# Restart all running AI agent processes in-place.
# Saves their session state, kills the processes (not the panes), and resumes them.
# Use case: pick up new CLAUDE.md / config without losing tmux layout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

LOG_FILE="${DATA_DIR}/agent-restart.log"

if [ -f "$LOG_FILE" ]; then
	tail -n 500 "$LOG_FILE" >"${LOG_FILE}.tmp" 2>/dev/null && mv "${LOG_FILE}.tmp" "$LOG_FILE" || true
fi

# --- Main ---

log "restart: saving current agent sessions..."
bash "$SCRIPT_DIR/save.sh"

INPUT_FILE="${DATA_DIR}/agent-sessions.json"
cp "$INPUT_FILE" "${INPUT_FILE}.bak" 2>/dev/null || true

if [ ! -f "$INPUT_FILE" ]; then
	log "restart: no saved sessions found, nothing to restart"
	exit 0
fi

sessions=$(jq -r '.sessions // []' "$INPUT_FILE")
count=$(echo "$sessions" | jq 'length')

if [ "$count" -eq 0 ]; then
	log "restart: no agent sessions to restart"
	exit 0
fi

log "restart: killing $count agent process(es)..."

# Extract just pids from saved sessions
pids=$(echo "$sessions" | jq -r '.[].pid // empty')

# Send SIGTERM to all at once
killed=0
for pid in $pids; do
	[ -z "$pid" ] && continue
	if kill -0 "$pid" 2>/dev/null; then
		kill "$pid" 2>/dev/null || true
		killed=$((killed + 1))
	fi
done

log "restart: sent SIGTERM to $killed process(es), waiting for exit..."

# Wait for all to exit (up to 30s)
for _ in $(seq 1 60); do
	all_dead=true
	for pid in $pids; do
		[ -z "$pid" ] && continue
		if kill -0 "$pid" 2>/dev/null; then
			all_dead=false
			break
		fi
	done
	$all_dead && break
	sleep 0.5
done

# Force-kill any survivors
for pid in $pids; do
	[ -z "$pid" ] && continue
	if kill -0 "$pid" 2>/dev/null; then
		kill -9 "$pid" 2>/dev/null || true
		log "restart: force-killed pid $pid"
	fi
done

log "restart: killed $killed process(es), waiting for shells to settle..."
sleep 1

log "restart: restoring agent sessions..."
bash "$SCRIPT_DIR/restore.sh"

log "restart: done"
