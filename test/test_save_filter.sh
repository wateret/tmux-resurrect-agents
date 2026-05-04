
echo "=== save filters non-interactive sessions ==="

tmux new-session -d -s test-task -c /tmp
if ! wait_for_pane_ready test-task; then
	fail "test-task pane never became ready"
	dump_pane_diagnostics test-task
fi
tmux send-keys -t test-task "command claude" Enter

task_claude_pid=$(get_pane_agent_pid claude test-task 15) || {
	echo "WARN: claude process not found in test-task"
	dump_pane_diagnostics test-task
}

if [ -n "$task_claude_pid" ]; then
	cat >"$MOCK_SESSIONS_DIR/${task_claude_pid}.json" <<TEOF
{"pid":${task_claude_pid},"sessionId":"ses_task_skip","cwd":"/tmp","kind":"task","status":"running"}
TEOF
fi

rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

SAVED="$TEST_DATA_DIR/agent-sessions.json"
task_count=$(jq '[.sessions[] | select(.pane | contains("test-task"))] | length' "$SAVED")
assert_eq "Non-interactive session filtered out" "0" "$task_count"

kill_pane_children test-task true
