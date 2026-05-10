
echo "=== extract_cli_args() ==="

# Allowlisted flags are kept; --model, --resume, and other one-time flags are dropped
assert_eq "keep allowed, drop --model and --resume" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude --dangerously-skip-permissions --model opus --resume ses_abc123" claude)"
assert_eq "strip --resume= (equals form)" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude --dangerously-skip-permissions --resume=ses_abc123" claude)"
assert_eq "full path stripped" "--dangerously-skip-permissions" \
	"$(extract_cli_args "/usr/local/bin/claude --dangerously-skip-permissions --resume ses_abc" claude)"
assert_eq "no allowed flags" "" \
	"$(extract_cli_args "claude --resume ses_abc" claude)"
assert_eq "bare binary" "" \
	"$(extract_cli_args "claude" claude)"
assert_eq "multiple spaces normalized" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude  --dangerously-skip-permissions  --model  opus  --resume  ses_abc" claude)"
assert_eq "node.js double-binary stripped" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude /usr/local/bin/claude --dangerously-skip-permissions --resume ses_abc" claude)"

# One-time session flags are dropped
assert_eq "drop --worktree" "" \
	"$(extract_cli_args "claude --worktree --resume ses_abc" claude)"
assert_eq "drop --worktree, keep allowed" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude --dangerously-skip-permissions --worktree --resume ses_abc" claude)"
assert_eq "drop -w short form" "" \
	"$(extract_cli_args "claude -w --resume ses_abc" claude)"
assert_eq "drop -w, keep allowed" "--dangerously-skip-permissions" \
	"$(extract_cli_args "claude --dangerously-skip-permissions -w --resume ses_abc" claude)"
assert_eq "drop --continue / -c" "" \
	"$(extract_cli_args "claude -c" claude)"
assert_eq "drop --print / -p" "" \
	"$(extract_cli_args "claude -p some prompt" claude)"

# Allowlisted flags
assert_eq "keep --permission-mode with value" "--permission-mode bypassPermissions" \
	"$(extract_cli_args "claude --permission-mode bypassPermissions --resume ses_abc" claude)"
assert_eq "keep --allowedTools multi-value" "--allowedTools Bash Edit Read" \
	"$(extract_cli_args "claude --allowedTools Bash Edit Read --resume ses_abc" claude)"
assert_eq "keep --add-dir multi-value" "--add-dir /path/one /path/two" \
	"$(extract_cli_args "claude --add-dir /path/one /path/two --resume ses_abc" claude)"
assert_eq "keep --mcp-config" "--mcp-config /path/to/config.json" \
	"$(extract_cli_args "claude --mcp-config /path/to/config.json --resume ses_abc" claude)"
assert_eq "keep --bare" "--bare" \
	"$(extract_cli_args "claude --bare --resume ses_abc" claude)"
assert_eq "keep multiple allowed flags" "--dangerously-skip-permissions --permission-mode bypassPermissions" \
	"$(extract_cli_args "claude --dangerously-skip-permissions --permission-mode bypassPermissions --model opus --resume ses_abc" claude)"

# Codex-specific
assert_eq "codex: strip resume subcommand" "--model o3" \
	"$(extract_cli_args "codex --model o3 resume abc-123-def" codex)"
assert_eq "codex: bare resume" "" \
	"$(extract_cli_args "codex resume abc-123-def" codex)"
assert_eq "codex: full path" "--full-auto" \
	"$(extract_cli_args "/usr/local/bin/codex --full-auto resume abc-123" codex)"
assert_eq "codex: node.js double-binary" "--full-auto" \
	"$(extract_cli_args "codex /usr/local/bin/codex --full-auto resume abc-123" codex)"
