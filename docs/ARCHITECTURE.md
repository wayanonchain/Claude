# Архитектура — двухагентная система (EdgeLab Day-1 модель)

<!-- Часть проекта Wayan (автор: Wayan Onchain, @wayan_onchain) -->

Документ описывает целевую архитектуру репозитория: два универсальных цифровых
сотрудника на одном VPS.

## Соответствие EdgeLab Day-1

| EdgeLab Day-1 | Здесь |
|---|---|
| Jarvis — primary, Telegram gateway | **JUPITER** — оператор/шлюз/маршрутизация |
| Richard — исполнитель/резерв | **URAN** — исполнитель (код, research, документы, автоматизация) |
| root-Claude — только установка | `install/remove-root-claude.sh` после установки |
| Два независимых Telegram-бота | `tg-jupiter`, `tg-uran` (systemd) |
| Layout `~/.claude-lab/<agent>/` | то же |
| Узкие sudo-права (`sudoers.d`) | `install/link-agents.sh` |
| Идемпотентный установщик | `install/install.sh` |

## Агенты и роли

- **JUPITER (operator)** — единственная точка входа для человека. Разбирает задачу,
  решает: ответить/сделать самому или делегировать. Контролирует результат
  исполнителя и докладывает оператору. Шаблон: `templates/jupiter.md`.
- **URAN (executor)** — выполняет тяжёлую работу. Получает самодостаточные задачи
  от JUPITER (или от оператора напрямую). Шаблон: `templates/uran.md`.

Имя агента → роль по умолчанию: `jupiter`→operator, остальные→executor
(переопределяется `AGENT_ROLE=operator|executor`).

## Маршрутизация задач

```
JUPITER  ──►  uran -p "<задача>" --output-format json  ──►  URAN
   ▲                                                          │
   └────────────────  result (JSON.result)  ◄────────────────┘
```

Механика прав:

1. У каждого агента есть фиксированный helper `/usr/local/bin/<agent>-exec`
   (root-owned), запускающий `claude` агента в его workspace.
2. Команда `<agent>` = `sudo -u <agent> -- /usr/local/bin/<agent>-exec`.
3. `link-agents.sh` создаёт правило `/etc/sudoers.d/<op>-to-<ex>`:
   `<op> ALL=(<ex>) NOPASSWD: /usr/local/bin/<ex>-exec`.
4. JUPITER делегирует, запуская `uran` — sudo разрешён без пароля только на этот
   один helper, поэтому привилегия узкая.

JUPITER должен класть в промпт URAN весь нужный контекст: сессии не разделяются.

## Файловая модель

```
/home/<agent>/
├── .claude/
│   ├── CLAUDE.md            глобальные правила агента
│   ├── settings.json        права инструментов (operator ≠ executor)
│   └── .credentials.json    токен claude login (НЕ в git)
├── .claude-lab/<agent>/
│   └── .claude/
│       ├── CLAUDE.md        роль (operator/executor)
│       ├── skills/          универсальные скиллы (из repo/skills)
│       └── memory/
├── .config/<agent>/         (если включён Telegram)
│   ├── telegram.env         токен бота + whitelist (секрет, НЕ в git)
│   ├── telegram_bridge.py   развёрнутая копия моста
│   └── telegram-sessions.json
└── Claude/                  чекаут репозитория
```

## Telegram-мост

Один бот = один агент. `tools/telegram_bridge.py` (stdlib-only) принимает
сообщения от whitelist'а, гоняет их через `claude -p` с непрерывной сессией на
чат и возвращает ответ. Устанавливается как `tg-<agent>.service`
(`install/telegram-install.sh`).

Режимы прав моста (`CLAUDE_PERMISSION_ARGS` в `telegram.env`):

- **пусто (безопасно)** — агент использует только allowlist из `settings.json`.
  В headless всё вне allowlist автоотклоняется. Подходит для JUPITER.
- **`--dangerously-skip-permissions`** — полная автономия. Осознанно; подходит для
  URAN-исполнителя, которому нужен весь инструментарий на VPS.

> **Порядок важен:** сначала `claude login` под пользователем агента, потом
> `systemctl enable --now tg-<agent>`. Иначе каждый запрос вернёт ошибку агента.

## Известные ограничения

- **Мост однопоточный:** длинная задача (до `CLAUDE_TIMEOUT`, по умолчанию 300с)
  блокирует обработку других сообщений этого бота. Для параллелизма нужна очередь
  (не реализовано).
- **Деплой моста — копия:** обновляется при `<agent>-update` (передеплой +
  `systemctl try-restart`), но не при `git pull` вручную.

## Жизненный цикл

```
install.sh (root) ──► создаёт пользователя, ставит claude, разворачивает роль
       │
       ├─► claude login (под агентом)
       ├─► link-agents.sh (operator ↔ executor)
       ├─► telegram-install.sh (опц., per-agent бот)
       └─► remove-root-claude.sh (убрать root-Claude)

<agent>-update ──► git pull + claude update + sync skills + redeploy bridge
uninstall.sh ──► снять команды/сервис/sudoers (home по умолчанию цел; --purge сносит)
```

## Слои фреймворка и порядок загрузки

Помимо двух агентов, репозиторий организован как слои знаний. Порядок применения:

1. `GLOBAL.md` — поведение по умолчанию для всех агентов
2. `WORKSPACE.md` — контекст конкретного агента/проекта
3. `rules` — операционные границы
4. `skills/` — переиспользуемые навыки
5. `workflows/` — повторяемые процессы (coding / content / research)
6. `frameworks/` — модели мышления (first-principles, risk-analysis)
7. `blueprints/` — преднастройки под роль/кейс (operator, developer, creator, founder, researcher)
8. `examples/` — заполненные примеры

Слои `workflows/`, `frameworks/`, `blueprints/` — универсальные строительные блоки;
их подключают и JUPITER (при разборе задачи), и URAN (при исполнении).

---

> *© Wayan Onchain ([@wayan_onchain](https://t.me/wayan_onchain)), 2026.*
