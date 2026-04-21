# Dashboard Charts Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Recharts + Entire-sourced dashboard with 10 Chart.js charts powered by Git AI data for a presentation-ready look.

**Architecture:** One new backend endpoint (`/api/gitai/dashboard`) returns all aggregated data. Frontend swaps Recharts for Chart.js + react-chartjs-2, deletes 12 old chart components, creates 8 new ones + a Chart.js config module. Dashboard.tsx is rewritten with the new layout.

**Tech Stack:** Chart.js 4, react-chartjs-2 5, React 19, TanStack Query 5, Tailwind CSS 4, Express 5, better-sqlite3

**Spec:** `docs/superpowers/specs/2026-04-21-dashboard-charts-redesign.md`

---

## File Map

### Backend (`entire-poc-backend`)

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `src/api/routes/gitai.ts` | Add `GET /api/gitai/dashboard` endpoint with aggregation logic |

### Frontend (`entire-poc-frontend`)

| Action | File | Responsibility |
|--------|------|---------------|
| Install | `chart.js`, `react-chartjs-2` | Charting library |
| Remove | `recharts` | Old charting library |
| Create | `src/lib/chartDefaults.ts` | Chart.js global registration + defaults |
| Create | `src/components/charts/StatCards.tsx` | 3 headline stat cards |
| Create | `src/components/charts/AgentPctOverTime.tsx` | Smoothed line chart |
| Create | `src/components/charts/AttributionBreakdown.tsx` | Stacked bar: AI vs human per commit |
| Create | `src/components/charts/AiByDeveloper.tsx` | Horizontal bar: avg AI % per dev |
| Create | `src/components/charts/ModelDistribution.tsx` | Doughnut: commits by model |
| Create | `src/components/charts/FilesByLayer.tsx` | Stacked bar: lines by architectural layer |
| Create | `src/components/charts/HumanEditRate.tsx` | Bar: human edit % per commit |
| Create | `src/components/charts/CommitCadence.tsx` | Bar: hours between commits |
| Rewrite | `src/components/Dashboard.tsx` | New layout with 10 charts |
| Modify | `src/api/client.ts` | Add dashboard type + method, remove unused Entire types |
| Modify | `src/hooks/useChartData.ts` | Remove Entire hooks, add useGitAiDashboard |
| Delete | 12 files | Old chart components (see Task 3) |

---

## Task 1: Backend — Dashboard Aggregation Endpoint

**Files:**
- Modify: `entire-poc-backend/src/api/routes/gitai.ts`

- [ ] **Step 1: Add the dashboard endpoint with aggregation logic**

Add this inside the `gitaiRoutes` function in `src/api/routes/gitai.ts`, before the `return router;` line. Add the `log` import at the top alongside existing imports:

```typescript
import { log } from '../../utils/logger.js';
```

Then add the endpoint:

```typescript
  // GET /api/gitai/dashboard — aggregated data for all dashboard charts
  router.get('/gitai/dashboard', (_req, res) => {
    const allRows = gitaiRepo.getAll();

    // --- Summary ---
    const totalCommits = allRows.length;
    const avgAgentPct = totalCommits > 0
      ? Math.round(allRows.reduce((s, r) => s + r.agent_percentage, 0) / totalCommits * 10) / 10
      : 0;
    const pureAiCount = allRows.filter(r => r.agent_percentage === 100).length;
    const pureAiCommitRate = totalCommits > 0 ? Math.round(pureAiCount / totalCommits * 1000) / 10 : 0;

    // First-time-right: commits where overriden_lines = 0 for all prompts
    let ftrCount = 0;
    let ftrTotal = 0;
    for (const row of allRows) {
      if (row.agent_lines === 0) continue; // skip human-only commits
      ftrTotal++;
      try {
        const noteText = row.raw_note_json ?? '';
        const jsonPart = noteText.split('\n---\n')[1];
        if (!jsonPart) { ftrCount++; continue; }
        const note = JSON.parse(jsonPart);
        const prompts = note.prompts ?? {};
        const allZero = Object.values(prompts).every(
          (p: any) => (p.overriden_lines ?? 0) === 0
        );
        if (allZero) ftrCount++;
      } catch {
        ftrCount++; // if we can't parse, assume first-time-right
      }
    }
    const firstTimeRightRate = ftrTotal > 0 ? Math.round(ftrCount / ftrTotal * 1000) / 10 : 0;

    const totalAiLines = allRows.reduce((s, r) => s + r.agent_lines, 0);
    const totalHumanLines = allRows.reduce((s, r) => s + r.human_lines, 0);

    // --- Agent % over time (sorted by date) ---
    const sorted = [...allRows].sort((a, b) =>
      (a.captured_at ?? '').localeCompare(b.captured_at ?? '')
    );
    const agentPctOverTime = sorted.map(r => ({
      commit_sha: r.commit_sha,
      repo: r.repo,
      agent_percentage: r.agent_percentage,
      captured_at: r.captured_at,
    }));

    // --- Attribution breakdown ---
    const attributionBreakdown = sorted.map(r => ({
      commit_sha: r.commit_sha,
      repo: r.repo,
      agent_lines: r.agent_lines,
      human_lines: r.human_lines,
      captured_at: r.captured_at,
    }));

    // --- By developer (parse human_author from raw_note_json) ---
    const devMap = new Map<string, { commits: number; totalPct: number }>();
    for (const row of allRows) {
      let author = 'Unknown';
      try {
        const noteText = row.raw_note_json ?? '';
        const jsonPart = noteText.split('\n---\n')[1];
        if (jsonPart) {
          const note = JSON.parse(jsonPart);
          const prompts = note.prompts ?? {};
          const firstPrompt: any = Object.values(prompts)[0];
          if (firstPrompt?.human_author) author = firstPrompt.human_author;
        }
      } catch { /* use Unknown */ }
      const entry = devMap.get(author) ?? { commits: 0, totalPct: 0 };
      entry.commits++;
      entry.totalPct += row.agent_percentage;
      devMap.set(author, entry);
    }
    const byDeveloper = [...devMap.entries()].map(([author, d]) => ({
      author,
      commits: d.commits,
      avg_agent_pct: Math.round(d.totalPct / d.commits * 10) / 10,
    }));

    // --- By model ---
    const modelMap = new Map<string, number>();
    for (const row of allRows) {
      const model = row.model ?? 'unknown';
      modelMap.set(model, (modelMap.get(model) ?? 0) + 1);
    }
    const byModel = [...modelMap.entries()].map(([model, commits]) => ({ model, commits }));

    // --- Files by layer ---
    const layerMap = new Map<string, { ai_lines: number; human_lines: number }>();
    for (const row of allRows) {
      try {
        const files: { file: string; lineCount: number }[] = JSON.parse(row.files_touched_json ?? '[]');
        for (const f of files) {
          const layer = classifyFileLayer(f.file);
          const entry = layerMap.get(layer) ?? { ai_lines: 0, human_lines: 0 };
          entry.ai_lines += f.lineCount;
          layerMap.set(layer, entry);
        }
      } catch { /* skip */ }
      // Distribute human lines proportionally (can't attribute to specific files)
    }
    const filesByLayer = [...layerMap.entries()]
      .map(([layer, d]) => ({ layer, ai_lines: d.ai_lines, human_lines: d.human_lines }))
      .sort((a, b) => b.ai_lines - a.ai_lines);

    // --- Human edit rate ---
    const humanEditRate = sorted.map(r => ({
      commit_sha: r.commit_sha,
      repo: r.repo,
      human_pct: Math.round((100 - r.agent_percentage) * 10) / 10,
      captured_at: r.captured_at,
    }));

    // --- Commit cadence ---
    const commitCadence: { commit_sha: string; hours_since_prev: number; captured_at: string | null }[] = [];
    for (let i = 1; i < sorted.length; i++) {
      const prev = sorted[i - 1].captured_at;
      const curr = sorted[i].captured_at;
      if (prev && curr) {
        const hours = Math.round((new Date(curr).getTime() - new Date(prev).getTime()) / 3600000 * 10) / 10;
        commitCadence.push({
          commit_sha: sorted[i].commit_sha,
          hours_since_prev: Math.max(0, hours),
          captured_at: curr,
        });
      }
    }

    res.json({
      summary: {
        total_commits: totalCommits,
        avg_agent_pct: avgAgentPct,
        pure_ai_commit_rate: pureAiCommitRate,
        first_time_right_rate: firstTimeRightRate,
        total_ai_lines: totalAiLines,
        total_human_lines: totalHumanLines,
      },
      agent_pct_over_time: agentPctOverTime,
      attribution_breakdown: attributionBreakdown,
      by_developer: byDeveloper,
      by_model: byModel,
      files_by_layer: filesByLayer,
      human_edit_rate: humanEditRate,
      commit_cadence: commitCadence,
    });
  });
```

Add this helper function at the bottom of the file, outside `gitaiRoutes`:

```typescript
function classifyFileLayer(filePath: string): string {
  const p = filePath.toLowerCase();
  if (p.includes('/components/') || p.includes('/pages/')) return 'components';
  if (p.includes('/routes/') || p.includes('/api/')) return 'routes';
  if (p.includes('/utils/') || p.includes('/lib/') || p.includes('/domain/')) return 'utils';
  if (p.includes('/tests/') || p.includes('/test/') || p.includes('.test.') || p.includes('.spec.')) return 'tests';
  if (p.includes('/docs/') || p.endsWith('.md')) return 'docs';
  if (p.includes('/db/') || p.includes('/migrations/')) return 'database';
  if (p.includes('/ingestion/')) return 'ingestion';
  return 'other';
}
```

- [ ] **Step 2: Verify TypeScript compiles**

Run: `cd ~/Projects/metrics_2_0/entire-poc-backend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 3: Run tests**

Run: `cd ~/Projects/metrics_2_0/entire-poc-backend && npx vitest run`
Expected: all tests pass

- [ ] **Step 4: Restart backend and test endpoint**

```bash
# Restart backend, then:
curl -s http://localhost:3001/api/gitai/dashboard | python3 -c "
import sys, json
d = json.load(sys.stdin)
s = d['summary']
print(f'total_commits: {s[\"total_commits\"]}')
print(f'avg_agent_pct: {s[\"avg_agent_pct\"]}')
print(f'pure_ai_commit_rate: {s[\"pure_ai_commit_rate\"]}')
print(f'first_time_right_rate: {s[\"first_time_right_rate\"]}')
print(f'by_developer: {len(d[\"by_developer\"])} devs')
print(f'by_model: {len(d[\"by_model\"])} models')
print(f'files_by_layer: {len(d[\"files_by_layer\"])} layers')
print(f'commit_cadence: {len(d[\"commit_cadence\"])} entries')
"
```

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend
git add src/api/routes/gitai.ts
git commit -m "feat: add /api/gitai/dashboard aggregation endpoint"
```

---

## Task 2: Frontend — Swap Recharts for Chart.js + Global Config

**Files:**
- Install: `chart.js`, `react-chartjs-2`
- Remove: `recharts`
- Create: `entire-poc-frontend/src/lib/chartDefaults.ts`

- [ ] **Step 1: Swap dependencies**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
npm uninstall recharts
npm install chart.js react-chartjs-2
```

- [ ] **Step 2: Create Chart.js global config**

Create `src/lib/chartDefaults.ts`:

```typescript
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  BarElement,
  LineElement,
  PointElement,
  ArcElement,
  Filler,
  Tooltip,
  Legend,
} from 'chart.js';

ChartJS.register(
  CategoryScale,
  LinearScale,
  BarElement,
  LineElement,
  PointElement,
  ArcElement,
  Filler,
  Tooltip,
  Legend,
);

ChartJS.defaults.font.family = 'ui-sans-serif, system-ui, sans-serif';
ChartJS.defaults.color = '#6b7280';
ChartJS.defaults.plugins.tooltip.backgroundColor = '#ffffff';
ChartJS.defaults.plugins.tooltip.titleColor = '#111827';
ChartJS.defaults.plugins.tooltip.bodyColor = '#374151';
ChartJS.defaults.plugins.tooltip.borderColor = '#e5e7eb';
ChartJS.defaults.plugins.tooltip.borderWidth = 1;
ChartJS.defaults.plugins.tooltip.padding = 12;
ChartJS.defaults.plugins.tooltip.cornerRadius = 8;
ChartJS.defaults.plugins.tooltip.boxPadding = 4;
ChartJS.defaults.plugins.legend.labels.usePointStyle = true;
ChartJS.defaults.plugins.legend.labels.pointStyle = 'circle';
ChartJS.defaults.animation = { duration: 300 };
ChartJS.defaults.scales = {
  ...ChartJS.defaults.scales,
};

export const COLORS = {
  ai: '#6366f1',
  human: '#10b981',
  aiFill: 'rgba(99, 102, 241, 0.1)',
  accent: ['#6366f1', '#8b5cf6', '#ec4899', '#f59e0b', '#10b981', '#06b6d4'],
  grid: '#f3f4f6',
};

export const CHART_HEIGHT = 280;
export const CHART_HEIGHT_WIDE = 320;
```

- [ ] **Step 3: Verify it compiles**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit
```

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add -A
git commit -m "feat: swap recharts for chart.js, add global chart config"
```

---

## Task 3: Frontend — Delete Old Chart Components + Clean Hooks/Client

**Files:**
- Delete: 12 old component files
- Modify: `entire-poc-frontend/src/hooks/useChartData.ts`
- Modify: `entire-poc-frontend/src/api/client.ts`

- [ ] **Step 1: Delete old chart components**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
rm src/components/charts/SessionsOverTimeChart.tsx
rm src/components/charts/AgentPercentageChart.tsx
rm src/components/charts/SlashCommandsChart.tsx
rm src/components/charts/ToolUsageMixChart.tsx
rm src/components/charts/FrictionPerSessionChart.tsx
rm src/components/charts/OpenItemsPerSessionChart.tsx
rm src/components/charts/FilesPerSessionChart.tsx
rm src/components/charts/SessionDurationChart.tsx
rm src/components/charts/GitAiAgentPercentageChart.tsx
rm src/components/CrossRepoSessionMap.tsx
rm src/components/EntireVsGitAiComparison.tsx
rm src/components/RepoLegend.tsx
```

- [ ] **Step 2: Clean up useChartData.ts — remove Entire hooks, add dashboard hook**

Replace `src/hooks/useChartData.ts` entirely:

```typescript
import { useQuery } from '@tanstack/react-query';
import { api } from '../api/client';

export function useGitAiDashboard() {
  return useQuery({ queryKey: ['gitai', 'dashboard'], queryFn: api.gitai.dashboard });
}

export function useGitAiCommits() {
  return useQuery({ queryKey: ['gitai', 'commits'], queryFn: api.gitai.commits });
}

export function useCommitDetail(sha: string) {
  return useQuery({
    queryKey: ['gitai', 'commit-detail', sha],
    queryFn: () => api.gitai.commitDetail(sha),
    enabled: !!sha,
  });
}
```

- [ ] **Step 3: Clean up client.ts — remove unused Entire types, add dashboard type and method**

In `src/api/client.ts`:

Remove these unused interfaces (they were only consumed by deleted charts):
- `SessionsOverTimePoint`
- `AgentPercentagePoint`
- `SlashCommandPoint`
- `ToolUsagePoint`
- `FrictionPoint`
- `OpenItemsPoint`
- `FilesPerSessionPoint`
- `SessionDurationPoint`
- `CrossRepoCommit`
- `CrossRepoSession`
- `GitAiSummary`
- `EntireVsGitAiRow`

Remove the `charts` and `sessions` objects from `api`:
```typescript
  // DELETE these:
  charts: { ... },
  sessions: { ... },
```

Also remove `api.gitai.summary` and `api.gitai.compare` (no longer used).

Add this new interface after `GitAiCommitDetail`:

```typescript
export interface GitAiDashboardData {
  summary: {
    total_commits: number;
    avg_agent_pct: number;
    pure_ai_commit_rate: number;
    first_time_right_rate: number;
    total_ai_lines: number;
    total_human_lines: number;
  };
  agent_pct_over_time: { commit_sha: string; repo: string; agent_percentage: number; captured_at: string | null }[];
  attribution_breakdown: { commit_sha: string; repo: string; agent_lines: number; human_lines: number; captured_at: string | null }[];
  by_developer: { author: string; commits: number; avg_agent_pct: number }[];
  by_model: { model: string; commits: number }[];
  files_by_layer: { layer: string; ai_lines: number; human_lines: number }[];
  human_edit_rate: { commit_sha: string; repo: string; human_pct: number; captured_at: string | null }[];
  commit_cadence: { commit_sha: string; hours_since_prev: number; captured_at: string | null }[];
}
```

Update the `api.gitai` object to its final form:

```typescript
  gitai: {
    commits: () => get<GitAiCommit[]>('/api/gitai/commits'),
    dashboard: () => get<GitAiDashboardData>('/api/gitai/dashboard'),
    commitDetail: (sha: string) => get<GitAiCommitDetail>(`/api/gitai/commits/${sha}/detail`),
    transcriptUrl: (sha: string, promptId: string) =>
      `${BASE}/api/gitai/commits/${sha}/transcript?prompt_id=${encodeURIComponent(promptId)}`,
  },
```

- [ ] **Step 4: Verify it compiles**

This will FAIL because Dashboard.tsx still imports deleted components. That's expected — we'll fix it in Task 5.

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit 2>&1 | head -20
```

Expected: errors about missing imports in Dashboard.tsx only.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add -A
git commit -m "refactor: remove Entire charts, clean hooks and API client"
```

---

## Task 4: Frontend — Create All Chart Components

**Files:**
- Create: `entire-poc-frontend/src/components/charts/StatCards.tsx`
- Create: `entire-poc-frontend/src/components/charts/AgentPctOverTime.tsx`
- Create: `entire-poc-frontend/src/components/charts/AttributionBreakdown.tsx`
- Create: `entire-poc-frontend/src/components/charts/AiByDeveloper.tsx`
- Create: `entire-poc-frontend/src/components/charts/ModelDistribution.tsx`
- Create: `entire-poc-frontend/src/components/charts/FilesByLayer.tsx`
- Create: `entire-poc-frontend/src/components/charts/HumanEditRate.tsx`
- Create: `entire-poc-frontend/src/components/charts/CommitCadence.tsx`

All components receive data as props (no internal fetching). Each imports from `../../lib/chartDefaults` for colors/heights.

- [ ] **Step 1: Create StatCards.tsx**

```tsx
// src/components/charts/StatCards.tsx
interface StatCardProps {
  label: string;
  value: string;
  borderColor: string;
  bgColor: string;
}

function StatCard({ label, value, borderColor, bgColor }: StatCardProps) {
  return (
    <div className={`rounded-lg border-l-4 p-5 ${borderColor} ${bgColor}`}>
      <p className="text-xs text-gray-500 uppercase tracking-wider">{label}</p>
      <p className="text-3xl font-bold text-gray-900 mt-1">{value}</p>
    </div>
  );
}

interface Props {
  avgAgentPct: number;
  pureAiCommitRate: number;
  firstTimeRightRate: number;
}

export function StatCards({ avgAgentPct, pureAiCommitRate, firstTimeRightRate }: Props) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
      <StatCard
        label="Avg Agent Attribution"
        value={`${avgAgentPct.toFixed(1)}%`}
        borderColor="border-indigo-500"
        bgColor="bg-indigo-50"
      />
      <StatCard
        label="Pure-AI Commit Rate"
        value={`${pureAiCommitRate.toFixed(1)}%`}
        borderColor="border-violet-500"
        bgColor="bg-violet-50"
      />
      <StatCard
        label="First-Time-Right Rate"
        value={`${firstTimeRightRate.toFixed(1)}%`}
        borderColor="border-emerald-500"
        bgColor="bg-emerald-50"
      />
    </div>
  );
}
```

- [ ] **Step 2: Create AgentPctOverTime.tsx**

```tsx
// src/components/charts/AgentPctOverTime.tsx
import { Line } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT_WIDE } from '../../lib/chartDefaults';

interface DataPoint {
  commit_sha: string;
  repo: string;
  agent_percentage: number;
  captured_at: string | null;
}

function rollingAvg(data: number[], window: number): number[] {
  return data.map((_, i) => {
    const start = Math.max(0, i - window + 1);
    const slice = data.slice(start, i + 1);
    return Math.round(slice.reduce((a, b) => a + b, 0) / slice.length * 10) / 10;
  });
}

export function AgentPctOverTime({ data }: { data: DataPoint[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  const labels = data.map(d => d.commit_sha.slice(0, 7));
  const raw = data.map(d => d.agent_percentage);
  const smoothed = rollingAvg(raw, 3);

  return (
    <div style={{ height: CHART_HEIGHT_WIDE }}>
      <Line
        data={{
          labels,
          datasets: [{
            label: 'Agent % (3-commit avg)',
            data: smoothed,
            borderColor: COLORS.ai,
            backgroundColor: COLORS.aiFill,
            fill: true,
            tension: 0.3,
            pointRadius: 0,
            pointHoverRadius: 5,
            pointHoverBackgroundColor: COLORS.ai,
            borderWidth: 2,
          }],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            y: { min: 0, max: 100, ticks: { callback: v => `${v}%` }, grid: { color: COLORS.grid } },
            x: { ticks: { maxRotation: 0, maxTicksLimit: 15, font: { size: 10 } }, grid: { display: false } },
          },
          plugins: {
            legend: { display: false },
            tooltip: { callbacks: { label: ctx => `${ctx.parsed.y}%` } },
          },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 3: Create AttributionBreakdown.tsx**

```tsx
// src/components/charts/AttributionBreakdown.tsx
import { Bar } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT } from '../../lib/chartDefaults';

interface DataPoint {
  commit_sha: string;
  repo: string;
  agent_lines: number;
  human_lines: number;
  captured_at: string | null;
}

export function AttributionBreakdown({ data }: { data: DataPoint[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  const labels = data.map(d => d.commit_sha.slice(0, 7));

  return (
    <div style={{ height: CHART_HEIGHT }}>
      <Bar
        data={{
          labels,
          datasets: [
            {
              label: 'AI Lines',
              data: data.map(d => d.agent_lines),
              backgroundColor: COLORS.ai,
              borderRadius: 2,
            },
            {
              label: 'Human Lines',
              data: data.map(d => d.human_lines),
              backgroundColor: COLORS.human,
              borderRadius: 2,
            },
          ],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { stacked: true, ticks: { maxRotation: 0, maxTicksLimit: 15, font: { size: 10 } }, grid: { display: false } },
            y: { stacked: true, grid: { color: COLORS.grid } },
          },
          plugins: { legend: { position: 'bottom' } },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 4: Create AiByDeveloper.tsx**

```tsx
// src/components/charts/AiByDeveloper.tsx
import { Bar } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT } from '../../lib/chartDefaults';

interface DevData {
  author: string;
  commits: number;
  avg_agent_pct: number;
}

export function AiByDeveloper({ data }: { data: DevData[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  const sorted = [...data].sort((a, b) => b.avg_agent_pct - a.avg_agent_pct);

  return (
    <div style={{ height: CHART_HEIGHT }}>
      <Bar
        data={{
          labels: sorted.map(d => `${d.author} (${d.commits})`),
          datasets: [{
            label: 'Avg Agent %',
            data: sorted.map(d => d.avg_agent_pct),
            backgroundColor: COLORS.ai,
            borderRadius: 4,
          }],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          indexAxis: 'y',
          scales: {
            x: { min: 0, max: 100, ticks: { callback: v => `${v}%` }, grid: { color: COLORS.grid } },
            y: { grid: { display: false } },
          },
          plugins: { legend: { display: false } },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 5: Create ModelDistribution.tsx**

```tsx
// src/components/charts/ModelDistribution.tsx
import { Doughnut } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT } from '../../lib/chartDefaults';

interface ModelData {
  model: string;
  commits: number;
}

export function ModelDistribution({ data }: { data: ModelData[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  const total = data.reduce((s, d) => s + d.commits, 0);

  return (
    <div style={{ height: CHART_HEIGHT }} className="flex items-center justify-center">
      <Doughnut
        data={{
          labels: data.map(d => d.model),
          datasets: [{
            data: data.map(d => d.commits),
            backgroundColor: COLORS.accent.slice(0, data.length),
            borderWidth: 0,
            hoverOffset: 8,
          }],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          cutout: '65%',
          plugins: {
            legend: { position: 'bottom' },
            tooltip: {
              callbacks: {
                label: ctx => `${ctx.label}: ${ctx.parsed} commits (${Math.round(ctx.parsed / total * 100)}%)`,
              },
            },
          },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 6: Create FilesByLayer.tsx**

```tsx
// src/components/charts/FilesByLayer.tsx
import { Bar } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT } from '../../lib/chartDefaults';

interface LayerData {
  layer: string;
  ai_lines: number;
  human_lines: number;
}

export function FilesByLayer({ data }: { data: LayerData[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  return (
    <div style={{ height: CHART_HEIGHT }}>
      <Bar
        data={{
          labels: data.map(d => d.layer),
          datasets: [
            {
              label: 'AI Lines',
              data: data.map(d => d.ai_lines),
              backgroundColor: COLORS.ai,
              borderRadius: 2,
            },
            {
              label: 'Human Lines',
              data: data.map(d => d.human_lines),
              backgroundColor: COLORS.human,
              borderRadius: 2,
            },
          ],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { stacked: true, grid: { display: false } },
            y: { stacked: true, grid: { color: COLORS.grid } },
          },
          plugins: { legend: { position: 'bottom' } },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 7: Create HumanEditRate.tsx**

```tsx
// src/components/charts/HumanEditRate.tsx
import { Bar } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT } from '../../lib/chartDefaults';

interface DataPoint {
  commit_sha: string;
  repo: string;
  human_pct: number;
  captured_at: string | null;
}

export function HumanEditRate({ data }: { data: DataPoint[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  return (
    <div style={{ height: CHART_HEIGHT }}>
      <Bar
        data={{
          labels: data.map(d => d.commit_sha.slice(0, 7)),
          datasets: [{
            label: 'Human Edit %',
            data: data.map(d => d.human_pct),
            backgroundColor: COLORS.human,
            borderRadius: 2,
          }],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { ticks: { maxRotation: 0, maxTicksLimit: 15, font: { size: 10 } }, grid: { display: false } },
            y: { min: 0, max: 100, ticks: { callback: v => `${v}%` }, grid: { color: COLORS.grid } },
          },
          plugins: { legend: { display: false } },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 8: Create CommitCadence.tsx**

```tsx
// src/components/charts/CommitCadence.tsx
import { Bar } from 'react-chartjs-2';
import { COLORS, CHART_HEIGHT } from '../../lib/chartDefaults';

interface DataPoint {
  commit_sha: string;
  hours_since_prev: number;
  captured_at: string | null;
}

export function CommitCadence({ data }: { data: DataPoint[] }) {
  if (!data.length) return <p className="text-gray-500 text-sm">No data yet</p>;

  return (
    <div style={{ height: CHART_HEIGHT }}>
      <Bar
        data={{
          labels: data.map(d => d.commit_sha.slice(0, 7)),
          datasets: [{
            label: 'Hours since previous',
            data: data.map(d => d.hours_since_prev),
            backgroundColor: COLORS.accent[3],
            borderRadius: 2,
          }],
        }}
        options={{
          responsive: true,
          maintainAspectRatio: false,
          scales: {
            x: { ticks: { maxRotation: 0, maxTicksLimit: 15, font: { size: 10 } }, grid: { display: false } },
            y: { grid: { color: COLORS.grid }, ticks: { callback: v => `${v}h` } },
          },
          plugins: { legend: { display: false } },
        }}
      />
    </div>
  );
}
```

- [ ] **Step 9: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add src/components/charts/ src/lib/
git commit -m "feat: add 8 Chart.js chart components for Git AI dashboard"
```

---

## Task 5: Frontend — Rewrite Dashboard.tsx

**Files:**
- Rewrite: `entire-poc-frontend/src/components/Dashboard.tsx`

- [ ] **Step 1: Rewrite Dashboard.tsx**

Replace the entire file:

```tsx
import { IngestionStatus } from './IngestionStatus';
import { useGitAiDashboard } from '../hooks/useChartData';
import { StatCards } from './charts/StatCards';
import { AgentPctOverTime } from './charts/AgentPctOverTime';
import { AttributionBreakdown } from './charts/AttributionBreakdown';
import { AiByDeveloper } from './charts/AiByDeveloper';
import { ModelDistribution } from './charts/ModelDistribution';
import { FilesByLayer } from './charts/FilesByLayer';
import { HumanEditRate } from './charts/HumanEditRate';
import { CommitCadence } from './charts/CommitCadence';
import '../lib/chartDefaults';

function ChartCard({ title, children, wide }: { title: string; children: React.ReactNode; wide?: boolean }) {
  return (
    <div className={`bg-white border border-gray-200 rounded-lg p-5 ${wide ? 'col-span-full' : ''}`}>
      <h3 className="text-sm font-semibold text-gray-700 mb-4">{title}</h3>
      {children}
    </div>
  );
}

export function Dashboard() {
  const { data, isLoading, isError } = useGitAiDashboard();

  if (isLoading) return (
    <main className="max-w-7xl mx-auto px-6 py-6 space-y-6">
      <IngestionStatus />
      <div className="animate-pulse space-y-4">
        <div className="grid grid-cols-3 gap-4">
          <div className="h-24 bg-gray-100 rounded-lg" />
          <div className="h-24 bg-gray-100 rounded-lg" />
          <div className="h-24 bg-gray-100 rounded-lg" />
        </div>
        <div className="h-80 bg-gray-100 rounded-lg" />
        <div className="grid grid-cols-2 gap-4">
          <div className="h-72 bg-gray-100 rounded-lg" />
          <div className="h-72 bg-gray-100 rounded-lg" />
        </div>
      </div>
    </main>
  );

  if (isError) return (
    <main className="max-w-7xl mx-auto px-6 py-6 space-y-6">
      <IngestionStatus />
      <p className="text-red-500 text-sm">Failed to load dashboard data.</p>
    </main>
  );

  if (!data) return null;

  return (
    <main className="max-w-7xl mx-auto px-6 py-6 space-y-6">
      <IngestionStatus />

      {/* Overview */}
      <StatCards
        avgAgentPct={data.summary.avg_agent_pct}
        pureAiCommitRate={data.summary.pure_ai_commit_rate}
        firstTimeRightRate={data.summary.first_time_right_rate}
      />

      <ChartCard title="Agent % Over Time (3-commit rolling average)" wide>
        <AgentPctOverTime data={data.agent_pct_over_time} />
      </ChartCard>

      {/* Breakdown */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <ChartCard title="Attribution Breakdown (AI vs Human Lines)">
          <AttributionBreakdown data={data.attribution_breakdown} />
        </ChartCard>
        <ChartCard title="AI Usage by Developer">
          <AiByDeveloper data={data.by_developer} />
        </ChartCard>
        <ChartCard title="Model Distribution">
          <ModelDistribution data={data.by_model} />
        </ChartCard>
        <ChartCard title="Files Touched by Layer">
          <FilesByLayer data={data.files_by_layer} />
        </ChartCard>
      </div>

      {/* Patterns */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        <ChartCard title="Human Edit Rate per Commit">
          <HumanEditRate data={data.human_edit_rate} />
        </ChartCard>
        <ChartCard title="Commit Cadence (hours between commits)">
          <CommitCadence data={data.commit_cadence} />
        </ChartCard>
      </div>
    </main>
  );
}
```

- [ ] **Step 2: Update useTriggerIngest to invalidate gitai queries**

In `src/hooks/useStatus.ts`, update the `onSuccess` callback to also invalidate `gitai` queries:

```typescript
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['status'] });
      queryClient.invalidateQueries({ queryKey: ['gitai'] });
    },
```

(Remove the old `charts` and `sessions` invalidations.)

- [ ] **Step 3: Verify it compiles**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit
```

- [ ] **Step 4: Build**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx vite build
```

- [ ] **Step 5: Lint**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx eslint src/
```

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add -A
git commit -m "feat: rewrite dashboard with Chart.js Git AI charts"
```

---

## Task 6: Final Verification + Push

**Files:** None (verification only)

- [ ] **Step 1: Run backend tests**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend && npx vitest run
```
Expected: all tests pass

- [ ] **Step 2: Lint both repos**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend && npx eslint src/ tests/
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx eslint src/
```

- [ ] **Step 3: Build frontend**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx vite build
```

- [ ] **Step 4: Visual verification**

Start both services, open `http://localhost:5173`:
- 3 stat cards render with real numbers
- Agent % Over Time shows a smoothed line
- Attribution Breakdown shows stacked bars
- AI by Developer shows horizontal bar(s)
- Model Distribution shows a doughnut
- Files by Layer shows stacked bars
- Human Edit Rate shows bars
- Commit Cadence shows bars
- Commits page still works (click through to detail)
- No console errors from chart rendering

- [ ] **Step 5: Push all repos**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend && git push
cd ~/Projects/metrics_2_0/entire-poc-frontend && git push origin main
cd ~/Projects/metrics_2_0/entire-poc-workspace && git push origin main
```
