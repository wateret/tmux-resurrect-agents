
echo "=== extract_cli_args() ==="

assert_eq "strip --resume" "--dangerously-skip-permissions --model opus" \
	"$(extract_cli_args "claude --dangerously-skip-permissions --model opus --resume ses_abc123" claude)"
assert_eq "strip --resume= (equals)" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude --dangerously-skip-permissions --resume=ses_abc123" claude)"
assert_eq "full path stripped" "--dangerously-skip-permissions" \
	"$(extract_cli_args "/usr/local/bin/claude --dangerously-skip-permissions --resume ses_abc" claude)"
assert_eq "no extra flags" "" \
	"$(extract_cli_args "claude --resume ses_abc" claude)"
assert_eq "bare binary" "" \
	"$(extract_cli_args "claude" claude)"
assert_eq "multiple spaces normalized" "--dangerously-skip-permissions --model opus" \
	"$(extract_cli_args "claude  --dangerously-skip-permissions  --model  opus  --resume  ses_abc" claude)"
assert_eq "node.js double-binary stripped" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude /usr/local/bin/claude --dangerously-skip-permissions --resume ses_abc" claude)"

# Codex-specific
assert_eq "codex: strip resume subcommand" "--model o3" \
	"$(extract_cli_args "codex --model o3 resume abc-123-def" codex)"
assert_eq "codex: bare resume" "" \
	"$(extract_cli_args "codex resume abc-123-def" codex)"
assert_eq "codex: full path" "--full-auto" \
	"$(extract_cli_args "/usr/local/bin/codex --full-auto resume abc-123" codex)"
assert_eq "codex: node.js double-binary" "--full-auto" \
	"$(extract_cli_args "codex /usr/local/bin/codex --full-auto resume abc-123" codex)"
