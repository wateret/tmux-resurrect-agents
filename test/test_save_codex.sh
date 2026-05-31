
echo "=== save detects codex with resume arg ==="

tmux new-session -d -s test-codex -c /tmp
if ! wait_for_pane_ready test-codex; then
	fail "test-codex pane never became ready"
	dump_pane_diagnostics test-codex
fi
tmux send-keys -t test-codex "command codex resume 019dc39b-fc7a-7f22-8923-9e2b217f602c" Enter

codex_pid=$(get_pane_agent_pid codex test-codex 15) || {
	echo "WARN: codex process not found"
	dump_pane_diagnostics test-codex
}

if [ -n "$codex_pid" ]; then
	SAVED=$(setup_resurrect_save)
	run_save 2>&1

	codex_count=$(jq '[.sessions[] | select(.pane | contains("test-codex"))] | length' "$SAVED")
	if [ "$codex_count" -ge 1 ]; then
		pass "Detected codex session in pane"
	else
		fail "Expected codex session, got $codex_count"
	fi

	codex_sid=$(jq -r '.sessions[] | select(.pane | contains("test-codex")) | .session_id' "$SAVED")
	assert_eq "Correct codex session ID from args" "019dc39b-fc7a-7f22-8923-9e2b217f602c" "$codex_sid"

	codex_tool=$(jq -r '.sessions[] | select(.pane | contains("test-codex")) | .tool' "$SAVED")
	assert_eq "Tool field is codex" "codex" "$codex_tool"
else
	fail "Could not find codex process in pane (skipping save assertions)"
fi

kill_pane_children test-codex true
