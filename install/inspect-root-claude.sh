#!/usr/bin/env bash
# Read-only: показывает, что за Claude Code установлен под пользователем root.
# Ничего не удаляет. Запускать: sudo bash install/inspect-root-claude.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo bash install/inspect-root-claude.sh" >&2; exit 1; }

ROOT_HOME="$(getent passwd root | cut -d: -f6)"
ROOT_HOME="${ROOT_HOME:-/root}"

echo "=== root home: ${ROOT_HOME} ==="
echo

echo "=== claude в PATH у root ==="
command -v claude 2>/dev/null || echo "  (не в PATH)"
echo

echo "=== бинарь/симлинк ${ROOT_HOME}/.local/bin/claude ==="
ls -la "${ROOT_HOME}/.local/bin/claude" 2>/dev/null || echo "  нет"
echo

echo "=== установка ${ROOT_HOME}/.local/share/claude ==="
if [[ -d "${ROOT_HOME}/.local/share/claude" ]]; then
  du -sh "${ROOT_HOME}/.local/share/claude" 2>/dev/null
  ls -la "${ROOT_HOME}/.local/share/claude/versions" 2>/dev/null || true
else
  echo "  нет"
fi
echo

echo "=== конфиг/креды ${ROOT_HOME}/.claude ==="
if [[ -d "${ROOT_HOME}/.claude" ]]; then
  du -sh "${ROOT_HOME}/.claude" 2>/dev/null
  ls -la "${ROOT_HOME}/.claude" 2>/dev/null | sed 's/^/  /'
  echo "  --- наличие креденшелов: ---"
  ls -la "${ROOT_HOME}/.claude/.credentials.json" 2>/dev/null || echo "  .credentials.json: нет"
  ls -la "${ROOT_HOME}/.claude.json" 2>/dev/null || echo "  ${ROOT_HOME}/.claude.json: нет"
else
  echo "  нет"
fi
echo

echo "=== глобальный npm @anthropic-ai/claude-code (если ставился через npm) ==="
( ls -la /usr/lib/node_modules/@anthropic-ai 2>/dev/null; \
  ls -la /usr/local/lib/node_modules/@anthropic-ai 2>/dev/null ) || true
npm ls -g --depth=0 2>/dev/null | grep -i claude || echo "  npm-глобально не найдено"
echo

echo "=== строки про claude в шелл-конфигах root ==="
grep -nE 'claude|\.local/bin' "${ROOT_HOME}/.bashrc" "${ROOT_HOME}/.profile" 2>/dev/null | sed 's/^/  /' || echo "  нет упоминаний"
echo
echo "=== Готово. Это только просмотр, ничего не удалено. ==="
