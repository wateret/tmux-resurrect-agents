
echo "=== save detects claude with session file ==="

tmux new-session -d -s test-claude -c /tmp
if ! wait_for_pane_ready test-claude; then
	fail "test-claude pane never became ready"
	dump_pane_diagnostics test-claude
fi
tmux send-keys -t test-claude "echo PATH=\$PATH; command -v claude; command claude --resume ses_detect_test" Enter

claude_pid=$(get_pane_agent_pid claude test-claude 15) || {
	echo "WARN: claude process not found"
	dump_pane_diagnostics test-claude
}

if [ -n "$claude_pid" ]; then
	cat >"$MOCK_SESSIONS_DIR/${claude_pid}.json" <<SEOF
{"pid":${claude_pid},"sessionId":"ses_detect_test","cwd":"/tmp/test-project","kind":"interactive","entrypoint":"cli","status":"idle"}
SEOF
fi

rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

SAVED="$TEST_DATA_DIR/agent-sessions.json"
detect_count=$(jq '.sessions | length' "$SAVED")
if [ "$detect_count" -ge 1 ]; then
	pass "Detected at least 1 claude session"
else
	fail "Expected at least 1 session, got $detect_count"
fi

detect_sid=$(jq -r '.sessions[] | select(.pane | contains("test-claude")) | .session_id' "$SAVED")
assert_eq "Correct session ID" "ses_detect_test" "$detect_sid"

detect_cwd=$(jq -r '.sessions[] | select(.pane | contains("test-claude")) | .cwd' "$SAVED")
assert_eq "Correct cwd from session file" "/tmp/test-project" "$detect_cwd"

kill_pane_children test-claude true
