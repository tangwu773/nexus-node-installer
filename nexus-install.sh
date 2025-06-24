#!/bin/bash

# Ask for swap file size in GB
read -p "Введите размер файла подкачки в ГБ (по умолчанию 12): " SWAP_SIZE
# Set default value if user doesn't enter anything
SWAP_SIZE=${SWAP_SIZE:-12}

# Remove all existing swap files
echo "Отключение всех файлов подкачки..."
sudo swapoff -a
if [ -f /swapfile ]; then
    echo "Удаление существующего файла подкачки /swapfile..."
    sudo rm /swapfile
fi

# Create a new swap file with the specified size
echo "Создание нового файла подкачки размером ${SWAP_SIZE}ГБ..."
sudo fallocate -l ${SWAP_SIZE}G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo "Файл подкачки создан и включен."

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo "tmux не установлен. Установка tmux..."
    if [ -x "$(command -v apt)" ]; then
        sudo apt update && sudo apt install -y tmux
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y tmux
    else
        echo "Не удалось определить менеджер пакетов. Установите tmux вручную."
        exit 1
    fi
else
    echo "tmux уже установлен."
fi

# Install Nexus CLI
echo "Установка Nexus CLI..."
curl https://cli.nexus.xyz/ | sh

# Display instructions for obtaining Nexus ID
echo "Скопируйте Nexus ID с сайта Nexus. Для этого в браузере перейдите по адресу https://app.nexus.xyz/nodes, войдите в свой аккаунт (кнопка Sign In), нажмите кнопку \"Add CLI Node\" и скопируйте появившиеся цифры. Это и есть ваш Nexus ID для данной ноды."

# Ask for Nexus ID and save it with retry logic
NEXUS_ID=""
ATTEMPT=1
MAX_ATTEMPTS=3

while [ $ATTEMPT -le $MAX_ATTEMPTS ] && [ -z "$NEXUS_ID" ]; do
    if [ $ATTEMPT -gt 1 ]; then
        echo "Попытка $ATTEMPT из $MAX_ATTEMPTS"
    fi
    read -p "Введите ваш Nexus ID: " NEXUS_ID
    
    if [ -z "$NEXUS_ID" ]; then
        echo "Nexus ID не может быть пустым"
        ATTEMPT=$((ATTEMPT + 1))
    fi
done

if [ -z "$NEXUS_ID" ]; then
    echo "Не удалось получить Nexus ID после $MAX_ATTEMPTS попыток. Скрипт завершен."
    exit 1
fi

# Check if tmux session "nexus" already exists
if tmux has-session -t nexus 2>/dev/null; then
    echo "Сессия tmux с именем 'nexus' уже существует. Завершаем её..."
    tmux kill-session -t nexus
fi

# Start a tmux session named "nexus" and run the command
echo "Запуск сессии tmux с именем 'nexus'..."
tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID"

echo "=================================="
echo "Нода Nexus успешно запущена в фоновом режиме!"
echo "=================================="
echo ""
echo "🆔 Ваш Nexus ID: $NEXUS_ID"
echo ""
echo "✅ Нода работает в фоновом режиме в tmux сессии"
echo "✅ Вы можете свободно закрывать терминал - нода продолжит работу"
echo "✅ Проверить статус ноды и начисление очков можно на странице:"
echo "   https://app.nexus.xyz/nodes"
echo ""
echo "📋 Полезные команды для управления нодой:"
echo ""
echo "🔗 Подключиться к сессии с нодой (посмотреть логи работы):"
echo "   tmux attach -t nexus"
echo ""
echo "🔙 Выйти из сессии БЕЗ остановки ноды:"
echo "   Нажмите Ctrl+B, отпустите, затем нажмите D"
echo ""
echo "📋 Показать все запущенные сессии:"
echo "   tmux list-sessions"
echo ""
echo "❌ Полностью остановить ноду:"
echo "   tmux kill-session -t nexus"
echo ""
echo "Скрипт выполнен успешно."