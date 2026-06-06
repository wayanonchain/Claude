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

## Удаление агента

```bash
sudo JUPITER_USER=uran bash install/uninstall.sh
```
