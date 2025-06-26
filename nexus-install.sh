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

# Check and stop existing tmux sessions first (before swap operations)
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПРОВЕРКА СУЩЕСТВУЮЩИХ ПРОЦЕССОВ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if tmux is installed first
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

# Check if tmux session "nexus" already exists and kill it before swap operations
if tmux has-session -t nexus 2>/dev/null; then
    echo "⚠️  Обнаружена работающая сессия tmux 'nexus' (возможно, запущен Nexus)"
    echo "Завершаем сессию для безопасной работы со swap-файлом..."
    tmux kill-session -t nexus 2>/dev/null || warning_message "Не удалось завершить существующую сессию"
    echo "✅ Существующая сессия завершена."
    sleep 2  # Wait for processes to fully terminate
else
    echo "✅ Активных сессий 'nexus' не обнаружено."
fi

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

# First, try to disable all swap
sudo swapoff -a 2>/dev/null

# Wait for processes to release swap
sleep 3

# Force kill processes using swap if needed
sudo fuser -k /swapfile 2>/dev/null || true
sleep 2

# Try multiple times to remove existing swapfile
MAX_REMOVE_ATTEMPTS=5
REMOVE_ATTEMPT=1

while [ $REMOVE_ATTEMPT -le $MAX_REMOVE_ATTEMPTS ] && [ -f /swapfile ]; do
    echo "Попытка удаления файла подкачки $REMOVE_ATTEMPT из $MAX_REMOVE_ATTEMPTS"
    
    # Disable swap on this specific file
    sudo swapoff /swapfile 2>/dev/null || true
    sleep 1
    
    # Force kill any processes still using the file
    sudo fuser -k /swapfile 2>/dev/null || true
    sleep 1
    
    # Try to remove the file
    if sudo rm -f /swapfile 2>/dev/null; then
        echo "✅ Старый файл подкачки удален"
        break
    else
        echo "⚠️ Попытка $REMOVE_ATTEMPT: не удалось удалить /swapfile"
        sleep 2
    fi
    
    REMOVE_ATTEMPT=$((REMOVE_ATTEMPT + 1))
done

# Check if old swapfile still exists
if [ -f /swapfile ]; then
    error_exit "Не удалось удалить существующий файл подкачки /swapfile после $MAX_REMOVE_ATTEMPTS попыток. Возможно, файл используется системным процессом. Попробуйте перезагрузить сервер."
fi

echo "✅ Подготовка к созданию нового файла подкачки завершена"
echo ""

# Create a new swap file with the specified size
echo "Создание нового файла подкачки размером ${SWAP_SIZE}ГБ..."

# Check available disk space
AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
REQUIRED_SPACE=$((SWAP_SIZE + 1))  # Add 1GB buffer

if [ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]; then
    error_exit "Недостаточно свободного места. Доступно: ${AVAILABLE_SPACE}ГБ, требуется: ${REQUIRED_SPACE}ГБ (${SWAP_SIZE}ГБ + 1ГБ буфер)"
fi

echo "✅ Проверка места: доступно ${AVAILABLE_SPACE}ГБ, требуется ${REQUIRED_SPACE}ГБ"

# Try to create swap file, retry if failed
MAX_SWAP_ATTEMPTS=3
SWAP_ATTEMPT=1

while [ $SWAP_ATTEMPT -le $MAX_SWAP_ATTEMPTS ]; do
    if [ $SWAP_ATTEMPT -gt 1 ]; then
        echo ""
        echo "Попытка создания swap-файла $SWAP_ATTEMPT из $MAX_SWAP_ATTEMPTS"
        sleep 3
        
        # Clean up any partial files
        sudo rm -f /swapfile 2>/dev/null || true
    fi
    
    # Try to create the file
    echo "Создание файла размером ${SWAP_SIZE}ГБ..."
    if sudo fallocate -l ${SWAP_SIZE}G /swapfile 2>/dev/null; then
        echo "✅ Файл создан, настройка прав доступа..."
        if sudo chmod 600 /swapfile; then
            echo "✅ Права установлены, инициализация swap..."
            if sudo mkswap /swapfile 2>/dev/null; then
                echo "✅ Swap инициализирован, активация..."
                if sudo swapon /swapfile 2>/dev/null; then
                    echo "✅ Файл подкачки создан и включен."
                    echo ""
                    echo "Информация о файле подкачки:"
                    sudo swapon --show
                    printf "\033[0m"  # Reset color formatting
                    echo ""
                    echo "Статус памяти после создания swap-файла:"
                    free -h
                    break
                else
                    echo "❌ Ошибка при активации swap-файла (попытка $SWAP_ATTEMPT)"
                fi
            else
                echo "❌ Ошибка при инициализации swap (попытка $SWAP_ATTEMPT)"
            fi
        else
            echo "❌ Ошибка при установке прав доступа (попытка $SWAP_ATTEMPT)"
        fi
        # Clean up failed attempt
        sudo rm -f /swapfile 2>/dev/null || true
    else
        echo "❌ Не удалось создать файл подкачки (попытка $SWAP_ATTEMPT)"
        echo "Возможные причины: недостаточно места, проблемы с правами или файловой системой"
    fi
    
    SWAP_ATTEMPT=$((SWAP_ATTEMPT + 1))
done

# Check if swap creation was successful
if [ $SWAP_ATTEMPT -gt $MAX_SWAP_ATTEMPTS ]; then
    error_exit "Не удалось создать файл подкачки после $MAX_SWAP_ATTEMPTS попыток. Проверьте свободное место на диске и права доступа."
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
printf "\033[1;32mПРОВЕРКА СОВМЕСТИМОСТИ СИСТЕМЫ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check OS compatibility
echo "Проверка совместимости операционной системы..."

# Get OS information
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    echo "✅ Обнаружена ОС: $OS_NAME $OS_VERSION"
else
    warning_message "Не удалось определить версию операционной системы"
    OS_NAME="Unknown"
    OS_VERSION="0"
fi

# Check Ubuntu version compatibility
if [[ "$OS_NAME" == *"Ubuntu"* ]]; then
    # Extract major version number (e.g., "24.04" -> "24")
    UBUNTU_MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d'.' -f1)
    
    echo "Проверка совместимости Ubuntu $UBUNTU_MAJOR_VERSION с Nexus CLI..."
    
    if [ "$UBUNTU_MAJOR_VERSION" -lt 24 ]; then
        echo ""
        printf "\033[1;31m❌ КРИТИЧЕСКАЯ ОШИБКА СОВМЕСТИМОСТИ\033[0m\n"
        printf "\033[1;31m================================================\033[0m\n"
        echo ""
        echo "🚫 Обнаружена несовместимая версия операционной системы"
        echo ""
        echo "📋 Информация о системе:"
        echo "   ОС: $OS_NAME $OS_VERSION"
        echo ""
        printf "\033[1;33m⚠️  ТРЕБОВАНИЯ NEXUS:\033[0m\n"
        echo "   Nexus CLI работает только на Ubuntu 24.04 и выше"
        echo "   Ваша версия Ubuntu $OS_VERSION не поддерживается"
        echo ""
        printf "\033[1;36m💡 РЕШЕНИЕ ПРОБЛЕМЫ:\033[0m\n"
        echo "   1. Обновите Ubuntu до версии 24.04 LTS или выше"
        echo "   2. Используйте другой сервер с Ubuntu 24.04+"
        echo ""
        printf "\033[1;31mСкрипт остановлен из-за несовместимости версии ОС.\033[0m\n"
        printf "\033[1;31mПожалуйста, обновите Ubuntu и запустите скрипт заново.\033[0m\n"
        echo ""
        exit 1
    else
        echo "✅ Ubuntu $OS_VERSION совместима с Nexus CLI"
    fi
else
    warning_message "Обнаружена не-Ubuntu система: $OS_NAME. Nexus может работать некорректно на других ОС."
    echo "Продолжаем установку на ваш страх и риск..."
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
        echo "Nexus ID не может быть пустым"
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
printf "\033[1;32m🎉 УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО 🎉\033[0m\n"
printf "\033[1;32m==================================\033[0m\n"
echo ""
printf "\033[1;32mНода Nexus успешно запущена в фоновом режиме\033[0m\n"
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
printf "\033[1;32mСкрипт выполнен успешно 🚀\033[0m\n"
printf "\033[1;32m==================================\033[0m\n"