#!/bin/bash
# ============================================================================
# Common Functions for Container Tools
# Provides platform detection, basic utilities and common functions
# ============================================================================

declare -A EXEC_MODES=(
    [0]="STANDARD"      # Полный запуск
    [1]="SKIP_ALL"      # Пропустить все, только exec команду
    [2]="INIT_ONLY"     # Только инициализация, без основной команды
    [3]="DEBUG"         # Режим отладки с детальными логами
    [4]="DRY_RUN"       # Показать что будет выполнено, но не выполнять
)

declare -A ERROR_POLICY_NAMES=(
    [0]="STRICT"        # Любая ошибка = остановка
    [1]="SOFT"          # Логируем ошибку и продолжаем
    [2]="CUSTOM"        # Настраиваемая политика
)

# ============================================================================
# PLATFORM DETECTION
# ============================================================================

# Определяем тип операционной системы
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID:-unknown}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Определяем семейство ОС
detect_os_family() {
    local os=$(detect_os)

    case "$os" in
        ubuntu|debian)
            echo "debian"
            ;;
        rhel|centos|fedora|ol|rocky|almalinux)
            echo "rhel"
            ;;
        alpine)
            echo "alpine"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Проверяем, является ли система минимальной (BusyBox)
is_minimal_system() {
    # Проверяем наличие BusyBox
    if command -v busybox >/dev/null 2>&1; then
        return 0
    fi

    # Проверяем признаки минимальной системы
    if [[ ! -d /usr/bin ]] || [[ $(ls /usr/bin | wc -l) -lt 10 ]]; then
        return 0
    fi

    return 1
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Проверка существования команды (кроссплатформенная)
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Безопасная проверка переменной окружения
check_env_var() {
    local var_name="$1"
    local var_value="${!var_name}"

    if [[ -z "$var_value" ]]; then
        log_error "Required environment variable '$var_name' is not set"
        return 1
    fi

    log_debug "Environment variable '$var_name' = '$var_value'"
    return 0
}

# Проверка списка переменных окружения
check_required_env_vars() {
    local missing_vars=()

    for var_name in "$@"; do
        local var_value="${!var_name}"
        if [[ -z "$var_value" ]]; then
            missing_vars+=("$var_name")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        return 1
    fi

    log_success "All required environment variables are set"
    return 0
}

# Безопасное создание директории
safe_mkdir() {
    local dir="$1"
    local owner="${2:-}"
    local permissions="${3:-755}"

    if [[ -z "$dir" ]]; then
        log_error "Directory path is required"
        return 1
    fi

    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        if mkdir -p "$dir"; then
            log_success "Directory created: $dir"
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    else
        log_debug "Directory already exists: $dir"
    fi

    # Устанавливаем права если указаны
    if [[ -n "$permissions" ]]; then
        chmod "$permissions" "$dir" || log_warning "Failed to set permissions $permissions on $dir"
    fi

    # Устанавливаем владельца если указан
    if [[ -n "$owner" ]]; then
        chown "$owner" "$dir" || log_warning "Failed to set owner $owner on $dir"
    fi

    return 0
}

# Ожидание готовности файла или директории
wait_for_path() {
    local path="$1"
    local timeout="${2:-30}"
    local check_type="${3:-file}"  # file|dir|any

    log_info "Waiting for $check_type: $path (timeout: ${timeout}s)"

    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        case "$check_type" in
            "file")
                if [[ -f "$path" ]]; then
                    log_success "$check_type ready: $path"
                    return 0
                fi
                ;;
            "dir")
                if [[ -d "$path" ]]; then
                    log_success "$check_type ready: $path"
                    return 0
                fi
                ;;
            "any")
                if [[ -e "$path" ]]; then
                    log_success "Path exists: $path"
                    return 0
                fi
                ;;
        esac

        sleep 1
        elapsed=$((elapsed + 1))

        # Показываем прогресс каждые 10 секунд
        if (( elapsed % 10 == 0 )); then
            log_info "Still waiting for $path... (${elapsed}/${timeout}s)"
        fi
    done

    log_error "Timeout waiting for $check_type: $path"
    return 1
}

# Получение информации о текущем пользователе
get_current_user_info() {
    local current_user=$(whoami 2>/dev/null || echo "unknown")
    local current_uid=$(id -u 2>/dev/null || echo "unknown")
    local current_gid=$(id -g 2>/dev/null || echo "unknown")
    local current_groups=$(id -G 2>/dev/null || echo "unknown")

    log_debug "Current user info:"
    log_debug "  User: $current_user"
    log_debug "  UID: $current_uid"
    log_debug "  GID: $current_gid"
    log_debug "  Groups: $current_groups"

    # Экспортируем переменные для использования в других скриптах
    export CURRENT_USER="$current_user"
    export CURRENT_UID="$current_uid"
    export CURRENT_GID="$current_gid"
}

# ============================================================================
# EXECUTION MODE MANAGEMENT
# ============================================================================

# Получение текущего режима выполнения как строки
get_exec_mode_name() {
    local mode="${1:-$EXEC_MODE}"
    echo "${EXEC_MODES[$mode]:-UNKNOWN}"
}

# Получение текущей политики ошибок как строки
get_error_policy_name() {
    local policy="${1:-$EXEC_ERROR_POLICY}"
    echo "${ERROR_POLICY_NAMES[$policy]:-UNKNOWN}"
}

# Установка политики ошибок
set_error_policy() {
    local policy_name="$1"

    case "$policy_name" in
        "strict")
            export EXEC_ERROR_POLICY=0
            ;;
        "soft")
            export EXEC_ERROR_POLICY=1
            ;;
        "custom")
            export EXEC_ERROR_POLICY=2
            ;;
        *)
            log_error "Invalid error policy: $policy_name"
            log_info "Available policies: strict, soft, custom"
            return 1
            ;;
    esac

    log_debug "Error policy set to: $policy_name"
    return 0
}

# Проверка нужно ли выполнять операцию в текущем режиме
should_execute_in_mode() {
    local operation_type="$1"  # init, exec, dependencies
    local current_mode="${2:-$EXEC_MODE}"  # Можно передать явно или взять из переменной
    local mode_name="${EXEC_MODES[$current_mode]:-UNKNOWN}"

    case "$mode_name" in
        "STANDARD"|"DEBUG")
            return 0  # Выполняем все
            ;;
        "SKIP_ALL")
            if [[ "$operation_type" == "exec" ]]; then
                return 0  # Только exec команду
            else
                return 1  # Пропускаем инициализацию
            fi
            ;;
        "INIT_ONLY")
            if [[ "$operation_type" == "exec" ]]; then
                return 1  # НЕ выполняем exec
            else
                return 0  # Выполняем инициализацию
            fi
            ;;
        "DRY_RUN")
            return 0  # Выполняем все в режиме симуляции
            ;;
        *)
            log_warning "Unknown exec mode: $mode_name, defaulting to STANDARD"
            return 0
            ;;
    esac
}

# ============================================================================
# ERROR HANDLING UTILITIES
# ============================================================================

# Обработка ошибок согласно политике EXEC_ERROR_POLICY
handle_operation_error() {
    local operation_name="$1"
    local error_message="${2:-Operation failed}"
    local exit_code="${3:-1}"

    case "$(get_error_policy_name)" in
        "STRICT")
            log_error "Failed to $operation_name"
            log_error "$error_message"
            exit $exit_code
            ;;
        "SOFT")
            log_warning "Failed to $operation_name, continuing due to soft error policy"
            log_warning "$error_message"
            return 0
            ;;
        "CUSTOM")
            log_warning "Failed to $operation_name (custom error handling)"
            log_warning "$error_message"
            return $exit_code
            ;;
        *)
            log_warning "Failed to $operation_name, unknown error policy: $(get_error_policy_name)"
            log_warning "$error_message"
            return $exit_code
            ;;
    esac
}