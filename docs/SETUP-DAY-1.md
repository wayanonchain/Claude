# День 1 — два цифровых сотрудника на твоём VPS

> **Проект Wayan** · автор [@wayan_onchain](https://t.me/wayan_onchain)
> *«Тебе не нужно учиться промптить. Тебе нужно вернуть 14 часов в неделю.»*

За один вечер ты поднимаешь на чистом сервере **двух агентов**, которые работают
24/7 и слушаются тебя из Telegram с любого устройства — телефон, ноут, планшет.
Один и тот же git, одна и та же команда. Поставил раз — повторяешь где угодно.

```
                 ТЫ (Telegram, любой девайс)
                          │
                   ┌──────▼───────┐   бот #1
                   │   JUPITER    │   оператор: разбирает задачу,
                   │  оператор    │   решает сам или зовёт исполнителя
                   └──────┬───────┘
                          │  uran -p "<задача>"
                   ┌──────▼───────┐   бот #2
                   │     URAN     │   исполнитель: код, ресёрч,
                   │ исполнитель  │   документы, автоматизация
                   └──────────────┘
```

**JUPITER** — твой голос в системе: разговаривает, разбирает, поручает.
**URAN** — руки: делает тяжёлую работу в репозитории и не только.

---

## Что нужно

- **VPS** с чистой **Ubuntu 22.04 или 24.04**, доступ `root` (по SSH).
- **Подписка Anthropic** (Claude Code умеет логиниться под несколько агентов из одной подписки).
- **Telegram** + бот-токены от [@BotFather](https://t.me/BotFather) и твой user id от [@userinfobot](https://t.me/userinfobot).
- 15 минут.

> Принцип Wayan: **тишина = баг**. Ты всегда видишь, что делает агент. И **ничего
> в продакшен/клиенту/в бой — без твоего «ок»**.

---

## Шаг 0 — зайти на сервер

С любого девайса:

```bash
ssh root@TWOJ_IP
```

(или через Cursor / VS Code Remote-SSH — удобнее редактировать на ходу).

---

## Шаг 1 — поставить базу и клонировать твой git

```bash
apt-get update && apt-get install -y git
git clone https://github.com/wayanonchain/Claude.git
cd Claude
```

> Это **твой** репозиторий — вся логика агентов едет из него. Обновил репо →
> агенты обновились командой `<agent>-update`. Один источник правды.

---

## Шаг 2 — поставить JUPITER (оператор)

```bash
sudo AGENT=jupiter bash install/install.sh
```

Установщик сам: создаст пользователя `jupiter`, поставит Node + Claude Code,
развернёт рабочую папку `~/.claude-lab/jupiter/`, пропишет роль **оператора** и
права. Имя `jupiter` → роль operator определяется автоматически.

---

## Шаг 3 — поставить URAN (исполнитель)

```bash
sudo AGENT=uran bash install/install.sh
```

То же самое, но роль — **исполнитель** (полный набор инструментов: код, git,
python, файлы).

> Хочешь агента со своим именем? Роль задаётся явно:
> `sudo AGENT=max AGENT_ROLE=operator bash install/install.sh`

---

## Шаг 4 — логин (по разу на агента)

Каждый агент логинится в свою сессию Claude:

```bash
sudo -u jupiter -H bash -lc '/home/jupiter/.local/bin/claude login'
sudo -u uran    -H bash -lc '/home/uran/.local/bin/claude login'
```

Перейди по ссылке, подтверди — токен ляжет в `~/.claude/.credentials.json` агента.

---

## Шаг 5 — связать оператора и исполнителя

Чтобы JUPITER мог **поручать** задачи URAN:

```bash
sudo bash install/link-agents.sh
```

Это создаёт узкое правило sudoers (least-privilege): JUPITER может без пароля
запускать ровно одну команду исполнителя. Теперь JUPITER делегирует так:

```bash
uran -p "<самодостаточная задача со всем контекстом>" --output-format json
```

---

## Шаг 6 — Telegram-боты (один бот = один агент)

1. У [@BotFather](https://t.me/BotFather): `/newbot` → получи **два** токена (для JUPITER и URAN).
2. У [@userinfobot](https://t.me/userinfobot): узнай свой **Telegram user id**.
3. Поставь мост каждому агенту:

```bash
sudo AGENT=jupiter bash install/telegram-install.sh
sudo AGENT=uran    bash install/telegram-install.sh
```

4. Впиши токен и свой id (это секрет — в git НЕ попадает):

```bash
sudo -u jupiter nano /home/jupiter/.config/jupiter/telegram.env
sudo -u uran    nano /home/uran/.config/uran/telegram.env
```

В каждом файле:
```
TELEGRAM_BOT_TOKEN=123456:AA...      # свой токен
TELEGRAM_ALLOWED_IDS=123456789       # твой id (через запятую можно несколько)
```

5. Запусти ботов:

```bash
sudo systemctl enable --now tg-jupiter
sudo systemctl enable --now tg-uran
sudo journalctl -u tg-jupiter -f     # смотреть логи вживую
```

Теперь пиши боту в Telegram обычным текстом — агент на связи с любого устройства.

> **Режимы прав моста** (в `telegram.env`, переменная `CLAUDE_PERMISSION_ARGS`):
> - пусто = **безопасно** (только разрешённый allowlist) — норм для JUPITER;
> - `--dangerously-skip-permissions` = **полная автономия** (любые инструменты на
>   VPS) — осознанно, удобно для URAN-исполнителя.

---

## Шаг 7 — убрать root-Claude (гигиена)

root нужен только для установки. После — уберём Claude из-под root:

```bash
sudo bash install/inspect-root-claude.sh        # сначала посмотреть
sudo bash install/remove-root-claude.sh --yes   # убрать бинарь + установку
```

Чужие агенты это не трогает — только домашку `root`.

---

## Шаг 8 — проверка

```bash
# роли на месте
head -1 /home/jupiter/.claude-lab/jupiter/.claude/CLAUDE.md   # # JUPITER — operator & gateway
head -1 /home/uran/.claude-lab/uran/.claude/CLAUDE.md         # # URAN — executor

# делегирование работает
sudo -u jupiter -H jupiter -p "Передай URAN: ответь строкой PONG" --output-format json

# боты живы
systemctl is-active tg-jupiter tg-uran
```

Готово. Два сотрудника работают.

---

## С любого девайса — повторяемость

Вся система — в **твоём git**. Поэтому новый сервер поднимается теми же шагами:
`git clone` → `install.sh` (jupiter + uran) → login → `link-agents` → telegram.
Поменял логику в репо → на сервере:

```bash
jupiter-update     # подтянет репо, обновит Claude, скиллы и Telegram-мост
uran-update
```

Управление — из Telegram, откуда угодно. Сервер — один, девайсов — сколько хочешь.

---

## Обновление и удаление

```bash
jupiter-update / uran-update                     # обновить
sudo AGENT=uran bash install/uninstall.sh        # снять агента (данные целы)
sudo AGENT=uran bash install/uninstall.sh --purge # снять ПОЛНОСТЬЮ (удалит home и токены)
```

---

## Если что-то пошло не так

| Симптом | Причина / лечение |
|---|---|
| `apt` падает с `No module named 'apt_pkg'` | Системный `python3` подменён. Верни: `update-alternatives --set python3 /usr/bin/python3.10`. Текущий установщик системный python НЕ трогает. |
| Бот отвечает «Ошибка агента» на каждое сообщение | Агент не залогинен. Сделай `claude login` под пользователем агента (Шаг 4), затем `systemctl restart tg-<agent>`. |
| Бот «молчит» / не выполняет задачи | Безопасный режим прав. Для URAN поставь `CLAUDE_PERMISSION_ARGS=--dangerously-skip-permissions` в `telegram.env` и `systemctl restart tg-uran`. |
| JUPITER не может вызвать `uran` | Не выполнен `link-agents.sh`, либо в settings оператора нет `Bash(uran:*)`. |
| Длинная задача — бот «завис» | Мост однопоточный: пока идёт задача, другие сообщения ждут. Это ожидаемо. |

---

## Структура (что где живёт)

```
~/.claude/                       глобальные правила + settings + токен логина
~/.claude-lab/<agent>/.claude/   роль агента (CLAUDE.md), скиллы, память
~/.config/<agent>/               telegram.env (секрет), мост, сессии
~/Claude/                        чекаут твоего репозитория
/usr/local/bin/<agent>           запуск агента
/etc/sudoers.d/<op>-to-<ex>      право делегирования (узкое)
```

Подробно об архитектуре — [ARCHITECTURE.md](ARCHITECTURE.md).

---

> *© Wayan Onchain ([@wayan_onchain](https://t.me/wayan_onchain)), 2026.*
> Сохрани атрибуцию `wayan_onchain` при использовании.
