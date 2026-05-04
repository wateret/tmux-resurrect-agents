
echo "=== restore sends correct codex resume command ==="

tmux new-session -d -s test-restore-codex -c /tmp
if ! wait_for_pane_ready test-restore-codex; then
	fail "pane never became ready"
fi

test_pane=$(tmux list-panes -t test-restore-codex -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

cat >"$TEST_DATA_DIR/agent-sessions.json" <<REOF
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "codex", "session_id": "019dc39b-fc7a-7f22-8923-9e2b217f602c", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
REOF

rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 3

restore_log=$(cat "$RESTORE_LOG")
assert_contains "Restore mentions codex" "$restore_log" "restoring codex"
assert_contains "Restore uses 'command codex resume'" "$restore_log" "command codex resume"
assert_contains "Restore has codex session ID" "$restore_log" "019dc39b-fc7a-7f22-8923-9e2b217f602c"

kill_pane_children test-restore-codex true
