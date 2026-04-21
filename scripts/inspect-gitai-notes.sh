#!/usr/bin/env bash
# Diagnostic helper: dump Git AI notes from all three PoC repos.
set -euo pipefail

BASE="${HOME}/Projects/metrics_2_0"
REPOS=("entire-poc-workspace" "entire-poc-backend" "entire-poc-frontend")

for repo in "${REPOS[@]}"; do
  echo "================================================================="
  echo "=== ${repo}"
  echo "================================================================="
  cd "${BASE}/${repo}"

  NOTE_COUNT=$(git notes --ref=ai list 2>/dev/null | wc -l | tr -d ' ')
  echo "Notes count: ${NOTE_COUNT}"

  if [ "${NOTE_COUNT}" -gt 0 ]; then
    echo ""
    echo "--- Last 3 commits with notes ---"
    git log --show-notes=ai --oneline -3 2>/dev/null
    echo ""

    LATEST=$(git rev-parse HEAD)
    echo "--- Latest commit (${LATEST:0:7}) note ---"
    git notes --ref=ai show "${LATEST}" 2>/dev/null || echo "(no note on HEAD)"
  fi
  echo ""
done

echo "Done. Git AI version: $(git ai --version 2>/dev/null || echo 'not installed')"
