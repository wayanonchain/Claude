#!/usr/bin/env bash
set -euo pipefail
JUPITER_USER="${JUPITER_USER:-jupiter}"
JUPITER_HOME="/home/${JUPITER_USER}"

read -r -p "Remove JUPITER commands and user ${JUPITER_USER}? Type YES: " answer
[[ "$answer" == "YES" ]] || { echo "Cancelled."; exit 0; }

rm -f /usr/local/bin/jupiter /usr/local/bin/jupiter-update
if id -u "$JUPITER_USER" >/dev/null 2>&1; then
  userdel -r "$JUPITER_USER" || true
fi

echo "JUPITER removed."
