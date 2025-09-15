#!/bin/bash

uninstall() {
    local all=false
    local modules=""
    local verbose=false
    local interactive=false
    local daemon=false
    local error_policy="strict"

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                all=true
                shift
                ;;
            --modules=*)
                modules="${1#*=}"
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -d|--daemon)
                daemon=true
                shift
                ;;
            --error-policy=*)
                error_policy="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Валидация обязательных параметров
    if [[ "$interactive" == false && "$daemon" == false ]]; then
        log_error "Must specify either --interactive or --daemon"
        exit 1
    fi

    if [[ "$interactive" == true && "$daemon" == true ]]; then
        log_error "Cannot specify both --interactive and --daemon"
        exit 1
    fi

    if [[ "$all" == false && -z "$modules" ]]; then
        log_error "Must specify either --all or --modules"
        exit 1
    fi

    # Установка verbose режима
    if [[ "$verbose" == true ]]; then
        logger_set_level DEBUG
    fi

    # Установка политики ошибок
    set_error_policy "$error_policy"

    log_header "Starting Module Uninstallation"

    # Централизованная конфигурация путей
    local target_lib_dir="/usr/local/lib/devtools/packages"
    local target_bin_dir=$(get_system_bin_dir)

    log_info "Target lib dir: $target_lib_dir"
    log_info "Target bin dir: $target_bin_dir"

    # 1. Поиск установленных модулей
    log_step 1 "Discovering installed modules"
    local installed_modules
    if ! installed_modules=$(discover_installed_modules "$target_lib_dir"); then
        log_error "Failed to discover installed modules"
        exit 1
    fi

    if [[ -z "$installed_modules" ]]; then
        log_info "No dev-tools modules found in system"
        exit 0
    fi

    local installed_count=$(echo "$installed_modules" | wc -l)
    log_success "Found $installed_count installed modules"

    # Показываем найденные модули
    log_info "Installed modules:"
    while IFS= read -r module_name; do
        if [[ -n "$module_name" ]]; then
            log_info "  - $module_name"
        fi
    done <<< "$installed_modules"

    # 2. Определяем модули для удаления
    log_step 2 "Selecting modules for removal"
    local modules_to_remove
    if [[ "$all" == true ]]; then
        modules_to_remove="$installed_modules"
        log_info "Selected all modules for removal"
    else
        modules_to_remove=$(select_modules_for_removal "$modules" "$installed_modules")
        if [[ -z "$modules_to_remove" ]]; then
            log_warning "No valid modules selected for removal"
            exit 0
        fi
    fi

    local removal_count=$(echo "$modules_to_remove" | wc -l)
    log_success "Selected $removal_count modules for removal"

    # 3. Интерактивное подтверждение (если включено)
    if [[ "$interactive" == true ]]; then
        log_info "About to remove $removal_count modules:"
        while IFS= read -r module_name; do
            if [[ -n "$module_name" ]]; then
                log_info "  - $module_name"
            fi
        done <<< "$modules_to_remove"

        echo -n "Proceed with removal? [y/N]: "
        read -r response
        if [[ "$response" != [yY] && "$response" != [yY][eE][sS] ]]; then
            log_info "Uninstallation cancelled by user"
            exit 0
        fi
    fi

    # Удаление модулей
    log_step 3 "Removing modules"
    if ! remove_modules "$modules_to_remove" "$target_lib_dir" "$target_bin_dir"; then
        log_error "Module removal failed"
        exit 1
    fi

    # 4. Удаление повисших ссылок
    log_step 4 "Removing hanging symlink"
    if ! remove_hanging_symlinks "$target_bin_dir"; then
        log_error "Hanging symlinks removal failed"
        exit 1
    fi

    log_success "Uninstallation completed successfully!"
    log_info "Removed $removal_count modules"
}

# Поиск установленных модулей
discover_installed_modules() {
    local target_lib_dir="$1"

    if [[ ! -d "$target_lib_dir" ]]; then
        log_debug "Dev-tools directory not found: $target_lib_dir"
        return 0
    fi

    local found_modules=()

    # Ищем директории модулей
    for module_dir in "$target_lib_dir"/*/; do
        if [[ -d "$module_dir" ]]; then
            local module_name=$(basename "${module_dir%/}")

            # Проверяем что это валидный модуль dev-tools
            if [[ -f "$module_dir/bin/$module_name.sh" ]]; then
                found_modules+=("$module_name")
            fi
        fi
    done

    # Возвращаем найденные модули
    printf '%s\n' "${found_modules[@]}"
    return 0
}

# Выбор модулей для удаления из списка
select_modules_for_removal() {
    local requested_modules="$1"
    local installed_modules="$2"

    local selected_modules=()

    # Разбиваем запрошенные модули по запятым
    IFS=',' read -ra requested_array <<< "$requested_modules"

    for requested_module in "${requested_array[@]}"; do
        # Удаляем лишние пробелы
        requested_module="${requested_module// /}"

        if [[ -z "$requested_module" ]]; then
            continue
        fi

        # Проверяем что модуль установлен
        local found=false
        while IFS= read -r installed_module; do
            if [[ "$installed_module" == "$requested_module" ]]; then
                selected_modules+=("$requested_module")
                found=true
                break
            fi
        done <<< "$installed_modules"

        if [[ "$found" == false ]]; then
            log_warning "Module not found or not installed: $requested_module"
        fi
    done

    # Возвращаем выбранные модули
    printf '%s\n' "${selected_modules[@]}"
    return 0
}

# Удаление модулей
remove_modules() {
    local modules_to_remove="$1"
    local target_lib_dir="$2"
    local target_bin_dir="$3"

    local removed_modules=()
    local failed_modules=()

    # Удаляем каждый модуль
    while IFS= read -r module_name; do
        if [[ -n "$module_name" ]]; then
            log_debug "Removing module: $module_name"

            if remove_single_module "$module_name" "$target_lib_dir" "$target_bin_dir"; then
                removed_modules+=("$module_name")
                log_success "Module removed: $module_name"
            else
                failed_modules+=("$module_name")
                log_error "Failed to remove module: $module_name"
            fi
        fi
    done <<< "$modules_to_remove"

    # Проверяем результаты удаления
    local removed_count=${#removed_modules[@]}
    local failed_count=${#failed_modules[@]}

    log_info "Module removal results: $removed_count successful, $failed_count failed"

    if [[ $failed_count -gt 0 ]]; then
        handle_operation_error_quite "remove_modules" "Failed module removals: ${failed_modules[*]}" 1
    fi

    if [[ $removed_count -eq 0 ]]; then
        return $(handle_operation_error_quite "remove_modules" "No modules were successfully removed" 1)
    fi

    # Очищаем пустую директорию devtools если все модули удалены
    if [[ -d "$target_lib_dir" ]] && [[ -z "$(ls -A "$target_lib_dir" 2>/dev/null)" ]]; then
        log_info "Removing empty devtools directory: $target_lib_dir"
        if rmdir "$target_lib_dir" 2>/dev/null; then
            log_success "Empty devtools directory removed"
        else
            log_warning "Failed to remove empty devtools directory"
        fi
    fi

    return 0
}

# Удаление одного модуля
remove_single_module() {
    local module_name="$1"
    local target_lib_dir="$2"
    local target_bin_dir="$3"

    local module_lib_dir="$target_lib_dir/$module_name"
    local module_symlink="$target_bin_dir/$module_name"

    # Удаляем симлинк
    if [[ -L "$module_symlink" ]]; then
        log_debug "Removing symlink: $module_symlink"
        if ! rm -f "$module_symlink" 2>/dev/null; then
            log_error "Failed to remove symlink: $module_symlink"
            return 1
        fi
        log_debug "Symlink removed: $module_symlink"
    elif [[ -e "$module_symlink" ]]; then
        log_warning "Target exists but is not a symlink: $module_symlink"
    fi

    # Удаляем директорию модуля
    if [[ -d "$module_lib_dir" ]]; then
        log_debug "Removing module directory: $module_lib_dir"
        if ! rm -rf "$module_lib_dir" 2>/dev/null; then
            log_error "Failed to remove module directory: $module_lib_dir"
            return 1
        fi
        log_debug "Module directory removed: $module_lib_dir"
    else
        log_warning "Module directory not found: $module_lib_dir"
    fi

    return 0
}

# удаление повисших симлинков после чистки пакетов
remove_hanging_symlinks() {
  local target_bin_dir=$1
  find $target_bin_dir -type l ! -exec test -e {} \; -print -delete
}


uninstall "$@"