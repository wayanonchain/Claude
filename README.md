# Claude -- авторский фреймворк настройки Claude-агентов от wayan_onchain

> **Автор и владелец курса:** Wayan Onchain (@wayan_onchain)
> **Версия:** 1.0 (май 2026)
> **Лицензия:** MIT

Полный курс и репозиторий шаблонов для настройки Claude Code как полноценного
цифрового сотрудника. Авторская методология wayan_onchain, заточенная под
**массовую русскоязычную аудиторию вне крипты**: маркетологов, SMM, копирайтеров,
владельцев малого бизнеса. Плюс отдельный бонус-трек для разработчиков.

Якорный нарратив тяжёлого продукта (CLAUDE BIZ): [Claude for Small Business](https://shazoo.ru/2026/05/14/183978/anthropic-zapustila-claude-for-small-business-15-gotovykh-stsenariev-i-integratsiia-so-storonnimi-sistemami)
от Anthropic, релиз 14 мая 2026.

---

## Зачем тебе CLAUDE.md

CLAUDE.md -- главный конфигурационный файл Claude Code. Это не «промпт» и не
«инструкция». Это **конституция**, по которой агент принимает решения, расставляет
приоритеты и определяет, что ему можно, а что нельзя без твоего разрешения.

Без CLAUDE.md ты получаешь дорогой чат-бот.
С грамотно настроенным CLAUDE.md -- сотрудника, который:

- знает кто ты, в каком часовом поясе работаешь и как к тебе обращаться
- молчит, пока ты не дал триггер; и говорит до того, как ты успел спросить
- сам себя проверяет на ошибки до того, как покажет тебе результат
- никогда не публикует ничего клиенту / в боевую соцсеть / в продакшен без твоего «ок»

Для **маркетолога** грамотный CLAUDE.md = агент, который пишет твоим голосом, а не «как все».
Для **предпринимателя** = агент, который заменяет 5 операционных ролей одним пайплайном.
Для **разработчика** = агент, который не запушит в main и не удалит .next на проде.

---

## Три трека курса wayan_onchain

| Трек | Кому | Чек | Что получаешь |
|---|---|---|---|
| **CLAUDE PRO** | маркетологи, SMM, копирайтеры, контент-мейкеры | 4 990 / 14 990 / 39 990 ₽ | возврат 10--15 часов в неделю, голос бренда в Project, контент-конвейер на 30+ постов/мес без потери качества |
| **CLAUDE BIZ** | владельцы малого бизнеса, SMB-фаундеры | 24 990 / 79 990 / 249 990 ₽ | один агент = 5 ролей (маркетинг + продажи + клиент-сервис + отчёты + документы), ночные Routines, окупаемость 1--2 мес |
| **CLAUDE DEV** (бонус) | разработчики, ML-инженеры | по запросу | мультиагентные системы, координатор + кодеры, продакшен-сетап |

Все три трека -- одна и та же структура CLAUDE.md из этого репо.
Меняются примеры, скиллы и роли агентов.

---

## Двухуровневая архитектура wayan_onchain

```
~/
├── .claude/
│   ├── CLAUDE.md              <- ГЛОБАЛЬНЫЙ (применяется ко всем агентам на машине)
│   └── rules/
│       ├── voice.md           <- голос бренда (PRO)
│       ├── smb-stack.md       <- бизнес-стек (BIZ)
│       └── python.md          <- стиль кода (DEV)
│
└── .claude-lab/
    └── agent-1/
        └── .claude/
            ├── CLAUDE.md      <- РАБОЧИЙ (для одного конкретного агента)
            ├── core/
            │   ├── USER.md
            │   ├── rules.md
            │   ├── warm/decisions.md
            │   └── hot/handoff.md
            └── tools/TOOLS.md
```

### Глобальный (`~/.claude/CLAUDE.md`) -- «конституция»

Применяется ко **всем** твоим Claude-агентам. Содержит идентификацию оператора,
языковые правила, зоны автономии, принципы безопасности, 9 рабочих принципов.

### Рабочий (`.claude/CLAUDE.md`) -- «трудовой договор»

Должностная инструкция конкретного агента. Содержит роль (SOUL), характер, стиль
общения, память, координацию с другими агентами.

---

## Гайды

| Файл | Содержание | Кому |
|---|---|---|
| [GLOBAL.md](GLOBAL.md) | Как заполнить глобальный CLAUDE.md | универсально |
| [WORKSPACE.md](WORKSPACE.md) | Как заполнить рабочий CLAUDE.md | универсально |
| [GLOBAL-NONTECH.md](GLOBAL-NONTECH.md) | То же, но **без git/CI/деплоя/кода** | маркетологи, SMB |
| [WORKSPACE-NONTECH.md](WORKSPACE-NONTECH.md) | Должностная инструкция для контент-агента и SMB-оркестратора | маркетологи, SMB |
| [COURSE.md](COURSE.md) | Структура двух платных продуктов: CLAUDE PRO и CLAUDE BIZ | для партнёров |

---

## Шаблоны

Готовые шаблоны с `{{ПЛЕЙСХОЛДЕРАМИ}}` -- копируй и заполняй:

### Tech-трек (разработчики)

| Файл | Назначение |
|---|---|
| [templates/global-claude.md](templates/global-claude.md) | Глобальный CLAUDE.md |
| [templates/workspace-claude.md](templates/workspace-claude.md) | Рабочий CLAUDE.md |
| [templates/rules.md](templates/rules.md) | Операционные правила |
| [templates/user.md](templates/user.md) | Профиль оператора |

### Non-tech-трек (маркетологи и предприниматели)

| Файл | Назначение |
|---|---|
| [templates/global-claude-nontech.md](templates/global-claude-nontech.md) | Глобальный CLAUDE.md без кодерской терминологии |
| [templates/workspace-pro.md](templates/workspace-pro.md) | Рабочий CLAUDE.md для контент-агента (CLAUDE PRO) |
| [templates/workspace-biz.md](templates/workspace-biz.md) | Рабочий CLAUDE.md для SMB-оркестратора (CLAUDE BIZ) |
| [templates/rules-nontech.md](templates/rules-nontech.md) | Операционные правила без git/деплоя |
| [templates/user-nontech.md](templates/user-nontech.md) | Профиль оператора-непрограммиста |

---

## Примеры (заполненные CLAUDE.md)

Три вымышленных героя курса wayan_onchain:

| Файл | Герой | Трек |
|---|---|---|
| [examples/dev-orchestrator-filled.md](examples/dev-orchestrator-filled.md) | **Дима**, фуллстек-разработчик, координатор + кодер на одном VPS | **DEV** |
| [examples/dev-coordinator-workspace.md](examples/dev-coordinator-workspace.md) | **Дима**, рабочий CLAUDE.md его агента-координатора | **DEV** |
| [examples/marketer-pro-filled.md](examples/marketer-pro-filled.md) | **Маша**, SMM-менеджер агентства, контент-агент с голосом бренда | **PRO** |
| [examples/smb-biz-filled.md](examples/smb-biz-filled.md) | **Артём**, владелец онлайн-школы, мульти-роль агент (5 ролей в одном) | **BIZ** |

---

## Скиллы

Готовые навыки для агентов -- устанавливай и используй:

| Скилл | Описание | Трек |
|---|---|---|
| [skills/present](skills/present/) | HTML-визуализация в стиле Notion (light/dark, zero dependencies) | универсально |
| [skills/onboarding](skills/onboarding/) | Пост-установочный онбординг: агент знакомится с тобой и заполняет CLAUDE.md через диалог | универсально |
| [skills/self-compiler](skills/self-compiler/) | Компилятор знаний: переводит разговор в структурированные файлы (profile, goals, stack, rules) | универсально |
| [skills/brand-voice](skills/brand-voice/) | Настройка голоса бренда: few-shot из прошлых текстов -> Project, агент пишет твоим голосом | **PRO** |
| [skills/smb-orchestra](skills/smb-orchestra/) | Оркестратор SMB-ролей: координатор + 5 специалистов (маркетинг / продажи / клиент-сервис / отчёты / документы) | **BIZ** |

---

## Семь паттернов wayan_onchain

1. **Приоритет правил:** Безопасность > Указание оператора > Проверка фактов > Границы > Стиль
2. **Тишина = баг.** Оператор всегда должен видеть, что делает агент
3. **Обучение -> система.** Ошибка должна становиться системным изменением (правилом, хуком, Routine), а не записью в памяти
4. **Brand Native** (PRO -- голос бренда в Project как single source of truth) и **Owner Native** (BIZ -- агент знает твой стек, клиента, поставщика)
5. **Доверяй, но проверяй.** CRM / база данных / реальная проверка > локальная память агента
6. **Экономия токенов.** Внутренние файлы на английском (экономия 50--60% токенов на @includes), максимум 4 @includes, авто-компакт 400K
7. **Возврат времени, а не «промптинг».** Цель агента -- освободить тебе 10--15 часов в неделю, а не научить «правильно писать промпт»

---

## С чего начать

### Если ты маркетолог / SMM / копирайтер (CLAUDE PRO)

1. Прочитай [GLOBAL-NONTECH.md](GLOBAL-NONTECH.md)
2. Скопируй [templates/global-claude-nontech.md](templates/global-claude-nontech.md) в `~/.claude/CLAUDE.md`, заполни плейсхолдеры
3. Открой [examples/marketer-pro-filled.md](examples/marketer-pro-filled.md) -- увидишь, как это выглядит у Маши
4. Установи скилл [brand-voice](skills/brand-voice/) и настрой Project с твоими прошлыми текстами

### Если ты владелец малого бизнеса (CLAUDE BIZ)

1. Прочитай [GLOBAL-NONTECH.md](GLOBAL-NONTECH.md) и [WORKSPACE-NONTECH.md](WORKSPACE-NONTECH.md)
2. Скопируй [templates/workspace-biz.md](templates/workspace-biz.md), заполни блоки про твой стек
3. Открой [examples/smb-biz-filled.md](examples/smb-biz-filled.md) -- как Артём собрал оркестратор из 5 агентов
4. Установи [smb-orchestra](skills/smb-orchestra/) -- готовый координатор + 5 специалистов

### Если ты разработчик (CLAUDE DEV)

1. Прочитай [GLOBAL.md](GLOBAL.md) и [WORKSPACE.md](WORKSPACE.md)
2. Скопируй [templates/global-claude.md](templates/global-claude.md) и [templates/workspace-claude.md](templates/workspace-claude.md)
3. Открой [examples/dev-orchestrator-filled.md](examples/dev-orchestrator-filled.md)

---

## Контакты

- [@wayan_onchain](https://t.me/wayan_onchain) -- канал автора курса
- [Claude for Small Business](https://shazoo.ru/2026/05/14/183978/) -- внешний нарратив-якорь для BIZ-трека

---

## Авторство и лицензия

- **Автор:** Wayan Onchain ([@wayan_onchain](https://t.me/wayan_onchain)), 2026
- **Лицензия:** MIT (см. [LICENSE](LICENSE))

При использовании материалов курса сохрани атрибуцию `wayan_onchain`.

---

> *«Тебе не нужно учиться промптить. Тебе нужно вернуть 14 часов в неделю.»* -- wayan_onchain
