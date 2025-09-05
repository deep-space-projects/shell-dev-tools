#!/bin/bash
# ============================================================================
# Working Directories Permissions Setup Module
# Sets up user permissions for custom working directories
# ============================================================================

set -euo pipefail

# Подключаем базовые функции
source "${CONTAINER_TOOLS}/core/modules.sh"

# Загружаем нужную реализацию
load_module_implementation "working-directories-permissions"

# ============================================================================
# MODULE FUNCTION
# ============================================================================

module() {
    tlog header "WORKING DIRECTORIES PERMISSIONS SETUP"

    # Проверяем наличие переменной CONTAINER_WORKING_DIRS
    if [[ -z "${CONTAINER_WORKING_DIRS:-}" ]]; then
        tlog info "CONTAINER_WORKING_DIRS is not set or empty - skipping working directories permissions setup"
        tlog success "Working directories permissions setup module completed (skipped)"
        return 0
    fi

    if [[ $EUID -ne 0 ]]; then
        tlog warning "Not running as root (UID: $EUID) - some permission operations may fail"
    fi

    local owner_string="$CONTAINER_UID:$CONTAINER_GID"
    tlog info "Setting up working directories permissions for owner: $owner_string ($CONTAINER_USER:$CONTAINER_GROUP)"
    tlog info "Working directories: $CONTAINER_WORKING_DIRS"

    # Показываем политику ограничений
    show_restrictions_policy

    # Разбираем список директорий
    working_dirs=(${CONTAINER_WORKING_DIRS//,/ })

    tlog debug "Parsed ${#working_dirs[@]} working directories:"
    for i in "${!working_dirs[@]}"; do
        tlog debug "  [$i]: '${working_dirs[i]}'"
    done

    if [[ ${#working_dirs[@]} -eq 0 ]]; then
        tlog info "No working directories specified - skipping"
        tlog success "Working directories permissions setup module completed (no directories)"
        return 0
    fi

    # ========================================================================
    # 1. PROCESSING WORKING DIRECTORIES
    # ========================================================================

    tlog step "1" "Processing working directories"
    local success_count=0
    local error_count=0
    local processed_dirs=()

    for working_dir in "${working_dirs[@]}"; do
        # Убираем пробелы
        working_dir=$(echo "$working_dir" | xargs)

        if [[ -z "$working_dir" ]]; then
            tlog debug "Skipping empty directory entry"
            continue
        fi

        tlog info "====================================="
        tlog info "Setting up working directory permissions: $working_dir"

        setup_working_directory_permissions "$working_dir"
        local set_permissions_result=$?

        if [[ $set_permissions_result -ne 0  ]]; then
            operations handle-quite "setup working directory permissions for $working_dir" \
                "Directory permissions setup failed" $set_permissions_result
            error_count=$((error_count + 1))
        else
            processed_dirs+=("$working_dir")
            success_count=$((success_count + 1))
        fi
    done

    # ========================================================================
    # 2. PERMISSIONS VERIFICATION
    # ========================================================================

    if [[ ${#processed_dirs[@]} -gt 0 ]]; then
        tlog step "2" "Verifying working directories permissions"

        if ! verify_working_directories_permissions "${processed_dirs[@]}"; then
            operations handle-quite "verify working directories permissions" \
                "Permissions verification failed" 1
        fi
    fi

    # ========================================================================
    # SUMMARY
    # ========================================================================

    tlog info "Working directories permissions setup summary:"
    tlog info "  Total directories requested: ${#working_dirs[@]}"
    tlog info "  Successfully processed: $success_count"
    tlog info "  Errors encountered: $error_count"
    tlog info "  Owner: $CONTAINER_USER:$CONTAINER_GROUP"
    tlog info "  Permissions: 755/644 (directories/files, recursive)"

    if [[ ${#processed_dirs[@]} -gt 0 ]]; then
        tlog info "  Processed directories:"
        for working_dir in "${processed_dirs[@]}"; do
            tlog info "    - $working_dir"
        done
    fi

    # ========================================================================
    # COMPLETION
    # ========================================================================

    tlog success "Working directories permissions setup module completed successfully"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Запускаем модуль и завершаем скрипт с его кодом
module "$@"
exit $?