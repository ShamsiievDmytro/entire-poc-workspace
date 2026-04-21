# Commit Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-commit view showing Git AI attribution data from all storage layers (Git Notes + local prompt DB).

**Architecture:** Backend adds a local DB reader for `~/.git-ai/internal/db` (read-only) and two new endpoints (detail + transcript download). Frontend adds `react-router-dom` with a nav bar, commit list page, and commit detail page with stacked sections.

**Tech Stack:** TypeScript ESM, Express 5, better-sqlite3, React 19, react-router-dom, TanStack Query, Tailwind CSS 4

**Spec:** `docs/superpowers/specs/2026-04-21-commit-detail-view-design.md`

---

## File Map

### Backend (`entire-poc-backend`)

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `src/db/gitai-local-reader.ts` | Read-only access to `~/.git-ai/internal/db` prompts table |
| Modify | `src/config.ts` | Add `GITAI_LOCAL_DB_PATH` env var |
| Modify | `src/api/routes/gitai.ts` | Add `/commits/:sha/detail` and `/commits/:sha/transcript` endpoints |

### Frontend (`entire-poc-frontend`)

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `src/components/NavBar.tsx` | Top navigation bar with Dashboard / Commits links |
| Create | `src/pages/CommitListPage.tsx` | Table of all commits with attribution summary |
| Create | `src/pages/CommitDetailPage.tsx` | Full commit detail with all Git AI data layers |
| Modify | `src/App.tsx` | Add BrowserRouter, routes, layout with NavBar |
| Modify | `src/components/Dashboard.tsx` | Remove header/footer (moved to layout) |
| Modify | `src/api/client.ts` | Add detail/transcript types and API methods |
| Modify | `src/hooks/useChartData.ts` | Add `useCommitDetail` hook |

---

## Task 1: Backend — Config + Local DB Reader

**Files:**
- Modify: `entire-poc-backend/src/config.ts`
- Create: `entire-poc-backend/src/db/gitai-local-reader.ts`

- [ ] **Step 1: Add GITAI_LOCAL_DB_PATH to config**

In `src/config.ts`, add the new env var to the Zod schema with a default that resolves `~` to `os.homedir()`:

```typescript
// At the top, add:
import { homedir } from 'node:os';
import { join } from 'node:path';

// In the Schema, add after INGESTION_INTERVAL_MS:
  GITAI_LOCAL_DB_PATH: z.string().default(join(homedir(), '.git-ai', 'internal', 'db')),
```

- [ ] **Step 2: Create gitai-local-reader.ts**

```typescript
// src/db/gitai-local-reader.ts
import Database from 'better-sqlite3';
import { existsSync } from 'node:fs';
import { config } from '../config.js';
import { log } from '../utils/logger.js';

export interface LocalPromptRecord {
  prompt_id: string;
  session_id: string;
  workdir: string | null;
  tool: string;
  model: string;
  human_author: string | null;
  total_additions: number | null;
  total_deletions: number | null;
  accepted_lines: number | null;
  overridden_lines: number | null;
  message_preview: string | null;
  message_bytes: number;
  created_at: string;
  updated_at: string;
}

let instance: Database.Database | null = null;
let initAttempted = false;

function getLocalDb(): Database.Database | null {
  if (initAttempted) return instance;
  initAttempted = true;

  const dbPath = config.GITAI_LOCAL_DB_PATH;
  if (!existsSync(dbPath)) {
    log('warn', 'Git AI local DB not found, local prompt data unavailable', { path: dbPath });
    return null;
  }

  try {
    instance = new Database(dbPath, { readonly: true });
    log('info', 'Opened Git AI local DB (read-only)', { path: dbPath });
    return instance;
  } catch (err) {
    log('error', 'Failed to open Git AI local DB', { path: dbPath, error: String(err) });
    return null;
  }
}

export function getPromptById(promptId: string): LocalPromptRecord | null {
  const db = getLocalDb();
  if (!db) return null;

  try {
    const row = db.prepare(`
      SELECT
        id AS prompt_id,
        external_thread_id AS session_id,
        workdir,
        tool,
        model,
        human_author,
        total_additions,
        total_deletions,
        accepted_lines,
        overridden_lines,
        substr(messages, 1, 500) AS message_preview,
        length(messages) AS message_bytes,
        created_at,
        updated_at
      FROM prompts
      WHERE id = ?
    `).get(promptId) as Record<string, unknown> | undefined;

    if (!row) return null;

    return {
      prompt_id: row.prompt_id as string,
      session_id: row.session_id as string,
      workdir: row.workdir as string | null,
      tool: row.tool as string,
      model: row.model as string,
      human_author: row.human_author as string | null,
      total_additions: row.total_additions as number | null,
      total_deletions: row.total_deletions as number | null,
      accepted_lines: row.accepted_lines as number | null,
      overridden_lines: row.overridden_lines as number | null,
      message_preview: row.message_preview as string | null,
      message_bytes: row.message_bytes as number,
      created_at: new Date((row.created_at as number) * 1000).toISOString(),
      updated_at: new Date((row.updated_at as number) * 1000).toISOString(),
    };
  } catch (err) {
    log('error', 'Failed to query local prompt', { promptId, error: String(err) });
    return null;
  }
}

export function getFullTranscript(promptId: string): string | null {
  const db = getLocalDb();
  if (!db) return null;

  try {
    const row = db.prepare('SELECT messages FROM prompts WHERE id = ?').get(promptId) as { messages: string } | undefined;
    return row?.messages ?? null;
  } catch (err) {
    log('error', 'Failed to fetch transcript', { promptId, error: String(err) });
    return null;
  }
}
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `cd ~/Projects/metrics_2_0/entire-poc-backend && npx tsc --noEmit`
Expected: clean, no errors

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend
git add src/config.ts src/db/gitai-local-reader.ts
git commit -m "feat: add Git AI local DB reader for prompt metadata"
```

---

## Task 2: Backend — Detail + Transcript Endpoints

**Files:**
- Modify: `entire-poc-backend/src/api/routes/gitai.ts`

- [ ] **Step 1: Add detail endpoint**

Add to `src/api/routes/gitai.ts`, inside the `gitaiRoutes` function, after the existing `/gitai/commits/:sha` route:

```typescript
import { getPromptById, getFullTranscript } from '../../db/gitai-local-reader.js';
```

```typescript
  // GET /api/gitai/commits/:sha/detail — full commit detail with local prompt data
  router.get('/gitai/commits/:sha/detail', (req, res) => {
    const rows = gitaiRepo.getBySha(req.params.sha);
    if (rows.length === 0) {
      res.status(404).json({ error: 'No Git AI attribution found for this commit' });
      return;
    }

    const row = rows[0];
    const files: unknown[] = [];
    for (const r of rows) {
      try { files.push(...JSON.parse(r.files_touched_json ?? '[]')); }
      catch { /* skip malformed */ }
    }

    const localPrompt = row.prompt_id ? getPromptById(row.prompt_id) : null;

    res.json({
      commit_sha: row.commit_sha,
      repo: row.repo,
      captured_at: row.captured_at,
      attribution: {
        agent: row.agent,
        model: row.model,
        agent_lines: row.agent_lines,
        human_lines: row.human_lines,
        agent_percentage: row.agent_percentage,
        prompt_id: row.prompt_id,
      },
      files,
      raw_note: row.raw_note_json,
      local_prompt: localPrompt,
    });
  });
```

- [ ] **Step 2: Add transcript download endpoint**

Add right after the detail endpoint:

```typescript
  // GET /api/gitai/commits/:sha/transcript — download full transcript
  router.get('/gitai/commits/:sha/transcript', (req, res) => {
    const promptId = req.query.prompt_id as string;
    if (!promptId) {
      res.status(400).json({ error: 'prompt_id query parameter required' });
      return;
    }

    const transcript = getFullTranscript(promptId);
    if (!transcript) {
      res.status(404).json({ error: 'Transcript not found for this prompt' });
      return;
    }

    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Content-Disposition', `attachment; filename=${promptId}.json`);
    res.send(transcript);
  });
```

- [ ] **Step 3: Verify TypeScript compiles**

Run: `cd ~/Projects/metrics_2_0/entire-poc-backend && npx tsc --noEmit`
Expected: clean

- [ ] **Step 4: Verify endpoints work**

Run: `cd ~/Projects/metrics_2_0/entire-poc-backend && npx vitest run`
Expected: all existing tests pass

Restart the backend server, then test:

```bash
# Detail endpoint (use a known commit SHA from the DB)
curl -s http://localhost:3001/api/gitai/commits/6df5a6e53e91c84802ed2a25a7c80eda120dd171/detail | python3 -m json.tool | head -30

# Transcript endpoint
curl -s "http://localhost:3001/api/gitai/commits/6df5a6e53e91c84802ed2a25a7c80eda120dd171/transcript?prompt_id=1612649c4bf0b88e" | head -5
```

Expected: detail returns full JSON with `local_prompt` populated; transcript returns raw JSON content.

- [ ] **Step 5: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend
git add src/api/routes/gitai.ts
git commit -m "feat: add commit detail and transcript download endpoints"
```

---

## Task 3: Frontend — Install react-router-dom + Routing Setup

**Files:**
- Modify: `entire-poc-frontend/package.json` (via npm install)
- Modify: `entire-poc-frontend/src/App.tsx`
- Create: `entire-poc-frontend/src/components/NavBar.tsx`
- Modify: `entire-poc-frontend/src/components/Dashboard.tsx`

- [ ] **Step 1: Install react-router-dom**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npm install react-router-dom
```

- [ ] **Step 2: Create NavBar component**

Create `src/components/NavBar.tsx`:

```tsx
import { NavLink } from 'react-router-dom';

export function NavBar() {
  const linkClass = ({ isActive }: { isActive: boolean }) =>
    `px-3 py-1 text-sm font-medium ${
      isActive
        ? 'text-indigo-600 border-b-2 border-indigo-600'
        : 'text-gray-500 hover:text-gray-700'
    }`;

  return (
    <header className="bg-white border-b border-gray-200 px-6 py-3">
      <div className="max-w-7xl mx-auto flex items-center justify-between">
        <h1 className="text-xl font-bold text-gray-900">Entire PoC Dashboard</h1>
        <nav className="flex gap-2">
          <NavLink to="/" end className={linkClass}>Dashboard</NavLink>
          <NavLink to="/commits" className={linkClass}>Commits</NavLink>
        </nav>
      </div>
    </header>
  );
}
```

- [ ] **Step 3: Update App.tsx with routing**

Replace `src/App.tsx` entirely:

```tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter, Routes, Route, Outlet } from 'react-router-dom';
import { NavBar } from './components/NavBar';
import { Dashboard } from './components/Dashboard';
import { CommitListPage } from './pages/CommitListPage';
import { CommitDetailPage } from './pages/CommitDetailPage';
import { POLL_INTERVAL_MS } from './constants';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: POLL_INTERVAL_MS,
      retry: 1,
    },
  },
});

function Layout() {
  return (
    <div className="min-h-screen bg-gray-50">
      <NavBar />
      <Outlet />
    </div>
  );
}

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Routes>
          <Route element={<Layout />}>
            <Route path="/" element={<Dashboard />} />
            <Route path="/commits" element={<CommitListPage />} />
            <Route path="/commits/:sha" element={<CommitDetailPage />} />
          </Route>
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  );
}

export default App;
```

Note: `CommitListPage` and `CommitDetailPage` don't exist yet — create placeholder files so TypeScript compiles:

Create `src/pages/CommitListPage.tsx`:
```tsx
export function CommitListPage() {
  return <div className="max-w-7xl mx-auto px-6 py-6">Commit list (coming next)</div>;
}
```

Create `src/pages/CommitDetailPage.tsx`:
```tsx
export function CommitDetailPage() {
  return <div className="max-w-7xl mx-auto px-6 py-6">Commit detail (coming next)</div>;
}
```

- [ ] **Step 4: Update Dashboard.tsx — remove header and footer, remove outer min-h-screen**

The header is now in NavBar and `min-h-screen bg-gray-50` is in the Layout. Update Dashboard to remove those wrappers:

Remove the outer `<div className="min-h-screen bg-gray-50">`, the `<header>...</header>` block, and the `<footer>...</footer>` block. Keep the `<main>` content as-is but without the wrapping div. The component should become:

```tsx
// Keep all existing imports unchanged, plus add:
import { RepoLegend } from './RepoLegend';
import { GitAiAgentPercentageChart } from './charts/GitAiAgentPercentageChart';
import { EntireVsGitAiComparison } from './EntireVsGitAiComparison';

// ChartCard stays as-is

export function Dashboard() {
  return (
    <main className="max-w-7xl mx-auto px-6 py-6 space-y-6">
      <IngestionStatus />

      <RepoLegend />

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* all existing ChartCard blocks stay exactly the same */}
      </div>

      <ChartCard title="Cross-Repo Session Map">
        <CrossRepoSessionMap />
      </ChartCard>

      <div className="border-t-2 border-blue-200 pt-6">
        {/* Git AI section stays exactly the same */}
      </div>
    </main>
  );
}
```

- [ ] **Step 5: Verify it compiles and renders**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit
```

Open `http://localhost:5173` — should see NavBar at top, Dashboard below. Click "Commits" — should see placeholder text.

- [ ] **Step 6: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add -A
git commit -m "feat: add react-router-dom, NavBar, and routing layout"
```

---

## Task 4: Frontend — API Client + Hook for Commit Detail

**Files:**
- Modify: `entire-poc-frontend/src/api/client.ts`
- Modify: `entire-poc-frontend/src/hooks/useChartData.ts`

- [ ] **Step 1: Add types and API methods to client.ts**

Add after the `EntireVsGitAiRow` interface:

```typescript
export interface GitAiFileAttribution {
  file: string;
  promptId: string;
  lineRanges: string;
  lineCount: number;
}

export interface GitAiLocalPrompt {
  prompt_id: string;
  session_id: string;
  workdir: string | null;
  tool: string;
  model: string;
  human_author: string | null;
  total_additions: number | null;
  total_deletions: number | null;
  accepted_lines: number | null;
  overridden_lines: number | null;
  message_preview: string | null;
  message_bytes: number;
  created_at: string;
  updated_at: string;
}

export interface GitAiCommitDetail {
  commit_sha: string;
  repo: string;
  captured_at: string | null;
  attribution: {
    agent: string;
    model: string | null;
    agent_lines: number;
    human_lines: number;
    agent_percentage: number;
    prompt_id: string | null;
  };
  files: GitAiFileAttribution[];
  raw_note: string | null;
  local_prompt: GitAiLocalPrompt | null;
}
```

Update the `api.gitai` object — add `commitDetail` and `transcriptUrl` after the existing entries:

```typescript
  gitai: {
    commits: () => get<GitAiCommit[]>('/api/gitai/commits'),
    summary: () => get<GitAiSummary>('/api/gitai/summary'),
    compare: () => get<EntireVsGitAiRow[]>('/api/compare/entire-vs-gitai'),
    commitDetail: (sha: string) => get<GitAiCommitDetail>(`/api/gitai/commits/${sha}/detail`),
    transcriptUrl: (sha: string, promptId: string) =>
      `${BASE}/api/gitai/commits/${sha}/transcript?prompt_id=${encodeURIComponent(promptId)}`,
  },
```

- [ ] **Step 2: Add useCommitDetail hook**

Add at the end of `src/hooks/useChartData.ts`:

```typescript
export function useCommitDetail(sha: string) {
  return useQuery({
    queryKey: ['gitai', 'commit-detail', sha],
    queryFn: () => api.gitai.commitDetail(sha),
    enabled: !!sha,
  });
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit
```

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add src/api/client.ts src/hooks/useChartData.ts
git commit -m "feat: add commit detail API types and hook"
```

---

## Task 5: Frontend — Commit List Page

**Files:**
- Modify: `entire-poc-frontend/src/pages/CommitListPage.tsx` (replace placeholder)

- [ ] **Step 1: Implement CommitListPage**

Replace `src/pages/CommitListPage.tsx`:

```tsx
import { useNavigate } from 'react-router-dom';
import { useGitAiCommits } from '../hooks/useChartData';
import { REPO_PREFIX } from '../constants';

const REPO_COLORS: Record<string, string> = {
  'entire-poc-backend': 'bg-indigo-100 text-indigo-800',
  'entire-poc-frontend': 'bg-amber-100 text-amber-800',
  'entire-poc-workspace': 'bg-green-100 text-green-800',
};

function formatDate(value: string | null): string {
  if (!value) return '—';
  const d = new Date(value);
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

export function CommitListPage() {
  const { data, isLoading, isError } = useGitAiCommits();
  const navigate = useNavigate();

  if (isLoading) return <div className="max-w-7xl mx-auto px-6 py-6"><div className="animate-pulse h-64 bg-gray-100 rounded" /></div>;
  if (isError) return <div className="max-w-7xl mx-auto px-6 py-6"><p className="text-red-500 text-sm">Failed to load commits.</p></div>;
  if (!data?.length) return <div className="max-w-7xl mx-auto px-6 py-6"><p className="text-gray-500 text-sm">No Git AI commit data yet.</p></div>;

  return (
    <main className="max-w-7xl mx-auto px-6 py-6">
      <h2 className="text-lg font-semibold text-gray-800 mb-4">
        All Commits ({data.length})
        <span className="ml-2 inline-block px-1.5 py-0.5 bg-blue-100 text-blue-800 rounded text-xs font-medium">Git AI</span>
      </h2>

      <div className="bg-white border border-gray-200 rounded-lg overflow-hidden">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-gray-200 bg-gray-50 text-left text-xs text-gray-500 uppercase tracking-wider">
              <th className="px-4 py-2">Commit</th>
              <th className="px-4 py-2">Repo</th>
              <th className="px-4 py-2">Agent %</th>
              <th className="px-4 py-2 text-right">AI Lines</th>
              <th className="px-4 py-2 text-right">Human</th>
              <th className="px-4 py-2">Agent</th>
              <th className="px-4 py-2">Model</th>
              <th className="px-4 py-2">Date</th>
            </tr>
          </thead>
          <tbody>
            {data.map((c) => (
              <tr
                key={`${c.commit_sha}-${c.repo}`}
                onClick={() => navigate(`/commits/${c.commit_sha}`)}
                className="border-b border-gray-100 hover:bg-gray-50 cursor-pointer"
              >
                <td className="px-4 py-2 font-mono text-xs">{c.commit_sha.slice(0, 7)}</td>
                <td className="px-4 py-2">
                  <span className={`inline-block px-1.5 py-0.5 rounded text-xs font-medium ${REPO_COLORS[c.repo] ?? 'bg-gray-100 text-gray-800'}`}>
                    {c.repo.replace(REPO_PREFIX, '')}
                  </span>
                </td>
                <td className="px-4 py-2">
                  <div className="flex items-center gap-2">
                    <div className="w-16 h-2 bg-gray-200 rounded-full overflow-hidden">
                      <div
                        className="h-full bg-indigo-500 rounded-full"
                        style={{ width: `${c.agent_percentage}%` }}
                      />
                    </div>
                    <span className="text-xs font-medium">{c.agent_percentage.toFixed(1)}%</span>
                  </div>
                </td>
                <td className="px-4 py-2 text-right font-medium text-blue-700">{c.agent_lines}</td>
                <td className="px-4 py-2 text-right text-gray-500">{c.human_lines}</td>
                <td className="px-4 py-2 text-xs">{c.agent}</td>
                <td className="px-4 py-2 text-xs text-gray-500">{c.model}</td>
                <td className="px-4 py-2 text-xs text-gray-500">{formatDate(c.captured_at)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </main>
  );
}
```

- [ ] **Step 2: Verify it compiles and renders**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit
```

Open `http://localhost:5173/commits` — should see the commit table with data.

- [ ] **Step 3: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add src/pages/CommitListPage.tsx
git commit -m "feat: implement commit list page with attribution table"
```

---

## Task 6: Frontend — Commit Detail Page

**Files:**
- Modify: `entire-poc-frontend/src/pages/CommitDetailPage.tsx` (replace placeholder)

- [ ] **Step 1: Implement CommitDetailPage**

Replace `src/pages/CommitDetailPage.tsx`:

```tsx
import { useParams, Link } from 'react-router-dom';
import { useCommitDetail } from '../hooks/useChartData';
import { api } from '../api/client';
import { REPO_PREFIX } from '../constants';

const REPO_BADGE: Record<string, string> = {
  'entire-poc-backend': 'bg-indigo-100 text-indigo-800',
  'entire-poc-frontend': 'bg-amber-100 text-amber-800',
  'entire-poc-workspace': 'bg-green-100 text-green-800',
};

function StatCard({ label, value, sub, color }: { label: string; value: string | number; sub?: string; color: string }) {
  return (
    <div className={`rounded-lg border p-4 ${color}`}>
      <p className="text-xs text-gray-500 uppercase tracking-wider">{label}</p>
      <p className="text-2xl font-bold mt-1">{value}</p>
      {sub && <p className="text-xs text-gray-500 mt-1">{sub}</p>}
    </div>
  );
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  return `${(bytes / 1024).toFixed(1)} KB`;
}

export function CommitDetailPage() {
  const { sha } = useParams<{ sha: string }>();
  const { data, isLoading, isError } = useCommitDetail(sha ?? '');

  if (isLoading) return <div className="max-w-7xl mx-auto px-6 py-6"><div className="animate-pulse h-96 bg-gray-100 rounded" /></div>;
  if (isError || !data) return (
    <div className="max-w-7xl mx-auto px-6 py-6">
      <Link to="/commits" className="text-indigo-600 text-sm hover:underline">&larr; Back to commits</Link>
      <p className="text-red-500 text-sm mt-4">Failed to load commit detail.</p>
    </div>
  );

  const { attribution, files, raw_note, local_prompt } = data;
  const noteparts = raw_note?.split('\n---\n') ?? [];
  const fileMapSection = noteparts[0] ?? '';
  const jsonSection = noteparts[1] ?? '';

  let formattedJson = jsonSection;
  try { formattedJson = JSON.stringify(JSON.parse(jsonSection), null, 2); } catch { /* use raw */ }

  return (
    <main className="max-w-7xl mx-auto px-6 py-6 space-y-6">
      {/* Section A — Summary Header */}
      <div>
        <Link to="/commits" className="text-indigo-600 text-sm hover:underline">&larr; Back to commits</Link>

        <div className="mt-3 flex items-center gap-3 flex-wrap">
          <h2 className="text-lg font-semibold font-mono">{data.commit_sha}</h2>
          <span className={`inline-block px-2 py-0.5 rounded text-xs font-medium ${REPO_BADGE[data.repo] ?? 'bg-gray-100 text-gray-800'}`}>
            {data.repo.replace(REPO_PREFIX, '')}
          </span>
        </div>

        <p className="text-sm text-gray-500 mt-1">
          {data.captured_at ? new Date(data.captured_at).toLocaleString() : '—'}
          {' · '}{attribution.agent}{attribution.model ? ` (${attribution.model})` : ''}
        </p>

        <div className="grid grid-cols-3 gap-4 mt-4">
          <StatCard label="AI Lines" value={attribution.agent_lines} color="border-blue-200 bg-blue-50" />
          <StatCard label="Human Lines" value={attribution.human_lines} color="border-gray-200 bg-gray-50" />
          <StatCard label="Agent %" value={`${attribution.agent_percentage.toFixed(1)}%`} color="border-indigo-200 bg-indigo-50" />
        </div>
      </div>

      {/* Section B — File Attribution Map */}
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <h3 className="text-sm font-semibold text-gray-700 mb-3">File Attribution ({files.length} files)</h3>
        {files.length === 0 ? (
          <p className="text-gray-500 text-sm">No file-level attribution data.</p>
        ) : (
          <div className="space-y-2">
            {files.map((f, i) => {
              const totalForFile = f.lineCount + (attribution.human_lines > 0 ? Math.round(attribution.human_lines * f.lineCount / Math.max(attribution.agent_lines, 1)) : 0);
              const aiPct = totalForFile > 0 ? (f.lineCount / totalForFile) * 100 : 100;
              return (
                <div key={i} className="border border-gray-100 rounded p-3">
                  <div className="flex items-center justify-between">
                    <span className="font-mono text-xs text-gray-800">{f.file}</span>
                    <span className="text-xs text-gray-500">{f.lineCount} lines</span>
                  </div>
                  <div className="flex items-center gap-2 mt-1">
                    <div className="flex-1 h-1.5 bg-gray-200 rounded-full overflow-hidden">
                      <div className="h-full bg-blue-500 rounded-full" style={{ width: `${aiPct}%` }} />
                    </div>
                    <span className="text-xs text-gray-500">Lines {f.lineRanges}</span>
                  </div>
                  <p className="text-xs text-gray-400 mt-1">prompt: {f.promptId}</p>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Section C — Raw Git Note */}
      {raw_note && (
        <details open className="bg-white border border-gray-200 rounded-lg p-4">
          <summary className="text-sm font-semibold text-gray-700 cursor-pointer">Raw Git Note</summary>
          <div className="mt-3 space-y-3">
            <div>
              <p className="text-xs text-gray-500 uppercase tracking-wider mb-1">File Map</p>
              <pre className="bg-gray-50 border border-gray-200 rounded p-3 text-xs font-mono overflow-x-auto whitespace-pre">{fileMapSection}</pre>
            </div>
            <div>
              <p className="text-xs text-gray-500 uppercase tracking-wider mb-1">JSON Metadata</p>
              <pre className="bg-gray-50 border border-gray-200 rounded p-3 text-xs font-mono overflow-x-auto whitespace-pre">{formattedJson}</pre>
            </div>
          </div>
        </details>
      )}

      {/* Section D — Local Prompt Data */}
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <h3 className="text-sm font-semibold text-gray-700 mb-3">Local Prompt Data</h3>
        {local_prompt ? (
          <div className="space-y-4">
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3 text-sm">
              <div><span className="text-gray-500 text-xs">Session ID</span><p className="font-mono text-xs">{local_prompt.session_id}</p></div>
              <div><span className="text-gray-500 text-xs">Workdir</span><p className="font-mono text-xs truncate" title={local_prompt.workdir ?? ''}>{local_prompt.workdir}</p></div>
              <div><span className="text-gray-500 text-xs">Tool / Model</span><p className="text-xs">{local_prompt.tool} / {local_prompt.model}</p></div>
              <div><span className="text-gray-500 text-xs">Human Author</span><p className="text-xs">{local_prompt.human_author}</p></div>
              <div><span className="text-gray-500 text-xs">Created</span><p className="text-xs">{new Date(local_prompt.created_at).toLocaleString()}</p></div>
              <div><span className="text-gray-500 text-xs">Updated</span><p className="text-xs">{new Date(local_prompt.updated_at).toLocaleString()}</p></div>
            </div>

            <div className="grid grid-cols-4 gap-3">
              <div className="text-center p-2 bg-blue-50 rounded"><p className="text-xs text-gray-500">Additions</p><p className="font-bold text-sm">{local_prompt.total_additions ?? '—'}</p></div>
              <div className="text-center p-2 bg-red-50 rounded"><p className="text-xs text-gray-500">Deletions</p><p className="font-bold text-sm">{local_prompt.total_deletions ?? '—'}</p></div>
              <div className="text-center p-2 bg-green-50 rounded"><p className="text-xs text-gray-500">Accepted</p><p className="font-bold text-sm">{local_prompt.accepted_lines ?? '—'}</p></div>
              <div className="text-center p-2 bg-amber-50 rounded"><p className="text-xs text-gray-500">Overridden</p><p className="font-bold text-sm">{local_prompt.overridden_lines ?? '—'}</p></div>
            </div>

            {local_prompt.message_preview && (
              <div>
                <p className="text-xs text-gray-500 uppercase tracking-wider mb-1">Transcript Preview</p>
                <div className="bg-gray-50 border border-gray-200 rounded p-3 text-xs font-mono whitespace-pre-wrap">
                  {local_prompt.message_preview}
                  {local_prompt.message_bytes > 500 && <span className="text-gray-400">...</span>}
                </div>
              </div>
            )}

            {attribution.prompt_id && (
              <a
                href={api.gitai.transcriptUrl(data.commit_sha, attribution.prompt_id)}
                download
                className="inline-flex items-center gap-2 px-4 py-2 bg-indigo-600 text-white text-sm rounded hover:bg-indigo-700"
              >
                Download Full Transcript ({formatBytes(local_prompt.message_bytes)})
              </a>
            )}
          </div>
        ) : (
          <p className="text-gray-500 text-sm">Local prompt data not available (prompt may be from a different machine or session).</p>
        )}
      </div>
    </main>
  );
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx tsc --noEmit
```

- [ ] **Step 3: End-to-end test**

1. Open `http://localhost:5173/commits` — commit list renders
2. Click any row — navigates to detail page
3. Verify all 4 sections render (Summary, Files, Raw Note, Local Prompt)
4. Click "Download Full Transcript" — browser downloads a JSON file
5. Click "Back to commits" — returns to list
6. Click "Dashboard" in nav — returns to existing dashboard, all charts still work

- [ ] **Step 4: Commit**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
git add src/pages/CommitDetailPage.tsx
git commit -m "feat: implement commit detail page with all Git AI data layers"
```

---

## Task 7: Final Verification + Push

**Files:** None (verification only)

- [ ] **Step 1: Run all backend tests**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend && npx vitest run
```
Expected: all tests pass

- [ ] **Step 2: Lint both repos**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend && npx eslint src/ tests/
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx eslint src/
```
Expected: clean

- [ ] **Step 3: Build frontend**

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend && npx vite build
```
Expected: builds successfully

- [ ] **Step 4: Push all repos**

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend && git push
cd ~/Projects/metrics_2_0/entire-poc-frontend && git push origin main
cd ~/Projects/metrics_2_0/entire-poc-workspace && git push origin main
```
