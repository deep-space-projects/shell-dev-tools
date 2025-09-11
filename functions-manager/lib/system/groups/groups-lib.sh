#!/bin/bash
# ============================================================================
# Platform-specific Command Wrappers
# Provides cross-platform compatibility for common operations
# ============================================================================

# Получение GID по имени группы (кроссплатформенно)
get_group_uid() {
    local groupname="$1"

    if [[ -z "$groupname" ]]; then
        log_error "Group name is required"
        return 1
    fi

    # Метод 1: через getent group (если доступен)
    if command -v getent >/dev/null 2>&1; then
        local gid=$(getent group "$groupname" 2>/dev/null | cut -d: -f3)
        if [[ -n "$gid" ]]; then
            echo "$gid"
            return 0
        fi
    fi

    # Метод 2: через /etc/group
    if [[ -f /etc/group ]]; then
        local gid=$(grep "^${groupname}:" /etc/group 2>/dev/null | cut -d: -f3)
        if [[ -n "$gid" ]]; then
            echo "$gid"
            return 0
        fi
    fi

    log_warning "Cannot determine GID for group: $groupname"
    return 1
}

# Проверка существования пользователя (кроссплатформенная)
is_group_exists() {
    local groupname="$1"

    if [[ -z "$groupname" ]]; then
        log_error "Group name is required"
        return 1
    fi

    get_group_uid $groupname
    return $?
}