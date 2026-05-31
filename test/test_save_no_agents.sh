
echo "=== save with no agents running ==="

tmux new-session -d -s test-empty -c /tmp
sleep 1

SAVED=$(setup_resurrect_save)
run_save 2>&1

assert_file_exists "sidecar created" "$SAVED"
empty_count=$(jq '.sessions | length' "$SAVED")
assert_eq "no agents → empty sessions" "0" "$empty_count"

tmux kill-session -t test-empty 2>/dev/null || true
