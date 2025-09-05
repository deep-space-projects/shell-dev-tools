#!/bin/bash
# ============================================================================
# Permissions Setup Module
# Sets up file permissions for logging, temp directories, and container tools
# ============================================================================

set -euo pipefail

# Подключаем базовые функции
source "${CONTAINER_TOOLS}/core/modules.sh"

# Загружаем нужную реализацию
load_module_implementation "permissions"

# ============================================================================
# MODULE FUNCTION
# ============================================================================

module() {
    tlog header "PERMISSIONS SETUP"

    if [[ $EUID -ne 0 ]]; then
        tlog warning "Not running as root (UID: $EUID) - some permission operations may fail"
    fi

    OWNER_STRING="$CONTAINER_UID:$CONTAINER_GID"
    tlog info "Setting up permissions for owner: $OWNER_STRING ($CONTAINER_USER:$CONTAINER_GROUP)"
    tlog info "Container temp directory: $CONTAINER_TEMP"

    # ========================================================================
    # 1. CONTAINER TEMP DIRECTORY
    # ========================================================================

    tlog step "1" "Setting up container temp directory: $CONTAINER_TEMP"
    if ! setup_container_temp_directory; then
        tlog error "Container temp directory setup failed"
        return 1
    fi

    # ========================================================================
    # 2. tlog DIRECTORY
    # ========================================================================

    tlog step "2" "Setting up tlog directory"
    if ! setup_log_directory; then
        tlog error "Log directory setup failed"
        return 1
    fi

    # ========================================================================
    # 3. USER INIT SCRIPTS (if exist)
    # ========================================================================

    tlog step "3" "Setting up user init scripts permissions"
    if ! setup_user_init_scripts; then
        tlog error "User init scripts permissions setup failed"
        return 1
    fi

    # ========================================================================
    # 4. USER CONFIGS (if exist)
    # ========================================================================

    tlog step "4" "Setting up user configs permissions"
    if ! setup_user_configs; then
        tlog error "User configs permissions setup failed"
        return 1
    fi

    # ========================================================================
    # 5. USER DEPENDENCIES SCRIPTS (if exist)
    # ========================================================================

    tlog step "5" "Setting up user dependencies scripts permissions"
    if ! setup_user_dependencies_scripts; then
        tlog error "User dependencies scripts permissions setup failed"
        return 1
    fi

    # ========================================================================
    # 6. CONTAINER TOOLS
    # ========================================================================

    tlog step "6" "Setting up container tools permissions"
    if ! setup_container_tools; then
        tlog error "Container tools permissions setup failed"
        return 1
    fi

    # ========================================================================
    # 7. PERMISSIONS VERIFICATION
    # ========================================================================

    tlog step "7" "Verifying permissions"
    if ! verify_permissions; then
        tlog error "Permissions verification failed"
        return 1
    fi

    # ========================================================================
    # PERMISSIONS SUMMARY
    # ========================================================================

    tlog info "Permissions setup summary:"
    tlog info "  Container temp: $CONTAINER_TEMP (700/600, owner: $CONTAINER_USER)"
    tlog info "  tlog directory: /var/log/$CONTAINER_NAME (700/600, owner: $CONTAINER_USER)"
    tlog info "  Init scripts: $CONTAINER_ENTRYPOINT_SCRIPTS (700/700 + executable, owner: $CONTAINER_USER)"
    tlog info "  Configs: $CONTAINER_ENTRYPOINT_CONFIGS (700/600, owner: $CONTAINER_USER)"
    tlog info "  Dependencies: $CONTAINER_ENTRYPOINT_DEPENDENCIES (700/700 + executable, owner: $CONTAINER_USER)"
    tlog info "  Container tools: $CONTAINER_TOOLS (750/750 + executable, owner: $CONTAINER_USER)"

    # ========================================================================
    # COMPLETION
    # ========================================================================

    tlog success "Permissions setup module completed successfully"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Запускаем модуль и завершаем скрипт с его кодом
module "$@"
exit $?