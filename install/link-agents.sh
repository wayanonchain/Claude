#!/usr/bin/env bash
# Связывает оператора (operator) с исполнителем (executor) для делегирования
# задач: operator получает право БЕЗ ПАРОЛЯ запускать ровно один фиксированный
# helper исполнителя (/usr/local/bin/<executor>-exec) от имени пользователя
# executor. Узкое правило sudoers — модель least-privilege EdgeLab Day-1.
#
#   sudo bash install/link-agents.sh                 # jupiter -> uran (по умолчанию)
#   sudo OPERATOR=jupiter EXECUTOR=uran bash install/link-agents.sh
#   sudo bash install/link-agents.sh --unlink        # снять связь
#
# После связки JUPITER делегирует так:
#   uran -p "<самодостаточная задача>" --output-format json
set -euo pipefail

OPERATOR="$(printf '%s' "${OPERATOR:-jupiter}" | tr '[:upper:]' '[:lower:]')"
EXECUTOR="$(printf '%s' "${EXECUTOR:-uran}" | tr '[:upper:]' '[:lower:]')"
UNLINK=0
for a in "$@"; do case "$a" in --unlink) UNLINK=1 ;; *) echo "Неизвестный флаг: $a" >&2; exit 1 ;; esac; done

for n in "$OPERATOR" "$EXECUTOR"; do
  [[ "$n" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || { echo "Некорректное имя: '$n'" >&2; exit 1; }
done
[[ "$OPERATOR" != "$EXECUTOR" ]] || { echo "operator и executor не могут совпадать" >&2; exit 1; }
[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo bash install/link-agents.sh" >&2; exit 1; }

SUDOERS_FILE="/etc/sudoers.d/${OPERATOR}-to-${EXECUTOR}"

if [[ "$UNLINK" == "1" ]]; then
  rm -f "$SUDOERS_FILE"
  echo "Связь ${OPERATOR} -> ${EXECUTOR} снята (${SUDOERS_FILE} удалён)."
  exit 0
fi

id -u "$OPERATOR" >/dev/null 2>&1 || { echo "Нет пользователя '${OPERATOR}'. Сначала: sudo AGENT=${OPERATOR} bash install/install.sh" >&2; exit 1; }
id -u "$EXECUTOR" >/dev/null 2>&1 || { echo "Нет пользователя '${EXECUTOR}'. Сначала: sudo AGENT=${EXECUTOR} bash install/install.sh" >&2; exit 1; }
EXEC_HELPER="/usr/local/bin/${EXECUTOR}-exec"
[[ -x "$EXEC_HELPER" ]] || { echo "Нет helper'а ${EXEC_HELPER}. Переустанови исполнителя: sudo AGENT=${EXECUTOR} bash install/install.sh" >&2; exit 1; }

# Узкое правило: оператор может запускать ТОЛЬКО этот helper как пользователь executor.
tmp="$(mktemp)"
cat > "$tmp" <<EOF
# ${OPERATOR} делегирует задачи ${EXECUTOR} через фиксированный helper. Создано link-agents.sh.
${OPERATOR} ALL=(${EXECUTOR}) NOPASSWD: ${EXEC_HELPER}
EOF
# Проверяем синтаксис перед установкой, иначе можно сломать sudo.
visudo -cf "$tmp" >/dev/null || { echo "visudo: некорректный sudoers, не применяю." >&2; rm -f "$tmp"; exit 1; }
install -m 0440 -o root -g root "$tmp" "$SUDOERS_FILE"
rm -f "$tmp"

echo "Связь установлена: ${OPERATOR} -> ${EXECUTOR}"
echo "  правило: ${SUDOERS_FILE}"
echo "  ${OPERATOR} теперь может делегировать:  ${EXECUTOR} -p \"<задача>\" --output-format json"
