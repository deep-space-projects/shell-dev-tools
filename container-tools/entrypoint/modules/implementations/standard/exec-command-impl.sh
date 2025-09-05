#!/bin/bash
# ============================================================================
# Standard Final Command Execution Implementation
# ============================================================================

set -euo pipefail

pre_execution_validation() {
    # Проверяем что целевой пользователь существует
    if ! users exists "$CONTAINER_USER"; then
        operations handle-quite "validate target user" "User does not exist: $CONTAINER_USER" 1
    fi

    # Получаем информацию о текущем пользователе
    users get-info $USER

    tlog info "Current user: $CURRENT_USER (UID: $CURRENT_UID)"
    tlog info "Target user: $CONTAINER_USER (UID: $CONTAINER_UID)"

    if [[ "$CURRENT_USER" == "$CONTAINER_USER" ]]; then
        tlog info "Already running as target user"
    elif [[ $EUID -ne 0 ]]; then
        tlog warning "Not running as root - cannot switch users"
        tlog warning "Will execute command as current user: $CURRENT_USER"
    fi

    tlog success "Pre-execution validation completed"
}

prepare_user_environment_for_exec() {
    # Подготавливаем окружение пользователя
    if ! users prepare-env "$CONTAINER_USER" "true"; then
        operations handle-quite "prepare user environment" "Failed to prepare environment for: $CONTAINER_USER" 1
    fi

    tlog success "User environment prepared"
}

execute_final_command() {
    # Логируем финальную информацию перед exec
    tlog success "Initialization completed successfully"
    tlog info "Switching to user '$CONTAINER_USER' and executing command..."
    tlog info "Command: $FINAL_COMMAND"
    tlog info ""
    tlog info "=== END OF ENTRYPOINT LOGS ==="

    # Выполняем финальную команду через функцию из process-lib.sh
    # Эта функция делает exec, поэтому мы сюда не вернемся
    exec_final_command "$CONTAINER_USER" "$FINAL_COMMAND"

    # Если мы дошли до сюда - что-то пошло не так
    tlog error "Failed to execute final command - this should not happen"
    exit 1
}

# Выполнение финальной команды под правильным пользователем
exec_final_command() {
    local target_user=$1
    shift
    local command_to_exec="$*"

    if [[ -z "$command_to_exec" ]]; then
        tlog error "No command specified to execute"
        return 1
    fi

    tlog header "EXECUTING COMMAND"
    tlog info "Target user: $target_user"
    tlog info "Command: $command_to_exec"

    # Прямая валидация через platform функции
    if [[ -z "$target_user" ]]; then
        tlog error "Target user not specified"
        return 1
    fi

    if ! users exists "$target_user"; then
        tlog error "Target user does not exist: $target_user"
        return 1
    fi

    # Подготавливаем окружение (используем функцию из common.sh)
    if ! users prepare-env "$target_user" "true"; then
        tlog error "Failed to prepare user environment"
        return 1
    fi

    # Получаем информацию о текущем пользователе
    users get-info "$target_user"

    # Если уже нужный пользователь - выполняем напрямую
    if [[ "$CURRENT_USER" == "$target_user" ]] || [[ $EUID -ne 0 ]]; then
        tlog info "Executing command as current user"
        exec bash -c "$command_to_exec"
    fi

    # Переключаемся на пользователя и выполняем команду (используем platform.sh)
    tlog success "Switching to user '$target_user' and executing command..."

    users switch "$target_user" "$command_to_exec"

    # Если мы дошли сюда - что-то пошло не так
    tlog error "Failed to execute final command"
    return 1
}