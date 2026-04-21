# Requirements Specification — Entire Workspace Pattern C Validation Project

## 1. Document purpose

This document specifies the **functional and non-functional requirements** for a proof-of-concept system that validates whether Entire IO can be operated in a "hybrid Pattern C" deployment across a multi-repo workspace. It is the input to a separate Architecture & Implementation Specification that describes how the requirements are met.

The proof-of-concept must produce a clear, evidence-based answer to the question: *"Can we adopt Entire IO Pattern C as the AI session capture layer for our real workspace, or do we need a different approach?"*

This document is intended to be handed to Claude Code (or any competent implementer) and acted on without further clarification.

---

## 2. Background and motivation

### 2.1 The real-world setup we are simulating

Our production workspace is a VS Code multi-root workspace containing:
- One **hub folder** (`_wod.workspace/`) — holds skills, BMad workflows, MCP configs, agent settings, shared documentation. Not an application repo.
- ~60 **independent GitLab repositories** organized into domain folders (`wod/`, `auth/`, `core/`, `cm/`, `taxart/`, `procurement/`, `ai/`, `qa/`).
- Developers launch AI coding agents (Claude Code, Cursor, Codex) **from the workspace hub**; the agents edit files in sibling service repos; commits happen inside each service repo.

### 2.2 The Entire IO architectural mismatch

Entire IO is repo-scoped: it expects the agent session and the `git commit` to happen in the same repo. In our setup they don't. The Entire team confirmed (Discord, April 2026) that hub-launched cross-repo sessions are not natively supported and suggested per-repo worktrees as a workaround — which would force a significant developer behavior change.

### 2.3 The hypothesis to test

**Pattern C (Hybrid):** enable Entire in both the workspace hub and in every service repo. Capture central transcripts from the workspace, line-level attribution from each service repo, and join them server-side by `session_id` + timestamps + files-touched overlap.

If Pattern C produces a coherent, queryable data model in practice, we adopt it for the real workspace. If it produces gaps (orphaned sessions, broken joins, missing attribution) we cannot work around, we explore alternatives — Git AI as the most likely fallback, or a session-attach wrapper as Plan B (see Section 13).

### 2.4 Why a separate proof-of-concept

The real workspace contains years of Git history we cannot risk corrupting with experimental hooks, agent configurations, or branch pushes. We replicate the **architectural shape** of the real workspace in a clean, disposable test environment under a personal GitHub account. This allows aggressive experimentation without affecting production code.

---

## 3. In-scope vs out-of-scope

### 3.1 In scope

- Three brand-new GitHub repositories that mirror the architectural shape of the real workspace (one hub + one frontend service + one backend service).
- Sample applications in the frontend and backend repos with enough realism to allow meaningful AI agent sessions that span both.
- Full Entire Pattern C setup: workspace-level Entire enablement, per-service-repo Entire enablement, scheduled `entire doctor` cleanup, automatic session-attach wrapper as Plan B.
- A working backend ingestion service that reads `entire/checkpoints/v1` branches from all three repos, parses transcripts, and produces a unified data model.
- A frontend dashboard that visualizes a meaningful subset of the agreed metrics (charts 1, 4, 14, 21, 25, 26 from the existing catalog — see Section 8).
- Documented validation criteria and test scenarios.
- All code, scripts, configuration, and documentation pushed to public GitHub repos under the implementer's account.

### 3.2 Out of scope

- Production deployment to any cloud provider beyond local development.
- Authentication / authorization on the dashboard or backend API.
- Multi-tenancy.
- Migration tooling for the real production workspace.
- Performance tuning beyond what is needed for a 1-developer, ~50-session validation dataset.
- Anything involving the real GitLab workspace or its 60 repos.

---

## 4. Test scenario design

### 4.1 The three test repositories

The PoC creates three repositories under the implementer's personal GitHub account, deliberately mirroring the real workspace structure at small scale:

| Repo name suggestion | Role | Maps to real-workspace concept |
|---|---|---|
| `entire-poc-workspace` | Hub | `_wod.workspace/` — agent launch point, no app code |
| `entire-poc-frontend` | Frontend service repo | A `wod.*.webApp` style React app |
| `entire-poc-backend` | Backend service repo | A `wod.*.api` style Node.js API |

The implementer may rename these but must keep the three-repo, hub-plus-two-service-repos shape.

### 4.2 Application idea — "AI Metrics Mini Dashboard"

The application built across the frontend and backend repos is itself an AI metrics dashboard, scaled down. This is intentional: it gives the validation a meta-quality (we measure AI productivity using a tool built with AI assistance, captured by the very system under test) and lets us reuse chart definitions from the existing main project.

**Backend (`entire-poc-backend`)** — Node.js + TypeScript:
- REST API that serves AI metrics data
- Ingestion service that reads `entire/checkpoints/v1` branches from all three test repos via the GitHub API, parses the contained `metadata.json` and `full.jsonl` files, and writes normalized records into a SQLite database
- Endpoints serving aggregated metrics for a defined chart set
- Scheduled job (or manual trigger endpoint) that re-runs ingestion

**Frontend (`entire-poc-frontend`)** — React + TypeScript + Vite:
- Single-page dashboard
- Fetches metrics from the backend API
- Renders six charts using a charting library (Chart.js, lightweight-charts, or Recharts — implementer's choice)
- One "ingestion status" panel showing last ingestion time, repo coverage, session count

**Workspace (`entire-poc-workspace`)** — no application code:
- VS Code multi-root workspace file (`.code-workspace`) that includes all three repos
- Shared skills / BMad-style configurations
- Entire setup configuration committed
- Helper scripts for bootstrap, onboarding, ingestion triggers
- Documentation

### 4.3 Test session scenarios to exercise

The validation runs a defined set of agent sessions designed to stress every code path of the Pattern C model. These must be runnable as a documented manual playbook (Section 11) and produce predictable, verifiable outcomes.

| Scenario | What it tests |
|---|---|
| Single-repo session (backend only) | Baseline — does Entire capture line-level attribution per commit when used the "intended" way |
| Single-repo session (frontend only) | Same baseline on a different agent + framework |
| Cross-repo session (backend + frontend in one session) | The actual Pattern C use case — does the join logic work |
| Three-repo session (workspace + backend + frontend) | Edge case — sessions that touch the hub itself |
| Long-running session crossing multiple commits | Tests session-state continuity and `entire doctor` cleanup |
| Session that crashes mid-flow (manual kill) | Tests orphaned-session handling and the Plan B attach wrapper |

---

## 5. Functional requirements

### 5.1 Workspace setup requirements (FR-W)

- **FR-W-1.** A `setup-workspace.sh` script that initializes Entire in the workspace repo with auto-summarize enabled.
- **FR-W-2.** A `bootstrap-services.sh` script that enables Entire in both service repos and copies a shared template `.entire/settings.json`.
- **FR-W-3.** A `dev-onboard.sh` script that installs local Git hooks in all three repos and (on first run only) registers the scheduled `entire doctor` job.
- **FR-W-4.** A `commit-entire-config.sh` script that commits and pushes Entire configuration files in each service repo (after the bootstrap creates them).
- **FR-W-5.** A scheduled task (cron on macOS/Linux, Task Scheduler on Windows) that runs `entire doctor --force` in the workspace every 4 hours.
- **FR-W-6.** A VS Code workspace file (`entire-poc.code-workspace`) that opens all three repos as a multi-root workspace.

### 5.2 Backend service requirements (FR-B)

- **FR-B-1.** Ingestion: reads `entire/checkpoints/v1` from all three configured GitHub repos via the GitHub REST API.
- **FR-B-2.** Parsing: handles `metadata.json` (per-checkpoint metadata) and `full.jsonl` (per-session event stream) from each checkpoint folder.
- **FR-B-3.** Path-to-repo resolution: strips machine-specific prefixes from absolute file paths in `full.jsonl` events and maps the relative path to one of the three known repos.
- **FR-B-4.** Session join logic: implements the four-table data model described in Section 7 with confidence flags (HIGH / MEDIUM / LOW) on cross-repo session-to-commit links.
- **FR-B-5.** Idempotency: re-ingesting the same checkpoint produces the same result with no duplicates.
- **FR-B-6.** Storage: SQLite database file under `entire-poc-backend/data/poc.db`. No external database required.
- **FR-B-7.** REST API: documented endpoints serving the chart data sets defined in Section 8.
- **FR-B-8.** Manual trigger endpoint: `POST /api/ingest/run` to force a re-ingestion outside the schedule.
- **FR-B-9.** Status endpoint: `GET /api/status` returning last ingestion time, repos covered, total sessions ingested, total checkpoints, total commits linked.
- **FR-B-10.** Logging: structured JSON logs of every ingestion run with counts of new vs updated records.

### 5.3 Frontend dashboard requirements (FR-F)

- **FR-F-1.** Fetches all chart data from the backend API on page load.
- **FR-F-2.** Renders the six charts defined in Section 8.
- **FR-F-3.** Displays an "Ingestion Status" panel sourced from `GET /api/status`.
- **FR-F-4.** Provides a "Refresh" button that calls `POST /api/ingest/run` and re-fetches.
- **FR-F-5.** Visibly indicates the **confidence flag** on cross-repo joined data — for example, a HIGH/MEDIUM/LOW badge on session-to-commit links displayed in any drill-down view.
- **FR-F-6.** Responsive enough to display correctly at 1280×800 in a developer's browser. No mobile design required.

### 5.4 Plan B — Session-attach wrapper requirements (FR-A)

The session-attach wrapper is the fallback mechanism that makes session linkage automatic, in case `entire doctor` and the natural `entire attach` flow prove insufficient.

- **FR-A-1.** A wrapper script `entire-attach-watcher.sh` that runs as a background process on the developer's machine.
- **FR-A-2.** Watches the agent's transcript directory (e.g. `~/.claude/projects/<project>/`) for new sessions.
- **FR-A-3.** When a new commit is detected in any of the three monitored repos, runs `entire attach <session-id> -a <agent> -f` in that repo, linking the most recently active session.
- **FR-A-4.** Maintains a local state file (`~/.entire-poc/session-state.json`) tracking which sessions have been attached to which commits, to ensure idempotency.
- **FR-A-5.** Provides a manual-mode subcommand that lists detected sessions and prompts the developer to confirm the link before attaching.
- **FR-A-6.** Logs all attach decisions and outcomes to `~/.entire-poc/attach.log`.
- **FR-A-7.** Documented as **opt-in** for the validation phase. Plan A (workspace + per-repo + `entire doctor`) is tested first; the wrapper is enabled and re-tested only if Plan A produces unacceptable join confidence.

---

## 6. Non-functional requirements

### 6.1 Operational

- **NFR-O-1.** All scripts must be POSIX-shell compatible (bash 4+) for macOS and Linux. A separate PowerShell version of the cron-equivalent task is provided for Windows developers.
- **NFR-O-2.** No external service dependencies beyond GitHub (no AWS, no Docker required for basic operation; Docker Compose may be used for orchestration but must be optional).
- **NFR-O-3.** Total disk footprint for the PoC including all three repos, dependencies, and SQLite database: under 1 GB.
- **NFR-O-4.** Backend startup time: under 5 seconds.
- **NFR-O-5.** End-to-end ingestion time for the validation dataset (~50 sessions across 3 repos): under 60 seconds.

### 6.2 Code quality

- **NFR-Q-1.** TypeScript with strict mode enabled in both frontend and backend.
- **NFR-Q-2.** ESLint and Prettier configured and passing.
- **NFR-Q-3.** Backend has unit tests for the path-to-repo resolution function and the session-join logic. Coverage target: >70% on those specific modules.
- **NFR-Q-4.** Each repo has a README with setup, run, and test instructions.

### 6.3 Documentation

- **NFR-D-1.** Each of the three repos has its own README covering setup, configuration, and usage.
- **NFR-D-2.** The workspace repo also contains a top-level `VALIDATION-PLAYBOOK.md` (see Section 11) and a `RESULTS-TEMPLATE.md` for recording test outcomes.
- **NFR-D-3.** The Architecture & Implementation Specification (the companion document to this one) is committed under `entire-poc-workspace/docs/`.

### 6.4 Security and privacy

- **NFR-S-1.** No secrets committed. GitHub tokens used by the backend are read from `.env` files which are `.gitignore`'d.
- **NFR-S-2.** Auto-summarize is enabled, but the implementer must review at least one generated summary to ensure no sensitive content from prompts leaks into committed files.

---

## 7. Data model requirements

The backend database stores data in a four-table model based on the Pattern C design:

### Table: `sessions`

| Column | Type | Notes |
|---|---|---|
| `session_id` | TEXT PRIMARY KEY | Stable session identifier from Entire transcript |
| `workspace_checkpoint_id` | TEXT | Checkpoint ID where the central transcript landed (nullable) |
| `started_at` | TIMESTAMP | First event timestamp in `full.jsonl` |
| `ended_at` | TIMESTAMP | Last event timestamp in `full.jsonl` |
| `agent` | TEXT | `claude-code`, `cursor`, `codex`, etc. |
| `model` | TEXT | Detected model name from the transcript |
| `total_input_tokens` | INTEGER | Summed from token usage events |
| `total_output_tokens` | INTEGER | Same |
| `total_cache_read_tokens` | INTEGER | Same |
| `friction_count` | INTEGER | Length of `summary.friction[]` |
| `open_items_count` | INTEGER | Length of `summary.open_items[]` |
| `learnings_json` | TEXT (JSON) | Full `summary.learnings` object as JSON string |
| `friction_json` | TEXT (JSON) | Full `summary.friction[]` as JSON string |
| `open_items_json` | TEXT (JSON) | Full `summary.open_items[]` as JSON string |
| `raw_metadata_path` | TEXT | Path back to the source `metadata.json` for debugging |

### Table: `session_repo_touches`

Derived from parsing absolute file paths in the workspace transcript.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `session_id` | TEXT | FK → `sessions.session_id` |
| `repo` | TEXT | One of the three known repo names |
| `files_touched_json` | TEXT (JSON) | List of file paths within that repo |
| `tool_calls_json` | TEXT (JSON) | Map of tool name → count (Read, Edit, Write, Bash, Skill, Task, etc.) |
| `slash_commands_json` | TEXT (JSON) | List of slash commands invoked in that session |
| `subagent_count` | INTEGER | Number of Task subagent spawns |
| UNIQUE (session_id, repo) | | One row per session per repo touched |

### Table: `repo_checkpoints`

From service-repo `entire/checkpoints/v1` branches.

| Column | Type | Notes |
|---|---|---|
| `repo` | TEXT | |
| `checkpoint_id` | TEXT | |
| `commit_sha` | TEXT | The commit the checkpoint was attached to |
| `committed_at` | TIMESTAMP | Commit timestamp |
| `agent_percentage` | REAL | From metadata, may be NULL if line-level attribution missing |
| `agent_lines` | INTEGER | Same |
| `human_added` | INTEGER | Same |
| `human_modified` | INTEGER | Same |
| `human_removed` | INTEGER | Same |
| `files_touched_json` | TEXT (JSON) | List of file paths in this commit |
| `session_id_in_metadata` | TEXT | Session ID found in this checkpoint's metadata, if any |
| PRIMARY KEY (repo, checkpoint_id) | | |

### Table: `session_commit_links`

The derived join — the heart of the validation.

| Column | Type | Notes |
|---|---|---|
| `id` | INTEGER PRIMARY KEY | Auto-increment |
| `session_id` | TEXT | FK → `sessions.session_id` |
| `repo` | TEXT | |
| `checkpoint_id` | TEXT | FK → `repo_checkpoints.checkpoint_id` |
| `confidence` | TEXT | `HIGH`, `MEDIUM`, `LOW` |
| `join_reason` | TEXT | `session_id_match`, `timestamp_files_overlap`, `fallback` |
| `confidence_score` | REAL | 0.0–1.0 numeric for ranking |
| `created_at` | TIMESTAMP | |

**Confidence rules:**
- `HIGH`: `repo_checkpoints.session_id_in_metadata` exactly equals `sessions.session_id`
- `MEDIUM`: timestamps overlap within ±5 minutes AND ≥1 file touched in the commit appears in the workspace transcript's `filePath` events for that session
- `LOW`: timestamps overlap within ±15 minutes only, no file overlap

---

## 8. Charts to implement

The frontend dashboard implements **six charts** drawn from the existing catalog. These are deliberately chosen to exercise different parts of the data model — if all six render with sensible data, the Pattern C model is working end-to-end.

| # | Chart | Data source in the model | Validates |
|---|---|---|---|
| 1 | **Sessions Over Time** | `sessions.started_at` bucketed by day | Basic ingestion works |
| 4 | **Agent % per Commit** | `repo_checkpoints.agent_percentage` | Per-repo line-level attribution captured |
| 14 | **Slash Command Frequency** | Aggregated from `session_repo_touches.slash_commands_json` | Workspace transcript is being read |
| 21 | **Tool Usage Mix** | Aggregated from `session_repo_touches.tool_calls_json` | Tool-call events are being captured |
| 25 | **Friction per Session** | `sessions.friction_count` + `sessions.friction_json` | Auto-summarize is working |
| 26 | **Open Items per Session** | `sessions.open_items_count` + `sessions.open_items_json` | Same |

A seventh **"Cross-Repo Session Map"** view is required (not strictly a chart): a table or sankey diagram showing each session, the repos it touched, and the commits it produced — with confidence flags. This is the most important visualization for validating the join.

---

## 9. API specification

### Endpoints the backend must expose

| Method | Path | Purpose | Response shape |
|---|---|---|---|
| GET | `/api/status` | Ingestion status | `{ lastRun, repos, sessionCount, checkpointCount, linkCount }` |
| POST | `/api/ingest/run` | Trigger re-ingestion | `{ jobId, startedAt }` |
| GET | `/api/charts/sessions-over-time` | Chart 1 | `[{ date, count }]` |
| GET | `/api/charts/agent-percentage` | Chart 4 | `[{ commit, repo, agentPercentage, committedAt }]` |
| GET | `/api/charts/slash-commands` | Chart 14 | `[{ command, count }]` |
| GET | `/api/charts/tool-usage` | Chart 21 | `[{ tool, count }]` |
| GET | `/api/charts/friction` | Chart 25 | `[{ sessionId, count, items[] }]` |
| GET | `/api/charts/open-items` | Chart 26 | `[{ sessionId, count, items[] }]` |
| GET | `/api/sessions/:sessionId` | Session drill-down with linked commits | Full session record + links + confidence |
| GET | `/api/sessions/cross-repo` | "Cross-Repo Session Map" data | `[{ sessionId, repos[], commits[], confidence }]` |

All responses are JSON. CORS is open for local development.

---

## 10. Validation criteria

The PoC is judged successful if **all** of the following hold after running the test scenarios in Section 11:

### 10.1 Hard pass criteria (all required)

- **VC-1.** Single-repo sessions produce checkpoints with line-level attribution (`agent_percentage` non-null, `agent_lines` > 0) on the corresponding service repo's branch.
- **VC-2.** Cross-repo sessions produce **at least one** entry in the workspace's `entire/checkpoints/v1` branch containing the full transcript with `filePath` events spanning multiple repos.
- **VC-3.** The backend successfully ingests data from all three repos' checkpoint branches without crashes or skipped records.
- **VC-4.** The path-to-repo resolution function correctly identifies the originating repo for every file path in the test dataset (validated with unit tests).
- **VC-5.** All six charts render with data on the frontend.

### 10.2 Soft pass criteria (graceful degradation acceptable)

- **VC-6.** At least 70% of cross-repo session-to-commit links resolve at HIGH or MEDIUM confidence. LOW confidence on the remaining 30% is acceptable but documented.
- **VC-7.** The `entire doctor --force` scheduled job successfully condenses all orphaned sessions from cross-repo and crashed-session test scenarios.
- **VC-8.** Auto-summarize produces non-empty `summary.friction` or `summary.open_items` for at least 50% of sessions.

### 10.3 Failure modes that trigger Plan B

- **FM-1.** If VC-2 fails (workspace transcripts don't contain cross-repo `filePath` entries), Plan B (attach wrapper) is enabled and tests are re-run.
- **FM-2.** If VC-6 fails consistently (most cross-repo joins are LOW confidence), Plan B is enabled.
- **FM-3.** If Plan B re-runs still fail VC-2 or VC-6, the conclusion is documented as **"Pattern C is not viable; recommend Git AI evaluation."**

### 10.4 Outcomes that trigger a re-design

- **OD-1.** If Entire's hooks produce different `session_id` values for the same logical session in different repos (i.e., session ID is per-repo, not global), the entire join model needs to be rebuilt around timestamps + file overlap only. This must be explicitly tested for as part of VC-1 / VC-2.

---

## 11. Validation playbook (handed off as a test runner)

The implementer must produce a `VALIDATION-PLAYBOOK.md` in the workspace repo containing **runnable, step-by-step test instructions** with expected outcomes for each scenario. Format:

```
## Scenario N — <name>

### Setup
<exact commands to run>

### Steps
1. <action>
2. <action>
...

### Expected outcome
- <observable 1>
- <observable 2>

### Recording results
- Pass / Fail (circle one)
- Confidence flags observed:
- Notes:
```

The companion `RESULTS-TEMPLATE.md` is filled in during validation and committed back to the workspace repo as the official record.

---

## 12. Deliverable inventory

The implementation must produce:

### Repositories (3 separate GitHub repos)

1. `entire-poc-workspace` — public, contains:
   - `.code-workspace` file
   - `.entire/settings.json` (workspace config)
   - `.claude/settings.json` (committed agent hooks)
   - `scripts/setup-workspace.sh`
   - `scripts/bootstrap-services.sh`
   - `scripts/commit-entire-config.sh`
   - `scripts/dev-onboard.sh`
   - `scripts/entire-attach-watcher.sh` (Plan B)
   - `scripts/install-cron.sh` (macOS/Linux)
   - `scripts/install-task.ps1` (Windows)
   - `templates/entire-service-settings.json`
   - `docs/REQUIREMENTS.md` (this document)
   - `docs/ARCHITECTURE.md` (companion document)
   - `docs/VALIDATION-PLAYBOOK.md`
   - `docs/RESULTS-TEMPLATE.md`
   - `README.md`

2. `entire-poc-backend` — public, contains:
   - Node.js + TypeScript service
   - `src/ingestion/` — GitHub fetch, parse, store
   - `src/api/` — REST endpoints
   - `src/db/` — SQLite schema and queries
   - `src/utils/path-resolver.ts` — path-to-repo resolution
   - `src/utils/session-joiner.ts` — confidence-flagged join logic
   - `tests/` — unit tests
   - `.entire/settings.json` (per-service template)
   - `package.json`, `tsconfig.json`, ESLint config
   - `README.md`

3. `entire-poc-frontend` — public, contains:
   - React + TypeScript + Vite app
   - `src/components/charts/` — chart components
   - `src/components/CrossRepoSessionMap.tsx`
   - `src/components/IngestionStatus.tsx`
   - `src/api/client.ts` — backend client
   - `.entire/settings.json` (per-service template)
   - `package.json`, `tsconfig.json`, ESLint config
   - `README.md`

### Documentation deliverables

- `docs/REQUIREMENTS.md` — this document, committed verbatim
- `docs/ARCHITECTURE.md` — companion architecture spec
- `docs/VALIDATION-PLAYBOOK.md` — runnable test scenarios
- `docs/RESULTS-TEMPLATE.md` — outcome record
- `docs/CONCLUSIONS.md` — written after validation, summarizing what was learned and the go/no-go decision

---

## 13. Plan B detail — automatic session-attach wrapper

If Plan A (workspace + per-repo + `entire doctor`) fails the validation criteria, a wrapper that **automatically calls `entire attach` after every commit** is implemented and re-tested.

### How it works

1. The wrapper runs as a background watcher process started by the developer (or by a Git pre-commit hook chain).
2. It maintains a state file recording the most recently active agent session ID.
3. It registers a per-repo `post-commit` Git hook in each service repo that, on every commit, calls:
   ```
   entire attach <last-active-session-id> -a <agent> -f
   ```
4. This forcibly links the agent session to the just-made commit, creating a HIGH-confidence row in `session_commit_links` because the session ID is now embedded in the checkpoint metadata.

### Why this is Plan B, not Plan A

- It adds a moving part (the wrapper process) that can fail silently
- It introduces ordering assumptions ("most recently active session") that may be wrong if multiple agents are running
- It wraps Entire's intended behavior rather than using it as designed

But it gives us a fallback if Pattern C without the wrapper produces unacceptable join quality.

### Conclusion

After the validation playbook is completed (with or without Plan B), `docs/CONCLUSIONS.md` records:
1. Which scenarios passed / failed
2. Whether Plan B was needed
3. Final recommendation: **adopt Pattern C for production**, **evaluate Git AI as alternative**, or **build a custom solution**

---

## 14. Glossary

- **Workspace** — the hub folder where developers launch AI agents from
- **Service repo** — a sibling GitLab/GitHub repo containing actual application code
- **Hub-launched session** — an agent session started in the workspace folder that goes on to edit files in service repos
- **Pattern C** — Entire enabled in workspace AND all service repos, joined server-side
- **Plan B** — automatic session-attach wrapper as fallback when Pattern C joins are unreliable
- **HIGH/MEDIUM/LOW confidence** — quality grading of cross-repo session-to-commit links
- **Checkpoint** — Entire's atomic unit of captured session data, addressed by `checkpoint_id`
- **`entire/checkpoints/v1`** — the Git branch where Entire stores all checkpoint data
- **`entire doctor`** — Entire's command for cleaning up stuck or orphaned sessions
- **`entire attach`** — Entire's command for retroactively linking a session transcript to a commit
