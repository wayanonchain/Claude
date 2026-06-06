#!/usr/bin/env python3
"""Telegram <-> Claude Code bridge (один бот = один агент).

Принимает сообщения только от пользователей из белого списка, передаёт текст
агенту Claude в headless-режиме (claude -p) с непрерывной сессией на каждый чат
и возвращает ответ в Telegram. Без внешних зависимостей (только stdlib).

Конфиг — через переменные окружения (см. telegram.env.example):
  TELEGRAM_BOT_TOKEN      токен бота от @BotFather (секрет)
  TELEGRAM_ALLOWED_IDS    разрешённые Telegram user id, через запятую
  AGENT_NAME              метка агента (jupiter/uran), для логов и приветствия
  CLAUDE_BIN              путь к бинарю claude
  CLAUDE_WORKSPACE        рабочая папка, в которой запускается агент
  CLAUDE_PERMISSION_ARGS  доп. аргументы прав (по умолчанию пусто = безопасно).
                          Для полной автономии: "--dangerously-skip-permissions"
  STATE_FILE              файл с картой chat_id -> session_id
  CLAUDE_TIMEOUT          таймаут одного ответа агента, сек (по умолчанию 300)
"""
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
ALLOWED = {
    x.strip()
    for x in os.environ.get("TELEGRAM_ALLOWED_IDS", "").split(",")
    if x.strip()
}
AGENT = os.environ.get("AGENT_NAME", "agent").strip()
CLAUDE_BIN = os.environ.get("CLAUDE_BIN", "claude").strip()
WORKSPACE = os.environ.get("CLAUDE_WORKSPACE", os.getcwd()).strip()
PERM_ARGS = os.environ.get("CLAUDE_PERMISSION_ARGS", "").split()
STATE_FILE = os.environ.get("STATE_FILE", "").strip()
CLAUDE_TIMEOUT = int(os.environ.get("CLAUDE_TIMEOUT", "300"))

API = f"https://api.telegram.org/bot{TOKEN}"
TG_LIMIT = 4096


def die(msg):
    print(f"[FATAL] {msg}", file=sys.stderr)
    sys.exit(1)


if not TOKEN:
    die("TELEGRAM_BOT_TOKEN не задан")
if not ALLOWED:
    die("TELEGRAM_ALLOWED_IDS пуст — отказываюсь стартовать без белого списка")


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


# --- состояние сессий (chat_id -> session_id) ---
def load_state():
    if STATE_FILE and os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE) as f:
                return json.load(f)
        except Exception:
            return {}
    return {}


def save_state(state):
    if not STATE_FILE:
        return
    try:
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, STATE_FILE)
    except Exception as e:
        log(f"не смог сохранить state: {e}")


SESSIONS = load_state()


# --- Telegram API ---
def tg_call(method, params, timeout=60):
    data = urllib.parse.urlencode(params).encode()
    req = urllib.request.Request(f"{API}/{method}", data=data)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def tg_send(chat_id, text):
    # бьём длинные ответы на куски по лимиту Telegram
    if not text:
        text = "(пустой ответ)"
    for i in range(0, len(text), TG_LIMIT):
        chunk = text[i : i + TG_LIMIT]
        try:
            tg_call("sendMessage", {"chat_id": chat_id, "text": chunk})
        except Exception as e:
            log(f"sendMessage error: {e}")


def tg_typing(chat_id):
    try:
        tg_call("sendChatAction", {"chat_id": chat_id, "action": "typing"})
    except Exception:
        pass


# --- вызов агента ---
def _run_claude(prompt, sid, resume):
    args = [CLAUDE_BIN, "-p", prompt, "--output-format", "json"]
    args += ["--resume", sid] if resume else ["--session-id", sid]
    args += PERM_ARGS
    return subprocess.run(
        args, cwd=WORKSPACE, capture_output=True, text=True, timeout=CLAUDE_TIMEOUT,
    )


def _stale_session(proc):
    # claude не нашёл сохранённую сессию (напр. после смены workspace/миграции).
    blob = ((proc.stderr or "") + (proc.stdout or "")).lower()
    return ("no conversation found" in blob) or ("session id" in blob and "not found" in blob)


def ask_claude(chat_key, prompt):
    sid = SESSIONS.get(chat_key)
    resume = bool(sid)
    if not sid:
        sid = str(uuid.uuid4())
    try:
        proc = _run_claude(prompt, sid, resume)
        # Если возобновление сорвалось из-за пропавшей сессии — стартуем свежую.
        if proc.returncode != 0 and resume and _stale_session(proc):
            log(f"сессия {sid} не найдена — начинаю новую для chat={chat_key}")
            SESSIONS.pop(chat_key, None)
            sid = str(uuid.uuid4())
            resume = False
            proc = _run_claude(prompt, sid, resume)
    except subprocess.TimeoutExpired:
        return "⏱ Агент не ответил за отведённое время. Попробуй сузить запрос."
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()[:1500]
        return f"⚠️ Ошибка агента (код {proc.returncode}):\n{err}"
    out = (proc.stdout or "").strip()
    # пытаемся разобрать JSON; вытащить result и session_id
    try:
        obj = json.loads(out)
        result = obj.get("result") or obj.get("text") or out
        new_sid = obj.get("session_id") or sid
        SESSIONS[chat_key] = new_sid
        save_state(SESSIONS)
        return result
    except json.JSONDecodeError:
        SESSIONS[chat_key] = sid
        save_state(SESSIONS)
        return out or "(агент вернул пустой ответ)"


# --- обработка апдейтов ---
def handle(update):
    msg = update.get("message") or update.get("edited_message")
    if not msg:
        return
    chat_id = msg["chat"]["id"]
    user_id = str(msg.get("from", {}).get("id", ""))
    text = (msg.get("text") or "").strip()
    if not text:
        return

    if user_id not in ALLOWED:
        log(f"ОТКАЗ неразрешённому user_id={user_id} (chat={chat_id})")
        tg_send(chat_id, "⛔ Доступ запрещён.")
        return

    chat_key = str(chat_id)

    if text in ("/start", "/help"):
        tg_send(
            chat_id,
            f"🤖 Агент {AGENT.upper()} на связи.\n"
            "Пиши задачу обычным текстом.\n"
            "/reset — начать новую сессию (забыть контекст).",
        )
        return
    if text == "/reset":
        SESSIONS.pop(chat_key, None)
        save_state(SESSIONS)
        tg_send(chat_id, "🔄 Контекст сброшен, начинаю новую сессию.")
        return

    log(f"[{AGENT}] от {user_id}: {text[:80]}")
    tg_typing(chat_id)
    reply = ask_claude(chat_key, text)
    tg_send(chat_id, reply)


def main():
    log(f"Telegram-мост для агента {AGENT.upper()} запущен. "
        f"Разрешено id: {sorted(ALLOWED)}; workspace={WORKSPACE}")
    if PERM_ARGS:
        log(f"Режим прав: {' '.join(PERM_ARGS)}")
    else:
        log("Режим прав: безопасный (только allowlist из settings.json)")
    offset = None
    while True:
        try:
            params = {"timeout": 50}
            if offset is not None:
                params["offset"] = offset
            resp = tg_call("getUpdates", params, timeout=60)
        except urllib.error.URLError as e:
            log(f"getUpdates сеть: {e}; пауза 5с")
            time.sleep(5)
            continue
        except Exception as e:
            log(f"getUpdates ошибка: {e}; пауза 5с")
            time.sleep(5)
            continue

        if not resp.get("ok"):
            log(f"Telegram вернул not ok: {resp}")
            time.sleep(5)
            continue

        for upd in resp.get("result", []):
            offset = upd["update_id"] + 1
            try:
                handle(upd)
            except Exception as e:
                log(f"handle ошибка: {e}")


if __name__ == "__main__":
    main()
