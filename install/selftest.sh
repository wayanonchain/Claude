#!/usr/bin/env bash
# Самопроверка двухагентной установки на одноразовой паре demoop/demoex.
# Боевые агенты (jupiter/uran/edgelab) НЕ затрагиваются. В конце всё удаляется.
#
#   sudo bash install/selftest.sh
#
# Не используем set -e: хотим выполнить ВСЕ проверки и в конце показать итог.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SELF_DIR}/.." && pwd)"
export AGENT_REPO_SOURCE=local
LOG=/tmp/selftest-install.log
: > "$LOG"

OP=demoop
EX=demoex

PASS=0; FAIL=0
chk(){ # chk "описание" "ожидаемое" "фактическое"
  if [[ "$2" == "$3" ]]; then printf '  [PASS] %-34s = %s\n' "$1" "$3"; PASS=$((PASS+1))
  else printf '  [FAIL] %-34s ожид=%s факт=%s\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}
contains(){ # contains "описание" "подстрока" "строка"
  if [[ "$3" == *"$2"* ]]; then printf '  [PASS] %-34s содержит %s\n' "$1" "$2"; PASS=$((PASS+1))
  else printf '  [FAIL] %-34s НЕ содержит %s (факт: %s)\n' "$1" "$2" "$3"; FAIL=$((FAIL+1)); fi
}

[[ $EUID -eq 0 ]] || { echo "Запусти под root: sudo bash install/selftest.sh"; exit 1; }

PY_BEFORE="$(python3 --version 2>&1)"

echo "### Установка ${OP} (operator) ###"
if AGENT="$OP" bash "$REPO/install/install.sh" >>"$LOG" 2>&1; then echo "  установлен"; else echo "  ОШИБКА — хвост лога:"; tail -25 "$LOG"; fi

echo "### Установка ${EX} (executor) ###"
if AGENT="$EX" bash "$REPO/install/install.sh" >>"$LOG" 2>&1; then echo "  установлен"; else echo "  ОШИБКА — хвост лога:"; tail -25 "$LOG"; fi

echo "### Связка ${OP} -> ${EX} ###"
OPERATOR="$OP" EXECUTOR="$EX" bash "$REPO/install/link-agents.sh" >>"$LOG" 2>&1 && echo "  связано" || { echo "  ОШИБКА link — хвост лога:"; tail -15 "$LOG"; }

echo
echo "### ПРОВЕРКИ ###"
OP_CLAUDE="/home/${OP}/.claude-lab/${OP}/.claude/CLAUDE.md"
EX_CLAUDE="/home/${EX}/.claude-lab/${EX}/.claude/CLAUDE.md"

chk ".claude-lab layout operator" "yes" "$([[ -f "$OP_CLAUDE" ]] && echo yes || echo no)"
chk ".claude-lab layout executor" "yes" "$([[ -f "$EX_CLAUDE" ]] && echo yes || echo no)"
contains "роль operator (заголовок)" "operator" "$([[ -f "$OP_CLAUDE" ]] && head -1 "$OP_CLAUDE")"
contains "роль executor (заголовок)" "executor" "$([[ -f "$EX_CLAUDE" ]] && head -1 "$EX_CLAUDE")"

for c in "$OP" "$EX" "${OP}-exec" "${EX}-exec" "${OP}-update" "${EX}-update"; do
  chk "команда /usr/local/bin/$c" "yes" "$([[ -x "/usr/local/bin/$c" ]] && echo yes || echo no)"
done

SUDOERS="/etc/sudoers.d/${OP}-to-${EX}"
chk "sudoers-файл существует" "yes" "$([[ -f "$SUDOERS" ]] && echo yes || echo no)"
contains "sudoers-правило" "${OP} ALL=(${EX}) NOPASSWD: /usr/local/bin/${EX}-exec" "$([[ -f "$SUDOERS" ]] && cat "$SUDOERS")"
chk "sudoers валиден (visudo)" "yes" "$(visudo -cf "$SUDOERS" >/dev/null 2>&1 && echo yes || echo no)"

contains "operator settings: делегирование" "Bash(uran:*)" "$(cat "/home/${OP}/.claude/settings.json" 2>/dev/null)"

PY_AFTER="$(python3 --version 2>&1)"
chk "системный python3 не изменён" "$PY_BEFORE" "$PY_AFTER"
chk "apt_pkg цел (apt не сломан)" "ok" "$(python3 -c 'import apt_pkg; print("ok")' 2>/dev/null || echo broken)"

echo
echo "### ОЧИСТКА ###"
echo YES | AGENT="$OP" bash "$REPO/install/uninstall.sh" --purge >>"$LOG" 2>&1
echo YES | AGENT="$EX" bash "$REPO/install/uninstall.sh" --purge >>"$LOG" 2>&1
chk "пользователь ${OP} удалён" "no"  "$(id "$OP" >/dev/null 2>&1 && echo yes || echo no)"
chk "пользователь ${EX} удалён" "no"  "$(id "$EX" >/dev/null 2>&1 && echo yes || echo no)"
chk "команда ${OP} удалена"    "no"  "$([[ -e "/usr/local/bin/$OP" ]] && echo yes || echo no)"
chk "sudoers-файл удалён"      "no"  "$([[ -e "$SUDOERS" ]] && echo yes || echo no)"

echo
echo "### ИТОГ: PASS=${PASS} FAIL=${FAIL} (полный лог: ${LOG}) ###"
[[ "$FAIL" -eq 0 ]] && echo "### РЕЗУЛЬТАТ: OK ###" || echo "### РЕЗУЛЬТАТ: ЕСТЬ ОШИБКИ ###"
