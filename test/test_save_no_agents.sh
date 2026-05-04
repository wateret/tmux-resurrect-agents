
echo "=== save with no agents running ==="

tmux new-session -d -s test-empty -c /tmp
sleep 1

rm -f "$TEST_DATA_DIR/agent-sessions.json"
run_save 2>&1

SAVED="$TEST_DATA_DIR/agent-sessions.json"
assert_file_exists "agent-sessions.json created" "$SAVED"
empty_count=$(jq '.sessions | length' "$SAVED")
assert_eq "no agents → empty sessions" "0" "$empty_count"

tmux kill-session -t test-empty 2>/dev/null || true
