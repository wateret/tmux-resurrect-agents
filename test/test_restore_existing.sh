
echo "=== restore skips pane with existing agent ==="

tmux new-session -d -s test-existing -c /tmp
if ! wait_for_pane_ready test-existing; then
	fail "pane never became ready"
fi

test_pane=$(tmux list-panes -t test-existing -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

tmux send-keys -t test-existing "claude --resume ses_existing &" Enter
sleep 2

cat >"$TEST_DATA_DIR/agent-sessions.json" <<EXISTING
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "claude", "session_id": "ses_should_skip", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
EXISTING

rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 3

restore_log=$(cat "$RESTORE_LOG")
if echo "$restore_log" | grep -q "already has a running agent"; then
	pass "Guard 2: skips pane with background agent"
elif echo "$restore_log" | grep -q "not a shell"; then
	pass "Guard 1: skips pane (agent is foreground — acceptable)"
else
	fail "Neither guard fired for pane with existing agent"
fi

kill_pane_children test-existing true
