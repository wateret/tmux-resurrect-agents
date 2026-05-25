#!/usr/bin/env bash
# Test runner — discovers test_*.sh files, runs them, aggregates results.
# Usage: run-tests.sh [filter]
#   filter: substring match on test filename (e.g. "unit", "restore", "full_cycle")
set -euo pipefail

if [ ! -f /.dockerenv ]; then
    echo "ERROR: tests must run inside Docker. Use: just test" >&2
    exit 1
fi

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="${TEST_FILTER:-${1:-}}"

source "$TEST_DIR/lib.sh"

# tmux server setup (needed for integration tests)
CLAUDE_BIN="$(command -v claude)"
CLAUDE_BIN_DIR="$(dirname "$CLAUDE_BIN")"
echo "Test harness bash: $BASH_VERSION"
echo "Scripts runner: $SCRIPT_RUNNER"
echo "Pane default shell: $PANE_SHELL"
echo "claude binary: $CLAUDE_BIN"
[ -n "$FILTER" ] && echo "Filter: $FILTER"
echo ""

tmux new-session -d -s _init -x 200 -y 50
tmux set-option -g default-shell "$(command -v "$PANE_SHELL")"
tmux set-environment -g PATH "${CLAUDE_BIN_DIR}:/usr/local/bin:/usr/bin:/bin:$PATH"

# Run each test file
TOTAL_PASS=0
TOTAL_FAIL=0
ALL_ERRORS=""

for test_file in "$TEST_DIR"/test_*.sh; do
	[ -f "$test_file" ] || continue
	name="$(basename "$test_file" .sh)"

	# Apply filter
	if [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]]; then
		continue
	fi

	echo ""
	# Run in same shell (not subshell) so tmux state persists between tests
	PASS=0
	FAIL=0
	ERRORS=""
	source "$test_file"
	TOTAL_PASS=$((TOTAL_PASS + PASS))
	TOTAL_FAIL=$((TOTAL_FAIL + FAIL))
	ALL_ERRORS="${ALL_ERRORS}${ERRORS}"
done

# Summary
echo ""
echo "=========================================="
echo "  Results: $TOTAL_PASS passed, $TOTAL_FAIL failed"
echo "=========================================="

if [ "$TOTAL_FAIL" -gt 0 ]; then
	echo -e "\nFailures:$ALL_ERRORS"
	echo ""
	exit 1
fi

echo ""
exit 0
