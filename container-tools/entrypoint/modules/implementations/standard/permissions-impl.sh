#!/bin/bash
# ============================================================================
# Standard Permissions Setup Implementation
# ============================================================================

set -euo pipefail

setup_container_temp_directory() {
    if ! permissions setup --privileged=true --path="$CONTAINER_TEMP" --owner="$OWNER_STRING" \
                           --dir-perms="700" --file-perms="600" --flags="create,strict,recursive"; then
        operations handle-quite "setup container temp directory" "Path: $CONTAINER_TEMP" 1
    else
        tlog success "Container temp directory configured: $CONTAINER_TEMP"
    fi
}

setup_log_directory() {
    tlog info "Configuring tlog directory: $LOG_DIR"

    if ! permissions setup --privileged=true --path="$LOG_DIR" --owner="$OWNER_STRING" \
                           --dir-perms="700" --file-perms="600" --flags="create,strict,recursive"; then
        operations handle-quite "setup tlog directory" "Path: $LOG_DIR" 1
    else
        tlog success "Log directory configured: $LOG_DIR"
    fi
}

setup_user_init_scripts() {
    tlog info "Checking user init scripts: $CONTAINER_ENTRYPOINT_SCRIPTS"

    if [[ -d "$CONTAINER_ENTRYPOINT_SCRIPTS" ]]; then
        tlog info "User init scripts directory found, setting permissions"
        if ! permissions setup --privileged=true --path="$CONTAINER_ENTRYPOINT_SCRIPTS" --owner="$OWNER_STRING" \
                               --dir-perms="700" --file-perms="700" --flags="required,strict,recursive,executable"; then
            operations handle-quite "setup init scripts permissions" "Path: $CONTAINER_ENTRYPOINT_SCRIPTS" 1
        else
            tlog success "Init scripts permissions configured: $CONTAINER_ENTRYPOINT_SCRIPTS"
        fi
    else
        tlog info "No user init scripts directory found (this is normal)"
    fi
}

setup_user_configs() {
    tlog info "Checking user configs: $CONTAINER_ENTRYPOINT_CONFIGS"

    if [[ -d "$CONTAINER_ENTRYPOINT_CONFIGS" ]]; then
        tlog info "User configs directory found, setting permissions"
        if ! permissions setup --privileged=true --path="$CONTAINER_ENTRYPOINT_CONFIGS" --owner="$OWNER_STRING" \
                               --dir-perms="700" --file-perms="600" --flags="required,strict,recursive"; then
            operations handle-quite "setup configs permissions" "Path: $CONTAINER_ENTRYPOINT_CONFIGS" 1
        else
            tlog success "Configs permissions configured: $CONTAINER_ENTRYPOINT_CONFIGS"
        fi
    else
        tlog info "No user configs directory found (this is normal)"
    fi
}

setup_user_dependencies_scripts() {
    tlog info "Checking user dependencies scripts: $CONTAINER_ENTRYPOINT_DEPENDENCIES"

    if [[ -d "$CONTAINER_ENTRYPOINT_DEPENDENCIES" ]]; then
        tlog info "User dependencies scripts directory found, setting permissions"
        if ! permissions setup --privileged=true --path="$CONTAINER_ENTRYPOINT_DEPENDENCIES" --owner="$OWNER_STRING" \
                               --dir-perms="700" --file-perms="700" --flags="required,strict,recursive,executable"; then
            operations handle-quite "setup dependencies scripts permissions" "Path: $CONTAINER_ENTRYPOINT_DEPENDENCIES" 1
        else
            tlog success "Dependencies scripts permissions configured: $CONTAINER_ENTRYPOINT_DEPENDENCIES"
        fi
    else
        tlog info "No user dependencies scripts directory found (this is normal)"
    fi
}

setup_container_tools() {
    tlog info "Configuring container tools: $CONTAINER_TOOLS"

    # Container tools должны быть доступны владельцу и группе
    if ! permissions setup --privileged=true --path="$CONTAINER_TOOLS" --owner="$OWNER_STRING" \
                           --dir-perms="750" --file-perms="750" --flags="required,strict,recursive,executable"; then
        operations handle-quite "setup container tools permissions" "Path: $CONTAINER_TOOLS" 1
    else
        tlog success "Container tools permissions configured: $CONTAINER_TOOLS"
    fi
}

verify_permissions() {
    # Проверяем что критически важные директории имеют правильного владельца
    critical_dirs=(
        "/var/log/$CONTAINER_NAME"
        "$CONTAINER_TOOLS"
        "$CONTAINER_TEMP"
    )

    verification_failed=false

    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Проверяем владельца
            if commands exists stat; then
                dir_owner=$(stat -c '%U:%G' "$dir" 2>/dev/null || echo "unknown:unknown")
                expected_owner="$CONTAINER_USER:$CONTAINER_GROUP"

                if [[ "$dir_owner" == "$expected_owner" ]]; then
                    tlog debug "✓ Correct owner for $dir: $dir_owner"
                else
                    tlog warning "Owner mismatch for $dir: expected $expected_owner, got $dir_owner"
                    verification_failed=true
                fi
            fi

            # Проверяем базовые права доступа
            if [[ -r "$dir" ]] && [[ -x "$dir" ]]; then
                tlog debug "✓ Directory accessible: $dir"
            else
                tlog warning "Directory not accessible: $dir"
                verification_failed=true
            fi
        else
            tlog warning "Critical directory not found: $dir"
            verification_failed=true
        fi
    done

    # Проверяем все .sh файлы в core директории на исполняемость
    tlog info "Checking core scripts executability..."
    core_scripts=()
    while IFS= read -r -d '' script; do
        core_scripts+=("$script")
    done < <(find "$CONTAINER_TOOLS/core" -name "*.sh" -type f -print0 2>/dev/null)

    if [[ ${#core_scripts[@]} -eq 0 ]]; then
        tlog warning "No .sh files found in core directory: $CONTAINER_TOOLS/core"
        verification_failed=true
    else
        tlog info "Found ${#core_scripts[@]} core scripts to verify"
        for script in "${core_scripts[@]}"; do
            if [[ -x "$script" ]]; then
                tlog debug "✓ Executable: $(basename "$script")"
            else
                tlog warning "Not executable: $(basename "$script")"
                verification_failed=true
            fi
        done
    fi

    if [[ "$verification_failed" == "true" ]]; then
        operations handle-quite "permissions verification" "Some files/directories have incorrect permissions or ownership" 1
    else
        tlog success "Permissions verification completed successfully"
    fi
}