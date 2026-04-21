# Entire IO Pattern C — Validation Playbook (Agent Prompt)

You are running the validation playbook for an Entire IO Pattern C deployment. This workspace has Entire enabled with auto-summarize. Your job is to execute SIX validation scenarios end-to-end, observe what happens, verify the captured data, and produce a written results record.

---

## Critical context — read this twice before starting

- You were launched from `entire-poc-workspace/` (the hub repo)
- Sibling repos are at `../entire-poc-backend/` and `../entire-poc-frontend/`
- The backend API is running at http://localhost:3001
- The frontend dashboard is at http://localhost:5173
- Entire IO is enabled in all three repos with Claude Code hooks
- **Every tool call you make right now is being captured by Entire's hooks**
- The whole purpose of this test is to discover whether sessions launched from the workspace correctly attribute work done in sibling repos. **You are simultaneously the test subject and the test runner.**

### Hard rules that override any conflicting instinct

1. **You MUST remain rooted in `entire-poc-workspace/` for scenarios 3, 4, 5, and 6.** When you need to edit a file in a sibling repo, use the Edit/Write tool with a relative path (e.g. `../entire-poc-backend/src/api/routes/status.ts`). **Do NOT `cd` into a service repo during these scenarios.** The bash `cd` is fine for `git commit`/`git push` operations, but use a subshell so your "current" location stays the workspace: `(cd ../entire-poc-backend && git add -A && git commit -m "...")`.

2. **Scenarios 1 and 2 are different.** They are baseline tests of the intended single-repo Entire usage. For those two only, you DO `cd` into the service repo, work there, and commit there. After scenario 2 completes, you MUST `cd` back to the workspace before starting scenario 3.

3. **Verify your location before scenario 3 starts.** Run `pwd` and confirm it ends with `entire-poc-workspace`. If it doesn't, `cd` back. The single most common way this whole validation produces a false-positive "success" is by accidentally running scenario 3 from inside a service repo — which would test the trivial case Entire already supports.

4. **Do NOT edit any file under `entire-poc-workspace/scripts/` or `entire-poc-workspace/docs/` during any scenario.** Those are test infrastructure. The only workspace file you touch is `skills/add-endpoint.md` in scenario 4.

5. **Note the commit SHA after every commit** (`git log -1 --oneline`) and keep them in your working memory — you'll write them into `RESULTS-TEMPLATE.md` at the end.

---

## Scenario 1 — Single-repo (backend only) — BASELINE

**Purpose:** confirm Entire's intended single-repo flow still works.
**Where you operate:** inside `entire-poc-backend`.

### Steps

1. `cd ../entire-poc-backend && pwd` — confirm location
2. Add a utility function to `src/utils/time.ts`:
   ```typescript
   export function formatDuration(ms: number): string {
     return `${(ms / 1000).toFixed(1)}s`;
   }
   ```
   If the file doesn't exist, create it. If it exists, append.
3. `git add -A && git commit -m "test: scenario 1 — single repo backend utility"`
4. Note the commit SHA: `git log -1 --oneline`
5. `git push origin main`

### Pass criteria for scenario 1

After the post-scenario verification at the end of the playbook:
- `entire-poc-backend`'s `entire/checkpoints/v1` branch has a new checkpoint
- That checkpoint's `metadata.json` has `agent_percentage > 0` and `agent_lines > 0`
- The checkpoint references the commit SHA you noted

### Fail criteria for scenario 1

- No new checkpoint on the backend's checkpoint branch
- `agent_percentage` is null or zero
- Conclusion: something is wrong with the basic Entire setup; STOP the playbook and report

---

## Scenario 2 — Single-repo (frontend only) — BASELINE

**Purpose:** same as scenario 1, on a different repo and different agent surface.
**Where you operate:** inside `entire-poc-frontend`.

### Steps

1. `cd ../entire-poc-frontend && pwd` — confirm location
2. Create `src/utils/format.ts`:
   ```typescript
   export function truncateId(id: string): string {
     return id.slice(0, 8) + '...';
   }
   ```
3. Open `src/components/CrossRepoSessionMap.tsx`. Find any inline `.slice(0, N)` call on a session ID. Replace it with a call to `truncateId` from the new utility, and add the import at the top of the file.
4. `git add -A && git commit -m "test: scenario 2 — single repo frontend utility"`
5. Note the commit SHA
6. `git push origin main`

### Pass criteria for scenario 2

Same as scenario 1, but on the frontend's checkpoint branch.

### Fail criteria for scenario 2

Same as scenario 1.

---

## ⚠️ TRANSITION POINT — return to workspace

Before scenario 3:

1. `cd ../entire-poc-workspace && pwd`
2. **Verify the output ends with `entire-poc-workspace`.** Do not proceed if it does not.
3. From now until the end of scenario 6, you do not `cd` into a sibling repo. All file edits use relative paths from the workspace. Only `git` operations on sibling repos use `(cd ../sibling && git ...)` subshells.

---

## Scenario 3 — Cross-repo (backend + frontend) — THE CRITICAL TEST

**Purpose:** the entire reason this PoC exists. Tests whether a single agent session launched from the workspace can correctly attribute work spanning two sibling repos.
**Where you operate:** workspace (do NOT `cd` into either service repo).

### Steps

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `../entire-poc-backend/src/api/routes/status.ts` — add a `version: '0.1.0'` field to the status response object that this route returns. Look at the existing response shape and add it as a sibling field.
3. Edit `../entire-poc-frontend/src/components/IngestionStatus.tsx` — render the new `version` field next to the existing status info. Use whatever simple inline element fits the existing layout (e.g. `<span className="text-xs text-gray-500">v{status.version}</span>`).
4. Commit each repo separately:
   ```
   (cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 3 — cross-repo backend version field" && git log -1 --oneline)
   (cd ../entire-poc-frontend && git add -A && git commit -m "test: scenario 3 — cross-repo frontend version display" && git log -1 --oneline)
   ```
5. Note both commit SHAs.
6. Push both:
   ```
   (cd ../entire-poc-backend && git push origin main)
   (cd ../entire-poc-frontend && git push origin main)
   ```

### Pass criteria for scenario 3 — the load-bearing checks

After the post-scenario verification at the end:

**Hard pass (any one of these is required):**
- The workspace's `entire/checkpoints/v1` branch has a session whose `full.jsonl` contains `filePath` events spanning BOTH `entire-poc-backend` AND `entire-poc-frontend` paths
- AT LEAST ONE row in `session_commit_links` resolves at HIGH or MEDIUM confidence linking the workspace session to either of the scenario-3 commits

**Soft pass (preferred but not required):**
- BOTH cross-repo commits get HIGH confidence links

### Fail criteria for scenario 3

- The workspace's checkpoint branch has no session for this scenario
- OR the session's `full.jsonl` only contains paths from one of the two repos
- OR all `session_commit_links` for the scenario-3 session ID are LOW confidence
- **If any of these fail conditions hold, this is the moment to consider stopping and switching to Plan B (see "Plan B trigger" section at the end of this prompt).**

---

## Scenario 4 — Three-repo (workspace + backend + frontend)

**Purpose:** edge case where the workspace itself receives a commit alongside service repos.
**Where you operate:** workspace.

### Steps

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `skills/add-endpoint.md` — append a new section:
   ```
   ## Testing notes

   Tested during Pattern C validation on <today's date in YYYY-MM-DD format>.
   ```
3. Edit `../entire-poc-backend/src/config.ts` — add a comment line at the top of the file: `// Validated: Pattern C cross-repo config`
4. Edit `../entire-poc-frontend/src/api/client.ts` — add a comment line at the top: `// Validated: Pattern C cross-repo client`
5. Commit each repo separately with descriptive messages prefixed `"test: scenario 4 — "`:
   ```
   git add -A && git commit -m "test: scenario 4 — workspace skill notes"
   (cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 4 — backend config comment")
   (cd ../entire-poc-frontend && git add -A && git commit -m "test: scenario 4 — frontend client comment")
   ```
6. Note all three commit SHAs.
7. Push all three:
   ```
   git push origin main
   (cd ../entire-poc-backend && git push origin main)
   (cd ../entire-poc-frontend && git push origin main)
   ```

### Pass criteria for scenario 4

- Workspace's checkpoint branch has a session referencing all three repos in its `filePath` events
- `session_repo_touches` table contains rows for all three repo names
- At least one HIGH or MEDIUM confidence link to each of the three commits

### Fail criteria

- Workspace files don't appear in `session_repo_touches` (workspace's own changes lost)
- OR the workspace commit has no checkpoint at all
- OR cross-repo links are all LOW

---

## Scenario 5 — Rapid multi-commit session (sequential commits)

**Purpose:** observe whether multiple commits within the same session are grouped under one session ID or split.
**Note:** this scenario was originally framed as "long-running" but a true >1h idle test isn't practical inside one playbook run. We test the rapid-sequential variant here and accept that the >1h `entire doctor` trigger needs separate manual testing.
**Where you operate:** workspace.

### Steps

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `../entire-poc-backend/src/utils/logger.ts` — add a new function `logDebug(msg: string)` that calls `console.debug` only when `process.env.DEBUG` is truthy. If the file doesn't exist, create it.
3. `(cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 5a — backend logger" && git log -1 --oneline && git push origin main)`
4. `sleep 10`
5. Edit `../entire-poc-frontend/src/api/client.ts` — add a new exported constant `export const API_TIMEOUT_MS = 30000;`
6. `(cd ../entire-poc-frontend && git add -A && git commit -m "test: scenario 5b — frontend timeout constant" && git log -1 --oneline && git push origin main)`
7. `sleep 10`
8. Edit `../entire-poc-backend/src/utils/logger.ts` again — add a second function `logWarn(msg: string)` that calls `console.warn`.
9. `(cd ../entire-poc-backend && git add -A && git commit -m "test: scenario 5c — backend warn logger" && git log -1 --oneline && git push origin main)`
10. Note all three commit SHAs.

### Pass criteria for scenario 5

- All three commits appear in the appropriate per-repo checkpoint branches
- In the workspace's checkpoint data, observe whether the three commits all link to ONE session ID or THREE different session IDs — record this observation. Either outcome is acceptable but the answer is critical for the production design (it tells us whether long sessions naturally group or naturally split).

### Fail criteria

- Any of the three commits has no associated checkpoint
- The session/commit linking produces only LOW confidence across the board

---

## Scenario 6 — Crashed session (orphan recovery)

**Purpose:** verify `entire doctor` reliably handles sessions that didn't end cleanly. This is critical because real developers' sessions crash regularly, and Plan B's value depends on this case being either solved natively or solvable via the wrapper.
**Where you operate:** workspace.

### ⚠️ Important — this scenario requires manual intervention

Step 3 below requires the human user to kill this Claude Code session manually (Ctrl+C). You (the agent) cannot do this yourself. When you reach step 3, output a clear message to the user telling them to Ctrl+C now, then wait. Do not continue past step 3 on your own.

### Steps

1. Verify `pwd` ends with `entire-poc-workspace`.
2. Edit `../entire-poc-backend/src/api/routes/charts.ts` — add a new export: `export const SCENARIO_6_MARKER = 'orphan-test';`. **Do not commit yet.** Do not run `git add` or `git commit`.
3. Output this message to the user, then stop:
   ```
   ⏸ SCENARIO 6 PAUSE — manual action required.

   I have made an uncommitted edit to ../entire-poc-backend/src/api/routes/charts.ts.
   This simulates an agent session that crashed mid-flow.

   Please now Ctrl+C this Claude Code session.

   After killing the session, restart Claude Code from the workspace and tell it to:
     - Run `entire doctor --force` in the workspace
     - Run `entire doctor --force` in entire-poc-backend
     - Report whether the orphaned shadow branch was condensed cleanly,
       discarded cleanly, or produced an error
     - Then resume with the post-scenario verification steps below
   ```

### Pass criteria for scenario 6

- After the human kills the session and restarts the agent
- Both `entire doctor --force` runs complete without errors
- The orphaned shadow branch is either:
  - Condensed into `entire/checkpoints/v1` (preferred — data preserved)
  - Discarded cleanly (acceptable — no error, no leftover state)

### Fail criteria

- `entire doctor` errors out
- The orphan persists after `entire doctor --force` and shows up again on the next run
- The shadow branch grows over multiple runs

---

## After all six scenarios — post-scenario verification

This section is the actual proof of whether Pattern C works. Skipping any of these steps means the validation is incomplete.

### Step A — Force-condense everything

Run `entire doctor --force` in all three repos, in this order:

```
(cd entire-poc-workspace && entire doctor --force) || true
(cd ../entire-poc-backend && entire doctor --force) || true
(cd ../entire-poc-frontend && entire doctor --force) || true
```

Capture the full output of each command in your report.

### Step B — Push all checkpoint branches

```
git push origin entire/checkpoints/v1
(cd ../entire-poc-backend && git push origin entire/checkpoints/v1)
(cd ../entire-poc-frontend && git push origin entire/checkpoints/v1)
```

If any push fails (e.g., remote rejects, branch doesn't exist), record it.

### Step C — Trigger backend ingestion

```
curl -fsS -X POST http://localhost:3001/api/ingest/run | tee /tmp/ingest-result.json
```

If the ingestion endpoint returns an error, do not proceed. Record the error.

### Step D — Query high-level status

```
curl -fsS http://localhost:3001/api/status | tee /tmp/status.json
curl -fsS http://localhost:3001/api/sessions/cross-repo | tee /tmp/cross-repo.json
```

### Step E — Inspect the SQLite database directly

This is the load-bearing verification. Don't trust the API responses alone — verify the underlying data:

```
sqlite3 ../entire-poc-backend/data/poc.db <<'SQL'
.headers on
.mode column
SELECT 'sessions' AS t, COUNT(*) AS n FROM sessions
UNION ALL SELECT 'session_repo_touches', COUNT(*) FROM session_repo_touches
UNION ALL SELECT 'repo_checkpoints', COUNT(*) FROM repo_checkpoints
UNION ALL SELECT 'session_commit_links', COUNT(*) FROM session_commit_links;

SELECT '--- Confidence breakdown ---' AS '';
SELECT confidence, COUNT(*) AS n
FROM session_commit_links
GROUP BY confidence
ORDER BY confidence;

SELECT '--- Sessions with multi-repo touches (cross-repo evidence) ---' AS '';
SELECT session_id, COUNT(DISTINCT repo) AS repos_touched
FROM session_repo_touches
GROUP BY session_id
HAVING COUNT(DISTINCT repo) > 1;

SELECT '--- Per-repo checkpoint counts ---' AS '';
SELECT repo, COUNT(*) AS checkpoints,
       SUM(CASE WHEN agent_percentage IS NOT NULL THEN 1 ELSE 0 END) AS with_attribution
FROM repo_checkpoints
GROUP BY repo;
SQL
```

### Step F — Deep-inspect the workspace transcript for scenario 3 evidence

This is the single most important check in the whole playbook. It directly answers "did the workspace actually capture cross-repo events":

```
# Find the workspace's most recent checkpoint folder
ls -lt entire-poc-workspace/.git/refs/heads/entire/checkpoints/ 2>/dev/null || true

# Use git to inspect the checkpoint branch directly
(cd entire-poc-workspace && git log entire/checkpoints/v1 --oneline | head -10)

# List checkpoint folders on the branch
(cd entire-poc-workspace && git ls-tree -r entire/checkpoints/v1 | grep 'metadata.json' | head -10)
```

Then for the most recent checkpoint, extract `full.jsonl` and grep for both repo names:

```
# Replace <CHECKPOINT_PATH> with the path you found above
(cd entire-poc-workspace && git show entire/checkpoints/v1:<CHECKPOINT_PATH>/sessions/*/full.jsonl 2>/dev/null \
  | grep -oE '"filePath":"[^"]*"' \
  | sort -u \
  | head -50)
```

Record the unique `filePath` values you see. The critical question:

- **Do you see paths containing `entire-poc-backend`?**
- **Do you see paths containing `entire-poc-frontend`?**
- **Do you see paths from BOTH in the same session's `full.jsonl`?**

If yes to all three for at least one session: Scenario 3 architecturally PASSES.
If no: Scenario 3 architecturally FAILS regardless of what the dashboard shows.

---

## Step G — Fill in and commit the results record

Open `entire-poc-workspace/docs/RESULTS-TEMPLATE.md`. Fill in the per-scenario results in the format specified by the template. Include:

- For each scenario: the commit SHAs, pass/fail vs the per-scenario criteria, observed confidence levels, anything unexpected
- Overall summary: hard pass criteria met (yes/no), soft pass criteria met (yes/no), Plan B needed (yes/no/maybe)
- Raw output from steps C, D, E, F appended at the end as appendices

Commit and push:

```
git add docs/RESULTS-TEMPLATE.md
git commit -m "docs: validation playbook results"
git push origin main
```

Then write `entire-poc-workspace/docs/CONCLUSIONS.md` with the final go/no-go recommendation:

- **GO — adopt Pattern C** if all hard pass criteria met, ≥70% of cross-repo links HIGH/MEDIUM
- **NEEDS-PLAN-B** if scenario 3 architecturally passes (workspace transcript has cross-repo paths) but session-to-commit joins are mostly LOW confidence
- **NO-GO — evaluate alternatives** if scenario 3 architecturally fails (workspace transcript doesn't capture cross-repo paths)

Commit and push CONCLUSIONS.md too.

---

## Plan B trigger — when to stop Plan A and switch

If at any point during Step F you observe that the workspace's `full.jsonl` does NOT contain `filePath` events from sibling repos for the scenario-3 session, STOP. Do not continue running scenarios. Instead:

1. Output a clear message to the user:
   ```
   ⚠ PLAN A FAILURE DETECTED.

   The workspace's checkpoint transcript does not contain cross-repo file paths
   for scenario 3. This means Entire's per-repo hooks did not capture the
   sibling-repo edits in the workspace session.

   Plan A (vanilla Pattern C with entire doctor) appears to be insufficient.

   Recommendation: enable Plan B (the entire-attach-watcher.sh) and re-run
   scenarios 3, 4, and 5. Plan B forces session-to-commit linkage by calling
   entire attach after every commit.
   ```

2. Wait for user instruction. Do NOT enable Plan B yourself — that's a human decision because it changes the meaning of subsequent results.

If Plan B is then enabled by the user, run scenarios 3, 4, and 5 again under the wrapper. Compare the new SQLite confidence breakdown to the original. Document the delta in CONCLUSIONS.md.

---

## What you must report at the end

Regardless of pass/fail outcome, your final response in the chat should contain:

1. **Summary table** — one row per scenario, columns: scenario, commit SHAs, hard-pass yes/no, soft-pass yes/no, observed confidence
2. **Step F output** — the unique `filePath` values from the workspace transcript, with explicit yes/no on whether both `entire-poc-backend` and `entire-poc-frontend` appeared
3. **Step E output** — the SQLite counts and confidence breakdown
4. **Final recommendation** — GO, NEEDS-PLAN-B, or NO-GO, with one paragraph of reasoning
5. **Confirmation** — that RESULTS-TEMPLATE.md and CONCLUSIONS.md were filled in, committed, and pushed

Do not reply with "I executed the scenarios" alone. The validation only counts if you provide all five sections.

---

## What you must NOT do

- Do not edit any file under `entire-poc-workspace/scripts/` or `entire-poc-workspace/docs/` during the scenarios (RESULTS-TEMPLATE.md and CONCLUSIONS.md are the only docs files you write to, and only at the very end)
- Do not skip the SQLite verification step (Step E) — it's the load-bearing check
- Do not skip the `full.jsonl` deep inspection (Step F) — it's the single most important check
- Do not enable Plan B without user instruction
- Do not declare "success" if `agent_percentage` columns are all NULL in `repo_checkpoints` — that means line-level attribution is broken and Pattern C as designed is not working
- Do not invent commit SHAs or other observable values if a step failed — record the actual error and continue if possible

---

Begin scenario 1 when ready.
