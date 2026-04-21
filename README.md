# entire-poc-workspace
Hub repository for the Entire IO Pattern C validation proof-of-concept.
I am superman
This repo is the **workspace hub** — the launch point for AI agent sessions. It contains no application code. It holds shared configuration, setup scripts, validation documentation, and the VS Code multi-root workspace file.

## Quick Start

### Prerequisites

- [Entire CLI](https://entire.dev) installed
- [Claude CLI](https://claude.ai/code) installed and authenticated
- Node.js 20+
- GitHub CLI (`gh`) authenticated
- All three repos cloned as siblings:
  ```
  ~/Projects/metrics_2_0/
  ├── entire-poc-workspace/   (this repo)
  ├── entire-poc-backend/
  └── entire-poc-frontend/
  ```

### Setup

```bash
# 1. Enable Entire in the workspace
./scripts/setup-workspace.sh

# 2. Bootstrap Entire in service repos
./scripts/bootstrap-services.sh

# 3. Commit Entire config to service repos
./scripts/commit-entire-config.sh

# 4. Install local hooks and cron
./scripts/dev-onboard.sh
./scripts/install-cron.sh
```

### Opening the Workspace

Open `entire-poc.code-workspace` in VS Code to get a multi-root workspace with all three repos.

### Running the Validation

See `docs/VALIDATION-PLAYBOOK.md` for the full test scenario runbook.

```bash
# After running test scenarios:
./scripts/run-validation.sh

# Inspect current state:
./scripts/inspect-state.sh
```

## Repository Structure

```
├── .code-workspace          # VS Code multi-root workspace file
├── .entire/                 # Workspace Entire config (auto-summarize ON)
├── .claude/                 # Claude Code agent settings
├── scripts/                 # Setup, bootstrap, and validation scripts
├── templates/               # Shared config templates for service repos
├── skills/                  # Test skills for cross-repo agent sessions
└── docs/                    # Specs, playbook, results, conclusions
```

## Companion Repos

- [entire-poc-backend](https://github.com/ShamsiievDmytro/entire-poc-backend) — Node.js API + ingestion service
- [entire-poc-frontend](https://github.com/ShamsiievDmytro/entire-poc-frontend) — React dashboard

## Documentation

- [REQUIREMENTS.md](docs/REQUIREMENTS.md) — Functional and non-functional requirements
- [ARCHITECTURE.md](docs/ARCHITECTURE.md) — Architecture and implementation specification
- [VALIDATION-PLAYBOOK.md](docs/VALIDATION-PLAYBOOK.md) — Test scenario runbook
- [RESULTS-TEMPLATE.md](docs/RESULTS-TEMPLATE.md) — Outcome recording template
