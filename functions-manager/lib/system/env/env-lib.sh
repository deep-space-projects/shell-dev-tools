#!/bin/bash
# ============================================================================
# Common Functions for Container Tools
# Provides platform detection, basic utilities and common functions
# ============================================================================

set -

# Области видимости и их битовые флаги
declare -A SCOPE_FLAGS=(
    ["script"]=1    # 001 - только текущий shell
    ["subprocess"]=2  # 010 - только дочерние процессы
    ["all"]=3       # 011 - и shell и дочерние процессы (1 + 2)
)

check_env_var() {
    local fail_on_unsupported=1
    local var_name=""

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fail)
                fail_on_unsupported=0
                shift
                ;;
            *)
                # Все оставшиеся аргументы - команда/функция и её параметры
                var_name=("$@")
                break
                ;;
        esac
    done

    # Проверяем что var_name не пустой
    if [[ -z "${var_name:-}" ]]; then
        log_warning "Variable name is required"
        return 1
    fi

    # Безопасное получение значения переменной
    local var_value=""
    if [[ -v "${var_name}" ]]; then
        var_value="${!var_name}"
    fi

    if [[ -z "${var_value:-}" ]]; then
        log_warning "Required environment variable '$var_name' is not set"

        if [[ $fail_on_unsupported -eq 0 ]]; then
            exit 1
        fi

        return 1
    fi

    log_debug "Environment variable '$var_name' = '$var_value'"
    return 0
}

# Проверка списка переменных окружения
check_env_vars() {
    local fail_on_missing=false
    local var_names=()

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fail)
                fail_on_missing=true
                shift
                ;;
            *)
                # Все оставшиеся аргументы - имена переменных
                var_names=("$@")
                break
                ;;
        esac
    done

    local missing_vars=()
    local has_errors=false

    # Проверяем каждую переменную
    for var_name in "${var_names[@]}"; do
        if ! check_env_var "$var_name"; then
            missing_vars+=("$var_name")
            has_errors=true
        fi
    done

    # Если есть отсутствующие переменные
    if [[ $has_errors == true ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done

        if [[ $fail_on_missing == true ]]; then
            exit 1
        fi

        return 1
    fi

    log_success "All required environment variables are set"
    return 0
}

set_env_var() {
    local var_name=""
    local var_value=""
    local scope="subprocess"  # значение по умолчанию изменено
    local no_overwrite=0
    local scope_flag

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --scope=*)
                scope="${1#*=}"
                shift
                ;;
            --name=*)
                var_name="${1#*=}"
                shift
                ;;
            --value=*)
                var_value="${1#*=}"
                shift
                ;;
            --no-overwrite)
                no_overwrite=1
                shift
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done

    # Валидация
    if [[ -z "$var_name" ]]; then
        echo "Error: Variable name is required. Use --name=" >&2
        return 1
    fi

    if [[ -z "$var_value" ]]; then
        echo "Error: Variable value is required. Use --value=" >&2
        return 1
    fi

    if [[ -z "${SCOPE_FLAGS[$scope]}" ]]; then
        echo "Error: Invalid scope: $scope. Available: ${!SCOPE_FLAGS[*]}" >&2
        return 1
    fi

    # Проверка на перезапись
    if [[ $no_overwrite -eq 1 ]]; then
        # Проверяем существует ли переменная и не пустая ли она
        if [[ -n "${!var_name+x}" && -n "${!var_name}" ]]; then
            echo "Skip: Variable '$var_name' already exists and is not empty" >&2
            return 0
        fi
    fi

    scope_flag="${SCOPE_FLAGS[$scope]}"

    # Установка в текущем shell (бит 0 установлен)
    if (( scope_flag & 1 )); then
        eval "$var_name=\"\$var_value\""
        echo "Set in current shell: $var_name='$var_value'"
    fi

    # Экспорт для дочерних процессов (бит 1 установлен)
    if (( scope_flag & 2 )); then
        eval "export $var_name=\"\$var_value\""
        echo "Exported for subprocesses: $var_name='$var_value'"
    fi

    return 0
}

set_env_var_quite() {
    local var_name="$1"
    local var_value="$2"
    local scope="${3:-subprocess}"

    # Валидация
    if [[ -z "$var_name" || -z "$var_value" ]]; then
        echo "Usage: set_env_var_quite <name> <value> [scope] [no_overwrite]" >&2
        return 1
    fi

    # Подготавливаем аргументы для set_env_var
    local args=("--name=$var_name" "--value=$var_value" "--scope=$scope")

    # Вызываем основную функцию
    set_env_var "${args[@]}"
}
