#!/usr/bin/env bash
# Quick health check for all three PoC repos
# Verifies each repo is on main, clean, and has Git AI notes
set -euo pipefail

BASE="${HOME}/Projects/metrics_2_0"
REPOS=("entire-poc-workspace" "entire-poc-backend" "entire-poc-frontend")

for repo in "${REPOS[@]}"; do
  echo "=== ${repo} ==="
  cd "${BASE}/${repo}"
  echo "  Branch: $(git branch --show-current)"
  echo "  Status: $(git status --short | wc -l | tr -d ' ') uncommitted files"
  echo "  Notes:  $(git notes --ref=ai list 2>/dev/null | wc -l | tr -d ' ') commits with attribution"
  echo ""
done
