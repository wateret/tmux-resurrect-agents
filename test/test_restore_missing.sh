
echo "=== restore skips missing pane gracefully ==="

SIDECAR=$(setup_resurrect_save)
cat >"$SIDECAR" <<'MISSING'
{
  "timestamp": "2026-01-01T00:00:00Z",
  "sessions": [
    {"pane": "nonexistent-session:0.0", "tool": "claude", "session_id": "ses_missing", "cwd": "/tmp", "pid": "99999", "cli_args": ""}
  ]
}
MISSING

rm -f "$RESTORE_LOG"
restore_exit=0
run_restore 2>&1 || restore_exit=$?
sleep 2

assert_eq "Restore doesn't crash on missing pane" "0" "$restore_exit"
restore_log=$(cat "$RESTORE_LOG")
assert_contains "Logs missing session" "$restore_log" "does not exist"
