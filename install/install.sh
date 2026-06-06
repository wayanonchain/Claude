#!/usr/bin/env bash
# Универсальный установщик одного агента Claude Code (JUPITER, URAN, ...).
# Двухагентная архитектура (модель EdgeLab Day-1):
#   - роль operator  -> шлюз/маршрутизатор (шаблон templates/jupiter.md)
#   - роль executor  -> исполнитель        (шаблон templates/uran.md)
# Repo: https://github.com/wayanonchain/Claude
# Target: clean Ubuntu 22.04 / 24.04 VPS
#
#   sudo AGENT=jupiter bash install/install.sh         # роль operator (по имени)
#   sudo AGENT=uran    bash install/install.sh         # роль executor (по имени)
#   sudo AGENT=bob AGENT_ROLE=executor bash install/install.sh
#   sudo AGENT_REPO_SOURCE=local AGENT=uran bash install/install.sh  # ставить из локального чекаута
#
set -euo pipefail

INSTALL_VERSION="1.2.0"

# Корень репозитория = родитель папки install/, где лежит этот скрипт.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SELF_DIR}/.." && pwd)"

AGENT_RAW="${AGENT:-${1:-jupiter}}"
AGENT="$(printf '%s' "$AGENT_RAW" | tr '[:upper:]' '[:lower:]')"
[[ "$AGENT" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || { echo "Некорректное имя агента: '$AGENT_RAW' (нужно [a-z][a-z0-9_-])" >&2; exit 1; }
AGENT_UPPER="$(printf '%s' "$AGENT" | tr '[:lower:]' '[:upper:]')"

# Роль: задаётся явно (AGENT_ROLE), иначе выводится из имени.
#   jupiter -> operator, всё остальное -> executor.
if [[ -n "${AGENT_ROLE:-}" ]]; then
  AGENT_ROLE="$(printf '%s' "$AGENT_ROLE" | tr '[:upper:]' '[:lower:]')"
else
  case "$AGENT" in
    jupiter) AGENT_ROLE="operator" ;;
    *)       AGENT_ROLE="executor" ;;
  esac
fi
[[ "$AGENT_ROLE" == "operator" || "$AGENT_ROLE" == "executor" ]] || { echo "AGENT_ROLE должен быть operator|executor (получено: $AGENT_ROLE)" >&2; exit 1; }

AGENT_USER="$AGENT"
AGENT_HOME="/home/${AGENT_USER}"
AGENT_REPO="${AGENT_REPO:-https://github.com/wayanonchain/Claude.git}"
AGENT_REPO_DIR="${AGENT_REPO_DIR:-${AGENT_HOME}/Claude}"
# Layout EdgeLab: рабочая папка агента в ~/.claude-lab/<agent>.
AGENT_WORKSPACE="${AGENT_WORKSPACE:-${AGENT_HOME}/.claude-lab/${AGENT}}"
AGENT_REPO_SOURCE="${AGENT_REPO_SOURCE:-git}"   # git | local
NODE_MAJOR="${NODE_MAJOR:-22}"
OPERATOR_NAME="${OPERATOR_NAME:-Wayan}"
OPERATOR_LANGUAGE="${OPERATOR_LANGUAGE:-Russian}"
OPERATOR_TIMEZONE="${OPERATOR_TIMEZONE:-Asia/Kuala_Lumpur}"
# Старый layout для миграции без потери данных.
LEGACY_WORKSPACE="${AGENT_HOME}/workspace"

CURL_OPTS=(-fsSL --max-time 60 --retry 2 --retry-delay 3)

if [[ -t 1 ]]; then
  C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_YELLOW='\033[1;33m'; C_BLUE='\033[0;34m'; C_BOLD='\033[1m'; C_NC='\033[0m'
else
  C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_NC=''
fi
log(){ printf '%b[%s]%b %s\n' "$C_BLUE" "$(date +%H:%M:%S)" "$C_NC" "$*"; }
ok(){ printf '%b✓%b %s\n' "$C_GREEN" "$C_NC" "$*"; }
warn(){ printf '%b!%b %s\n' "$C_YELLOW" "$C_NC" "$*" >&2; }
die(){ printf '%b✗%b %s\n' "$C_RED" "$C_NC" "$*" >&2; exit 1; }
step(){ printf '\n%b== Step %s: %s ==%b\n' "$C_BOLD" "$1" "$2" "$C_NC"; }

apt_get(){
  local tries=0
  while fuser /var/lib/dpkg/lock-frontend &>/dev/null || fuser /var/lib/apt/lists/lock &>/dev/null; do
    tries=$((tries+1)); [[ $tries -gt 20 ]] && die "apt/dpkg lock держится слишком долго."; sleep 3
  done
  DEBIAN_FRONTEND=noninteractive apt-get "$@"
}
as_agent(){ sudo -u "$AGENT_USER" -H -- "$@"; }

preflight(){
  step 0 "Preflight (agent=${AGENT}, role=${AGENT_ROLE}, source=${AGENT_REPO_SOURCE})"
  [[ $EUID -eq 0 ]] || die "Запусти под root: sudo AGENT=${AGENT} bash install/install.sh"
  [[ -r /etc/os-release ]] || die "Не читается /etc/os-release"
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Неподдерживаемая ОС: ${ID:-unknown}. Нужна Ubuntu 22.04/24.04."
  case "${VERSION_ID:-}" in
    22.04|24.04) ok "Ubuntu ${VERSION_ID}" ;;
    *) [[ "${JUPITER_ALLOW_UNTESTED_UBUNTU:-0}" == "1" ]] || die "Непротестированная Ubuntu ${VERSION_ID:-unknown}. Поставь JUPITER_ALLOW_UNTESTED_UBUNTU=1." ;;
  esac
}

install_base_dependencies(){
  step 1 "Базовые пакеты"
  apt_get update -qq
  apt_get install -y -qq ca-certificates gnupg lsb-release software-properties-common sudo curl wget git jq rsync build-essential cron logrotate nano unzip
  . /etc/os-release
  if [[ "${VERSION_ID:-}" == "22.04" ]]; then
    if ! command -v python3.12 >/dev/null 2>&1; then
      log "deadsnakes PPA для Python 3.12"; add-apt-repository -y ppa:deadsnakes/ppa >/dev/null; apt_get update -qq
    fi
    apt_get install -y -qq python3.12 python3.12-venv python3.12-dev python3-pip
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100 >/dev/null 2>&1 || true
    update-alternatives --set python3 /usr/bin/python3.12 >/dev/null 2>&1 || true
  else
    apt_get install -y -qq python3 python3-venv python3-pip python3-dev
  fi
  ok "Python: $(python3 --version 2>&1)"
}

install_node(){
  step 2 "Node.js ${NODE_MAJOR}"
  if command -v node >/dev/null 2>&1; then
    local major; major=$(node -v | sed -E 's/^v([0-9]+).*/\1/')
    if [[ "$major" == "$NODE_MAJOR" ]]; then ok "Node.js $(node -v) уже стоит"; return; fi
    warn "Node.js $(node -v) != v${NODE_MAJOR}; ставлю v${NODE_MAJOR}"
  fi
  curl "${CURL_OPTS[@]}" "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt_get install -y -qq nodejs
  ok "Node.js: $(node -v)"
}

create_user(){
  step 3 "Пользователь: ${AGENT_USER}"
  if id -u "$AGENT_USER" >/dev/null 2>&1; then
    ok "Пользователь ${AGENT_USER} уже есть"
  else
    useradd --create-home --shell /bin/bash "$AGENT_USER"; ok "Пользователь ${AGENT_USER} создан"
  fi
  chown "${AGENT_USER}:${AGENT_USER}" "$AGENT_HOME"; chmod 0755 "$AGENT_HOME"
}

ensure_user_path(){
  local marker="# Added by ${AGENT_UPPER} installer"
  local line='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "${AGENT_HOME}/.bashrc" "${AGENT_HOME}/.profile"; do
    [[ -f "$rc" ]] || as_agent touch "$rc"
    if ! grep -Fq "$marker" "$rc" 2>/dev/null; then
      local tmp; tmp=$(mktemp)
      { echo "$marker"; echo "$line"; echo; cat "$rc"; } > "$tmp"
      install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "$rc"; rm -f "$tmp"
    fi
  done
}

install_claude_code(){
  step 4 "Claude Code CLI для ${AGENT_USER}"
  local claude_bin="${AGENT_HOME}/.local/bin/claude"
  if [[ -x "$claude_bin" ]]; then
    ok "Claude уже установлен: $claude_bin"
    as_agent "$claude_bin" update >/dev/null 2>&1 || warn "claude update не прошёл; продолжаю"
    ensure_user_path; return
  fi
  local tmp; tmp=$(mktemp)
  curl "${CURL_OPTS[@]}" https://claude.ai/install.sh -o "$tmp"; chmod 0644 "$tmp"
  as_agent bash "$tmp"; rm -f "$tmp"
  [[ -x "$claude_bin" ]] || die "Claude CLI не найден после установки: $claude_bin"
  ensure_user_path
  ok "Claude Code: $($claude_bin --version 2>/dev/null || echo installed)"
}

clone_repo(){
  step 5 "Репозиторий (source=${AGENT_REPO_SOURCE})"
  if [[ "$AGENT_REPO_SOURCE" == "local" ]]; then
    # Ставим из текущего локального чекаута — без зависимости от GitHub и без
    # риска получить устаревший код. .git не копируем.
    install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_REPO_DIR"
    rsync -a --delete --exclude '.git' --exclude '__pycache__' "${REPO_ROOT}/" "${AGENT_REPO_DIR}/"
    chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_REPO_DIR"
    ok "Репо из локального источника: ${REPO_ROOT} -> ${AGENT_REPO_DIR}"
    return
  fi
  if [[ -d "${AGENT_REPO_DIR}/.git" ]]; then
    log "Репо есть; pull"; as_agent git -C "$AGENT_REPO_DIR" pull --ff-only || warn "git pull не прошёл; оставляю как есть"
  else
    as_agent git clone --depth 1 "$AGENT_REPO" "$AGENT_REPO_DIR" \
      || die "git clone не прошёл (${AGENT_REPO}). Если репо локальный/приватный — запусти с AGENT_REPO_SOURCE=local."
  fi
  ok "Репо: ${AGENT_REPO_DIR}"
}

migrate_legacy_workspace(){
  # Перенос со старого layout ~/workspace на ~/.claude-lab/<agent> без потери
  # данных. Старое НЕ удаляем — оператор удалит сам после проверки.
  [[ -d "$LEGACY_WORKSPACE" ]] || return 0
  [[ "$AGENT_WORKSPACE" != "$LEGACY_WORKSPACE" ]] || return 0
  if [[ -e "${AGENT_WORKSPACE}/.claude/CLAUDE.md" ]]; then
    warn "Новый workspace уже заполнен (${AGENT_WORKSPACE}); старый ${LEGACY_WORKSPACE} не трогаю."
    return 0
  fi
  step 5.5 "Миграция со старого ~/workspace"
  install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_WORKSPACE"
  rsync -a "${LEGACY_WORKSPACE}/" "${AGENT_WORKSPACE}/"
  chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_WORKSPACE"
  warn "Скопировал ${LEGACY_WORKSPACE} -> ${AGENT_WORKSPACE}. Проверь и удали старое вручную."
}

render_template(){
  # render_template <src-template> <agent-upper-name-in-template> <dst>
  # Подставляет имя агента и профиль оператора в шаблон.
  local src="$1" name_token="$2" dst="$3" tmp
  tmp=$(mktemp)
  sed -e "s/${name_token}/${AGENT_UPPER}/g" \
      -e "s|{{OPERATOR_NAME}}|${OPERATOR_NAME}|g" \
      -e "s|{{OPERATOR_LANGUAGE}}|${OPERATOR_LANGUAGE}|g" \
      -e "s|{{OPERATOR_TIMEZONE}}|${OPERATOR_TIMEZONE}|g" \
      "$src" > "$tmp"
  install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "$dst"; rm -f "$tmp"
}

write_agent_prompt(){
  step 6 "Конфигурация агента ${AGENT_UPPER} (роль: ${AGENT_ROLE})"
  local claude_dir="${AGENT_HOME}/.claude"
  local workspace_claude="${AGENT_WORKSPACE}/.claude"

  install -d -m 0700 -o "$AGENT_USER" -g "$AGENT_USER" "$claude_dir"
  install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" \
    "${AGENT_HOME}/.claude-lab" \
    "$AGENT_WORKSPACE" \
    "${AGENT_WORKSPACE}/coding" "${AGENT_WORKSPACE}/research" "${AGENT_WORKSPACE}/content" \
    "${AGENT_WORKSPACE}/reports" "${AGENT_WORKSPACE}/projects" "${AGENT_WORKSPACE}/logs" \
    "$workspace_claude" "${workspace_claude}/skills" "${workspace_claude}/memory"

  # Выбор шаблона по роли.
  local op_template="${AGENT_REPO_DIR}/templates/jupiter.md"
  local ex_template="${AGENT_REPO_DIR}/templates/uran.md"
  if [[ "$AGENT_ROLE" == "operator" && -f "$op_template" ]]; then
    render_template "$op_template" "JUPITER" "${workspace_claude}/CLAUDE.md"
  elif [[ "$AGENT_ROLE" == "executor" && -f "$ex_template" ]]; then
    render_template "$ex_template" "URAN" "${workspace_claude}/CLAUDE.md"
  else
    warn "Шаблон роли ${AGENT_ROLE} не найден; пишу минимальный CLAUDE.md"
    local tmp; tmp=$(mktemp)
    cat > "$tmp" <<EOF2
# ${AGENT_UPPER}

You are ${AGENT_UPPER} (role: ${AGENT_ROLE}).

Operator: ${OPERATOR_NAME} | Language: ${OPERATOR_LANGUAGE} | TZ: ${OPERATOR_TIMEZONE}

- Keep secrets, API keys, tokens, and .env files out of git.
- Before destructive operations, show the exact command and explain the impact.
- Use git status and git diff before committing.
- Never run broad cleanup commands from / or /home without explicit confirmation.

Workspace: ${AGENT_WORKSPACE}
EOF2
    install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${workspace_claude}/CLAUDE.md"; rm -f "$tmp"
  fi

  # Глобальные правила (~/.claude/CLAUDE.md) — не перезаписываем, если уже есть.
  if [[ ! -f "${claude_dir}/CLAUDE.md" ]]; then
    local tmp; tmp=$(mktemp)
    cat > "$tmp" <<EOF2
# Global Claude Rules for ${AGENT_UPPER}

- Agent name: ${AGENT_UPPER}
- Role: ${AGENT_ROLE}
- Universal digital employee (project-neutral).
- Do not expose secrets.
- Ask before risky production actions.
- Keep changes auditable through git.
EOF2
    install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${claude_dir}/CLAUDE.md"; rm -f "$tmp"
  fi

  # settings.json — права по роли. operator дополнительно может звать исполнителя.
  if [[ ! -f "${claude_dir}/settings.json" ]]; then
    local tmp; tmp=$(mktemp)
    if [[ "$AGENT_ROLE" == "operator" ]]; then
      cat > "$tmp" <<'EOF2'
{
  "env": { "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000" },
  "permissions": {
    "allow": [
      "Read", "Write", "Edit",
      "Bash(git:*)", "Bash(ls:*)", "Bash(cat:*)", "Bash(find:*)", "Bash(grep:*)",
      "Bash(uran:*)"
    ]
  }
}
EOF2
    else
      cat > "$tmp" <<'EOF2'
{
  "env": { "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000" },
  "permissions": {
    "allow": [
      "Read", "Write", "Edit",
      "Bash(git:*)", "Bash(node:*)", "Bash(npm:*)", "Bash(python3:*)", "Bash(pip3:*)",
      "Bash(ls:*)", "Bash(cat:*)", "Bash(mkdir:*)", "Bash(cp:*)", "Bash(mv:*)",
      "Bash(find:*)", "Bash(grep:*)"
    ]
  }
}
EOF2
    fi
    install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${claude_dir}/settings.json"; rm -f "$tmp"
  fi

  chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_HOME"
  ok "${AGENT_UPPER} сконфигурирован (роль ${AGENT_ROLE}, workspace ${AGENT_WORKSPACE})"
}

install_edge_skills(){
  step 7 "Универсальные скиллы"
  local skills_dir="${AGENT_WORKSPACE}/.claude/skills"
  install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" "$skills_dir"
  if [[ -d "${AGENT_REPO_DIR}/skills" ]]; then
    rsync -a "${AGENT_REPO_DIR}/skills/" "$skills_dir/"
    chown -R "${AGENT_USER}:${AGENT_USER}" "$skills_dir"
    ok "Скиллы: $skills_dir"
  else
    warn "В репо нет папки skills/ — пропускаю"
  fi
}

install_commands(){
  step 8 "Команды запуска: ${AGENT}, ${AGENT}-exec, ${AGENT}-update"

  # Фиксированный helper (root-owned): запускает claude этого агента в его
  # workspace ОТ ИМЕНИ ТЕКУЩЕГО пользователя. Единая точка для sudoers, чтобы
  # другой агент мог делегировать сюда узко (см. install/link-agents.sh).
  cat > "/usr/local/bin/${AGENT}-exec" <<EOF2
#!/usr/bin/env bash
set -euo pipefail
exec env -C "${AGENT_WORKSPACE}" "${AGENT_HOME}/.local/bin/claude" "\$@"
EOF2
  chmod 0755 "/usr/local/bin/${AGENT}-exec"

  # Обычная команда запуска: sudo в пользователя агента + фиксированный helper.
  cat > "/usr/local/bin/${AGENT}" <<EOF2
#!/usr/bin/env bash
set -euo pipefail
exec sudo -u "${AGENT_USER}" -H -- "/usr/local/bin/${AGENT}-exec" "\$@"
EOF2
  chmod 0755 "/usr/local/bin/${AGENT}"

  cat > "/usr/local/bin/${AGENT}-update" <<EOF2
#!/usr/bin/env bash
set -euo pipefail
if [[ -d "${AGENT_REPO_DIR}/.git" ]]; then
  sudo -u "${AGENT_USER}" -H -- git -C "${AGENT_REPO_DIR}" pull --ff-only || true
fi
sudo -u "${AGENT_USER}" -H -- "${AGENT_HOME}/.local/bin/claude" update || true
if [[ -d "${AGENT_REPO_DIR}/skills" ]]; then
  rsync -a "${AGENT_REPO_DIR}/skills/" "${AGENT_WORKSPACE}/.claude/skills/"
fi
# Передеплой Telegram-моста, если он установлен (иначе багфиксы не доедут).
BRIDGE_DST="${AGENT_HOME}/.config/${AGENT}/telegram_bridge.py"
if [[ -f "\$BRIDGE_DST" && -f "${AGENT_REPO_DIR}/tools/telegram_bridge.py" ]]; then
  install -o "${AGENT_USER}" -g "${AGENT_USER}" -m 0700 "${AGENT_REPO_DIR}/tools/telegram_bridge.py" "\$BRIDGE_DST"
  systemctl try-restart "tg-${AGENT}.service" 2>/dev/null || true
fi
chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_WORKSPACE}/.claude/skills" "${AGENT_REPO_DIR}" || true
EOF2
  chmod 0755 "/usr/local/bin/${AGENT}-update"
  ok "Команды установлены: ${AGENT}, ${AGENT}-exec, ${AGENT}-update"
}

final_message(){
  cat <<EOF2

${C_GREEN}Агент ${AGENT_UPPER} установлен (роль: ${AGENT_ROLE}).${C_NC}

Дальше:
1) Логин Claude Code (один раз):
   sudo -u ${AGENT_USER} -H bash -lc '${AGENT_HOME}/.local/bin/claude login'

2) Запуск агента:
   ${AGENT}

3) Обновление:
   ${AGENT}-update

Пути:
- User:      ${AGENT_USER}
- Role:      ${AGENT_ROLE}
- Repo:      ${AGENT_REPO_DIR}
- Workspace: ${AGENT_WORKSPACE}
- Agent:     ${AGENT_WORKSPACE}/.claude/CLAUDE.md
- Skills:    ${AGENT_WORKSPACE}/.claude/skills

EOF2
  if [[ "$AGENT_ROLE" == "operator" ]]; then
    cat <<EOF2
Двухагентная схема: поставь исполнителя командой
   sudo AGENT=uran bash install/install.sh
тогда ${AGENT} сможет делегировать задачи через:  uran -p "<задача>" --output-format json

EOF2
  fi
}

main(){
  preflight
  install_base_dependencies
  install_node
  create_user
  install_claude_code
  clone_repo
  migrate_legacy_workspace
  write_agent_prompt
  install_edge_skills
  install_commands
  final_message
}
main "$@"
