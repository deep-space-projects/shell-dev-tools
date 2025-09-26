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

create_group() {
    local fail_on_exists="false"
    local groupname=""
    local uid=""

    while [ $# -gt 0 ]; do
        case $1 in
            --fail-on-exists)
                fail_on_exists="true"
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$groupname" ]]; then
                    groupname="$1"
                elif [[ -z "$uid" ]]; then
                    uid="$1"
                else
                    echo "Too many arguments" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$groupname" ]] || [[ ! "$groupname" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
        log_error "Group name is required"
        return 1
    fi

    if [[ -z "$uid" ]] || [[ ! "$uid" =~ ^[1-9][0-9]{0,4}$ ]] ; then
        log_error "Group UID is required"
        return 1
    fi
    
    if is_group_exists "$groupname"; then
        if [[ $fail_on_exists == "true" ]]; then
            log_error "Group already exists: $groupname"
            return 1
        else
            log_info "Group already exists: $groupname"
            return 0
        fi
    fi

    local os_family=$(detect_os_family)

    if [[ -z "$os_family" ]]; then
        log_error "Undefined OS"
        return 1
    fi

    case "$os_family" in
        "debian"|"rhel")
            if ! command -v groupadd >/dev/null 2>&1; then
                log_error "\$(groupadd) function not found in $os_family family system!"
                return 1
            fi
            
            create_group_with_groupadd $groupname $uid
            ;;
        "alpine")
            if ! command -v addgroup >/dev/null 2>&1; then
                log_error "\$(addgroup) function not found in $os_family family system!"
                return 1
            fi
            
            create_group_with_addgroup $groupname $uid
            ;;
        *)
            log_error "Unknown OS family: $os_family"
            return 1
            ;;
    esac
}

# Создание группы с помощью groupadd
create_group_with_groupadd() {
    local group_name="$1"
    local group_id="$2"

    log_debug "Using groupadd to create group"
    if groupadd -g "$group_id" "$group_name"; then
        log_success "Group created with groupadd: $group_name ($group_id)"
        return 0
    else
        log_error "Failed to create group with groupadd"
        return 1
    fi
}

# Создание группы с помощью addgroup
create_group_with_addgroup() {
    local group_name="$1"
    local group_id="$2"

    log_debug "Using addgroup to create group"
    if addgroup -g "$group_id" "$group_name"; then
        log_success "Group created with addgroup: $group_name ($group_id)"
        return 0
    else
        log_error "Failed to create group with addgroup"
        return 1
    fi
}