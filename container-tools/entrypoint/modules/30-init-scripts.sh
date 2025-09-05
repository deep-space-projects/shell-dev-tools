#!/bin/bash
# ============================================================================
# Init Scripts Execution Module
# Executes user-provided initialization scripts in lexicographic order
# ============================================================================

set -euo pipefail

# Подключаем базовые функции
source "${CONTAINER_TOOLS}/core/modules.sh"

# Загружаем нужную реализацию
load_module_implementation "init-scripts"

# ============================================================================
# MODULE FUNCTION
# ============================================================================

module() {
    tlog header "INIT SCRIPTS EXECUTION"

    tlog info "Checking for user initialization scripts in: $CONTAINER_ENTRYPOINT_SCRIPTS"

    # ========================================================================
    # 1. CHECK INIT SCRIPTS DIRECTORY
    # ========================================================================

    tlog step "1" "Checking init scripts directory"
    if ! check_init_scripts_directory; then
        tlog error "Init scripts directory check failed"
        return 1
    fi

    # ========================================================================
    # 2. EXECUTE INIT SCRIPTS
    # ========================================================================

    tlog step "2" "Executing init scripts"
    if ! execute_init_scripts; then
        tlog error "Init scripts execution failed"
        return 1
    fi

    # ========================================================================
    # COMPLETION
    # ========================================================================

    tlog success "Init scripts execution module completed successfully"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Запускаем модуль и завершаем скрипт с его кодом
module "$@"
exit $?