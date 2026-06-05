#!/usr/bin/env bash
set -euo pipefail
JUPITER_USER="${JUPITER_USER:-jupiter}"
JUPITER_HOME="/home/${JUPITER_USER}"
JUPITER_REPO_DIR="${JUPITER_REPO_DIR:-${JUPITER_HOME}/Claude}"
JUPITER_WORKSPACE="${JUPITER_WORKSPACE:-${JUPITER_HOME}/workspace}"

sudo -u "$JUPITER_USER" -H -- git -C "$JUPITER_REPO_DIR" pull --ff-only || true
sudo -u "$JUPITER_USER" -H -- "${JUPITER_HOME}/.local/bin/claude" update || true
if [[ -d "${JUPITER_REPO_DIR}/skills" ]]; then
  rsync -a "${JUPITER_REPO_DIR}/skills/" "${JUPITER_WORKSPACE}/.claude/skills/"
fi
chown -R "${JUPITER_USER}:${JUPITER_USER}" "$JUPITER_WORKSPACE" "$JUPITER_REPO_DIR" || true
echo "JUPITER updated. Start with: jupiter"
