#!/usr/bin/env bash
# Shared list of repos used by all setup scripts.
# Paths are relative to the parent directory of the workspace repo.

export REPOS_PARENT_DIR="${REPOS_PARENT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"

export WORKSPACE_REPO="entire-poc-workspace"

# Service repos — extend this if more are added later
export SERVICE_REPOS=(
  "entire-poc-backend"
  "entire-poc-frontend"
)

# Convenience: all repos including workspace
export ALL_REPOS=("${WORKSPACE_REPO}" "${SERVICE_REPOS[@]}")

resolve_repo_path() {
  local rel="$1"
  printf '%s/%s' "${REPOS_PARENT_DIR}" "${rel}"
}
