#!/bin/bash
# ============================================================================
# Working Directories Permissions Implementation - Standard Mode
# Real execution of working directories permissions setup
# ============================================================================

# Список запрещенных директорий по умолчанию
DEFAULT_RESTRICTED_DIRS=(
    "/"
    "/bin"
    "/boot"
    "/dev"
    "/etc"
    "/lib"
    "/lib32"
    "/lib64"
    "/proc"
    "/root"
    "/run"
    "/sbin"
    "/sys"
    "/usr"
    "/var/lib"
    "/var/run"
    "/var/spool"
)

# Показать политику ограничений
show_restrictions_policy() {
    tlog info "Restricted directories policy:"
    if [[ -n "${CONTAINER_WORKING_DIRS_RESTRICTIONS:-}" ]]; then
        tlog info "  Custom restrictions: $CONTAINER_WORKING_DIRS_RESTRICTIONS"
    else
        tlog info "  Using default system restrictions (/, /bin, /boot, /dev, /etc, /lib, /proc, /root, /run, /sbin, /sys, /usr, /var/lib, /var/run, /var/spool)"
    fi
}

# Получить список запрещенных директорий
get_restricted_directories() {
    local restricted_dirs=()

    if [[ -n "${CONTAINER_WORKING_DIRS_RESTRICTIONS:-}" ]]; then
        tlog debug "Using custom restricted directories: $CONTAINER_WORKING_DIRS_RESTRICTIONS"
        IFS=',' read -ra restricted_dirs <<< "$CONTAINER_WORKING_DIRS_RESTRICTIONS"
    else
        tlog debug "Using default restricted directories"
        restricted_dirs=("${DEFAULT_RESTRICTED_DIRS[@]}")
    fi

    # Нормализуем пути (убираем trailing slash)
    local normalized_dirs=()
    for dir in "${restricted_dirs[@]}"; do
        dir="${dir%/}"  # Remove trailing slash
        [[ -n "$dir" ]] && normalized_dirs+=("$dir")
    done

    printf '%s\n' "${normalized_dirs[@]}"
}

# Проверить, разрешена ли директория для модификации
is_directory_allowed() {
    local target_dir="$1"
    local restricted_dirs

    # Нормализуем целевой путь
    target_dir="${target_dir%/}"
    [[ "$target_dir" == "" ]] && target_dir="/"

    # Получаем список запрещенных директорий
    mapfile -t restricted_dirs < <(get_restricted_directories)

    # Проверяем каждую запрещенную директорию
    for restricted in "${restricted_dirs[@]}"; do
        if [[ "$target_dir" == "$restricted" ]] || [[ "$target_dir" == "$restricted"/* ]]; then
            tlog debug "Directory '$target_dir' matches restriction '$restricted'"
            return 1
        fi
    done

    tlog debug "Directory '$target_dir' is allowed for modification"
    return 0
}

# Проверить доступность директории для записи
validate_directory_access() {
    local dir_path="$1"

    # Проверяем существование директории
    if [[ ! -e "$dir_path" ]]; then
        tlog debug "Directory does not exist: $dir_path"
        return 0
    fi

    # Проверяем, что это директория
    if [[ ! -d "$dir_path" ]]; then
        tlog debug "Path is not a directory: $dir_path"
        return 1
    fi

    # Проверяем права на запись (если мы root)
    if [[ $EUID -eq 0 ]]; then
        tlog debug "Running as root, should have access to: $dir_path"
        return 0
    fi

    # Проверяем права на запись для не-root пользователя
    if [[ -w "$dir_path" ]]; then
        tlog debug "Directory is writable: $dir_path"
        return 0
    fi

    tlog debug "Directory is not writable: $dir_path"
    return 1
}

# Настроить разрешения для рабочей директории
setup_working_directory_permissions() {
    local dir_path="$1"
    local owner_string="$CONTAINER_UID:$CONTAINER_GID"

    # РЕАЛЬНЫЕ ПРОВЕРКИ БЕЗОПАСНОСТИ
    if ! is_directory_allowed "$dir_path"; then
        tlog error "Directory '$dir_path' is restricted and cannot be modified"
        return 1
    fi

    # РЕАЛЬНАЯ ПРОВЕРКА ДОСТУПНОСТИ
    if ! validate_directory_access "$dir_path"; then
        tlog error "Directory '$dir_path' is not accessible or does not exist"
        return 1
    fi

    # РЕАЛЬНОЕ УСТАНОВЛЕНИЕ РАЗРЕШЕНИЙ через setup_permissions
    tlog debug "Setting up permissions for working directory: $dir_path (owner: $owner_string)"

    if ! permissions setup \
        --path="$dir_path" \
        --owner="$owner_string" \
        --dir-perms="755" \
        --file-perms="744" \
        --flags="create,strict,recursive"; then
        tlog error "Failed to set permissions for working directory: $dir_path"
        return 1
    fi

    tlog success "Successfully set permissions for working directory: $dir_path"
    return 0
}

# Проверить владельца директории используя platform функции
verify_directory_owner() {
    local dir_path="$1"
    local expected_uid="$2"
    local expected_gid="$3"

    # Получаем текущего владельца через platform функции
    local current_uid current_gid

    # Используем ls -ld как платформонезависимый метод
    local ls_output
    ls_output=$(ls -ld "$dir_path" 2>/dev/null) || {
        tlog warning "Could not get file information for: $dir_path"
        return 1
    }

    # Извлекаем владельца и группу (3-е и 4-е поля)
    local owner_name group_name
    owner_name=$(echo "$ls_output" | awk '{print $3}')
    group_name=$(echo "$ls_output" | awk '{print $4}')

    # Конвертируем имена в UID/GID если нужно
    if [[ "$owner_name" =~ ^[0-9]+$ ]]; then
        current_uid="$owner_name"
    else
        current_uid=$(users get-uid "$owner_name" 2>/dev/null) || {
            tlog warning "Could not resolve UID for user: $owner_name"
            return 1
        }
    fi

    if [[ "$group_name" =~ ^[0-9]+$ ]]; then
        current_gid="$group_name"
    else
        current_gid=$(groups get-uid "$group_name" 2>/dev/null) || {
            tlog warning "Could not resolve GID for group: $group_name"
            return 1
        }
    fi

    # Проверяем соответствие
    if [[ "$current_uid" != "$expected_uid" ]] || [[ "$current_gid" != "$expected_gid" ]]; then
        tlog warning "Owner mismatch for '$dir_path': expected '$expected_uid:$expected_gid', got '$current_uid:$current_gid'"
        return 1
    fi

    tlog debug "Owner verification passed for: $dir_path ($current_uid:$current_gid)"
    return 0
}

# Проверить права доступа директории (упрощенная кроссплатформенная версия)
verify_directory_permissions() {
    local dir_path="$1"

    # Базовая проверка - доступность на чтение и выполнение
    if [[ ! -r "$dir_path" ]] || [[ ! -x "$dir_path" ]]; then
        tlog warning "Directory permissions insufficient: $dir_path"
        return 1
    fi

    # Если владелец директории - это наш целевой пользователь, проверяем запись
    if [[ -w "$dir_path" ]]; then
        tlog debug "Directory permissions verified: $dir_path (readable, writable, executable)"
    else
        tlog debug "Directory permissions verified: $dir_path (readable, executable)"
    fi

    return 0
}

# Проверить разрешения всех рабочих директорий
verify_working_directories_permissions() {
    local processed_dirs=("$@")
    local verification_errors=0

    for working_dir in "${processed_dirs[@]}"; do
        tlog debug "Verifying permissions for working directory: $working_dir"

        # РЕАЛЬНАЯ ПРОВЕРКА СУЩЕСТВОВАНИЯ
        if [[ ! -d "$working_dir" ]]; then
            tlog warning "Directory does not exist: $working_dir"
            ((verification_errors++))
            continue
        fi

        # РЕАЛЬНАЯ ПРОВЕРКА ВЛАДЕЛЬЦА через platform функции
        if ! verify_directory_owner "$working_dir" "$CONTAINER_UID" "$CONTAINER_GID"; then
            ((verification_errors++))
        fi

        # РЕАЛЬНАЯ ПРОВЕРКА РАЗРЕШЕНИЙ (кроссплатформенная)
        if ! verify_directory_permissions "$working_dir"; then
            ((verification_errors++))
        fi

        tlog debug "Permissions verified successfully for: $working_dir"
    done

    if [[ $verification_errors -gt 0 ]]; then
        tlog warning "Permissions verification completed with $verification_errors errors"
        return 1
    fi

    tlog success "All working directories permissions verified successfully"
    return 0
}