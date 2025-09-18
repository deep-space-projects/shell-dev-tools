#!/bin/bash
# ============================================================================
# Module Validation
# Coordinates module validation through modular validators
# ============================================================================

# Главная функция валидации модулей
validators_validate() {
    local modules_list="$1"

    log_debug "Starting module validation"

    # Определяем путь к validators модулям
    local validators_dir="${LIB_DIR}/commands/install/module/validators"
    local modules_dir="${validators_dir}/modules"

    if [[ ! -d "$modules_dir" ]]; then
        return $(handle_operation_error_quite "validators_validate" "Validators modules directory not found: $modules_dir" 1)
    fi

    local validated_modules=()
    local failed_modules=()
    local total_modules=0

    # Обрабатываем каждый модуль из списка
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            total_modules=$((total_modules + 1))
            local module_name=$(basename "$module_path")

            log_debug "Validating module: $module_name"

            if validate_single_module "$module_path"; then
                validated_modules+=("$module_path")
                log_debug "Module validation passed: $module_name"
            else
                failed_modules+=("$module_name")
                log_warning "Module validation failed: $module_name"
            fi
        fi
    done <<< "$modules_list"

    # Оценка результатов
    local validated_count=${#validated_modules[@]}
    local failed_count=${#failed_modules[@]}

    log_info "Module validation completed: $validated_count/$total_modules passed"

    if [[ $failed_count -gt 0 ]]; then
        handle_operation_error_quite "module_validation" "Failed module validations: ${failed_modules[*]}" 1
    fi

    # Проверяем что есть хотя бы один валидный модуль
    if [[ $validated_count -eq 0 ]]; then
        return $(handle_operation_error_quite "module_validation" "No modules passed validation" 1)
    fi

    log_success "Module validation completed successfully"

    # Возвращаем только валидные модули
    printf '%s\n' "${validated_modules[@]}"
    return 0
}

# Валидация одного модуля
validate_single_module() {
    local module_path="$1"
    local module_name=$(basename "$module_path")

    # Получаем список валидаторов в лексикографическом порядке
    local validators_dir="${LIB_DIR}/commands/install/module/validators"
    local modules_dir="${validators_dir}/modules"

    local validator_modules=()
    while IFS= read -r validator_file; do
        if [[ -f "$validator_file" && "$validator_file" == *.sh ]]; then
            validator_modules+=("$validator_file")
        fi
    done <<< "$(find "$modules_dir" -name "*.sh" -type f 2>/dev/null | sort)"

    if [[ ${#validator_modules[@]} -eq 0 ]]; then
        log_warning "No validator modules found"
        return 0
    fi

    # Применяем каждый валидатор к модулю
    local failed_validators=()

    for validator_file in "${validator_modules[@]}"; do
        local validator_name=$(basename "$validator_file" .sh)

        log_debug "Running validator '$validator_name' on module '$module_name'"

        # Каждый валидатор получает путь к модулю как параметр
        if source "$validator_file" "$module_path"; then
            log_debug "Validator '$validator_name' passed for module '$module_name'"
        else
            log_debug "Validator '$validator_name' failed for module '$module_name'"
            failed_validators+=("$validator_name")
        fi
    done

    # Проверяем результат валидации
    if [[ ${#failed_validators[@]} -gt 0 ]]; then
        log_warning "Module '$module_name' failed validators: ${failed_validators[*]}"
        return 1
    fi

    log_debug "Module '$module_name' passed all validators"
    return 0
}