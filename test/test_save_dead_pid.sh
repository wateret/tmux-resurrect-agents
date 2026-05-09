
echo "=== stale session file with dead PID ==="

cat >"$MOCK_SESSIONS_DIR/99999.json" <<'EOF'
{"pid":99999,"sessionId":"ses_dead","cwd":"/tmp","kind":"interactive","entrypoint":"cli","status":"idle"}
EOF

rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

SAVED="$TEST_DATA_DIR/agent-sessions.json"
dead_count=$(jq '[.sessions[] | select(.session_id == "ses_dead")] | length' "$SAVED")
assert_eq "Dead PID not saved (process tree won't find it)" "0" "$dead_count"
