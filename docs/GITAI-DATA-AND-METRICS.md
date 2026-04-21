# Git AI Data Model & Metrics Catalog

**Date:** 2026-04-21
**Based on:** Git AI Standard v3.0.0 (authorship/3.0.0), Git AI CLI 1.3.2
**Source data:** 56 commits across 3 repos from validation session

---

## 1. What Git AI Preserves — Raw Data Fields

Every commit with agent involvement gets a Git Note in `refs/notes/ai`. The note has two sections: a file map and a JSON metadata block, separated by `---`.

### 1.1 File Map Section (top)

```
src/api/routes/status.ts
  1612649c4bf0b88e 32
src/components/Dashboard.tsx
  1612649c4bf0b88e 2,35-36
```

| Field | Description | Example |
|-------|-------------|---------|
| **File path** | Relative path within the repo | `src/api/routes/status.ts` |
| **Prompt ID** | Links to the specific agent prompt/interaction that produced these lines | `1612649c4bf0b88e` |
| **Line ranges** | Exact line numbers attributed to that prompt | `2,35-36` = lines 2, 35, 36 |

Line ranges use comma-separated values and dash ranges: `1-6` = lines 1 through 6, `51-52,54,58-110` = specific ranges and individual lines.

### 1.2 JSON Metadata Section (below `---`)

```json
{
  "schema_version": "authorship/3.0.0",
  "git_ai_version": "1.3.2",
  "base_commit_sha": "fc9a230...",
  "prompts": {
    "<prompt_id>": {
      "agent_id": {
        "tool": "claude",
        "id": "9b4e6eb7-...",
        "model": "claude-opus-4-6"
      },
      "human_author": "Dmytro Shamsiiev",
      "messages": [],
      "total_additions": 10,
      "total_deletions": 0,
      "accepted_lines": 10,
      "overriden_lines": 0,
      "messages_url": "https://usegitai.com/cas/..." 
    }
  }
}
```

| Field | Type | Description | Always present? |
|-------|------|-------------|-----------------|
| `schema_version` | string | Format version (`authorship/3.0.0`) | Yes |
| `git_ai_version` | string | CLI version that created the note | Yes |
| `base_commit_sha` | string | The commit this note is attached to | Yes |
| `prompts` | object | Map of prompt_id -> attribution data | Yes (may be empty for human-only commits) |
| `prompts.*.agent_id.tool` | string | Agent identifier: `claude`, `cursor`, `copilot`, `codex`, `gemini-cli`, etc. | Yes |
| `prompts.*.agent_id.id` | string | Session/instance ID of the agent | Yes |
| `prompts.*.agent_id.model` | string | LLM model used: `claude-opus-4-6`, `gpt-4`, `sonnet-4.5`, etc. | Yes |
| `prompts.*.human_author` | string | Git user who committed (`Name <email>`) | Yes |
| `prompts.*.messages` | array | Prompt messages (populated when `prompt_storage != local`) | Yes (may be empty) |
| `prompts.*.total_additions` | number | Total lines added in this prompt's scope | Yes |
| `prompts.*.total_deletions` | number | Total lines deleted in this prompt's scope | Yes |
| `prompts.*.accepted_lines` | number | Lines the human accepted (committed) from the agent's suggestions | Yes |
| `prompts.*.overriden_lines` | number | Lines the human modified after agent generation | Yes |
| `prompts.*.messages_url` | string | URL to stored prompt/response content | Only when `prompt_storage != local` |

### 1.3 Derived Fields (computable from the raw data)

| Field | Derivation | Description |
|-------|-----------|-------------|
| `agent_lines` | Count lines in file map for each prompt | Lines attributed to AI |
| `human_lines` | `total_additions - accepted_lines` | Lines not attributed to any agent |
| `unknown_lines` | Lines in git diff but not in any note | Changes outside agent scope (e.g., auto-generated files) |
| `agent_percentage` | `agent_lines / (agent_lines + human_lines) * 100` | AI contribution ratio |
| `override_rate` | `overriden_lines / (accepted_lines + overriden_lines)` | How often humans modify agent output |
| `files_per_prompt` | Count distinct files per prompt ID | Scope of each agent interaction |

### 1.4 Relationships Between Fields

```
Session (agent_id.id)
  └── Prompt (prompt_id)
        ├── File A
        │     └── Lines 1-6 (from file map)
        ├── File B
        │     └── Lines 35-36, 2 (from file map)
        └── Metadata
              ├── total_additions: 10
              ├── accepted_lines: 10
              └── overriden_lines: 0
```

**One commit can have multiple prompts** (agent switched between interactions).
**One prompt can span multiple files** (agent edited several files in one interaction).
**One commit can have multiple agents** (developer used Cursor, then Claude before committing).

### 1.5 What Is NOT Preserved

| Missing Data | Why | Workaround |
|---|---|---|
| Prompt/response text | Requires `prompt_storage != local` | Enable `notes` or `default` storage; or use Entire's transcript |
| Token usage | Git AI doesn't track tokens | Use Entire's session data or agent-specific APIs |
| Time spent per edit | Checkpoints don't record wall-clock time | Approximate from commit timestamps |
| Friction / blockers | Not in scope for Git AI | Use Entire's friction/open-items signals |
| Tool calls | Not tracked by Git AI | Use Entire's tool-call aggregation |
| Why code was written | Only "what" and "who", not "why" | Combine with commit messages + Entire session context |

---

## 2. Multi-Agent Behavior — Validated

### 2.1 Concurrent Subagent Test

Three subagents ran in parallel from the same parent session, each editing a different repo:

| Repo | Commit | Files Changed | AI Lines | Human Lines |
|------|--------|---------------|----------|-------------|
| Backend | `fc9a230` | `server.ts` lines 22-31 | 10 | 0 |
| Frontend | `bcf1acb` | `RepoLegend.tsx` 1-18, `Dashboard.tsx` 2,35-36 | 21 | 0 |
| Workspace | `fa71e28` | `verify-multi-agent-notes.sh` 1-67 | 67 | 0 |

**Observations:**
- All three share `prompt_id: 1612649c4bf0b88e` and `session_id: 9b4e6eb7-...` — they're children of the same parent Claude Code session.
- File attribution is correct: each repo's note only lists files changed in THAT repo.
- Line ranges are correct: e.g., `Dashboard.tsx` shows lines `2,35-36` (the import line and the two lines for `<RepoLegend />`).
- No cross-contamination: backend note doesn't mention frontend files and vice versa.

### 2.2 How True Multi-Agent Would Appear

When different agent types contribute to the same commit, the note contains multiple entries in `prompts`:

```json
{
  "prompts": {
    "aaa111": {
      "agent_id": { "tool": "cursor", "model": "gpt-4o" },
      "accepted_lines": 15
    },
    "bbb222": {
      "agent_id": { "tool": "claude", "model": "claude-opus-4-6" },
      "accepted_lines": 8
    }
  }
}
```

The file map section would show which lines came from which prompt:
```
src/feature.ts
  aaa111 1-15
  bbb222 16-23
```

This enables per-agent breakdown within a single commit — a scenario our DB schema already handles via the `(repo, commit_sha, agent)` primary key.

### 2.3 Multi-Agent Limitations Observed

- **Subagents share parent prompt ID:** Parallel subagents dispatched from the same Claude Code session all use the same prompt ID. They appear as a single "interaction" in the notes. To distinguish them, you'd need to correlate with the agent framework's own task IDs.
- **Agent tool name granularity:** Claude Code subagents all report as `tool: "claude"`. The framework doesn't distinguish "main agent" from "subagent". True multi-agent distinction only appears when DIFFERENT agent products are used (Claude vs Cursor vs Copilot).

---

## 3. Metrics Catalog — What Can Be Built

### 3.1 Commit-Level Metrics (per commit)

| Metric | Source Fields | Description | Use Case |
|--------|-------------|-------------|----------|
| **AI Contribution %** | `accepted_lines / total_additions * 100` | Percentage of committed code written by AI | ROI dashboard headline number |
| **AI Lines Added** | `accepted_lines` | Absolute count of AI-authored lines | Volume tracking |
| **Human Lines Added** | `total_additions - accepted_lines` | Lines written by human | Complement to AI metric |
| **Override Rate** | `overriden_lines / (accepted_lines + overriden_lines)` | How often humans modify AI output | Quality signal — high override = low suggestion quality |
| **Deletion Impact** | `total_deletions` | Lines deleted in AI-assisted edits | Refactoring/cleanup signal |
| **Files Touched** | Count of files in file map | Scope of the commit | Complexity indicator |
| **Agent Identity** | `agent_id.tool` | Which agent wrote the code | Per-agent comparison |
| **Model Used** | `agent_id.model` | Which LLM model | Model quality comparison |

### 3.2 Repository-Level Metrics (aggregated per repo)

| Metric | Aggregation | Description |
|--------|-------------|-------------|
| **Avg AI %** | `AVG(agent_percentage)` over all commits | Overall AI adoption level in a repo |
| **Total AI Lines** | `SUM(agent_lines)` | Cumulative AI code volume |
| **AI Adoption Trend** | AI % grouped by week/month | Is AI usage increasing? |
| **Agent Mix** | `GROUP BY agent` | Which agents are used in this repo |
| **Model Mix** | `GROUP BY model` | Which models are used |
| **Human-Only Commit Rate** | Commits where `prompts = {}` / total commits | How often devs work without AI |

### 3.3 Developer-Level Metrics (aggregated per human_author)

| Metric | Aggregation | Description |
|--------|-------------|-------------|
| **AI Reliance %** | Avg AI % across developer's commits | How much each dev relies on AI |
| **Override Rate** | Avg override rate across dev's commits | Does this dev frequently modify AI output? |
| **Agent Preference** | Most common `agent_id.tool` per author | Which agent does each dev prefer? |
| **Model Preference** | Most common `agent_id.model` per author | Which model does each dev use? |
| **Productivity Delta** | AI lines/day with agents vs without | Does AI increase output? (requires baseline) |

### 3.4 Session-Level Metrics (aggregated per agent_id.id)

| Metric | Aggregation | Description |
|--------|-------------|-------------|
| **Session Scope** | Distinct repos touched per session ID | Cross-repo reach of a session |
| **Session Output** | Sum of AI lines per session | Total AI contribution per session |
| **Commits Per Session** | Count commits per session ID | Session productivity |
| **Prompt Efficiency** | Lines per prompt (accepted_lines / prompt count) | How productive each interaction is |
| **Session Agent Mix** | Distinct agents per session | Multi-agent session detection |

### 3.5 Time-Series Metrics (trend analysis)

| Metric | Time Dimension | Description |
|--------|---------------|-------------|
| **AI % Over Time** | By week/month, using `captured_at` | Adoption trajectory |
| **Agent Adoption Curve** | First appearance of each agent per repo over time | When did each tool enter the workflow? |
| **Override Rate Trend** | By week, using `captured_at` | Is AI suggestion quality improving? |
| **Commit Velocity (AI-assisted)** | Commits/week where AI % > 0 | Does AI increase commit frequency? |
| **Lines Per Day (AI vs Human)** | Daily sum split by AI/human | Productivity trend |

### 3.6 Cross-Repo / Workspace Metrics

| Metric | Source | Description |
|--------|--------|-------------|
| **Cross-Repo Session %** | Sessions touching >1 repo / total sessions | How often agents work across repos |
| **Repo Coupling** | Repos commonly edited in the same session | Implicit dependency map |
| **Hub vs Direct** | Sessions launched from workspace vs service repo | Workflow pattern analysis |

### 3.7 Quality & Trust Metrics

| Metric | Source | Description |
|--------|--------|-------------|
| **Override Rate** | `overriden_lines` | Direct signal of AI suggestion quality |
| **Acceptance Rate** | `accepted_lines / (accepted_lines + overriden_lines)` | Inverse of override rate |
| **AI Churn Rate** | AI-authored lines that are modified/deleted in subsequent commits | How durable is AI code? |
| **AI Bug Correlation** | Cross-reference AI % with bug-fix commits | Are AI-heavy commits more likely to need fixes? |

---

## 4. Comparison: Git AI Data vs Entire Data

| Metric Category | Git AI | Entire | Combined Value |
|----------------|--------|--------|---------------|
| **Line-level attribution** | Per-line, per-agent, per-model | Not available | Git AI is the only source |
| **File-level attribution** | Derived from line data | Direct from transcript | Redundant — Git AI is more precise |
| **Agent identification** | Direct (tool + model + session) | From transcript metadata | Both valid; Git AI more structured |
| **Token usage** | Not tracked | Input/output/cache tokens | Entire is the only source |
| **Friction signals** | Not tracked | Friction items per session | Entire is the only source |
| **Open items / learnings** | Not tracked | Per-session extraction | Entire is the only source |
| **Tool call patterns** | Not tracked | Tool name + count per repo | Entire is the only source |
| **Slash command usage** | Not tracked | Per-repo command set | Entire is the only source |
| **Session duration** | Approximation from commit timestamps | Start/end from transcript | Entire is more accurate |
| **Override behavior** | `overriden_lines` count | Not tracked | Git AI is the only source |
| **Cross-repo sessions** | Via shared session ID in notes | Via transcript `filePath` events | Both valid; Git AI per-line, Entire per-file |

### Recommended Combined Data Model

```
┌─────────────────────────────────────────────────────┐
│                   DASHBOARD                          │
├──────────────────────┬──────────────────────────────┤
│    Git AI Metrics     │     Entire Metrics           │
├──────────────────────┼──────────────────────────────┤
│ AI % per commit       │ Session duration             │
│ Agent/model breakdown │ Token usage                  │
│ Line-level attribution│ Friction & blockers          │
│ Override rate         │ Open items / learnings       │
│ Cross-repo line maps  │ Tool call patterns           │
│ Squash survival       │ Slash command frequency      │
│ Human-only detection  │ Subagent spawn count         │
└──────────────────────┴──────────────────────────────┘
             ↓ joined by session ID / commit SHA ↓
┌─────────────────────────────────────────────────────┐
│              COMBINED INSIGHTS                       │
├─────────────────────────────────────────────────────┤
│ "Session X: 45 min, 3.2k tokens, produced 2 commits │
│  across backend+frontend, 94% AI-authored,           │
│  1 friction item (type error), 0 overrides"          │
└─────────────────────────────────────────────────────┘
```

---

## 5. Production Metrics Dashboard — Recommended Panels

### Tier 1: Executive / Stakeholder (Weekly Report)

1. **AI Adoption Score** — Org-wide AI contribution % (weighted avg across repos)
2. **AI Lines This Week** — Total AI-authored lines committed
3. **Agent Distribution** — Pie chart: Claude vs Cursor vs Copilot vs other
4. **Top Repos by AI %** — Bar chart: which repos use AI the most
5. **Trend** — AI % over the past 12 weeks

### Tier 2: Engineering Manager (Per-Team)

6. **Team AI %** — Per-team breakdown (by committer)
7. **Override Rate** — Are suggestions being accepted or modified?
8. **Cross-Repo Session Rate** — How often do agents work across service boundaries?
9. **Model Usage** — Which models are teams using? (cost implication)
10. **Human-Only Commit Rate** — Balance metric: not everything should be AI

### Tier 3: Developer (Self-Service)

11. **My AI %** — Personal AI contribution trend
12. **My Agent Mix** — Which tools am I using?
13. **My Override Rate** — Am I accepting or modifying suggestions?
14. **My Session Productivity** — Lines per session, commits per session
15. **File-Level Attribution** — `git ai blame` on any file

### Tier 4: Quality & Trust (Engineering Leadership)

16. **AI Churn Rate** — AI lines modified/deleted within 7 days
17. **AI Bug Correlation** — Bug-fix commits vs AI % in parent commit
18. **High-Override Files** — Files where AI suggestions are frequently modified
19. **Agent Quality Comparison** — Override rate per agent type
20. **Model Quality Comparison** — Override rate per model version

---

## 6. Data Volume Estimates for Production (60 repos)

Based on our PoC data:

| Metric | PoC (3 repos) | Projected (60 repos) |
|--------|--------------|---------------------|
| Commits with notes | 56 | ~1,100/month* |
| DB rows (`gitai_commit_attribution`) | 56 | ~1,100/month |
| Note size (avg) | ~500 bytes | ~500 bytes |
| Total notes storage | ~28 KB | ~550 KB/month |
| GitHub API calls per ingestion | ~60 | ~1,200 |
| Ingestion time | ~60 seconds | ~20 minutes** |

*Assuming ~20 commits/repo/month with agent involvement.
**Can be reduced to ~2 minutes with incremental ingestion (track last-seen note).

Storage is negligible. API rate limits (5,000/hour authenticated) are the constraint — incremental ingestion is the production-critical optimization.

---

## 7. Schema Reference

### Current Schema (PoC)

```sql
CREATE TABLE gitai_commit_attribution (
  repo TEXT NOT NULL,
  commit_sha TEXT NOT NULL,
  agent TEXT NOT NULL,            -- e.g., 'claude', 'cursor', 'copilot'
  model TEXT,                      -- e.g., 'claude-opus-4-6', 'gpt-4'
  agent_lines INTEGER NOT NULL,    -- lines attributed to AI
  human_lines INTEGER NOT NULL,    -- lines not attributed to AI
  agent_percentage REAL NOT NULL,  -- derived: agent_lines / total * 100
  prompt_id TEXT,                  -- links to the agent interaction
  files_touched_json TEXT,         -- JSON array of {file, lineRanges, lineCount}
  raw_note_json TEXT,              -- full Git Note content for auditability
  captured_at TIMESTAMP,           -- commit timestamp
  ingested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (repo, commit_sha, agent)
);
```

### Recommended Production Extensions

```sql
-- Override tracking (from overriden_lines in notes)
ALTER TABLE gitai_commit_attribution ADD COLUMN overridden_lines INTEGER DEFAULT 0;

-- Session correlation
ALTER TABLE gitai_commit_attribution ADD COLUMN session_id TEXT;
-- Enables joining with Entire's sessions table

-- Human author (from notes)
ALTER TABLE gitai_commit_attribution ADD COLUMN human_author TEXT;
-- Enables developer-level metrics

-- Deletion tracking
ALTER TABLE gitai_commit_attribution ADD COLUMN deletion_lines INTEGER DEFAULT 0;

-- Messages URL (when prompt_storage != local)
ALTER TABLE gitai_commit_attribution ADD COLUMN messages_url TEXT;
```
