#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/repos.sh"

WORKSPACE_DIR="$(resolve_repo_path "${WORKSPACE_REPO}")"
ENTIRE_BIN="$(command -v entire)"
LOG_DIR="${HOME}/.entire-poc"
mkdir -p "${LOG_DIR}"

CRON_LINE="0 */4 * * * cd ${WORKSPACE_DIR} && ${ENTIRE_BIN} doctor --force >> ${LOG_DIR}/doctor.log 2>&1"

# Install if not present
if crontab -l 2>/dev/null | grep -Fq "${ENTIRE_BIN} doctor --force"; then
  echo "Cron job already installed."
else
  ( crontab -l 2>/dev/null; echo "${CRON_LINE}" ) | crontab -
  echo "Cron job installed: every 4h."
fi
