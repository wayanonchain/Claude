# JUPITER / multi-agent installer

Claude Code setup for `wayanonchain/Claude`. Поддерживает несколько агентов
(например `jupiter` и `uran`) — у каждого свой Linux-пользователь, workspace,
набор Edge Skills, отдельный логин Claude и свои команды запуска.

## Установка агента

Универсальный установщик. Имя агента задаёт пользователя и команды запуска:

```bash
git clone https://github.com/wayanonchain/Claude.git
cd Claude

# первый агент
sudo AGENT=jupiter bash install/agent-install.sh

# второй агент (полный близнец)
sudo AGENT=uran bash install/agent-install.sh
```

(Старый `install/install.sh` ставит только одного `jupiter` и оставлен для
совместимости. Новый `agent-install.sh` — рекомендуемый путь.)

## Логин (по одному разу на агента)

```bash
sudo -u jupiter -H bash -lc '/home/jupiter/.local/bin/claude login'
sudo -u uran    -H bash -lc '/home/uran/.local/bin/claude login'
```

## Запуск

```bash
jupiter      # запустить агента JUPITER
uran         # запустить агента URAN
```

## Обновление

```bash
jupiter-update
uran-update
```

## Снятие Claude из-под root

На VPS Claude иногда оказывается установлен под `root`. Осмотреть и убрать:

```bash
# read-only осмотр
sudo bash install/inspect-root-claude.sh

# dry-run плана удаления
sudo bash install/remove-root-claude.sh

# применить: бинарь + установка
sudo bash install/remove-root-claude.sh --yes

# полная чистка: + конфиг и токены логина (~/.claude)
sudo bash install/remove-root-claude.sh --yes --purge
```

Удаление строго ограничено домашней папкой `root` и не трогает других агентов.

## Общение через Telegram (один бот = один агент)

1. Создай бота у @BotFather (`/newbot`) — получишь токен.
2. Узнай свой Telegram user id у @userinfobot.
3. Поставь мост для агента (нужен root):

```bash
sudo AGENT=jupiter bash install/telegram-install.sh
sudo AGENT=uran    bash install/telegram-install.sh
```

4. Впиши токен и свой id в конфиг (секрет, в git не попадает):

```bash
sudo -u jupiter nano /home/jupiter/.config/jupiter/telegram.env
sudo -u uran    nano /home/uran/.config/uran/telegram.env
```

5. Запусти сервисы:

```bash
sudo systemctl enable --now tg-jupiter
sudo systemctl enable --now tg-uran
sudo journalctl -u tg-jupiter -f   # логи
```

Доступ только для id из `TELEGRAM_ALLOWED_IDS`. По умолчанию режим прав
безопасный (агент использует только allowlist из `settings.json`); для полной
автономии в `telegram.env` поставь `CLAUDE_PERMISSION_ARGS=--dangerously-skip-permissions`
(осознанно — это даёт боту право выполнять любые инструменты на VPS).

## Удаление агента

```bash
sudo JUPITER_USER=uran bash install/uninstall.sh
```
