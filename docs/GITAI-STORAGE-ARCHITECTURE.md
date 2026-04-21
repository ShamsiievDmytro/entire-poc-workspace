# Git AI Storage Architecture — Layer-by-Layer

**Date:** 2026-04-21
**Git AI CLI:** 1.3.2
**Inspected from:** entire-poc-backend repo with 29 attributed commits

---

## Overview

Git AI stores data in **four distinct layers**, from transient working state to permanent portable attribution:

```
┌──────────────────────────────────────────────────────┐
│              LAYER 4: REMOTE (GitHub/GitLab)          │
│  refs/notes/ai  →  same Git objects, pushed          │
│  refs/notes/ai-remote/origin  →  tracking ref        │
└──────────────────────┬───────────────────────────────┘
                       │ git push origin refs/notes/*
┌──────────────────────┴───────────────────────────────┐
│              LAYER 3: GIT OBJECTS (per repo)          │
│  refs/notes/ai  →  commit → tree → blobs (notes)     │
│  Fan-out: tree/ab/cdef1234...  →  note blob           │
└──────────────────────┬───────────────────────────────┘
                       │ git commit (condensed from layer 2)
┌──────────────────────┴───────────────────────────────┐
│              LAYER 2: REPO LOCAL (.git/ai/)           │
│  working_logs/  →  checkpoints.jsonl per commit       │
│  bash_snapshots/ → pre/post edit snapshots            │
│  rewrite_log  →  squash/rebase tracking               │
└──────────────────────┬───────────────────────────────┘
                       │ populated by Claude Code hooks
┌──────────────────────┴───────────────────────────────┐
│              LAYER 1: GLOBAL (~/.git-ai/)             │
│  internal/db  →  prompts, cas_sync_queue              │
│  internal/metrics-db  →  telemetry events             │
│  config.json  →  user settings                        │
│  bin/git-ai  →  CLI binary (13.5 MB)                  │
│  skills/  →  /ask, git-ai-search, prompt-analysis     │
└──────────────────────────────────────────────────────┘
```

---

## Layer 1: Global State (`~/.git-ai/`)

Machine-wide installation. Shared across all repos.

### Directory structure

```
~/.git-ai/
├── bin/
│   ├── git-ai              # CLI binary (13.5 MB, Rust)
│   ├── git          → git-ai  # Symlink: wraps git so hooks fire
│   └── git-og      → /opt/homebrew/bin/git  # Original git
├── config.json              # User settings
├── internal/
│   ├── db                   # Main SQLite (prompts, CAS sync)
│   ├── db-shm / db-wal     # WAL mode files
│   ├── metrics-db           # Telemetry SQLite
│   ├── metrics-db-shm/wal
│   ├── credentials          # Auth tokens (if logged in)
│   ├── distinct_id          # Anonymous user ID
│   ├── update_check         # Last update check timestamp
│   ├── async-checkpoint-blobs/  # Pending async uploads
│   └── daemon/              # Background process state
├── skills/                  # Claude Code skills (symlinked to ~/.claude/skills/)
│   ├── ask/                 # /ask skill — query past prompts
│   ├── git-ai-search/      # Search git history with AI context
│   └── prompt-analysis/    # Analyze prompting patterns
├── libexec → /opt/homebrew/opt/git/libexec  # Git internals
└── tmp/                     # Scratch space
```

### Key insight: `git` wrapper

Git AI installs itself as a `git` wrapper. `~/.git-ai/bin/git` is a symlink to `git-ai`, which intercepts git commands, runs its own logic, then delegates to the real git (`git-og`). This is how Git AI attaches notes on `git commit` without needing per-repo hooks.

### Main database (`internal/db`)

**Size:** 1.7 MB + 4.4 MB WAL = ~6 MB total

| Table | Rows | Purpose |
|-------|------|---------|
| `prompts` | 20 | Local prompt/session records |
| `cas_cache` | 0 | Content-addressable storage cache |
| `cas_sync_queue` | 0 | Queue for uploading prompts to usegitai.com (empty when `prompt_storage=local`) |
| `schema_metadata` | 1 | DB version tracking |

**`prompts` table schema:**

```sql
CREATE TABLE prompts (
    id TEXT PRIMARY KEY NOT NULL,          -- prompt ID (same as in Git Notes)
    workdir TEXT,                           -- absolute path to repo
    tool TEXT NOT NULL,                     -- 'claude', 'cursor', etc.
    model TEXT NOT NULL,                    -- 'claude-opus-4-6', etc.
    external_thread_id TEXT NOT NULL,       -- Claude session UUID
    messages TEXT NOT NULL,                 -- full prompt/response transcript (JSON)
    commit_sha TEXT,                        -- commit this prompt contributed to
    agent_metadata TEXT,                    -- JSON: transcript_path
    human_author TEXT,                      -- 'Dmytro Shamsiiev'
    total_additions INTEGER,
    total_deletions INTEGER,
    accepted_lines INTEGER,
    overridden_lines INTEGER,
    created_at INTEGER NOT NULL,           -- unix timestamp
    updated_at INTEGER NOT NULL
);
```

**Sample data:**

| id | workdir | tool | model | session | msg_bytes | created |
|----|---------|------|-------|---------|-----------|---------|
| `1612649c4bf0b88e` | `.../entire-poc-workspace` | claude | claude-opus-4-6 | `9b4e6eb7-...` | 192,382 | 2026-04-21 11:35 |
| `6584ecc0b5c4444c` | `.../entire-poc-workspace` | claude | claude-opus-4-6 | `50fdee9d-...` | 29,279 | 2026-04-21 10:12 |
| `8607c5c2c9598434` | `.../entire-poc-backend` | claude | claude-opus-4-7 | `cc77db23-...` | 1,097 | 2026-04-21 09:00 |

**Key observations:**
- `messages` stores the FULL prompt/response transcript locally (192 KB for a long session)
- `workdir` shows where the agent was launched from (the workspace), not which repos were edited
- Multiple models can appear (`claude-opus-4-6`, `claude-opus-4-7`)
- When `prompt_storage=local`, the `cas_sync_queue` stays empty — nothing uploaded

### Metrics database (`internal/metrics-db`)

**Size:** 4 KB + 791 KB WAL = ~795 KB

| Table | Rows | Purpose |
|-------|------|---------|
| `metrics` | 42 | Telemetry events (anonymized) |
| `agent_usage_throttle` | 26 | Rate-limiting per prompt ID |
| `schema_metadata` | 1 | DB version |

Telemetry events are encoded JSON with obfuscated field names (`"e":2`, `"a":{"20":"claude"}`). These track CLI usage, not code content.

### config.json

```json
{
  "git_path": "/opt/homebrew/bin/git",
  "api_base_url": "https://usegitai.com",
  "prompt_storage": "local"
}
```

---

## Layer 2: Repo-Local State (`.git/ai/`)

Per-repo directory inside `.git/`. Not committed. Not pushed. Contains the working state that gets condensed into Git Notes on each commit.

### Directory structure

```
.git/ai/
├── working_logs/
│   ├── old-<commit_sha>/         # One dir per historical commit
│   │   ├── .archived_at          # Timestamp of archival
│   │   ├── blobs/                # File content snapshots
│   │   └── checkpoints.jsonl     # The checkpoint records
│   └── old-initial/              # Baseline from repo init
├── bash_snapshots/               # Pre/post snapshots from Bash tool calls
│   └── <session_id>_<tool_use_id>.json
├── rewrite_log                   # Tracks squash/rebase/amend operations
└── logs/                         # (empty in our case)
```

### `checkpoints.jsonl` — the core working data

This is the richest data layer. Each line is a JSON record tracking one "checkpoint" — a snapshot of what the agent edited between tool calls. This file is **condensed** into the Git Note when the commit happens, then archived to `old-<sha>/`.

**Sample checkpoint record (formatted for readability):**

```json
{
  "kind": "AiAgent",
  "diff": "d636aacc...",
  "author": "Dmytro Shamsiiev",
  "entries": [
    {
      "file": "src/api/routes/status.ts",
      "blob_sha": "4a59cf86...",
      "attributions": [
        { "start": 0,    "end": 1134, "author_id": "human",            "ts": 1776771990152 },
        { "start": 1134, "end": 1157, "author_id": "1612649c4bf0b88e", "ts": 1776771990153 },
        { "start": 1157, "end": 1191, "author_id": "human",            "ts": 1776771990152 }
      ],
      "line_attributions": [
        { "start_line": 32, "end_line": 32, "author_id": "1612649c4bf0b88e", "overrode": null }
      ]
    }
  ],
  "timestamp": 1776771990,
  "transcript": {
    "messages": [
      { "type": "user", "text": "...", "timestamp": "2026-04-21T11:35:12.288Z" },
      { "type": "assistant", "text": "...", "timestamp": "2026-04-21T11:35:16.476Z" },
      { "type": "tool_use", "name": "Edit", "input": {...}, "timestamp": "..." }
    ]
  },
  "agent_id": {
    "tool": "claude",
    "id": "9b4e6eb7-f49a-48c2-b519-1842319d6fe1",
    "model": "claude-opus-4-6"
  },
  "agent_metadata": {
    "transcript_path": "~/.claude/projects/.../9b4e6eb7-....jsonl"
  },
  "line_stats": { "additions": 1, "deletions": 0, "additions_sloc": 1, "deletions_sloc": 0 },
  "api_version": "checkpoint/1.0.0",
  "git_ai_version": "1.3.2"
}
```

**What's in the checkpoint but NOT in the Git Note:**
- Full conversation transcript (user prompt + assistant responses + tool calls)
- Byte-level attributions (`start`/`end` byte offsets within the file)
- Blob SHAs of the file content at checkpoint time
- Timestamps per attribution event
- SLOC vs raw line counts
- `agent_metadata.transcript_path` — path to the Claude Code session JSONL

**What survives into the Git Note:**
- File paths + line ranges (condensed from byte ranges)
- Agent ID (tool, session, model)
- Human author
- Line counts (additions, deletions, accepted, overridden)
- Prompt ID linking back to the local prompts DB

### `bash_snapshots/` — pre/post edit state

Captures the working tree state before and after Bash tool calls. Used to distinguish agent edits from human edits and from commands that generate files.

```json
{
  "entries": {},
  "invocation_key": "<session_id>:<tool_use_id>",
  "repo_root": "/Users/.../entire-poc-backend",
  "effective_worktree_wm": 1776759646902615000,
  "per_file_wm": {},
  "inflight_agent_context": {
    "session_id": "88b279c9-...",
    "tool_use_id": "toolu_01HHV...",
    "agent_id": { "tool": "claude", "id": "...", "model": "claude-sonnet-4-6" },
    "agent_metadata": { "transcript_path": "..." }
  }
}
```

### `rewrite_log` — history rewrite tracking

One JSON line per event. Git AI uses this to rewrite notes when commits are squashed, rebased, or amended.

```
{"commit":{"base_commit":"486d711...","commit_sha":"fc9a230..."}}
{"merge_squash":{"source_branch":"22596b2...","source_head":"22596b2...","base_branch":"main","base_head":"f796221..."}}
{"reset":{"kind":"mixed","keep":false,"merge":false,"new_head_sha":"6ec25dd...","old_head_sha":"0000..."}}
```

Event types observed:
- `commit` — normal commit (base → new SHA)
- `merge_squash` — squash merge (tracks source and target)
- `reset` — git reset (tracks old/new HEAD)

---

## Layer 3: Git Objects (`refs/notes/ai`)

This is the **permanent, portable** layer. Stored as standard Git objects. Survives clone, push, fetch.

### How notes are stored in Git's object model

```
refs/notes/ai
  → commit (a5180b2)
      author: git-ai <git-ai@local>
      → tree (578aeb0)
          ├── 08/  (tree)
          │   └── 71c3d921a23406d33cf13c3febf462587a6cfc  (blob = note for 0871c3d...)
          ├── 10/  (tree)
          │   └── dddee8d61a62a599599c8ca096fe3be9c11cc2  (blob)
          ├── 4e/  (tree)
          │   └── 027dc3ff77efe497fdb9f91ded8c1322e6800c  (blob)
          ...
```

**Fan-out structure:** Git uses a 2-character prefix directory (like `08/`) containing entries named by the remaining 38 characters of the commit SHA. This is the standard Git Notes fan-out for performance with many notes.

**Blob content:** Each blob IS the note text — the file map + JSON metadata block that `git notes --ref=ai show <sha>` displays.

### Refs present on the remote

| Ref | Purpose |
|-----|---------|
| `refs/notes/ai` | Primary attribution data (the notes themselves) |
| `refs/notes/ai-remote/origin` | Tracks what was last pushed (Git AI internal bookkeeping) |

### What GitHub/GitLab sees

The remote receives standard Git objects. GitHub's API exposes them via:
- `GET /repos/{owner}/{repo}/git/refs/notes%2Fai` → the ref
- `GET /repos/{owner}/{repo}/git/trees/{sha}?recursive=true` → the fan-out tree
- `GET /repos/{owner}/{repo}/git/blobs/{sha}` → individual note content (base64)

No special GitHub features required — this is pure Git.

---

## Layer 4: Remote (GitHub/GitLab)

After `git push origin refs/notes/*`, the remote has an identical copy of Layer 3. The note content is available via:

1. **Git API** — fetch the tree, walk blobs (what our ingestion pipeline does)
2. **Git CLI** — `git fetch origin refs/notes/ai:refs/notes/ai` then `git notes --ref=ai show <sha>`
3. **GitHub web UI** — notes don't render in the commit view (GitHub limitation), but the data is there

---

## Data Lifecycle: From Edit to Dashboard

```
1. EDIT        Agent calls Write/Edit tool
                 ↓
2. HOOK        PreToolUse/PostToolUse fires
               git-ai checkpoint claude --hook-input stdin
                 ↓
3. CHECKPOINT  .git/ai/working_logs/checkpoints.jsonl updated
               - byte-level attribution recorded
               - full transcript captured
               - blob snapshot stored
                 ↓
4. COMMIT      git commit triggers condensation
               - checkpoints → Git Note (line-level, structured JSON)
               - working_logs archived to old-<sha>/
               - local prompts DB updated
               - rewrite_log entry appended
                 ↓
5. PUSH        git push (with notes refspec)
               - refs/notes/ai → remote
               - Code and attribution travel together
                 ↓
6. INGEST      Backend fetches notes via GitHub API
               - Walks refs/notes/ai tree
               - Fetches each blob
               - Parses authorship/3.0.0 format
               - Upserts to gitai_commit_attribution
                 ↓
7. DISPLAY     Frontend queries /api/gitai/* endpoints
               - Charts, tables, comparison views
```

---

## Storage Sizes

| Layer | Location | Size (this PoC) | Grows with |
|-------|----------|-----------------|------------|
| Layer 1: Global DB | `~/.git-ai/internal/db` | ~6 MB | Number of sessions (prompts table) |
| Layer 1: Metrics DB | `~/.git-ai/internal/metrics-db` | ~800 KB | CLI usage events |
| Layer 2: Working logs | `.git/ai/working_logs/` | ~2 MB per repo | Number of commits (archived dirs) |
| Layer 3: Git Notes | `.git/refs/notes/ai` | ~500 bytes per note | Number of attributed commits |
| Layer 4: Remote | GitHub/GitLab | Same as Layer 3 | Same as Layer 3 |

**Production estimate (60 repos, 1 year):**
- Layer 1: ~50 MB (one DB, grows with prompts)
- Layer 2: ~120 MB total across all repos (2 MB/repo)
- Layer 3: ~350 KB per repo, ~21 MB total
- Layer 4: Same as Layer 3

Storage is not a concern at any scale.

---

## Privacy & Security Considerations

| Layer | Contains PII/Sensitive? | Mitigation |
|-------|------------------------|------------|
| Layer 1 (`prompts.messages`) | **YES** — full prompt/response text | Set `prompt_storage: local`; don't back up `~/.git-ai/internal/` to shared storage |
| Layer 2 (`checkpoints.jsonl`) | **YES** — full conversation transcript | Lives in `.git/` (not committed); cleared on `git gc` or manual cleanup |
| Layer 3 (Git Notes) | **No PII** — only file paths, line ranges, agent/model IDs | Safe to push. No code content, no prompts. |
| Layer 4 (Remote) | Same as Layer 3 | Safe. Attribution metadata only. |

**The privacy boundary is clean:** Layers 3-4 (what gets shared) contain zero prompt text, zero code content, and zero user data beyond the git committer name (which is already in the commit). Layers 1-2 (what stays local) contain the sensitive data.
