
echo "=== full save/restore cycle across tmux server restart ==="

CLAUDE_BIN="$(command -v claude)"
CLAUDE_BIN_DIR="$(dirname "$CLAUDE_BIN")"

# 1. Create two panes: one with claude, one with codex
tmux new-session -d -s test-cycle -c /tmp -x 200 -y 50
tmux split-window -t test-cycle -c /tmp
sleep 0.5

cycle_claude_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)
cycle_codex_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | tail -1)

if ! wait_for_pane_ready "$cycle_claude_pane"; then
	fail "test-cycle claude pane never became ready"
fi
if ! wait_for_pane_ready "$cycle_codex_pane"; then
	fail "test-cycle codex pane never became ready"
fi

tmux send-keys -t "$cycle_claude_pane" "command claude --resume ses_full_cycle" Enter
tmux send-keys -t "$cycle_codex_pane" "command codex resume 019dc39b-full-cycle-codex" Enter

cycle_claude_pid=$(get_pane_agent_pid claude "$cycle_claude_pane" 15) || true
cycle_codex_pid=$(get_pane_agent_pid codex "$cycle_codex_pane" 15) || true

if [ -n "$cycle_claude_pid" ]; then
	cat >"$MOCK_SESSIONS_DIR/${cycle_claude_pid}.json" <<CEOF
{"pid":${cycle_claude_pid},"sessionId":"ses_full_cycle","cwd":"/tmp/cycle-project","kind":"interactive","entrypoint":"cli","status":"idle"}
CEOF
fi

# 2. Save both sessions
rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

SAVED="$TEST_DATA_DIR/agent-sessions.json"
cycle_claude_saved=$(jq '[.sessions[] | select(.session_id == "ses_full_cycle")] | length' "$SAVED")
cycle_codex_saved=$(jq '[.sessions[] | select(.session_id == "019dc39b-full-cycle-codex")] | length' "$SAVED")

if [ "$cycle_claude_saved" -ge 1 ]; then
	pass "Full cycle: save captured claude session"
else
	fail "Full cycle: save did not capture claude session"
fi
if [ "$cycle_codex_saved" -ge 1 ]; then
	pass "Full cycle: save captured codex session"
else
	fail "Full cycle: save did not capture codex session"
fi

# 3. Kill the tmux server entirely (simulates system restart)
tmux kill-server 2>/dev/null || true
sleep 1

# 4. Start a fresh tmux server with same layout (two panes)
tmux new-session -d -s test-cycle -c /tmp -x 200 -y 50
tmux split-window -t test-cycle -c /tmp
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"
sleep 1

new_claude_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)
new_codex_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | tail -1)

if ! wait_for_pane_ready "$new_claude_pane"; then
	fail "test-cycle claude pane not ready after restart"
fi
if ! wait_for_pane_ready "$new_codex_pane"; then
	fail "test-cycle codex pane not ready after restart"
fi

# 5. Run restore
rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 5

assert_file_exists "Full cycle: restore log exists" "$RESTORE_LOG"
cycle_log=$(cat "$RESTORE_LOG")

assert_contains "Full cycle: claude resume sent" "$cycle_log" "ses_full_cycle"
assert_contains "Full cycle: claude tool correct" "$cycle_log" "restoring claude"
assert_contains "Full cycle: codex resume sent" "$cycle_log" "019dc39b-full-cycle-codex"
assert_contains "Full cycle: codex tool correct" "$cycle_log" "restoring codex"

# 6. Verify both processes are running
cycle_restored_claude=$(get_pane_agent_pid claude "$new_claude_pane" 10) || true
cycle_restored_codex=$(get_pane_agent_pid codex "$new_codex_pane" 10) || true

if [ -n "$cycle_restored_claude" ]; then
	pass "Full cycle: claude running after restore"
else
	fail "Full cycle: claude not found after restore"
fi
if [ -n "$cycle_restored_codex" ]; then
	pass "Full cycle: codex running after restore"
else
	fail "Full cycle: codex not found after restore"
fi

kill_pane_children test-cycle true

# Restore tmux server state for any subsequent tests
tmux new-session -d -s _init -x 200 -y 50
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"
