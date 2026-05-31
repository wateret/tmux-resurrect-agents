#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use post-save-all (not post-save-layout, which receives the file path as an
# arg) for two reasons: (1) it runs unconditionally and *after* resurrect's
# duplicate-save dedup, so the "last" symlink is authoritative and the agent
# sidecar is refreshed every cycle even when the layout is unchanged but the
# agent sessions are not; (2) restore has no path-passing hook anyway, so both
# sides resolve the paired file from "last" (see agent_sessions_file in lib.sh).
tmux set-option -g @resurrect-hook-post-save-all "bash '${CURRENT_DIR}/scripts/save.sh'"
tmux set-option -g @resurrect-hook-post-restore-all "bash '${CURRENT_DIR}/scripts/restore.sh'"
