#!/bin/bash
# ============================================================================
# Linker: Validation
# Validates permissions, conflicts and prerequisites for installation
# ============================================================================

main() {
    local temp_dir="$1"
    local validated_modules="$2"
    local target_lib_dir="$3"
    local target_bin_dir="$4"

    log_debug "Validating installation prerequisites"

    # Проверяем права доступа к системным директориям
    if ! validate_system_permissions; then
        log_error "System permissions validation failed"
        return 1
    fi

    # Проверяем права доступа к системным директориям
    if ! validate_system_permissions "$target_lib_dir" "$target_bin_dir"; then
        log_error "System permissions validation failed"
        return 1
    fi

    # Проверяем конфликты имен модулей
    if ! validate_module_name_conflicts "$validated_modules" "$target_lib_dir" "$target_bin_dir"; then
        log_error "Module name conflicts detected"
        return 1
    fi


    log_success "Installation validation completed"
    return 0
}

# Проверка прав доступа к системным директориям
validate_system_permissions() {
    log_debug "Checking system directory permissions"

    local target_lib_dir="/usr/local/lib"
    local target_bin_dir="/usr/local/bin"

    # Проверяем /usr/local/lib
    if [[ ! -d "$target_lib_dir" ]]; then
        log_info "Creating target library directory: $target_lib_dir"
        if ! mkdir -p "$target_lib_dir" 2>/dev/null; then
            log_error "Cannot create directory: $target_lib_dir"
            return 1
        fi
    fi

    if [[ ! -w "$target_lib_dir" ]]; then
        # Проверяем возможность записи с sudo
        if ! test -w "$target_lib_dir" 2>/dev/null; then
            log_error "No write permission to: $target_lib_dir"
            return 1
        fi
    fi

    # Проверяем /usr/local/bin
    if [[ ! -d "$target_bin_dir" ]]; then
        log_info "Creating target binary directory: $target_bin_dir"
        if ! mkdir -p "$target_bin_dir" 2>/dev/null; then
            log_error "Cannot create directory: $target_bin_dir"
            return 1
        fi
    fi

    if [[ ! -w "$target_bin_dir" ]]; then
        # Проверяем возможность записи с sudo
        if ! test -w "$target_bin_dir" 2>/dev/null; then
            log_error "No write permission to: $target_bin_dir"
            return 1
        fi
    fi

    log_debug "System permissions validated"
    return 0
}

# Проверка конфликтов имен модулей
validate_module_name_conflicts() {
    local validated_modules="$1"

    log_debug "Checking for module name conflicts"

    local target_lib_dir="/usr/local/lib"
    local target_bin_dir="/usr/local/bin"
    local conflicts=()

    # Проверяем каждый модуль на конфликты
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            local module_name=$(basename "$module_path")

            # Проверяем конфликт в /usr/local/lib
            if [[ -e "$target_lib_dir/$module_name" ]]; then
                log_warning "Target directory already exists: $target_lib_dir/$module_name"
                conflicts+=("lib:$module_name")
            fi

            # Проверяем конфликт в /usr/local/bin
            if [[ -e "$target_bin_dir/$module_name" ]]; then
                log_warning "Target binary already exists: $target_bin_dir/$module_name"
                conflicts+=("bin:$module_name")
            fi
        fi
    done <<< "$validated_modules"

    # Если есть конфликты, показываем их и спрашиваем пользователя
    if [[ ${#conflicts[@]} -gt 0 ]]; then
        log_warning "Found existing installations:"
        for conflict in "${conflicts[@]}"; do
            log_warning "  - $conflict"
        done

        # В интерактивном режиме спрашиваем пользователя
        if [[ "${INTERACTIVE:-false}" == "true" ]]; then
            echo -n "Overwrite existing installations? [y/N]: "
            read -r response
            if [[ "$response" != [yY] && "$response" != [yY][eE][sS] ]]; then
                log_info "Installation cancelled by user"
                return 1
            fi
            log_info "User confirmed overwrite of existing installations"
        else
            log_info "Existing installations will be overwritten"
        fi
    fi

    log_debug "Module name conflicts validated"
    return 0
}

# Проверка структуры сгенерированных модулей
validate_generated_modules() {
    local temp_dir="$1"
    local validated_modules="$2"

    log_debug "Validating generated module structures"

    local validation_errors=()

    # Проверяем каждый сгенерированный модуль
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            local module_name=$(basename "$module_path")
            local module_temp_dir="$temp_dir/$module_name"

            # Проверяем основную структуру
            if [[ ! -d "$module_temp_dir" ]]; then
                validation_errors+=("Missing temp directory: $module_name")
                continue
            fi

            if [[ ! -d "$module_temp_dir/bin" ]]; then
                validation_errors+=("Missing bin directory: $module_name")
                continue
            fi

            if [[ ! -d "$module_temp_dir/lib" ]]; then
                validation_errors+=("Missing lib directory: $module_name")
                continue
            fi

            # Проверяем главный исполняемый файл
            local main_script="$module_temp_dir/bin/$module_name.sh"
            if [[ ! -f "$main_script" ]]; then
                validation_errors+=("Missing main script: $module_name.sh")
                continue
            fi

            if [[ ! -x "$main_script" ]]; then
                validation_errors+=("Main script not executable: $module_name.sh")
                continue
            fi

            # Проверяем синтаксис главного скрипта
            if ! bash -n "$main_script" 2>/dev/null; then
                validation_errors+=("Syntax error in main script: $module_name.sh")
                continue
            fi

            log_debug "Generated module structure validated: $module_name"
        fi
    done <<< "$validated_modules"

    # Проверяем результаты валидации
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_error "Generated module validation errors:"
        for error in "${validation_errors[@]}"; do
            log_error "  - $error"
        done
        return 1
    fi

    log_debug "All generated modules validated successfully"
    return 0
}

main "$@"