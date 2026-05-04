#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmux set-option -g @resurrect-hook-post-save-all "bash '${CURRENT_DIR}/scripts/save.sh'"
tmux set-option -g @resurrect-hook-post-restore-all "bash '${CURRENT_DIR}/scripts/restore.sh'"
