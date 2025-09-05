#!/bin/bash
# ============================================================================
# Standard Logging Setup Implementation
# ============================================================================

set -euo pipefail

setup_basic_logging_variables() {
    # Устанавливаем базовые переменные логирования только если они не установлены
    if [[ -z "${LOG_DIR:-}" ]]; then
        export LOG_DIR="/var/log/$CONTAINER_NAME"
        tlog info "Set LOG_DIR: $LOG_DIR"
    else
        tlog info "LOG_DIR already set: $LOG_DIR"
    fi

    if [[ -z "${LOG_LEVEL:-}" ]]; then
        export LOG_LEVEL="INFO"
        tlog info "Set LOG_LEVEL: $LOG_LEVEL"
    else
        tlog info "LOG_LEVEL already set: $LOG_LEVEL"
    fi

    tlog success "Basic logging variables configured"
}

verify_log_directory() {
    # Проверяем что директория логов существует (должна была быть создана в 10-permissions.sh)
    if [[ -d "$LOG_DIR" ]]; then
        tlog success "Log directory ready: $LOG_DIR"
    else
        operations handle-quite "verify tlog directory" "Directory not found: $LOG_DIR" 1
    fi
}