# Conclusions — Entire Pattern A* Validation

**Date:** 2026-04-21
**Recommendation:** GO — Adopt Pattern A* for production

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

### Database State

```
sessions:              1
session_repo_touches:  3  (1 per repo)
repo_checkpoints:      3  (workspace only)
session_commit_links:  16 (9 MEDIUM, 7 LOW)
```

### Cross-repo Session Map

```json
Session c2466fea-85f2-4d3e-8784-25f862e22176:
  Repos: [entire-poc-backend, entire-poc-frontend, entire-poc-workspace]
  Links: 16 total (10 backend, 6 frontend)
  Best confidence: MEDIUM (0.7)
  Join reason: timestamp_files_overlap
```

### Key Metrics from Validation

- Workspace transcript captured 23 unique file paths across 3 repos
- 9 of 16 commit links achieved MEDIUM confidence (56% — based on timestamp + file overlap)
- 7 links at LOW confidence (timestamp-only fallback)
- 0 links at HIGH confidence (expected — no per-repo session ID matching possible)
- All 3 chart endpoints return data (tool-usage: 3 tools, friction: 1 session, open-items: 1 session)

### Migration from Pattern C

The critical bug discovered in Pattern C was that `filePath` was nested inside
`toolUseResult.file.filePath` and `toolUseResult.filePath` in the Entire transcript
format, but the JSONL parser only checked the top-level `event.filePath`. Additionally,
tool names and file paths were split across assistant `tool_use` events (name + input)
and user `tool_result` events (result + filePath). Fixing the parser to extract from
all nesting levels was the key change that unlocked the full pipeline.

See [RESULTS-TEMPLATE.md](./RESULTS-TEMPLATE.md) for detailed per-scenario results.
