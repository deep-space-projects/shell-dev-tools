#!/bin/bash
# ============================================================================
# Standard Init Scripts Execution Implementation
# ============================================================================

set -euo pipefail

check_init_scripts_directory() {
    if [[ ! -d "$CONTAINER_ENTRYPOINT_SCRIPTS" ]]; then
        tlog info "Init scripts directory not found: $CONTAINER_ENTRYPOINT_SCRIPTS"
        tlog info "No user initialization scripts to execute (this is normal)"
        tlog success "Init scripts module completed - no scripts found"
    fi

    tlog success "Init scripts directory found: $CONTAINER_ENTRYPOINT_SCRIPTS"
}

execute_init_scripts() {
    # Выполняем init скрипты через функцию из process-lib.sh
    tlog info "Executing initialization scripts..."

    if ! scripts exec-all \
            --path="$CONTAINER_ENTRYPOINT_SCRIPTS" \
            --error-policy="$EXEC_ERROR_POLICY"
            --timeout=0 \
            --pattern="*.sh"; then
        operations handle-quite "execute init scripts" "Directory: $CONTAINER_ENTRYPOINT_SCRIPTS" 1
    else
        tlog success "All init scripts executed successfully"
    fi
}