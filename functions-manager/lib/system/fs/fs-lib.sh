#!/bin/bash
# ============================================================================
# Common Functions for Container Tools
# Provides platform detection, basic utilities and common functions
# ============================================================================

# Безопасное создание директории
safe_mkdir() {
    local dir="$1"
    local owner="${2:-}"
    local permissions="${3:-755}"

    if [[ -z "$dir" ]]; then
        log_error "Directory path is required"
        return 1
    fi

    if [[ ! -d "$dir" ]]; then
        log_debug "Creating directory: $dir"
        if mkdir -p "$dir"; then
            log_success "Directory created: $dir"
        else
            log_error "Failed to create directory: $dir"
            return 1
        fi
    else
        log_debug "Directory already exists: $dir"
    fi

    # Устанавливаем права если указаны
    if [[ -n "$permissions" ]]; then
        chmod "$permissions" "$dir" || log_warning "Failed to set permissions $permissions on $dir"
    fi

    # Устанавливаем владельца если указан
    if [[ -n "$owner" ]]; then
        chown "$owner" "$dir" || log_warning "Failed to set owner $owner on $dir"
    fi

    return 0
}