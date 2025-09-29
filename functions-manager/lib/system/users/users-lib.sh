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

    log_warning "Cannot determine UID for user: $username"
    return 1
}

# Получение имени пользователя по UID (кроссплатформенно)
get_username_by_uid() {
    local uid="$1"

    if [[ -z "$uid" ]]; then
        log_error "UID is required"
        return 1
    fi

    # Проверяем, что UID - это число
    if ! [[ "$uid" =~ ^[0-9]+$ ]]; then
        log_error "UID must be a numeric value"
        return 1
    fi

    # Метод 1: через id команду
    if command -v id >/dev/null 2>&1; then
        local username=$(id -nu "$uid" 2>/dev/null)
        if [[ -n "$username" ]]; then
            echo "$username"
            return 0
        fi
    fi

    # Метод 2: через getent (если доступен)
    if command -v getent >/dev/null 2>&1; then
        local username=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
        if [[ -n "$username" ]]; then
            echo "$username"
            return 0
        fi
    fi

    # Метод 3: через /etc/passwd
    if [[ -f /etc/passwd ]]; then
        local username=$(awk -F: -v uid="$uid" '$3 == uid {print $1}' /etc/passwd 2>/dev/null)
        if [[ -n "$username" ]]; then
            echo "$username"
            return 0
        fi
    fi

    log_warning "Cannot determine username for UID: $uid"
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

    log_warning "Cannot determine GID for user: $username"
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

# Создать пользователя или обработать кейс с уже существующим пользователем (платформо-независимо)
create_user() {
    local on_exist_mode="return"
    local update_mode=""
    local username=""
    local uid=""
    local groupname=""

    while [ $# -gt 0 ]; do
        case $1 in
            --on-exist=*)
                on_exist_mode="${1#*=}"
                shift
                ;;
            --update-mode=*)
                update_mode="${1#*=}"
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$username" ]]; then
                    username="$1"
                elif [[ -z "$uid" ]]; then
                    uid="$1"
                elif [[ -z "$groupname" ]]; then
                    groupname="$1"
                else
                    echo "Too many arguments" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    log_info "Execute create user command with arguments:
    --username=$username
    --uid=$uid
    --new group=$groupname"

    if [[ -z "$username" ]] || [[ ! "$username" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
        log_error "User name is required"
        return 1
    fi

    if [[ -z "$uid" ]] || [[ ! "$uid" =~ ^([1-9][0-9]{0,4}|0)$ ]] ; then
        log_error "User UID is required"
        return 1
    fi

    if [[ -z "$groupname" ]] || [[ ! "$groupname" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
        log_error "Group name is required"
        return 1
    fi

    if is_user_exists "$username"; then

        if [[ $(get_user_uid $username) == $uid &&  $(get_user_gid $username) == $(get_group_uid $groupname) ]]; then
            log_info "Current user already exists: $username"
            return 0
        fi

        case $on_exist_mode in
            fail)
                log_error "User already exists: $username"
                return 1
                ;;
            update)
                replace_user --update-mode=$update_mode $username $username $uid $groupname
                return $?
                ;;
            return)
                log_info "User already exists: $username"
                return 0
                ;;
            *)
                ;;
        esac
    else
        local os_family=$(detect_os_family)

        if [[ -z "$os_family" ]]; then
            log_error "Undefined OS"
            return 1
        fi

        case "$os_family" in
            "debian"|"rhel")
                if ! command -v useradd >/dev/null 2>&1; then
                    log_error "\$(useradd) function not found in $os_family family system!"
                    return 1
                fi

                create_user_with_useradd $username $uid $groupname
                ;;
            "alpine")
                if ! command -v adduser >/dev/null 2>&1; then
                    log_error "\$(adduser) function not found in $os_family family system!"
                    return 1
                fi

                create_user_with_adduser $username $uid $groupname
                ;;
            *)
                log_error "Unknown OS family: $os_family"
                return 1
                ;;
        esac
    fi

    log_success "Successfully created user: $username with UID: $uid in group: $groupname"
}

replace_user() {
    local update_mode="full"
    local old_username=""
    local new_username=""
    local new_uid=""
    local new_groupname=""
    local new_gid=""

    while [ $# -gt 0 ]; do
        case $1 in
            --update-mode=*)
                update_mode="${1#*=}"
                shift
                ;;
            -*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
            *)
                if [[ -z "$old_username" ]]; then
                    old_username="$1"
                elif [[ -z "$new_username" ]]; then
                    new_username="$1"
                elif [[ -z "$new_uid" ]]; then
                    new_uid="$1"
                elif [[ -z "$new_groupname" ]]; then
                    new_groupname="$1"
                else
                    echo "Too many arguments" >&2
                    return 1
                fi
                shift
                ;;
        esac
    done

    log_info "Execute replace user command with arguments and update $update_mode mode:
    --old username=$old_username
    --new username=$new_username
    --new uid=$new_uid
    --new group=$new_groupname"

    if [[ -z "$old_username" ]] || [[ ! "$old_username" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
        log_error "Old user name $old_username is required"
        return 1
    fi

    if ! is_user_exists $old_username; then
        log_error "Old user name $old_username does not exists"
        return 1
    fi

    if [[ -z "$new_username" ]] || [[ ! "$new_username" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
        log_error "New user name $new_username is required"
        return 1
    fi

    if [[ -z "$new_groupname" ]] || [[ ! "$new_groupname" =~ ^[a-zA-Z][a-zA-Z0-9_-]+$ ]]; then
        log_error "New group name $new_groupname is required"
        return 1
    fi

    if ! is_group_exists $new_groupname; then
        log_error "New group name $new_username does not exists"
        return 1
    fi

    if [[ -z "$new_uid" ]] || [[ ! "$new_uid" =~ ^[1-9][0-9]{0,4}$ ]] ; then
        log_error "User UID is required"
        return 1
    fi

    new_gid=$(get_group_uid $new_groupname)
    if [[ -z "$new_gid" ]] || [[ ! "$new_gid" =~ ^[1-9][0-9]{0,4}$ ]] ; then
        log_error "Group UID is undefined"
        return 1
    fi

    if [[ ! $update_mode =~ ^(just|full)$ ]]; then
        log_error "Unknown or undefined update mode: $update_mode"
        return 1
    fi

    if ! command -v usermod >/dev/null 2>&1; then
        log_error "\$(usermod) not available!"
        return 1
    fi

    # Получаем старый UID
    local old_uid
    old_uid=$(get_user_uid "$old_username")

    # изменяем старое имя пользователя на новое (теперь у )
    if [[ "$new_username" != "$old_username" ]]; then

        if is_user_exists $new_username; then
            # нельзя заменять пользователя который уже существует
            log_error "New user name $new_username already exists"
            return 1
        fi

        if ! usermod -l "$new_username" "$old_username"; then
            log_error "Could not change username from $old_username to $new_username"
            return 1
        fi

    fi

    # обозначаем что теперь у нас ОДИН username и два разных uid, которые требуется заменить
    local username=$new_username

    if usermod -u "$new_uid" -g "$new_groupname" "$username"; then
        log_success "User $username updated successfully from old $old_uid to new uid $new_uid and group:$new_groupname"

        # Исправляем права на файлы если UID изменился
        if [[ -n "$old_uid" && "$old_uid" != "$new_uid" ]] && [[ $update_mode == "full" ]]; then
            log_info "User UID changed from $old_uid to $new_uid - fixing file ownership"

            # Обновляем права в основных директориях
            # Используем переменную CHOWN_DIRS, если пуста - берем значения по умолчанию
            local chown_dirs="${USERS_CMD_REPLACE_CHOWN_DIRS:-/home,/opt,/var,/tmp,/etc,/usr,/data,/run}"
            # Заменяем запятые на пробелы
            chown_dirs="${chown_dirs//,/ }"

            log_info "Updating file ownership from UID $old_uid to $new_uid:$new_gid, for root dirs: ${chown_dirs}"

            for dir in ${chown_dirs}; do
                if [[ -d "$dir" ]]; then
                    log_debug "Checking directory: $dir"
                    find "$dir" -user "$old_uid" -print -exec chown "$new_uid:$new_gid" {} + 2>/dev/null || true
                fi
            done

            log_success "File ownership from $old_uid to $new_uid:$new_gid update completed"
        else
            log_warning "Update user $new_uid proceed, but not in full-mode. That means some system files could leave under $old_uid ownership!"
        fi
    else
        log_error "Failed to update user $new_uid with \$(usermod)!"
        return 1
    fi

    log_success "Successfully replaced user $old_username to $username with UID $new_uid in group $new_groupname"
}

# Создание пользователя с помощью useradd
create_user_with_useradd() {
    local user_name="$1"
    local user_id="$2"
    local group_name="$3"

    log_debug "Using useradd to create user"

    # Пытаемся создать с домашней директорией и bash
    if useradd -u "$user_id" -g "$group_name" -m -s /bin/bash "$user_name" 2>/dev/null; then
        log_success "User created with home directory: $user_name"
        return 0
    # Если не получилось, создаем без домашней директории
    elif useradd -u "$user_id" -g "$group_name" "$user_name"; then
        log_success "User created without home directory: $user_name"
        return 0
    else
        log_error "Failed to create user with useradd"
        return 1
    fi
}

# Создание пользователя с помощью adduser (BusyBox)
create_user_with_adduser() {
    local user_name="$1"
    local user_id="$2"
    local group_name="$3"

    log_debug "Using adduser (BusyBox) to create user"
    if adduser -u "$user_id" -G "$group_name" -D -s /bin/bash "$user_name"; then
        log_success "User created with adduser: $user_name"
        return 0
    else
        log_error "Failed to create user with adduser"
        return 1
    fi
}

export -f get_user_info get_user_home get_user_shell get_user_uid get_user_gid
export -f is_user_exists is_user_in_group
export -f switch_user prepare_user_environment