
echo "=== restore sends correct claude resume command ==="

tmux new-session -d -s test-restore-claude -c /tmp
if ! wait_for_pane_ready test-restore-claude; then
	fail "pane never became ready"
fi

test_pane=$(tmux list-panes -t test-restore-claude -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

cat >"$TEST_DATA_DIR/agent-sessions.json" <<REOF
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "claude", "session_id": "ses_restore_test", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
REOF

rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 3

assert_file_exists "Restore log created" "$RESTORE_LOG"
restore_log=$(cat "$RESTORE_LOG")
assert_contains "Restore mentions claude" "$restore_log" "restoring claude"
assert_contains "Restore has session ID" "$restore_log" "ses_restore_test"
assert_contains "Restore uses 'command claude'" "$restore_log" "command claude"

kill_pane_children test-restore-claude true
