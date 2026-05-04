
echo "=== restore handles cwd with special chars ==="

tmux new-session -d -s test-special -c /tmp
if ! wait_for_pane_ready test-special; then
	fail "pane never became ready"
fi

test_pane=$(tmux list-panes -t test-special -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

mkdir -p "/tmp/project's dir"

cat >"$TEST_DATA_DIR/agent-sessions.json" <<SPECIAL
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "claude", "session_id": "ses_special", "cwd": "/tmp/project's dir", "pid": "99999", "cli_args": ""}
  ]
}
SPECIAL

rm -f "$RESTORE_LOG"
restore_exit=0
run_restore 2>&1 || restore_exit=$?
sleep 3

assert_eq "Restore doesn't crash on special chars" "0" "$restore_exit"
restore_log=$(cat "$RESTORE_LOG")
assert_contains "Restore attempted with special cwd" "$restore_log" "ses_special"

kill_pane_children test-special true
