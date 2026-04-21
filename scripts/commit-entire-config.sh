#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

for repo in "${SERVICE_REPOS[@]}"; do
  dir="$(resolve_repo_path "${repo}")"
  [[ -d "${dir}/.git" ]] || continue

  pushd "${dir}" > /dev/null

  git add .entire/ .claude/ 2>/dev/null || true

  if git diff --cached --quiet; then
    echo "[${repo}] nothing to commit"
  else
    git commit -m "chore: enable Entire IO session capture"
    git push origin HEAD
    echo "[${repo}] committed and pushed"
  fi

  popd > /dev/null
done
