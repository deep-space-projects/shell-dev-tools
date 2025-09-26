#!/bin/bash
# ============================================================================
# Advanced Permissions Management for Container Tools
# Universal permission handling with named parameters and flag validation
# ============================================================================

# ============================================================================
# FLAG SYSTEM DEFINITION
# ============================================================================

# Группы флагов (взаимоисключающие внутри группы)
declare -A FLAG_GROUPS=(
    ["existence"]="create required optional"
    ["error_handling"]="strict soft silent"
    ["target_type"]="file-only dir-only auto"
    ["recursion"]="recursive non-recursive"
    ["symlinks"]="follow-symlinks no-follow-symlinks"
)

# Действия (можно комбинировать) - используем подчеркивания для совместимости с bash
declare -A ACTION_FLAGS=(
    ["executable"]="Make .sh files executable"
    ["files_only"]="Apply permissions only to files"
    ["dirs_only"]="Apply permissions only to directories"
)

# Флаги по умолчанию для каждой группы
declare -A DEFAULT_FLAGS=(
    ["existence"]="optional"
    ["error_handling"]="soft"
    ["target_type"]="auto"
    ["recursion"]="recursive"
    ["symlinks"]="no-follow-symlinks"
)

# ============================================================================
# FLAG VALIDATION AND PARSING
# ============================================================================

# Валидация флагов на конфликты и неизвестные флаги
validate_flags() {
    local flags_string="$1"

    if [[ -z "$flags_string" ]]; then
        return 0
    fi

    IFS=',' read -ra array_flags <<< "$flags_string"

    # Проверяем конфликты внутри групп
    for group_name in "${!FLAG_GROUPS[@]}"; do
        local group_flags="${FLAG_GROUPS[$group_name]}"
        local found_flags=()

        for flag in "${array_flags[@]}"; do
            if [[ " $group_flags " == *" $flag "* ]]; then
                found_flags+=("$flag")
            fi
        done

        if [[ ${#found_flags[@]} -gt 1 ]]; then
            log_error "Conflicting flags in group '$group_name': ${found_flags[*]}"
            log_error "Available options: $group_flags"
            return 1
        fi
    done

    # Проверяем неизвестные флаги
    local all_known_flags=""
    for group_flags in "${FLAG_GROUPS[@]}"; do
        all_known_flags="$all_known_flags $group_flags"
    done
    # Добавляем action флаги (с дефисами для пользователей)
    all_known_flags="$all_known_flags executable files-only dirs-only"

    for flag in "${array_flags[@]}"; do
        if [[ " $all_known_flags " != *" $flag "* ]]; then
            log_error "Unknown flag: '$flag'"
            log_error "Available flags: $all_known_flags"
            return 1
        fi
    done

    return 0
}

# Парсинг флагов с установкой значений по умолчанию
parse_flags() {
    local flags_string="$1"

    # Инициализируем значениями по умолчанию
    for group_name in "${!DEFAULT_FLAGS[@]}"; do
        local var_name="FLAG_${group_name^^}"
        declare -g "$var_name"="${DEFAULT_FLAGS[$group_name]}"
    done

    # Инициализируем action флаги как false
    for action_flag in "${!ACTION_FLAGS[@]}"; do
        local var_name="ACTION_${action_flag^^}"
        declare -g "$var_name"="false"
    done

    if [[ -z "$flags_string" ]]; then
        return 0
    fi

    IFS=',' read -ra flags <<< "$flags_string"

    # Устанавливаем флаги из групп
    for flag in "${flags[@]}"; do
        # Проверяем в группах флагов
        for group_name in "${!FLAG_GROUPS[@]}"; do
            local group_flags="${FLAG_GROUPS[$group_name]}"
            if [[ " $group_flags " == *" $flag "* ]]; then
                local var_name="FLAG_${group_name^^}"
                declare -g "$var_name"="$flag"
                break
            fi
        done

        # Проверяем в action флагах - преобразуем дефисы в подчеркивания
        local action_key=$(echo "$flag" | tr '-' '_')
        if [[ -n "${ACTION_FLAGS[$action_key]:-}" ]]; then
            local var_name="ACTION_${action_key^^}"
            declare -g "$var_name"="true"
        fi
    done
}

# ============================================================================
# PATH TYPE DETERMINATION
# ============================================================================

# Определение типа пути
determine_path_type() {
    local path="$1"
    local type_flag="$FLAG_TARGET_TYPE"

    # Если явно указан тип
    case "$type_flag" in
        "file-only") echo "file"; return 0 ;;
        "dir-only") echo "directory"; return 0 ;;
    esac

    # Если путь существует - определяем реально
    if [[ -e "$path" ]]; then
        if [[ -f "$path" ]]; then
            echo "file"
        elif [[ -d "$path" ]]; then
            echo "directory"
        else
            echo "unknown"
        fi
        return 0
    fi

    if [[ "$type_flag" == "auto" ]]; then
        case "$FLAG_EXISTENCE" in
            "create")
                # Для create пытаемся угадать тип по расширению пути
                if [[ "$path" == */ ]]; then
                    echo "directory"
                elif [[ "$path" == *.* ]]; then
                    echo "file"
                else
                    echo "directory"  # По умолчанию директория
                fi
                return 0
                ;;
            "required")
                log_error "Required path does not exist: $path"
                return 1
                ;;
            "optional")
                # ✅ Для optional - возвращаем тип, но основная логика решит что делать
                echo "directory"  # По умолчанию директория (не важно, файл не будет обрабатываться)
                return 0
                ;;
        esac
    fi

    echo "unknown"
    return 1
}

# ============================================================================
# ERROR HANDLING
# ============================================================================

# Обработка ошибок согласно флагу error_handling
handle_permission_error() {
    local message="$1"
    local exit_code="${2:-1}"

    case "$FLAG_ERROR_HANDLING" in
        "strict")
            log_error "$message"
            return $exit_code
            ;;
        "soft")
            log_warning "$message"
            return 0
            ;;
        "silent")
            return 0
            ;;
        *)
            log_warning "$message"
            return 0
            ;;
    esac
}

# ============================================================================
# MAIN PERMISSIONS FUNCTION
# ============================================================================

# Главная функция установки прав
setup_permissions() {
    local path=""
    local owner=""
    local perms=""
    local dir_perms=""
    local file_perms=""
    local flags=""
    local privileged=false

    # Парсинг именованных параметров
    while [[ $# -gt 0 ]]; do
        case $1 in
            --privileged=*|--r=*)
                privileged="${1#*=}"
                shift
                ;;
            --path=*|--p=*)
                path="${1#*=}"
                shift
                ;;
            --owner=*|--o=*)
                owner="${1#*=}"
                shift
                ;;
            --perms=*)
                perms="${1#*=}"
                shift
                ;;
            --dir-perms=*)
                dir_perms="${1#*=}"
                shift
                ;;
            --file-perms=*)
                file_perms="${1#*=}"
                shift
                ;;
            --flags=*|--f=*)
                flags="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown parameter: $1"
                return 1
                ;;
        esac
    done

    # Проверяем обязательные параметры
    if [[ -z "$path" ]]; then
        log_error "Parameter --path is required"
        return 1
    fi

    if [[ -z "$owner" ]] && [[ -z "$perms" ]] && [[ -z "$dir_perms" ]] && [[ -z "$file_perms" ]]; then
        log_error "At least one of --owner, --perms, --dir-perms, --file-perms is required"
        return 1
    fi

    local needs_sudo=false
    if [[ "$privileged" == "True" ]] || [[ "$privileged" == "true" ]]; then
        if [[ $EUID -ne 0 ]]; then
            needs_sudo=true
        fi
    fi

    if [[ "$needs_sudo" == "true" ]]; then
        log_info "Re-running with administrator privileges..."
        sudo -E bash -c "
            source '${BASH_SOURCE[0]}'
            __setup_permissions '$path' '$owner' '$perms' '$dir_perms' '$file_perms' '$flags' '$privileged'
        "
    else
        __setup_permissions "$path" "$owner" "$perms" "$dir_perms" "$file_perms" "$flags" "$privileged"
    fi
}

__setup_permissions() {
    local path="$1"
    local owner="$2"
    local perms="$3"
    local dir_perms="$4"
    local file_perms="$5"
    local flags="$6"
    local privileged="$7"

    log_debug "Setting up permissions with UID: $EUID"

    # Валидируем и парсим флаги
    if ! validate_flags "$flags"; then
        return 1
    fi

    parse_flags "$flags"

    log_debug "Setting up permissions for: $path"
    log_debug "Flags: existence=$FLAG_EXISTENCE, error_handling=$FLAG_ERROR_HANDLING, type=$FLAG_TARGET_TYPE"

    # Определяем тип пути
    local path_type
    if ! path_type=$(determine_path_type "$path"); then
        return 1
    fi

    log_debug "Path type determined: $path_type"

    # Обрабатываем несуществующий путь
    if [[ ! -e "$path" ]]; then
        case "$FLAG_EXISTENCE" in
            "create")
                log_info "Creating missing path: $path"
                if [[ "$path_type" == "directory" ]] || [[ "$path" == */ ]]; then
                    if ! safe_mkdir "$path"; then
                        return $(handle_permission_error "Failed to create directory: $path")
                    fi
                elif [[ "$path_type" == "file" ]]; then
                    local parent_dir=$(dirname "$path")
                    if [[ ! -d "$parent_dir" ]]; then
                        if ! safe_mkdir "$parent_dir"; then
                            return $(handle_permission_error "Failed to create parent directory: $parent_dir")
                        fi
                    fi
                    if ! touch "$path"; then
                        return $(handle_permission_error "Failed to create file: $path")
                    fi
                fi
                ;;
            "required")
                return $(handle_permission_error "Required path does not exist: $path")
                ;;
            "optional")
                handle_permission_error "Optional path does not exist, skipping: $path"
                return 0
                ;;
        esac
    fi

    # Устанавливаем владельца
    if [[ -n "$owner" ]]; then
        log_debug "Setting owner to: $owner"

        local chown_args=""
        if [[ "$FLAG_RECURSION" == "recursive" ]]; then
            chown_args="-R"
        fi
        if [[ "$FLAG_SYMLINKS" == "follow-symlinks" ]]; then
            chown_args="$chown_args -L"
        fi

        if ! chown $chown_args "$owner" "$path" 2>/dev/null; then
            handle_permission_error "Failed to set owner '$owner' on '$path'"
        else
            log_debug "Successfully set owner: $owner"
        fi
    fi

    # Устанавливаем права доступа
    if [[ "$path_type" == "file" ]] || [[ "$FLAG_RECURSION" == "non-recursive" ]]; then
        # Для файлов или non-recursive
        local target_perms="$perms"
        if [[ -n "$target_perms" ]]; then
            log_debug "Setting permissions to: $target_perms"
            if ! chmod "$target_perms" "$path" 2>/dev/null; then
                handle_permission_error "Failed to set permissions '$target_perms' on '$path'"
            else
                log_debug "Successfully set permissions: $target_perms"
            fi
        fi
    else
        # Для директорий с рекурсией
        if [[ -n "$dir_perms" ]] && [[ "$ACTION_DIRS_ONLY" == "true" || "$ACTION_FILES_ONLY" != "true" ]]; then
            log_debug "Setting directory permissions to: $dir_perms"
            if ! platform_chmod_recursive "$dir_perms" "$path" "dirs"; then
                handle_permission_error "Failed to set directory permissions '$dir_perms' on '$path'"
            else
                log_debug "Successfully set directory permissions: $dir_perms"
            fi
        fi

        if [[ -n "$file_perms" ]] && [[ "$ACTION_FILES_ONLY" == "true" || "$ACTION_DIRS_ONLY" != "true" ]]; then
            log_debug "Setting file permissions to: $file_perms"
            if ! platform_chmod_recursive "$file_perms" "$path" "files"; then
                handle_permission_error "Failed to set file permissions '$file_perms' on '$path'"
            else
                log_debug "Successfully set file permissions: $file_perms"
            fi
        fi

        # Если только --perms указан для директории
        if [[ -n "$perms" ]] && [[ -z "$dir_perms" ]] && [[ -z "$file_perms" ]]; then
            log_debug "Setting universal permissions to: $perms"
            if ! platform_chmod_recursive "$perms" "$path" "all"; then
                handle_permission_error "Failed to set permissions '$perms' on '$path'"
            else
                log_debug "Successfully set permissions: $perms"
            fi
        fi
    fi

    # Обрабатываем executable флаг
    if [[ "$ACTION_EXECUTABLE" == "true" ]]; then
        log_debug "Making shell scripts executable"
        local script_files=()
        while IFS= read -r -d '' file; do
            script_files+=("$file")
        done < <(find "$path" -name "*.sh" -type f -print0 2>/dev/null)

        if [[ ${#script_files[@]} -gt 0 ]]; then
            log_info "Making ${#script_files[@]} shell scripts executable"
            for script_file in "${script_files[@]}"; do
                if ! chmod 755 "$script_file" 2>/dev/null; then
                    handle_permission_error "Failed to make executable: $script_file"
                else
                    log_debug "Made executable: $(basename "$script_file")"
                fi
            done
        else
            log_debug "No shell scripts found to make executable"
        fi
    fi

    log_success "Permissions setup completed for: $path"
    return 0
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