# Claude — двухагентная система цифровых сотрудников от wayan_onchain

> **Автор и владелец:** Wayan Onchain ([@wayan_onchain](https://t.me/wayan_onchain))
> **Версия:** 2.0 (июнь 2026)
> **Лицензия:** MIT

Универсальный, **проектно-нейтральный** фреймворк для запуска Claude Code как пары
цифровых сотрудников на одном VPS. Архитектура по образцу **EdgeLab Day-1**:
один оператор-шлюз и один исполнитель, два независимых Telegram-бота, установка
из-под временного root с последующей его зачисткой.

Это не узкоспециализированные роли под одну нишу, а **универсальная система**:
исследования, код, документы, автоматизация — что угодно, чему можно поручить
агента.

---

## Двухагентная архитектура

```
                    Оператор (ты) — Telegram
                            │
                     ┌──────▼───────┐   бот #1 (tg-jupiter)
                     │   JUPITER    │   роль: operator
                     │ оператор /   │   диалог, разбор задачи,
                     │   шлюз       │   маршрутизация
                     └──────┬───────┘
                            │  uran -p "<задача>"
                     ┌──────▼───────┐   бот #2 (tg-uran)
                     │     URAN     │   роль: executor
                     │ исполнитель  │   код, исследования,
                     │              │   документы, автоматизация
                     └──────────────┘
```

| Агент | Роль | Делает |
|---|---|---|
| **JUPITER** | оператор / шлюз | разговаривает с тобой, разбирает задачу, решает — сделать самому или передать URAN, контролирует результат, докладывает |
| **URAN** | исполнитель | пишет код, работает с репозиторием, исследует, готовит документы, автоматизирует |

**Маршрутизация:** JUPITER делегирует исполнение командой
`uran -p "<самодостаточная задача>" --output-format json`. Право даётся узким
правилом sudoers (`install/link-agents.sh`) — модель least-privilege EdgeLab.

**root-Claude** используется только для установки и убирается после неё
(`install/remove-root-claude.sh`).

---

## Двухуровневая конфигурация

```
~/                                   (на каждого агента — свой Linux-пользователь)
├── .claude/
│   ├── CLAUDE.md                    <- ГЛОБАЛЬНЫЙ: общая «конституция» агента
│   └── settings.json               <- права инструментов (по роли)
│
└── .claude-lab/<agent>/
    └── .claude/
        ├── CLAUDE.md               <- РАБОЧИЙ: роль агента (operator / executor)
        ├── skills/                 <- универсальные скиллы
        └── memory/
```

- **Глобальный `~/.claude/CLAUDE.md`** — применяется ко всем сессиям агента:
  идентификация, безопасность, базовые принципы.
- **Рабочий `.claude-lab/<agent>/.claude/CLAUDE.md`** — должностная инструкция
  конкретного агента (роль, стиль, координация).

---

## Быстрый старт

```bash
git clone https://github.com/wayanonchain/Claude.git
cd Claude

# 1) Оператор-шлюз
sudo AGENT=jupiter bash install/install.sh

# 2) Исполнитель
sudo AGENT=uran bash install/install.sh

# 3) Логин Claude (по разу на агента)
sudo -u jupiter -H bash -lc '/home/jupiter/.local/bin/claude login'
sudo -u uran    -H bash -lc '/home/uran/.local/bin/claude login'

# 4) Дать JUPITER право делегировать URAN
sudo bash install/link-agents.sh

# 5) Запуск
jupiter        # оператор
uran           # исполнитель напрямую
```

📘 **Детальный гайд с нуля (как поднять своих агентов с любого девайса):**
[docs/SETUP-DAY-1.md](docs/SETUP-DAY-1.md).

Краткая инструкция (Telegram, обновления, удаление, чистка root) —
[README_INSTALL.md](README_INSTALL.md). Архитектура подробно —
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Шаблоны и примеры

| Файл | Назначение |
|---|---|
| [templates/jupiter.md](templates/jupiter.md) | Роль оператора/шлюза (operator) |
| [templates/uran.md](templates/uran.md) | Роль исполнителя (executor) |
| [templates/global-claude.md](templates/global-claude.md) | Глобальный CLAUDE.md |
| [templates/rules.md](templates/rules.md) | Операционные правила |
| [templates/user.md](templates/user.md) | Профиль оператора |
| [examples/jupiter-operator.md](examples/jupiter-operator.md) | Заполненный пример оператора |
| [examples/uran-executor.md](examples/uran-executor.md) | Заполненный пример исполнителя |

## Скиллы (универсальные)

| Скилл | Описание |
|---|---|
| [skills/onboarding](skills/onboarding/) | Пост-установочный онбординг: агент знакомится с тобой и заполняет CLAUDE.md через диалог |
| [skills/self-compiler](skills/self-compiler/) | Компилятор знаний: разговор → структурированные файлы (profile, goals, stack, rules) |
| [skills/present](skills/present/) | HTML-визуализация в стиле Notion (light/dark, zero dependencies) |

---

## Принципы

1. **Приоритет правил:** Безопасность > Указание оператора > Проверка фактов > Границы > Стиль.
2. **Тишина = баг.** Оператор всегда видит, что делает агент.
3. **Обучение → система.** Ошибка становится правилом/хуком/Routine, а не записью в памяти.
4. **Доверяй, но проверяй.** Реальная проверка (exec, тесты, diff) > локальная память.
5. **Экономия токенов.** Внутренние файлы на английском, авто-компакт 400K.
6. **Один оператор — два специалиста.** Шлюз разбирает, исполнитель делает.

---

## Что в архиве

Коммерческий курсовой слой (треки PRO/BIZ, non-tech, нишевые скиллы) вынесен в
[archive/](archive/) — он сохранён, но не входит в универсальную систему.
См. [archive/README.md](archive/README.md).

---

## Авторство и лицензия

- **Автор:** Wayan Onchain ([@wayan_onchain](https://t.me/wayan_onchain)), 2026.
- **Лицензия:** MIT (см. [LICENSE](LICENSE)).

При использовании материалов сохрани атрибуцию `wayan_onchain`.

---

> *«Тебе не нужно учиться промптить. Тебе нужно вернуть 14 часов в неделю.»* — wayan_onchain
