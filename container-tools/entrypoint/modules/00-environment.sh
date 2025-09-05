#!/bin/bash
# ============================================================================
# Environment Validation Module
# Validates environment variables and system requirements
# ============================================================================

set -euo pipefail

# Подключаем базовые функции
source "${CONTAINER_TOOLS}/core/modules.sh"
# Загружаем нужную реализацию
load_module_implementation "environment"

# ============================================================================
# MODULE FUNCTION
# ============================================================================

module() {
    tlog header "ENVIRONMENT VALIDATION"

    # ========================================================================
    # 1. OPERATING SYSTEM DETECTION
    # ========================================================================

    tlog info "Detecting operating system..."
    if ! detect_operating_system; then
        tlog error "Operating system detection failed"
        return 1
    fi

    # ========================================================================
    # 2. SYSTEM COMMANDS VALIDATION
    # ========================================================================

    tlog info "Checking system commands availability..."
    if ! validate_system_commands; then
        tlog error "System commands validation failed"
        return 1
    fi

    # ========================================================================
    # 3. USER VALIDATION
    # ========================================================================

    tlog info "Validating target user configuration..."
    if ! validate_target_user; then
        tlog error "Target user validation failed"
        return 1
    fi

    # ========================================================================
    # 4. DIRECTORY STRUCTURE VALIDATION
    # ========================================================================

    tlog info "Validating directory structure..."
    if ! validate_directory_structure; then
        tlog error "Directory structure validation failed"
        return 1
    fi

    # ========================================================================
    # 5. EXPORT RUNTIME INFORMATION
    # ========================================================================

    tlog info "Exporting runtime information..."
    if ! export_runtime_information; then
        tlog error "Runtime information export failed"
        return 1
    fi

    # ========================================================================
    # COMPLETION
    # ========================================================================

    tlog success "Environment validation module completed successfully"
    return 0
}

# ============================================================================
# ENTRY POINT
# ============================================================================

# Запускаем модуль и завершаем скрипт с его кодом
module "$@"
exit $?