#!/bin/bash
# ============================================================================
# Universal Docker Entrypoint
# Orchestrates all initialization modules and executes final command
# ============================================================================

set -euo pipefail

# ============================================================================
# BASH REQUIREMENT CHECK
# ============================================================================

# Проверяем наличие bash - обязательное требование
if ! command -v bash >/dev/null 2>&1; then
    echo "❌ ERROR: bash is required but not found"
    echo ""
    echo "Please install bash in your container:"
    echo "  Alpine:        RUN apk add --no-cache bash"
    echo "  Debian/Ubuntu: RUN apt-get update && apt-get install -y bash"
    echo "  RHEL/CentOS:   RUN yum install -y bash"
    echo "  Rocky/Alma:    RUN dnf install -y bash"
    echo ""
    exit 1
fi

# Проверяем обязательную переменную CONTAINER_TOOLS
if [[ -z "${CONTAINER_TOOLS:-}" ]]; then
    echo "❌ ERROR: CONTAINER_TOOLS environment variable is not set"
    echo ""
    echo "This variable should be set in your Dockerfile:"
    echo "  ENV CONTAINER_TOOLS=/opt/container-tools"
    echo ""
    exit 1
fi

# ============================================================================
# BOOTSTRAP AND DEPENDENCIES
# ============================================================================

# Используем абсолютные пути через CONTAINER_TOOLS
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# ============================================================================
# ENTRYPOINT CONFIGURATION
# ============================================================================

# Стандартные переменные окружения с значениями по умолчанию
export EXEC_MODE="${EXEC_MODE:-0}"
export EXEC_ERROR_POLICY="${EXEC_ERROR_POLICY:-0}"
export DEPENDENCY_TIMEOUT="${DEPENDENCY_TIMEOUT:-300}"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

# Выполнение модуля с проверкой режима
execute_module() {
    local module_name="$1"
    local operation_type="$2"  # init, dependencies, exec
    local module_path="$MODULES_DIR/$module_name"

    # Проверяем нужно ли выполнять в текущем режиме
    if ! should_execute_in_mode "$operation_type" "$EXEC_MODE"; then
        tlog info "Skipping module $module_name due to exec mode: $(cmn modes get-exec)"
        return 0
    fi

    # Проверяем существование модуля
    if [[ ! -f "$module_path" ]]; then
        local error_msg="Module not found: $module_path"
        case "$(modes err-policy current)" in
            "STRICT")
                tlog error "$error_msg"
                return 1
                ;;
            "SOFT"|"CUSTOM")
                tlog warning "$error_msg (continuing due to error policy)"
                return 0
                ;;
        esac
    fi

    tlog info ""
    tlog step "$(basename "$module_name" .sh | cut -d'-' -f1)" "Executing module: $module_name"

    # Выполняем модуль через bash
    if bash "$module_path"; then
        tlog success "Module completed: $module_name"
        return 0
    else
        local exit_code=$?
        local error_msg="Module failed: $module_name (exit code: $exit_code)"
        operations hendle-quite $module_name $error_msg $exit_code
        return $?
    fi
}

# Валидация обязательных переменных окружения
validate_environment() {
    tlog info "Validating environment configuration..."

    local required_vars=(
        "CONTAINER_USER"
        "CONTAINER_UID"
        "CONTAINER_GID"
        "CONTAINER_NAME"
        "CONTAINER_TOOLS"
        "CONTAINER_TEMP"
        "CONTAINER_ENTRYPOINT_SCRIPTS"
        "CONTAINER_ENTRYPOINT_CONFIGS"
        "CONTAINER_ENTRYPOINT_DEPENDENCIES"
    )

    local optional_vars=(
        "CONTAINER_GROUP"
        "EXEC_MODE"
        "EXEC_ERROR_POLICY"
        "DEPENDENCY_TIMEOUT"
        "CONTAINER_WORKING_DIRS"
        "CONTAINER_WORKING_DIRS_RESTRICTIONS"
    )

    # Проверяем обязательные переменные
    if ! envs check-all "${required_vars[@]}"; then
        tlog error "Environment validation failed"
        return 1
    fi

    # Логируем опциональные переменные
    for var in "${optional_vars[@]}"; do
        local value="${!var:-<not set>}"
        tlog debug "Optional variable: $var=$value"
    done

    # Валидируем значения режимов
    local mode_name=$(modes exec-mode current)
    local policy_name=$(modes err-policy current)

    if [[ "$mode_name" == "UNKNOWN" ]]; then
        tlog warning "Unknown EXEC_MODE: $EXEC_MODE, defaulting to STANDARD"
        export EXEC_MODE=0
    fi

    if [[ "$policy_name" == "UNKNOWN" ]]; then
        tlog warning "Unknown EXEC_ERROR_POLICY: $EXEC_ERROR_POLICY, defaulting to STRICT"
        export EXEC_ERROR_POLICY=0
    fi

    tlog success "Environment validation completed"
    tlog info "Execution mode: $mode_name"
    tlog info "Error policy: $policy_name"

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
            tlog_warning "Unknown exec mode: $mode_name, defaulting to STANDARD"
            return 0
            ;;
    esac
}

# ============================================================================
# MAIN ENTRYPOINT LOGIC
# ============================================================================

main() {
    local start_time=$(date +%s)

    # Заголовок
    tlog header "UNIVERSAL DOCKER ENTRYPOINT"
    tlog info "Container: $CONTAINER_NAME"
    tlog info "Target user: $CONTAINER_USER (UID: $CONTAINER_UID, GID: $CONTAINER_GID)"
    tlog info "Execution mode: $(cmn modes get-exec) (EXEC_MODE=$EXEC_MODE)"
    tlog info "Error policy: $(cmn modes get-err) (EXEC_ERROR_POLICY=$EXEC_ERROR_POLICY)"

    # Сохраняем аргументы командной строки для финального exec
    local final_command="$*"
    if [[ -z "$final_command" ]]; then
        tlog error "No command specified to execute"
        tlog error "Usage: $0 <command> [args...]"
        return 1
    fi

    # Экспортируем финальную команду для модуля 99-exec-command.sh
    export ENTRYPOINT_FINAL_COMMAND="$final_command"

    tlog info "Final command: $final_command"
    tlog info ""

    # Проверяем режим SKIP_ALL
    if [[ "$(cmn modes get-exec)" == "SKIP_ALL" ]]; then
        tlog warning "SKIP_ALL mode: jumping directly to command execution"
        exec_final_command "$CONTAINER_USER" "$final_command"
        return $?
    fi

    # Валидация окружения
    if ! validate_environment; then
        tlog error "Environment validation failed, cannot continue"
        return 1
    fi

    # ========================================================================
    # ВЫПОЛНЕНИЕ МОДУЛЕЙ В ПОРЯДКЕ
    # ========================================================================

    tlog header "INITIALIZATION PHASE"

    # Модуль 00: Проверка окружения
    if ! execute_module "00-environment.sh" "init"; then
        tlog error "Environment module failed"
        return 1
    fi

    # Модуль 10: Настройка прав доступа
    if ! execute_module "10-permissions.sh" "init"; then
        tlog error "Permissions module failed"
        return 1
    fi

    # Модуль 11: Настройка прав доступа для рабочих директорий
    if ! execute_module "11-working-directories-permissions.sh" "init"; then
        tlog error "Working directories module failed"
        return 1
    fi

    # Модуль 20: Настройка логирования
    if ! execute_module "20-tlogging.sh" "init"; then
        tlog error "Logging module failed"
        return 1
    fi

    # Модуль 30: Выполнение пользовательских init скриптов
    if ! execute_module "30-init-scripts.sh" "init"; then
        tlog error "Init scripts module failed"
        return 1
    fi

    # Модуль 40: Ожидание зависимостей
    if ! execute_module "40-dependencies.sh" "dependencies"; then
        tlog error "Dependencies module failed"
        return 1
    fi

    # ========================================================================
    # ФИНАЛЬНОЕ ВЫПОЛНЕНИЕ КОМАНДЫ
    # ========================================================================

    # Проверяем режим INIT_ONLY
    if [[ "$(modes exec-mode current)" == "INIT_ONLY" ]]; then
        tlog success "INIT_ONLY mode: initialization completed, skipping command execution"
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        tlog info "Total entrypoint duration: ${duration}s"
        return 0
    fi

    # Модуль 99: Выполнение финальной команды
    tlog header "COMMAND EXECUTION PHASE"

    if ! execute_module "99-exec-command.sh" "exec"; then
        tlog error "Command execution module failed"
        return 1
    fi

    # Если мы дошли до сюда в DRY_RUN - это нормально
    if [[ "$(modes exec-mode current)" == "DRY_RUN" ]]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        tlog success "DRY RUN completed successfully"
        tlog info "Total entrypoint duration: ${duration}s"
        return 0
    fi

    # Если мы дошли до сюда не в DRY_RUN - команда выполнилась и завершилась (нормально)
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    tlog success "Command completed successfully"
    tlog info "Total entrypoint duration: ${duration}s"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Обработка сигналов для graceful shutdown
trap 'tlog warning "Received termination signal, shutting down..."; exit 143' SIGTERM
trap 'tlog warning "Received interrupt signal, shutting down..."; exit 130' SIGINT

# Запуск основной логики
main "$@"
main_exit_code=$?

if [[ $main_exit_code -ne 0 ]]; then
    tlog error "Entrypoint failed with exit code: $main_exit_code"
    exit $main_exit_code
fi

# Если main() вернула 0 - все прошло успешно
tlog success "Entrypoint completed successfully"
exit 0