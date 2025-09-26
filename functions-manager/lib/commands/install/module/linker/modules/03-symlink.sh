#!/bin/bash
# ============================================================================
# Linker: Symlinks
# Creates symlinks in /usr/local/bin for installed modules
# ============================================================================

main() {
    local temp_dir="$1"
    local validated_modules="$2"
    local target_lib_dir="$3"
    local target_bin_dir="$4"

    log_debug "Creating symlinks for installed modules"

    local created_symlinks=()
    local failed_symlinks=()

    # Создаем симлинки для каждого модуля
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            local module_name=$(basename "$module_path")
            local function_name=$(yaml_get "$module_path/module.yml" ".metadata.name")

            log_debug "Creating symlink for module: $module_name"

            if create_module_symlink "$function_name" "$module_name" "$target_lib_dir" "$target_bin_dir"; then
                created_symlinks+=("$function_name")
                log_debug "Symlink created successfully: $function_name"
            else
                failed_symlinks+=("$function_name")
                log_error "Symlink creation failed: $function_name"
            fi
        fi
    done <<< "$validated_modules"

    # Проверяем результаты создания симлинков
    local created_count=${#created_symlinks[@]}
    local failed_count=${#failed_symlinks[@]}

    log_info "Symlink creation results: $created_count successful, $failed_count failed"

    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed symlink creations: ${failed_symlinks[*]}"
        return 1
    fi

    if [[ $created_count -eq 0 ]]; then
        log_error "No symlinks were created"
        return 1
    fi

    # Проверяем что все созданные симлинки работают
    if ! validate_created_symlinks "$target_bin_dir" "${created_symlinks[@]}"; then
        log_error "Symlink validation failed"
        return 1
    fi

    log_success "All symlinks created successfully: ${created_symlinks[*]}"
    return 0
}

# Создание симлинка для одного модуля
create_module_symlink() {
    local function_name="$1"
    local module_name="$2"
    local target_lib_dir="$3"
    local target_bin_dir="$4"

    local source_script="$target_lib_dir/$module_name/bin/$module_name.sh"
    local target_symlink="$target_bin_dir/$function_name"

    # Проверяем что исходный файл существует
    if [[ ! -f "$source_script" ]]; then
        log_error "Source script not found: $source_script"
        return 1
    fi

    # Проверяем что исходный файл исполняемый
    if [[ ! -x "$source_script" ]]; then
        log_error "Source script not executable: $source_script"
        return 1
    fi

    # Удаляем существующий симлинк если есть
    if [[ -L "$target_symlink" ]]; then
        log_debug "Removing existing symlink: $target_symlink"
        if ! rm -f "$target_symlink" 2>/dev/null; then
            log_error "Failed to remove existing symlink: $target_symlink"
            return 1
        fi
    elif [[ -e "$target_symlink" ]]; then
        log_error "Target path exists but is not a symlink: $target_symlink"
        return 1
    fi

    # Создаем новый симлинк
    log_debug "Creating symlink: $target_symlink -> $source_script"
    if ! ln -s "$source_script" "$target_symlink" 2>/dev/null; then
        log_error "Failed to create symlink: $target_symlink -> $source_script"
        return 1
    fi

    # Проверяем что симлинк создался корректно
    if [[ ! -L "$target_symlink" ]]; then
        log_error "Symlink was not created: $target_symlink"
        return 1
    fi

    # Проверяем что симлинк указывает на правильный файл
    local symlink_target=$(readlink "$target_symlink" 2>/dev/null)
    if [[ "$symlink_target" != "$source_script" ]]; then
        log_error "Symlink points to wrong target: $target_symlink -> $symlink_target (expected: $source_script)"
        return 1
    fi

    log_debug "Symlink created and validated: $module_name"
    return 0
}

# Валидация всех созданных симлинков
validate_created_symlinks() {
    local target_bin_dir="$1"
    shift
    local created_symlinks=("$@")

    log_debug "Validating created symlinks"

    local validation_errors=()

    for module_name in "${created_symlinks[@]}"; do
        local symlink_path="$target_bin_dir/$module_name"

        # Проверяем что симлинк существует
        if [[ ! -L "$symlink_path" ]]; then
            validation_errors+=("Symlink does not exist: $symlink_path")
            continue
        fi

        # Проверяем что целевой файл существует
        if [[ ! -f "$symlink_path" ]]; then
            validation_errors+=("Symlink target does not exist: $symlink_path")
            continue
        fi

        # Проверяем что симлинк исполняемый
        if [[ ! -x "$symlink_path" ]]; then
            validation_errors+=("Symlink not executable: $symlink_path")
            continue
        fi

        # Тестируем что симлинк вызывается без ошибок (проверяем help)
        if ! "$symlink_path" help >/dev/null 2>&1; then
            # Проверяем синтаксические ошибки
            local target_file=$(readlink "$symlink_path")
            if ! bash -n "$target_file" 2>/dev/null; then
                validation_errors+=("Symlink target has syntax errors: $symlink_path")
                continue
            fi
            log_debug "Symlink help command failed (might be normal): $module_name"
        fi

        log_debug "Symlink validated successfully: $module_name"
    done

    # Проверяем результаты валидации
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_error "Symlink validation errors:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    log_debug "All symlinks validated successfully"
    return 0
}

# Информационная функция - показывает созданные симлинки
show_installation_summary() {
    local created_symlinks=("$@")

    if [[ ${#created_symlinks[@]} -eq 0 ]]; then
        return 0
    fi

    log_info ""
    log_info "Installation Summary:"
    log_info "===================="
    log_info "Installed modules are now available as commands:"

    for module_name in "${created_symlinks[@]}"; do
        log_info "  $module_name - run '$module_name help' for usage"
    done

    log_info ""
    log_info "All commands are available in PATH via /usr/local/bin"
}

main "$@"

# Показываем итоговую информацию
if [[ $? -eq 0 ]]; then
    # Извлекаем имена модулей из validated_modules
    local module_names=()
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            module_names+=($(basename "$module_path"))
        fi
    done <<< "$2"

    show_installation_summary "${module_names[@]}"
fi