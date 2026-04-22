# Open Questions

Issues and decisions pending resolution before production rollout.

---

## 1. Agent lines counting — should overridden lines count as AI contribution?

**Context:** When the agent writes 9 lines and the human modifies 3 of them before committing, Git AI reports:
- `accepted_lines: 6` (in file map — agent's original content survived)
- `overriden_lines: 3` (agent wrote these but human changed the content)

The file map only lists the 6 unchanged lines. The 3 overridden lines are excluded from the map.

**Current behavior:** Our `agent_lines` = 6 (from file map only). The agent's total contribution was actually 9 — it wrote the initial version of all lines, including the ones the human later modified.

**Question:** Should we add an `agent_total_lines` metric = `agent_lines + overridden_lines` to show what the agent originally produced? This affects:
- Agent % calculation (6/12 = 50% vs 9/12 = 75%)
- Dashboard stat cards
- The narrative: "AI wrote 50% of this commit" vs "AI wrote 75%, human refined 25% of the AI output"

**Options:**
- **A)** Keep current: `agent_lines` = file map only (conservative, what shipped unchanged)
- **B)** Add `agent_total_lines` = accepted + overridden (shows full AI contribution)
- **C)** Show both on the dashboard — "AI produced" vs "AI shipped unchanged"

**Decision:** Pending
