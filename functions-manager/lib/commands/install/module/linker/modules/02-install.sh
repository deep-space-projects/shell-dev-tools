#!/bin/bash
# ============================================================================
# Linker: Installation
# Installs modules from temporary directory to system locations
# ============================================================================

main() {
    local temp_dir="$1"
    local validated_modules="$2"
    local target_lib_dir="$3"
    local target_bin_dir="$4"

    log_debug "Installing modules to system directories"

    local installed_modules=()
    local failed_modules=()

    # Устанавливаем каждый модуль
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            local module_name=$(basename "$module_path")
            local module_temp_dir="$temp_dir/$module_name"
            local target_module_dir="$target_lib_dir/$module_name"

            log_debug "Installing module: $module_name"

            if install_single_module "$module_temp_dir" "$target_module_dir" "$module_name"; then
                installed_modules+=("$module_name")
                log_debug "Module installed successfully: $module_name"
            else
                failed_modules+=("$module_name")
                log_error "Module installation failed: $module_name"
            fi
        fi
    done <<< "$validated_modules"

    # Проверяем результаты установки
    local installed_count=${#installed_modules[@]}
    local failed_count=${#failed_modules[@]}

    log_info "Module installation results: $installed_count successful, $failed_count failed"

    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed module installations: ${failed_modules[*]}"
        return 1
    fi

    if [[ $installed_count -eq 0 ]]; then
        log_error "No modules were successfully installed"
        return 1
    fi

    log_success "All modules installed successfully: ${installed_modules[*]}"
    return 0
}

# Установка одного модуля
install_single_module() {
    local module_temp_dir="$1"
    local target_module_dir="$2"
    local module_name="$3"

    # Удаляем существующую установку если есть
    if [[ -e "$target_module_dir" ]]; then
        log_debug "Removing existing installation: $target_module_dir"
        if ! rm -rf "$target_module_dir" 2>/dev/null; then
            log_error "Failed to remove existing installation: $target_module_dir"
            return 1
        fi
    fi

    # Создаем целевую директорию модуля
    log_debug "Creating target directory: $target_module_dir"
    if ! mkdir -p "$target_module_dir" 2>/dev/null; then
        log_error "Failed to create target directory: $target_module_dir"
        return 1
    fi

    # Копируем содержимое модуля
    log_debug "Copying module files from: $module_temp_dir"

    # Копируем bin директорию
    if [[ -d "$module_temp_dir/bin" ]]; then
        if ! cp -r "$module_temp_dir/bin" "$target_module_dir/" 2>/dev/null; then
            log_error "Failed to copy bin directory for module: $module_name"
            return 1
        fi
        log_debug "Copied bin directory for module: $module_name"
    fi

    # Копируем lib директорию
    if [[ -d "$module_temp_dir/lib" ]]; then
        if ! cp -r "$module_temp_dir/lib" "$target_module_dir/" 2>/dev/null; then
            log_error "Failed to copy lib directory for module: $module_name"
            return 1
        fi
        log_debug "Copied lib directory for module: $module_name"
    fi

    # Копируем дополнительные файлы (README, .version, etc.)
    for extra_file in "$module_temp_dir"/*; do
        if [[ -f "$extra_file" ]]; then
            local file_name=$(basename "$extra_file")
            # Пропускаем служебные файлы
            if [[ "$file_name" != .module-* ]]; then
                if ! cp "$extra_file" "$target_module_dir/" 2>/dev/null; then
                    log_warning "Failed to copy extra file: $file_name"
                else
                    log_debug "Copied extra file: $file_name"
                fi
            fi
        fi
    done

    # Проверяем что установка прошла корректно
    if ! validate_installed_module "$target_module_dir" "$module_name"; then
        log_error "Module validation failed after installation: $module_name"
        return 1
    fi

    log_debug "Module installation completed: $module_name"
    return 0
}

# Валидация установленного модуля
validate_installed_module() {
    local target_module_dir="$1"
    local module_name="$2"

    # Проверяем основную структуру
    if [[ ! -d "$target_module_dir/bin" ]]; then
        log_error "Missing bin directory in installed module: $module_name"
        return 1
    fi

    if [[ ! -d "$target_module_dir/lib" ]]; then
        log_error "Missing lib directory in installed module: $module_name"
        return 1
    fi

    # Проверяем главный исполняемый файл
    local main_script="$target_module_dir/bin/$module_name.sh"
    if [[ ! -f "$main_script" ]]; then
        log_error "Missing main script in installed module: $module_name.sh"
        return 1
    fi

    if [[ ! -x "$main_script" ]]; then
        log_error "Main script not executable in installed module: $module_name.sh"
        return 1
    fi

    # Проверяем что файлы читаемы
    if [[ ! -r "$main_script" ]]; then
        log_error "Main script not readable in installed module: $module_name.sh"
        return 1
    fi

    # Проверяем наличие библиотечных файлов
    local lib_files_count=$(find "$target_module_dir/lib" -name "*.sh" -type f 2>/dev/null | wc -l)
    if [[ $lib_files_count -eq 0 ]]; then
        log_warning "No library files found in installed module: $module_name"
    else
        log_debug "Found $lib_files_count library files in installed module: $module_name"
    fi

    log_debug "Installed module validation passed: $module_name"
    return 0
}

main "$@"