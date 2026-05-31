
echo "=== stale session file with dead PID ==="

cat >"$MOCK_SESSIONS_DIR/99999.json" <<'EOF'
{"pid":99999,"sessionId":"ses_dead","cwd":"/tmp","kind":"interactive","entrypoint":"cli","status":"idle"}
EOF

SAVED=$(setup_resurrect_save)
run_save 2>&1

dead_count=$(jq '[.sessions[] | select(.session_id == "ses_dead")] | length' "$SAVED")
assert_eq "Dead PID not saved (process tree won't find it)" "0" "$dead_count"
