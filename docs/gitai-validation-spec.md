# Git AI Validation — Specification

## 1. Document purpose

This document specifies how to migrate our existing Entire PoC infrastructure to Git AI and validate whether Git AI produces the line-level per-commit attribution we need for production coding metrics, in our specific cross-repo workspace workflow.

This is the input spec for Claude Code (or any implementer) to execute. It contains everything needed to run the validation end-to-end and produce a clear go/no-go answer.

---

## 2. Background — the problem we are solving

### 2.1 What we need

Our team builds AI observability for software development. The primary deliverable is a coding-metrics dashboard that captures, per commit, in every repo of a multi-repo workspace:

1. **Lines written by AI agent(s)** — distinguished per agent (Claude Code, Cursor, Codex, Copilot)
2. **Lines written by the human developer**
3. **Token usage per agent session** (optional but desired)

These three metrics are the business-facing "ROI of AI coding" signals. File-level proxies are insufficient — stakeholders want to see "73% of this commit was agent-authored," not "the agent touched 4 files in this commit."

### 2.2 Why this is hard in our environment

Three constraints make most commercial tools inapplicable:

- **Decentralized subscriptions.** Each developer owns their own Copilot / Cursor / Anthropic subscription. No admin-level API access exists at the organization level. This eliminates DX, LinearB, Jellyfish, Axify, and every tool whose server-side aggregation depends on admin vendor APIs.
- **Multi-agent coverage.** We use Claude Code, Cursor, Codex, and Copilot simultaneously. Tools that only cover one agent are insufficient.
- **GitLab-based production environment.** The real workspace runs on GitLab, not GitHub. Many tools in this space are GitHub-first.

### 2.3 The workspace architecture that must be supported

This is the single most important architectural property to validate against:

```
~/Projects/metrics_2_0/
├── _wod.workspace/           ← Hub repo. Skills, BMad configs, agent settings.
│                               No application code.
│                               Developers LAUNCH agents from here.
├── wod/
│   ├── wod.wodModule.api/    ← Service repo (one of ~60)
│   ├── wod.employeeService/  ← Service repo
│   └── ...
├── auth/ ...
├── core/ ...
└── ...
```

- Developers launch Claude Code / Cursor / Codex **from the workspace hub** (`_wod.workspace/`)
- Agents edit files across **sibling service repos** in the same session
- Commits happen **inside each service repo**, not in the hub
- The real workspace has ~60 service repos; our PoC represents this with 2 (`entire-poc-backend`, `entire-poc-frontend`)

### 2.4 What we tried, and what we learned

**Entire IO Pattern C** — enable Entire in every repo, join on server side.
- ❌ Service repos produce no checkpoints when commits happen via subshell from a workspace-rooted agent session. Architectural mismatch with hub-launched workflow.

**Entire IO Pattern A*** (workspace-only, transcript-first ingestion) — enable Entire only in the workspace, derive per-repo attribution from transcript `filePath` events.
- ✅ Works for file-level attribution, cross-repo session continuity, friction, open items, tool usage
- ❌ Cannot produce per-commit line-level attribution (the primary business deliverable)
- ❌ Requires `entire doctor` cron + session-log commits + workspace-only workflow

**Decision:** Entire captures valuable session-process signal but does not deliver the line-level coding metrics that are our primary deliverable. We are therefore evaluating Git AI, whose architectural model appears to match our requirements natively.

### 2.5 Why Git AI is the hypothesis worth testing

From the Git AI project documentation:

- **Agent-reported, not heuristic.** Agents call `git-ai checkpoint` to explicitly mark the lines they wrote — no guesswork
- **No per-repo setup required.** Installed as a machine-wide git extension; works across any repo
- **Local-first, 100% offline, free.** Apache 2.0 open source, no login required, no external service dependencies
- **Line-level attribution via Git Notes.** Stored per commit in `refs/notes/ai` (or similar), portable with the repo
- **Multi-agent support.** Claude Code, Cursor, Codex, Copilot, Gemini CLI, and others
- **Works on rebase/squash/cherry-pick.** Attribution automatically follows history rewrites

The architectural key is that agents themselves call `git-ai checkpoint` during code generation — not a repo-local hook. This means the "where was the agent launched" question stops mattering; what matters is which files the agent marked edits against. This is exactly the property our hub-launched workflow needs.

**What we need to validate is whether this claim holds in practice** for our cross-repo hub-launched scenario — the same failure mode that broke Entire's Pattern C.

---

## 3. Current working setup — what the agent is starting from

The implementer is starting from a known-good state documented in the existing PoC repos. The following must be preserved during the Git AI migration.

### 3.1 Existing repos (GitHub, personal account)

- `ShamsiievDmytro/entire-poc-workspace` — hub repo, contains the Entire Pattern A* setup + the backend ingestion pipeline code
- `ShamsiievDmytro/entire-poc-backend` — Node.js + TypeScript + SQLite ingestion service and REST API (port 3001)
- `ShamsiievDmytro/entire-poc-frontend` — React + Vite dashboard (port 5173)

### 3.2 Running services

- Backend dev server: `http://localhost:3001`
- Frontend dev server: `http://localhost:5173`
- SQLite database: `entire-poc-backend/data/poc.db`

### 3.3 Existing data model (SQLite)

Current tables (Pattern A*):
- `sessions` — session-level metadata, tokens, friction, open items
- `session_repo_touches` — derived per-repo file touches from workspace transcript
- `repo_checkpoints` — per-commit attribution (currently populated only for workspace commits via Entire)
- `session_commit_links` — session-to-commit joins at HIGH/MEDIUM/LOW confidence

### 3.4 Validation baseline

Before Git AI migration, the current database state contains Entire Pattern A* data from earlier validation sessions:

- `sessions`: multiple rows (baseline — will need to be noted)
- `session_commit_links`: populated with MEDIUM/LOW confidence joins from Pattern A*

This baseline is intentionally preserved so we can compare "Entire Pattern A*" results against "Git AI" results side-by-side on the same infrastructure.

### 3.5 Current Entire configuration

The workspace currently has Entire enabled:
- `_wod.workspace/.entire/settings.json` with auto-summarize on
- `_wod.workspace/.claude/settings.json` with Entire hooks installed
- Cron job running `entire doctor --force` every 4 hours

**Important: during the Git AI validation, Entire stays installed.** We are testing whether Git AI can run alongside Entire on the same machine, capturing its own Git Notes independently. If both tools coexist without interfering, the side-by-side comparison is cleanest. If they conflict, we'll disable Entire temporarily for the Git AI validation phase.

---

## 4. Goals and non-goals

### 4.1 Goals

- Install Git AI on the developer machine (one-time, machine-wide)
- Verify Git AI produces Git Notes with line-level attribution on normal single-repo commits
- Verify Git AI produces Git Notes with line-level attribution on **cross-repo hub-launched commits** (the critical case)
- Extend the existing backend ingestion pipeline to read Git Notes from the three PoC repos on GitHub
- Store Git AI attribution data in the SQLite database using the existing schema where possible
- Display Git AI per-commit attribution in the existing frontend dashboard, alongside the Entire data for comparison
- Produce a clear go/no-go verdict with evidence

### 4.2 Non-goals

- Replacing Entire in production yet (only validating Git AI as a candidate)
- Deploying the commercial "Git AI For Teams" product (free tier only)
- Setting up self-hosted prompt storage (local SQLite is fine for validation)
- Rewriting the frontend dashboard beyond adding one new chart and one comparison view
- Supporting GitLab (validation is on personal GitHub; GitLab is the production target, to be tested separately if Git AI validates here)
- Testing every supported agent; Claude Code is sufficient for the validation
- Removing Entire from the workspace (it stays installed for comparison purposes)

---

## 5. Requirements

### 5.1 Installation requirements (REQ-I)

- **REQ-I-1.** Git AI CLI installed on the developer machine via the official install script
- **REQ-I-2.** Installation must not require a paid license, account signup, or external service dependency
- **REQ-I-3.** After install, `git ai --version` returns a valid version string
- **REQ-I-4.** After install, the `/ask` skill is available in `~/.agents/skills/` and `~/.claude/skills/` (per the docs — this is Git AI's default setup)
- **REQ-I-5.** Existing Git operations (`git status`, `git log`, `git commit`, `git push`, `git pull`) continue to work normally with no regression
- **REQ-I-6.** Installation must coexist with the existing Entire setup in the workspace repo without interfering with Entire's hooks or commit flow
- **REQ-I-7.** IDEs and agent sessions started before Git AI installation must be restarted to pick up the agent hooks (documented as required in the Git AI setup docs)

### 5.2 Capture requirements (REQ-C)

- **REQ-C-1.** When Claude Code edits a file, it must call `git-ai checkpoint` automatically (via the hooks installed by Git AI) — no manual instruction required in the agent prompt
- **REQ-C-2.** After a `git commit` in a service repo, a Git Note must be attached to the commit in the appropriate Git Notes ref (per Git AI's standard — likely `refs/notes/ai` or `refs/notes/commits`)
- **REQ-C-3.** The Git Note content must include at minimum: agent identifier (e.g., `claude-code`), model name, line ranges attributed to the agent, and a reference to the prompt/session
- **REQ-C-4.** For commits made in a service repo during a session launched from the workspace hub, the Git Note must still be created and populated with attribution — this is the core test case
- **REQ-C-5.** For commits made by the human (no agent involvement), no agent attribution should appear — lines should be correctly identified as human-authored
- **REQ-C-6.** For commits where both human and agent contributed, line ranges must correctly split between the two sources

### 5.3 Data portability requirements (REQ-P)

- **REQ-P-1.** `git push origin refs/notes/*` (or the specific Git AI notes ref) must successfully push notes to GitHub
- **REQ-P-2.** Notes must be visible on GitHub via the REST API endpoint `GET /repos/{owner}/{repo}/git/refs`
- **REQ-P-3.** Note content must be fetchable via the GitHub API and parseable into structured data
- **REQ-P-4.** Notes must survive normal Git operations: rebase, squash merge, cherry-pick (automatic rewriting is a Git AI feature per the docs)

### 5.4 Ingestion pipeline requirements (REQ-B)

- **REQ-B-1.** The existing backend service (`entire-poc-backend`) must be extended to read Git Notes from each of the three PoC repos via the GitHub API
- **REQ-B-2.** New ingestion code must coexist with existing Entire ingestion code; both run in the same orchestrator, neither removes the other
- **REQ-B-3.** A new source flag (e.g., `source: 'git-ai' | 'entire'`) must distinguish which capture layer produced each row in the database
- **REQ-B-4.** The Git AI ingestion must parse the Git Notes format (Git AI Standard v3.0.0 or current) into structured fields:
  - `commit_sha`
  - `repo`
  - `agent` (e.g., claude-code, cursor)
  - `model`
  - `agent_lines` (count)
  - `human_lines` (count)
  - `agent_percentage` (derived)
  - `prompt_id` (reference to local session data)
  - `files_touched_json` (list of files with agent-attributed line ranges)
  - `captured_at` (commit timestamp)
- **REQ-B-5.** Ingestion must be idempotent — re-running on the same commits must not produce duplicate rows
- **REQ-B-6.** New REST endpoints must expose Git AI data:
  - `GET /api/gitai/commits` — all commits with attribution
  - `GET /api/gitai/commits/:sha` — detail for one commit including file-level attribution
  - `GET /api/gitai/summary` — aggregated summary (agent % by repo, by day, etc.)
  - `GET /api/compare/entire-vs-gitai` — side-by-side comparison for commits covered by both sources

### 5.5 Database schema requirements (REQ-D)

Extend the existing schema rather than replace it. New table:

```sql
CREATE TABLE IF NOT EXISTS gitai_commit_attribution (
  repo TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  agent TEXT NOT NULL,
  model TEXT,
  agent_lines INTEGER NOT NULL,
  human_lines INTEGER NOT NULL,
  agent_percentage REAL NOT NULL,
  prompt_id TEXT,
  files_touched_json TEXT,
  raw_note_json TEXT,
  captured_at TIMESTAMP,
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (repo, commit_sha, agent)
);

CREATE INDEX IF NOT EXISTS idx_gitai_committed_at ON gitai_commit_attribution(captured_at);
CREATE INDEX IF NOT EXISTS idx_gitai_repo ON gitai_commit_attribution(repo);
```

Primary key includes `agent` because a single commit could theoretically contain contributions from multiple agents (e.g., developer used Cursor then Claude Code before committing).

### 5.6 Frontend requirements (REQ-F)

- **REQ-F-1.** Add a new "Git AI Attribution" section to the dashboard showing per-commit agent-percentage across all three repos
- **REQ-F-2.** Add a comparison view showing the same time window of commits with both sources (Entire Pattern A* file-level data + Git AI line-level data) side-by-side
- **REQ-F-3.** Add a chart: "Agent % per Commit Over Time" using Git AI data as the source
- **REQ-F-4.** Existing Entire dashboard sections remain unchanged — this is additive
- **REQ-F-5.** A visible indicator on each data row showing which source it came from (badge: "Entire" vs "Git AI")

### 5.7 Validation criteria (REQ-V)

The Git AI validation is **successful** if ALL of the following hold:

- **REQ-V-1.** After a Claude Code session launched from the workspace editing files in both service repos, committing in each service repo, each service-repo commit has a Git Note with attribution data
- **REQ-V-2.** The attribution identifies Claude Code as the source with a plausible model name
- **REQ-V-3.** `agent_lines` plus `human_lines` equals the total lines changed in the commit (or is close — small off-by-one is acceptable)
- **REQ-V-4.** Attribution is correct for a control case: a commit made purely by human with no agent involvement shows zero agent lines
- **REQ-V-5.** The backend successfully ingests Git Notes from GitHub without errors
- **REQ-V-6.** The frontend dashboard displays the Git AI attribution data
- **REQ-V-7.** The Entire-vs-Git-AI comparison view shows the same commits with both sources' interpretation

The validation is **partially successful** (warrants further investigation) if:

- **REQ-V-8.** Git Notes exist but attribution is incomplete (missing model name, fuzzy line counts)
- **REQ-V-9.** Attribution works for commits made after `cd`ing into the service repo, but not for cross-repo hub-launched commits (this would mean Git AI has a similar repo-scoping limitation as Entire)

The validation **fails** (Git AI is not viable for our use case) if:

- **REQ-V-10.** No Git Notes appear on service-repo commits at all
- **REQ-V-11.** Git Notes exist but have no structured attribution data
- **REQ-V-12.** Installation breaks normal Git operations

---

## 6. Implementation phases

Ordered. Each phase has explicit done criteria.

### Phase 0 — Preflight (5 min)

1. Verify current baseline is intact:
   ```bash
   cd ~/Projects/metrics_2_0/entire-poc-workspace
   entire status  # should show enabled with existing sessions
   curl -s http://localhost:3001/api/status  # should return JSON
   curl -s -o /dev/null -w "%{http_code}" http://localhost:5173  # 200
   ```

2. Record current database baseline:
   ```bash
   sqlite3 ~/Projects/metrics_2_0/entire-poc-backend/data/poc.db <<'SQL'
   .headers on
   .mode column
   SELECT 'sessions' AS t, COUNT(*) AS n FROM sessions
   UNION ALL SELECT 'session_repo_touches', COUNT(*) FROM session_repo_touches
   UNION ALL SELECT 'repo_checkpoints', COUNT(*) FROM repo_checkpoints
   UNION ALL SELECT 'session_commit_links', COUNT(*) FROM session_commit_links;
   SQL
   ```
   **Write down the counts** for later comparison.

3. Check Node, npm, Claude CLI versions:
   ```bash
   node --version  # expect 20+
   claude --version
   ```

4. Confirm we have a GitHub token available (already present for the existing Entire ingestion):
   ```bash
   grep GITHUB_TOKEN ~/Projects/metrics_2_0/entire-poc-backend/.env
   ```

**Done when:** all five checks pass. Baseline counts are recorded.

---

### Phase 1 — Install Git AI (10 min)

1. Review official install instructions at `usegitai.com/docs/cli` to confirm the current install command.

2. Run the installer:
   ```bash
   # Expected — verify the exact command from the docs first
   curl -fsSL https://usegitai.com/install.sh | bash
   ```

3. Restart the terminal shell completely (per REQ-I-7):
   ```bash
   exec $SHELL
   ```

4. Verify installation:
   ```bash
   git ai --version
   git ai --help
   ```

5. Verify existing Git works:
   ```bash
   cd ~/Projects/metrics_2_0/entire-poc-backend
   git status
   git log --oneline -3
   ```

6. Check if Git AI placed the `/ask` skill:
   ```bash
   ls ~/.agents/skills/ 2>/dev/null
   ls ~/.claude/skills/ 2>/dev/null
   ```

7. Check for any Git AI local state / SQLite:
   ```bash
   ls -la ~/.git-ai/ 2>/dev/null
   ls -la ~/.local/share/git-ai/ 2>/dev/null
   ```

8. Important: **restart VS Code and close any running Claude Code sessions** so agent hooks are re-read on next launch.

**Done when:**
- `git ai --version` returns a valid version
- Existing Git operations still work
- `/ask` skill is present (or documented as absent if the docs are outdated)
- VS Code and Claude Code sessions have been restarted

---

### Phase 2 — Single-repo smoke test (15 min)

Test the intended happy path first before the workspace scenario.

1. `cd ~/Projects/metrics_2_0/entire-poc-backend`

2. Launch Claude Code directly from the backend repo (not the workspace):
   ```bash
   claude
   ```

3. Ask the agent a simple task:
   > Add a TypeScript utility function `formatPercent(value: number): string` to `src/utils/format.ts` (create the file if it doesn't exist). Return the value formatted as `"XX%"` rounded to 1 decimal. Then commit the change with the message "test: git-ai smoke — add formatPercent utility" and push.

4. After the agent commits, inspect:
   ```bash
   # Check default notes ref
   git log --show-notes=ai --oneline -3
   
   # List notes
   git notes --ref=ai list 2>/dev/null
   
   # Get the most recent commit SHA
   LATEST=$(git rev-parse HEAD)
   
   # Show the note content
   git notes --ref=ai show "$LATEST" 2>/dev/null
   
   # Try Git AI's own commands
   git ai blame src/utils/format.ts
   git ai stats HEAD~1..HEAD --json
   ```

5. Push the notes to origin:
   ```bash
   git push origin refs/notes/ai
   # Or the full refspec
   git push origin 'refs/notes/*:refs/notes/*'
   ```

6. Verify notes arrived on GitHub:
   ```bash
   gh api "repos/ShamsiievDmytro/entire-poc-backend/git/refs" | jq '.[] | select(.ref | contains("notes"))'
   ```

**Done when:**
- The commit has a Git Note containing attribution
- The attribution identifies Claude Code and has line counts
- Notes ref is visible on GitHub via API

**If this fails:** stop immediately. Single-repo usage is Git AI's intended happy path. If it doesn't work here, it won't work for our harder case. Report the failure mode — likely missing hooks, auth problem, or VS Code not restarted.

---

### Phase 3 — The critical test: workspace-launched cross-repo session (20 min)

This is the test that Entire failed. If Git AI passes this, the architecture is viable for production.

1. `cd ~/Projects/metrics_2_0/entire-poc-workspace && pwd`

2. Confirm the shell is rooted in the workspace. Do NOT `cd` into any service repo during this phase.

3. Launch Claude Code from the workspace:
   ```bash
   claude
   ```

4. Prompt the agent to make a cross-repo change (same scenario shape as earlier Entire tests):
   > I'm testing Git AI from our workspace. Please make the following change spanning both sibling repos:
   >
   > 1. Edit `../entire-poc-backend/src/api/routes/status.ts` — add a field `gitAiTest: true` to the response object returned by this route.
   > 2. Edit `../entire-poc-frontend/src/components/IngestionStatus.tsx` — display that `gitAiTest` field as a small badge somewhere in the status panel.
   > 3. Commit each repo separately:
   >    - `(cd ../entire-poc-backend && git add -A && git commit -m "test: git-ai cross-repo — backend gitAiTest field")`
   >    - `(cd ../entire-poc-frontend && git add -A && git commit -m "test: git-ai cross-repo — frontend gitAiTest display")`
   > 4. Do NOT push yet. I'll handle the push and inspection.
   >
   > Stay rooted in the workspace — edit sibling files via relative paths (`../entire-poc-backend/...` and `../entire-poc-frontend/...`), and use subshells for git operations. Do not cd into the service repos.

5. After the agent reports done, inspect each service repo's most recent commit:
   ```bash
   # Backend
   BE_LATEST=$(git -C ../entire-poc-backend rev-parse HEAD)
   echo "Backend HEAD: $BE_LATEST"
   git -C ../entire-poc-backend notes --ref=ai show "$BE_LATEST" 2>/dev/null
   git -C ../entire-poc-backend ai stats HEAD~1..HEAD --json 2>/dev/null
   
   # Frontend
   FE_LATEST=$(git -C ../entire-poc-frontend rev-parse HEAD)
   echo "Frontend HEAD: $FE_LATEST"
   git -C ../entire-poc-frontend notes --ref=ai show "$FE_LATEST" 2>/dev/null
   git -C ../entire-poc-frontend ai stats HEAD~1..HEAD --json 2>/dev/null
   ```

6. **Critical evidence capture — paste the output verbatim into the results document.**

   Specifically, for each service repo's commit:
   - Does a Git Note exist? (yes/no)
   - If yes, does it contain structured attribution data?
   - Is the agent correctly identified as `claude-code`?
   - Does `agent_lines` look plausible (non-zero, roughly matching what the agent wrote)?
   - Does the prompt_id/session reference point at anything inspectable?

7. Push the code and the notes:
   ```bash
   (cd ../entire-poc-backend && git push origin main && git push origin 'refs/notes/*:refs/notes/*')
   (cd ../entire-poc-frontend && git push origin main && git push origin 'refs/notes/*:refs/notes/*')
   ```

**Done when:** verdict is recorded for each of the two commits (pass / partial / fail per REQ-V criteria) and the raw note content is captured for later analysis.

**This phase's outcome determines whether to continue to Phase 4.** If both service-repo commits have Git Notes with valid attribution → Git AI passes the critical test, proceed. If either fails → stop and document the failure mode.

---

### Phase 4 — Extend the backend ingestion pipeline (60-90 min)

Only run this phase if Phase 3 passed.

1. **Pull Git Notes from GitHub:** The backend's existing Octokit client needs to fetch notes. GitHub API path:
   ```
   GET /repos/{owner}/{repo}/git/refs/notes%2Fai
   GET /repos/{owner}/{repo}/git/blobs/{sha}
   ```
   Or simpler: clone/fetch the notes ref via git commands invoked from the backend. Whichever pattern fits the existing code style.

2. **Add new ingestion module `src/ingestion/gitai-fetcher.ts`:**
   - Fetches `refs/notes/ai` from each of the three repos
   - For each note, gets the commit SHA it's attached to
   - Parses the note content (likely text with a known structure per Git AI Standard v3.0.0 — see below for the format)
   - Returns a list of `GitAiNoteRecord` objects

3. **Add parser `src/ingestion/gitai-parser.ts`:**
   Per the Git AI docs, note format looks roughly like (example from the Git AI docs):
   ```
   src/commands/checkpoint.rs 6e4d6f2 51-52,54,58-110,901-931,934-947
   src/git/test_utils/mod.rs 6e4d6f2 4,410-425
   ```
   Format: `<file_path> <prompt_id> <line_ranges>`
   
   Additional metadata (agent, model, etc.) may be in a header block or associated JSON. Parse what's actually there — the exact format should be inspected from real note output in Phase 3.

4. **Add DB migration:** run the `gitai_commit_attribution` table creation SQL from REQ-D.

5. **Extend the orchestrator:**
   ```typescript
   // src/ingestion/orchestrator.ts — add
   import { runGitAiIngestion } from './gitai-orchestrator.js';
   
   export async function runIngestion(): Promise<IngestionReport> {
     const entireResult = await runEntireIngestion();  // existing
     const gitaiResult = await runGitAiIngestion();    // new
     return { entire: entireResult, gitai: gitaiResult };
   }
   ```

6. **Add new routes:**
   - `src/api/routes/gitai.ts` — implements the endpoints from REQ-B-6
   - Wire into `src/api/server.ts`

7. **Tests:**
   - `tests/gitai-parser.test.ts` — parse a sample note string, verify structured output
   - `tests/gitai-orchestrator.test.ts` — mocked GitHub API, verify database writes

8. **Verify:**
   ```bash
   cd ~/Projects/metrics_2_0/entire-poc-backend
   npm test
   npm run build
   npm run lint
   ```

**Done when:** all tests pass, builds clean, and `curl -X POST http://localhost:3001/api/ingest/run` completes without errors and populates `gitai_commit_attribution`.

---

### Phase 5 — Extend the frontend (45 min)

Only run after Phase 4 succeeds.

1. Add API client methods in `src/api/client.ts`:
   ```typescript
   api.gitai = {
     commits:  () => get<GitAiCommit[]>('/api/gitai/commits'),
     commit:   (sha: string) => get<GitAiCommitDetail>(`/api/gitai/commits/${sha}`),
     summary:  () => get<GitAiSummary>('/api/gitai/summary'),
     compare:  () => get<EntireVsGitAiComparison[]>('/api/compare/entire-vs-gitai'),
   };
   ```

2. Add chart `src/components/charts/AgentPercentagePerCommit.tsx`:
   - Horizontal bar chart
   - One bar per commit
   - X-axis: agent %, 0–100
   - Y-axis: short commit label (first 7 chars of SHA + commit message prefix)
   - Color by agent (Claude Code, Cursor, Copilot, etc.)

3. Add comparison view `src/components/EntireVsGitAiComparison.tsx`:
   - Table with columns: commit SHA, repo, Entire attribution (file-level), Git AI attribution (line-level), delta
   - Makes the "what Git AI adds" case visually obvious

4. Add "Source" badge to all existing tables/lists:
   - "Entire" badge for existing rows
   - "Git AI" badge for Git AI-sourced rows

5. Wire into `Dashboard.tsx`.

6. Verify:
   ```bash
   cd ~/Projects/metrics_2_0/entire-poc-frontend
   npm run build
   npm run lint
   ```

**Done when:** the dashboard renders both the new Agent Percentage chart and the Entire vs Git AI comparison view with real data.

---

### Phase 6 — Run end-to-end validation (30 min)

1. Ensure all three services are running (backend on 3001, frontend on 5173, Git AI installed).

2. Trigger ingestion:
   ```bash
   curl -X POST http://localhost:3001/api/ingest/run | jq .
   ```

3. Inspect the database:
   ```bash
   sqlite3 ~/Projects/metrics_2_0/entire-poc-backend/data/poc.db <<'SQL'
   .headers on
   .mode column
   SELECT 'gitai_attribution' AS t, COUNT(*) AS n FROM gitai_commit_attribution;
   
   SELECT repo, COUNT(*) AS commits, 
          AVG(agent_percentage) AS avg_agent_pct,
          SUM(agent_lines) AS total_agent_lines,
          SUM(human_lines) AS total_human_lines
   FROM gitai_commit_attribution
   GROUP BY repo;
   
   SELECT agent, COUNT(*) AS commits, AVG(agent_percentage) AS avg_pct
   FROM gitai_commit_attribution
   GROUP BY agent;
   SQL
   ```

4. Query the new API endpoints:
   ```bash
   curl -s http://localhost:3001/api/gitai/summary | jq .
   curl -s http://localhost:3001/api/gitai/commits | jq '. | length'
   curl -s http://localhost:3001/api/compare/entire-vs-gitai | jq .
   ```

5. Open `http://localhost:5173`, hard-refresh, verify:
   - New Agent Percentage chart renders with data
   - Comparison view shows both sources for the same commits
   - Source badges visible

6. Sanity-check one specific commit manually:
   - Pick a recent commit SHA from Phase 3
   - In the database: is its Git AI row present with correct attribution?
   - On GitHub: does the Git Note exist?
   - In the UI: does the commit appear in the Agent Percentage chart?

**Done when:** all five checks pass with real data.

---

### Phase 7 — Document verdict (30 min)

Create `docs/GITAI-VALIDATION-RESULTS.md` in the workspace repo. Include:

1. **Summary:** Git AI validated / partially validated / not validated, with one-sentence justification
2. **Installation experience:** smooth / rough, with notes
3. **Single-repo smoke test result:** pass / fail, with Git Note content
4. **Cross-repo test result (Phase 3 — the critical test):** pass / fail, with Git Note content from both service-repo commits
5. **Attribution accuracy:** verify on a commit you know the provenance of, compare to Git AI's claim
6. **Data model and pipeline:** what was built, what works
7. **Side-by-side with Entire Pattern A*:** table showing same commits through both lenses
8. **Recommendation:** adopt Git AI / keep investigating / reject
9. **Production rollout implications for the real 60-repo GitLab workspace:** what would need to change

Commit and push to the workspace repo.

---

## 7. Hard rules for the implementer

- **Do NOT remove Entire from the workspace.** This validation runs both tools in parallel. Entire data preserves the earlier baseline for comparison.
- **Do NOT modify the existing Pattern A* ingestion code.** Add Git AI ingestion alongside it; do not refactor the two together.
- **Do NOT force the agent to call `git-ai checkpoint` in the test prompts.** That's exactly what this validation must verify happens automatically — forcing it would defeat the test.
- **Do NOT skip Phase 2.** The single-repo smoke test is the prerequisite check before the workspace test. Running Phase 3 without knowing Phase 2 works produces ambiguous failure signals.
- **DO preserve the location-discipline in Phase 3.** Stay rooted in workspace, use subshells for git operations. The cross-repo nature of the test depends on this.
- **DO capture raw Git Note content** in the results document. The exact format and contents of Git AI's notes are the single most important piece of evidence for any subsequent discussion with the Git AI community or internal stakeholders.
- **DO restart VS Code and terminal sessions** after installing Git AI. The docs explicitly call this out, and forgetting it is the most common reason the first test looks like a failure.

---

## 8. Expected artifact inventory

On completion, the workspace repo contains:

- `docs/GITAI-VALIDATION-SPEC.md` — this document
- `docs/GITAI-VALIDATION-RESULTS.md` — outcome document written in Phase 7
- `scripts/install-gitai.sh` — wrapper around the Git AI install command (thin, for reproducibility)
- `scripts/inspect-gitai-notes.sh` — diagnostic helper to dump Git Notes from all three repos

The backend repo contains:

- `src/ingestion/gitai-fetcher.ts`
- `src/ingestion/gitai-parser.ts`
- `src/ingestion/gitai-orchestrator.ts`
- `src/api/routes/gitai.ts`
- `src/db/migrations/` — new migration for `gitai_commit_attribution`
- `tests/gitai-parser.test.ts`
- `tests/gitai-orchestrator.test.ts`

The frontend repo contains:

- `src/components/charts/AgentPercentagePerCommit.tsx`
- `src/components/EntireVsGitAiComparison.tsx`
- Minor updates to `Dashboard.tsx`, `src/api/client.ts`

---

## 9. Risks and mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Git AI install breaks existing Git commands | Low | Phase 1 explicitly verifies `git status` / `git log` after install; rollback = uninstall Git AI per its docs |
| Claude Code hooks don't fire without VS Code restart | High | Phase 1 step 8 mandates restart; documented in Git AI docs |
| Cross-repo test fails (Phase 3) — Git AI has same limitation as Entire | Medium | Validation is designed to discover this — document, then fall back to evaluating self-built solution using Cursor Agent Trace spec |
| Git Notes format changes between Git AI versions | Low | Pin Git AI version in install script; document the version in the results doc |
| GitHub API rate limit during ingestion | Low | Use authenticated requests (5000/h); ingestion is small-volume |
| Git AI and Entire conflict on same commit | Medium | They write to different notes refs (`refs/notes/ai` vs Entire's checkpoint branch); should not collide, but document any conflicts observed |
| Agent doesn't call `git-ai checkpoint` automatically | Medium | Phase 2 smoke test catches this; if Claude Code integration isn't working, try Cursor or Codex to isolate the issue to one agent |

---

## 10. Definition of done

The validation is complete and the final recommendation can be made when:

1. All phases 0–7 have been executed
2. `docs/GITAI-VALIDATION-RESULTS.md` is filled in and committed
3. Both existing (Entire) and new (Git AI) data are visible on the dashboard
4. For at least one specific cross-repo session, line-level attribution exists in the database and maps correctly to the actual agent-written lines in the commits
5. A clear go/no-go recommendation is written with evidence backing it

The recommendation informs the production decision: **adopt Git AI for the real 60-repo workspace** (GO), or **reject Git AI and investigate remaining options** (STOP).

---

## 11. Glossary

- **Git AI** — Apache 2.0 open-source Git extension from the `git-ai-project` GitHub org, providing line-level AI code attribution via Git Notes
- **Git AI Standard v3.0.0** — the open format specification for AI attribution in Git Notes
- **Cursor Agent Trace** — competing open specification from Cursor (v0.1.0, Jan 2026) for the same problem; not used in this validation but worth knowing
- **Git Notes** — a native Git feature for attaching metadata to commits without modifying the commits themselves; stored in `refs/notes/*`
- **Pattern A*** — our current working Entire setup (workspace-only enablement + transcript-first ingestion)
- **Workspace hub** — the non-application-code root folder where developers launch agents from (`_wod.workspace/` in production, `entire-poc-workspace/` in the PoC)
- **Service repo** — a sibling Git repo containing actual application code that agents edit (`wod.*` / `auth.*` / etc. in production, `entire-poc-backend` / `entire-poc-frontend` in the PoC)
- **Cross-repo hub-launched session** — an agent session started in the workspace that edits files in sibling service repos during the same session; the critical architectural case this validation must verify
