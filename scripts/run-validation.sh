#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

echo "==> Pushing all repos"
for repo in "${ALL_REPOS[@]}"; do
  ( cd "$(resolve_repo_path "${repo}")" && git push origin HEAD || true )
done

echo "==> Forcing entire doctor in workspace"
( cd "$(resolve_repo_path "${WORKSPACE_REPO}")" && entire doctor --force )

echo "==> Triggering backend ingestion"
curl -fsS -X POST http://localhost:3001/api/ingest/run | jq .

echo "==> Done. Open http://localhost:5173 to inspect."
