# Nexus Node Installer

Автоматический установщик ноды Nexus для Linux серверов.

## Установка

```bash
curl -sSL https://raw.githubusercontent.com/titbm/nexus-node-installer/main/nexus-install.sh | bash
```

## Системные требования

- Ubuntu 24.04+ (обязательно)
- Sudo права
- Интернет-соединение
- Минимум 4GB RAM

## Управление нодой

```bash
# Просмотр логов
tmux a -t nexus

# Остановка ноды
tmux kill-session -t nexus

# Выход из логов без остановки ноды
# Ctrl+B, затем D
```

## Основные проблемы

### Несовместимая версия Ubuntu
Требуется Ubuntu 24.04 или выше. Обновите систему или используйте другой сервер.

### Отсутствие зависимостей
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install curl tmux -y

# CentOS/RHEL
sudo yum install curl tmux -y
```

### Проблемы с tmux
```bash
# Посмотреть сессии
tmux list-sessions

# Принудительно завершить
tmux kill-session -t nexus
```

## Лицензия

MIT License
