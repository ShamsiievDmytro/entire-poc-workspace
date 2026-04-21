# Validation Playbook — Entire Pattern C PoC

This document contains runnable, step-by-step test instructions for each validation scenario defined in REQUIREMENTS.md Section 4.3.

---
Dmytro Shamsiiev

## Scenario 1 — Single-repo session (backend only)

### Setup
```bash
cd ~/Projects/metrics_2_0/entire-poc-backend
entire status  # Confirm enabled
```

### Steps
1. Launch Claude Code from the backend repo directory
2. Ask the agent to make a small change (e.g., add a comment to `src/index.ts`)
3. Commit the change: `git add . && git commit -m "test: scenario 1 — single repo backend"`
4. Push: `git push origin main`
5. Wait 2 minutes, then run: `entire doctor --force` in the backend repo
6. Trigger ingestion: `curl -X POST http://localhost:3001/api/ingest/run`

### Expected outcome
- A checkpoint appears on `entire/checkpoints/v1` branch in the backend repo
- `repo_checkpoints` table has a row with `agent_percentage` non-null and `agent_lines > 0`
- Dashboard shows the session in "Sessions Over Time" chart

### Recording results
- Pass / Fail (circle one)
- `agent_percentage` value observed:
- `agent_lines` value observed:
- Notes:

---

## Scenario 2 — Single-repo session (frontend only)

### Setup
```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
entire status  # Confirm enabled
```

### Steps
1. Launch Claude Code from the frontend repo directory
2. Ask the agent to make a small change (e.g., update a component's text)
3. Commit: `git add . && git commit -m "test: scenario 2 — single repo frontend"`
4. Push: `git push origin main`
5. Wait 2 minutes, then: `entire doctor --force`
6. Trigger ingestion: `curl -X POST http://localhost:3001/api/ingest/run`

### Expected outcome
- A checkpoint appears on `entire/checkpoints/v1` branch in the frontend repo
- `repo_checkpoints` table has a row with `agent_percentage` non-null
- Dashboard shows the session

### Recording results
- Pass / Fail (circle one)
- `agent_percentage` value observed:
- Notes:

---

## Scenario 3 — Cross-repo session (backend + frontend in one session)

### Setup
```bash
cd ~/Projects/metrics_2_0/entire-poc-workspace
entire status  # Confirm enabled
```

### Steps
1. Launch Claude Code from the **workspace** repo directory
2. Ask the agent to make changes in both `../entire-poc-backend/src/` and `../entire-poc-frontend/src/`
3. Commit each repo separately:
   ```bash
   cd ../entire-poc-backend && git add . && git commit -m "test: scenario 3 — cross-repo backend part"
   cd ../entire-poc-frontend && git add . && git commit -m "test: scenario 3 — cross-repo frontend part"
   ```
4. Push both repos
5. Run `entire doctor --force` in the workspace repo
6. Push workspace repo (to push checkpoint branch)
7. Trigger ingestion

### Expected outcome
- Workspace `entire/checkpoints/v1` branch contains a checkpoint with `filePath` events spanning both backend and frontend
- `session_repo_touches` has rows for both repos under the same `session_id`
- `session_commit_links` has entries linking the session to commits in both repos
- Cross-Repo Session Map shows the session with 2 repos touched
- **Critical check:** Does the `session_id` in the workspace transcript match any `session_id_in_metadata` in the service repo checkpoints?

### Recording results
- Pass / Fail (circle one)
- Confidence flags observed: HIGH / MEDIUM / LOW
- Session ID consistency: same / different across repos
- Notes:

---

## Scenario 4 — Three-repo session (workspace + backend + frontend)

### Setup
Same as Scenario 3.

### Steps
1. Launch Claude Code from the workspace repo
2. Ask the agent to edit files in the workspace itself (e.g., `skills/add-endpoint.md`) AND in both service repos
3. Commit all three repos separately
4. Push all three
5. Run `entire doctor --force` in workspace
6. Push workspace
7. Trigger ingestion

### Expected outcome
- Same as Scenario 3, plus the workspace repo itself appears in `session_repo_touches`
- Three repos show in the Cross-Repo Session Map for this session

### Recording results
- Pass / Fail (circle one)
- Confidence flags observed:
- Notes:

---

## Scenario 5 — Long-running session crossing multiple commits

### Setup
Same as Scenario 3.

### Steps
1. Launch Claude Code from workspace
2. Make a change in backend, commit and push
3. Wait 5 minutes
4. Make another change in frontend, commit and push
5. Wait 5 minutes
6. Make a third change in backend, commit and push
7. Run `entire doctor --force`
8. Push workspace
9. Trigger ingestion

### Expected outcome
- All three commits link to the same session
- Session `ended_at - started_at` spans the full duration
- `entire doctor` successfully condenses the session

### Recording results
- Pass / Fail (circle one)
- Number of commits linked:
- Session duration observed:
- Notes:

---

## Scenario 6 — Session that crashes mid-flow (manual kill)

### Setup
Same as Scenario 3.

### Steps
1. Launch Claude Code from workspace
2. Ask the agent to start a multi-step task
3. While the agent is working, kill the process (Ctrl+C or `kill`)
4. Make a commit in the repo the agent was editing
5. Push
6. Run `entire doctor --force` in workspace
7. Push workspace
8. Trigger ingestion

### Expected outcome
- `entire doctor` recovers the orphaned session
- The partial session appears in the `sessions` table
- The commit may or may not link (LOW confidence acceptable)
- No crashes or skipped records in ingestion

### Recording results
- Pass / Fail (circle one)
- Doctor recovery: success / failure
- Session captured: yes / no / partial
- Link confidence:
- Notes:

---

## Plan B Re-run Instructions

If Scenarios 3, 4, or 5 fail to produce HIGH or MEDIUM confidence links:

1. Start the attach watcher: `~/Projects/metrics_2_0/entire-poc-workspace/scripts/entire-attach-watcher.sh &`
2. Re-run the failed scenario(s)
3. Record results with "Plan B" annotation
4. Compare confidence flags: Plan A vs Plan B
