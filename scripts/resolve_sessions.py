#!/usr/bin/env python3
"""Batch resolve agent session IDs for tmux-resurrect-agents.

Reads candidate lines from the CANDIDATES env var (TSV: target, tool, pid, args, cwd).
Outputs resolved results as TSV: target, tool, pid, session_id, session_cwd, args.

Supports Claude Code and Codex CLI.
"""
import glob, json, os, re, sqlite3, subprocess, sys, time


# --- Claude ---

def get_claude_session(pid, args, claude_sessions_dir):
    # Only match user-launched CLI sessions (entrypoint=="cli", kind=="interactive").
    # Subagents use entrypoint "sdk-cli" and are excluded.
    session_file = os.path.join(claude_sessions_dir, f"{pid}.json")
    if os.path.isfile(session_file):
        try:
            with open(session_file) as f:
                data = json.load(f)
            if data.get("entrypoint") == "cli" and data.get("kind") == "interactive":
                sid = data.get("sessionId", "")
                if sid:
                    return sid, data.get("cwd", "")
            elif data.get("entrypoint") or data.get("kind"):
                return None, None
        except Exception:
            pass
    # Fallback: --resume in args
    m = re.search(r'--resume[= ] *([A-Za-z0-9_-]+)', args)
    if m:
        return m.group(1), ""
    return None, None


# --- Codex ---

def _get_child_pids(pid):
    try:
        result = subprocess.run(["ps", "-o", "pid=", "--ppid", pid],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return [p.strip() for p in result.stdout.decode().split() if p.strip()]
    except Exception:
        return []


def _get_etimes(pid):
    try:
        r = subprocess.run(["ps", "-o", "etimes=", "-p", pid],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        return r.stdout.decode().strip()
    except Exception:
        return ""


def get_codex_session(pid, args, cwd, logs_db, logs_min_id, state_db, used_codex_sids):
    # Method 1: logs DB PID lookup (+ child PIDs)
    if logs_db:
        pids_to_try = [pid] + _get_child_pids(pid)
        cur = logs_db.cursor()
        for p in pids_to_try:
            cur.execute(
                "SELECT thread_id FROM logs "
                "WHERE id > ? AND process_uuid LIKE ? AND thread_id IS NOT NULL "
                "ORDER BY id DESC LIMIT 1",
                (logs_min_id, f"pid:{p}:%"),
            )
            row = cur.fetchone()
            if row and row[0]:
                return row[0]

    # Method 2: state DB cwd match
    if state_db and cwd:
        etimes_raw = _get_etimes(pid)
        process_start = None
        if etimes_raw.isdigit():
            process_start = time.time() - int(etimes_raw)

        cur = state_db.cursor()
        cur.execute(
            "SELECT id, updated_at FROM threads "
            "WHERE cwd = ? AND archived = 0 ORDER BY updated_at DESC",
            (cwd,),
        )
        rows = cur.fetchall()
        for require_after in (True, False):
            for sid, updated_at in rows:
                if sid in used_codex_sids:
                    continue
                if require_after and process_start is not None and updated_at < process_start:
                    continue
                return sid

    # Method 3: resume arg in process args
    m = re.search(r'resume\s+([A-Za-z0-9_-]+)', args)
    if m and not m.group(1).startswith("--"):
        return m.group(1)

    return None


# --- Main ---

def main():
    claude_sessions_dir = sys.argv[1]
    codex_home = sys.argv[2]

    # Open codex DBs once
    logs_db = None
    logs_min_id = 0
    logs_dbs = sorted(glob.glob(os.path.join(codex_home, "logs_*.sqlite")),
                      key=os.path.getmtime, reverse=True)
    if logs_dbs:
        try:
            logs_db = sqlite3.connect(f"file:{logs_dbs[0]}?mode=ro", uri=True)
            _max = logs_db.execute("SELECT MAX(id) FROM logs").fetchone()[0] or 0
            # Limit scan to most recent 200k rows via PK index to avoid full table scan
            logs_min_id = max(0, _max - 200000)
        except Exception:
            logs_db = None

    state_db = None
    state_dbs = sorted(glob.glob(os.path.join(codex_home, "state_*.sqlite")),
                       key=os.path.getmtime, reverse=True)
    if state_dbs:
        try:
            state_db = sqlite3.connect(f"file:{state_dbs[0]}?mode=ro", uri=True)
        except Exception:
            state_db = None

    used_codex_sids = set()

    # Process candidates
    for line in os.environ.get("CANDIDATES", "").splitlines():
        if not line:
            continue
        parts = line.split("\t", 4)
        if len(parts) < 5:
            continue
        target, tool, pid, args, cwd = parts

        session_id = ""
        session_cwd = ""
        if tool == "claude":
            result = get_claude_session(pid, args, claude_sessions_dir)
            if result[0]:
                session_id = result[0]
                session_cwd = result[1] or ""
        elif tool == "codex":
            sid = get_codex_session(pid, args, cwd, logs_db, logs_min_id, state_db, used_codex_sids)
            if sid:
                session_id = sid
                used_codex_sids.add(sid)

        # Use "-" for empty fields to prevent bash read from collapsing consecutive tabs
        print(f"{target}\t{tool}\t{pid}\t{session_id or '-'}\t{session_cwd or '-'}\t{args}")

    if logs_db:
        logs_db.close()
    if state_db:
        state_db.close()


if __name__ == "__main__":
    main()
