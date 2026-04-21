# Git AI Validation — Results

**Date:** 2026-04-21
**Tester:** Claude Code agent (Opus 4.6, 1M context)
**Git AI CLI version:** 1.3.2
**Git AI Standard:** authorship/3.0.0
**Claude CLI version:** 2.1.98
**Session ID:** 9b4e6eb7-f49a-48c2-b519-1842319d6fe1

---

## 1. Summary

**Git AI VALIDATED — line-level per-commit attribution works for our cross-repo workspace workflow.**

Git AI produces accurate, structured Git Notes on every commit in every repo, including commits made in sibling service repos from a workspace-launched Claude Code session. This is the architectural property that Entire Pattern C could not deliver. Git AI solves it by design — attribution is agent-reported via global Claude Code hooks, not repo-local hooks, so the "where was the agent launched" question is irrelevant.

**Recommendation: ADOPT**

---

## 2. Cleanup Summary

Before the validation, repos were cleaned up:

- **Branches deleted:** `entire/checkpoints/v1` removed from `entire-poc-backend` and `entire-poc-frontend` (local + remote). Kept in `entire-poc-workspace` for Entire baseline preservation.
- **No other stale branches** found across any repo.
- **Entire remnants:** Service repos already clean (no `.entire/` dir, no hooks). Workspace Entire left intact.
- **Old docs:** 7 obsolete Entire validation docs deleted; new `gitai-validation-spec.md` added.
- **Final state:** All three repos on `main` only, services running, database intact with 5 sessions / 8 checkpoints / 31 links.

---

## 3. Installation Experience

**Smooth — Git AI was already installed (v1.3.2, installed 2026-04-20).**

- Binary at `~/.git-ai/bin/git-ai`
- Claude Code hooks configured automatically in `~/.claude/settings.json`:
  - `PreToolUse` → `git-ai checkpoint claude --hook-input stdin` (matcher: `*`)
  - `PostToolUse` → `git-ai checkpoint claude --hook-input stdin` (matcher: `*`)
- Skills installed: `/ask`, `git-ai-search`, `prompt-analysis` (symlinked to `~/.claude/skills/` and `~/.agents/skills/`)
- Config: points to system git (`/opt/homebrew/bin/git`), API base `https://usegitai.com`
- **No paid license, no signup, no external service dependency** (REQ-I-2 satisfied)
- Existing Git operations (`git status`, `git log`, `git commit`, `git push`) work normally (REQ-I-5 satisfied)
- **Coexists with Entire** without interference (REQ-I-6 satisfied) — both tools operated simultaneously throughout the validation

---

## 4. Phase 2 Result — Single-Repo Smoke Test

**PASS**

Commit: `4e027dc` in `entire-poc-backend`
Change: Added `src/utils/format.ts` (6 lines, `formatPercent` utility)

### Raw Git Note

```
src/utils/format.ts
  1612649c4bf0b88e 1-6
---
{
  "schema_version": "authorship/3.0.0",
  "git_ai_version": "1.3.2",
  "base_commit_sha": "4e027dc3ff77efe497fdb9f91ded8c1322e6800c",
  "prompts": {
    "1612649c4bf0b88e": {
      "agent_id": {
        "tool": "claude",
        "id": "9b4e6eb7-f49a-48c2-b519-1842319d6fe1",
        "model": "claude-opus-4-6"
      },
      "human_author": "Dmytro Shamsiiev",
      "messages": [],
      "total_additions": 6,
      "total_deletions": 0,
      "accepted_lines": 6,
      "overriden_lines": 0,
      "messages_url": "https://usegitai.com/cas/41759e6d33aa9e0ac1a8c754a8c60cb991a5ed7fb67a8d4c47e0b09b45d845bf"
    }
  }
}
```

### Verification

| Check | Result |
|-------|--------|
| Git Note exists | Yes |
| Agent identified | `claude` / `claude-opus-4-6` |
| Line ranges | `1-6` (all lines — correct for 100% AI-authored file) |
| `total_additions` = 6, `accepted_lines` = 6 | Correct |
| `git ai blame` output | All 6 lines attributed to `claude` |
| `git ai stats --json` | `ai_additions: 6`, `human_additions: 0` |
| Notes visible on GitHub via API | Yes — `refs/notes/ai` present |

---

## 5. Phase 3 Result — Cross-Repo Hub-Launched Test (THE CRITICAL TEST)

**PASS — both service-repo commits have Git Notes with full attribution.**

This is the test that Entire Pattern C failed. Agent launched from `entire-poc-workspace/`, edited files in both `../entire-poc-backend/` and `../entire-poc-frontend/` via relative paths, committed in each repo via subshells.

### Backend Commit: `6df5a6e`

Change: Added `gitAiTest: true` to status route response object (1 line)

```
src/api/routes/status.ts
  1612649c4bf0b88e 32
---
{
  "schema_version": "authorship/3.0.0",
  "git_ai_version": "1.3.2",
  "base_commit_sha": "6df5a6e53e91c84802ed2a25a7c80eda120dd171",
  "prompts": {
    "1612649c4bf0b88e": {
      "agent_id": {
        "tool": "claude",
        "id": "9b4e6eb7-f49a-48c2-b519-1842319d6fe1",
        "model": "claude-opus-4-6"
      },
      "human_author": "Dmytro Shamsiiev",
      "messages": [],
      "total_additions": 1,
      "total_deletions": 0,
      "accepted_lines": 1,
      "overriden_lines": 0,
      "messages_url": "https://usegitai.com/cas/d0ea55ae26e4f7bf785c27378f68677cebeac7780ea27c9544ff0aaa76a1c99b"
    }
  }
}
```

### Frontend Commit: `45935c0`

Change: Added Git AI badge to IngestionStatus component (1 agent line + 4 unknown from `test-results/`)

```
src/components/IngestionStatus.tsx
  1612649c4bf0b88e 24
---
{
  "schema_version": "authorship/3.0.0",
  "git_ai_version": "1.3.2",
  "base_commit_sha": "45935c019a80bc81796b67ccd838f27a895719d8",
  "prompts": {
    "1612649c4bf0b88e": {
      "agent_id": {
        "tool": "claude",
        "id": "9b4e6eb7-f49a-48c2-b519-1842319d6fe1",
        "model": "claude-opus-4-6"
      },
      "human_author": "Dmytro Shamsiiev",
      "messages": [],
      "total_additions": 1,
      "total_deletions": 0,
      "accepted_lines": 1,
      "overriden_lines": 0,
      "messages_url": "https://usegitai.com/cas/1448aa267ec3beb36bce8f3e59097c0a96925c8e39c99ecc42fe6c3ddb9e80a7"
    }
  }
}
```

### Critical Properties Verified

| Property | Result |
|----------|--------|
| Notes exist on BOTH service-repo commits | **Yes** |
| Agent correctly identified in both | `claude` / `claude-opus-4-6` |
| Same session ID in both notes | `9b4e6eb7-...` — same session |
| Same prompt ID across repos | `1612649c4bf0b88e` — proves cross-repo session continuity |
| Line attribution correct | Backend: line 32. Frontend: line 24. Both correct. |
| `unknown_additions` distinguished from `ai_additions` | Frontend: 4 lines from auto-included `test-results/` correctly classified as unknown |

### Why This Succeeds Where Entire Failed

Entire Pattern C required per-repo hooks fired by git events within each repo. When commits happened via subshell from a workspace-rooted agent, Entire's repo-local hooks never fired in the service repos.

Git AI uses a fundamentally different architecture: Claude Code's **global hooks** (PreToolUse/PostToolUse in `~/.claude/settings.json`) fire on every file edit regardless of which repo the file is in. The checkpoint command writes to each file's repo's `.git/ai/` directory based on the file path, not the CWD. When the commit happens, the accumulated checkpoints are condensed into a Git Note. The "where was the agent launched" question is irrelevant — what matters is which files were edited.

---

## 6. Ingestion Pipeline Changes

### New backend files

| File | Purpose |
|------|---------|
| `src/ingestion/gitai-fetcher.ts` | Fetches Git AI notes from GitHub via Git database API (refs, trees, blobs) |
| `src/ingestion/gitai-parser.ts` | Parses authorship/3.0.0 note format into structured data |
| `src/ingestion/gitai-orchestrator.ts` | Orchestrates fetch → parse → DB upsert for all repos |
| `src/db/gitai-repo.ts` | Repository layer with UPSERT, queries, and summary aggregations |
| `src/api/routes/gitai.ts` | REST endpoints for Git AI data |
| `tests/gitai-parser.test.ts` | 9 tests covering parsing and attribution computation |

### New API endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/gitai/commits` | All commits with attribution |
| `GET /api/gitai/commits/:sha` | Detail for one commit including file-level attribution |
| `GET /api/gitai/summary` | Aggregated summary (by repo, by agent) |
| `GET /api/compare/entire-vs-gitai` | Side-by-side comparison joining Git AI and Entire data |

### Integration approach

- Git AI ingestion runs alongside Entire ingestion in the same orchestrator cycle
- Both sources coexist: `POST /api/ingest/run` returns a combined report with `entire` and `gitai` sections
- Existing Entire ingestion code is **untouched** — Git AI code was added alongside per the spec

---

## 7. Frontend Additions

| File | Description |
|------|-------------|
| `src/components/charts/GitAiAgentPercentageChart.tsx` | Horizontal bar chart — agent % per commit, colored by repo |
| `src/components/EntireVsGitAiComparison.tsx` | Table with source badges showing both sources' data per commit |
| Updated `src/api/client.ts` | Added `api.gitai.*` methods and types |
| Updated `src/hooks/useChartData.ts` | Added `useGitAiCommits`, `useGitAiSummary`, `useEntireVsGitAi` hooks |
| Updated `src/components/Dashboard.tsx` | New "Git AI Attribution" section with chart and comparison table |

The dashboard now has:
- All original Entire sections (unchanged)
- A new "Git AI Attribution" section (visually separated with blue border)
- Agent % per Commit chart (Git AI line-level data)
- Entire vs Git AI comparison table with source badges

---

## 8. Database State

### Baseline (before Git AI ingestion)

| Table | Count |
|-------|-------|
| `sessions` | 5 |
| `session_repo_touches` | 8 |
| `repo_checkpoints` | 8 |
| `session_commit_links` | 31 |

### After Git AI ingestion

| Table | Count |
|-------|-------|
| `sessions` | 11 (Entire) |
| `session_repo_touches` | 8 (Entire) |
| `repo_checkpoints` | 10 (Entire) |
| `session_commit_links` | 31 (Entire) |
| **`gitai_commit_attribution`** | **44** |

### Git AI attribution breakdown

| Repo | Commits | Avg Agent % | Total AI Lines | Total Human Lines |
|------|---------|-------------|----------------|-------------------|
| entire-poc-backend | 22 | 95.9% | 2,327 | 179 |
| entire-poc-frontend | 16 | 93.5% | 1,118 | 8 |
| entire-poc-workspace | 6 | 100.0% | 2,787 | 0 |
| **Total** | **44** | **95.6%** | **6,232** | **187** |

---

## 9. Comparison Table — Entire Pattern A* vs Git AI

| Dimension | Entire Pattern A* | Git AI |
|-----------|-------------------|--------|
| **Attribution granularity** | File-level (which files were touched) | **Line-level** (which lines, by which agent) |
| **Per-commit attribution** | Indirect (session-to-commit linking via timestamp + file overlap) | **Direct** (Git Note attached to the commit) |
| **Cross-repo from workspace** | Session continuity: YES. Per-repo attribution: NO (Pattern C limitation) | **YES** — notes on both service-repo commits |
| **Confidence level** | MEDIUM/LOW (probabilistic joins) | **Deterministic** (agent self-reports) |
| **Agent identification** | From transcript metadata | From checkpoint hook — includes tool, model, session ID |
| **Model identification** | From transcript metadata | **Per-prompt** — tracks model changes within a session |
| **Setup per repo** | None (workspace-only) | None (machine-wide) |
| **Data storage** | Checkpoint branch + DB | Git Notes (`refs/notes/ai`) + DB |
| **Portability** | Requires Entire CLI + cron | **Native Git** — notes push/pull like any ref |
| **Session-level signals** | Friction, open items, learnings, token usage, tool calls | Not captured (complement, not replacement) |
| **Offline operation** | Yes | Yes |
| **Multi-agent** | Claude Code only (current setup) | Claude, Cursor, Copilot, Codex, Gemini CLI, others |

### Key insight

Entire and Git AI are **complementary**, not competing:
- **Entire** captures session-process signals (friction, learnings, open items, token usage, tool calls)
- **Git AI** captures code-attribution signals (which lines were AI-written, by which agent/model)

The production recommendation is to run both: Entire for session analytics, Git AI for commit attribution.

---

## 10. Final Recommendation

### **ADOPT** — Git AI delivers the primary business deliverable

Line-level per-commit attribution works in our cross-repo workspace workflow. The architectural property holds: agents report their own edits via global hooks, so hub-launched sessions correctly attribute code in sibling service repos.

### Evidence

1. **Single-repo:** 100% correct attribution on `4e027dc` (6 AI lines, 0 human)
2. **Cross-repo:** Both `6df5a6e` (backend) and `45935c0` (frontend) have correct notes with shared session/prompt IDs
3. **Scale:** 44 commits across 3 repos successfully ingested with 95.6% average AI attribution
4. **Accuracy:** `unknown_additions` correctly distinguished from `ai_additions` (4 auto-included test artifact lines flagged as unknown)
5. **Coexistence:** Git AI and Entire ran simultaneously with zero interference throughout the validation

### Caveats — all verified

All four original caveats have been tested and resolved:

1. **Human-only commit control case (REQ-V-4): VERIFIED.**
   Commit `7ee324a` was created using only Bash (no Write/Edit agent tools). Result: Git Note exists with `"prompts": {}` (empty). `git ai stats` shows `ai_additions: 0`, `unknown_additions: 3`. Git AI correctly attributes zero lines to AI when no agent tools were used. The 3 lines are classified as "unknown" rather than "human" — a correct semantic: Git AI tracks what agents DID write; everything else is unattributed.

2. **`messages_url` / prompt privacy: RESOLVED.**
   Running `git ai config set prompt_storage local` removes the `messages_url` field entirely from Git Notes. Commit `ba0d9c8` (made after the config change) has no `messages_url` — prompts stay in local SQLite only. For production: set this config on every developer machine during onboarding. The attribution data (agent, model, line ranges) is unaffected — only the prompt upload is disabled.

3. **Note push discipline: RESOLVED.**
   Configure per-repo (or global) push refspecs:
   ```bash
   git config --add remote.origin.push 'refs/heads/main:refs/heads/main'
   git config --add remote.origin.push 'refs/notes/*:refs/notes/*'
   ```
   Verified: `git push` (no explicit ref) pushes both main and notes automatically. Local and remote `refs/notes/ai` confirmed in sync. For production: add this to repo setup scripts or enforce via git templates.

4. **Rebase/squash attribution survival: VERIFIED.**
   Created two commits on branch `test/rebase-squash-notes` (A: `796b9b5`, B: `22596b2`), each with Git AI notes. Squash-merged into main as `acc1ed8`. Result: the squash commit's note **correctly combines** both files from A and B, with `accepted_lines: 6` (3+3) and both file paths listed. Git AI's automatic rewrite works as documented — attribution survives squash merges.

---

## 11. Production Rollout Implications (60-repo GitLab Workspace)

### What needs to change

1. **Machine-wide install:** Run `curl -sSL https://usegitai.com/install.sh | bash` on each developer machine. One-time, ~30 seconds.

2. **IDE/Agent restart:** After install, restart VS Code and all agent sessions. Document in onboarding.

3. **Git Notes push:** Configure each repo (or global git config) to push notes alongside branches (verified working in this validation):
   ```bash
   git config --add remote.origin.push 'refs/heads/main:refs/heads/main'
   git config --add remote.origin.push 'refs/notes/*:refs/notes/*'
   ```
   This ensures `git push` sends both code and attribution. Add to repo setup scripts or git templates.

3b. **Prompt privacy:** Run on each developer machine:
   ```bash
   git ai config set prompt_storage local
   ```
   This prevents prompt content from being uploaded to usegitai.com. Attribution metadata (agent, model, line ranges) is unaffected.

4. **GitLab notes support:** Verify GitLab handles `refs/notes/ai` correctly — GitLab supports Git Notes natively, but verify the API path differs from GitHub (`/projects/:id/repository/commits/:sha/comments` vs raw refs).

5. **Ingestion pipeline:** Replace GitHub API calls with GitLab API calls in `gitai-fetcher.ts`. The note format is the same; only the transport layer changes.

6. **Scale consideration:** 60 repos × N commits = many API calls per ingestion. Consider:
   - Incremental ingestion (track last-seen note per repo)
   - `git fetch` with notes refs instead of API calls (faster for local ingestion)
   - Rate limiting / pagination for GitLab API

7. **Supabase migration:** For production, migrate from local SQLite to Supabase (or PostgreSQL). The `gitai_commit_attribution` schema is production-ready; only the connection layer needs to change.

8. **Multi-agent coverage:** Git AI supports Cursor, Copilot, Codex, and Gemini CLI out of the box. As developers use different agents, attribution data will naturally include multiple agent types.

9. **Entire retention:** Keep Entire for session-process analytics (friction, learnings, open items). Git AI for commit attribution. Both feed into the same dashboard.

---

## 12. Artifact Inventory

### Workspace repo (`entire-poc-workspace`)
- `docs/gitai-validation-spec.md` — specification document
- `docs/GITAI-VALIDATION-RESULTS.md` — this document
- `scripts/install-gitai.sh` — Git AI install wrapper
- `scripts/inspect-gitai-notes.sh` — diagnostic helper

### Backend repo (`entire-poc-backend`)
- `src/ingestion/gitai-fetcher.ts` — GitHub API fetcher for Git Notes
- `src/ingestion/gitai-parser.ts` — authorship/3.0.0 parser
- `src/ingestion/gitai-orchestrator.ts` — ingestion orchestrator
- `src/db/gitai-repo.ts` — database repository layer
- `src/api/routes/gitai.ts` — REST API routes
- `src/db/schema.sql` — updated with `gitai_commit_attribution` table
- `tests/gitai-parser.test.ts` — parser tests (9 tests)

### Frontend repo (`entire-poc-frontend`)
- `src/components/charts/GitAiAgentPercentageChart.tsx` — agent % chart
- `src/components/EntireVsGitAiComparison.tsx` — comparison table
- Updated: `Dashboard.tsx`, `client.ts`, `useChartData.ts`
