#!/usr/bin/env bash
# Wrapper around the Git AI install command — for reproducibility.
# See: https://usegitai.com/docs/cli
set -euo pipefail

echo "Installing Git AI CLI..."
curl -sSL https://usegitai.com/install.sh | bash

echo ""
echo "Verifying installation..."
git ai --version

echo ""
echo "IMPORTANT: Restart VS Code, all terminals, and any running Claude Code sessions"
echo "so that agent hooks are picked up."
