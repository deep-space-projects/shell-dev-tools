#!/bin/bash
# ============================================================================
# Logging Setup Module
# Sets up basic logging environment variables if not already configured
# ============================================================================

set -euo pipefail

# Подключаем базовые функции
source "${CONTAINER_TOOLS}/core/modules.sh"

# Загружаем нужную реализацию
load_module_implementation "logging"

# ============================================================================
# MODULE FUNCTION
# ============================================================================

module() {
    tlog header "LOGGING SETUP"

    tlog info "Configuring basic logging environment for container: $CONTAINER_NAME"

    # ========================================================================
    # 1. BASIC LOGGING VARIABLES
    # ========================================================================

    tlog step "1" "Setting up basic logging variables"
    if ! setup_basic_logging_variables; then
        tlog error "Basic logging variables setup failed"
        return 1
    fi

    # ========================================================================
    # 2. VERIFY tlog DIRECTORY
    # ========================================================================

    tlog step "2" "Verifying tlog directory"
    if ! verify_log_directory; then
        tlog error "Log directory verification failed"
        return 1
    fi

    # ========================================================================
    # LOGGING SUMMARY
    # ========================================================================

    tlog info "Logging setup summary:"
    tlog info "  tlog directory: $LOG_DIR"
    tlog info "  tlog level: $LOG_LEVEL"

    # ========================================================================
    # COMPLETION
    # ========================================================================

    tlog success "Logging setup module completed successfully"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Запускаем модуль и завершаем скрипт с его кодом
module "$@"
exit $?