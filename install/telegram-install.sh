#!/usr/bin/env bash
# Ставит Telegram-мост для одного агента как systemd-сервис.
# Один бот = один агент. Токен берётся из ~/.config/<agent>/telegram.env (его
# создаёт оператор сам; в git не попадает).
#
#   sudo AGENT=jupiter bash install/telegram-install.sh
#   sudo AGENT=uran    bash install/telegram-install.sh
#
set -euo pipefail

AGENT_RAW="${AGENT:-${1:-jupiter}}"
AGENT="$(printf '%s' "$AGENT_RAW" | tr '[:upper:]' '[:lower:]')"
[[ "$AGENT" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || { echo "Некорректное имя агента: '$AGENT_RAW'" >&2; exit 1; }

AGENT_HOME="/home/${AGENT}"
# Layout EdgeLab: рабочая папка агента в ~/.claude-lab/<agent> (см. install.sh).
AGENT_WORKSPACE="${AGENT_WORKSPACE:-${AGENT_HOME}/.claude-lab/${AGENT}}"
CLAUDE_BIN="${CLAUDE_BIN:-${AGENT_HOME}/.local/bin/claude}"
REPO_DIR="${REPO_DIR:-${AGENT_HOME}/Claude}"
CONF_DIR="${AGENT_HOME}/.config/${AGENT}"
ENV_FILE="${CONF_DIR}/telegram.env"
STATE_FILE="${CONF_DIR}/telegram-sessions.json"
BRIDGE_DST="${CONF_DIR}/telegram_bridge.py"
SERVICE="tg-${AGENT}"

[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo AGENT=${AGENT} bash install/telegram-install.sh" >&2; exit 1; }
id -u "$AGENT" >/dev/null 2>&1 || { echo "Пользователь '${AGENT}' не найден. Сначала: sudo AGENT=${AGENT} bash install/install.sh" >&2; exit 1; }
[[ -x "$CLAUDE_BIN" ]] || { echo "Claude CLI не найден: ${CLAUDE_BIN}" >&2; exit 1; }

SRC_BRIDGE="${REPO_DIR}/tools/telegram_bridge.py"
SRC_ENV="${REPO_DIR}/tools/telegram.env.example"
[[ -f "$SRC_BRIDGE" ]] || { echo "Нет ${SRC_BRIDGE} (обнови репо)" >&2; exit 1; }

install -d -m 0700 -o "$AGENT" -g "$AGENT" "$CONF_DIR"
install -o "$AGENT" -g "$AGENT" -m 0700 "$SRC_BRIDGE" "$BRIDGE_DST"

# Заготовка env-файла, только если его ещё нет (не перезатираем реальный токен).
if [[ ! -f "$ENV_FILE" ]]; then
  sed "s/^AGENT_NAME=.*/AGENT_NAME=${AGENT}/" "$SRC_ENV" > "${ENV_FILE}.new"
  install -o "$AGENT" -g "$AGENT" -m 0600 "${ENV_FILE}.new" "$ENV_FILE"
  rm -f "${ENV_FILE}.new"
  echo "Создан шаблон ${ENV_FILE} — впиши TELEGRAM_BOT_TOKEN и TELEGRAM_ALLOWED_IDS."
  NEED_EDIT=1
else
  echo "Конфиг уже есть: ${ENV_FILE} (не трогаю)."
  NEED_EDIT=0
fi

# systemd-юнит
cat > "/etc/systemd/system/${SERVICE}.service" <<EOF2
[Unit]
Description=Telegram bridge for Claude agent ${AGENT}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${AGENT}
Group=${AGENT}
WorkingDirectory=${AGENT_WORKSPACE}
EnvironmentFile=${ENV_FILE}
Environment=CLAUDE_BIN=${CLAUDE_BIN}
Environment=CLAUDE_WORKSPACE=${AGENT_WORKSPACE}
Environment=STATE_FILE=${STATE_FILE}
ExecStart=/usr/bin/python3 ${BRIDGE_DST}
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF2

systemctl daemon-reload
echo
echo "Сервис ${SERVICE}.service установлен."
if [[ "$NEED_EDIT" == "1" ]]; then
  cat <<EOF2

Дальше:
1) Впиши токен и свой Telegram id:
   sudo -u ${AGENT} nano ${ENV_FILE}
2) Запусти и включи автозапуск:
   sudo systemctl enable --now ${SERVICE}
3) Логи:
   sudo journalctl -u ${SERVICE} -f
EOF2
else
  echo "Запуск:  sudo systemctl enable --now ${SERVICE}"
  echo "Логи:    sudo journalctl -u ${SERVICE} -f"
fi
