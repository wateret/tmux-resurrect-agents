
echo "=== full save/restore cycle across tmux server restart ==="

CLAUDE_BIN="$(command -v claude)"
CLAUDE_BIN_DIR="$(dirname "$CLAUDE_BIN")"

# 1. Create two panes: one with claude, one with codex
tmux new-session -d -s test-cycle -c /tmp -x 200 -y 50
tmux split-window -t test-cycle -c /tmp
sleep 0.5

cycle_claude_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)
cycle_codex_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | tail -1)

if ! wait_for_pane_ready "$cycle_claude_pane"; then
	fail "test-cycle claude pane never became ready"
fi
if ! wait_for_pane_ready "$cycle_codex_pane"; then
	fail "test-cycle codex pane never became ready"
fi

tmux send-keys -t "$cycle_claude_pane" "command claude --resume ses_full_cycle" Enter
tmux send-keys -t "$cycle_codex_pane" "command codex resume 019dc39b-full-cycle-codex" Enter

cycle_claude_pid=$(get_pane_agent_pid claude "$cycle_claude_pane" 15) || true
cycle_codex_pid=$(get_pane_agent_pid codex "$cycle_codex_pane" 15) || true

if [ -n "$cycle_claude_pid" ]; then
	cat >"$MOCK_SESSIONS_DIR/${cycle_claude_pid}.json" <<CEOF
{"pid":${cycle_claude_pid},"sessionId":"ses_full_cycle","cwd":"/tmp/cycle-project","kind":"interactive","entrypoint":"cli","status":"idle"}
CEOF
fi

# 2. Save both sessions
rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

SAVED="$TEST_DATA_DIR/agent-sessions.json"
cycle_claude_saved=$(jq '[.sessions[] | select(.session_id == "ses_full_cycle")] | length' "$SAVED")
cycle_codex_saved=$(jq '[.sessions[] | select(.session_id == "019dc39b-full-cycle-codex")] | length' "$SAVED")

if [ "$cycle_claude_saved" -ge 1 ]; then
	pass "Full cycle: save captured claude session"
else
	fail "Full cycle: save did not capture claude session"
fi
if [ "$cycle_codex_saved" -ge 1 ]; then
	pass "Full cycle: save captured codex session"
else
	fail "Full cycle: save did not capture codex session"
fi

# 3. Kill the tmux server entirely (simulates system restart)
tmux kill-server 2>/dev/null || true
sleep 1

# 4. Start a fresh tmux server with same layout (two panes)
tmux new-session -d -s test-cycle -c /tmp -x 200 -y 50
tmux split-window -t test-cycle -c /tmp
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"
sleep 1

new_claude_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)
new_codex_pane=$(tmux list-panes -t test-cycle -F "#{session_name}:#{window_index}.#{pane_index}" | tail -1)

if ! wait_for_pane_ready "$new_claude_pane"; then
	fail "test-cycle claude pane not ready after restart"
fi
if ! wait_for_pane_ready "$new_codex_pane"; then
	fail "test-cycle codex pane not ready after restart"
fi

# 5. Run restore
rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 5

assert_file_exists "Full cycle: restore log exists" "$RESTORE_LOG"
cycle_log=$(cat "$RESTORE_LOG")

assert_contains "Full cycle: claude resume sent" "$cycle_log" "ses_full_cycle"
assert_contains "Full cycle: claude tool correct" "$cycle_log" "restoring claude"
assert_contains "Full cycle: codex resume sent" "$cycle_log" "019dc39b-full-cycle-codex"
assert_contains "Full cycle: codex tool correct" "$cycle_log" "restoring codex"

# 6. Verify both processes are running
cycle_restored_claude=$(get_pane_agent_pid claude "$new_claude_pane" 10) || true
cycle_restored_codex=$(get_pane_agent_pid codex "$new_codex_pane" 10) || true

if [ -n "$cycle_restored_claude" ]; then
	pass "Full cycle: claude running after restore"
else
	fail "Full cycle: claude not found after restore"
fi
if [ -n "$cycle_restored_codex" ]; then
	pass "Full cycle: codex running after restore"
else
	fail "Full cycle: codex not found after restore"
fi

kill_pane_children test-cycle true

# Restore tmux server state for any subsequent tests
tmux new-session -d -s _init -x 200 -y 50
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"

echo "=== worktree session: restore strips -w flag ==="

# 1. Create pane and start claude with -w (simulates a session launched inside a worktree)
worktree_cwd="/tmp/worktree-test-project"
mkdir -p "$worktree_cwd"

tmux new-session -d -s test-worktree -c "$worktree_cwd" -x 200 -y 50
sleep 0.5

wt_pane=$(tmux list-panes -t test-worktree -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

if ! wait_for_pane_ready "$wt_pane"; then
	fail "worktree: pane never became ready"
fi

tmux send-keys -t "$wt_pane" "command claude -w --resume ses_wt_cycle" Enter

# 2. Wait for process to appear and create mock session file
wt_pid=$(get_pane_agent_pid claude "$wt_pane" 15) || true

if [ -n "$wt_pid" ]; then
	cat >"$MOCK_SESSIONS_DIR/${wt_pid}.json" <<WTEOF
{"pid":${wt_pid},"sessionId":"ses_wt_cycle","cwd":"${worktree_cwd}","kind":"interactive","entrypoint":"cli","status":"idle"}
WTEOF
fi

# 3. Save — verify session captured and -w stripped from cli_args
rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

wt_saved=$(jq '[.sessions[] | select(.session_id == "ses_wt_cycle")] | length' "$TEST_DATA_DIR/agent-sessions.json")
if [ "$wt_saved" -ge 1 ]; then
	pass "Worktree: save captured session"
else
	fail "Worktree: save did not capture session"
fi

wt_cli_args=$(jq -r '[.sessions[] | select(.session_id == "ses_wt_cycle")] | .[0].cli_args // ""' "$TEST_DATA_DIR/agent-sessions.json")
if echo "$wt_cli_args" | grep -qE '(^| )(-w|--worktree)( |$)'; then
	fail "Worktree: -w/--worktree was not stripped from saved cli_args (got: '$wt_cli_args')"
else
	pass "Worktree: -w stripped from saved cli_args"
fi

# 4. Kill tmux server, restart with fresh pane (simulates system restart)
tmux kill-server 2>/dev/null || true
sleep 1

tmux new-session -d -s test-worktree -c "$worktree_cwd" -x 200 -y 50
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"
sleep 1

new_wt_pane=$(tmux list-panes -t test-worktree -F "#{session_name}:#{window_index}.#{pane_index}" | head -1)

if ! wait_for_pane_ready "$new_wt_pane"; then
	fail "Worktree: pane not ready after restart"
fi

# 5. Restore
rm -f "$RESTORE_LOG"
run_restore 2>&1
sleep 5

# 6. Verify restore log: command must not include -w/--worktree (quoted or unquoted)
wt_log=$(cat "$RESTORE_LOG")
assert_contains "Worktree: resume attempted" "$wt_log" "ses_wt_cycle"
if echo "$wt_log" | grep -qE "cmd:.*[ '](-w|--worktree)[' ]"; then
	fail "Worktree: restore command includes -w/--worktree"
else
	pass "Worktree: restore command does not include -w/--worktree"
fi

# 7. Verify claude is STILL running after 5s (single snapshot — not a start-up poll).
# If -w was replayed, claude exits immediately with "No conversation found"; it would be gone by now.
wt_pane_pid=$(tmux display-message -t "$new_wt_pane" -p '#{pane_pid}' 2>/dev/null || true)
wt_restored=$(ps -eo pid=,ppid=,args= | awk -v root="$wt_pane_pid" \
	'$2 == root && /claude/ {print $1; exit}' || true)
if [ -n "$wt_restored" ]; then
	pass "Worktree: claude still running after restore"
else
	fail "Worktree: claude not running after restore"
fi

kill_pane_children test-worktree true

# Restore tmux server state for subsequent tests
tmux new-session -d -s _init -x 200 -y 50
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"
