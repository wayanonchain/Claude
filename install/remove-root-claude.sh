#!/usr/bin/env bash
# Удаляет установку Claude Code из-под пользователя root. Не трогает других юзеров.
#
#   sudo bash install/remove-root-claude.sh            # dry-run: только покажет план
#   sudo bash install/remove-root-claude.sh --yes      # удалит бинарь + ~/.local/share/claude
#   sudo bash install/remove-root-claude.sh --yes --purge  # + удалит ~/.claude и ~/.claude.json (креды/конфиг)
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo bash install/remove-root-claude.sh" >&2; exit 1; }

ROOT_HOME="$(getent passwd root | cut -d: -f6)"; ROOT_HOME="${ROOT_HOME:-/root}"

APPLY=0; PURGE=0
for a in "$@"; do
  case "$a" in
    --yes) APPLY=1 ;;
    --purge) PURGE=1 ;;
    *) echo "Неизвестный флаг: $a" >&2; exit 1 ;;
  esac
done

# Цели — строго внутри домашней папки root.
targets=(
  "${ROOT_HOME}/.local/bin/claude"
  "${ROOT_HOME}/.local/share/claude"
)
purge_targets=(
  "${ROOT_HOME}/.claude"
  "${ROOT_HOME}/.claude.json"
)
[[ $PURGE -eq 1 ]] && targets+=("${purge_targets[@]}")

# Защита: ни одна цель не должна выходить за пределы /root.
for t in "${targets[@]}"; do
  case "$t" in
    "${ROOT_HOME}/"*) : ;;
    *) echo "ОТКАЗ: цель вне ${ROOT_HOME}: $t" >&2; exit 1 ;;
  esac
done

echo "=== Будет удалено: ==="
for t in "${targets[@]}"; do
  if [[ -e "$t" || -L "$t" ]]; then printf '  %s  (%s)\n' "$t" "$(du -sh "$t" 2>/dev/null | cut -f1)"; else printf '  %s  (нет — пропуск)\n' "$t"; fi
done
[[ $PURGE -eq 0 ]] && echo "  (конфиг/креды ${ROOT_HOME}/.claude НЕ трогаем — добавь --purge чтобы удалить)"
echo

if [[ $APPLY -eq 0 ]]; then
  echo "DRY-RUN. Ничего не удалено. Для применения добавь --yes (и --purge для конфига)."
  exit 0
fi

for t in "${targets[@]}"; do
  if [[ -e "$t" || -L "$t" ]]; then rm -rf -- "$t" && echo "удалено: $t"; fi
done

# Убрать строки PATH/claude из шелл-конфигов root (бэкап рядом).
for rc in "${ROOT_HOME}/.bashrc" "${ROOT_HOME}/.profile"; do
  if [[ -f "$rc" ]] && grep -qE 'claude|\.local/bin' "$rc"; then
    cp -a "$rc" "${rc}.bak.preremove"
    grep -vE 'Added by JUPITER installer|\.local/bin' "$rc" > "${rc}.tmp" && mv "${rc}.tmp" "$rc"
    echo "почищен: $rc (бэкап ${rc}.bak.preremove)"
  fi
done

echo "Готово. Claude удалён из-под root."
