# tmux-resurrect-agents

Save and restore sessions across tmux-resurrect save/restore cycles.

Does not modify your agent configuration - detection is read-only, based on existing runtime state.

## Supported Agents

- Claude Code
- Codex

## Install

**Via [TPM](https://github.com/tmux-plugins/tpm):**

Add to `tmux.conf`:

```tmux
set -g @plugin 'wateret/tmux-resurrect-agents'
```

Then press `prefix + I` to install.

**Manual:**

```bash
git clone https://github.com/wateret/tmux-resurrect-agents ~/.config/tmux/plugins/tmux-resurrect-agents
```

Add to `tmux.conf`:

```tmux
run-shell ~/.config/tmux/plugins/tmux-resurrect-agents/tmux-resurrect-agents.tmux
```

## Requirements

- [tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect)
- `python3`
- `jq`

## How it works

Hooks into tmux-resurrect's `post-save-all` and `post-restore-all` events:

1. **Save** — walks the process tree under each tmux pane, finds running agent processes, resolves session IDs from existing runtime state (session files, SQLite DBs, process args). Writes a sidecar JSON alongside resurrect's save files.
2. **Restore** — reads the sidecar JSON and sends the appropriate resume command (`claude --resume` / `codex resume`) into the correct panes.

## Restarting agents (without restarting tmux sessions)

Saves sessions, kills the agent processes, and resumes them in-place — without restarting tmux sessions. Convenient for applying CLI app updates or `CLAUDE.md` / config changes.

```bash
~/.config/tmux/plugins/tmux-resurrect-agents/scripts/restart.sh
```

## Disclaimer

Session detection relies on undocumented internal state of Claude Code and
Codex CLI. These formats may change without notice, which can cause detection
to fail or produce incorrect session mappings — panes may be skipped or
restored with the wrong session.

Restored sessions may not be 100% identical to the original. Only a subset
of CLI flags are replayed on resume; others (e.g. `--model`, `--worktree`)
are intentionally dropped. The conversation history is preserved, but
session-level options not in the allowlist will revert to defaults.

## Dev tasks (requires [just](https://github.com/casey/just))

```bash
just install    # register hooks in current tmux server
just uninstall  # remove hooks
just status     # show hook status and saved sessions
just save       # run save manually
just restore    # run restore manually
just restart    # save → kill → restore (picks up config changes)
just test       # run full test suite
just test unit  # run only tests matching "unit"
```
