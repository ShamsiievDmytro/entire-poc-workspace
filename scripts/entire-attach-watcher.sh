#!/usr/bin/env bash
set -euo pipefail
# Plan B: post-commit auto-attach wrapper.
#
# How it works:
# 1. Runs as a daemon launched manually by the developer.
# 2. Polls Claude Code's transcript directory for the most recent active session.
# 3. Polls each service repo's git log for new commits since last check.
# 4. When a new commit is detected, runs:
#      entire attach <session-id> -a claude-code -f
#    inside that repo, with the most recently active session ID.
# 5. Writes the result to ~/.entire-poc/attach.log.
# 6. Maintains state in ~/.entire-poc/session-state.json for idempotency.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

STATE_DIR="${HOME}/.entire-poc"
STATE_FILE="${STATE_DIR}/session-state.json"
LOG_FILE="${STATE_DIR}/attach.log"
TRANSCRIPT_DIR="${HOME}/.claude/projects"

mkdir -p "${STATE_DIR}"
[[ -f "${STATE_FILE}" ]] || echo '{}' > "${STATE_FILE}"

log() { printf '%s [watcher] %s\n' "$(date -Iseconds)" "$*" | tee -a "${LOG_FILE}"; }

most_recent_active_session_id() {
  # Find the most recently modified .jsonl in the transcript dir
  # The session_id is the filename stem.
  find "${TRANSCRIPT_DIR}" -type f -name '*.jsonl' -mmin -60 \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -1 | awk '{print $2}' \
    | xargs -I{} basename {} .jsonl
}

last_attached_commit_for_repo() {
  jq -r --arg r "$1" '.[$r] // ""' "${STATE_FILE}"
}

set_last_attached_commit_for_repo() {
  local repo="$1" sha="$2" tmp
  tmp=$(mktemp)
  jq --arg r "${repo}" --arg s "${sha}" '.[$r] = $s' "${STATE_FILE}" > "${tmp}"
  mv "${tmp}" "${STATE_FILE}"
}

while true; do
  session_id="$(most_recent_active_session_id || true)"
  if [[ -z "${session_id}" ]]; then
    sleep 30; continue
  fi

  for repo in "${SERVICE_REPOS[@]}"; do
    dir="$(resolve_repo_path "${repo}")"
    [[ -d "${dir}/.git" ]] || continue

    last_known="$(last_attached_commit_for_repo "${repo}")"
    head_sha="$(git -C "${dir}" rev-parse HEAD 2>/dev/null || echo '')"

    if [[ -n "${head_sha}" && "${head_sha}" != "${last_known}" ]]; then
      log "Detected new commit in ${repo}: ${head_sha:0:8}, attaching ${session_id}"
      ( cd "${dir}" && entire attach "${session_id}" -a claude-code -f ) \
        >> "${LOG_FILE}" 2>&1 \
        && set_last_attached_commit_for_repo "${repo}" "${head_sha}" \
        || log "WARN: attach failed for ${repo}@${head_sha:0:8}"
    fi
  done

  sleep 30
done
