# Pattern A* Migration & Validation Prompt

You are continuing work on the Entire IO Pattern C validation PoC. The previous validation run (see `docs/RESULTS-TEMPLATE.md` and `docs/CONCLUSIONS.md`) revealed that **Pattern C as originally designed does not work** in the cross-repo workspace scenario — but it also revealed that the workspace transcript alone captures everything needed for almost all dashboard metrics.

This prompt directs you to migrate the PoC to **Pattern A\*** — workspace-only Entire enablement with transcript-first ingestion — and re-validate that it works end-to-end.

---

## Why this migration is happening

Read this carefully. The reasoning matters because some of the changes below will look like they're throwing away working code. They're not — they're throwing away code that *appeared* to work but was never producing useful data.

### Findings from the previous validation

1. **Workspace captured cross-repo file paths perfectly.** A single session's `full.jsonl` contained 5 backend file paths and 4 frontend file paths. This is the foundation Pattern C needs.

2. **Service repos produced ZERO checkpoints.** Even though Entire was enabled in `entire-poc-backend` and `entire-poc-frontend`, no checkpoints landed on their `entire/checkpoints/v1` branches when commits happened via subshell from a workspace-rooted agent session. The per-repo enablement was decorative, not functional.

3. **The ingestion pipeline created 0 `session_repo_touches` and 0 `session_commit_links`** because it was waiting for per-repo checkpoints that never appeared. It never tried the obvious fallback of deriving repo attribution from the workspace transcript's `filePath` events.

4. **Auto-summarize works.** The session metadata had structured `friction` (2 items), `open_items` (3 items), and `learnings` (repo/code/workflow). No changes needed there.

### What we're doing about it

- **Remove Entire from the two service repos entirely.** They were doing nothing useful. Their `.entire/` and committed `.claude/settings.json` files are just noise.
- **Modify the ingestion pipeline** to derive `session_repo_touches` and `session_commit_links` directly from the workspace transcript's `filePath` events, matched against actual commit history in the service repos via the GitHub API.
- **Re-run scenarios 3, 4, 5** (the cross-repo ones) to confirm the new ingestion produces meaningful data.
- **Document that Pattern A\* is the production recommendation** based on the new evidence.

---

## Hard rules

1. **Do NOT touch the workspace's Entire setup.** `entire-poc-workspace/.entire/`, `.claude/settings.json`, the cron job — all stay exactly as they are.

2. **Do NOT modify any file under `entire-poc-workspace/scripts/` or `entire-poc-workspace/docs/`** during validation runs. The only doc files you write to are `RESULTS-TEMPLATE.md` and `CONCLUSIONS.md` at the very end. The new helper scripts you create go under `scripts/` (allowed) but you only create them in Phase 1 of this prompt, not during the re-validation phase.

3. **You MUST remain rooted in `entire-poc-workspace/`** during the re-validation scenarios in Phase 4. The same location-discipline rules from the previous playbook apply: use `(cd ../sibling && git ...)` subshells for git operations, never `cd` your shell into a service repo for the cross-repo scenarios.

4. **For Phase 1 (cleanup) and Phase 3 (verification of cleanup)**, you DO need to operate in the service repos. That's expected. After Phase 3 completes, return to the workspace and stay there.

5. **Note all commit SHAs** as you go. They go into the final results record.

---

## Phase 1 — Remove Entire from the two service repos

### Why
The previous validation confirmed these enablements produced no useful data. Removing them simplifies the system, eliminates dead configuration files, and proves that workspace-only is genuinely sufficient.

### Steps for `entire-poc-backend`

1. `cd ../entire-poc-backend && pwd` — confirm location
2. Run: `entire disable --uninstall`
   - This removes the local `.git/hooks/` files Entire installed
   - It also removes Entire's references in `.claude/settings.json`
3. Manually remove the `.entire/` directory (if it still exists after disable):
   ```
   rm -rf .entire
   ```
4. Verify what changed: `git status`
5. Stage the cleanup:
   ```
   git add -A
   git commit -m "chore: remove Entire IO config — workspace-only capture per Pattern A*"
   git push origin main
   ```
6. Note the commit SHA: `git log -1 --oneline`

### Steps for `entire-poc-frontend`

Repeat exactly the same steps for the frontend repo:

1. `cd ../entire-poc-frontend && pwd`
2. `entire disable --uninstall`
3. `rm -rf .entire`
4. `git status`
5. Commit and push with the same message
6. Note the commit SHA

### Pass criteria for Phase 1

- Both service repos no longer contain `.entire/` directories
- `entire status` run inside either service repo reports "not enabled" (or the equivalent error)
- The commits are pushed to GitHub
- Local `.git/hooks/post-commit`, `.git/hooks/pre-push`, `.git/hooks/prepare-commit-msg` in the service repos are gone (or no longer reference `entire`)

### Return to workspace

After both service repos are cleaned up:
```
cd ../entire-poc-workspace && pwd
```

Confirm `pwd` ends with `entire-poc-workspace`. Do not proceed to Phase 2 if it doesn't.

---

## Phase 2 — Modify the backend ingestion pipeline

### Why
The current ingestion expects `repo_checkpoints` rows to exist for service repos so it can join sessions to commits. Since service repos no longer produce checkpoints (and never did, in this workflow), the join layer needs to derive everything from the workspace transcript instead.

### What you're changing

The ingestion pipeline currently does roughly:

```
for each repo:
  fetch entire/checkpoints/v1
  parse metadata + jsonl
  insert into sessions, repo_checkpoints
join sessions × repo_checkpoints → session_commit_links
```

The new pipeline does:

```
fetch workspace's entire/checkpoints/v1 only
parse metadata + jsonl
insert into sessions
for each event in jsonl:
  resolve filePath → repo name
  accumulate per-session, per-repo touches → session_repo_touches
for each session:
  for each repo touched:
    fetch service repo's git log via GitHub API for the session window (±15 min)
    for each commit in window where files-touched overlaps with session's files-touched in that repo:
      create session_commit_links row with MEDIUM confidence
```

### Files to modify in `entire-poc-backend/src/`

You will need to read the existing code to know exact paths, but expect to touch:

- `src/ingestion/orchestrator.ts` — change loop structure to process workspace only
- `src/ingestion/jsonl-parser.ts` — extend to extract `filePath` events into a per-repo accumulator
- `src/domain/session-joiner.ts` — replace the existing logic with the new transcript-first approach
- `src/ingestion/github-client.ts` — add a method to fetch git log + per-commit file lists for a service repo within a time window
- `src/db/schema.sql` — no schema changes needed, but `repo_checkpoints` will be empty for service repos by design
- `src/api/routes/sessions.ts` — the `/api/sessions/cross-repo` endpoint logic may need adjustment to query against the new `session_repo_touches` data structure

### Specific implementation details

**Path resolution:**
The function `resolveRepoFromAbsolutePath` in `src/domain/path-resolver.ts` already exists and works. Reuse it. Known repos: `entire-poc-workspace`, `entire-poc-backend`, `entire-poc-frontend`.

**Tool-call extraction:**
For each session in the workspace transcript, build a per-repo summary:
```typescript
type SessionRepoTouch = {
  sessionId: string;
  repo: string;
  filesTouched: string[];          // unique relative paths
  toolCalls: Record<string, number>; // tool name → count
  slashCommands: string[];          // unique slash commands invoked
  subagentCount: number;            // count of Task tool invocations
};
```
Iterate `full.jsonl` events. For each event with a `filePath`, resolve to repo and accumulate. For tool_use events without filePath (Bash, Skill, Task, Grep, Glob, WebSearch), bucket those at the workspace level.

**Confidence logic for the new joiner:**
Since `session_id` from the workspace transcript will never appear in any service repo's commit metadata (because service repos no longer produce checkpoints), HIGH confidence is no longer attainable. The new confidence rules:

- **MEDIUM**: commit timestamp falls within session window (±5 min from session start/end) AND at least one file in the commit appears in the session's files-touched list for that repo
- **LOW**: commit timestamp falls within ±15 min of session window, no file overlap required
- **No link**: outside ±15 min window

This change must be reflected in the `confidence` enum check in `schema.sql`'s `session_commit_links` table — actually, that check already accepts MEDIUM and LOW so no schema change needed.

**GitHub API for service repo commits:**
You need to fetch commits + their file lists from `entire-poc-backend` and `entire-poc-frontend` to perform the join. Use the existing Octokit client. The endpoints:
- `GET /repos/{owner}/{repo}/commits?since={iso8601}&until={iso8601}` — list commits in window
- `GET /repos/{owner}/{repo}/commits/{sha}` — get files changed in a specific commit

Cache results within a single ingestion run to avoid re-fetching.

**Idempotency:**
Re-ingesting the same workspace checkpoint should produce identical database state. Use `INSERT OR REPLACE` or check existence before inserting.

### Tests to add or update

In `entire-poc-backend/tests/`:

- `session-joiner.test.ts` — update to test the new MEDIUM/LOW logic without HIGH (since session_id matches are no longer possible)
- New test: `transcript-extraction.test.ts` — verify that a sample `full.jsonl` produces the expected `session_repo_touches` rows
- Existing `path-resolver.test.ts` should still pass unchanged

Run `npm test` and confirm all tests pass.

### Pass criteria for Phase 2

- `npm run build` succeeds with no TypeScript errors
- `npm test` passes with the updated and new tests
- `npm run lint` passes
- Backend service starts cleanly: `npm run dev` or equivalent
- `GET /api/status` returns 200 OK

---

## Phase 3 — Verify Phase 1 and 2 are complete

Before running new validation scenarios, confirm the cleanup actually happened:

1. From the workspace, run:
   ```
   ls -la ../entire-poc-backend/.entire 2>/dev/null
   ls -la ../entire-poc-frontend/.entire 2>/dev/null
   ```
   Both should return "No such file or directory."

2. Check that `.git/hooks/` in each service repo no longer references entire:
   ```
   grep -l 'entire' ../entire-poc-backend/.git/hooks/* 2>/dev/null
   grep -l 'entire' ../entire-poc-frontend/.git/hooks/* 2>/dev/null
   ```
   Should return nothing.

3. Workspace's setup is intact:
   ```
   ls -la .entire/
   entire status
   ```
   Should show enabled with summarize on.

4. Backend builds and starts:
   ```
   (cd ../entire-poc-backend && npm run build && npm test)
   ```
   Should succeed.

If any of these fail, fix before continuing.

---

## Phase 4 — Re-run validation scenarios 3, 4, 5

Now exercise the modified ingestion against fresh cross-repo agent activity. Scenarios 1, 2, and 6 from the previous playbook are skipped — they tested per-repo behavior we've now intentionally removed, and the crashed-session test already passed.

### Scenario 3R — Cross-repo (backend + frontend) — RE-VALIDATION

**Where you operate:** workspace. Verify `pwd` first.

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `../entire-poc-backend/src/api/routes/status.ts` — add a field `patternVersion: 'A-star-v1'` to the status response object.
3. Edit `../entire-poc-frontend/src/components/IngestionStatus.tsx` — display the new `patternVersion` field in the status panel (use a small label like `<span className="text-xs text-gray-500">{status.patternVersion}</span>`).
4. Commit each repo separately:
   ```
   (cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 3R — pattern A* version field" && git log -1 --oneline)
   (cd ../entire-poc-frontend && git add -A && git commit -m "test: scenario 3R — pattern A* version display" && git log -1 --oneline)
   ```
5. Note both SHAs.
6. Push both:
   ```
   (cd ../entire-poc-backend && git push origin main)
   (cd ../entire-poc-frontend && git push origin main)
   ```

### Scenario 4R — Three-repo (workspace + backend + frontend) — RE-VALIDATION

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `skills/add-endpoint.md` — append a new section:
   ```
   ## Pattern A* re-validation
   Re-tested on <today's date YYYY-MM-DD> after removing per-repo Entire setup.
   ```
3. Edit `../entire-poc-backend/src/config.ts` — add a comment at the top: `// Re-validated: Pattern A* (workspace-only) on <today's date>`
4. Edit `../entire-poc-frontend/src/api/client.ts` — add a comment at the top: `// Re-validated: Pattern A* (workspace-only) on <today's date>`
5. Commit each repo separately with `"test: scenario 4R — "` prefix:
   ```
   git add -A && git commit -m "test: scenario 4R — workspace skill re-validation note"
   (cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 4R — backend re-validation comment")
   (cd ../entire-poc-frontend && git add -A && git commit -m "test: scenario 4R — frontend re-validation comment")
   ```
6. Note all three SHAs.
7. Push all three:
   ```
   git push origin main
   (cd ../entire-poc-backend && git push origin main)
   (cd ../entire-poc-frontend && git push origin main)
   ```

### Scenario 5R — Rapid multi-commit session — RE-VALIDATION

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `../entire-poc-backend/src/utils/logger.ts` — add `export function logTrace(msg: string) { if (process.env.TRACE) console.trace(msg); }`. If file doesn't exist, create it.
3. `(cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 5R-a — logger trace" && git log -1 --oneline && git push origin main)`
4. `sleep 10`
5. Edit `../entire-poc-frontend/src/api/client.ts` — add `export const RETRY_COUNT = 3;`
6. `(cd ../entire-poc-frontend && git add -A && git commit -m "test: scenario 5R-b — retry constant" && git log -1 --oneline && git push origin main)`
7. `sleep 10`
8. Edit `../entire-poc-backend/src/utils/logger.ts` again — add `export function logFatal(msg: string) { console.error('[FATAL]', msg); }`
9. `(cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 5R-c — fatal logger" && git log -1 --oneline && git push origin main)`
10. Note all three SHAs.

---

## Phase 5 — Post-scenario verification

This is the load-bearing check. Execute every step.

### Step A — Force-condense workspace sessions

```
entire doctor --force
```

Capture the full output.

### Step B — Push the workspace checkpoint branch

```
git push origin entire/checkpoints/v1
```

If the push fails (no commits to push, or remote rejection), record it.

### Step C — Trigger backend ingestion

```
curl -fsS -X POST http://localhost:3001/api/ingest/run | tee /tmp/ingest-result.json
```

### Step D — Query the API

```
curl -fsS http://localhost:3001/api/status | tee /tmp/status.json
curl -fsS http://localhost:3001/api/sessions/cross-repo | tee /tmp/cross-repo.json
curl -fsS http://localhost:3001/api/charts/tool-usage | tee /tmp/tools.json
curl -fsS http://localhost:3001/api/charts/friction | tee /tmp/friction.json
curl -fsS http://localhost:3001/api/charts/open-items | tee /tmp/open-items.json
```

### Step E — Inspect SQLite database

```
sqlite3 ../entire-poc-backend/data/poc.db <<'SQL'
.headers on
.mode column

SELECT 'TABLE COUNTS' AS '';
SELECT 'sessions' AS t, COUNT(*) AS n FROM sessions
UNION ALL SELECT 'session_repo_touches', COUNT(*) FROM session_repo_touches
UNION ALL SELECT 'repo_checkpoints', COUNT(*) FROM repo_checkpoints
UNION ALL SELECT 'session_commit_links', COUNT(*) FROM session_commit_links;

SELECT '--- Confidence breakdown ---' AS '';
SELECT confidence, COUNT(*) AS n
FROM session_commit_links
GROUP BY confidence
ORDER BY confidence;

SELECT '--- Cross-repo evidence (sessions touching multiple repos) ---' AS '';
SELECT session_id, COUNT(DISTINCT repo) AS repos_touched, GROUP_CONCAT(DISTINCT repo) AS repos
FROM session_repo_touches
GROUP BY session_id
HAVING COUNT(DISTINCT repo) > 1;

SELECT '--- Per-repo touch summary ---' AS '';
SELECT repo, COUNT(*) AS sessions_touched
FROM session_repo_touches
GROUP BY repo;

SELECT '--- Sample link rows ---' AS '';
SELECT session_id, repo, checkpoint_id, confidence, join_reason
FROM session_commit_links
ORDER BY created_at DESC
LIMIT 10;
SQL
```

### Step F — Re-verify workspace transcript still has cross-repo paths

```
(cd entire-poc-workspace && git log entire/checkpoints/v1 --oneline | head -5)
(cd entire-poc-workspace && git ls-tree -r entire/checkpoints/v1 | grep 'metadata.json' | tail -5)
```

For the most recent checkpoint folder, dump unique filePaths:
```
# Replace <CHECKPOINT_PATH> with actual path from the previous command
(cd entire-poc-workspace && git show entire/checkpoints/v1:<CHECKPOINT_PATH>/sessions/*/full.jsonl 2>/dev/null \
  | grep -oE '"filePath":"[^"]*"' \
  | sort -u)
```

Confirm:
- Backend paths present? (entire-poc-backend/...)
- Frontend paths present? (entire-poc-frontend/...)
- Workspace paths present? (entire-poc-workspace/...)

---

## Phase 6 — Pass / fail assessment

The migration is successful if ALL of the following hold:

| Check | Pass criterion |
|---|---|
| Service repos cleaned | `.entire/` directories removed; commits pushed |
| Backend builds | `npm run build` and `npm test` pass |
| Cross-repo transcript still captured | Step F shows backend AND frontend paths in same session |
| `session_repo_touches` populated | Step E shows ≥1 row per repo per multi-repo session |
| Multi-repo evidence exists | Step E "Cross-repo evidence" query returns ≥1 session row |
| `session_commit_links` populated | Step E shows ≥1 link per cross-repo commit (MEDIUM confidence acceptable) |
| Cross-repo API responds | Step D `/api/sessions/cross-repo` returns array with data, not error |
| Charts have data | Step D chart endpoints return non-empty arrays |

If all checks pass, **Pattern A\* is the production recommendation.**

If `session_repo_touches` is populated but `session_commit_links` is still 0:
- The transcript-extraction works but the GitHub-API-based commit join failed
- Inspect ingestion logs for errors fetching commits
- Possible cause: time window mismatch, missing GitHub token scope, or rate limiting
- This is a fixable bug, not an architectural failure

If `session_repo_touches` is also 0:
- The Phase 2 ingestion changes didn't take effect
- Check the orchestrator wiring; the new transcript-extraction code may not be called
- Re-read your changes; do not declare failure without root-causing this

---

## Phase 7 — Update documentation

### Update RESULTS-TEMPLATE.md

Append a new section after the existing scenario results:

```
---

## Pattern A* Re-Validation Results (<today's date>)

After the original validation found that per-repo Entire enablement produced no useful data,
the system was migrated to Pattern A* (workspace-only) and the ingestion pipeline was
modified to derive cross-repo attribution directly from the workspace transcript.

### Cleanup commits

| Repo | SHA | Description |
|---|---|---|
| entire-poc-backend | <sha> | Removed .entire/ and disabled hooks |
| entire-poc-frontend | <sha> | Removed .entire/ and disabled hooks |

### Re-validation scenario commits

| Scenario | Repo | SHA |
|---|---|---|
| 3R | backend | <sha> |
| 3R | frontend | <sha> |
| 4R | workspace | <sha> |
| 4R | backend | <sha> |
| 4R | frontend | <sha> |
| 5R-a | backend | <sha> |
| 5R-b | frontend | <sha> |
| 5R-c | backend | <sha> |

### Database state after re-validation

[paste Step E output here]

### Cross-repo API output

[paste Step D /api/sessions/cross-repo output here]

### Workspace transcript filePath evidence

[paste Step F output, with explicit yes/no on backend/frontend/workspace presence]

### Verdict

[GO — Pattern A* validated for production]
OR
[NEEDS-FIX — describe what's still broken]
```

### Update CONCLUSIONS.md

Replace the existing content with the new conclusion:

```markdown
# Conclusions — Entire Pattern A* Validation

**Date:** <today's date>
**Recommendation:** [GO — Adopt Pattern A* for production]

---

## Final Verdict

Pattern A* (workspace-only Entire enablement with transcript-first ingestion) is
the validated production approach for the multi-repo workspace.

The original Pattern C design — enabling Entire in both workspace and all
service repos — was found to be unnecessary and ineffective. Service repos
launched no Entire sessions of their own when commits happened via subshell
from a workspace-rooted agent process. The per-repo enablement contributed
nothing measurable to the data model.

Pattern A* removes this dead complexity. Only the workspace hub needs Entire
installed. The backend ingestion pipeline derives per-repo attribution
directly from the workspace transcript's filePath events, then matches against
service-repo commits via the GitHub API for MEDIUM-confidence
session-to-commit linking.

---

## What Pattern A* Captures

- Cross-repo session continuity (single session ID across all touched repos)
- Per-repo file-touch attribution (which session touched which files in which repo)
- Tool usage (Read, Edit, Write, Bash, Skill, Task, Grep, Glob, WebSearch)
- Slash commands invoked
- Subagent (Task) spawns
- Auto-summarized friction and open_items per session
- Learnings (repo / code / workflow categories)
- Token usage (input, output, cache_read)
- Session-to-commit links at MEDIUM confidence (timestamp + file overlap)

## What Pattern A* Does NOT Capture

- Line-level attribution per commit (`agent_percentage`, `agent_lines`,
  `human_modified`, `human_added`, `human_removed`)
- HIGH-confidence session-to-commit links

These limitations affect approximately 4 of the 20+ planned dashboard metrics.
File-level proxies are available for those metrics from the workspace
transcript data.

---

## Production Rollout Implications

For the real workspace (~60 service repos):

- Enable Entire ONLY in `_wod.workspace/` — one repo, not 61
- No per-repo bootstrap script needed
- No `dev-onboard.sh` per repo — developers run `entire enable` once in the
  workspace only
- No `entire-attach-watcher.sh` daemon — Plan B is not needed
- Service repos remain completely untouched
- Single source of truth: workspace's `entire/checkpoints/v1` branch
- Platform's ingestion pipeline does the per-repo attribution server-side

Daily developer workflow is unchanged from today.

---

## Evidence Summary

[paste final Step E table counts]
[paste cross-repo session map output]
[link to RESULTS-TEMPLATE.md for detail]
```

Commit and push both files:
```
git add docs/RESULTS-TEMPLATE.md docs/CONCLUSIONS.md
git commit -m "docs: Pattern A* re-validation results and final recommendation"
git push origin main
```

---

## What you must report at the end

Your final response must contain:

1. **Cleanup confirmation** — both service repos cleaned, with commit SHAs
2. **Build status** — backend builds and tests pass after Phase 2 changes
3. **Re-validation summary table** — one row per scenario (3R, 4R, 5R), commit SHAs, pass/fail
4. **Database state after re-validation** — Step E output verbatim
5. **Cross-repo evidence** — Step F output, with explicit confirmation that workspace transcript still captures backend AND frontend paths
6. **API responses** — at minimum the `/api/sessions/cross-repo` output showing populated cross-repo session data
7. **Final recommendation** — GO if all Phase 6 checks pass, NEEDS-FIX with specific failure mode if not
8. **Confirmation** — RESULTS-TEMPLATE.md and CONCLUSIONS.md updated, committed, pushed

Do not declare success without all eight items.

---

## What you must NOT do

- Do not re-enable Entire in the service repos — the whole point is to prove it isn't needed
- Do not skip Phase 2 (the ingestion modification) — without it, Phases 4-6 will produce identical-to-before zero data
- Do not modify the workspace's Entire setup
- Do not invent SHAs or fake API responses if a step fails — report the actual error
- Do not silently fix unrelated bugs you encounter; flag them in your final report and stay focused on the migration

---

Begin Phase 1 when ready.
