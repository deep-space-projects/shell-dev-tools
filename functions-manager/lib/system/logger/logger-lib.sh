#!/bin/bash
# ============================================================================
# Universal Logger for Container Tools
# Provides unified logging with icons and colors across all platforms
# ============================================================================

# Определяем путь к файлу конфигурации рядом с библиотекой
readonly LOGGER_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# загрузка межпроцессной конфигурации
readonly TLOG_CONFIG_DIR="${TLOG_CONFIG_DIR:-$HOME/.config/tlog}"
readonly TLOG_CONFIG_FILE="${TLOG_CONFIG_DIR}/.tlog_config"

if [[ ! -d $TLOG_CONFIG_DIR ]]; then
    echo "Creating config directory for user $(whoami)" >&2
    echo "Logger config directory: $TLOG_CONFIG_DIR" >&2
    echo "Logger config file: $TLOG_CONFIG_FILE" >&2

    mkdir -p $TLOG_CONFIG_DIR
fi

if [[ -f "$TLOG_CONFIG_FILE" ]]; then
    source "$TLOG_CONFIG_FILE"
fi

# Настройки логирования (можно переопределить через переменные окружения)
LOG_LEVEL="${LOG_LEVEL:-${CONFIG_LOG_LEVEL:-INFO}}"
LOG_COLORS="${LOG_COLORS:-true}"
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-true}"

# Определение уровней логирования
declare -A LOG_LEVELS=(
    [TRACE]=0
    [DEBUG]=1
    [INFO]=2
    [SUCCESS]=3
    [WARNING]=4
    [ERROR]=5
)

# Иконки для разных уровней (совместимые с любой ОС)
declare -A LOG_ICONS=(
    [TRACE]="[TRACE] "
    [DEBUG]="[DEBUG] "
    [INFO]="[INFO]  "
    [SUCCESS]="[OK]    "
    [WARNING]="[WARN]  "
    [ERROR]="[ERROR] "
)

TRACE_ESCAPE_PATTERN="^.*$"
DEBUG_ESCAPE_PATTERN="^(?!.*\[TRACE\].*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\].*).*$"
INFO_ESCAPE_PATTERN="^(?!.*\[(TRACE|DEBUG)\].*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\].*).*$"
WARN_ESCAPE_PATTERN="^(?!.*\[(TRACE|DEBUG|INFO|OK)\].*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\].*).*$"
ERROR_ESCAPE_PATTERN="^(?!.*\[(TRACE|DEBUG|INFO|OK|WARN)\].*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\].*).*$"

declare -A LOG_ICONS_ESCAPED=(
    [TRACE]=$TRACE_ESCAPE_PATTERN
    [DEBUG]=$DEBUG_ESCAPE_PATTERN
    [INFO]=$INFO_ESCAPE_PATTERN
    [SUCCESS]=$INFO_ESCAPE_PATTERN
    [WARNING]=$WARN_ESCAPE_PATTERN
    [ERROR]=$ERROR_ESCAPE_PATTERN
)

# Цветовые коды ANSI (если поддерживаются)
declare -A LOG_COLORS_CODES=(
    [TRACE]="\033[0;36m"     # Cyan
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
    local current_level_num
    local message_level_num=${LOG_LEVELS[$level]:-1}

    # Проверяем, является ли LOG_LEVEL числом
    if [[ $LOG_LEVEL =~ ^[0-9]+$ ]]; then
        # LOG_LEVEL - это число, используем его напрямую
        current_level_num=$LOG_LEVEL
    else
        # LOG_LEVEL - это строка (название уровня), ищем в массиве
        current_level_num=${LOG_LEVELS[$LOG_LEVEL]:-1}
    fi

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

log_trace() {
    _log "TRACE" "$@"
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

    # Сохраняем в файл конфигурации для будущих вызовов
    echo "CONFIG_LOG_LEVEL=$new_level" > "$TLOG_CONFIG_FILE"

    export LOG_LEVEL="$new_level"
    log_debug "Log level set to: $LOG_LEVEL"
    return 0
}

log_current_level() {
  if [[ "$1" =~ ^[a-zA-Z]+$ ]]; then
    local current_level_num=${LOG_LEVELS[${1^^}]:-1}

    if [[ $current_level_num -eq -1 ]]; then
      return 1
    fi

    echo $current_level_num
    return 0
  fi

  if [[ "$1" =~ ^[0-5]$ ]]; then
    local current_level
    current_level=$(log_name_by_code $1)

    if [[ $? -ne 0 ]]; then
      return 1
    fi

    echo $current_level
    return 0
  fi

  echo "$1 unknow name/code level type" >&2
  return 1
}

log_max_level_code() {
  local max_code=-1

  for level_name in "${!LOG_LEVELS[@]}"; do
    local current_code=${LOG_LEVELS[$level_name]}
    if [[ $current_code -gt $max_code ]]; then
      max_code=$current_code
    fi
  done

  echo $max_code
}

log_min_level_code() {
  local min_code=999999

  for level_name in "${!LOG_LEVELS[@]}"; do
    local current_code=${LOG_LEVELS[$level_name]}
    if [[ $current_code -lt $min_code ]]; then
      min_code=$current_code
    fi
  done

  echo $min_code
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

log_name_by_code() {
    local target_code=$1

    for level_name in "${!LOG_LEVELS[@]}"; do
        if [[ ${LOG_LEVELS[$level_name]} -eq $target_code ]]; then
            echo "$level_name"
            return 0
        fi
    done

    return 1  # Не найдено
}

log_filter_by_level() {
  if [[ $# == 1 && -n "$1" && ! -z "$1" ]]; then
    # 1) Найти числовое значение переданного уровня
    local input_level_code=${LOG_LEVELS[${1^^}]:-1}
    local input_level_name=${1^^}

    if [[ $input_level_code -eq -1 ]]; then
      echo "Error: Unknown log level '$1'" >&2
      return 1
    fi

    # 2) Получить максимальное числовое значение
    local max_code=$(log_max_level_code)

    # 3) Составить паттерны для всех уровней от переданного до максимального
    local patterns=()
    patterns+=("${LOG_ICONS_ESCAPED[$input_level_name]}")

    # Объединить все паттерны через |
    local combined_pattern
    combined_pattern=$(IFS='|'; echo "${patterns[*]}")

    grep -P "$combined_pattern"
  else
    cat
  fi
}

log_filter_stdout() {
  if [[ $# == 1 && -n "$1" && ! -z "$1" && "$1" == "exclude" ]]; then
    local patterns="^.*\[(TRACE|DEBUG|INFO|OK|WARN)\].*\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\].*$"
    grep -P "$patterns"
  else
    cat
  fi
}
