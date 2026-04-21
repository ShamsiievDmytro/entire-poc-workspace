#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

for repo in "${ALL_REPOS[@]}"; do
  echo "=== ${repo} ==="
  ( cd "$(resolve_repo_path "${repo}")" && entire status )
  echo
done

echo "=== SQLite database ==="
sqlite3 "$(resolve_repo_path entire-poc-backend)/data/poc.db" <<'SQL'
.headers on
.mode column
SELECT 'sessions'        AS t, COUNT(*) AS n FROM sessions
UNION ALL SELECT 'session_repo_touches', COUNT(*) FROM session_repo_touches
UNION ALL SELECT 'repo_checkpoints',     COUNT(*) FROM repo_checkpoints
UNION ALL SELECT 'session_commit_links', COUNT(*) FROM session_commit_links;

SELECT confidence, COUNT(*) AS n
FROM session_commit_links
GROUP BY confidence
ORDER BY confidence;
SQL
