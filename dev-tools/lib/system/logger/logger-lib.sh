#!/bin/bash
# ============================================================================
# Universal Logger for Container Tools
# Provides unified logging with icons and colors across all platforms
# ============================================================================

# Настройки логирования (можно переопределить через переменные окружения)
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_COLORS="${LOG_COLORS:-true}"
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-true}"

# Определение уровней логирования
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [SUCCESS]=2
    [WARNING]=3
    [ERROR]=4
)

# Иконки для разных уровней (совместимые с любой ОС)
declare -A LOG_ICONS=(
    [DEBUG]="[DEBUG] "
    [INFO]="[INFO]  "
    [SUCCESS]="[OK]    "
    [WARNING]="[WARN]  "
    [ERROR]="[ERROR] "
)

# Цветовые коды ANSI (если поддерживаются)
declare -A LOG_COLORS_CODES=(
    [DEBUG]="\033[0;36m"     # Cyan
    [INFO]="\033[0;37m"      # White
    [SUCCESS]="\033[0;32m"   # Green
    [WARNING]="\033[0;33m"   # Yellow
    [ERROR]="\033[0;31m"     # Red
    [RESET]="\033[0m"        # Reset
)

# Функция проверки нужно ли логировать сообщение
should_log() {
    local level=$1
    local current_level_num=${LOG_LEVELS[$LOG_LEVEL]:-1}
    local message_level_num=${LOG_LEVELS[$level]:-1}

    [[ $message_level_num -ge $current_level_num ]]
}

# Функция получения timestamp
get_timestamp() {
    if [[ "$LOG_TIMESTAMPS" == "true" ]]; then
        date '+%Y-%m-%d %H:%M:%S'
    fi
}

# Основная функция логирования
_log() {
    local level=$1
    shift
    local message="$*"

    # Проверяем нужно ли логировать
    if ! should_log "$level"; then
        return 0
    fi

    # Формируем компоненты сообщения
    local timestamp=""
    if [[ "$LOG_TIMESTAMPS" == "true" ]]; then
        timestamp="[$(get_timestamp)] "
    fi

    local icon="${LOG_ICONS[$level]}"
    local color_start=""
    local color_end=""

    # Добавляем цвета если включены и терминал поддерживает
    if [[ "$LOG_COLORS" == "true" ]] && [[ -t 1 ]]; then
        color_start="${LOG_COLORS_CODES[$level]}"
        color_end="${LOG_COLORS_CODES[RESET]}"
    fi

    # Выводим сообщение с выравниванием
    printf "${color_start}%s${timestamp}%s${color_end}\n" "$icon" "$message" >&2
}

# Удобные функции для каждого уровня
log_debug() {
    _log "DEBUG" "$@"
}

log_info() {
    _log "INFO" "$@"
}

log_success() {
    _log "SUCCESS" "$@"
}

log_warning() {
    _log "WARNING" "$@"
}

log_error() {
    _log "ERROR" "$@"
}

# Функция для установки уровня логирования
logger_set_level() {
    local new_level="$1"

    # Проверяем что уровень валидный
    if [[ -z "${LOG_LEVELS[$new_level]}" ]]; then
        log_warning "Invalid log level: $new_level"
        log_info "Available levels: ${!LOG_LEVELS[*]}"
        return 1
    fi

    LOG_LEVEL="$new_level"
    log_debug "Log level set to: $LOG_LEVEL"
    return 0
}

# Функция для логирования заголовков (красивые разделители)
log_header() {
    local message="$*"
    local separator=$(printf '=%.0s' $(seq 1 ${#message}))

    log_info ""
    log_info "$separator"
    log_info "$message"
    log_info "$separator"
}

# Функция для логирования этапов
log_step() {
    local step_num="$1"
    shift
    local message="$*"

    log_info "Step $step_num: $message"
}

# Функция логирования с префиксом компонента
log_component() {
    local component="$1"
    local level="$2"
    shift 2
    local message="$*"

    _log "$level" "[$component] $message"
}