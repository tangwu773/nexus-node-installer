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

# Function to display a process message
process_message() {
    echo ""
    printf "\033[1;33m %s\033[0m\n" "$1"
    echo ""
}



# Function to check and install a package if missing
ensure_package_installed() {
    local pkg="$1"
    if ! command -v "$pkg" &> /dev/null; then
        process_message "$pkg не установлен. Установка $pkg..."
        if [ -x "$(command -v apt)" ]; then
            if ! sudo apt update; then
                error_exit "Не удалось обновить список пакетов apt"
            fi
            if ! sudo apt install -y "$pkg"; then
                error_exit "Не удалось установить $pkg через apt"
            fi
        elif [ -x "$(command -v yum)" ]; then
            if ! sudo yum install -y "$pkg"; then
                error_exit "Не удалось установить $pkg через yum"
            fi
        else
            error_exit "Не удалось определить менеджер пакетов. Установите $pkg вручную."
        fi
        echo "✅ $pkg успешно установлен."
    else
        echo "✅ $pkg уже установлен."
    fi
}

# Function to save Nexus ID to file
save_nexus_id() {
    local nexus_id="$1"
    local save_file="$HOME/.nexus_installer_config.json"
    local current_time=$(date +%s)
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$save_file")" 2>/dev/null
    
    # Preserve existing update time if available
    local existing_update_time=0
    if [ -f "$save_file" ]; then
        existing_update_time=$(grep -o '"last_update_check": [0-9]*' "$save_file" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || echo 0)
    fi
    
    # Save to new JSON structure
    echo "{\"nexus_id\": \"$nexus_id\", \"last_update_check\": $existing_update_time}" > "$save_file" 2>/dev/null
}

# Function to save update check time to JSON config
save_update_check_time() {
    local update_time="$1"
    local save_file="$HOME/.nexus_installer_config.json"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$save_file")" 2>/dev/null
    
    # Get existing nexus_id
    local existing_nexus_id=""
    if [ -f "$save_file" ]; then
        existing_nexus_id=$(grep -o '"nexus_id": "[^"]*"' "$save_file" 2>/dev/null | cut -d'"' -f4 || \
                           grep -o '"last_nexus_id": "[^"]*"' "$save_file" 2>/dev/null | cut -d'"' -f4)
    fi
    
    # Save to JSON with both parameters
    if [ -n "$existing_nexus_id" ]; then
        echo "{\"nexus_id\": \"$existing_nexus_id\", \"last_update_check\": $update_time}" > "$save_file" 2>/dev/null
    else
        echo "{\"nexus_id\": \"\", \"last_update_check\": $update_time}" > "$save_file" 2>/dev/null
    fi
}

# Function to load update check time from JSON config
load_update_check_time() {
    local save_file="$HOME/.nexus_installer_config.json"
    
    if [ -f "$save_file" ]; then
        # Extract update time from JSON
        grep -o '"last_update_check": [0-9]*' "$save_file" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || echo 0
    else
        echo 0
    fi
}

# Function to remove existing nexus auto-restart cron jobs
remove_nexus_cron() {
    # Remove any existing nexus restart cron jobs
    crontab -l 2>/dev/null | grep -v "nexus.*restart" | crontab - 2>/dev/null || true
}

# Function to add auto-restart cron job with auto-update
add_nexus_cron() {
    local interval_minutes="$1"
    local nexus_id="$2"
    
    # Remove existing cron jobs first
    remove_nexus_cron
    
    # Create auto-restart script with update functionality
    local restart_script=$(create_auto_restart_script)
    
    # Calculate cron expression for given interval
    if [ "$interval_minutes" -lt 60 ]; then
        # Less than hour - run every N minutes
        cron_expr="*/$interval_minutes * * * *"
    else
        # Hour or more - convert to hours
        local hours=$((interval_minutes / 60))
        cron_expr="0 */$hours * * *"
    fi
    
    # Create restart command using the script
    local restart_cmd="$restart_script $nexus_id # nexus auto restart"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$cron_expr $restart_cmd") | crontab -
}

# Function to load saved Nexus ID
load_saved_nexus_id() {
    local save_file="$HOME/.nexus_installer_config.json"
    
    if [ -f "$save_file" ]; then
        # Extract ID from new JSON structure
        grep -o '"nexus_id": "[^"]*"' "$save_file" 2>/dev/null | cut -d'"' -f4 || \
        # Fallback to old structure for backward compatibility
        grep -o '"last_nexus_id": "[^"]*"' "$save_file" 2>/dev/null | cut -d'"' -f4
    fi
}

# Function to create auto-restart script with update functionality
create_auto_restart_script() {
    local script_path="$HOME/.nexus/auto_restart.sh"
    
    # Create .nexus directory if it doesn't exist
    mkdir -p "$HOME/.nexus" 2>/dev/null
    
    # Create the auto-restart script
    cat > "$script_path" << 'AUTO_RESTART_EOF'
#!/bin/bash

# Auto-restart script with auto-update functionality
# Arguments: $1 = nexus_id

NEXUS_ID="$1"
CONFIG_FILE="$HOME/.nexus_installer_config.json"
CURRENT_TIME=$(date +%s)

# Function to load update check time from JSON config
load_update_check_time() {
    if [ -f "$CONFIG_FILE" ]; then
        grep -o '"last_update_check": [0-9]*' "$CONFIG_FILE" 2>/dev/null | cut -d':' -f2 | tr -d ' ' || echo 0
    else
        echo 0
    fi
}

# Function to save update check time to JSON config
save_update_check_time() {
    local update_time="$1"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$CONFIG_FILE")" 2>/dev/null
    
    # Get existing nexus_id
    local existing_nexus_id=""
    if [ -f "$CONFIG_FILE" ]; then
        existing_nexus_id=$(grep -o '"nexus_id": "[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 || \
                           grep -o '"last_nexus_id": "[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4)
    fi
    
    # Save to JSON with both parameters
    if [ -n "$existing_nexus_id" ]; then
        echo "{\"nexus_id\": \"$existing_nexus_id\", \"last_update_check\": $update_time}" > "$CONFIG_FILE" 2>/dev/null
    else
        echo "{\"nexus_id\": \"$NEXUS_ID\", \"last_update_check\": $update_time}" > "$CONFIG_FILE" 2>/dev/null
    fi
}

# Function for silent Nexus CLI update
update_nexus_cli_silent() {
    local last_update_time=$(load_update_check_time)
    
    # Check if update is needed (max once per hour)
    if [ $((CURRENT_TIME - last_update_time)) -gt 3600 ]; then
        # Stop existing session for update
        tmux kill-session -t nexus 2>/dev/null || true
        sleep 2
        
        # Check versions
        local current_version=""
        local latest_version=""
        
        if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
            current_version=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed "s/nexus-network //" | sed "s/^v//")
        fi
        
        latest_version=$(curl -s https://api.github.com/repos/nexus-xyz/nexus-cli/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E "s/.*\"tag_name\": \"v?([^\"]*)\".*/\\1/")
        
        # Update only if needed
        if [ -n "$current_version" ] && [ -n "$latest_version" ] && [ "$current_version" != "$latest_version" ]; then
            # Официальный способ: скачать install.sh и запустить с NONINTERACTIVE=1
            installer_dir="$HOME/.nexus"
            installer_file="$installer_dir/install.sh"
            mkdir -p "$installer_dir"
            if curl -sSf https://cli.nexus.xyz/ -o "$installer_file"; then
                chmod +x "$installer_file"
                if NONINTERACTIVE=1 "$installer_file" >/dev/null 2>&1; then
                    if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
                        save_update_check_time "$CURRENT_TIME"
                    fi
                fi
                rm -f "$installer_file"
            fi
        else
            # Mark as checked even if no update needed
            save_update_check_time "$CURRENT_TIME"
        fi
    fi
}

# Perform auto-update check
update_nexus_cli_silent

# Restart the node
tmux kill-session -t nexus 2>/dev/null || true
sleep 5
tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID"
AUTO_RESTART_EOF
    
    # Make the script executable
    chmod +x "$script_path"
    
    echo "$script_path"
}

# Функция установки/обновления Nexus CLI
# Возвращает: 0 = успех, 1 = ошибка, 2 = уже актуальная версия
update_nexus_cli() {
    local force_reinstall="${1:-false}"
    local quiet_mode="${2:-false}"
    
    # Определение режима: первая установка или обновление
    local is_first_install=true
    if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
        is_first_install=false
    fi
    
    # Функция для логирования (только если не тихий режим)
    log_message() {
        [ "$quiet_mode" = "false" ] && echo "$1"
    }
    
    # Проверка текущей и последней версии
    local current_version=""
    local latest_version=""
    
    if [ "$is_first_install" = "false" ]; then
        current_version=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed "s/nexus-network //" | sed "s/^v//")
    fi
    
    latest_version=$(curl -s https://api.github.com/repos/nexus-xyz/nexus-cli/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E "s/.*\"tag_name\": \"v?([^\"]*)\".*/\\1/")
    
    # Проверка необходимости обновления
    if [ "$force_reinstall" = "false" ] && [ "$is_first_install" = "false" ] && [ -n "$current_version" ] && [ "$current_version" = "$latest_version" ]; then
        log_message "✅ Nexus CLI уже актуален (версия $current_version)"
        return 2
    fi
    
    log_message "🔄 $([ "$is_first_install" = "true" ] && echo "Установка" || ([ "$force_reinstall" = "true" ] && echo "Переустановка" || echo "Обновление")) Nexus CLI..."
    [ -n "$current_version" ] && log_message "Текущая: $current_version"
    [ -n "$latest_version" ] && log_message "Последняя: $latest_version"
    
    # Остановка существующих процессов
    tmux kill-session -t nexus 2>/dev/null || true
    sleep 2
    
    # Проверка curl
    if ! command -v curl &> /dev/null; then
        log_message "❌ curl не найден. Установите curl для продолжения."
        return 1
    fi
    
    # Выполнение установки/обновления
    if [ "$is_first_install" = "true" ]; then
        # Первая установка - интерактивная
        if curl -sSL https://cli.nexus.xyz/ | sh; then
            log_message "✅ Nexus CLI установлен успешно"
            return 0
        else
            log_message "❌ Ошибка при установке Nexus CLI"
            return 1
        fi
    else
        # Обновление или переустановка - неинтерактивное через install.sh (официально)
        local installer_dir="$HOME/.nexus"
        local installer_file="$installer_dir/install.sh"
        mkdir -p "$installer_dir"
        if curl -sSf https://cli.nexus.xyz/ -o "$installer_file"; then
            chmod +x "$installer_file"
            if NONINTERACTIVE=1 "$installer_file" >/dev/null 2>&1; then
                local new_version=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed "s/nexus-network //" | sed "s/^v//")
                log_message "✅ Nexus CLI $([ "$force_reinstall" = "true" ] && echo "переустановлен" || echo "обновлен") до версии $new_version"
                rm -f "$installer_file"
                return 0
            else
                log_message "❌ Ошибка при $([ "$force_reinstall" = "true" ] && echo "переустановке" || echo "обновлении") Nexus CLI"
                rm -f "$installer_file"
                return 1
            fi
        else
            log_message "❌ Не удалось скачать официальный install.sh для Nexus CLI"
            return 1
        fi
    fi
}

# Function to display memory status in Russian table format
show_memory_status() {
    echo "┌──────────────────┬──────────┬──────────┬──────────┐"
    echo "│      Память      │  Всего   │ Занято   │ Свободно │"
    echo "├──────────────────┼──────────┼──────────┼──────────┤"
    
    # RAM info
    free -h | awk '
    /^Mem:/ {
        total = $2; gsub(/Gi/, "Гб", total); gsub(/Mi/, "Мб", total); gsub(/Ki/, "Кб", total);
        used = $3; gsub(/Gi/, "Гб", used); gsub(/Mi/, "Мб", used); gsub(/Ki/, "Кб", used);
        free = $4; gsub(/Gi/, "Гб", free); gsub(/Mi/, "Мб", free); gsub(/Ki/, "Кб", free);
        printf "│ Оперативка (RAM) │ %8s │ %8s │ %8s │\n", total, used, free
    }'
    
    # Проверяем, есть ли активный файл подкачки
    if swapon --show 2>/dev/null | grep -q .; then
        free -h | awk '
        /^Swap:/ {
            total = $2; gsub(/Gi/, "Гб", total); gsub(/Mi/, "Мб", total); gsub(/Ki/, "Кб", total);
            used = $3; gsub(/Gi/, "Гб", used); gsub(/Mi/, "Мб", used); gsub(/Ki/, "Кб", used);
            free = $4; gsub(/Gi/, "Гб", free); gsub(/Mi/, "Мб", free); gsub(/Ki/, "Кб", free);
            printf "│ Подкачка (Swap)  │ %8s │ %8s │ %8s │\n", total, used, free
        }'
        echo "└──────────────────┴──────────┴──────────┴──────────┘"
    else
        echo "└──────────────────┴──────────┴──────────┴──────────┘"
        echo "✅ Файл подкачки не используется"
    fi
}

# Function to display only RAM status in Russian table format
show_ram_status() {
    echo "┌──────────┬──────────┬──────────┬──────────┬──────────┬──────────┐"
    echo "│  Всего   │  Занято  │ Свободно │  Общее   │ Буфер/   │ Доступно │"
    echo "│          │          │          │          │   Кеш    │          │"
    echo "├──────────┼──────────┼──────────┼──────────┼──────────┼──────────┤"
    
    # Get memory info and format it with Russian units
    free -h | awk '
    /^Mem:/ {
        # Convert units to Russian
        total = $2; gsub(/Gi/, "Гб", total); gsub(/Mi/, "Мб", total); gsub(/Ki/, "Кб", total);
        used = $3; gsub(/Gi/, "Гб", used); gsub(/Mi/, "Мб", used); gsub(/Ki/, "Кб", used);
        free = $4; gsub(/Gi/, "Гб", free); gsub(/Mi/, "Мб", free); gsub(/Ki/, "Кб", free);
        shared = $5; gsub(/Gi/, "Гб", shared); gsub(/Mi/, "Мб", shared); gsub(/Ki/, "Кб", shared);
        cache = $6; gsub(/Gi/, "Гб", cache); gsub(/Mi/, "Мб", cache); gsub(/Ki/, "Кб", cache);
        available = $7; gsub(/Gi/, "Гб", available); gsub(/Mi/, "Мб", available); gsub(/Ki/, "Кб", available);
        
        printf "│ %8s │ %8s │ %8s │ %8s │ %8s │ %8s │\n", total, used, free, shared, cache, available
    }'
    
    echo "└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┘"
}

# Function to display only swap status in Russian table format
show_swap_table() {
    # Check if swap is active
    if swapon --show 2>/dev/null | grep -q .; then
        echo "┌──────────┬──────────┬──────────┐"
        echo "│  Всего   │  Занято  │ Свободно │"
        echo "├──────────┼──────────┼──────────┤"
        
        # Get swap info and format it with Russian units
        free -h | awk '
        /^Swap:/ {
            # Convert units to Russian
            total = $2; gsub(/Gi/, "Гб", total); gsub(/Mi/, "Мб", total); gsub(/Ki/, "Кб", total);
            used = $3; gsub(/Gi/, "Гб", used); gsub(/Mi/, "Мб", used); gsub(/Ki/, "Кб", used);
            free = $4; gsub(/Gi/, "Гб", free); gsub(/Mi/, "Мб", free); gsub(/Ki/, "Кб", free);
            
            printf "│ %8s │ %8s │ %8s │\n", total, used, free
        }'
        
        echo "└──────────┴──────────┴──────────┘"
    else
        echo "✅ Нет активных файлов подкачки"
    fi
}


# Check and stop existing tmux sessions first (before swap operations)
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПРОВЕРКА СУЩЕСТВУЮЩИХ ПРОЦЕССОВ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if tmux, cron, jq is installed first
ensure_package_installed "tmux"
ensure_package_installed "cron"
ensure_package_installed "jq"

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПРОВЕРКА СУЩЕСТВУЮЩИХ СЕССИЙ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if tmux session "nexus" already exists and kill it before swap operations
if tmux has-session -t nexus 2>/dev/null; then
    echo "⚠️  Обнаружена работающая сессия tmux 'nexus' (возможно, запущен Nexus)"
    echo ""
    printf "\033[1;32mЗавершаем сессию для безопасной работы с файлом подкачки...\033[0m\n"
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

echo "Текущее состояние оперативной памяти и файла подкачки:"
show_memory_status
echo ""


echo "Размер файла подкачки в ГБ (Enter = 12ГБ, 0 = не создавать): "
read SWAP_SIZE </dev/tty
# Set default value if user doesn't enter anything
SWAP_SIZE=${SWAP_SIZE:-12}

echo ""
if [ "$SWAP_SIZE" = "0" ]; then
    echo "✅ Файл подкачки не нужен"
else
    echo "✅ Создать файл подкачки размером ${SWAP_SIZE}Гб"
fi
echo ""

# Always remove existing swap files first
echo ""

# Check if swapfile exists before starting removal process
SWAP_FILE_EXISTS=false
if [ -f /swapfile ]; then
    SWAP_FILE_EXISTS=true
    printf "\033[1;32mОтключаем и удаляем текущий файл подкачки...\033[0m\n"
fi

# First, try to disable all swap
sudo swapoff -a 2>/dev/null

# Wait for processes to release swap
sleep 3

# Force kill processes using swap if needed
sudo fuser -k /swapfile 2>/dev/null || true
sleep 1

# Try multiple times to remove existing swapfile
MAX_REMOVE_ATTEMPTS=5
REMOVE_ATTEMPT=1

while [ $REMOVE_ATTEMPT -le $MAX_REMOVE_ATTEMPTS ] && [ -f /swapfile ]; do
    # Disable swap on this specific file
    sudo swapoff /swapfile 2>/dev/null || true
    sleep 1
    
    # Force kill any processes still using the file
    sudo fuser -k /swapfile 2>/dev/null || true
    sleep 1
    
    # Try to remove the file
    if sudo rm -f /swapfile 2>/dev/null; then
        break
    else
        sleep 2
    fi
    
    REMOVE_ATTEMPT=$((REMOVE_ATTEMPT + 1))
done

# Check if old swapfile still exists
if [ -f /swapfile ]; then
    error_exit "Не удалось удалить существующий файл подкачки /swapfile после $MAX_REMOVE_ATTEMPTS попыток. Возможно, файл используется системным процессом. Попробуйте перезагрузить сервер."
fi

# Show result of swap removal only if file existed
if [ "$SWAP_FILE_EXISTS" = true ]; then
    echo ""
    echo "✅ Файл подкачки успешно отключен и удален"
    echo ""
fi

# Check if user wants to skip swap creation
if [ "$SWAP_SIZE" = "0" ]; then
    # Don't output anything for swap=0 case
    true
else
    printf "\033[1;32mСоздаем новый файл подкачки размером ${SWAP_SIZE}Гб...\033[0m\n"

    # Check available disk space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    REQUIRED_SPACE=$((SWAP_SIZE + 1))  # Add 1GB buffer

    if [ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]; then
        error_exit "❌ Недостаточно свободного места. Доступно: ${AVAILABLE_SPACE}ГБ, требуется: ${REQUIRED_SPACE}ГБ (${SWAP_SIZE}ГБ + 1ГБ буфер)"
    fi

    # Try to create swap file, retry if failed
    MAX_SWAP_ATTEMPTS=3
    SWAP_ATTEMPT=1

    while [ $SWAP_ATTEMPT -le $MAX_SWAP_ATTEMPTS ]; do
        if [ $SWAP_ATTEMPT -gt 1 ]; then
            # Clean up any partial files
            sudo rm -f /swapfile 2>/dev/null || true
        fi
        
        # Try to create the file
        if sudo fallocate -l ${SWAP_SIZE}G /swapfile 2>/dev/null; then
            if sudo chmod 600 /swapfile; then
                if sudo mkswap /swapfile 2>/dev/null; then
                    if sudo swapon /swapfile 2>/dev/null; then
                        echo ""
                        echo "✅ Файл подкачки размером ${SWAP_SIZE}Гб создан"
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
        fi
        
        SWAP_ATTEMPT=$((SWAP_ATTEMPT + 1))
        sleep 1
    done

    # Check if swap creation was successful
    if [ $SWAP_ATTEMPT -gt $MAX_SWAP_ATTEMPTS ]; then
        error_exit "Не удалось создать файл подкачки после $MAX_SWAP_ATTEMPTS попыток. Проверьте свободное место на диске и права доступа."
    fi
fi

# Always show final memory and swap status
echo ""
echo "Текущее состояние памяти:"
show_memory_status
echo ""

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mУСТАНОВКА NEXUS CLI\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Check if Nexus CLI is already installed and show version info
if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
    echo "✅ Nexus CLI уже установлен."
    echo ""
    printf "\033[1;32mПроверка последней версии в репозитории...\033[0m\n"
    
    # Get current version
    if NEXUS_VERSION_RAW=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null); then
        NEXUS_VERSION=$(echo "$NEXUS_VERSION_RAW" | sed 's/nexus-network //')
        echo "Текущая версия: $NEXUS_VERSION"
    else
        echo "Текущая версия: не удалось определить"
        NEXUS_VERSION="unknown"
    fi
    
    # Get latest version
    if LATEST_VERSION=$(curl -s https://api.github.com/repos/nexus-xyz/nexus-cli/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E "s/.*\"tag_name\": \"v?([^\"]*)\".*/\\1/"); then
        if [ -n "$LATEST_VERSION" ]; then
            LATEST_VERSION_CLEAN=$(echo "$LATEST_VERSION" | sed 's/^v//')
            CURRENT_VER_CLEAN=$(echo "$NEXUS_VERSION" | sed 's/^v//')
            
            if [ "$NEXUS_VERSION" != "unknown" ] && [ "$CURRENT_VER_CLEAN" != "$LATEST_VERSION_CLEAN" ]; then
                if [[ "$LATEST_VERSION_CLEAN" > "$CURRENT_VER_CLEAN" ]]; then
                    printf "Последняя версия: \033[1;31m%s\033[0m\n" "$LATEST_VERSION_CLEAN"
                else
                    echo "Последняя версия: $LATEST_VERSION_CLEAN"
                fi
            else
                echo "Последняя версия: $LATEST_VERSION_CLEAN"
            fi
        else
            echo "Последняя версия: не удалось определить"
        fi
    else
        echo "Последняя версия: не удалось определить"
    fi
    
    echo ""
    echo "Переустановить Nexus CLI? (Enter = нет, y = да): "
    read REINSTALL_CHOICE </dev/tty
    
    case "${REINSTALL_CHOICE,,}" in
        y|yes|да|д)
            echo ""
            echo "✅ Переустанавливаем Nexus CLI..."
            if update_nexus_cli true false; then
                echo "✅ Nexus CLI успешно переустановлен."
            else
                error_exit "Не удалось переустановить Nexus CLI"
            fi
            ;;
        *)
            echo ""
            echo "✅ Используем существующую установку Nexus CLI."
            ;;
    esac
else
    echo "Nexus CLI не установлен."
    echo "Установка Nexus CLI..."
    if update_nexus_cli false false; then
        echo "✅ Nexus CLI успешно установлен."
    else
        error_exit "Не удалось установить Nexus CLI"
    fi
fi

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПРОВЕРКА СОВМЕСТИМОСТИ СИСТЕМЫ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

# Get OS information
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_NAME="$NAME"
    OS_VERSION="$VERSION_ID"
    echo "✅ Обнаружена ОС: $OS_NAME $OS_VERSION"
    echo ""
else
    warning_message "Не удалось определить версию операционной системы"
    OS_NAME="Unknown"
    OS_VERSION="0"
fi

# Check Ubuntu version compatibility
if [[ "$OS_NAME" == *"Ubuntu"* ]]; then
    # Extract major version number (e.g., "22.04" -> "22")
    UBUNTU_MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d'.' -f1)
    
    printf "\033[1;32mПроверка совместимости Ubuntu $UBUNTU_MAJOR_VERSION с Nexus CLI...\033[0m\n"
    
    if [ "$UBUNTU_MAJOR_VERSION" -lt 22 ]; then
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
        echo "   Nexus CLI работает только на Ubuntu 22.04 и выше"
        echo "   Ваша версия Ubuntu $OS_VERSION не поддерживается"
        echo ""
        printf "\033[1;36m💡 РЕШЕНИЕ ПРОБЛЕМЫ:\033[0m\n"
        echo "   1. Обновите Ubuntu до версии 22.04 LTS или выше"
        echo "   2. Используйте другой сервер с Ubuntu 22.04+"
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

# Load saved Nexus ID if exists
SAVED_NEXUS_ID=$(load_saved_nexus_id)

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
    
    # Show prompt with saved ID if available
    if [ -n "$SAVED_NEXUS_ID" ]; then
        echo "Nexus ID (Enter = $SAVED_NEXUS_ID): "
    else
        echo "Введите ваш Nexus ID: "
    fi
    
    read NEXUS_ID </dev/tty
    
    # Trim whitespace
    NEXUS_ID=$(echo "$NEXUS_ID" | xargs 2>/dev/null || echo "$NEXUS_ID")
    
    # If user didn't enter anything and we have saved ID, use it
    if [ -z "$NEXUS_ID" ] && [ -n "$SAVED_NEXUS_ID" ]; then
        NEXUS_ID="$SAVED_NEXUS_ID"
        echo "✅ Используем сохраненный Nexus ID: $NEXUS_ID"
        echo
    fi
    
    if [ -n "$NEXUS_ID" ]; then
        echo "Получен Nexus ID: $NEXUS_ID"
        
        # Save the ID for future use (only if it's different from saved one)
        if [ "$NEXUS_ID" != "$SAVED_NEXUS_ID" ]; then
            save_nexus_id "$NEXUS_ID"
            echo "✅ Nexus ID сохранен для следующих запусков"
        fi
        
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
        echo "✅ Нода успешно запущена и работает"
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
printf "\033[1;33m✅ Нода Nexus успешно запущена в фоновом режиме\033[0m\n"
echo ""
printf "🆔 Ваш Nexus ID: \033[1;36m$NEXUS_ID\033[0m\n"
echo ""

# Ask about auto-restart before final messages
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32m🔄 АВТОМАТИЧЕСКАЯ ПЕРЕЗАГРУЗКА\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""
echo "Как часто автоматически перезагружать ноду? (Enter = не перезагружать, число = минуты): "
read AUTO_RESTART_MINUTES </dev/tty

# Remove any existing auto-restart cron jobs first
remove_nexus_cron

if [ -n "$AUTO_RESTART_MINUTES" ] && [ "$AUTO_RESTART_MINUTES" -gt 0 ] 2>/dev/null; then
    add_nexus_cron "$AUTO_RESTART_MINUTES" "$NEXUS_ID"
    echo ""
    echo "✅ Нода будет автоматически перезагружаться каждые $AUTO_RESTART_MINUTES минут"
    echo "✅ Автообновление Nexus CLI включено (проверка раз в час)"
else
    echo "✅ Автоматическая перезагрузка отключена"
fi

echo ""
printf "\033[1;33m✅ Вы можете свободно закрывать терминал - нода продолжит работу\033[0m\n"
echo "✅ Проверить статус ноды и начисление очков можно на странице:"
echo "   https://app.nexus.xyz/nodes"
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32m📋 УПРАВЛЕНИЕ НОДОЙ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""
printf "\033[1;31m🔗 Просмотр логов: tmux a -t nexus\033[0m\n"
printf "\033[1;33m🔙 Выход из логов: Ctrl+B, затем D\033[0m\n"
printf "❌ Остановка ноды: tmux kill-session -t nexus\n"
echo ""
printf "\033[1;32m==================================\033[0m\n"
printf "\033[1;32mСкрипт выполнен успешно 🚀\033[0m\n"
printf "\033[1;32m==================================\033[0m\n"