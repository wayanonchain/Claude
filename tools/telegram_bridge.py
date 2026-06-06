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
import queue
import re
import subprocess
import sys
import threading
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


def tg_send_document(chat_id, path, caption=""):
    # Отправка файла через multipart/form-data (без внешних зависимостей).
    fname = os.path.basename(path)
    with open(path, "rb") as fh:
        data = fh.read()
    boundary = "----tgbridge" + uuid.uuid4().hex
    nl = b"\r\n"
    body = b""
    body += b"--" + boundary.encode() + nl
    body += b'Content-Disposition: form-data; name="chat_id"' + nl + nl
    body += str(chat_id).encode() + nl
    if caption:
        body += b"--" + boundary.encode() + nl
        body += b'Content-Disposition: form-data; name="caption"' + nl + nl
        body += caption[:1000].encode() + nl
    body += b"--" + boundary.encode() + nl
    body += ('Content-Disposition: form-data; name="document"; filename="%s"' % fname).encode() + nl
    body += b"Content-Type: application/octet-stream" + nl + nl
    body += data + nl
    body += b"--" + boundary.encode() + b"--" + nl
    req = urllib.request.Request(f"{API}/sendDocument", data=body)
    req.add_header("Content-Type", "multipart/form-data; boundary=" + boundary)
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.load(r)


# Файлы для доставки: (1) пути, упомянутые агентом в ответе; (2) папка outbox/.
_PATH_RE = re.compile(r"/[\w./\-]+\.[A-Za-z0-9]{1,8}")
_MAX_FILE = 45 * 1024 * 1024  # лимит бота Telegram ~50МБ
OUTBOX = os.path.join(WORKSPACE, "outbox")


# Никогда не отправляем секреты, даже если агент упомянул их путь.
_SECRET_DIRS = ("/.ssh/", "/.config/", "/.claude/", "/.gnupg/", "/.aws/", "/.local/share/")
_SECRET_NAMES = {"telegram.env", "telegram-sessions.json", ".credentials.json",
                 ".claude.json", "id_rsa", "id_ed25519", ".env"}
_SECRET_EXT = (".env", ".key", ".pem", ".pfx", ".p12", ".crt")
_SECRET_WORDS = ("credential", "secret", "token", "password", "passwd", "private")


def _is_secret(rp):
    low = rp.lower()
    name = os.path.basename(low)
    if any(d in low for d in _SECRET_DIRS):
        return True
    if name in _SECRET_NAMES or os.path.basename(rp) in _SECRET_NAMES:
        return True
    if low.endswith(_SECRET_EXT):
        return True
    if any(w in name for w in _SECRET_WORDS):
        return True
    return False


def _safe_file(p):
    home = os.path.realpath(os.path.expanduser("~"))
    try:
        rp = os.path.realpath(p)
        if not (os.path.isfile(rp) and rp.startswith(home + os.sep)):
            return False
        if not (0 < os.path.getsize(rp) <= _MAX_FILE):
            return False
        if _is_secret(rp):
            log(f"ОТКАЗ слать секретный файл: {rp}")
            return False
        return True
    except OSError:
        return False


def collect_files(reply):
    found = []
    for m in _PATH_RE.findall(reply or ""):
        p = m.rstrip(".")
        if p not in found and _safe_file(p):
            found.append(p)
        if len(found) >= 5:
            break
    return found


def drain_outbox():
    # Файлы из outbox/ отправляем и переносим в outbox/sent/, чтобы не слать дважды.
    if not os.path.isdir(OUTBOX):
        return []
    sent_dir = os.path.join(OUTBOX, "sent")
    out = []
    for name in sorted(os.listdir(OUTBOX)):
        p = os.path.join(OUTBOX, name)
        if os.path.isfile(p) and _safe_file(p):
            out.append(p)
    return out


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


# --- очередь задач и воркер ---
# Главный цикл только принимает апдейты и мгновенно отвечает; тяжёлый вызов
# агента идёт в отдельном воркере, поэтому Telegram-бот всегда отзывчив, задачи
# не теряются и видна позиция в очереди.
JOBS = queue.Queue()


def typing_keepalive(chat_id, stop_event):
    # Индикатор «печатает…» живёт ~5с — обновляем, пока агент работает.
    while not stop_event.is_set():
        tg_typing(chat_id)
        stop_event.wait(4)


def worker():
    while True:
        chat_id, chat_key, text = JOBS.get()
        stop = threading.Event()
        t = threading.Thread(target=typing_keepalive, args=(chat_id, stop), daemon=True)
        t.start()
        started = time.time()
        try:
            reply = ask_claude(chat_key, text)
        except Exception as e:
            reply = f"⚠️ Внутренняя ошибка моста: {e}"
        finally:
            stop.set()
        took = int(time.time() - started)
        tg_send(chat_id, reply)
        # Доставляем файлы: упомянутые в ответе + из outbox/.
        files = collect_files(reply)
        outbox = drain_outbox()
        for p in outbox:
            if p not in files:
                files.append(p)
        sent_dir = os.path.join(OUTBOX, "sent")
        for p in files:
            try:
                tg_send_document(chat_id, p, caption=os.path.basename(p))
                log(f"отправлен файл: {p}")
                # перенос только для файлов из outbox
                if os.path.dirname(os.path.realpath(p)) == os.path.realpath(OUTBOX):
                    os.makedirs(sent_dir, exist_ok=True)
                    os.replace(p, os.path.join(sent_dir, os.path.basename(p)))
            except Exception as e:
                tg_send(chat_id, f"⚠️ Не смог отправить файл {os.path.basename(p)}: {e}")
        tg_send(chat_id, f"✅ Готово за {took}с." if took >= 5 else "✅ Готово.")
        JOBS.task_done()


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
            "/reset — начать новую сессию (забыть контекст).\n"
            "/queue — сколько задач в очереди.",
        )
        return
    if text == "/reset":
        SESSIONS.pop(chat_key, None)
        save_state(SESSIONS)
        tg_send(chat_id, "🔄 Контекст сброшен, начинаю новую сессию.")
        return
    if text == "/queue":
        n = JOBS.qsize()
        tg_send(chat_id, f"📋 В очереди задач: {n}." if n else "📋 Очередь пуста.")
        return

    log(f"[{AGENT}] от {user_id}: {text[:80]}")
    # Мгновенный ack + позиция в очереди, затем задача уходит воркеру.
    ahead = JOBS.qsize()
    if ahead == 0:
        tg_send(chat_id, "🔄 Принял задачу, работаю…")
    else:
        tg_send(chat_id, f"⏳ Принял. Передо мной ещё задач: {ahead}. Начну, как освобожусь.")
    JOBS.put((chat_id, chat_key, text))


def main():
    log(f"Telegram-мост для агента {AGENT.upper()} запущен. "
        f"Разрешено id: {sorted(ALLOWED)}; workspace={WORKSPACE}")
    if PERM_ARGS:
        log(f"Режим прав: {' '.join(PERM_ARGS)}")
    else:
        log("Режим прав: безопасный (только allowlist из settings.json)")
    threading.Thread(target=worker, daemon=True).start()
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
