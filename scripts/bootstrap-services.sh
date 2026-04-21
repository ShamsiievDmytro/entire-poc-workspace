#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

TEMPLATE="$(resolve_repo_path "${WORKSPACE_REPO}")/templates/entire-service-settings.json"

for repo in "${SERVICE_REPOS[@]}"; do
  dir="$(resolve_repo_path "${repo}")"
  if [[ ! -d "${dir}/.git" ]]; then
    echo "[skip] ${repo} (not a git repo at ${dir})"
    continue
  fi

  echo "==> Bootstrapping ${repo}"
  pushd "${dir}" > /dev/null

  entire enable --agent claude-code --force

  mkdir -p .entire
  cp "${TEMPLATE}" .entire/settings.json
  echo "    settings.json written"

  popd > /dev/null
done

echo "==> Bootstrap complete. Run scripts/commit-entire-config.sh to commit and push."
