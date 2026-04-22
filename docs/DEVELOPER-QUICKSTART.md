# Developer Quickstart

Get up and running with the Entire IO PoC workspace in under 10 minutes.

## Prerequisites

- **Node.js 20+** — https://nodejs.org
- **GitHub CLI** (`gh`) authenticated — https://cli.github.com
- **Claude CLI** — https://claude.ai/code
- **Git AI CLI 1.3.2+** — installed via `./scripts/install-gitai.sh` (see step 2)

```bash
gh auth login   # authenticate GitHub CLI before anything else
```

## 1. Clone the Three Repos

All three repos must be siblings under the same parent directory:

```bash
mkdir -p ~/Projects/metrics_2_0 && cd ~/Projects/metrics_2_0

git clone https://github.com/ShamsiievDmytro/entire-poc-workspace
git clone https://github.com/ShamsiievDmytro/entire-poc-backend
git clone https://github.com/ShamsiievDmytro/entire-poc-frontend
```

```
~/Projects/metrics_2_0/
├── entire-poc-workspace/   ← workspace hub (this repo)
├── entire-poc-backend/     ← Node.js API + ingestion service
└── entire-poc-frontend/    ← React dashboard
```

## 2. Install Git AI and Bootstrap

```bash
cd ~/Projects/metrics_2_0/entire-poc-workspace

./scripts/install-gitai.sh        # install Git AI CLI
./scripts/setup-workspace.sh      # workspace-level Entire config
./scripts/bootstrap-services.sh   # Git AI hooks in service repos
./scripts/dev-onboard.sh          # local Git hooks
./scripts/install-cron.sh         # background cron job
```

## 3. Start the Backend

```bash
cd ~/Projects/metrics_2_0/entire-poc-backend
npm install
npx tsx src/index.ts
# API listens on http://localhost:3001
```

## 4. Start the Frontend

```bash
cd ~/Projects/metrics_2_0/entire-poc-frontend
npm install
npx vite
# Dashboard at http://localhost:5173
```

## 5. Verify Git AI Is Working

```bash
# Confirm CLI is reachable
git ai --version
# expected: git-ai 1.3.2

# After making at least one commit in a service repo:
cd ~/Projects/metrics_2_0/entire-poc-backend
git notes --ref=ai list
# prints one line per annotated commit (empty = no commits yet)
```

## 6. Open the VS Code Workspace

Open `entire-poc.code-workspace` in VS Code for a multi-root view of all three repos.

## Further Reading

| Document | Purpose |
|----------|---------|
| [GITAI-DATA-AND-METRICS.md](GITAI-DATA-AND-METRICS.md) | How Git AI works, data model, known limitations |
| [GITAI-STORAGE-ARCHITECTURE.md](GITAI-STORAGE-ARCHITECTURE.md) | Storage layers from local to remote |
| [GITAI-PRODUCTION-ROLLOUT-GUIDE.md](GITAI-PRODUCTION-ROLLOUT-GUIDE.md) | Full production deployment guide for multi-repo workspace |
