#!/bin/bash

# Clear the screen for better visibility
clear

echo ""
printf "\033[1;32m🚀 NEXUS NODE INSTALLER 🚀\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mАвтоматический установщик ноды Nexus\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

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
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mНАСТРОЙКА ФАЙЛА ПОДКАЧКИ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo "Введите размер файла подкачки в ГБ (по умолчанию 12): "
read SWAP_SIZE </dev/tty
# Set default value if user doesn't enter anything
SWAP_SIZE=${SWAP_SIZE:-12}
echo "✅ Установлен размер swap: ${SWAP_SIZE}ГБ"
echo ""

# Remove all existing swap files
echo "Отключение всех файлов подкачки..."
sudo swapoff -a 2>/dev/null || warning_message "Не удалось отключить все swap файлы"

# Wait a moment for swapoff to complete
sleep 2

# Remove existing swapfile if it exists
if [ -f /swapfile ]; then
    echo "Удаление существующего файла подкачки /swapfile..."
    sudo rm -f /swapfile 2>/dev/null || {
        warning_message "Не удалось удалить /swapfile, возможно он используется. Пытаемся принудительно..."
        sudo fuser -k /swapfile 2>/dev/null || true
        sleep 2
        sudo rm -f /swapfile 2>/dev/null || warning_message "Не удалось удалить файл подкачки, продолжаем..."
    }
fi

# Create a new swap file with the specified size
echo "Создание нового файла подкачки размером ${SWAP_SIZE}ГБ..."

if sudo fallocate -l ${SWAP_SIZE}G /swapfile 2>/dev/null; then
    if sudo chmod 600 /swapfile && sudo mkswap /swapfile 2>/dev/null && sudo swapon /swapfile 2>/dev/null; then
        echo "✅ Файл подкачки создан и включен."
        echo ""
        echo "Информация о файле подкачки:"
        sudo swapon --show
        printf "\033[0m"  # Reset color formatting
        echo ""
        echo "Статус памяти после создания swap-файла:"
        free -h
    else
        warning_message "Ошибка при создании swap. Продолжаем без swap файла..."
    fi
else
    warning_message "Не удалось создать файл подкачки. Продолжаем установку..."
fi

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mУСТАНОВКА TMUX\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo "tmux не установлен. Установка tmux..."
    if [ -x "$(command -v apt)" ]; then
        if ! sudo apt update; then
            error_exit "Не удалось обновить список пакетов apt"
        fi
        if ! sudo apt install -y tmux; then
            error_exit "Не удалось установить tmux через apt"
        fi
    elif [ -x "$(command -v yum)" ]; then
        if ! sudo yum install -y tmux; then
            error_exit "Не удалось установить tmux через yum"
        fi
    else
        error_exit "Не удалось определить менеджер пакетов. Установите tmux вручную."
    fi
    echo "✅ tmux успешно установлен."
else
    echo "✅ tmux уже установлен."
fi

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПРОВЕРКА СУЩЕСТВУЮЩИХ СЕССИЙ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if tmux session "nexus" already exists and kill it before installation
if tmux has-session -t nexus 2>/dev/null; then
    echo "Обнаружена существующая сессия tmux 'nexus'. Завершаем её..."
    tmux kill-session -t nexus 2>/dev/null || warning_message "Не удалось завершить существующую сессию"
    echo "✅ Существующая сессия завершена."
else
    echo "✅ Активных сессий 'nexus' не обнаружено."
fi

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mУСТАНОВКА NEXUS CLI\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if Nexus CLI is already installed
if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
    echo "✅ Nexus CLI уже установлен."
    
    # Get version if possible
    if NEXUS_VERSION=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null); then
        echo "Текущая версия: $NEXUS_VERSION"
    else
        echo "Версия: не удалось определить"
    fi
    
    echo ""
    echo "Хотите переустановить Nexus CLI? (y/N): "
    read REINSTALL_CHOICE </dev/tty
    
    case "${REINSTALL_CHOICE,,}" in
        y|yes|да|д)
            echo "Переустанавливаем Nexus CLI..."
            # Remove existing installation
            rm -rf "$HOME/.nexus" 2>/dev/null || warning_message "Не удалось удалить старую установку"
            INSTALL_NEXUS=true
            ;;
        *)
            echo "Используем существующую установку Nexus CLI."
            INSTALL_NEXUS=false
            ;;
    esac
else
    echo "Nexus CLI не установлен."
    INSTALL_NEXUS=true
fi

# Install Nexus CLI if needed
if [ "$INSTALL_NEXUS" = true ]; then
    echo "Установка Nexus CLI..."
    
    # Check if curl is available
    if ! command -v curl &> /dev/null; then
        error_exit "curl не найден. Установите curl для продолжения."
    fi
    
    if ! curl https://cli.nexus.xyz/ | sh; then
        error_exit "Не удалось установить Nexus CLI. Проверьте интернет-соединение."
    fi
    
    # Verify that nexus-network binary was installed
    if [ ! -f "$HOME/.nexus/bin/nexus-network" ]; then
        error_exit "Nexus CLI установлен, но исполняемый файл не найден в $HOME/.nexus/bin/nexus-network"
    fi
    
    echo "✅ Nexus CLI успешно установлен."
fi

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПОЛУЧЕНИЕ NEXUS ID\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Display instructions for obtaining Nexus ID
echo ""
echo "ВАЖНО: Получите ваш Nexus ID"
echo ""
echo "1. Откройте браузер и перейдите на: https://app.nexus.xyz/nodes"
echo "2. Войдите в свой аккаунт (кнопка Sign In)" 
echo "3. Нажмите кнопку 'Add CLI Node'"
echo "4. Скопируйте появившиеся цифры - это ваш Nexus ID"
echo ""

# Ask for Nexus ID and save it with retry logic
NEXUS_ID=""
ATTEMPT=1
MAX_ATTEMPTS=3

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    if [ $ATTEMPT -gt 1 ]; then
        echo ""
        echo "Попытка $ATTEMPT из $MAX_ATTEMPTS"
        echo "Nexus ID не может быть пустым!"
    fi
    
    echo "Введите ваш Nexus ID: "
    read NEXUS_ID </dev/tty
    
    # Trim whitespace
    NEXUS_ID=$(echo "$NEXUS_ID" | xargs 2>/dev/null || echo "$NEXUS_ID")
    
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

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mЗАПУСК НОДЫ NEXUS\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Start a tmux session named "nexus" and run the command
echo ""
echo "Запуск сессии tmux с именем 'nexus'..."

if tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID" 2>/dev/null; then
    echo "✅ Сессия tmux успешно создана"
    
    # Wait a moment and check if the session is still running
    sleep 3
    if tmux has-session -t nexus 2>/dev/null; then
        printf "\033[1;32m✅ Нода успешно запущена и работает\033[0m\n"
    else
        error_exit "Сессия tmux завершилась неожиданно. Проверьте правильность Nexus ID или запустите вручную: tmux attach -t nexus"
    fi
else
    error_exit "Не удалось создать tmux сессию. Проверьте установку tmux и Nexus CLI."
fi

echo ""
printf "\033[1;32m==================================\033[0m\n"
printf "\033[1;32m🎉 УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО! 🎉\033[0m\n"
printf "\033[1;32m==================================\033[0m\n"
echo ""
printf "\033[1;32mНода Nexus успешно запущена в фоновом режиме!\033[0m\n"
echo ""
printf "🆔 Ваш Nexus ID: \033[1;36m$NEXUS_ID\033[0m\n"
echo ""
echo "✅ Нода работает в фоновом режиме в tmux сессии"
printf "\033[1;33m✅ Вы можете свободно закрывать терминал - нода продолжит работу\033[0m\n"
echo "✅ Проверить статус ноды и начисление очков можно на странице:"
echo "   https://app.nexus.xyz/nodes"
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32m📋 ПОЛЕЗНЫЕ КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ НОДОЙ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
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
printf "\033[1;32m==================================\033[0m\n"
printf "\033[1;32mСкрипт выполнен успешно! 🚀\033[0m\n"
printf "\033[1;32m==================================\033[0m\n"