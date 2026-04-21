#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

EXTRA_FLAGS="${ENTIRE_ENABLE_FLAGS:-}"

for repo in "${ALL_REPOS[@]}"; do
  dir="$(resolve_repo_path "${repo}")"
  if [[ ! -d "${dir}/.git" ]]; then
    echo "[skip] ${repo} not found at ${dir}"
    continue
  fi
  echo "==> entire enable in ${repo}"
  pushd "${dir}" > /dev/null
  entire enable ${EXTRA_FLAGS} || echo "    (entire enable returned non-zero — check status)"
  popd > /dev/null
done

echo "==> Done. To verify: cd <repo> && entire status"
