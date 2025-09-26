#!/bin/bash
# ============================================================================
# Validator: YAML Structure
# Validates basic YAML structure and parseability
# ============================================================================

main() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    log_debug "Validating YAML structure for module: $module_name"

    # Проверяем существование файла
    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    # Проверяем что файл не пустой
    if [[ ! -s "$module_file" ]]; then
        log_error "Module file is empty: $module_file"
        return 1
    fi

    # Проверяем доступность yq
    if ! yaml_check_availability; then
        log_error "Cannot validate YAML structure without yq"
        return 1
    fi

    # Проверяем валидность YAML
    if ! yaml_validate "$module_file"; then
        log_error "Invalid YAML structure in: $module_file"
        return 1
    fi

    # Проверяем базовую структуру документа
    local version=$(yaml_get "$module_file" ".version")
    if [[ -z "$version" ]]; then
        log_error "Missing required field 'version' in: $module_file"
        return 1
    fi

    # Проверяем наличие секции metadata
    local metadata_check=$(yaml_get "$module_file" ".metadata")
    if [[ -z "$metadata_check" || "$metadata_check" == "null" ]]; then
        log_error "Missing required section 'metadata' in: $module_file"
        return 1
    fi

    # Проверяем наличие секции specification
    local spec_check=$(yaml_get "$module_file" ".specification")
    if [[ -z "$spec_check" || "$spec_check" == "null" ]]; then
        log_error "Missing required section 'specification' in: $module_file"
        return 1
    fi

    # Проверяем наличие секции module в specification
    local module_check=$(yaml_get "$module_file" ".specification.module")
    if [[ -z "$module_check" || "$module_check" == "null" ]]; then
        log_error "Missing required section 'specification.module' in: $module_file"
        return 1
    fi

    log_debug "YAML structure validation passed for: $module_name"
    return 0
}

main "$@"