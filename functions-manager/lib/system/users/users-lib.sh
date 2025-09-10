#!/bin/bash
# ============================================================================
# Platform-specific Command Wrappers
# Provides cross-platform compatibility for common operations
# ============================================================================

# ============================================================================
# USER MANAGEMENT COMMANDS
# ============================================================================

# Кроссплатформенное переключение пользователя и выполнение команды
switch_user() {
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
is_user_exists() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    get_user_uid $username
    return $?
}

# Подготовка окружения для пользователя
prepare_user_environment() {
    local target_user="$1"
    local create_home="${2:-false}"

    if [[ -z "$target_user" ]]; then
        log_error "Target user is required"
        return 1
    fi

    if ! is_user_exists "$target_user"; then
        log_error "Target user does not exist: $target_user"
        return 1
    fi

    log_info "Preparing environment for user: $target_user"

    # Получаем информацию о пользователе
    local user_home=$(get_user_home "$target_user")
    local user_shell=$(get_user_shell "$target_user")
    local user_uid=$(get_user_uid "$target_user")
    local user_gid=$(get_user_gid "$target_user")

    # Экспортируем переменные окружения
    export USER="$target_user"
    export HOME="$user_home"
    export SHELL="$user_shell"
    export LOGNAME="$target_user"

    log_debug "Environment prepared:"
    log_debug "  USER=$USER"
    log_debug "  HOME=$HOME"
    log_debug "  SHELL=$SHELL"
    log_debug "  LOGNAME=$LOGNAME"

    # Создаем домашнюю директорию если нужно
    if [[ "$create_home" == "true" ]] && [[ ! -d "$user_home" ]]; then
        log_info "Creating home directory: $user_home"
        if mkdir -p "$user_home" 2>/dev/null; then
            # Устанавливаем правильного владельца
            if [[ $EUID -eq 0 ]]; then
                chown "$user_uid:$user_gid" "$user_home" 2>/dev/null || {
                    log_warning "Could not set ownership of home directory"
                }
                chmod 755 "$user_home" 2>/dev/null || {
                    log_warning "Could not set permissions of home directory"
                }
            fi
            log_success "Home directory created: $user_home"
        else
            log_warning "Failed to create home directory: $user_home"
        fi
    fi

    return 0
}

# Кроссплатформенное получение домашней директории пользователя
get_user_home() {
    local username="$1"

    if [[ -z "$username" ]]; then
        log_error "Username is required"
        return 1
    fi

    # Метод 1: через getent (если доступен)
    if command -v getent >/dev/null 2>&1; then
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
    if command -v getent >/dev/null 2>&1; then
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
    if command -v id >/dev/null 2>&1; then
        local uid=$(id -u "$username" 2>/dev/null)
        if [[ -n "$uid" ]]; then
            echo "$uid"
            return 0
        fi
    fi

    # Метод 2: через getent (если доступен)
    if command -v getent >/dev/null 2>&1; then
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
    if command -v id >/dev/null 2>&1; then
        local gid=$(id -g "$username" 2>/dev/null)
        if [[ -n "$gid" ]]; then
            echo "$gid"
            return 0
        fi
    fi

    # Метод 2: через getent (если доступен)
    if command -v getent >/dev/null 2>&1; then
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

# Проверка является ли пользователь членом группы
is_user_in_group() {
    local username="$1"
    local groupname="$2"

    if [[ -z "$username" ]] || [[ -z "$groupname" ]]; then
        log_error "Both username and groupname are required"
        return 2
    fi

    # Метод 1: через groups команду
    if command -v groups >/dev/null 2>&1; then
        local user_groups=$(groups "$username" 2>/dev/null)
        if [[ -n "$user_groups" ]] && [[ "$user_groups" == *" $groupname "* || "$user_groups" == *" $groupname" || "$user_groups" == "$groupname "* || "$user_groups" == "$groupname" ]]; then
            return 0
        fi
    fi

    # Метод 2: через id команду
    if command -v id >/dev/null 2>&1; then
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

    if ! is_user_exists "$username"; then
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
    if command -v groups >/dev/null 2>&1; then
        local user_groups=$(groups "$username" 2>/dev/null)
        if [[ -n "$user_groups" ]]; then
            log_info "  Groups: $user_groups"
        fi
    fi

    return 0
}

export -f get_user_info get_user_home get_user_shell get_user_uid get_user_gid
export -f is_user_exists is_user_in_group
export -f switch_user prepare_user_environment