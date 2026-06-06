#!/usr/bin/env bash
# Обобщённый установщик одного агента Claude Code (JUPITER, URAN, ...).
# Имя агента задаёт пользователя, workspace и команды запуска.
# Repo: https://github.com/wayanonchain/Claude
# Target: clean Ubuntu 22.04 / 24.04 VPS
#
#   sudo AGENT=uran bash install/agent-install.sh
#   sudo bash install/agent-install.sh uran
#
set -euo pipefail

INSTALL_VERSION="1.1.0"

AGENT_RAW="${AGENT:-${1:-jupiter}}"
AGENT="$(printf '%s' "$AGENT_RAW" | tr '[:upper:]' '[:lower:]')"
[[ "$AGENT" =~ ^[a-z][a-z0-9_-]{1,30}$ ]] || { echo "Некорректное имя агента: '$AGENT_RAW' (нужно [a-z][a-z0-9_-])" >&2; exit 1; }
AGENT_UPPER="$(printf '%s' "$AGENT" | tr '[:lower:]' '[:upper:]')"

AGENT_USER="$AGENT"
AGENT_HOME="/home/${AGENT_USER}"
AGENT_REPO="${AGENT_REPO:-https://github.com/wayanonchain/Claude.git}"
AGENT_REPO_DIR="${AGENT_REPO_DIR:-${AGENT_HOME}/Claude}"
AGENT_WORKSPACE="${AGENT_WORKSPACE:-${AGENT_HOME}/workspace}"
NODE_MAJOR="${NODE_MAJOR:-22}"
OPERATOR_NAME="${OPERATOR_NAME:-Wayan}"
OPERATOR_LANGUAGE="${OPERATOR_LANGUAGE:-Russian}"
OPERATOR_TIMEZONE="${OPERATOR_TIMEZONE:-Asia/Kuala_Lumpur}"

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
  step 0 "Preflight (agent=${AGENT})"
  [[ $EUID -eq 0 ]] || die "Запусти под root: sudo AGENT=${AGENT} bash install/agent-install.sh"
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
  step 5 "Репозиторий"
  if [[ -d "${AGENT_REPO_DIR}/.git" ]]; then
    log "Репо есть; pull"; as_agent git -C "$AGENT_REPO_DIR" pull --ff-only || warn "git pull не прошёл; оставляю как есть"
  else
    as_agent git clone --depth 1 "$AGENT_REPO" "$AGENT_REPO_DIR"
  fi
  ok "Репо: ${AGENT_REPO_DIR}"
}

write_agent_prompt(){
  step 6 "Конфигурация агента ${AGENT_UPPER}"
  local claude_dir="${AGENT_HOME}/.claude"
  local workspace_claude="${AGENT_WORKSPACE}/.claude"

  install -d -m 0700 -o "$AGENT_USER" -g "$AGENT_USER" "$claude_dir"
  install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" \
    "$AGENT_WORKSPACE" \
    "${AGENT_WORKSPACE}/coding" "${AGENT_WORKSPACE}/research" "${AGENT_WORKSPACE}/content" \
    "${AGENT_WORKSPACE}/reports" "${AGENT_WORKSPACE}/projects" "${AGENT_WORKSPACE}/logs" \
    "$workspace_claude" "${workspace_claude}/skills" "${workspace_claude}/memory"

  # Промпт агента — близнец шаблона jupiter.md с подстановкой имени.
  local template="${AGENT_REPO_DIR}/templates/jupiter.md"
  local tmp; tmp=$(mktemp)
  if [[ -f "$template" ]]; then
    sed "s/JUPITER/${AGENT_UPPER}/g" "$template" > "$tmp"
  else
    cat > "$tmp" <<EOF2
# ${AGENT_UPPER}

You are ${AGENT_UPPER}.

Role:
- Edge Skills operator
- Research assistant
- Automation engineer
- Software engineering assistant
- Content creator

Operator profile:
- Name: ${OPERATOR_NAME}
- Preferred language: ${OPERATOR_LANGUAGE}
- Timezone: ${OPERATOR_TIMEZONE}

Operating rules:
- Use the repository at ${AGENT_REPO_DIR} as the source of templates and skills.
- Keep secrets, API keys, tokens, passwords, private keys, and .env files out of git.
- Before destructive operations, show the exact command and explain the impact.
- Prefer small reversible changes.
- Use git status and git diff before committing.
- Never run broad cleanup commands from / or /home without explicit confirmation.

Default workspace:
${AGENT_WORKSPACE}
EOF2
  fi
  install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${workspace_claude}/CLAUDE.md"; rm -f "$tmp"

  # Глобальные правила (~/.claude/CLAUDE.md) — не перезаписываем, если уже есть.
  if [[ ! -f "${claude_dir}/CLAUDE.md" ]]; then
    tmp=$(mktemp)
    cat > "$tmp" <<EOF2
# Global Claude Rules for ${AGENT_UPPER}

- Agent name: ${AGENT_UPPER}
- Use project-neutral Edge Skills.
- Do not expose secrets.
- Ask before risky production actions.
- Keep changes auditable through git.
EOF2
    install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${claude_dir}/CLAUDE.md"; rm -f "$tmp"
  fi

  if [[ ! -f "${claude_dir}/settings.json" ]]; then
    tmp=$(mktemp)
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
    install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${claude_dir}/settings.json"; rm -f "$tmp"
  fi

  chown -R "${AGENT_USER}:${AGENT_USER}" "$AGENT_HOME"
  ok "${AGENT_UPPER} сконфигурирован"
}

install_edge_skills(){
  step 7 "Edge Skills"
  local skills_dir="${AGENT_WORKSPACE}/.claude/skills"
  install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" "$skills_dir"
  [[ -d "${AGENT_REPO_DIR}/skills" ]] && rsync -a "${AGENT_REPO_DIR}/skills/" "$skills_dir/"
  local skill
  for skill in research code automation documentation content data-analysis web-analysis project-management x-thread-writer telegram-post-writer claude-code-developer; do
    install -d -m 0755 -o "$AGENT_USER" -g "$AGENT_USER" "${skills_dir}/${skill}"
    if [[ ! -f "${skills_dir}/${skill}/SKILL.md" ]]; then
      local tmp; tmp=$(mktemp)
      cat > "$tmp" <<EOF2
# ${skill}

Use this Edge skill when it improves the task outcome.

Principles:
- Be project-neutral.
- Produce useful, auditable outputs.
- Prefer structured steps and clear deliverables.
- Do not store or expose secrets.
EOF2
      install -o "$AGENT_USER" -g "$AGENT_USER" -m 0644 "$tmp" "${skills_dir}/${skill}/SKILL.md"; rm -f "$tmp"
    fi
  done
  chown -R "${AGENT_USER}:${AGENT_USER}" "$skills_dir"
  ok "Edge Skills: $skills_dir"
}

install_commands(){
  step 8 "Команды запуска: ${AGENT}, ${AGENT}-update"
  cat > "/usr/local/bin/${AGENT}" <<EOF2
#!/usr/bin/env bash
set -euo pipefail
exec sudo -u "${AGENT_USER}" -H -- env -C "${AGENT_WORKSPACE}" "${AGENT_HOME}/.local/bin/claude" "\$@"
EOF2
  chmod 0755 "/usr/local/bin/${AGENT}"

  cat > "/usr/local/bin/${AGENT}-update" <<EOF2
#!/usr/bin/env bash
set -euo pipefail
sudo -u "${AGENT_USER}" -H -- git -C "${AGENT_REPO_DIR}" pull --ff-only || true
sudo -u "${AGENT_USER}" -H -- "${AGENT_HOME}/.local/bin/claude" update || true
if [[ -d "${AGENT_REPO_DIR}/skills" ]]; then
  rsync -a "${AGENT_REPO_DIR}/skills/" "${AGENT_WORKSPACE}/.claude/skills/"
fi
chown -R "${AGENT_USER}:${AGENT_USER}" "${AGENT_WORKSPACE}/.claude/skills" "${AGENT_REPO_DIR}" || true
EOF2
  chmod 0755 "/usr/local/bin/${AGENT}-update"
  ok "Команды установлены: ${AGENT}, ${AGENT}-update"
}

final_message(){
  cat <<EOF2

${C_GREEN}Агент ${AGENT_UPPER} установлен.${C_NC}

Дальше:
1) Логин Claude Code (один раз):
   sudo -u ${AGENT_USER} -H bash -lc '${AGENT_HOME}/.local/bin/claude login'

2) Запуск агента:
   ${AGENT}

3) Обновление:
   ${AGENT}-update

Пути:
- User:      ${AGENT_USER}
- Repo:      ${AGENT_REPO_DIR}
- Workspace: ${AGENT_WORKSPACE}
- Agent:     ${AGENT_WORKSPACE}/.claude/CLAUDE.md
- Skills:    ${AGENT_WORKSPACE}/.claude/skills

EOF2
}

main(){
  preflight
  install_base_dependencies
  install_node
  create_user
  install_claude_code
  clone_repo
  write_agent_prompt
  install_edge_skills
  install_commands
  final_message
}
main "$@"
