# Validation Results — Entire Pattern C PoC

**Date:** 2026-04-21
**Tester:** Claude Code agent (automated playbook)
**Entire CLI version:** 0.5.5 (90bb1c50)
**Claude CLI version:** 2.1.98

---

## Scenario Results

| # | Scenario | Pass/Fail | Confidence | Notes |
|---|---|---|---|---|
| 1 | Single-repo (backend) | PARTIAL FAIL | N/A | Commit `a93d61c` pushed. Backend `entire/checkpoints/v1` has no checkpoint beyond init. However, the workspace checkpoint captured backend file paths. The per-repo checkpoint was not created — likely because the Bash tool resets cwd to workspace, so Entire hooks fired in workspace context, not backend. |
| 2 | Single-repo (frontend) | PARTIAL FAIL | N/A | Commit `94275a0` pushed. Frontend `entire/checkpoints/v1` has no checkpoint beyond init. Same root cause as scenario 1. Workspace transcript captured frontend file paths. |
| 3 | Cross-repo (backend + frontend) | ARCH PASS / LINK FAIL | None (0 links) | Backend commit `a2b299e`, frontend commit `280f32f`. Workspace `full.jsonl` contains file paths from BOTH repos in the same session. Architecturally passes — the workspace captured cross-repo events. But `session_commit_links = 0` because no per-repo checkpoints exist to join against. |
| 4 | Three-repo (workspace + both) | ARCH PASS / LINK FAIL | None (0 links) | Workspace `ae8b8ec`, backend `10dddee`, frontend `40b3ce2`. Workspace checkpoint exists with `agent_percentage: 100`. Transcript has all three repos. But `session_repo_touches = 0` and no commit linking. |
| 5 | Long-running multi-commit | ARCH PASS / LINK FAIL | None (0 links) | Backend `93016a8`, `d08483e`; frontend `dac3530`. All commits present on main. Workspace transcript captured all edits. All three commits in ONE session (`c2466fea-85f2-4d3e-8784-25f862e22176`). No per-repo checkpoints to link against. |
| 6 | Crashed session | PASS (acceptable) | N/A | Uncommitted edit to `charts.ts` left in working tree. Session killed via Ctrl+C. `entire doctor --force` ran cleanly in all three repos — no orphaned shadow branches found. The session either never produced a shadow branch (no commit was made) or it was already cleaned up. Doctor handled the case without errors. |

---

## Commit SHA Reference

| Scenario | Repo | SHA |
|---|---|---|
| 1 | backend | `a93d61c` |
| 2 | frontend | `94275a0` |
| 3 | backend | `a2b299e` |
| 3 | frontend | `280f32f` |
| 4 | workspace | `ae8b8ec` |
| 4 | backend | `10dddee` |
| 4 | frontend | `40b3ce2` |
| 5a | backend | `93016a8` |
| 5b | frontend | `dac3530` |
| 5c | backend | `d08483e` |
| 6 | backend | uncommitted |

---

## Validation Criteria Assessment

### Hard Pass Criteria

| ID | Criterion | Met? | Evidence |
|---|---|---|---|
| VC-1 | Single-repo checkpoints have line-level attribution | PARTIAL | Workspace checkpoint has `agent_percentage: 100`, `agent_lines: 4`. But backend/frontend have NO checkpoints on their own branches. Only workspace produced checkpoint data. |
| VC-2 | Cross-repo workspace checkpoints contain multi-repo filePath events | YES | `full.jsonl` contains 5 backend paths, 4 frontend paths, and 2 workspace paths. All in one session transcript. |
| VC-3 | Backend ingests all repos without crashes | PARTIAL | Ingestion ran without errors but only found 1 session (workspace). Backend/frontend checkpoint branches have no data to ingest. |
| VC-4 | Path-to-repo resolution correct (unit tests) | NOT TESTED | No unit tests were run during this playbook execution. |
| VC-5 | All six charts render with data | NOT TESTED | Dashboard rendering not verified in this automated run. |

### Soft Pass Criteria

| ID | Criterion | Met? | Evidence |
|---|---|---|---|
| VC-6 | ≥70% cross-repo links at HIGH or MEDIUM | NO | 0 links total. No per-repo checkpoints exist to join against. |
| VC-7 | `entire doctor` condenses orphaned sessions | YES (trivial) | Doctor ran clean in all three repos. No orphaned sessions to condense — the killed session had no commit, so no shadow branch was created. |
| VC-8 | Auto-summarize produces friction/open_items ≥50% | YES | Session metadata includes `friction` (2 items) and `open_items` (3 items). Summary also includes `intent`, `outcome`, `learnings` with repo/code/workflow breakdowns. |

---

## Session ID Consistency Check (OD-1)

- Same session_id across workspace and service repos? **Cannot determine** — only the workspace produced checkpoint data. Backend and frontend have no checkpoint sessions. The workspace session ID is `c2466fea-85f2-4d3e-8784-25f862e22176`.
- Pattern observed: Entire hooks only created checkpoints in the workspace (where `claude` CLI was launched), not in the service repos that were edited via cross-repo file paths.

---

## Plan B Results (if needed)

Plan B was not executed. See recommendations in CONCLUSIONS.md.

| # | Scenario | Plan A Confidence | Plan B Confidence | Delta |
|---|---|---|---|---|
| 3 | Cross-repo | 0 links | Not tested | — |
| 4 | Three-repo | 0 links | Not tested | — |
| 5 | Long-running | 0 links | Not tested | — |

---

## Database State After All Scenarios

```
sessions:              1
session_repo_touches:  0
repo_checkpoints:      1
session_commit_links:  0

Confidence distribution:
  HIGH:   0
  MEDIUM: 0
  LOW:    0
```

---

## Step F — Workspace Transcript filePath Evidence (Critical Check)

Unique filePath values found in workspace checkpoint `2e/dacdad81b7/0/full.jsonl`:

```
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-backend/src/api/routes/charts.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-backend/src/api/routes/status.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-backend/src/config.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-backend/src/utils/logger.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-backend/src/utils/time.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-frontend/src/api/client.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-frontend/src/components/CrossRepoSessionMap.tsx"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-frontend/src/components/IngestionStatus.tsx"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-frontend/src/utils/format.ts"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-workspace/docs/validation-playbook-prompt.md"
"filePath":"/Users/dmytroshamsiiev/Projects/metrics_2_0/entire-poc-workspace/skills/add-endpoint.md"
```

- **Paths containing `entire-poc-backend`?** YES (5 files)
- **Paths containing `entire-poc-frontend`?** YES (4 files)
- **Both repos in the SAME session's `full.jsonl`?** YES

**Scenario 3 architecturally PASSES.**

---

## Step C — Ingestion Output

```json
{"jobId":"288a5b49-46d6-4f79-b859-7d23cba30c0a","startedAt":"2026-04-21T08:43:47.776Z","sessions":1,"checkpoints":1,"links":0,"errors":[]}
```

## Step D — Status and Cross-Repo Outputs

Status:
```json
{"lastRun":"2026-04-21T08:40:32.539Z","repos":["entire-poc-workspace"],"sessionCount":1,"checkpointCount":1,"linkCount":0}
```

Cross-repo sessions:
```json
{"error":"Session not found"}
```

---

## Additional Notes

### Root Cause of Missing Per-Repo Checkpoints

The Entire CLI hooks are installed in all three repos, but checkpoints were only generated in the workspace. This is because:

1. **Scenarios 1 & 2**: The Bash tool in Claude Code resets the working directory to the workspace after each command. Even though `cd ../entire-poc-backend && git commit` ran the commit inside the backend, the Entire hooks likely evaluated in the context of the workspace process, not the backend. The backend and frontend repos never had a Claude Code session launched directly within them.

2. **Scenarios 3–6**: By design, these operate from the workspace. Cross-repo edits are captured in the workspace's transcript (confirmed via Step F), but the service repos' Entire hooks never triggered because commits were done via `(cd ../repo && git commit)` subshells — the git hooks in the service repos would need to independently detect and create checkpoints.

### Key Architectural Insight

Pattern C's cross-repo transcript capture WORKS — the workspace checkpoint faithfully records every `filePath` event from sibling repos. The GAP is in the **joining layer**: the ingestion pipeline expects per-repo checkpoints (on each repo's `entire/checkpoints/v1` branch) to exist independently, but the service repos never produce them when commits are made via subshell from a workspace-rooted session.

### Recommendation

This is a **NEEDS-PLAN-B** situation. The transcript data is there (cross-repo paths captured) but the session-to-commit linking pipeline has no per-repo checkpoint data to join against. Plan B (`entire-attach-watcher.sh`) or an enhanced ingestion pipeline that extracts commit linkage directly from the workspace transcript's file paths would close this gap.
