# Charts Inventory

## Page 1: Bitcoin Price Dashboard (`/src/pages/index.astro`)

| # | Chart Name | Type | Library | Input Data | What it shows / why it matters |
|---|-----------|------|---------|------------|-------------------------------|
| 1 | **24-Hour Price Chart** | Area | lightweight-charts | `ChartPoint[]` `{time, value}` from live WebSocket | BTC/USD price over 24h with cyan gradient fill and crosshair tooltip. |
| 2 | **Live Price Card** | Stat card | — | `PriceTick` `{price, timestamp, direction}` | Current BTC price with directional arrow, 24h change %, and flash animation. |
| 3 | **Market Data Card** | Stat card | — | `MarketData` `{marketCap, change24h, high24h, low24h}` | Market cap and 24h price range in compact notation. |

## Page 2: AI Metrics Dashboard (`/src/pages/ai-metrics.astro`)

### Attribution Section (`AttributionSection.tsx`)

| Chart Name | Type | Library | Input Data | What it shows / why it matters |
|-----------|------|---------|------------|-------------------------------|
| **Agent % Over Time (Smoothed)** | Line | lightweight-charts | `agent_percentage` per checkpoint, smoothed with 3-checkpoint rolling average | AI-authored line share per commit, smoothed to reduce noise from outlier commits. Each point shows the mean agent_percentage of that commit and the two preceding ones. Shows the actual adoption trajectory. |
| **AI Usage by Developer** | Horizontal bar | Chart.js | Average `agent_percentage` per author across all their checkpoints | Per-developer average AI code share. Only shown when multiple developers are present. Number in parentheses is commit count. Identifies AI adoption leaders and those who may need support. |
| **Pure-AI Commit Rate** | Stat card | — | % of checkpoints with `agent_percentage=100` | Share of commits where AI wrote 100% of the code. Distinguishes "AI helped a bit" from "AI did the work end-to-end." |
| **Human Edit Rate** | Bar | Chart.js | `100 - agent_percentage` per checkpoint | How much of AI output gets rewritten before commit. Rising values signal quality issues with AI output or mismatch with team standards. |
| **Attribution Breakdown** | Stacked bar | Chart.js | `agent_percentage` + human% per checkpoint | Visual split of AI-authored (purple) vs human-contributed (green) lines per commit, stacked to 100%. |
| **Avg Agent Attribution** | Stat card | — | Mean of all `agent_percentage` | Single headline number: average AI contribution across the whole project. |
| **First-Time-Right Rate** | Stat card + trend line | lightweight-charts | Checkpoints with `agent_lines > 0 AND human_added == 0 AND human_modified == 0 AND human_removed == 0` | AI output that shipped without any human edits. Sparkline shows cumulative FTR rate converging to the headline number. |

### Token Economics Section (`TokenSection.tsx`)

| Chart Name | Type | Library | Input Data | What it shows / why it matters |
|-----------|------|---------|------------|-------------------------------|
| **Token Breakdown** | Stacked bar | Chart.js | `tokens.{input, cache_creation, cache_read, output}` | Stacked view of token consumption per commit. Cache tokens (93-98% of total) are hidden by default behind a toggle to keep input/output visible. |
| **API Call Count** | Bar | Chart.js | Sum of `turn_count` across all turns per checkpoint | Total API turns per checkpoint. Distinguishes chatty sessions (many calls, few tokens each) from deep-reasoning sessions (few calls, many tokens each). |
| **Prompts per Checkpoint** | Bar | Chart.js | `turns.length` per checkpoint | Count of distinct prompt turn entries per checkpoint. Maps directly to request-based billing models. Different from API Call Count which sums internal turn_count depth. |
| **Model Distribution** | Doughnut | Chart.js | Count of each `turn.model` across all turns | Which LLMs the team actually uses (Sonnet, Opus, Haiku, etc.). Exposes whether premium-model usage is justified by work type. |

### Quality Signals Section (`QualitySection.tsx`)

| Chart Name | Type | Library | Input Data | What it shows / why it matters |
|-----------|------|---------|------------|-------------------------------|
| **Session Depth vs Agent %** | Scatter | Chart.js | X: total turns (sum of `turn_count`), Y: `agent_percentage` | Correlation: do longer sessions produce more AI-authored code, or do they degrade as context fills up? Positive correlation means deeper sessions yield more AI code; flat or negative suggests context degradation. |

### Behavioral / SDLC Section (`BehavioralSection.tsx`)

| Chart Name | Type | Library | Input Data | What it shows / why it matters |
|-----------|------|---------|------------|-------------------------------|
| **Slash Command Frequency** | Horizontal bar | Chart.js | Aggregated slash-command counts extracted from `turns[].prompt_txt` | All slash commands used across sessions, sorted by frequency. Shows which parts of the structured workflow are actually used. |
| **BMAD Command Frequency** | Horizontal bar | Chart.js | Aggregated `/bmad*` commands extracted from `turns[].prompt_txt` | Same as Slash Command Frequency but filtered to only `/bmad` prefix commands. Focused view of BMAD-specific workflow adoption. |
| **Prompt Type Distribution** | Doughnut | Chart.js | Slash Command / Free-form / Continuation counts | Classifies every user prompt: slash commands (starts with `/`), free-form (natural language), or continuation (empty prompt). Higher slash-command share indicates disciplined workflow. |
| **Files Touched by Layer** | Stacked bar | Chart.js | Files classified into 6 layers (components, services, stores, utils, docs, other) | Architectural distribution of AI edits per checkpoint, color-coded by layer. Reveals which parts of the codebase AI is trusted with. |
| **Unique Sessions per Checkpoint** | Bar | Chart.js | Count of unique `session_id` per checkpoint | Distinct agent sessions per commit. Value of 1 = single work session; higher = multiple sessions merged into one commit. |
| **Tool Usage Mix** | Horizontal bar | Chart.js | Count of `tool_use` blocks grouped by tool name across all checkpoints | Tools invoked by the AI agent (Read, Edit, Bash, Grep, etc.), sorted by frequency. Answers "what kind of work did the AI do?" |
| **Top-N Skills Invoked** | Horizontal bar | Chart.js | Aggregated `Skill` tool_use frequency per `skill_id` across all checkpoints | Skills the AI agent invoked autonomously via the Skill tool. Informs which skills in the catalog get real usage. |
| **Subagent Usage Timeline** | Bar | Chart.js | `subagent_count` per checkpoint, sorted by `commit_date` | Subagent tasks spawned per checkpoint over time. Tracks adoption of agentic workflows — the shift from "AI assists me" to "I orchestrate AI agents." |

### Temporal Section (`TemporalSection.tsx`)

| Chart Name | Type | Library | Input Data | What it shows / why it matters |
|-----------|------|---------|------------|-------------------------------|
| **Checkpoint Cadence** | Bar | Chart.js | Hours between consecutive commits | Time gaps between consecutive checkpoints. Exposes work rhythm — tight bursts, steady drips, or long gaps. Useful for spotting stalled work or unsustainable intensity. |

### Quality & Debt Section (`QualityDebtSection.tsx`)

| Chart Name | Type | Library | Input Data | What it shows / why it matters |
|-----------|------|---------|------------|-------------------------------|
| **Friction Events per Checkpoint** | Horizontal bar + recent-items list | Chart.js | `summary.friction[]` per checkpoint | Agent-reported places where work hit resistance. Tooltip reveals the specific friction text. Below the chart, the 5 most recent friction items are listed with timestamps. Rising counts signal growing complexity or drifting prompt quality. |
| **Open Items per Checkpoint** | Bar + cumulative line overlay + recent-items list | Chart.js | `summary.open_items[]` per checkpoint, ordered by `commit_date` | Acknowledged-but-deferred work per checkpoint. Bars show items added; dashed line tracks cumulative acknowledged debt (upper bound — items may be resolved without explicit closure). Below the chart, the 5 most recent open items are listed. |

---

## Implementation summary

**Total implemented charts:** 22 (across 6 sections)

| Section | Chart count | Component |
|---------|:-----------:|-----------|
| Attribution | 7 | `AttributionSection.tsx` |
| Token Economics | 4 | `TokenSection.tsx` |
| Quality Signals | 1 | `QualitySection.tsx` |
| Behavioral / SDLC | 8 | `BehavioralSection.tsx` |
| Temporal | 1 | `TemporalSection.tsx` |
| Quality & Debt | 2 | `QualityDebtSection.tsx` |

### Notes

**Friction & Open Items data source:** Both charts consume `summary.friction[]` and `summary.open_items[]` from per-session `metadata.json` files. These fields are populated only when auto-summarization is enabled in `.entire/settings.json`. Checkpoints without summarization produce empty arrays; both charts handle this gracefully with an empty-state placeholder.

**Friction & Open Items data caveat:** Entire records friction and open items per checkpoint but does not mark whether open items are later resolved. The cumulative open-items line is an upper bound ("debt acknowledged"), not ground truth ("debt still active").
