#!/bin/bash
# ============================================================================
# Process Management for Container Tools
# Handles timeouts, user switching, safe script execution, and final command exec
# ============================================================================
# ============================================================================
# SAFE SCRIPT EXECUTION
# ============================================================================

# Безопасное выполнение скрипта с обработкой ошибок
execute_script() {
    local script_path=""
    local error_policy=$(get_current_error_policy)
    local timeout="0"  # 0 = без таймаута для init скриптов
    local description=""
    local operation_name="Script safe execution"

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --script-path=*|--path=*)
                script_path="${1#*=}"
                shift
                ;;
            --error-policy=*|--policy=*)
                error_policy="${1#*=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            --description=*|--desc=*)
                description="${1#*=}"
                shift
                ;;
            --operation-name=*|--operation=*)
                operation_name="${1#*=}"
                shift
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done

    log_debug "SCRIPT EXECUTION"
    log_debug "Directory: $scripts_dir"
    log_debug "Error policy: $error_policy"
    log_debug "Timeout: $timeout"
    log_debug "Description: $description"
    log_debug "Operation name: $operation_name"

    # Устанавливаем описание по умолчанию если не задано
    if [[ -z "$description" ]]; then
        description=$(basename "$script_path")
    fi

    # Валидация обязательных параметров
    if [[ -z "$script_path" ]]; then
        local error_msg="Error: Script path is required. Use --script-path="
        return $(handle_operation_error_quite $operation_name $error_msg 1)
    fi

    if [[ ! -f "$script_path" ]]; then
        local error_msg="Script not found: $script_path"
        return $(handle_operation_error_quite $operation_name $error_msg 1)
    fi

    if [[ ! -x "$script_path" ]]; then
        log_debug "Making script executable: $script_path"
        chmod +x "$script_path" 2>/dev/null || {
            log_warning "Could not make script executable: $script_path"
        }
    fi

    local exit_code=0

    # Определяем как запускать скрипт
    local interpreter=""
    if [[ "$script_path" == *.sh ]]; then
        interpreter="/bin/bash"
    fi

    # Выполняем скрипт
    if [[ -n "$timeout" ]] && [[ "$timeout" -gt 0 ]]; then
        if [[ -n "$interpreter" ]]; then
            execute_command --timeout="$timeout" --description="$description" "$interpreter" "$script_path"
        else
            execute_command --timeout="$timeout" --description="$description"  "$script_path"
        fi
        exit_code=$?
    else
        log_info "Executing script: $description"
        if [[ -n "$interpreter" ]]; then
            "$interpreter" "$script_path"
        else
            "$script_path"
        fi
        exit_code=$?
    fi

    # Обрабатываем результат согласно политике ошибок
    if [[ $exit_code -ne 0 ]]; then
        local error_msg="Script '$description' failed with exit code $exit_code"
        return $(handle_operation_error_quite $operation_name $error_msg $exit_code)
    else
        log_success "Script '$description' completed successfully"
    fi

    return $exit_code
}

# Выполнение всех скриптов в директории
execute_scripts_in_directory() {
    local scripts_dir=""
    local error_policy=$(get_current_error_policy)
    local timeout=0
    local operation_name="Script safe execution"
    local pattern="*.sh"

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --script-path=*|--path=*)
                scripts_dir="${1#*=}"
                shift
                ;;
            --error-policy=*|--policy=*)
                error_policy="${1#*=}"
                shift
                ;;
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            --pattern=*)
                pattern="${1#*=}"
                shift
                ;;
            --operation-name=*|--operation=*)
                operation_name="${1#*=}"
                shift
                ;;
            *)
                echo "Error: Unknown argument: $1" >&2
                return 1
                ;;
        esac
    done

    log_debug "SCRIPT(S) EXECUTION"
    log_debug "Directory: $scripts_dir"
    log_debug "Error policy: $error_policy"
    log_debug "Timeout: $timeout (global)"
    log_debug "Pattern: $pattern"
    log_debug "Operation name: $operation_name"

    if [[ -z "$scripts_dir" ]]; then
        log_error "Scripts directory is required"
        return 1
    fi

    if [[ ! -d "$scripts_dir" ]]; then
        log_debug "Scripts directory does not exist: $scripts_dir"
        return 0
    fi

    # Применяем глобальный таймаут если задан
    if [[ -n "$timeout" ]] && [[ "$timeout" -gt 0 ]]; then
        log_info "Executing scripts with global timeout: ${timeout}s"
        execute_command --timeout="$timeout" --description="Execute scripts in $scripts_dir" __execute_all_scripts "$scripts_dir" "$error_policy" "$pattern"
        return $?
    else
        # Выполняем без глобального таймаута
        __execute_all_scripts "$scripts_dir" "$error_policy" "$pattern"
        return $?
    fi

}

# Внутренняя функция для выполнения всех скриптов без глобального таймаута
__execute_all_scripts() {
    local scripts_dir="$1"
    local error_policy="$2"
    local pattern="$3"

    log_info "Executing scripts from: $scripts_dir"

    # Получаем список скриптов в лексикографическом порядке
    local scripts=()
    while IFS= read -r -d '' script; do
        scripts+=("$script")
    done < <(find "$scripts_dir" -maxdepth 1 -name "$pattern" -type f -print0 | sort -z)

    if [[ ${#scripts[@]} -eq 0 ]]; then
        log_info "No scripts found in: $scripts_dir"
        return 0
    fi

    log_info "Found ${#scripts[@]} scripts to execute"

    local failed_scripts=()
    local total_executed=0

    for script in "${scripts[@]}"; do
        local script_name=$(basename "$script")
        total_executed=$((total_executed + 1))

        log_step "$total_executed" "Executing $script_name"

        # Выполняем скрипт БЕЗ индивидуального таймаута (timeout=0)
        if ! execute_script \
                --script-path="$script" \
                --error-policy="$error_policy" \
                --timeout="0" \
                --operation-name="$script_name"; then
            failed_scripts+=("$script_name")

            # Для STRICT политики прерываем выполнение
            if [[ "$(get_error_policy_name_by_code "$error_policy")" == "STRICT" ]]; then
                log_error "Stopping execution due to strict error policy"
                break
            fi
        fi
    done

    # Итоговая сводка
    local successful=$((total_executed - ${#failed_scripts[@]}))
    log_info "Scripts execution summary: $successful/$total_executed successful"

    if [[ ${#failed_scripts[@]} -gt 0 ]]; then
        log_warning "Failed scripts: ${failed_scripts[*]}"

        if [[ "$(get_error_policy_name_by_code "$error_policy")" == "STRICT" ]]; then
            return 1
        fi
    fi

    return 0
}

# Экспорт функций
export -f execute_script execute_scripts_in_directory