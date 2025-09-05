#!/bin/bash
# ============================================================================
# Standard Dependencies Waiting Implementation
# ============================================================================

set -euo pipefail

check_dependencies_scripts_directory() {
    if [[ ! -d "$CONTAINER_ENTRYPOINT_DEPENDENCIES" ]]; then
        tlog info "Dependencies scripts directory not found: $CONTAINER_ENTRYPOINT_DEPENDENCIES"
        tlog info "No dependency waiting scripts to execute (this is normal)"
        tlog success "Dependencies module completed - no scripts found"
        return 0  # Это нормальная ситуация, возвращаем успех
    fi

    tlog success "Dependencies scripts directory found: $CONTAINER_ENTRYPOINT_DEPENDENCIES"
}

execute_dependencies_scripts() {
    # Проверяем есть ли вообще скрипты для выполнения
    local scripts_count=0
    if [[ -d "$CONTAINER_ENTRYPOINT_DEPENDENCIES" ]]; then
        scripts_count=$(find "$CONTAINER_ENTRYPOINT_DEPENDENCIES" -maxdepth 1 -name "*.sh" -type f | wc -l)
    fi

    if [[ $scripts_count -eq 0 ]]; then
        tlog info "No dependency scripts found in $CONTAINER_ENTRYPOINT_DEPENDENCIES"
        tlog success "Dependencies check completed - no scripts to execute"
        return 0
    fi

    tlog info "Found $scripts_count dependency scripts, executing under total timeout: ${DEPENDENCY_TIMEOUT}s..."

    commands exec \
            --timeout="$DEPENDENCY_TIMEOUT" \
            --description="All dependency scripts" \
            execute_scripts_in_directory "$CONTAINER_ENTRYPOINT_DEPENDENCIES" "$EXEC_ERROR_POLICY" 0 "*.sh"
    local timeout_exit_code=$?


    if [[ $timeout_exit_code -ne 0 ]]; then
        operations handle-quite "execute dependencies scripts with timeout" "Directory: $CONTAINER_ENTRYPOINT_DEPENDENCIES, Total timeout: ${DEPENDENCY_TIMEOUT}s" $timeout_exit_code
        return $?
    else
        tlog success "All dependency scripts executed successfully within timeout"
        return 0
    fi
}