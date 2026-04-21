# Commit Detail View — Design Spec

**Date:** 2026-04-21
**Status:** Approved
**Scope:** Backend endpoints + frontend pages for per-commit Git AI attribution view

---

## 1. Overview

Add a per-commit view to the PoC dashboard. A commit list page shows all commits with Git AI attribution across all 3 repos. Clicking a commit opens a detail page showing all data from `refs/notes/ai` (the Git Note) and `~/.git-ai/internal/db` (local prompt metadata and transcript).

## 2. Architecture

**Approach:** Dedicated detail endpoint + local DB reader (Approach 1 from brainstorming).

The backend opens two SQLite databases:
- `poc.db` — existing, contains `gitai_commit_attribution` (ingested note data)
- `~/.git-ai/internal/db` — Git AI's local database, opened **read-only**, contains `prompts` table with session transcripts

The frontend adds `react-router-dom` for client-side routing with a top nav bar.

## 3. Backend Changes

### 3.1 Config

Add to `.env` and `config.ts` Zod schema:

```
GITAI_LOCAL_DB_PATH=~/.git-ai/internal/db
```

Default: `~/.git-ai/internal/db` (resolved via `os.homedir()`). Optional — if the file doesn't exist, local prompt data is unavailable but the API still works.

### 3.2 New module: `src/db/gitai-local-reader.ts`

Opens `~/.git-ai/internal/db` read-only (lazy singleton, `{ readonly: true }`).

Exports:
- `getPromptById(promptId: string)` → metadata + first 500 chars of transcript + total message size. Returns `null` if not found.
- `getFullTranscript(promptId: string)` → raw `messages` text. Returns `null` if not found.

Fields returned by `getPromptById`:

| Field | Source column | Description |
|-------|-------------|-------------|
| `prompt_id` | `id` | Prompt identifier |
| `session_id` | `external_thread_id` | Claude session UUID |
| `workdir` | `workdir` | Where agent was launched |
| `tool` | `tool` | Agent tool name |
| `model` | `model` | LLM model |
| `human_author` | `human_author` | Git committer name |
| `total_additions` | `total_additions` | Lines added |
| `total_deletions` | `total_deletions` | Lines deleted |
| `accepted_lines` | `accepted_lines` | Lines accepted from agent |
| `overridden_lines` | `overridden_lines` | Lines human modified |
| `message_preview` | `substr(messages, 1, 500)` | First 500 chars of transcript |
| `message_bytes` | `length(messages)` | Total transcript size |
| `created_at` | `created_at` | Unix timestamp → ISO string |
| `updated_at` | `updated_at` | Unix timestamp → ISO string |

Graceful degradation: if the local DB file doesn't exist or can't be opened, log a warning and return `null` for all queries. The API continues to work with just the ingested data.

### 3.3 New endpoint: `GET /api/gitai/commits/:sha/detail`

Response:

```json
{
  "commit_sha": "6df5a6e...",
  "repo": "entire-poc-backend",
  "captured_at": "2026-04-21T11:46:44Z",
  "attribution": {
    "agent": "claude",
    "model": "claude-opus-4-6",
    "agent_lines": 1,
    "human_lines": 0,
    "agent_percentage": 100,
    "prompt_id": "1612649c4bf0b88e"
  },
  "files": [
    { "file": "src/api/routes/status.ts", "promptId": "...", "lineRanges": "32", "lineCount": 1 }
  ],
  "raw_note": "src/api/routes/status.ts\n  1612649c... 32\n---\n{...}",
  "local_prompt": {
    "session_id": "9b4e6eb7-...",
    "workdir": "/Users/.../entire-poc-workspace",
    "tool": "claude",
    "model": "claude-opus-4-6",
    "human_author": "Dmytro Shamsiiev",
    "total_additions": 1,
    "total_deletions": 0,
    "accepted_lines": 1,
    "overridden_lines": 0,
    "message_preview": "# Git AI Validation — Agent Prompt...",
    "message_bytes": 192382,
    "created_at": "2026-04-21T11:35:12",
    "updated_at": "2026-04-21T14:13:00"
  }
}
```

`local_prompt` is `null` when the prompt ID is not found in the local Git AI database.

### 3.4 New endpoint: `GET /api/gitai/commits/:sha/transcript?prompt_id=...`

- Reads full `messages` from local DB via `getFullTranscript()`
- Returns `Content-Type: application/json`
- Sets `Content-Disposition: attachment; filename=<prompt_id>.json`
- Returns 404 if prompt not found

### 3.5 Route wiring

Both new endpoints go in the existing `src/api/routes/gitai.ts` file alongside the current endpoints. No new route file needed.

## 4. Frontend Changes

### 4.1 New dependency

`react-router-dom` — for client-side routing.

### 4.2 Routing setup

**`App.tsx`** — wrap with `BrowserRouter`, define routes:
- `/` → Dashboard (existing)
- `/commits` → CommitListPage (new)
- `/commits/:sha` → CommitDetailPage (new)

Layout route wraps all pages with `NavBar` at the top.

### 4.3 New component: `NavBar.tsx`

Replaces the current `<header>` in Dashboard.
- App title "Entire PoC Dashboard" on the left
- Two nav links: "Dashboard" (`/`) and "Commits" (`/commits`)
- Active link highlighted with indigo underline
- Renders above every page via layout route

### 4.4 Dashboard.tsx changes

- Remove `<header>` (now in NavBar)
- Remove `<footer>` (move to layout or keep per-page)
- All existing chart sections unchanged

### 4.5 New page: `src/pages/CommitListPage.tsx`

Table of all commits with Git AI data across all 3 repos.

**Data source:** Existing `GET /api/gitai/commits` endpoint.

**Columns:**

| Column | Content |
|--------|---------|
| Commit | SHA first 7 chars, monospace |
| Repo | Colored badge (indigo=backend, amber=frontend, green=workspace) |
| Agent % | Percentage + small inline colored bar |
| AI Lines | Number |
| Human Lines | Number |
| Agent | Tool name |
| Model | Model name |
| Date | `captured_at` formatted |

**Behavior:**
- Sorted by `captured_at` DESC (newest first)
- Row click → navigate to `/commits/:sha`
- Row hover state (light gray bg, pointer cursor)
- Loading skeleton / error / empty states per existing patterns
- No pagination (PoC scale)

### 4.6 New page: `src/pages/CommitDetailPage.tsx`

Stacked sections, all visible on scroll.

**Section A — Summary Header**
- Full commit SHA (monospace) + repo badge
- Date, agent, model
- Three stat cards: AI Lines (blue), Human Lines (gray), Agent % (with visual indicator)
- Back link to `/commits`

**Section B — File Attribution Map**
- One card per file
- File path, prompt ID, line ranges, line count
- Small horizontal bar showing AI/human proportion per file

**Section C — Raw Git Note**
- Collapsible `<details>` block, expanded by default
- Split on `---`: file map section (styled code block) + JSON metadata section (formatted `<pre>`)

**Section D — Local Prompt Data**
- Visible when `local_prompt` is not null
- Card: session ID, workdir, tool, model, human author, timestamps
- Line stats: additions, deletions, accepted, overridden
- Transcript preview: 500-char preview in gray box with "..." truncation
- Download button: "Download Full Transcript (XXX KB)" → triggers `GET /api/gitai/commits/:sha/transcript?prompt_id=...` as browser download
- When `local_prompt` is null: info note "Local prompt data not available"

### 4.7 API client additions

Add to `src/api/client.ts`:

```typescript
gitai: {
  // existing...
  commits: () => get<GitAiCommit[]>('/api/gitai/commits'),
  summary: () => get<GitAiSummary>('/api/gitai/summary'),
  compare: () => get<EntireVsGitAiRow[]>('/api/compare/entire-vs-gitai'),
  // new
  commitDetail: (sha: string) => get<GitAiCommitDetail>(`/api/gitai/commits/${sha}/detail`),
  transcriptUrl: (sha: string, promptId: string) =>
    `${BASE}/api/gitai/commits/${sha}/transcript?prompt_id=${promptId}`,
}
```

`transcriptUrl` returns a URL string (not a fetch) — used as an `<a href>` download link.

### 4.8 New hooks

In `src/hooks/useChartData.ts`:

```typescript
export function useCommitDetail(sha: string) {
  return useQuery({
    queryKey: ['gitai', 'commit-detail', sha],
    queryFn: () => api.gitai.commitDetail(sha),
    enabled: !!sha,
  });
}
```

## 5. Files to Create/Modify

### Backend (`entire-poc-backend`)

| Action | File |
|--------|------|
| Create | `src/db/gitai-local-reader.ts` |
| Modify | `src/config.ts` — add `GITAI_LOCAL_DB_PATH` |
| Modify | `src/api/routes/gitai.ts` — add detail + transcript endpoints |

### Frontend (`entire-poc-frontend`)

| Action | File |
|--------|------|
| Create | `src/components/NavBar.tsx` |
| Create | `src/pages/CommitListPage.tsx` |
| Create | `src/pages/CommitDetailPage.tsx` |
| Modify | `src/App.tsx` — add BrowserRouter + routes |
| Modify | `src/components/Dashboard.tsx` — remove header/footer |
| Modify | `src/api/client.ts` — add detail + transcript types/methods |
| Modify | `src/hooks/useChartData.ts` — add useCommitDetail hook |
| Install | `react-router-dom` |

## 6. Non-goals

- Pagination (PoC has ~60 commits)
- Search/filter on the commit list
- Editing or modifying Git AI data
- Displaying data from `.git/ai/working_logs/` (checkpoint files are large, ephemeral, and complex to parse — the condensed note + local prompt data covers the use case)
- Syntax highlighting for code in the raw note display
