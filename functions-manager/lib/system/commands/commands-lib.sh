#!/bin/bash
# ============================================================================
# Common Command Functions
# Provides platform detection, basic utilities and common functions
# ============================================================================


# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Проверка существования команды (кроссплатформенная)
is_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

execute_command() {
    local timeout=""
    local description=""
    local executable_args=()

    # Парсим именованные параметры
    while [[ $# -gt 0 ]]; do
        case $1 in
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            --description=*)
                description="${1#*=}"
                shift
                ;;
            *)
                # Все оставшиеся аргументы - команда/функция и её параметры
                executable_args=("$@")
                break
                ;;
        esac
    done

    # Валидация параметров
    if [[ ${#executable_args[@]} -eq 0 ]]; then
        log_error "Usage: execute_command [--timeout=SECONDS] command [args...]"
        return 1
    fi

    # Если timeout не передан, просто выполняем команду
    if [[ -z "$timeout" ]]; then
        "${executable_args[@]}"
        return $?
    fi

    # Если timeout передан, вызываем execute_command_with_timeout
    execute_command_with_timeout \
        --timeout="$timeout" \
        --description="$description" \
        "${executable_args[@]}"
}


# ============================================================================
# FUNCTION EXECUTION WITH TIMEOUT
# ============================================================================

# Универсальное выполнение команды/функции с таймаутом
# БЫЛО execute_function_with_timeout
execute_command_with_timeout() {
    local timeout=""
    local description=""
    local executable_args=()

    # Парсим именованные параметры
    while [[ $# -gt 0 ]]; do
        case $1 in
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            --description=*)
                description="${1#*=}"
                shift
                ;;
            *)
                # Все оставшиеся аргументы - команда/функция и её параметры
                executable_args=("$@")
                break
                ;;
        esac
    done

    # Валидация параметров
    if [[ -z "$timeout" ]] || [[ ${#executable_args[@]} -eq 0 ]] || [[ -z "$description" ]]; then
        log_error "Usage: execute_command_with_timeout --timeout=SECONDS --description='Description' command [args...]"
        return 1
    fi

    log_info "Executing: $description (timeout: ${timeout}s)"
    log_debug "Command: ${executable_args[*]}"

    # Запускаем в background
    "${executable_args[@]}" &
    local bg_pid=$!

    # Мониторим выполнение
    local elapsed=0
    local status="running"

    while [[ $elapsed -lt $timeout ]] && [[ "$status" == "running" ]]; do
        if ! kill -0 "$bg_pid" 2>/dev/null; then
            status="finished"
            break
        fi

        sleep 1
        elapsed=$((elapsed + 1))

        # Показываем прогресс каждые 30 секунд
        if (( elapsed % 30 == 0 )); then
            log_debug "Still executing '$description'... (${elapsed}/${timeout}s)"
        fi
    done

    local exit_code=0

    if [[ "$status" == "running" ]]; then
        # Таймаут - принудительное завершение
        log_warning "Timeout reached for '$description', terminating..."

        # Сначала мягкое завершение
        if kill -TERM "$bg_pid" 2>/dev/null; then
            # Ждем 5 секунд для graceful shutdown
            local term_wait=0
            while [[ $term_wait -lt 5 ]] && kill -0 "$bg_pid" 2>/dev/null; do
                sleep 1
                term_wait=$((term_wait + 1))
            done
        fi

        # Если не помогло - принудительное завершение
        if kill -0 "$bg_pid" 2>/dev/null; then
            log_warning "Executable didn't respond to SIGTERM, sending SIGKILL"
            kill -KILL "$bg_pid" 2>/dev/null
        fi

        exit_code=124  # Стандартный код для timeout
        log_error "Execution '$description' terminated due to timeout (${timeout}s)"
    else
        # Завершилось нормально
        wait "$bg_pid"
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            log_success "Execution '$description' completed successfully (${elapsed}s)"
        else
            log_error "Execution '$description' failed with exit code $exit_code (${elapsed}s)"
        fi
    fi

    return $exit_code
}

# Экспорт функций
export -f is_command_exists
export -f execute_command execute_command_with_timeout
