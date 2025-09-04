#!/bin/bash
# ============================================================================
# Platform-specific Command Wrappers
# Provides cross-platform compatibility for common operations
# ============================================================================

# ============================================================================
# USER MANAGEMENT COMMANDS
# ============================================================================

# Кроссплатформенное переключение пользователя и выполнение команды
platform_switch_user() {
    local target_user="$1"
    shift
    local command_to_run="$*"

    if [[ -z "$target_user" ]] || [[ -z "$command_to_run" ]]; then
        log_error "Usage: platform_switch_user <user> <command>"
        return 1
    fi

    local os_family=$(detect_os_family)

    log_debug "Switching to user '$target_user' on $os_family system"

    case "$os_family" in
        "debian"|"rhel")
            # Стандартные Linux системы
            exec su "$target_user" -s /bin/bash -c "exec $command_to_run"
            ;;
        "alpine")
            # Alpine Linux (BusyBox su)
            if is_minimal_system; then
                exec su -s /bin/bash "$target_user" -c "$command_to_run"
            else
                exec su "$target_user" -s /bin/bash -c "exec $command_to_run"
            fi
            ;;
        *)
            log_warning "Unknown OS family: $os_family, using default su command"
            exec su "$target_user" -s /bin/bash -c "exec $command_to_run"
            ;;
    esac
}

# Проверка существования пользователя (кроссплатформенная)
platform_user_exists() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 2
    fi

    # Метод 1: через getent (если доступен)
    if command_exists getent; then
        getent passwd "$username" >/dev/null 2>&1
        return $?
    fi

    # Метод 2: через /etc/passwd
    if [[ -f /etc/passwd ]]; then
        grep -q "^${username}:" /etc/passwd 2>/dev/null
        return $?
    fi

    # Метод 3: через id команду
    if command_exists id; then
        id "$username" >/dev/null 2>&1
        return $?
    fi

    log_warning "No method available to check user existence"
    return 2
}

# Проверка существования группы (кроссплатформенная)
platform_group_exists() {
    local groupname="$1"

    if [[ -z "$groupname" ]]; then
        log_error "Group name is required"
        return 2
    fi

    # Метод 1: через getent (если доступен)
    if command_exists getent; then
        getent group "$groupname" >/dev/null 2>&1
        return $?
    fi

    # Метод 2: через /etc/group
    if [[ -f /etc/group ]]; then
        grep -q "^${groupname}:" /etc/group 2>/dev/null
        return $?
    fi

    log_warning "No method available to check group existence"
    return 2
}

# ============================================================================
# FILE SYSTEM OPERATIONS
# ============================================================================

# Кроссплатформенная установка прав с рекурсией
platform_chown_recursive() {
    local owner="$1"
    local path="$2"
    local follow_symlinks="${3:-false}"

    if [[ -z "$owner" ]] || [[ -z "$path" ]]; then
        log_error "Usage: platform_chown_recursive <owner> <path> [follow_symlinks]"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        log_error "Path does not exist: $path"
        return 1
    fi

    log_debug "Setting owner '$owner' on '$path' (recursive)"

    local chown_args="-R"
    if [[ "$follow_symlinks" == "true" ]]; then
        chown_args="$chown_args -L"
    fi

    # В большинстве систем chown работает одинаково
    if chown $chown_args "$owner" "$path" 2>/dev/null; then
        log_debug "Successfully set owner '$owner' on '$path'"
        return 0
    else
        log_error "Failed to set owner '$owner' on '$path'"
        return 1
    fi
}

# Кроссплатформенная установка прав доступа с рекурсией
platform_chmod_recursive() {
    local permissions="$1"
    local path="$2"
    local type="${3:-all}"  # all|files|dirs

    if [[ -z "$permissions" ]] || [[ -z "$path" ]]; then
        log_error "Usage: platform_chmod_recursive <permissions> <path> [type]"
        return 1
    fi

    if [[ ! -e "$path" ]]; then
        log_error "Path does not exist: $path"
        return 1
    fi

    log_debug "Setting permissions '$permissions' on '$path' (recursive, type: $type)"

    case "$type" in
        "all")
            chmod -R "$permissions" "$path" 2>/dev/null
            ;;
        "files")
            find "$path" -type f -exec chmod "$permissions" {} + 2>/dev/null
            ;;
        "dirs")
            find "$path" -type d -exec chmod "$permissions" {} + 2>/dev/null
            ;;
        *)
            log_error "Invalid type: $type (use: all|files|dirs)"
            return 1
            ;;
    esac

    local result=$?
    if [[ $result -eq 0 ]]; then
        log_debug "Successfully set permissions '$permissions' on '$path'"
    else
        log_error "Failed to set permissions '$permissions' on '$path'"
    fi

    return $result
}

# ============================================================================
# PROCESS MANAGEMENT
# ============================================================================

# Кроссплатформенная проверка запущенных процессов
platform_process_exists() {
    local process_name="$1"
    local exact_match="${2:-false}"

    if [[ -z "$process_name" ]]; then
        log_error "Process name is required"
        return 2
    fi

    local ps_args
    if command_exists ps; then
        # Определяем аргументы ps для разных систем
        if ps aux >/dev/null 2>&1; then
            ps_args="aux"
        elif ps -ef >/dev/null 2>&1; then
            ps_args="-ef"
        else
            ps_args=""
        fi

        if [[ -n "$ps_args" ]]; then
            if [[ "$exact_match" == "true" ]]; then
                ps $ps_args | grep -q "^[^[:space:]]*[[:space:]]*[0-9]*.*[[:space:]]${process_name}$"
            else
                ps $ps_args | grep -q "$process_name"
            fi
            return $?
        fi
    fi

    # Fallback: проверка через /proc если доступен
    if [[ -d /proc ]]; then
        local found=false
        for pid_dir in /proc/[0-9]*; do
            if [[ -r "$pid_dir/comm" ]]; then
                local comm=$(cat "$pid_dir/comm" 2>/dev/null)
                if [[ "$exact_match" == "true" ]]; then
                    if [[ "$comm" == "$process_name" ]]; then
                        found=true
                        break
                    fi
                else
                    if [[ "$comm" == *"$process_name"* ]]; then
                        found=true
                        break
                    fi
                fi
            fi
        done

        if [[ "$found" == "true" ]]; then
            return 0
        else
            return 1
        fi
    fi

    log_warning "No method available to check process existence"
    return 2
}

# ============================================================================
# USER INFORMATION FUNCTIONS
# ============================================================================

# Кроссплатформенное получение домашней директории пользователя
get_user_home() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    # Метод 1: через getent (если доступен)
    if command_exists getent; then
        local home_dir=$(getent passwd "$username" 2>/dev/null | cut -d: -f6)
        if [[ -n "$home_dir" ]]; then
            echo "$home_dir"
            return 0
        fi
    fi

    # Метод 2: через /etc/passwd
    if [[ -f /etc/passwd ]]; then
        local home_dir=$(grep "^${username}:" /etc/passwd 2>/dev/null | cut -d: -f6)
        if [[ -n "$home_dir" ]]; then
            echo "$home_dir"
            return 0
        fi
    fi

    # Метод 3: через переменные окружения (если запрашиваем текущего пользователя)
    local current_user=$(whoami 2>/dev/null || echo "")
    if [[ "$username" == "$current_user" ]] && [[ -n "$HOME" ]]; then
        echo "$HOME"
        return 0
    fi

    # Fallback: стандартное расположение
    if [[ "$username" == "root" ]]; then
        echo "/root"
    else
        echo "/home/$username"
    fi

    return 0
}

# Кроссплатформенное получение shell пользователя
get_user_shell() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    # Метод 1: через getent (если доступен)
    if command_exists getent; then
        local user_shell=$(getent passwd "$username" 2>/dev/null | cut -d: -f7)
        if [[ -n "$user_shell" ]]; then
            echo "$user_shell"
            return 0
        fi
    fi

    # Метод 2: через /etc/passwd
    if [[ -f /etc/passwd ]]; then
        local user_shell=$(grep "^${username}:" /etc/passwd 2>/dev/null | cut -d: -f7)
        if [[ -n "$user_shell" ]]; then
            echo "$user_shell"
            return 0
        fi
    fi

    # Метод 3: через переменные окружения (если запрашиваем текущего пользователя)
    local current_user=$(whoami 2>/dev/null || echo "")
    if [[ "$username" == "$current_user" ]] && [[ -n "$SHELL" ]]; then
        echo "$SHELL"
        return 0
    fi

    # Fallback: определяем доступный shell
    local available_shells=("/bin/bash" "/bin/sh" "/usr/bin/bash")

    for shell in "${available_shells[@]}"; do
        if [[ -x "$shell" ]]; then
            echo "$shell"
            return 0
        fi
    done

    # Последний fallback
    echo "/bin/sh"
    return 0
}

# Получение UID пользователя (кроссплатформенно)
get_user_uid() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    # Метод 1: через id команду
    if command_exists id; then
        local uid=$(id -u "$username" 2>/dev/null)
        if [[ -n "$uid" ]]; then
            echo "$uid"
            return 0
        fi
    fi

    # Метод 2: через getent (если доступен)
    if command_exists getent; then
        local uid=$(getent passwd "$username" 2>/dev/null | cut -d: -f3)
        if [[ -n "$uid" ]]; then
            echo "$uid"
            return 0
        fi
    fi

    # Метод 3: через /etc/passwd
    if [[ -f /etc/passwd ]]; then
        local uid=$(grep "^${username}:" /etc/passwd 2>/dev/null | cut -d: -f3)
        if [[ -n "$uid" ]]; then
            echo "$uid"
            return 0
        fi
    fi

    log_error "Cannot determine UID for user: $username"
    return 1
}

# Получение GID пользователя (кроссплатформенно)
get_user_gid() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    # Метод 1: через id команду
    if command_exists id; then
        local gid=$(id -g "$username" 2>/dev/null)
        if [[ -n "$gid" ]]; then
            echo "$gid"
            return 0
        fi
    fi

    # Метод 2: через getent (если доступен)
    if command_exists getent; then
        local gid=$(getent passwd "$username" 2>/dev/null | cut -d: -f4)
        if [[ -n "$gid" ]]; then
            echo "$gid"
            return 0
        fi
    fi

    # Метод 3: через /etc/passwd
    if [[ -f /etc/passwd ]]; then
        local gid=$(grep "^${username}:" /etc/passwd 2>/dev/null | cut -d: -f4)
        if [[ -n "$gid" ]]; then
            echo "$gid"
            return 0
        fi
    fi

    log_error "Cannot determine GID for user: $username"
    return 1
}

# Получение GID по имени группы (кроссплатформенно)
get_group_gid() {
    local groupname="$1"

    if [[ -z "$groupname" ]]; then
        log_error "Group name is required"
        return 1
    fi

    # Метод 1: через getent group (если доступен)
    if command_exists getent; then
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

    log_error "Cannot determine GID for group: $groupname"
    return 1
}

# Проверка является ли пользователь членом группы
platform_user_in_group() {
    local username="$1"
    local groupname="$2"

    if [[ -z "$username" ]] || [[ -z "$groupname" ]]; then
        log_error "Both username and groupname are required"
        return 2
    fi

    # Метод 1: через groups команду
    if command_exists groups; then
        local user_groups=$(groups "$username" 2>/dev/null)
        if [[ -n "$user_groups" ]] && [[ "$user_groups" == *" $groupname "* || "$user_groups" == *" $groupname" || "$user_groups" == "$groupname "* || "$user_groups" == "$groupname" ]]; then
            return 0
        fi
    fi

    # Метод 2: через id команду
    if command_exists id; then
        local group_list=$(id -Gn "$username" 2>/dev/null)
        if [[ -n "$group_list" ]]; then
            # Преобразуем в массив и проверяем
            IFS=' ' read -ra user_groups_array <<< "$group_list"
            for group in "${user_groups_array[@]}"; do
                if [[ "$group" == "$groupname" ]]; then
                    return 0
                fi
            done
        fi
    fi

    # Метод 3: через /etc/group
    if [[ -f /etc/group ]]; then
        local group_line=$(grep "^${groupname}:" /etc/group 2>/dev/null)
        if [[ -n "$group_line" ]]; then
            local group_members=$(echo "$group_line" | cut -d: -f4)
            if [[ "$group_members" == *"$username"* ]]; then
                return 0
            fi
        fi
    fi

    return 1
}

# Получение полной информации о пользователе
get_user_info() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    if ! platform_user_exists "$username"; then
        log_error "User does not exist: $username"
        return 1
    fi

    log_info "User information for: $username"

    local uid=$(get_user_uid "$username")
    local gid=$(get_user_gid "$username")
    local home=$(get_user_home "$username")
    local shell=$(get_user_shell "$username")

    log_info "  UID: ${uid:-unknown}"
    log_info "  GID: ${gid:-unknown}"
    log_info "  Home: ${home:-unknown}"
    log_info "  Shell: ${shell:-unknown}"

    # Дополнительная информация о группах (если доступна)
    if command_exists groups; then
        local user_groups=$(groups "$username" 2>/dev/null)
        if [[ -n "$user_groups" ]]; then
            log_info "  Groups: $user_groups"
        fi
    fi

    return 0
}