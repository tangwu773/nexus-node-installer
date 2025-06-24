#!/bin/bash

# Ask for swap file size in GB
read -p "Введите размер файла подкачки в ГБ (по умолчанию 12): " SWAP_SIZE
# Set default value if user doesn't enter anything
SWAP_SIZE=${SWAP_SIZE:-12}

# Remove all existing swap files
echo "Отключение всех файлов подкачки..."
sudo swapoff -a

# Wait a moment for swapoff to complete
sleep 2

# Remove existing swapfile if it exists
if [ -f /swapfile ]; then
    echo "Удаление существующего файла подкачки /swapfile..."
    sudo rm -f /swapfile 2>/dev/null || {
        echo "Не удалось удалить /swapfile, возможно он используется. Пытаемся принудительно..."
        sudo fuser -k /swapfile 2>/dev/null
        sleep 2
        sudo rm -f /swapfile 2>/dev/null || echo "Не удалось удалить файл подкачки, продолжаем..."
    }
fi

# Create a new swap file with the specified size
echo "Создание нового файла подкачки размером ${SWAP_SIZE}ГБ..."
if sudo fallocate -l ${SWAP_SIZE}G /swapfile; then
    sudo chmod 600 /swapfile
    if sudo mkswap /swapfile && sudo swapon /swapfile; then
        echo "Файл подкачки создан и включен."
    else
        echo "Ошибка при создании swap. Продолжаем без swap файла..."
    fi
else
    echo "Не удалось создать файл подкачки. Продолжаем установку..."
fi

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
echo ""
echo "================================================"
echo "ВАЖНО: Получите ваш Nexus ID"
echo "================================================"
echo "1. Откройте браузер и перейдите на: https://app.nexus.xyz/nodes"
echo "2. Войдите в свой аккаунт (кнопка Sign In)" 
echo "3. Нажмите кнопку 'Add CLI Node'"
echo "4. Скопируйте появившиеся цифры - это ваш Nexus ID"
echo ""

# Ask for Nexus ID and save it with retry logic
NEXUS_ID=""
ATTEMPT=1
MAX_ATTEMPTS=3

echo "Теперь введите ваш Nexus ID:"

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if [ $ATTEMPT -gt 1 ]; then
        echo ""
        echo "Попытка $ATTEMPT из $MAX_ATTEMPTS"
        echo "Nexus ID не может быть пустым!"
    fi
    
    echo -n "Введите ваш Nexus ID: "
    read NEXUS_ID
    
    # Trim whitespace
    NEXUS_ID=$(echo "$NEXUS_ID" | xargs)
    
    if [ -n "$NEXUS_ID" ]; then
        echo "Получен Nexus ID: $NEXUS_ID"
        break
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

if [ -z "$NEXUS_ID" ]; then
    echo ""
    echo "❌ Не удалось получить Nexus ID после $MAX_ATTEMPTS попыток."
    echo "Скрипт завершен. Запустите скрипт заново и обязательно введите Nexus ID."
    exit 1
fi

# Check if tmux session "nexus" already exists
if tmux has-session -t nexus 2>/dev/null; then
    echo "Сессия tmux с именем 'nexus' уже существует. Завершаем её..."
    tmux kill-session -t nexus
fi

# Start a tmux session named "nexus" and run the command
echo ""
echo "Запуск сессии tmux с именем 'nexus'..."

if tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID"; then
    echo "✅ Сессия tmux успешно создана"
    
    # Wait a moment and check if the session is still running
    sleep 3
    if tmux has-session -t nexus 2>/dev/null; then
        echo "✅ Нода успешно запущена"
    else
        echo "⚠️ Сессия tmux завершилась. Проверьте правильность Nexus ID"
        echo "Попробуйте подключиться вручную: tmux attach -t nexus"
    fi
else
    echo "❌ Ошибка при создании tmux сессии"
    echo "Попробуйте запустить ноду вручную:"
    echo "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID"
    exit 1
fi

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