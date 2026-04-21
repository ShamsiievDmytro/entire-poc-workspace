#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

echo "==> Setting up Entire in the workspace repo"

cd "$(resolve_repo_path "${WORKSPACE_REPO}")"

# Initial enable with Claude Code (extend with --agent flags as needed)
entire enable --agent claude-code --force

# Verify settings.json was already committed; if not, write the template
if [[ ! -f .entire/settings.json ]]; then
  echo "==> Writing .entire/settings.json"
  cat > .entire/settings.json <<'EOF'
{
  "enabled": true,
  "log_level": "info",
  "strategy_options": {
    "push_sessions": true,
    "summarize": { "enabled": true }
  }
}
EOF
fi

echo "==> Workspace setup complete. Run entire status to verify."
entire status
