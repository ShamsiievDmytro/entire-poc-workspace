# Conclusions — Entire Pattern C Validation

**Date:** 2026-04-21
**Recommendation:** NEEDS-PLAN-B

---

## Final Verdict

**NEEDS-PLAN-B** — Scenario 3 architecturally passes (the workspace transcript captures cross-repo file paths from both `entire-poc-backend` and `entire-poc-frontend` in a single session), but session-to-commit joins are completely absent (0 links at any confidence level) because service repos produce no independent checkpoints when commits are made via subshell from a workspace-rooted agent session.

---

## What Works

1. **Cross-repo file path capture**: The workspace's `full.jsonl` contains 11 unique `filePath` entries spanning all three repos. This is the core mechanism Pattern C depends on, and it works correctly.

2. **Auto-summarize quality**: The session metadata includes structured `intent`, `outcome`, `learnings` (repo/code/workflow), `friction` (2 items), and `open_items` (3 items). The summary accurately describes the validation session.

3. **Line-level attribution (workspace)**: The workspace checkpoint has `agent_percentage: 100` with `agent_lines: 4`, correctly attributing the workspace-side changes.

4. **Session continuity**: All scenarios (1–5) ran under a single session ID (`c2466fea-85f2-4d3e-8784-25f862e22176`). Multiple sequential commits across repos within one session are naturally grouped, not split.

5. **Orphan recovery**: `entire doctor --force` ran without errors. The killed session (scenario 6) left no orphaned shadow branches.

---

## What Does Not Work

1. **Per-repo checkpoints for service repos**: Backend and frontend `entire/checkpoints/v1` branches contain only the initialization commit. No scenario produced a checkpoint in these repos' branches. The Entire hooks in service repos do not trigger when commits are made via `(cd ../repo && git commit)` subshells from a workspace-rooted session.

2. **Session-to-commit linking**: `session_commit_links = 0`. The ingestion pipeline requires per-repo checkpoint data to exist in order to match sessions to commits. Since service repos have no checkpoints, no links are created.

3. **`session_repo_touches`**: Zero rows. The ingestion pipeline does not extract repo-touch information from the workspace transcript's cross-repo file paths.

4. **Cross-repo session detection via API**: The `/api/sessions/cross-repo` endpoint returns no data because the underlying joining tables are empty.

---

## Root Cause

The Entire CLI creates checkpoints via git hooks installed in each repo. These hooks fire when git operations occur within that repo. However, in Pattern C's cross-repo workflow:

- The agent session runs in the **workspace** repo
- File edits happen via absolute paths to sibling repos
- Commits in sibling repos happen via **subshell** commands: `(cd ../entire-poc-backend && git commit)`
- The workspace's Entire hooks capture the full transcript (including cross-repo file paths) correctly
- But the service repos' git hooks either don't fire or don't associate with the workspace session
- Result: transcript data exists but per-repo checkpoint data doesn't, breaking the join

---

## Plan B Recommendation

Enable `entire-attach-watcher.sh` (Plan B) and re-run scenarios 3, 4, and 5. Plan B forces session-to-commit linkage by calling `entire attach` after every commit in a service repo, explicitly linking the current workspace session to the service repo's commit.

Alternatively, enhance the ingestion pipeline to:
1. Parse the workspace transcript's `filePath` entries
2. Resolve each path to a repo name
3. Match against commits in those repos by timestamp overlap with the session window
4. Create `session_commit_links` and `session_repo_touches` entries directly from the workspace transcript

This "transcript-first" approach would eliminate the dependency on per-repo checkpoints entirely and leverage the data that Pattern C already captures successfully.

---

## Summary Table

| Scenario | Commit SHAs | Hard Pass | Soft Pass | Observed Confidence |
|---|---|---|---|---|
| 1 — Single-repo backend | `a93d61c` | NO (no per-repo checkpoint) | N/A | N/A |
| 2 — Single-repo frontend | `94275a0` | NO (no per-repo checkpoint) | N/A | N/A |
| 3 — Cross-repo (critical) | backend `a2b299e`, frontend `280f32f` | PARTIAL (transcript YES, links NO) | NO (0 links) | None |
| 4 — Three-repo | workspace `ae8b8ec`, backend `10dddee`, frontend `40b3ce2` | PARTIAL (transcript YES, links NO) | NO (0 links) | None |
| 5 — Multi-commit | backend `93016a8`/`d08483e`, frontend `dac3530` | PARTIAL (transcript YES, links NO) | NO (0 links) | None |
| 6 — Crashed session | uncommitted | YES (doctor clean) | YES (no orphan) | N/A |
