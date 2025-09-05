#!/bin/bash
# ============================================================================
# Standard Environment Validation Implementation
# ============================================================================

set -euo pipefail

detect_operating_system() {
    OS_TYPE=$(cmn os detect)
    OS_FAMILY=$(cmn os family)
    IS_MINIMAL=$(os is-mini && echo "true" || echo "false")

    tlog info "Operating System: $OS_TYPE"
    tlog info "OS Family: $OS_FAMILY"
    tlog info "Minimal system: $IS_MINIMAL"

    # Экспортируем информацию об ОС для других модулей
    export DETECTED_OS="$OS_TYPE"
    export DETECTED_OS_FAMILY="$OS_FAMILY"
    export IS_MINIMAL_SYSTEM="$IS_MINIMAL"
}

validate_system_commands() {
    required_commands=("id" "whoami" "chmod" "chown")
    optional_commands=("find" "grep" "cut" "sort")

    missing_required=()
    for cmd in "${required_commands[@]}"; do
        if ! commands exists "$cmd"; then
            missing_required+=("$cmd")
        else
            tlog debug "✓ $cmd available"
        fi
    done

    if [[ ${#missing_required[@]} -gt 0 ]]; then
        tlog error "Missing required system commands:"
        for cmd in "${missing_required[@]}"; do
            tlog error "  - $cmd"
        done
        operations handle-quite "validate system commands" "Missing required commands: ${missing_required[*]}" 1
    fi

    missing_optional=()
    for cmd in "${optional_commands[@]}"; do
        if ! commands exists "$cmd"; then
            missing_optional+=("$cmd")
        else
            tlog debug "✓ $cmd available"
        fi
    done

    if [[ ${#missing_optional[@]} -gt 0 ]]; then
        tlog warning "Missing optional commands (some features may be limited):"
        for cmd in "${missing_optional[@]}"; do
            tlog warning "  - $cmd"
        done
    fi

    tlog success "System commands check completed"
}

validate_target_user() {
    # Проверяем существование целевого пользователя
    if ! users exists "$CONTAINER_USER"; then
        operations handle-quite "validate target user existence" "Target user does not exist: $CONTAINER_USER. Please ensure setup-container-user.sh was executed during build" 1
    fi

    # Проверяем UID/GID соответствие
    actual_uid=$(users get-uid "$CONTAINER_USER")
    actual_gid=$(users get-gid "$CONTAINER_USER")

    if [[ "$actual_uid" != "$CONTAINER_UID" ]]; then
        operations handle-quite "validate user UID" "UID mismatch for user $CONTAINER_USER: expected $CONTAINER_UID, actual $actual_uid" 1
    fi

    if [[ "$actual_gid" != "$CONTAINER_GID" ]]; then
        operations handle-quite "validate user GID" "GID mismatch for user $CONTAINER_USER: expected $CONTAINER_GID, actual $actual_gid" 1
    fi

    # Проверяем группу если указана
    if [[ -n "$CONTAINER_GROUP" ]] && [[ "$CONTAINER_GROUP" != "root" ]]; then
        if ! groups exists "$CONTAINER_GROUP"; then
            operations handle-quite "validate target group" "Target group does not exist: $CONTAINER_GROUP" 1
        fi

        # Проверяем что пользователь в группе
        if ! users in-group "$CONTAINER_USER" "$CONTAINER_GROUP"; then
            tlog warning "User $CONTAINER_USER is not a member of group $CONTAINER_GROUP"
        fi
    fi

    tlog success "User validation completed"
    tlog info "Target user: $CONTAINER_USER (UID: $actual_uid, GID: $actual_gid)"
}

validate_directory_structure() {
    # Проверяем стандартные директории
    standard_dirs=(
        "$CONTAINER_ENTRYPOINT_SCRIPTS"
        "$CONTAINER_ENTRYPOINT_CONFIGS"
        "$CONTAINER_ENTRYPOINT_DEPENDENCIES"
    )

    for dir in "${standard_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            tlog debug "✓ Directory exists: $dir"
        else
            tlog debug "→ Directory will be created if needed: $dir"
        fi
    done

    # Проверяем директорию логов
    log_dir="/var/log/$CONTAINER_NAME"
    if [[ -d "$log_dir" ]]; then
        tlog debug "✓ tlog directory exists: $log_dir"
    else
        tlog debug "→ tlog directory will be created: $log_dir"
    fi

    tlog success "Directory structure validation completed"
}

export_runtime_information() {
    # Экспортируем информацию для других модулей
    export RUNTIME_START_TIME="$(date +%s)"
    export RUNTIME_START_ISO="$(date -Iseconds)"
    export CURRENT_WORKING_DIR="$(pwd)"

    # Получаем информацию о текущем пользователе
    users get-info $USER

    tlog info "Runtime information:"
    tlog info "  Start time: $RUNTIME_START_ISO"
    tlog info "  Working directory: $CURRENT_WORKING_DIR"
    tlog info "  Current user: $CURRENT_USER (UID: $CURRENT_UID)"
    tlog info "  Target user: $CONTAINER_USER (UID: $CONTAINER_UID)"
}