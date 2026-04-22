# Git AI — How It Works, What It Captures, and Known Limitations

**Last updated:** 2026-04-22
**Git AI Standard:** authorship/3.0.0 | CLI: 1.3.2
**Validated on:** 91 commits across 3 repos, 1 developer, Claude Code + subagents

---

## 1. How Git AI Attribution Works

### 1.1 The capture mechanism

Git AI doesn't guess who wrote what. It intercepts agent tool calls via hooks and records exactly which lines the agent produced.

```
1. Agent calls Write/Edit tool on a file
2. PreToolUse hook fires → git-ai records file state BEFORE edit
3. Agent writes/edits the file
4. PostToolUse hook fires → git-ai records file state AFTER edit
5. git-ai diffs before/after → knows exactly which bytes changed
6. On git commit → all checkpoint diffs condensed into a Git Note
```

The hooks live in `~/.claude/settings.json` (or equivalent for Cursor/Copilot). They fire on **every tool call** regardless of which repo the file is in — this is why cross-repo workspace sessions work.

### 1.2 What Git AI tracks vs what it doesn't

**Git AI tracks: what the agent wrote.**
Every line that flows through an agent's Write/Edit/MultiEdit tool call is checkpointed with byte-level precision.

**Git AI does NOT track: what the human wrote.**
If you open a file in your editor and type code, no hook fires. Git AI has no visibility into manual edits. These lines simply don't appear in the attribution.

**The implication:** Git AI answers the question "which lines did AI write?" The complement — "which lines did the human write?" — is derived by subtraction:

```
human_lines = total_lines_in_git_diff - agent_attributed_lines
```

We get `total_lines_in_git_diff` from `git diff --numstat`. This is a reliable ground truth for what changed in the commit.

### 1.3 The three categories

Git AI's own `git ai stats` command classifies every line in a commit's diff into exactly one of three categories:

| Category | Meaning | How determined |
|----------|---------|----------------|
| **ai_additions** | Lines the agent wrote via tool calls | From checkpoint data (file map) |
| **unknown_additions** | Lines in the diff not claimed by any agent | Absence from file map |
| **human_additions** | Always 0 in practice | Git AI has no human tracking mechanism |

Our dashboard labels `unknown_additions` as **"Human"** because in practice, unattributed lines were either typed by the human or are agent-written lines that fell outside the checkpoint range (see Known Limitations below).

---

## 2. The Git Note Format

Every commit with agent involvement gets a Git Note in `refs/notes/ai`. The note has two sections separated by `---`.

### 2.1 File Map (above `---`) — RELIABLE, per-commit

```
src/api/routes/status.ts
  1612649c4bf0b88e 6,11,15,19,21,27-32,35,37,43
src/utils/format.ts
  1612649c4bf0b88e 3,6,9-16
```

This is the **ground truth for attribution**. Each line lists:
- File path (relative to repo root)
- Prompt ID + line numbers the agent wrote

Line ranges use commas and dashes: `6,11,15` = individual lines; `27-32` = range; `9-16` = lines 9 through 16.

### 2.2 JSON Metadata (below `---`) — SESSION-SCOPED, use with caution

```json
{
  "schema_version": "authorship/3.0.0",
  "prompts": {
    "1612649c4bf0b88e": {
      "agent_id": { "tool": "claude", "model": "claude-opus-4-6" },
      "human_author": "Dmytro Shamsiiev",
      "total_additions": 174,
      "accepted_lines": 110,
      "overriden_lines": 0
    }
  }
}
```

**Critical finding from testing:** The numeric fields in the JSON metadata (`total_additions`, `accepted_lines`, `overriden_lines`) are **session-scoped, not commit-scoped**. A single prompt ID spans an entire agent session, which may touch multiple files across multiple repos. These numbers accumulate across the session.

| JSON Field | Per-commit? | Reliable for metrics? |
|-----------|-------------|----------------------|
| `agent_id.tool` | Yes | **Yes** — correct per commit |
| `agent_id.model` | Yes | **Yes** — correct per commit |
| `human_author` | Yes | **Yes** — but prefer git commit Author (has email) |
| `total_additions` | **No** — session-wide | **No** — may be 174 when commit added 88 lines |
| `accepted_lines` | **No** — session-wide | **No** — same issue |
| `overriden_lines` | **No** — session-wide | **No** — can't use for per-commit override rate |
| `messages` | Always `[]` with `prompt_storage: local` | N/A |

### 2.3 What we actually use for metrics

| Metric | Source | How |
|--------|--------|-----|
| Agent-attributed lines | **File map** line ranges | Count lines from ranges |
| Total lines changed | `git diff --numstat` | Per-commit ground truth |
| Human/unattributed lines | `diff_additions - agent_lines` | Derived |
| Agent tool | **JSON** `agent_id.tool` | Reliable per commit |
| Model | **JSON** `agent_id.model` | Reliable per commit |
| Commit author | `git log --format=%aN <%aE>` | From git, not from note |
| Commit date | `git log --format=%aI` | From git |

---

## 3. Known Limitations

### 3.1 Incomplete line range coverage

**Symptom:** An agent creates a file with 88 lines. The file map attributes lines 7-78 (72 lines). The remaining 16 lines are classified as "human" even though the agent wrote them.

**Cause:** Git AI's checkpoint mechanism sometimes doesn't cover the first and last few lines of a file, particularly when:
- The file was created via a single `Write` tool call (the initial lines and trailing lines fall outside the checkpoint boundary)
- The file has leading headers, blank lines at the top, or trailing content

**Impact:** Agent attribution is **conservative** — it may undercount by 5-15% on file-creation commits. For edits to existing files, coverage is more precise because the pre/post diff is tighter.

**Our approach:** Accept the undercount. The file map is still the best source of truth. The alternative (trusting `accepted_lines` from JSON metadata) would overcount because those numbers are session-scoped.

### 3.2 Blank lines within attributed ranges ARE counted

**Tested and confirmed:** Git AI includes blank lines that fall within an attributed range. If the agent wrote lines 1-18 and some of those are blank, all 18 are counted as AI-attributed. Blank lines are only "missed" when they fall outside the attributed range (see 3.1).

### 3.3 JSON metadata is session-scoped

**Symptom:** A commit's note shows `total_additions: 174` but the commit's actual diff only has 88 additions.

**Cause:** The `prompt_id` in the note spans the entire agent session. If the session edited files in 3 repos and produced 3 commits, the `total_additions` in each note reflects the cumulative session total, not the individual commit.

**Impact:** The following JSON fields are unreliable for per-commit metrics:
- `total_additions` / `total_deletions`
- `accepted_lines`
- `overriden_lines`

**Our approach:** Ignore these fields for metrics. Use the file map (lines) + `git diff --numstat` (totals) instead.

### 3.4 Human-only commits have empty notes

**Tested:** When a commit is made entirely by hand (no agent involvement), Git AI still creates a note, but with an empty file map and `"prompts": {}`.

```
---
{
  "schema_version": "authorship/3.0.0",
  "prompts": {}
}
```

Our ingestion correctly handles this: `agent_lines = 0`, `human_lines = diff_additions`.

### 3.5 Merge commits have no notes

GitHub/GitLab merge commits created server-side never have Git AI notes (no agent was involved). Our ingestion correctly skips these — it only processes commits listed by `git notes --ref=ai list`.

**Squash merges via GitHub/GitLab web UI** are problematic: the original commits (with notes) are discarded, and the new squash commit has no note. Use fast-forward or regular merge to preserve attribution.

### 3.6 Notes pushed separately from code

`git push` does not push notes by default. Developers must configure:

```bash
git config --add remote.origin.push 'refs/heads/*:refs/heads/*'
git config --add remote.origin.push 'refs/notes/*:refs/notes/*'
```

If a developer forgets, their commits arrive without notes. The commits will show as 100% human on the dashboard.

---

## 4. Data Pipeline

### 4.1 Ingestion flow

```
Every 5 minutes (configurable):

1. For each repo:
   a. git fetch origin refs/notes/*:refs/notes/*    ← pull other devs' notes
   b. git fetch origin                               ← pull latest commits
   c. git notes --ref=ai list                        ← all commit SHAs with notes
   d. Filter: skip commits already in DB (watermark + SHA check)
   e. For each NEW commit:
      - git notes --ref=ai show <sha>                ← note content
      - git diff --numstat <sha>^..<sha>             ← actual lines changed
      - git log -1 --format=%aI%n%aN <%aE>%n%s <sha> ← date, author, message
      - Parse file map → count agent lines
      - human_lines = diff_additions - agent_lines
      - Upsert to database

2. Dashboard reads from database with time-range filters
```

### 4.2 Incremental ingestion

The ingestion is incremental:
- Uses `MAX(captured_at)` per repo as a watermark (indexed column, O(1) lookup)
- Only processes commits newer than the watermark
- Falls back to SHA check for edge cases (same-second commits)
- A full re-ingestion from empty DB takes seconds (all data is in git notes)

### 4.3 Database is a derived cache

The SQLite database can be deleted and rebuilt at any time. Git notes are the permanent source of truth — they live in the repo's git history and travel with push/fetch. The database is just a queryable cache for the dashboard.

---

## 5. Database Schema

```sql
CREATE TABLE gitai_commit_attribution (
  repo TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  agent TEXT NOT NULL,              -- 'claude', 'cursor', 'copilot'
  model TEXT,                        -- 'claude-opus-4-6', 'gpt-4'
  agent_lines INTEGER NOT NULL,      -- from file map line ranges
  human_lines INTEGER NOT NULL,      -- diff_additions - agent_lines
  agent_percentage REAL NOT NULL,    -- agent_lines / diff_additions * 100
  prompt_id TEXT,                    -- session-level prompt identifier
  commit_author TEXT,                -- 'Name <email>' from git log
  commit_message TEXT,               -- commit subject line
  diff_additions INTEGER DEFAULT 0,  -- from git diff --numstat
  diff_deletions INTEGER DEFAULT 0,  -- from git diff --numstat
  files_touched_json TEXT,           -- [{file, lineRanges, lineCount}]
  raw_note_json TEXT,                -- full note for auditability
  captured_at TIMESTAMP,             -- commit date
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (repo, commit_sha, agent)
);
```

**Primary key includes `agent`** because a single commit could have contributions from multiple agents (e.g., developer used Cursor then Claude before committing).

---

## 6. Dashboard Charts

The current dashboard shows 10 charts, all powered by Git AI data:

### Overview (headline metrics)

| Chart | Type | What it shows |
|-------|------|--------------|
| Avg Agent Attribution | Stat card | Overall AI contribution % across all commits |
| Pure-AI Commit Rate | Stat card | % of commits that are 100% AI-authored |
| First-Time-Right Rate | Stat card | % of commits where agent code was accepted without modification |
| Agent % Over Time | Line chart | Smoothed (3-commit rolling avg) AI contribution trend |

### Breakdown (who/what/where)

| Chart | Type | What it shows |
|-------|------|--------------|
| Attribution Breakdown | Stacked bar | AI vs human lines per commit |
| AI Usage by Developer | Horizontal bar | Avg AI % per developer (by commit author email) |
| Model Distribution | Doughnut | Commit count by LLM model |
| Files by Layer | Stacked bar | AI/human lines by architectural layer (components, routes, utils, tests, docs, etc.) |

### Patterns (tempo + quality)

| Chart | Type | What it shows |
|-------|------|--------------|
| Human Edit Rate | Bar | Human edit % per commit (inverse of AI %) |
| Commit Cadence | Bar | Hours between consecutive commits |

### Commit Detail

Clicking any commit in the `/commits` list opens a detail page showing:
- Summary header (SHA, repo, agent, model, stat cards)
- File attribution map (per-file line ranges with progress bars)
- Raw Git Note (file map + JSON, split and formatted)
- Local prompt metadata (from `~/.git-ai/internal/db`, if available)
- Transcript download button

---

## 7. Metrics That CANNOT Be Built from Git AI Alone

| Metric | Why not | Alternative |
|--------|---------|------------|
| Token usage per session | Git AI doesn't track API calls | Agent-specific APIs or billing data |
| Session duration | No start/end timestamps | Approximate from first/last commit in a prompt_id group |
| Friction / blockers | Not in scope | Manual tracking or Entire IO |
| Tool call patterns | Not tracked | Agent transcript analysis |
| Override rate (per commit) | `overriden_lines` is session-scoped | Would need Git AI to fix this upstream |
| Prompt quality analysis | Requires prompt text | Enable `prompt_storage: notes` (sends to usegitai.com) |
