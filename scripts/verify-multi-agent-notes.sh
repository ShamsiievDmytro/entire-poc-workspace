#!/usr/bin/env bash
# Verify Git AI notes across all three PoC repos and report a summary.
set -euo pipefail

BASE="${HOME}/Projects/metrics_2_0"
REPOS=("entire-poc-workspace" "entire-poc-backend" "entire-poc-frontend")

declare -a SUMMARY_LINES=()

for repo in "${REPOS[@]}"; do
  echo "================================================================="
  echo "=== ${repo}"
  echo "================================================================="

  REPO_DIR="${BASE}/${repo}"
  if [ ! -d "${REPO_DIR}/.git" ]; then
    echo "  SKIP: ${REPO_DIR} is not a git repository"
    SUMMARY_LINES+=("${repo}: SKIP (not a git repo)")
    echo ""
    continue
  fi

  cd "${REPO_DIR}"

  # 1. Latest commit SHA
  SHA=$(git rev-parse HEAD)
  echo "  Latest commit: ${SHA}"

  # 2. Try to show the Git AI note for HEAD
  echo ""
  echo "  --- AI note for HEAD ---"
  NOTE_TEXT=""
  if NOTE_TEXT=$(git notes --ref=ai show HEAD 2>/dev/null); then
    NOTE_EXISTS="yes"
    echo "${NOTE_TEXT}" | sed 's/^/  /'
  else
    NOTE_EXISTS="no"
    echo "  (no AI note on HEAD)"
  fi

  # 3. Run git ai stats if available
  echo ""
  echo "  --- git ai stats ---"
  if command -v git-ai &>/dev/null || git ai --version &>/dev/null 2>&1; then
    git ai stats HEAD~1..HEAD --json 2>/dev/null | sed 's/^/  /' || echo "  (git ai stats returned no output)"
  else
    echo "  (git-ai CLI not installed)"
  fi

  # 4. Count agent lines in the note
  AGENT_LINES=0
  if [ "${NOTE_EXISTS}" = "yes" ] && [ -n "${NOTE_TEXT}" ]; then
    AGENT_LINES=$(echo "${NOTE_TEXT}" | wc -l | tr -d ' ')
  fi

  SUMMARY_LINES+=("${repo}: NOTE_EXISTS=${NOTE_EXISTS} AGENT_LINES=${AGENT_LINES}")
  echo ""
done

echo "================================================================="
echo "=== SUMMARY"
echo "================================================================="
for line in "${SUMMARY_LINES[@]}"; do
  echo "  ${line}"
done
echo ""
echo "Done. Git AI version: $(git ai --version 2>/dev/null || echo 'not installed')"
