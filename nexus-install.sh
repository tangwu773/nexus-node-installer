#!/bin/bash

# Exit on any error
set -e

# Function to handle errors
error_exit() {
    echo ""
    echo "❌ ОШИБКА: $1"
    echo "Скрипт остановлен из-за критической ошибки."
    echo "Проверьте сообщения об ошибках выше и попробуйте снова."
    exit 1
}

# Function to handle non-critical errors
warning_message() {
    echo "⚠️ ПРЕДУПРЕЖДЕНИЕ: $1"
    echo "Продолжаем выполнение..."
}

# Ask for swap file size in GB
read -p "Введите размер файла подкачки в ГБ (по умолчанию 12): " SWAP_SIZE
# Set default value if user doesn't enter anything
SWAP_SIZE=${SWAP_SIZE:-12}

# Remove all existing swap files
echo "Отключение всех файлов подкачки..."
# Temporarily disable exit on error for swap operations (non-critical)
set +e
sudo swapoff -a

# Wait a moment for swapoff to complete
sleep 2

# Remove existing swapfile if it exists
if [ -f /swapfile ]; then
    echo "Удаление существующего файла подкачки /swapfile..."
    sudo rm -f /swapfile 2>/dev/null || {
        warning_message "Не удалось удалить /swapfile, возможно он используется. Пытаемся принудительно..."
        sudo fuser -k /swapfile 2>/dev/null
        sleep 2
        sudo rm -f /swapfile 2>/dev/null || warning_message "Не удалось удалить файл подкачки, продолжаем..."
    }
fi
# Re-enable exit on error
set -e

# Create a new swap file with the specified size
echo "Создание нового файла подкачки размером ${SWAP_SIZE}ГБ..."

# Temporarily disable exit on error for swap creation (non-critical)
set +e
if sudo fallocate -l ${SWAP_SIZE}G /swapfile; then
    sudo chmod 600 /swapfile
    if sudo mkswap /swapfile && sudo swapon /swapfile; then
        echo "✅ Файл подкачки создан и включен."
    else
        warning_message "Ошибка при создании swap. Продолжаем без swap файла..."
    fi
else
    warning_message "Не удалось создать файл подкачки. Продолжаем установку..."
fi
# Re-enable exit on error
set -e

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo "tmux не установлен. Установка tmux..."
    if [ -x "$(command -v apt)" ]; then
        sudo apt update || error_exit "Не удалось обновить список пакетов apt"
        sudo apt install -y tmux || error_exit "Не удалось установить tmux через apt"
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y tmux || error_exit "Не удалось установить tmux через yum"
    else
        error_exit "Не удалось определить менеджер пакетов. Установите tmux вручную."
    fi
    echo "✅ tmux успешно установлен."
else
    echo "✅ tmux уже установлен."
fi

# Install Nexus CLI
echo "Установка Nexus CLI..."
if ! curl https://cli.nexus.xyz/ | sh; then
    error_exit "Не удалось установить Nexus CLI. Проверьте интернет-соединение."
fi

# Verify that nexus-network binary was installed
if [ ! -f "$HOME/.nexus/bin/nexus-network" ]; then
    error_exit "Nexus CLI установлен, но исполняемый файл не найден в $HOME/.nexus/bin/nexus-network"
fi

echo "✅ Nexus CLI успешно установлен."

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
    error_exit "Не удалось получить Nexus ID после $MAX_ATTEMPTS попыток. Запустите скрипт заново и обязательно введите Nexus ID."
fi

# Check if tmux session "nexus" already exists
if tmux has-session -t nexus 2>/dev/null; then
    echo "Сессия tmux с именем 'nexus' уже существует. Завершаем её..."
    tmux kill-session -t nexus || warning_message "Не удалось завершить существующую сессию"
fi

# Start a tmux session named "nexus" and run the command
echo ""
echo "Запуск сессии tmux с именем 'nexus'..."

if ! tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID"; then
    error_exit "Не удалось создать tmux сессию. Проверьте установку tmux и Nexus CLI."
fi

echo "✅ Сессия tmux успешно создана"

# Wait a moment and check if the session is still running
sleep 3
if tmux has-session -t nexus 2>/dev/null; then
    echo "✅ Нода успешно запущена и работает"
else
    error_exit "Сессия tmux завершилась неожиданно. Проверьте правильность Nexus ID или запустите вручную: tmux attach -t nexus"
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