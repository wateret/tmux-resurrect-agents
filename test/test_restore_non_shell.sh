
echo "=== restore skips non-shell panes ==="

tmux new-session -d -s test-noshell -c /tmp
if ! wait_for_pane_ready test-noshell; then
	fail "pane never became ready"
fi

test_pane=$(tmux list-panes -t test-noshell -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

tmux send-keys -t test-noshell "sleep 9999" Enter
sleep 1

cat >"$TEST_DATA_DIR/agent-sessions.json" <<NOSHELL
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "claude", "session_id": "ses_noshell", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
NOSHELL

rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 3

restore_log=$(cat "$RESTORE_LOG")
assert_contains "Skips non-shell pane" "$restore_log" "not a shell"

kill_pane_children test-noshell true
