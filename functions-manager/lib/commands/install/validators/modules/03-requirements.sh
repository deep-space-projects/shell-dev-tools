#!/bin/bash
# ============================================================================
# Validator: Requirements Section
# Validates module requirements and checks their availability
# ============================================================================

main() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    log_debug "Validating requirements for module: $module_name"

    # Проверяем все требования модуля
    if ! requirements_check_all "$module_file"; then
        log_error "Requirements validation failed for module: $module_name"
        return 1
    fi

    # Дополнительно проверяем структуру requirements секции (если есть)
    local requirements_check=$(yaml_get "$module_file" ".specification.module.requirements")

    if [[ -n "$requirements_check" && "$requirements_check" != "null" ]]; then
        # Проверяем структуру environment requirements
        local env_section=$(yaml_get "$module_file" ".specification.module.requirements.environment")
        if [[ -n "$env_section" && "$env_section" != "null" ]]; then
            # Проверяем что это массив
            local env_vars
            if ! env_vars=$(yaml_get_module_env_requirements "$module_file"); then
                log_warning "Invalid environment requirements structure in: $module_file"
            else
                local env_count=$(echo "$env_vars" | wc -l)
                log_debug "Found $env_count environment requirements"
            fi
        fi

        # Проверяем структуру packages requirements
        local packages_section=$(yaml_get "$module_file" ".specification.module.requirements.packages")
        if [[ -n "$packages_section" && "$packages_section" != "null" ]]; then
            # Проверяем наличие list секции
            local packages_list=$(yaml_get "$module_file" ".specification.module.requirements.packages.list")
            if [[ -z "$packages_list" || "$packages_list" == "null" ]]; then
                log_warning "Empty packages.list in requirements for module: $module_name"
            fi

            # Проверяем overrides секцию (опциональная)
            local overrides=$(yaml_get "$module_file" ".specification.module.requirements.packages.overrides")
            if [[ -n "$overrides" && "$overrides" != "null" ]]; then
                log_debug "Found package overrides for different OS distributions"
            fi
        fi
    else
        log_debug "No requirements section found for module: $module_name"
    fi

    log_debug "Requirements validation passed for module: $module_name"
    return 0
}

main "$@"