#!/bin/bash
# ============================================================================
# Validator: Metadata Section
# Validates metadata fields and their values
# ============================================================================

main() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    log_debug "Validating metadata for module: $module_name"

    # Получаем метаданные модуля
    local metadata_info
    if ! metadata_info=$(yaml_get_module_metadata "$module_file"); then
        log_error "Failed to extract metadata from: $module_file"
        return 1
    fi

    # Парсим метаданные
    local name version description author
    while IFS='=' read -r key value; do
        case "$key" in
            "name") name="$value" ;;
            "version") version="$value" ;;
            "description") description="$value" ;;
            "author") author="$value" ;;
        esac
    done <<< "$metadata_info"

    # Проверяем обязательное поле name
    if [[ -z "$name" || "$name" == "unknown" ]]; then
        log_error "Missing or invalid metadata.name in: $module_file"
        return 1
    fi

    # Проверяем корректность имени модуля (только буквы, цифры, дефисы)
    if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        log_error "Invalid module name format: '$name' (only letters, numbers, underscores and hyphens allowed)"
        return 1
    fi

    # Проверяем что имя модуля соответствует имени директории
    if [[ "$name" != "$module_name" ]]; then
        log_warning "Module name '$name' differs from directory name '$module_name'"
    fi

    # Проверяем версию (желательно)
    if [[ -z "$version" || "$version" == "unknown" ]]; then
        log_warning "Missing or invalid metadata.version in: $module_file"
    else
        # Проверяем формат версии (семантическое версионирование)
        if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][a-zA-Z0-9.-]*)?$ ]]; then
            log_warning "Version '$version' does not follow semantic versioning format"
        fi
    fi

    # Проверяем описание (желательно)
    if [[ -z "$description" ]]; then
        log_warning "Missing metadata.description in: $module_file"
    fi

    log_debug "Metadata validation passed for module: $name"
    return 0
}

main "$@"