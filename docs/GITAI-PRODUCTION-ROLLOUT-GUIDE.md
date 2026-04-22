# Git AI Production Rollout Guide

**For:** WoD Workspace (~90 repos, multi-developer team)
**Based on:** Validated PoC (3 repos, single developer, Claude Code)
**Git AI Version:** 1.3.2+ | Standard: authorship/3.0.0
**Last updated:** 2026-04-22 Updated

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [What Git AI Captures and How](#2-what-git-ai-captures-and-how)
3. [Installation — Per Developer](#3-installation--per-developer)
4. [New Developer Onboarding Checklist](#4-new-developer-onboarding-checklist)
5. [Git Notes Push Configuration](#5-git-notes-push-configuration)
6. [Multi-Repo Workspace — How It Works](#6-multi-repo-workspace--how-it-works)
7. [Metrics Dashboard — Centralized Ingestion](#7-metrics-dashboard--centralized-ingestion)
8. [GitLab-Specific Considerations](#8-gitlab-specific-considerations)
9. [CI/CD Integration](#9-cicd-integration)
10. [Privacy and Security](#10-privacy-and-security)
11. [Troubleshooting](#11-troubleshooting)
12. [Appendix: Validated PoC Results](#12-appendix-validated-poc-results)

---

## 1. Architecture Overview

```
Developer Machine                          GitLab                    Metrics Server
┌──────────────────────┐                   ┌──────────┐             ┌──────────────┐
│ VS Code Workspace    │                   │          │             │              │
│                      │                   │ repo A   │  git clone  │  Ingestion   │
│  _wod.workspace/     │                   │ repo B   │────────────▶│  Service     │
│  ├── .claude/        │                   │ repo C   │             │              │
│  │   └── settings    │                   │ ...      │             │  reads notes │
│  │       (hooks)     │                   │ repo N   │             │  from local  │
│  │                   │                   │          │             │  git clones  │
│  wod/                │   git push        │ Each repo│             │              │
│  ├── wod.api/     ───┼──────────────────▶│ has      │             │  ┌────────┐  │
│  ├── wod.webApp/  ───┼──────────────────▶│ refs/    │             │  │ SQLite/ │  │
│  ├── wod.employee ───┼──────────────────▶│ notes/ai │             │  │ Postgres│  │
│  auth/               │                   │          │             │  └────────┘  │
│  ├── auth.identity───┼──────────────────▶│          │             │       │      │
│  core/               │                   └──────────┘             │       ▼      │
│  ├── dreamteam.* ────┼──────────────────▶                         │  Dashboard   │
│                      │                                            │  (charts)    │
│  ~/.git-ai/          │                                            │              │
│  ├── bin/git-ai      │                                            └──────────────┘
│  ├── config.json     │
│  ├── internal/db     │  ← local prompts, never leaves machine
│  └── skills/         │
└──────────────────────┘
```

**Key architectural property (validated):** An agent launched from `_wod.workspace/` that edits files in `wod/wod.employeeService/` and `auth/auth.profileService/` in the same session produces correct Git Notes on commits in **both** sibling repos. This works because Git AI hooks fire on every file edit tool call regardless of which repo the file is in.

---

## 2. What Git AI Captures and How

### The capture flow

```
1. Developer launches Claude Code / Cursor / Codex from _wod.workspace/
2. Agent edits a file in wod/wod.employeeService/src/service.ts
   └── PreToolUse hook fires → git-ai checkpoint claude --hook-input stdin
   └── Git AI records: which file, which bytes, which agent, which model
3. Agent edits a file in auth/auth.profileService/src/controller.ts
   └── Same hook fires → checkpoint recorded in auth repo's .git/ai/
4. Developer commits in wod.employeeService
   └── Git AI condenses checkpoints → Git Note attached to commit
5. Developer commits in auth.profileService
   └── Git AI condenses checkpoints → Git Note attached to commit
6. Developer pushes both repos
   └── Code + notes travel together to GitLab
```

### What's in a Git Note (per commit)

```
src/service.ts
  a1b2c3d4e5f6g7h8 15-42,50-67
src/utils/helper.ts
  a1b2c3d4e5f6g7h8 1-12
---
{
  "schema_version": "authorship/3.0.0",
  "git_ai_version": "1.3.2",
  "prompts": {
    "a1b2c3d4e5f6g7h8": {
      "agent_id": {
        "tool": "claude",           ← which agent
        "id": "session-uuid",       ← session identifier
        "model": "claude-opus-4-6"  ← which model
      },
      "human_author": "Jane Doe",
      "total_additions": 57,
      "total_deletions": 3,
      "accepted_lines": 57,         ← lines agent wrote that were kept
      "overriden_lines": 0           ← lines human modified after agent wrote
    }
  }
}
```

### What metrics this enables

| Metric | Source |
|--------|--------|
| % of code written by AI per commit | `agent_lines / total_diff_additions` |
| Which agent wrote what | `agent_id.tool` (claude, cursor, copilot, codex) |
| Which model was used | `agent_id.model` |
| First-time-right rate (AI code accepted without edits) | `overriden_lines == 0` |
| Human edit rate | `100 - agent_percentage` |
| Files touched by architectural layer | File paths classified into layers |
| Cross-repo session tracking | Shared `prompt_id` across repos |
| Per-developer AI adoption | `human_author` field |
| Commit cadence | Timestamp analysis |

---

## 3. Installation — Per Developer

Git AI is a **machine-wide** install. Once installed, it works across every Git repo on that machine — no per-repo setup required.

### 3.1 Install Git AI CLI

```bash
curl -sSL https://usegitai.com/install.sh | bash
```

This installs:
- `~/.git-ai/bin/git-ai` — the CLI binary (13.5 MB)
- `~/.git-ai/bin/git` → symlink to `git-ai` (wraps git to intercept commits)
- `~/.git-ai/skills/` — `/ask`, `git-ai-search`, `prompt-analysis` skills
- `~/.git-ai/config.json` — settings
- `~/.git-ai/internal/db` — local prompts database

### 3.2 Verify installation

```bash
git ai --version          # should print version number
git status                # existing git commands still work
which git                 # should point to ~/.git-ai/bin/git
```

### 3.3 Configure privacy (REQUIRED for enterprise)

```bash
# Keep prompts local — don't upload to usegitai.com
git ai config set prompt_storage local
```

This ensures:
- No `messages_url` field in Git Notes (no external links)
- Prompts stay in local SQLite only (`~/.git-ai/internal/db`)
- Attribution metadata (agent, model, lines) is unaffected

### 3.4 Verify agent hooks are installed

For **Claude Code**, check `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "~/.git-ai/bin/git-ai checkpoint claude --hook-input stdin" }]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "~/.git-ai/bin/git-ai checkpoint claude --hook-input stdin" }]
    }]
  }
}
```

For **Cursor**, **Copilot**, **Codex** — Git AI installs hooks automatically for each supported agent. Verify with:

```bash
git ai install-hooks    # re-run if hooks are missing
```

### 3.5 Restart everything

**Critical:** After installation, restart:
- All terminal sessions
- VS Code
- Any running agent sessions (Claude Code, Cursor, etc.)

The hooks are only picked up on session start. This is the #1 cause of "Git AI isn't working" issues.

---

## 4. New Developer Onboarding Checklist

Print this and hand it to every new developer:

```
□ 1. Install Git AI
     curl -sSL https://usegitai.com/install.sh | bash

□ 2. Set privacy mode
     git ai config set prompt_storage local

□ 3. Verify installation
     git ai --version
     git status    (should work normally)

□ 4. Close and reopen VS Code

□ 5. Close and reopen any terminal/agent sessions

□ 6. Clone the workspace repos (if not already done)
     cd ~/Projects/wod
     git clone git@gitlab.com:yourorg/_wod.workspace.git
     git clone git@gitlab.com:yourorg/wod/wod.wodModule.api.git
     ... (other repos as needed)

□ 7. Configure notes auto-push for each cloned repo
     Run the setup script (see Section 5):
     bash _wod.workspace/scripts/setup-gitai-push.sh

□ 8. Test it works
     - Open VS Code with the workspace
     - Launch Claude Code from _wod.workspace terminal
     - Ask the agent to make a small change in any sibling repo
     - Commit and push
     - Verify: git notes --ref=ai show HEAD
       → should show attribution data

□ 9. Done — every future commit will have attribution automatically
```

---

## 5. Git Notes Push Configuration

By default, `git push` does NOT push notes. Each developer needs to configure their repos to include notes in push operations.

### 5.1 Option A: Per-repo config (recommended for controlled rollout)

For each repo a developer works with:

```bash
cd wod/wod.employeeService
git config --add remote.origin.push 'refs/heads/*:refs/heads/*'
git config --add remote.origin.push 'refs/notes/*:refs/notes/*'
```

### 5.2 Option B: Global config (all repos on this machine)

```bash
git config --global --add remote.origin.push 'refs/heads/*:refs/heads/*'
git config --global --add remote.origin.push 'refs/notes/*:refs/notes/*'
```

**Warning:** This affects every repo on the machine, including personal projects.

### 5.3 Option C: Setup script (recommended for team onboarding)

Create `_wod.workspace/scripts/setup-gitai-push.sh`:

```bash
#!/usr/bin/env bash
# Configure Git AI notes auto-push for all workspace repos.
# Run once after cloning the workspace.
set -euo pipefail

WORKSPACE_ROOT="${1:-$(pwd)/..}"
echo "Configuring Git AI notes push for repos in: $WORKSPACE_ROOT"

configured=0
for repo_dir in "$WORKSPACE_ROOT"/*/ "$WORKSPACE_ROOT"/*/*/; do
  if [ -d "$repo_dir/.git" ]; then
    repo_name=$(basename "$repo_dir")
    
    # Check if already configured
    existing=$(git -C "$repo_dir" config --get-all remote.origin.push 2>/dev/null || true)
    if echo "$existing" | grep -q 'refs/notes'; then
      echo "  ✓ $repo_name (already configured)"
      continue
    fi
    
    git -C "$repo_dir" config --add remote.origin.push 'refs/heads/*:refs/heads/*'
    git -C "$repo_dir" config --add remote.origin.push 'refs/notes/*:refs/notes/*'
    echo "  ✓ $repo_name (configured)"
    configured=$((configured + 1))
  fi
done

echo ""
echo "Done. Configured $configured repos."
echo "Notes will now be pushed automatically with 'git push'."
```

Include this script in the hub repo. New developers run it once after cloning.

### 5.4 Fetching notes from other developers

When pulling repos, notes from other developers don't arrive by default. To fetch them:

```bash
# Per repo
git fetch origin 'refs/notes/*:refs/notes/*'

# Or configure auto-fetch (permanent)
git config --add remote.origin.fetch '+refs/notes/*:refs/notes/*'
```

The metrics dashboard server should have this configured for all repos.

---

## 6. Multi-Repo Workspace — How It Works

### 6.1 The cross-repo session problem (solved)

```
Developer launches Claude Code from _wod.workspace/

Session edits:
  wod/wod.employeeService/src/service.ts     ← repo A
  wod/wod.departmentService/src/handler.ts   ← repo B
  auth/auth.profileService/src/controller.ts ← repo C

Developer commits in each repo:
  repo A: commit abc1234 → Git Note with attribution ✓
  repo B: commit def5678 → Git Note with attribution ✓
  repo C: commit ghi9012 → Git Note with attribution ✓
```

**All three commits share the same `prompt_id`** in their Git Notes. This is how the metrics dashboard can reconstruct the logical session across repos.

### 6.2 Why this works architecturally

Git AI hooks live in `~/.claude/settings.json` (or equivalent for other agents) — they are **global**, not per-repo. When the agent calls Write/Edit on any file, the hook fires and `git-ai checkpoint` determines which repo owns that file by walking up the directory tree to find the `.git` folder. Checkpoints are stored in each repo's `.git/ai/` directory independently.

This means:
- No setup needed in each sibling repo
- No workspace-level coordinator needed
- No "session boundary" detection needed
- Works with any number of repos
- Works regardless of directory structure

### 6.3 Scale: 90 repos in the WoD workspace

For the WoD workspace with ~90 repos:
- Each developer only clones the repos they work with (typically 5-15)
- Git AI only tracks repos where files are actually edited (no overhead for cloned-but-untouched repos)
- Notes are lightweight (~500 bytes each) — negligible storage impact
- No centralized service required on the developer machine

---

## 7. Metrics Dashboard — Centralized Ingestion

### 7.1 Architecture

The metrics dashboard is a separate service that:
1. Has all workspace repos cloned locally (or a subset)
2. Periodically fetches `refs/notes/ai` from each repo
3. Reads notes and commit diffs using local git commands
4. Stores parsed attribution in a database
5. Serves charts via a web dashboard

```
Metrics Server
├── /repos/                          ← All repos cloned here
│   ├── wod.employeeService/
│   ├── wod.departmentService/
│   ├── auth.profileService/
│   └── ...
├── ingestion/
│   ├── git-fetch-all.sh             ← Cron: fetches notes from all repos
│   ├── gitai-fetcher.ts             ← Reads notes via local git CLI
│   ├── gitai-parser.ts              ← Parses authorship/3.0.0 format
│   └── gitai-orchestrator.ts        ← Orchestrates fetch → parse → store
├── database/
│   └── metrics.db (or PostgreSQL)
└── dashboard/
    └── web UI with charts
```

### 7.2 Ingestion flow

```bash
# Step 1: Fetch latest notes from GitLab (cron, every 15 min)
for repo in /repos/*/; do
  git -C "$repo" fetch origin 'refs/notes/*:refs/notes/*' --quiet
  git -C "$repo" pull --quiet
done

# Step 2: Ingestion service reads notes locally
# For each repo:
#   git notes --ref=ai list              → all commit SHAs with notes
#   git notes --ref=ai show <sha>        → note content
#   git diff --numstat <sha>^..<sha>     → actual lines changed
#   git log -1 --format=%aI <sha>        → commit date
```

### 7.3 Data pipeline

```
git notes --ref=ai show <sha>
        │
        ▼
┌─────────────────┐     ┌──────────────────┐     ┌──────────────┐
│ Parse note       │────▶│ Enrich with      │────▶│ Store in DB  │
│ - file map       │     │ git diff stats   │     │ - per commit │
│ - JSON metadata  │     │ - total adds     │     │ - per agent  │
│ - agent/model    │     │ - total deletes  │     │ - per file   │
│ - line ranges    │     │ - commit date    │     │ - per dev    │
└─────────────────┘     └──────────────────┘     └──────────────┘
```

### 7.4 Multi-developer data

When multiple developers push notes to the same repo:
- Each developer's commits have their own notes
- Notes don't conflict (each note is keyed by commit SHA, and developers have different commits)
- The `human_author` field in each note identifies who committed
- The `agent_id.tool` field identifies which agent they used

Example dashboard query:

```sql
SELECT human_author, agent, 
       COUNT(*) AS commits,
       AVG(agent_percentage) AS avg_ai_pct,
       SUM(agent_lines) AS total_ai_lines
FROM gitai_commit_attribution
WHERE captured_at > date('now', '-30 days')
GROUP BY human_author, agent
ORDER BY total_ai_lines DESC;
```

### 7.5 Database schema (production)

```sql
CREATE TABLE gitai_commit_attribution (
  repo TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  agent TEXT NOT NULL,
  model TEXT,
  agent_lines INTEGER NOT NULL,
  human_lines INTEGER NOT NULL,
  agent_percentage REAL NOT NULL,
  prompt_id TEXT,
  human_author TEXT,
  files_touched_json TEXT,
  raw_note_json TEXT,
  diff_additions INTEGER,
  diff_deletions INTEGER,
  captured_at TIMESTAMP,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (repo, commit_sha, agent)
);

CREATE INDEX idx_gitai_repo ON gitai_commit_attribution(repo);
CREATE INDEX idx_gitai_captured_at ON gitai_commit_attribution(captured_at);
CREATE INDEX idx_gitai_author ON gitai_commit_attribution(human_author);
CREATE INDEX idx_gitai_agent ON gitai_commit_attribution(agent);
```

---

## 8. GitLab-Specific Considerations

### 8.1 Git Notes support

GitLab supports Git Notes natively. They are stored as regular Git refs and travel with push/fetch. No special GitLab configuration is needed.

### 8.2 GitLab API for notes (if needed)

If the metrics server doesn't have repos cloned locally, it can use the GitLab API:

```
GET /api/v4/projects/:id/repository/tree?ref=notes/ai&recursive=true
GET /api/v4/projects/:id/repository/blobs/:sha/raw
```

However, the **local git approach is recommended** — it's faster, has no rate limits, and the metrics server needs repo access anyway.

### 8.3 Protected refs

GitLab allows protecting refs. Do NOT protect `refs/notes/*` — developers need to push notes alongside their code. If your GitLab instance has a wildcard ref protection that blocks non-standard refs, add an exception for `refs/notes/ai`.

### 8.4 Merge requests

When a merge request is created and merged via the GitLab web UI:
- **Fast-forward merge:** Notes survive (commit SHAs don't change)
- **Merge commit:** Notes on the original commits survive; the merge commit itself has no note (no agent was involved)
- **Squash merge:** Git AI rewrites notes automatically on the developer's machine, but the **squashed commit on GitLab** is created server-side. Notes for the squashed commit will be missing unless:
  - The developer's local repo is updated and notes are re-pushed
  - A CI job runs `git-ai` after squash to reconstruct notes (requires Git AI on the CI runner)

**Recommendation:** Prefer fast-forward or regular merges over squash merges if attribution preservation matters.

---

## 9. CI/CD Integration

### 9.1 Verifying notes exist (CI check)

Add a CI job that verifies commits have Git AI notes:

```yaml
# .gitlab-ci.yml
verify-attribution:
  stage: test
  script:
    - git fetch origin 'refs/notes/*:refs/notes/*'
    - |
      LATEST=$(git rev-parse HEAD)
      NOTE=$(git notes --ref=ai show "$LATEST" 2>/dev/null || echo "MISSING")
      if [ "$NOTE" = "MISSING" ]; then
        echo "⚠️ No Git AI attribution note on commit $LATEST"
        echo "Ensure Git AI is installed and hooks are active."
        # exit 1  # uncomment to enforce
      else
        echo "✓ Git AI attribution present on $LATEST"
      fi
  allow_failure: true   # advisory, not blocking
```

### 9.2 Pushing notes from CI

If your CI pipeline creates commits (e.g., version bumps, changelog generation), those commits won't have Git AI notes (no agent involved). This is correct behavior — they are machine-generated, not AI-generated.

### 9.3 Notes fetch in CI

If downstream CI jobs need attribution data:

```yaml
before_script:
  - git fetch origin 'refs/notes/*:refs/notes/*'
```

---

## 10. Privacy and Security

### 10.1 What leaves the developer machine

| Layer | Content | Goes to GitLab? |
|-------|---------|-----------------|
| Git Note (refs/notes/ai) | File paths, line ranges, agent name, model, human author | **Yes** — pushed with code |
| Local prompts DB (~/.git-ai/internal/db) | Full conversation transcripts | **No** — stays local |
| Working logs (.git/ai/) | Byte-level diffs, file snapshots | **No** — never committed |
| Config (~/.git-ai/config.json) | Settings | **No** — stays local |

### 10.2 What's in a Git Note (the only thing that gets pushed)

- File paths (already visible in the commit diff)
- Line numbers (already visible in the commit diff)
- Agent tool name ("claude", "cursor", etc.)
- Model name ("claude-opus-4-6")
- Session ID (opaque UUID)
- Human author name (already in the commit metadata)
- Line counts (additions, deletions, accepted, overridden)

**Not in the note:** prompts, responses, code content, API keys, credentials, personal data beyond the committer name.

### 10.3 Disabling prompt upload

With `prompt_storage: local`, no conversation data is sent to usegitai.com. The `messages_url` field is omitted from notes entirely. This should be the **mandatory** setting for enterprise use.

### 10.4 Opt-out

A developer can opt out of Git AI by:

```bash
# Uninstall
~/.git-ai/bin/git-ai uninstall

# Or disable without uninstalling
git ai config set exclude_repositories '*'
```

Their commits will simply have no notes — the dashboard shows them with 0% AI attribution.

---

## 11. Troubleshooting

### "No Git AI notes on my commits"

1. **Did you restart VS Code and terminals after installing?**
   ```bash
   git ai --version   # should return a version
   ```

2. **Are hooks installed?**
   ```bash
   cat ~/.claude/settings.json | grep "git-ai"
   # Should show checkpoint commands in hooks
   ```

3. **Are checkpoints being recorded?**
   ```bash
   ls .git/ai/working_logs/
   # Should have directories if hooks are firing
   ```

4. **Is the agent actually making edits?**
   Git AI only records Write/Edit tool calls. If you manually edit files without an agent, no note is produced (correct behavior).

### "Notes aren't arriving on GitLab"

1. **Check push config:**
   ```bash
   git config --get-all remote.origin.push
   # Should include refs/notes/*:refs/notes/*
   ```

2. **Push notes explicitly:**
   ```bash
   git push origin 'refs/notes/*:refs/notes/*'
   ```

3. **Check GitLab ref protection** — ensure `refs/notes/*` isn't blocked.

### "Dashboard shows stale data"

1. **Fetch latest notes:**
   ```bash
   git fetch origin 'refs/notes/*:refs/notes/*'
   ```

2. **Trigger re-ingestion:**
   ```bash
   curl -X POST http://localhost:3001/api/ingest/run
   ```

### "Human lines are 0 for commits where I edited manually"

This is by design. Git AI tracks what **agents** wrote — human edits are the implicit complement. The metrics dashboard should derive human lines from:

```
human_lines = git_diff_additions - agent_accepted_lines
```

If the dashboard still shows 0, ensure the ingestion is using `git diff --numstat` to get actual diff statistics.

---

## 12. Appendix: Validated PoC Results

The following was validated on 2026-04-21 with a 3-repo workspace simulating the WoD workspace structure:

| Test | Result |
|------|--------|
| Single-repo attribution (agent launched in same repo) | **PASS** |
| Cross-repo attribution (agent launched from hub, commits in siblings) | **PASS** |
| Multi-agent concurrent (3 parallel subagents, 3 repos) | **PASS** |
| Human-only commit (no agent involvement) | **PASS** — correctly shows 0% AI |
| Squash merge attribution survival | **PASS** — notes rewritten correctly |
| Local prompt storage (no external upload) | **PASS** — `messages_url` removed |
| Auto-push notes alongside code | **PASS** — configured push refspecs work |
| Coexistence with Entire IO | **PASS** — no interference |

**Data scale validated:** 72 commits, 3 repos, 12,402 AI lines, 9,596 human lines, 2 models, 1 developer. Dashboard renders 10 charts from this data in under 100ms.

**Projected scale for WoD:** ~90 repos, ~15 developers, ~2,000 commits/month → ~2,000 DB rows/month, ~1 MB notes storage/month. No performance concerns.

---

## Quick Reference Card

```
┌─────────────────────────────────────────────────────────┐
│                    GIT AI QUICK REFERENCE                │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  INSTALL         curl -sSL https://usegitai.com/install.sh | bash
│  PRIVACY         git ai config set prompt_storage local  │
│  VERSION         git ai --version                        │
│  STATUS          git ai status                           │
│  BLAME           git ai blame <file>                     │
│  STATS           git ai stats HEAD~5..HEAD --json        │
│  VIEW NOTE       git notes --ref=ai show <sha>           │
│  LIST NOTES      git notes --ref=ai list                 │
│  PUSH NOTES      git push origin 'refs/notes/*:refs/notes/*'
│  FETCH NOTES     git fetch origin 'refs/notes/*:refs/notes/*'
│  REINSTALL HOOKS git ai install-hooks                    │
│                                                          │
│  NOTES AUTO-PUSH CONFIG (per repo):                      │
│  git config --add remote.origin.push 'refs/heads/*:refs/heads/*'
│  git config --add remote.origin.push 'refs/notes/*:refs/notes/*'
│                                                          │
└─────────────────────────────────────────────────────────┘
```
