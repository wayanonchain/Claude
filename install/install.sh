#!/usr/bin/env bash
# Wayan Claude / JUPITER installer
# Repo: https://github.com/wayanonchain/Claude
# Target: clean Ubuntu 22.04 / 24.04 VPS
# Purpose: one project-neutral Edge Skills agent named JUPITER.

set -euo pipefail

INSTALL_VERSION="1.0.0"
JUPITER_USER="${JUPITER_USER:-jupiter}"
JUPITER_HOME="/home/${JUPITER_USER}"
JUPITER_REPO="${JUPITER_REPO:-https://github.com/wayanonchain/Claude.git}"
JUPITER_REPO_DIR="${JUPITER_REPO_DIR:-${JUPITER_HOME}/Claude}"
JUPITER_WORKSPACE="${JUPITER_WORKSPACE:-${JUPITER_HOME}/workspace}"
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
    tries=$((tries+1))
    [[ $tries -gt 20 ]] && die "apt/dpkg lock is held too long. Stop the other apt process and retry."
    sleep 3
  done
  DEBIAN_FRONTEND=noninteractive apt-get "$@"
}

as_jupiter(){ sudo -u "$JUPITER_USER" -H -- "$@"; }

preflight(){
  step 0 "Preflight"
  [[ $EUID -eq 0 ]] || die "Run as root: sudo bash install/install.sh"
  [[ -r /etc/os-release ]] || die "Cannot read /etc/os-release"
  . /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "Unsupported OS: ${ID:-unknown}. Use Ubuntu 22.04 or 24.04."
  case "${VERSION_ID:-}" in
    22.04|24.04) ok "Ubuntu ${VERSION_ID} detected" ;;
    *) [[ "${JUPITER_ALLOW_UNTESTED_UBUNTU:-0}" == "1" ]] || die "Untested Ubuntu ${VERSION_ID:-unknown}. Set JUPITER_ALLOW_UNTESTED_UBUNTU=1 to continue." ;;
  esac
}

install_base_dependencies(){
  step 1 "Installing base dependencies"
  apt_get update -qq
  apt_get install -y -qq ca-certificates gnupg lsb-release software-properties-common sudo curl wget git jq rsync build-essential cron logrotate nano unzip

  . /etc/os-release
  if [[ "${VERSION_ID:-}" == "22.04" ]]; then
    if ! command -v python3.12 >/dev/null 2>&1; then
      log "Adding deadsnakes PPA for Python 3.12"
      add-apt-repository -y ppa:deadsnakes/ppa >/dev/null
      apt_get update -qq
    fi
    apt_get install -y -qq python3.12 python3.12-venv python3.12-dev python3-pip
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 100 >/dev/null 2>&1 || true
    update-alternatives --set python3 /usr/bin/python3.12 >/dev/null 2>&1 || true
  else
    apt_get install -y -qq python3 python3-venv python3-pip python3-dev
  fi
  ok "Python ready: $(python3 --version 2>&1)"
}

install_node(){
  step 2 "Installing Node.js ${NODE_MAJOR}"
  if command -v node >/dev/null 2>&1; then
    local major
    major=$(node -v | sed -E 's/^v([0-9]+).*/\1/')
    if [[ "$major" == "$NODE_MAJOR" ]]; then
      ok "Node.js $(node -v) already installed"
      return
    fi
    warn "Existing Node.js $(node -v) is not v${NODE_MAJOR}; installing v${NODE_MAJOR}"
  fi
  curl "${CURL_OPTS[@]}" "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -
  apt_get install -y -qq nodejs
  ok "Node.js ready: $(node -v)"
}

create_user(){
  step 3 "Creating Linux user: ${JUPITER_USER}"
  if id -u "$JUPITER_USER" >/dev/null 2>&1; then
    ok "User ${JUPITER_USER} already exists"
  else
    useradd --create-home --shell /bin/bash "$JUPITER_USER"
    ok "User ${JUPITER_USER} created"
  fi
  chown "${JUPITER_USER}:${JUPITER_USER}" "$JUPITER_HOME"
  chmod 0755 "$JUPITER_HOME"
}

ensure_user_path(){
  local marker="# Added by JUPITER installer"
  local line='export PATH="$HOME/.local/bin:$PATH"'
  for rc in "${JUPITER_HOME}/.bashrc" "${JUPITER_HOME}/.profile"; do
    [[ -f "$rc" ]] || as_jupiter touch "$rc"
    if ! grep -Fq "$marker" "$rc" 2>/dev/null; then
      local tmp
      tmp=$(mktemp)
      { echo "$marker"; echo "$line"; echo; cat "$rc"; } > "$tmp"
      install -o "$JUPITER_USER" -g "$JUPITER_USER" -m 0644 "$tmp" "$rc"
      rm -f "$tmp"
    fi
  done
}

install_claude_code(){
  step 4 "Installing Claude Code CLI"
  local claude_bin="${JUPITER_HOME}/.local/bin/claude"
  if [[ -x "$claude_bin" ]]; then
    ok "Claude Code already installed: $claude_bin"
    as_jupiter "$claude_bin" update >/dev/null 2>&1 || warn "Claude update failed; continuing"
    ensure_user_path
    return
  fi
  local tmp
  tmp=$(mktemp)
  curl "${CURL_OPTS[@]}" https://claude.ai/install.sh -o "$tmp"
  chmod 0644 "$tmp"
  as_jupiter bash "$tmp"
  rm -f "$tmp"
  [[ -x "$claude_bin" ]] || die "Claude CLI not found after install: $claude_bin"
  ensure_user_path
  ok "Claude Code ready: $($claude_bin --version 2>/dev/null || echo installed)"
}

clone_repo(){
  step 5 "Cloning repository"
  if [[ -d "${JUPITER_REPO_DIR}/.git" ]]; then
    log "Repo already exists; pulling latest"
    as_jupiter git -C "$JUPITER_REPO_DIR" pull --ff-only || warn "git pull failed; keeping existing checkout"
  else
    as_jupiter git clone --depth 1 "$JUPITER_REPO" "$JUPITER_REPO_DIR"
  fi
  ok "Repo ready: ${JUPITER_REPO_DIR}"
}

write_jupiter_prompt(){
  step 6 "Configuring JUPITER agent"
  local claude_dir="${JUPITER_HOME}/.claude"
  local workspace_claude="${JUPITER_WORKSPACE}/.claude"

  install -d -m 0700 -o "$JUPITER_USER" -g "$JUPITER_USER" "$claude_dir"
  install -d -m 0755 -o "$JUPITER_USER" -g "$JUPITER_USER" \
    "$JUPITER_WORKSPACE" \
    "${JUPITER_WORKSPACE}/coding" \
    "${JUPITER_WORKSPACE}/research" \
    "${JUPITER_WORKSPACE}/content" \
    "${JUPITER_WORKSPACE}/reports" \
    "${JUPITER_WORKSPACE}/projects" \
    "${JUPITER_WORKSPACE}/logs" \
    "$workspace_claude" \
    "${workspace_claude}/skills" \
    "${workspace_claude}/memory"

  local template="${JUPITER_REPO_DIR}/templates/jupiter.md"
  if [[ -f "$template" ]]; then
    install -o "$JUPITER_USER" -g "$JUPITER_USER" -m 0644 "$template" "${workspace_claude}/CLAUDE.md"
  else
    cat > /tmp/jupiter-CLAUDE.md <<EOF2
# JUPITER

You are JUPITER.

Role:
- Edge Skills operator
- Research assistant
- Automation engineer
- Software engineering assistant
- Content creator

Primary user:
The operator

Operator profile:
- Name: ${OPERATOR_NAME}
- Preferred language: ${OPERATOR_LANGUAGE}
- Timezone: ${OPERATOR_TIMEZONE}

Objectives:
1. Find relevant information quickly.
2. Automate repetitive work.
3. Produce actionable research.
4. Create high-quality content.
5. Assist with software development.
6. Use Edge skills when they improve outcomes.
7. Remain project-neutral and reusable.

Operating rules:
- Use the repository at ${JUPITER_REPO_DIR} as the source of templates and skills.
- Keep secrets, API keys, tokens, passwords, private keys, and .env files out of git.
- Before destructive operations, show the exact command and explain the impact.
- Prefer small reversible changes.
- Use git status and git diff before committing.
- Never run broad cleanup commands from / or /home without explicit confirmation.
- Write concise operational summaries after completing tasks.

Default workspace:
${JUPITER_WORKSPACE}
EOF2
    install -o "$JUPITER_USER" -g "$JUPITER_USER" -m 0644 /tmp/jupiter-CLAUDE.md "${workspace_claude}/CLAUDE.md"
    rm -f /tmp/jupiter-CLAUDE.md
  fi

  cat > /tmp/jupiter-global.md <<EOF2
# Global Claude Rules for JUPITER

- Agent name: JUPITER
- Use project-neutral Edge Skills.
- Do not expose secrets.
- Ask before risky production actions.
- Keep changes auditable through git.
EOF2
  [[ -f "${claude_dir}/CLAUDE.md" ]] || install -o "$JUPITER_USER" -g "$JUPITER_USER" -m 0644 /tmp/jupiter-global.md "${claude_dir}/CLAUDE.md"
  rm -f /tmp/jupiter-global.md

  cat > /tmp/jupiter-settings.json <<'EOF2'
{
  "env": {
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  },
  "permissions": {
    "allow": [
      "Read",
      "Write",
      "Edit",
      "Bash(git:*)",
      "Bash(node:*)",
      "Bash(npm:*)",
      "Bash(python3:*)",
      "Bash(pip3:*)",
      "Bash(ls:*)",
      "Bash(cat:*)",
      "Bash(mkdir:*)",
      "Bash(cp:*)",
      "Bash(mv:*)",
      "Bash(find:*)",
      "Bash(grep:*)"
    ]
  }
}
EOF2
  [[ -f "${claude_dir}/settings.json" ]] || install -o "$JUPITER_USER" -g "$JUPITER_USER" -m 0644 /tmp/jupiter-settings.json "${claude_dir}/settings.json"
  rm -f /tmp/jupiter-settings.json

  chown -R "${JUPITER_USER}:${JUPITER_USER}" "$JUPITER_HOME"
  ok "JUPITER configured"
}

install_edge_skills(){
  step 7 "Installing Edge Skills"
  local skills_dir="${JUPITER_WORKSPACE}/.claude/skills"
  install -d -m 0755 -o "$JUPITER_USER" -g "$JUPITER_USER" "$skills_dir"

  if [[ -d "${JUPITER_REPO_DIR}/skills" ]]; then
    rsync -a "${JUPITER_REPO_DIR}/skills/" "$skills_dir/"
  fi

  local skill
  for skill in research code automation documentation content data-analysis web-analysis project-management x-thread-writer telegram-post-writer claude-code-developer; do
    install -d -m 0755 -o "$JUPITER_USER" -g "$JUPITER_USER" "${skills_dir}/${skill}"
    if [[ ! -f "${skills_dir}/${skill}/SKILL.md" ]]; then
      cat > "/tmp/${skill}-SKILL.md" <<EOF2
# ${skill}

Use this Edge skill when it improves the task outcome.

Principles:
- Be project-neutral.
- Produce useful, auditable outputs.
- Prefer structured steps and clear deliverables.
- Do not store or expose secrets.
EOF2
      install -o "$JUPITER_USER" -g "$JUPITER_USER" -m 0644 "/tmp/${skill}-SKILL.md" "${skills_dir}/${skill}/SKILL.md"
      rm -f "/tmp/${skill}-SKILL.md"
    fi
  done

  chown -R "${JUPITER_USER}:${JUPITER_USER}" "$skills_dir"
  ok "Edge Skills ready: $skills_dir"
}

install_commands(){
  step 8 "Installing command helpers"
  cat > /usr/local/bin/jupiter <<EOF2
#!/usr/bin/env bash
set -euo pipefail
cd "${JUPITER_WORKSPACE}"
exec sudo -u "${JUPITER_USER}" -H -- env -C "${JUPITER_WORKSPACE}" "${JUPITER_HOME}/.local/bin/claude" "\$@"
EOF2
  chmod 0755 /usr/local/bin/jupiter

  cat > /usr/local/bin/jupiter-update <<EOF2
#!/usr/bin/env bash
set -euo pipefail
sudo -u "${JUPITER_USER}" -H -- git -C "${JUPITER_REPO_DIR}" pull --ff-only || true
sudo -u "${JUPITER_USER}" -H -- "${JUPITER_HOME}/.local/bin/claude" update || true
if [[ -d "${JUPITER_REPO_DIR}/skills" ]]; then
  rsync -a "${JUPITER_REPO_DIR}/skills/" "${JUPITER_WORKSPACE}/.claude/skills/"
fi
chown -R "${JUPITER_USER}:${JUPITER_USER}" "${JUPITER_WORKSPACE}/.claude/skills" "${JUPITER_REPO_DIR}" || true
EOF2
  chmod 0755 /usr/local/bin/jupiter-update

  ok "Commands installed: jupiter, jupiter-update"
}

final_message(){
  cat <<EOF2

${C_GREEN}JUPITER installer finished.${C_NC}

Next:
1) Login Claude Code once:
   sudo -u ${JUPITER_USER} -H bash -lc '${JUPITER_HOME}/.local/bin/claude login'

2) Start the agent:
   jupiter

3) Update later:
   jupiter-update

Paths:
- User:      ${JUPITER_USER}
- Repo:      ${JUPITER_REPO_DIR}
- Workspace: ${JUPITER_WORKSPACE}
- Agent:     ${JUPITER_WORKSPACE}/.claude/CLAUDE.md
- Skills:    ${JUPITER_WORKSPACE}/.claude/skills

EOF2
}

main(){
  preflight
  install_base_dependencies
  install_node
  create_user
  install_claude_code
  clone_repo
  write_jupiter_prompt
  install_edge_skills
  install_commands
  final_message
}

main "$@"
