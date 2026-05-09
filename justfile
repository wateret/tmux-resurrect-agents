# tmux-resurrect-agents — dev tasks

plugin_dir := justfile_directory()

# Show available recipes
default:
    @just --list

# Register resurrect hooks in the current tmux server
install:
    @bash '{{plugin_dir}}/tmux-resurrect-agents.tmux'
    @echo "Hooks registered. tmux-resurrect will now save/restore Claude sessions."

# Remove resurrect hooks from the current tmux server
uninstall:
    @tmux set-option -gu @resurrect-hook-post-save-all 2>/dev/null || true
    @tmux set-option -gu @resurrect-hook-post-restore-all 2>/dev/null || true
    @echo "Hooks removed."

# Show current hook registration status
status:
    @echo "Post-save hook:"
    @tmux show-option -gqv @resurrect-hook-post-save-all 2>/dev/null || echo "  (not set)"
    @echo "Post-restore hook:"
    @tmux show-option -gqv @resurrect-hook-post-restore-all 2>/dev/null || echo "  (not set)"
    @echo ""
    @echo "Last saved sessions:"
    @bash -c 'source "{{plugin_dir}}/scripts/lib.sh"; f="$DATA_DIR/agent-sessions.json"; \
        if [ -f "$f" ]; then \
            jq ".sessions | length" "$f" | xargs -I{} echo "  {} session(s)"; \
            jq -r ".sessions[] | \"  \\(.pane) — \\(.tool) (\\(.session_id))\"" "$f"; \
        else \
            echo "  (no saved sessions)"; \
        fi'

# Run save hook manually
save:
    @bash '{{plugin_dir}}/scripts/save.sh'

# Run restore hook manually
restore:
    @bash '{{plugin_dir}}/scripts/restore.sh'

# Restart all agent processes (save -> kill -> restore) - useful to pick up config changes
restart:
    @bash '{{plugin_dir}}/scripts/restart.sh'

# Run tests in Docker (optional filter: just test restore)
test filter='':
    docker build -t tmux-resurrect-agents-test -f '{{plugin_dir}}/test/Dockerfile' '{{plugin_dir}}'
    docker run --rm -e TEST_FILTER='{{filter}}' tmux-resurrect-agents-test
