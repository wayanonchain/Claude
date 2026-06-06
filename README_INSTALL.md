# Установка двухагентной системы JUPITER + URAN

Claude Code setup для `wayanonchain/Claude`. Каждый агент — свой Linux-пользователь,
рабочая папка `~/.claude-lab/<agent>/`, набор универсальных скиллов, отдельный
логин Claude и свои команды запуска. Архитектура — см.
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 1. Установка агентов

Имя агента задаёт пользователя, роль и команды. По имени роль определяется
автоматически: `jupiter`→operator (шлюз), остальные→executor (исполнитель).
Роль можно переопределить: `AGENT_ROLE=operator|executor`.

```bash
git clone https://github.com/wayanonchain/Claude.git
cd Claude

# Оператор-шлюз
sudo AGENT=jupiter bash install/install.sh

# Исполнитель
sudo AGENT=uran bash install/install.sh
```

Ставить из **локального** чекаута (без зависимости от GitHub, без риска получить
устаревший код):

```bash
sudo AGENT_REPO_SOURCE=local AGENT=uran bash install/install.sh
```

Уже стоящие агенты со старым layout `~/workspace` мигрируются автоматически
(копия в `~/.claude-lab/<agent>/`, старое не удаляется — проверь и удали сам).

## 2. Логин (по разу на агента) — ДО запуска сервисов

```bash
sudo -u jupiter -H bash -lc '/home/jupiter/.local/bin/claude login'
sudo -u uran    -H bash -lc '/home/uran/.local/bin/claude login'
```

## 3. Связка оператора и исполнителя

Даёт JUPITER право без пароля делегировать задачи URAN (узкое sudoers-правило):

```bash
sudo bash install/link-agents.sh                 # jupiter -> uran
# другой набор: sudo OPERATOR=jupiter EXECUTOR=uran bash install/link-agents.sh
# снять:        sudo bash install/link-agents.sh --unlink
```

После связки JUPITER делегирует:
`uran -p "<самодостаточная задача>" --output-format json`.

## 4. Запуск

```bash
jupiter      # оператор-шлюз
uran         # исполнитель напрямую
```

## 5. Обновление

```bash
jupiter-update
uran-update
```

`*-update` делает `git pull` (если репо git), `claude update`, синк скиллов и
**передеплой Telegram-моста** с рестартом сервиса (если мост установлен).

## 6. Telegram (один бот = один агент)

1. Создай бота у @BotFather (`/newbot`) — получишь токен.
2. Узнай свой Telegram user id у @userinfobot.
3. Поставь мост (нужен root):

```bash
sudo AGENT=jupiter bash install/telegram-install.sh
sudo AGENT=uran    bash install/telegram-install.sh
```

4. Впиши токен и id в конфиг (секрет, в git не попадает):

```bash
sudo -u jupiter nano /home/jupiter/.config/jupiter/telegram.env
sudo -u uran    nano /home/uran/.config/uran/telegram.env
```

5. Запусти сервисы (после `claude login`!):

```bash
sudo systemctl enable --now tg-jupiter
sudo systemctl enable --now tg-uran
sudo journalctl -u tg-jupiter -f   # логи
```

Доступ только для id из `TELEGRAM_ALLOWED_IDS`. По умолчанию режим прав
безопасный (агент использует только allowlist из `settings.json`). Для полной
автономии исполнителя поставь в `telegram.env`:
`CLAUDE_PERMISSION_ARGS=--dangerously-skip-permissions` (осознанно — это даёт боту
право выполнять любые инструменты на VPS).

## 7. Снятие Claude из-под root

```bash
sudo bash install/inspect-root-claude.sh           # read-only осмотр
sudo bash install/remove-root-claude.sh            # dry-run плана
sudo bash install/remove-root-claude.sh --yes      # бинарь + установка
sudo bash install/remove-root-claude.sh --yes --purge  # + конфиг и токены root
```

Удаление строго ограничено домашней папкой `root`, других агентов не трогает.

## 8. Удаление агента

По умолчанию данные пользователя (токен логина, telegram.env, рабочие файлы)
**сохраняются** — удаляются только команды, сервис и sudoers-связи:

```bash
sudo AGENT=uran bash install/uninstall.sh          # безопасно: home цел
sudo AGENT=uran bash install/uninstall.sh --purge  # ПОЛНОЕ: userdel -r (снесёт home и токены)
```
