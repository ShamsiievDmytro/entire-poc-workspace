# Dashboard Charts Redesign — Design Spec

**Date:** 2026-04-21
**Status:** Approved
**Scope:** Replace Entire-sourced Recharts dashboard with Git AI-powered Chart.js dashboard

---

## 1. Overview

Rebuild the dashboard with 10 charts powered entirely by Git AI data, using Chart.js (`react-chartjs-2`) for a polished, presentation-ready look. Remove all Entire-sourced charts and the Recharts dependency. The dashboard becomes a focused Git AI attribution analytics view.

## 2. Data Source

All charts draw from `gitai_commit_attribution` table (66 commits, 3 repos, 10,200 AI lines). Some aggregations require parsing `raw_note_json` server-side (developer names, overridden lines count).

## 3. Backend Changes

### 3.1 New endpoint: `GET /api/gitai/dashboard`

Single endpoint returning all aggregated data the dashboard needs.

Response shape:

```json
{
  "summary": {
    "total_commits": 66,
    "avg_agent_pct": 97.1,
    "pure_ai_commit_rate": 89.4,
    "first_time_right_rate": 92.3,
    "total_ai_lines": 10200,
    "total_human_lines": 187
  },
  "agent_pct_over_time": [
    { "commit_sha": "abc1234", "repo": "entire-poc-backend", "agent_percentage": 100, "captured_at": "2026-04-21T07:29:49Z" }
  ],
  "attribution_breakdown": [
    { "commit_sha": "abc1234", "repo": "entire-poc-backend", "agent_lines": 105, "human_lines": 0, "captured_at": "2026-04-21T07:29:49Z" }
  ],
  "by_developer": [
    { "author": "Dmytro Shamsiiev", "commits": 66, "avg_agent_pct": 97.1 }
  ],
  "by_model": [
    { "model": "claude-opus-4-6", "commits": 64 },
    { "model": "claude-opus-4-7", "commits": 2 }
  ],
  "files_by_layer": [
    { "layer": "components", "ai_lines": 1200, "human_lines": 5 },
    { "layer": "routes", "ai_lines": 800, "human_lines": 20 }
  ],
  "human_edit_rate": [
    { "commit_sha": "abc1234", "repo": "entire-poc-backend", "human_pct": 0, "captured_at": "2026-04-21T07:29:49Z" }
  ],
  "commit_cadence": [
    { "commit_sha": "abc1234", "hours_since_prev": 0.5, "captured_at": "2026-04-21T07:29:49Z" }
  ]
}
```

### 3.2 Aggregation logic

**`summary.pure_ai_commit_rate`**: `COUNT(WHERE agent_percentage = 100) / COUNT(*) * 100`

**`summary.first_time_right_rate`**: Parse `raw_note_json` for each commit. A commit is "first-time-right" when ALL prompts in the note have `overriden_lines = 0` (note: Git AI spells it `overriden_lines` with one 'r'). Rate = `COUNT(first_time_right) / COUNT(commits_with_agent_lines > 0) * 100`.

**`by_developer`**: Parse `raw_note_json` → `prompts.*.human_author`. Group by author, compute avg agent_percentage per author.

**`files_by_layer`**: Parse `files_touched_json` for all commits. Classify each file path:
- `components/` or `pages/` → "components"
- `routes/` or `api/` → "routes"
- `utils/` or `lib/` or `domain/` → "utils"
- `tests/` or `test/` or `*.test.*` or `*.spec.*` → "tests"
- `docs/` or `*.md` → "docs"
- `db/` or `migrations/` → "database"
- `ingestion/` → "ingestion"
- Everything else → "other"

Sum `lineCount` per layer across all commits, split by AI vs human.

**`human_edit_rate`**: `human_pct = 100 - agent_percentage` per commit.

**`commit_cadence`**: Order commits by `captured_at` ASC. For each commit (except the first), compute hours since previous commit's `captured_at`.

### 3.3 Route location

Add to existing `src/api/routes/gitai.ts`. Compute aggregations in a helper function within the same file (no new module needed — the logic is query + parse, not complex enough for a separate file).

## 4. Frontend Changes

### 4.1 Dependency changes

- Remove: `recharts`
- Add: `chart.js`, `react-chartjs-2`

### 4.2 Files to delete

All Entire-sourced chart components (no longer used):

```
src/components/charts/SessionsOverTimeChart.tsx
src/components/charts/AgentPercentageChart.tsx
src/components/charts/SlashCommandsChart.tsx
src/components/charts/ToolUsageMixChart.tsx
src/components/charts/FrictionPerSessionChart.tsx
src/components/charts/OpenItemsPerSessionChart.tsx
src/components/charts/FilesPerSessionChart.tsx
src/components/charts/SessionDurationChart.tsx
src/components/charts/GitAiAgentPercentageChart.tsx
src/components/CrossRepoSessionMap.tsx
src/components/EntireVsGitAiComparison.tsx
src/components/RepoLegend.tsx
```

### 4.3 Files to create

| File | Chart Type | Description |
|------|-----------|-------------|
| `src/components/charts/StatCards.tsx` | Stat cards (3) | Avg Agent %, Pure-AI Commit Rate, First-Time-Right Rate |
| `src/components/charts/AgentPctOverTime.tsx` | Line | Smoothed agent % trend (3-commit rolling avg) |
| `src/components/charts/AttributionBreakdown.tsx` | Stacked bar | AI vs human lines per commit |
| `src/components/charts/AiByDeveloper.tsx` | Horizontal bar | Avg agent % per developer |
| `src/components/charts/ModelDistribution.tsx` | Doughnut | Commit count by model |
| `src/components/charts/FilesByLayer.tsx` | Stacked bar | AI/human lines by architectural layer |
| `src/components/charts/HumanEditRate.tsx` | Bar | Human edit % per commit |
| `src/components/charts/CommitCadence.tsx` | Bar | Hours between consecutive commits |
| `src/lib/chartDefaults.ts` | Config | Chart.js global defaults registration |

### 4.4 Chart.js global configuration (`src/lib/chartDefaults.ts`)

Register Chart.js components and set global defaults:
- Font: system sans-serif
- Grid: `#f3f4f6`, no border
- Tooltips: white bg, subtle shadow, rounded, padding 12
- Animations: 300ms duration
- Responsive: true, maintainAspectRatio: true

### 4.5 Dashboard layout

```
┌──────────────────────────────────────────────────────┐
│  IngestionStatus                                      │
├─────────────┬─────────────┬──────────────────────────┤
│ Avg Agent   │ Pure-AI     │ First-Time-Right         │
│ Attrib.     │ Commit %    │ Rate                     │
│   97.1%     │   89.4%     │   92.3%                  │
├─────────────┴─────────────┴──────────────────────────┤
│  Agent % Over Time — smoothed (line, full width)     │
├──────────────────────────┬───────────────────────────┤
│ Attribution Breakdown    │ AI Usage by Developer     │
│ (stacked bar)            │ (horizontal bar)          │
├──────────────────────────┬───────────────────────────┤
│ Model Distribution       │ Files by Layer            │
│ (doughnut)               │ (stacked bar)             │
├──────────────────────────┬───────────────────────────┤
│ Human Edit Rate          │ Commit Cadence            │
│ (bar)                    │ (bar)                     │
└──────────────────────────┴───────────────────────────┘
```

### 4.6 Dashboard.tsx rewrite

- Remove all old chart imports
- Import new Chart.js components
- Single data hook (`useGitAiDashboard`) fetches `GET /api/gitai/dashboard`
- Pass data slices to each chart component as props (no per-chart API calls)
- Keep `IngestionStatus` component (it still works via the existing `/api/status` endpoint)
- Keep `ChartCard` wrapper (same white card styling, updated padding)

### 4.7 Hooks cleanup

**Remove** (Entire-specific, no longer used):
- `useSessionsOverTime`, `useAgentPercentage`, `useSlashCommands`, `useToolUsage`
- `useFriction`, `useOpenItems`, `useFilesPerSession`, `useSessionDuration`
- `useCrossRepoSessions`

**Add:**
- `useGitAiDashboard()` — fetches `/api/gitai/dashboard`

**Keep:**
- `useGitAiCommits()` — used by CommitListPage
- `useGitAiSummary()` — may be used elsewhere
- `useEntireVsGitAi()` — can remove later but harmless
- `useCommitDetail()` — used by CommitDetailPage

### 4.8 API client updates

Add `GitAiDashboardData` interface matching the endpoint response. Add `api.gitai.dashboard()` method. Keep existing methods (used by other pages).

## 5. Visual Design

### 5.1 Color palette

| Purpose | Color | Tailwind | Hex |
|---------|-------|----------|-----|
| AI/Agent (primary) | Indigo | indigo-500 | `#6366f1` |
| Human | Emerald | emerald-500 | `#10b981` |
| Accent 1 | Violet | violet-500 | `#8b5cf6` |
| Accent 2 | Pink | pink-500 | `#ec4899` |
| Accent 3 | Amber | amber-500 | `#f59e0b` |
| Accent 4 | Cyan | cyan-500 | `#06b6d4` |

### 5.2 Stat cards

- Large bold number (text-3xl)
- Small uppercase label above (text-xs tracking-wider)
- Colored left border (4px, indigo for AI metrics, emerald for quality)
- Light background tint matching the border
- Grid: 3 columns

### 5.3 Chart cards

- White background, `border-gray-200`, `rounded-lg`, `p-5`
- Title: `text-sm font-semibold text-gray-700`
- Standard chart height: 280px
- Full-width line chart height: 320px

### 5.4 Agent % Over Time specifics

- 3-commit rolling average smoothing
- Semi-transparent fill: `rgba(99, 102, 241, 0.1)`
- Line: `#6366f1`, 2px, tension 0.3
- Points hidden, shown on hover
- X-axis: date labels, Y-axis: 0-100% scale

### 5.5 Doughnut specifics (Model Distribution)

- Cutout: 65% (donut, not pie)
- Legend: bottom position
- Colors from accent palette
- Center text showing total commits (via plugin or overlay)

## 6. Files Summary

### Backend (`entire-poc-backend`)

| Action | File |
|--------|------|
| Modify | `src/api/routes/gitai.ts` — add `/api/gitai/dashboard` endpoint |

### Frontend (`entire-poc-frontend`)

| Action | File |
|--------|------|
| Install | `chart.js`, `react-chartjs-2` |
| Remove dep | `recharts` |
| Create | `src/lib/chartDefaults.ts` |
| Create | `src/components/charts/StatCards.tsx` |
| Create | `src/components/charts/AgentPctOverTime.tsx` |
| Create | `src/components/charts/AttributionBreakdown.tsx` |
| Create | `src/components/charts/AiByDeveloper.tsx` |
| Create | `src/components/charts/ModelDistribution.tsx` |
| Create | `src/components/charts/FilesByLayer.tsx` |
| Create | `src/components/charts/HumanEditRate.tsx` |
| Create | `src/components/charts/CommitCadence.tsx` |
| Rewrite | `src/components/Dashboard.tsx` |
| Modify | `src/api/client.ts` — add dashboard types/method |
| Modify | `src/hooks/useChartData.ts` — remove Entire hooks, add useGitAiDashboard |
| Delete | 12 old chart/component files (listed in 4.2) |

## 7. Non-goals

- Keeping Recharts as a dependency
- Keeping Entire-sourced charts
- Adding new backend tables or migrations
- Token/session analytics (Entire-only data, not available from Git AI)
- Pagination or filtering on charts
- Dark mode
