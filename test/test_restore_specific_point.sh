
echo "=== restore reads the sidecar paired with the snapshot 'last' points to ==="

tmux new-session -d -s test-point -c /tmp
if ! wait_for_pane_ready test-point; then
	fail "pane never became ready"
fi

test_pane=$(tmux list-panes -t test-point -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

# Two snapshots, each with its own agent sidecar.
old_sidecar=$(setup_resurrect_save 20260101T000000)
cat >"$old_sidecar" <<OLD
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "claude", "session_id": "ses_point_old", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
OLD

new_sidecar=$(setup_resurrect_save 20260201T000000)
cat >"$new_sidecar" <<NEW
{
  "timestamp": "2026-02-01T00:00:00Z",
  "sessions": [
    {"pane": "${test_pane}", "tool": "claude", "session_id": "ses_point_new", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
NEW

# Restore a specific (older) point: re-point "last" to the old snapshot, as a
# user would when rolling back to an earlier resurrect save. The agent sidecar
# must follow "last" — not default to the newest one.
ln -sf "tmux_resurrect_20260101T000000.txt" "$TEST_DATA_DIR/last"

rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 3

restore_log=$(cat "$RESTORE_LOG")
assert_contains "Restores agents from the snapshot 'last' points to" "$restore_log" "ses_point_old"
if echo "$restore_log" | grep -q "ses_point_new"; then
	fail "Pulled agents from the wrong (newer) snapshot"
else
	pass "Ignored the newer snapshot's sidecar"
fi

kill_pane_children test-point true
