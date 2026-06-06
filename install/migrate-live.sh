#!/usr/bin/env bash
# Миграция БОЕВЫХ агентов на двухагентную модель (layout ~/.claude-lab, роли,
# делегирование, перенастройка Telegram-моста) БЕЗ потери данных.
#
#   sudo bash install/migrate-live.sh
#   sudo OPERATOR=jupiter EXECUTOR=uran bash install/migrate-live.sh
#
# Что делает:
#   1. Бэкап ~/.claude, ~/.config, ~/workspace обоих агентов в /root.
#   2. Останавливает tg-<agent> на время миграции.
#   3. Откладывает старые settings.json -> .bak (чтобы сгенерились ролевые,
#      у оператора с правом делегирования Bash(<executor>:*)).
#   4. Переустанавливает обоих из локального чекаута: layout .claude-lab,
#      перенос ~/workspace (rsync, старое НЕ удаляется), ролевой CLAUDE.md (force).
#   5. Связывает operator -> executor (sudoers).
#   6. Перенастраивает Telegram-мост (если был) на новый layout и запускает.
#   7. Проверки + итог. Старый ~/workspace оставляет — удалишь вручную после проверки.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SELF_DIR}/.." && pwd)"

OPERATOR="$(printf '%s' "${OPERATOR:-jupiter}" | tr '[:upper:]' '[:lower:]')"
EXECUTOR="$(printf '%s' "${EXECUTOR:-uran}" | tr '[:upper:]' '[:lower:]')"

[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo bash install/migrate-live.sh"; exit 1; }
for n in "$OPERATOR" "$EXECUTOR"; do id -u "$n" >/dev/null 2>&1 || { echo "Нет пользователя '$n'"; exit 1; }; done

ts(){ date +%F-%H%M%S; }
say(){ printf '\n=== %s ===\n' "$*"; }

BACKUP="/root/agents-backup-$(ts).tgz"
say "1. Бэкап -> ${BACKUP}"
tar czf "$BACKUP" \
  "/home/${OPERATOR}/.claude" "/home/${OPERATOR}/.config" "/home/${OPERATOR}/workspace" \
  "/home/${EXECUTOR}/.claude" "/home/${EXECUTOR}/.config" "/home/${EXECUTOR}/workspace" \
  2>/dev/null && echo "  ок" || echo "  частичный бэкап (часть путей отсутствует — норм)"

say "2. Останавливаю Telegram-мосты на время миграции"
for a in "$OPERATOR" "$EXECUTOR"; do
  if systemctl is-active "tg-${a}" >/dev/null 2>&1; then systemctl stop "tg-${a}" && echo "  tg-${a} остановлен"; else echo "  tg-${a} не запущен"; fi
done

say "3. Откладываю старые settings.json -> .bak"
for a in "$OPERATOR" "$EXECUTOR"; do
  f="/home/${a}/.claude/settings.json"
  if [[ -f "$f" ]]; then mv "$f" "${f}.bak-$(ts)" && echo "  ${a}: отложен"; else echo "  ${a}: settings.json нет"; fi
done

say "4. Переустановка из локального чекаута (${REPO})"
export AGENT_REPO_SOURCE=local AGENT_FORCE_PROMPT=1
echo "--- ${OPERATOR} (operator) ---"
AGENT="$OPERATOR" AGENT_ROLE=operator bash "$REPO/install/install.sh" || echo "  ВНИМАНИЕ: установка ${OPERATOR} вернула ошибку"
echo "--- ${EXECUTOR} (executor) ---"
AGENT="$EXECUTOR" AGENT_ROLE=executor bash "$REPO/install/install.sh" || echo "  ВНИМАНИЕ: установка ${EXECUTOR} вернула ошибку"

say "5. Связка ${OPERATOR} -> ${EXECUTOR}"
OPERATOR="$OPERATOR" EXECUTOR="$EXECUTOR" bash "$REPO/install/link-agents.sh" || echo "  ВНИМАНИЕ: link-agents вернул ошибку"

say "6. Telegram-мост на новый layout"
for a in "$OPERATOR" "$EXECUTOR"; do
  if [[ -f "/home/${a}/.config/${a}/telegram.env" ]]; then
    AGENT="$a" bash "$REPO/install/telegram-install.sh" >/dev/null 2>&1 && echo "  ${a}: мост перенастроен"
    systemctl enable --now "tg-${a}" >/dev/null 2>&1 || true
    systemctl restart "tg-${a}" 2>/dev/null && echo "  ${a}: tg-${a} перезапущен" || echo "  ${a}: tg-${a} не перезапущен"
  else
    echo "  ${a}: telegram.env нет — мост пропущен"
  fi
done

say "7. ПРОВЕРКИ"
op_c="/home/${OPERATOR}/.claude-lab/${OPERATOR}/.claude/CLAUDE.md"
ex_c="/home/${EXECUTOR}/.claude-lab/${EXECUTOR}/.claude/CLAUDE.md"
echo -n "  operator CLAUDE.md: "; [[ -f "$op_c" ]] && head -1 "$op_c" || echo MISSING
echo -n "  executor CLAUDE.md: "; [[ -f "$ex_c" ]] && head -1 "$ex_c" || echo MISSING
echo -n "  делегирование в settings оператора: "; grep -o "Bash(${EXECUTOR}:\*)\|Bash(uran:\*)" "/home/${OPERATOR}/.claude/settings.json" 2>/dev/null || echo "НЕТ — проверь settings"
echo -n "  sudoers ${OPERATOR}->${EXECUTOR}: "; [[ -f "/etc/sudoers.d/${OPERATOR}-to-${EXECUTOR}" ]] && echo OK || echo MISSING
for a in "$OPERATOR" "$EXECUTOR"; do
  echo -n "  tg-${a}: "; systemctl is-active "tg-${a}" 2>/dev/null || echo "(не активен/нет)"
done

cat <<EOF

=== ГОТОВО ===
Бэкап:        ${BACKUP}
Старый workspace НЕ удалён: /home/${OPERATOR}/workspace , /home/${EXECUTOR}/workspace
Проверь работу, затем удали старое вручную:
  rm -rf /home/${OPERATOR}/workspace /home/${EXECUTOR}/workspace

Проверка делегирования (нужен выполненный 'claude login' у обоих):
  sudo -u ${OPERATOR} -H ${OPERATOR} -p "Передай ${EXECUTOR}: ответь строкой PONG" --output-format json

Откат: распакуй ${BACKUP}, верни settings.json.bak-*, systemctl restart tg-*
EOF
