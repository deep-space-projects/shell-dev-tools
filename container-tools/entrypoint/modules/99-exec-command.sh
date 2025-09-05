#!/bin/bash
# ============================================================================
# Final Command Execution Module
# Switches to application user and executes the final command
# ============================================================================

set -euo pipefail

# Подключаем базовые функции
source "${CONTAINER_TOOLS}/core/modules.sh"
# Загружаем нужную реализацию
load_module_implementation "exec-command"

# ============================================================================
# MODULE FUNCTION
# ============================================================================

module() {
    tlog header "FINAL COMMAND EXECUTION"

    # Получаем финальную команду из аргументов universal-entrypoint.sh
    # Эти аргументы передаются через переменную окружения или файл
    FINAL_COMMAND="${ENTRYPOINT_FINAL_COMMAND:-}"

    if [[ -z "$FINAL_COMMAND" ]]; then
        tlog error "No final command specified"
        tlog error "This should not happen - universal-entrypoint.sh should have set ENTRYPOINT_FINAL_COMMAND"
        return 1
    fi

    tlog info "Target user: $CONTAINER_USER (UID: $CONTAINER_UID, GID: $CONTAINER_GID)"
    tlog info "Final command: $FINAL_COMMAND"

    # ========================================================================
    # 1. PRE-EXECUTION VALIDATION
    # ========================================================================

    tlog step "1" "Pre-execution validation"
    if ! pre_execution_validation; then
        tlog error "Pre-execution validation failed"
        return 1
    fi

    # ========================================================================
    # 2. USER ENVIRONMENT PREPARATION
    # ========================================================================

    tlog step "2" "Preparing user environment"
    if ! prepare_user_environment_for_exec; then
        tlog error "User environment preparation failed"
        return 1
    fi

    # ========================================================================
    # 3. FINAL COMMAND EXECUTION
    # ========================================================================

    tlog step "3" "Executing final command"
    if ! execute_final_command; then
        tlog error "Final command execution failed"
        return 1
    fi

    # ========================================================================
    # COMPLETION (только для DRY_RUN)
    # ========================================================================

    tlog success "Final command execution module completed successfully"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Запускаем модуль и завершаем скрипт с его кодом
module "$@"
exit $?