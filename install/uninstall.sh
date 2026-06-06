#!/usr/bin/env bash
# Снятие одного агента. По умолчанию данные пользователя НЕ удаляются
# (токен логина, telegram.env, рабочие файлы остаются). Полное удаление — --purge.
#
#   sudo AGENT=uran bash install/uninstall.sh            # убрать команды + сервис, home оставить
#   sudo AGENT=uran bash install/uninstall.sh --purge    # + userdel -r (СНЕСЁТ home и токены!)
#
set -euo pipefail

# Имя агента: AGENT, либо легаси JUPITER_USER, либо первый позиционный аргумент.
AGENT_RAW="${AGENT:-${JUPITER_USER:-${1:-jupiter}}}"
AGENT="$(printf '%s' "$AGENT_RAW" | tr '[:upper:]' '[:lower:]')"
[[ "$AGENT" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || { echo "Некорректное имя агента: '$AGENT_RAW'" >&2; exit 1; }

PURGE=0
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    "$AGENT_RAW"|"$AGENT") : ;;  # имя как позиционный аргумент — игнорируем
    *) echo "Неизвестный флаг: $a" >&2; exit 1 ;;
  esac
done

[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo AGENT=${AGENT} bash install/uninstall.sh" >&2; exit 1; }

AGENT_HOME="/home/${AGENT}"
SERVICE="tg-${AGENT}"

echo "Удаляю агента: ${AGENT}"
echo " - команды:  /usr/local/bin/${AGENT}, /usr/local/bin/${AGENT}-update"
echo " - сервис:   ${SERVICE}.service"
if [[ "$PURGE" == "1" ]]; then
  echo " - PURGE:    userdel -r ${AGENT} (УДАЛИТ ${AGENT_HOME} вместе с токеном логина и telegram.env)"
fi
read -r -p "Подтверди — впиши YES: " answer
[[ "$answer" == "YES" ]] || { echo "Отменено."; exit 0; }

# systemd-сервис Telegram-моста.
if systemctl list-unit-files "${SERVICE}.service" >/dev/null 2>&1; then
  systemctl disable --now "${SERVICE}.service" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE}.service"
  systemctl daemon-reload 2>/dev/null || true
  echo "Сервис ${SERVICE} снят."
fi

# Команды запуска (именно этого агента).
rm -f "/usr/local/bin/${AGENT}" "/usr/local/bin/${AGENT}-exec" "/usr/local/bin/${AGENT}-update"

# Sudoers-связи, где этот агент — оператор или исполнитель.
rm -f /etc/sudoers.d/${AGENT}-to-* /etc/sudoers.d/*-to-${AGENT} 2>/dev/null || true

if [[ "$PURGE" == "1" ]]; then
  if id -u "$AGENT" >/dev/null 2>&1; then
    userdel -r "$AGENT" 2>/dev/null || userdel "$AGENT" || true
    echo "Пользователь ${AGENT} и его home удалены."
  fi
else
  echo "Home ${AGENT_HOME} оставлен (данные/токены целы). Для полного удаления: --purge"
fi

echo "Готово: ${AGENT} снят."
