# Validation Results — Entire Pattern C PoC

**Date:** ___________
**Tester:** ___________
**Entire CLI version:** ___________
**Claude CLI version:** ___________

---

## Scenario Results

| # | Scenario | Pass/Fail | Confidence | Notes |
|---|---|---|---|---|
| 1 | Single-repo (backend) | | | |
| 2 | Single-repo (frontend) | | | |
| 3 | Cross-repo (backend + frontend) | | | |
| 4 | Three-repo (workspace + both) | | | |
| 5 | Long-running multi-commit | | | |
| 6 | Crashed session | | | |

---

## Validation Criteria Assessment

### Hard Pass Criteria

| ID | Criterion | Met? | Evidence |
|---|---|---|---|
| VC-1 | Single-repo checkpoints have line-level attribution | | |
| VC-2 | Cross-repo workspace checkpoints contain multi-repo filePath events | | |
| VC-3 | Backend ingests all repos without crashes | | |
| VC-4 | Path-to-repo resolution correct (unit tests) | | |
| VC-5 | All six charts render with data | | |

### Soft Pass Criteria

| ID | Criterion | Met? | Evidence |
|---|---|---|---|
| VC-6 | ≥70% cross-repo links at HIGH or MEDIUM | | |
| VC-7 | `entire doctor` condenses orphaned sessions | | |
| VC-8 | Auto-summarize produces friction/open_items ≥50% | | |

---

## Session ID Consistency Check (OD-1)

- Same session_id across workspace and service repos? ___________
- If different: document the pattern observed

---

## Plan B Results (if needed)

| # | Scenario | Plan A Confidence | Plan B Confidence | Delta |
|---|---|---|---|---|
| 3 | Cross-repo | | | |
| 4 | Three-repo | | | |
| 5 | Long-running | | | |

---

## Database State After All Scenarios

```
sessions:              ___
session_repo_touches:  ___
repo_checkpoints:      ___
session_commit_links:  ___

Confidence distribution:
  HIGH:   ___
  MEDIUM: ___
  LOW:    ___
```

---

## Additional Notes

___________
