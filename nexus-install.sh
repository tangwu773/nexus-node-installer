#!/bin/bash

# Clear the screen for better visibility
clear

echo ""
printf "\033[1;32mNEXUS NODE INSTALLER 🚀\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mАвтоматический установщик ноды Nexus\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"

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
# Parameters: $1 = message, $2 = "begin" | "end" | "beginend" (optional)
process_message() {
    local message="$1"
    local spacing="$2"
    
    # Add empty line before message if begin or beginend
    [[ "$spacing" == "begin" || "$spacing" == "beginend" ]] && echo ""
    
    # Display the message
    printf "\033[1;33m%s\033[0m\n" "$message"
    
    # Add empty line after message if end or beginend
    [[ "$spacing" == "end" || "$spacing" == "beginend" ]] && echo ""
}


# Function to display a success message
# Parameters: $1 = message, $2 = "begin" | "end" | "beginend" (optional)
success_message() {
    local message="$1"
    local spacing="$2"
    
    # Add empty line before message if begin or beginend
    [[ "$spacing" == "begin" || "$spacing" == "beginend" ]] && echo ""
    
    # Display the message
    printf "\033[1;34m%s\033[0m\n" "$message"
    
    # Add empty line after message if end or beginend
    [[ "$spacing" == "end" || "$spacing" == "beginend" ]] && echo ""
}




# Function to check and install a package if missing (improved package detection)
# Parameters: $1 = package name
ensure_package_installed() {
    local pkg="$1"
    local is_installed=false
    
    # Special checks for different package types
    case "$pkg" in
        "build-essential")
            # Check for essential build tools on Debian/Ubuntu
            if command -v gcc &> /dev/null && command -v make &> /dev/null && command -v g++ &> /dev/null; then
                is_installed=true
            elif [ -x "$(command -v apt)" ]; then
                # Additional check via dpkg for Debian-based systems
                if dpkg -l build-essential 2>/dev/null | grep -q "^ii"; then
                    is_installed=true
                fi
            fi
            ;;
        "libssl-dev"|"openssl-devel")
            # Check for SSL development files
            if [ -f "/usr/include/openssl/ssl.h" ] || [ -f "/usr/include/openssl/opensslv.h" ]; then
                is_installed=true
            elif command -v pkg-config &> /dev/null && pkg-config --exists openssl 2>/dev/null; then
                is_installed=true
            fi
            ;;
        "pkg-config"|"pkgconfig")
            # Standard command check works well for pkg-config
            if command -v pkg-config &> /dev/null; then
                is_installed=true
            fi
            ;;
        "protobuf-compiler")
            # Check for protoc compiler
            if command -v protoc &> /dev/null; then
                is_installed=true
            fi
            ;;
        *)
            # Default check for other packages (commands, binaries)
            if command -v "$pkg" &> /dev/null; then
                is_installed=true
            fi
            ;;
    esac
    
    if [ "$is_installed" = true ]; then
        echo "✅ $pkg уже установлен"
        return 0
    fi
    
    # Install the package
    process_message "Устанавливаем $pkg..."
    
    if [ -x "$(command -v apt)" ]; then
        if ! sudo DEBIAN_FRONTEND=noninteractive apt install -y "$pkg" >/dev/null 2>&1; then
            echo "❌ Не удалось установить $pkg"
            return 1
        fi
    else
        echo "❌ Система не поддерживается. Требуется Debian/Ubuntu с менеджером пакетов apt"
        return 1
    fi
    
    success_message "✅ $pkg успешно установлен"
    return 0
}

# Function to save Nexus ID to file
save_nexus_id() {
    local nexus_id="$1"
    local save_file="$HOME/.nexus_installer_config.json"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$save_file")" 2>/dev/null
    
    # Save simple JSON structure
    echo "{\"nexus_id\": \"$nexus_id\"}" > "$save_file" 2>/dev/null
}

# Function to remove existing nexus auto-update cron jobs
remove_nexus_cron() {
    # Remove any existing nexus auto-update cron jobs
    crontab -l 2>/dev/null | grep -v "nexus.*auto.*update" | crontab - 2>/dev/null || true
}

# Function to add auto-update cron job (hourly)
add_nexus_cron() {
    local nexus_id="$1"
    
    # Remove existing cron jobs first
    remove_nexus_cron
    
    # Create auto-update script
    local update_script=$(create_auto_update_script)
    
    # Add hourly cron job (every hour at minute 0)
    local update_cmd="0 * * * * $update_script $nexus_id # nexus auto update"
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "$update_cmd") | crontab -
}

# Function to load saved Nexus ID
load_saved_nexus_id() {
    local save_file="$HOME/.nexus_installer_config.json"
    
    if [ -f "$save_file" ]; then
        # Extract ID from new JSON structure
        jq -r '.nexus_id // empty' "$save_file" 2>/dev/null
    fi
}

# Function to get latest Nexus CLI version from GitHub
# Returns: version string or "Не удалось определить"
get_latest_nexus_version() {
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        # Get data from GitHub API with timeout
        local api_response=$(curl -s --max-time 3 https://api.github.com/repos/nexus-xyz/nexus-cli/releases/latest 2>/dev/null)
        
        # Check if we got valid JSON with tag_name field
        if [ -n "$api_response" ] && echo "$api_response" | jq -e '.tag_name' >/dev/null 2>&1; then
            local version=$(echo "$api_response" | jq -r '.tag_name' | sed 's/^v//')
            
            # Check if version is not empty and looks like a version (contains numbers/dots)
            if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+(\.[0-9]+)*.*$ ]]; then
                echo "$version"
                return 0
            fi
        fi
        
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 2
    done
    
    # If all attempts failed
    echo "не удалось определить"
    return 1
}

# Function to build Nexus CLI from source code
# Returns: 0 = success, 1 = error
build_nexus_from_source() {
    process_message "🔄 Собираем Nexus CLI из исходного кода..."
    
    # Install individual packages using the updated function
    ensure_package_installed "build-essential" || return 1
    ensure_package_installed "libssl-dev" || return 1
    ensure_package_installed "pkg-config" || return 1
    ensure_package_installed "git" || return 1
    ensure_package_installed "protobuf-compiler" || return 1

    # Check if Rust is installed
    if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
        process_message "Устанавливаем Rust..."
        if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable >/dev/null 2>&1; then
            echo "❌ Не удалось установить Rust."
            return 1
        fi
        source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
    fi

    # Clone and build
    local build_dir="$HOME/.nexus_build"
    rm -rf "$build_dir" 2>/dev/null || true
    mkdir -p "$build_dir"

    process_message "Клонируем репозиторий Nexus CLI..."
    if ! git clone https://github.com/nexus-xyz/nexus-cli.git "$build_dir" >/dev/null 2>&1; then
        echo "❌ Не удалось клонировать репозиторий Nexus CLI."
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi

    cd "$build_dir" || return 1
    
    # Navigate to the CLI directory where Cargo.toml is located
    if [ -d "clients/cli" ] && cd "clients/cli" && [ -f "Cargo.toml" ]; then
        # Directory exists and has Cargo.toml - continue
        true
    else
        echo "❌ Не удалось найти clients/cli/Cargo.toml в репозитории."
        cd "$HOME"
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi
    
    source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"

    process_message "Собираем проект (это может занять несколько минут)..."
    if cargo build --release >/dev/null 2>&1; then
        mkdir -p "$HOME/.nexus/bin"
        if [ -f "target/release/nexus-network" ]; then
            cp "target/release/nexus-network" "$HOME/.nexus/bin/"
            chmod +x "$HOME/.nexus/bin/nexus-network"
            
            local build_version=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed 's/nexus-network //' || echo "unknown")
            success_message "✅ Nexus CLI успешно собран из исходного кода (версия: $build_version)." "begin"
            
            cd "$HOME"
            rm -rf "$build_dir" 2>/dev/null || true
            return 0
        else
            echo "❌ Исполняемый файл nexus-network не найден после сборки."
            process_message "Содержимое target/release/:"
            ls -la target/release/ 2>/dev/null || echo "Директория target/release/ не найдена"
            cd "$HOME"
            rm -rf "$build_dir" 2>/dev/null || true
            return 1
        fi
    else
        echo "❌ Ошибка при сборке."
        cd "$HOME"
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi
}

# Function to install Nexus CLI using official script
# Returns: 0 = success, 1 = error
install_nexus_cli() {
    process_message "🔄 Устанавливаем Nexus CLI через официальный скрипт..."

    # Run official installation script
    if curl -sSL https://cli.nexus.xyz/ | sh; then
        # Verify installation
        if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
            local script_version=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed 's/nexus-network //' || echo "unknown")
            success_message "✅ Nexus CLI успешно установлен (версия: $script_version)." "begin"
            return 0
        else
            echo "❌ Установка завершена, но исполняемый файл nexus-network не найден."
            return 1
        fi
    else
        echo "❌ Ошибка при загрузке официального скрипта установки Nexus CLI."
        return 1
    fi
}

# Function to update Nexus CLI using non-interactive mode
# Returns: 0 = success, 1 = error
update_nexus_cli() {
    process_message "🔄 Обновляем Nexus CLI..."

    # Download the install script first
    local installer_dir="$HOME/.nexus"
    local installer_file="$installer_dir/install.sh"
    
    mkdir -p "$installer_dir"
    
    if curl -sSf https://cli.nexus.xyz/ -o "$installer_file" 2>/dev/null; then
        chmod +x "$installer_file"
        
        # Run in non-interactive mode as per README (suppress output)
        if NONINTERACTIVE=1 "$installer_file" >/dev/null 2>&1; then
            # Verify installation
            if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
                local update_version=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed 's/nexus-network //' || echo "unknown")
                success_message "✅ Nexus CLI успешно обновлен (версия: $update_version)."
                rm -f "$installer_file"
                return 0
            else
                echo "❌ Обновление завершено, но исполняемый файл nexus-network не найден."
                rm -f "$installer_file"
                return 1
            fi
        else
            echo "❌ Ошибка при выполнении обновления Nexus CLI."
            rm -f "$installer_file"
            return 1
        fi
    else
        echo "❌ Ошибка при загрузке скрипта установки для обновления."
        return 1
    fi
}

# Function to update Nexus CLI with fallback to source build
# Returns: 0 = success, 1 = error
update_nexus_cli_with_fallback() {
    if update_nexus_cli; then
        return 0
    else
        warning_message "Официальное обновление не удалось. Попробуем сборку из исходного кода..."
        if build_nexus_from_source; then
            return 0
        else
            echo "❌ Не удалось обновить Nexus CLI ни одним из способов."
            return 1
        fi
    fi
}

# Function to create auto-update script
create_auto_update_script() {
    local script_path="$HOME/.nexus/auto_update.sh"
    
    # Create .nexus directory if it doesn't exist
    mkdir -p "$HOME/.nexus" 2>/dev/null
    
    # Create the auto-update script
    cat > "$script_path" << 'AUTO_UPDATE_EOF'
#!/bin/bash

# Auto-update script for Nexus CLI with fallback support (official script priority)
# Arguments: $1 = nexus_id

NEXUS_ID="$1"
CONFIG_FILE="$HOME/.nexus_installer_config.json"

# Function to get current Nexus CLI version
get_current_nexus_version() {
    if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
        $HOME/.nexus/bin/nexus-network --version 2>/dev/null | sed 's/nexus-network //' | sed 's/^v//' || echo "unknown"
    else
        echo "unknown"
    fi
}

# Function to get latest version from GitHub (with retries)
get_latest_nexus_version() {
    local max_attempts=3
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        local api_response=$(curl -s --max-time 3 https://api.github.com/repos/nexus-xyz/nexus-cli/releases/latest 2>/dev/null)
        if [ -n "$api_response" ] && echo "$api_response" | jq -e '.tag_name' >/dev/null 2>&1; then
            local version=$(echo "$api_response" | jq -r '.tag_name' | sed 's/^v//')
            if [ -n "$version" ] && [[ "$version" =~ ^[0-9]+(\.[0-9]+)*.*$ ]]; then
                echo "$version"
                return 0
            fi
        fi
        attempt=$((attempt + 1))
        [ $attempt -le $max_attempts ] && sleep 2
    done
    echo "unknown"
    return 1
}

# Function to load Nexus ID from config
load_saved_nexus_id() {
    if [ -f "$CONFIG_FILE" ]; then
        jq -r '.nexus_id // empty' "$CONFIG_FILE" 2>/dev/null || echo ""
    else
        echo ""
    fi
}

# Function to update via official script (silent)
update_nexus_cli_silent() {
    local installer_dir="$HOME/.nexus"
    local installer_file="$installer_dir/install.sh"
    mkdir -p "$installer_dir"
    if curl -sSf https://cli.nexus.xyz/ -o "$installer_file" 2>/dev/null; then
        chmod +x "$installer_file"
        if NONINTERACTIVE=1 "$installer_file" >/dev/null 2>&1; then
            if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
                rm -f "$installer_file"
                return 0
            fi
        fi
        rm -f "$installer_file"
    fi
    return 1
}

# Function to check and install a package if missing (silent, improved detection)
ensure_package_installed_silent() {
    local pkg="$1"
    local is_installed=false
    
    # Update package repositories silently on first package installation attempt
    if [ ! -f "/tmp/.nexus_auto_update_repos_updated" ]; then
        sudo apt update >/dev/null 2>&1 || true
        touch "/tmp/.nexus_auto_update_repos_updated" 2>/dev/null || true
    fi
    
    # Special checks for different package types (silent)
    case "$pkg" in
        "build-essential")
            if command -v gcc &> /dev/null && command -v make &> /dev/null && command -v g++ &> /dev/null; then
                is_installed=true
            elif [ -x "$(command -v apt)" ]; then
                if dpkg -l build-essential 2>/dev/null | grep -q "^ii"; then
                    is_installed=true
                fi
            fi
            ;;
        "libssl-dev"|"openssl-devel")
            if [ -f "/usr/include/openssl/ssl.h" ] || [ -f "/usr/include/openssl/opensslv.h" ]; then
                is_installed=true
            elif command -v pkg-config &> /dev/null && pkg-config --exists openssl 2>/dev/null; then
                is_installed=true
            fi
            ;;
        "pkg-config"|"pkgconfig")
            if command -v pkg-config &> /dev/null; then
                is_installed=true
            fi
            ;;
        "protobuf-compiler")
            if command -v protoc &> /dev/null; then
                is_installed=true
            fi
            ;;
        *)
            if command -v "$pkg" &> /dev/null; then
                is_installed=true
            fi
            ;;
    esac
    
    if [ "$is_installed" = true ]; then
        return 0
    fi
    
    # Install silently
    if [ -x "$(command -v apt)" ]; then
        sudo DEBIAN_FRONTEND=noninteractive apt install -y "$pkg" >/dev/null 2>&1 || return 1
    else
        return 1
    fi
    return 0
}

# Function to build from source (robust, silent)
build_nexus_from_source_silent() {
    # Install build dependencies one by one, silent
    ensure_package_installed_silent "build-essential" || return 1
    ensure_package_installed_silent "libssl-dev" || return 1
    ensure_package_installed_silent "pkg-config" || return 1
    ensure_package_installed_silent "git" || return 1
    ensure_package_installed_silent "protobuf-compiler" || return 1

    # Check if Rust is installed
    if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable >/dev/null 2>&1
        source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
    fi

    # Clone and build
    local build_dir="$HOME/.nexus_build_auto"
    rm -rf "$build_dir" 2>/dev/null || true
    mkdir -p "$build_dir"
    if ! git clone https://github.com/nexus-xyz/nexus-cli.git "$build_dir" >/dev/null 2>&1; then
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi
    cd "$build_dir" || return 1
    if [ -d "clients/cli" ] && cd "clients/cli" && [ -f "Cargo.toml" ]; then
        true
    else
        cd "$HOME"
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi
    source "$HOME/.cargo/env" 2>/dev/null || export PATH="$HOME/.cargo/bin:$PATH"
    if cargo build --release >/dev/null 2>&1; then
        mkdir -p "$HOME/.nexus/bin"
        if [ -f "target/release/nexus-network" ]; then
            cp "target/release/nexus-network" "$HOME/.nexus/bin/"
            chmod +x "$HOME/.nexus/bin/nexus-network"
            cd "$HOME"
            rm -rf "$build_dir" 2>/dev/null || true
            return 0
        else
            cd "$HOME"
            rm -rf "$build_dir" 2>/dev/null || true
            return 1
        fi
    else
        cd "$HOME"
        rm -rf "$build_dir" 2>/dev/null || true
        return 1
    fi
}

# Main auto-update logic (silent)
main() {
    if [ -z "$NEXUS_ID" ]; then
        NEXUS_ID=$(load_saved_nexus_id)
    fi
    if [ -z "$NEXUS_ID" ]; then
        exit 0
    fi
    CURRENT_VERSION=$(get_current_nexus_version_silent)
    LATEST_VERSION=$(get_latest_nexus_version_silent)
    if [ "$CURRENT_VERSION" != "unknown" ] && [ "$LATEST_VERSION" != "unknown" ] && [ "$CURRENT_VERSION" != "$LATEST_VERSION" ]; then
        tmux kill-session -t nexus 2>/dev/null || true
        pkill -f "nexus-network" 2>/dev/null || true
        sleep 3
        if update_nexus_cli_silent || build_nexus_from_source_silent; then
            if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
                sleep 2
                tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID" 2>/dev/null
            fi
        fi
    fi
}

main
AUTO_UPDATE_EOF
    
    # Make the script executable
    chmod +x "$script_path"
    
    echo "$script_path"
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
        echo "├──────────────────┼──────────┼──────────┼──────────┤"
        free -h | awk '
        /^Swap:/ {
            total = $2; gsub(/Gi/, "Гб", total); gsub(/Mi/, "Мб", total); gsub(/Ki/, "Кб", total);
            used = $3; gsub(/Gi/, "Гб", used); gsub(/Mi/, "Мб", used); gsub(/Ki/, "Кб", used);
            free = $4; gsub(/Gi/, "Гб", free); gsub(/Mi/, "Мб", free); gsub(/Ki/, "Кб", free);
            printf "│ Подкачка (Swap)  │ %8s │ %8s │ %8s │\n", total, used, free
        }'
        echo "└──────────────────┴──────────┴──────────┴──────────┘"
    else
        echo "├──────────────────┼──────────┴──────────┴──────────┤"
        echo "│ Подкачка (Swap)  │         НЕ ИСПОЛЬЗУЕТСЯ        │"
        echo "└──────────────────┴────────────────────────────────┘"
    fi
}


# Check and stop existing tmux sessions first (before swap operations)
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mПРОВЕРКА УСТАНОВЛЕННОГО ПО\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

# Update package repositories first
process_message "Обновляем списки пакетов..."
if ! sudo apt update >/dev/null 2>&1; then
    warning_message "Не удалось обновить списки пакетов. Продолжаем с текущими репозиториями."
else
    success_message "✅ Списки пакетов обновлены."
fi

# Check if tmux, cron, jq is installed first
ensure_package_installed "tmux"
ensure_package_installed "cron"
ensure_package_installed "jq"

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mОСТАНОВКА ЗАПУЩЕННЫХ ПРОЦЕССОВ NEXUS CLI\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

# Check if tmux session "nexus" already exists and kill it before swap operations
process_message "Поиск запущенных tmux сессий с именем 'nexus'..."

if tmux has-session -t nexus 2>/dev/null; then
    success_message "⚠️ Обнаружена работающая сессия tmux c именем 'nexus'"
    process_message "Завершаем сессию для безопасной работы с файлом подкачки..."
    
    if tmux kill-session -t nexus 2>/dev/null; then
        success_message "✅ Существующая tmux сессия успешно завершена." "end"
    else
        warning_message "Не удалось завершить существующую tmux сессию"
    fi
    sleep 2  # Wait for processes to fully terminate
else
    success_message "✅ Активных tmux сессий 'nexus' не обнаружено." "end"
fi

# Check for any running Nexus processes outside tmux sessions
process_message "Поиск запущенных процессов Nexus вне сессий..."
NEXUS_PROCESSES=$(pgrep -f "nexus-network" 2>/dev/null || true)

if [ -n "$NEXUS_PROCESSES" ]; then
    success_message "⚠️ Обнаружены запущенные процессы Nexus вне tmux сессий:"
    echo ""
    # Show running processes for user information
    ps aux | grep -E "nexus-network|nexus-cli" | grep -v grep | while read line; do
        echo "   $line"
    done
    echo ""
    process_message "Завершаем процессы Nexus для безопасной работы с файлом подкачки..."

    # First try graceful termination
    if pkill -TERM -f "nexus-network" 2>/dev/null; then
        process_message "Мягкое завершение процессов Nexus..."
        sleep 3
    fi
    
    # Check if processes still running and force kill if needed
    REMAINING_PROCESSES=$(pgrep -f "nexus-network" 2>/dev/null || true)
    if [ -n "$REMAINING_PROCESSES" ]; then
        process_message "Принудительное завершение оставшихся процессов..."
        pkill -KILL -f "nexus-network" 2>/dev/null || true
        sleep 2
    fi
    
    # Final check
    FINAL_CHECK=$(pgrep -f "nexus-network" 2>/dev/null || true)
    if [ -z "$FINAL_CHECK" ]; then
        success_message "✅ Все процессы Nexus успешно завершены."
    else
        warning_message "Некоторые процессы Nexus могут все еще работать"
    fi
else
    success_message "✅ Запущенных процессов Nexus вне сессий не обнаружено."
fi

# Ask for swap file size in GB
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mНАСТРОЙКА ФАЙЛА ПОДКАЧКИ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

echo "Текущее состояние оперативной памяти и файла подкачки:"
show_memory_status
echo ""

# Ask for swap size with validation
SWAP_SIZE=""
ATTEMPT=1
MAX_ATTEMPTS=10

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
    echo "Размер файла подкачки в ГБ (Enter = 12ГБ, 0 = не создавать): "
    read SWAP_SIZE </dev/tty
    
    # Trim whitespace
    SWAP_SIZE=$(echo "$SWAP_SIZE" | xargs 2>/dev/null || echo "$SWAP_SIZE")
    
    # If user didn't enter anything, use default
    if [ -z "$SWAP_SIZE" ]; then
        SWAP_SIZE="12"
        success_message "✅ Используем значение по умолчанию: ${SWAP_SIZE}ГБ"
        break
    fi
    
    # Check if SWAP_SIZE is a valid number (only digits) and within reasonable range (0-128)
    if [ -n "$SWAP_SIZE" ] && [[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] && [ "$SWAP_SIZE" -ge 0 ] && [ "$SWAP_SIZE" -le 128 ]; then
        if [ "$SWAP_SIZE" = "0" ]; then
            success_message "✅ Файл подкачки не нужен" "begin"
        else
            success_message "✅ Создать файл подкачки размером ${SWAP_SIZE}Гб" "begin"
        fi
        break
    else
        # Silent retry - just clear the invalid input
        SWAP_SIZE=""
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

if [ -z "$SWAP_SIZE" ]; then
    error_exit "Размер файла подкачки должен быть числом от 0 до 128. Запустите скрипт заново и введите корректное значение."
fi

echo ""
sleep 1

# Remove existing swap file if it exists
if [ -f /swapfile ]; then
    process_message "Отключаем и удаляем текущий файл подкачки..."
    
    # Disable all swap and kill processes using it
    sudo swapoff -a 2>/dev/null
    sudo fuser -k /swapfile 2>/dev/null || true
    sleep 2
    
    # Remove the file
    if ! sudo rm -f /swapfile 2>/dev/null; then
        error_exit "Не удалось удалить существующий файл подкачки /swapfile. Возможно, файл используется системным процессом. Попробуйте перезагрузить сервер."
    fi
    
    success_message "✅ Файл подкачки успешно отключен и удален"
    sleep 1
fi

# Check if user wants to skip swap creation
if [ "$SWAP_SIZE" = "0" ]; then
    # Don't output anything for swap=0 case
    true
else
    # Create swap file with single attempt
    process_message "Создаем новый файл подкачки размером ${SWAP_SIZE}Гб..."
    sleep 1

    # Check available disk space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print int($4/1024/1024)}')
    REQUIRED_SPACE=$((SWAP_SIZE + 1))  # Add 1GB buffer

    if [ $AVAILABLE_SPACE -lt $REQUIRED_SPACE ]; then
        error_exit "❌ Недостаточно свободного места. Доступно: ${AVAILABLE_SPACE}ГБ, требуется: ${REQUIRED_SPACE}ГБ (${SWAP_SIZE}ГБ + 1ГБ буфер)"
    fi

    # Create and configure swap file
    if sudo fallocate -l ${SWAP_SIZE}G /swapfile 2>/dev/null && \
       sudo chmod 600 /swapfile && \
       sudo mkswap /swapfile >/dev/null 2>&1 && \
       sudo swapon /swapfile >/dev/null 2>&1; then
        success_message "✅ Файл подкачки размером ${SWAP_SIZE}Гб создан"
        sleep 1
    else
        # Clean up failed attempt and exit with error
        sudo rm -f /swapfile 2>/dev/null || true
        error_exit "Не удалось создать файл подкачки. Проверьте свободное место на диске и права доступа."
    fi
fi

# Always show final memory and swap status
echo ""
echo "Текущее состояние памяти:"
show_memory_status

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mУСТАНОВКА NEXUS CLI\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

# Check if Nexus CLI is already installed and show version info
if [ -f "$HOME/.nexus/bin/nexus-network" ]; then
    echo "✅ Nexus CLI уже установлен."
    process_message "Проверка последней версии в репозитории..." "begin"
    
    # Get current version
    if NEXUS_VERSION_RAW=$($HOME/.nexus/bin/nexus-network --version 2>/dev/null); then
        NEXUS_VERSION=$(echo "$NEXUS_VERSION_RAW" | sed 's/nexus-network //')
        echo "Текущая версия: $NEXUS_VERSION"
    else
        echo "Текущая версия: не удалось определить"
        NEXUS_VERSION="unknown"
    fi
    
    # Get latest version
    LATEST_VERSION=$(get_latest_nexus_version)
    
    # Show latest version with red color if update is available
    if [ "$NEXUS_VERSION" != "unknown" ] && [ "$NEXUS_VERSION" != "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "не удалось определить" ]; then
        printf "Последняя версия: \033[1;31m%s\033[0m\n" "$LATEST_VERSION"
    else
        echo "Последняя версия: $LATEST_VERSION"
    fi
    
    echo ""
    
    # Determine default action based on version comparison
    if [ "$NEXUS_VERSION" != "unknown" ] && [ "$NEXUS_VERSION" != "$LATEST_VERSION" ] && [ "$LATEST_VERSION" != "не удалось определить" ]; then
        # New version available - default is to update
        echo "Переустановить Nexus CLI? (Enter = да, n = нет): "
        read REINSTALL_CHOICE </dev/tty
        
        case "${REINSTALL_CHOICE,,}" in
            n|no|нет|н)
                success_message "✅ Используем существующую установку Nexus CLI." "begin"
                ;;
            *)
                success_message "✅ Переустанавливаем Nexus CLI." "beginend"
                if update_nexus_cli_with_fallback; then
                    true
                else
                    warning_message "Не удалось переустановить Nexus CLI."
                fi
                ;;
        esac
    else
        # No new version or version unknown - default is not to update
        echo "Переустановить Nexus CLI? (Enter = нет, y = да): "
        read REINSTALL_CHOICE </dev/tty
        
        case "${REINSTALL_CHOICE,,}" in
            y|yes|да|д)
                success_message "✅ Переустанавливаем Nexus CLI." "beginend"
                if update_nexus_cli_with_fallback; then
                    true
                else
                    warning_message "Не удалось переустановить Nexus CLI."
                fi
                ;;
            *)
                success_message "✅ Используем существующую установку Nexus CLI." "begin"
                ;;
        esac
    fi
else
    if install_nexus_cli; then
        # Success message is already shown by the function
        true
    else
        warning_message "Официальный скрипт установки не удался. Попробуем сборку из исходного кода..."
        if build_nexus_from_source; then
            true
        else
            error_exit "Не удалось установить Nexus CLI ни одним из способов. Скрипт остановлен."
        fi
    fi
fi
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mВВОД NEXUS ID\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

# Display instructions for obtaining Nexus ID
process_message "ВАЖНО: Получите ваш Nexus ID" "end"

echo "1. Откройте браузер и перейдите на: https://app.nexus.xyz/nodes"
echo "2. Войдите в свой аккаунт (кнопка Sign In)" 
echo "3. Нажмите кнопку 'Add CLI Node'"
echo "4. Скопируйте появившиеся цифры - это ваш Nexus ID"
echo ""

# Load saved Nexus ID if exists
SAVED_NEXUS_ID=$(load_saved_nexus_id)

# Ask for Nexus ID with silent validation
NEXUS_ID=""
ATTEMPT=1
MAX_ATTEMPTS=10

while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
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
        success_message "✅ Используем сохраненный Nexus ID"
        break
    fi
    
    # Check if NEXUS_ID is a number (only digits)
    if [ -n "$NEXUS_ID" ] && [[ "$NEXUS_ID" =~ ^[0-9]+$ ]]; then
        success_message "✅ Получен Nexus ID: $NEXUS_ID" "begin"

        # Save the ID for future use (only if it's different from saved one)
        if [ "$NEXUS_ID" != "$SAVED_NEXUS_ID" ]; then
            save_nexus_id "$NEXUS_ID"
            success_message "✅ Nexus ID сохранен для следующих запусков"
        fi
        
        break
    else
        # Silent retry - just clear the invalid input
        NEXUS_ID=""
    fi
    
    ATTEMPT=$((ATTEMPT + 1))
done

if [ -z "$NEXUS_ID" ]; then
    error_exit "Nexus ID должен содержать только цифры. Запустите скрипт заново и явведите корректный Nexus ID."
fi

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mЗАПУСК НОДЫ NEXUS\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""

# Start a tmux session named "nexus" and run the command
process_message "Запуск сессии tmux с Nexus CLI..."

if tmux new-session -d -s nexus "$HOME/.nexus/bin/nexus-network start --node-id $NEXUS_ID" 2>/dev/null; then
    success_message "✅ Сессия tmux 'nexus' успешно запущена."
    
    # Wait a moment and check if the session is still running
    process_message "Проверяем, не завершилась ли сессия с ошибкой..."
    sleep 3
    if tmux has-session -t nexus 2>/dev/null; then
        success_message "✅ Сессия работает стабильно."
    else
        error_exit "Сессия tmux завершилась неожиданно."
    fi
else
    error_exit "Не удалось создать tmux сессию. Cкрипт остановлен."
fi


# Ask about auto-update before final messages
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mАВТОМАТИЧЕСКОЕ ОБНОВЛЕНИЕ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""


# Remove any existing auto-update cron jobs first
remove_nexus_cron

echo "Включить автообновление? (Enter = да, n = нет): "
read AUTO_UPDATE_CHOICE </dev/tty

case "${AUTO_UPDATE_CHOICE,,}" in
    n|no|нет|н)
        success_message "✅ Автоматическое обновление отключено"
        ;;
    *)
        add_nexus_cron "$NEXUS_ID"
        success_message "✅ Автоматическое обновление включено (проверка каждый час)"
        ;;
esac

echo ""
printf "\033[1;32m==================================\033[0m\n"
printf "\033[1;32mУСТАНОВКА ЗАВЕРШЕНА УСПЕШНО 🎉\033[0m\n"
printf "\033[1;32m==================================\033[0m\n"
echo ""

printf "✅ Нода Nexus успешно запущена в фоновом режиме\n"
echo ""
printf "🆔 Ваш Nexus ID: \033[1;36m$NEXUS_ID\033[0m\n"
echo ""
printf "\033[1;36m✅ Вы можете свободно закрывать терминал - нода продолжит работу\033[0m\n"
echo ""
echo "Проверить статус ноды и начисление очков можно на странице:"
echo "https://app.nexus.xyz/nodes"

echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32mУПРАВЛЕНИЕ НОДОЙ\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
echo ""
printf "\033[1;36m🔗 Просмотр логов: \033[1;37mtmux a -t nexus\033[0m\n"
printf "\033[1;36m🔙 Выход из логов: \033[1;37mCtrl+B, затем D\033[0m\n"
printf "\033[1;36m❌ Остановка ноды: \033[1;37mtmux kill-session -t nexus\033[0m\n"
echo ""
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"
printf "\033[1;32m================================================\033[0m\n"