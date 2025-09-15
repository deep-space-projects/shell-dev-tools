#!/bin/bash
# ============================================================================
# Generator: Prepare Module Structure
# Creates base directory structure and prepares environment
# ============================================================================

main() {
    local module_path="$1"
    local module_temp_dir="$2"
    local module_name=$(basename "$module_path")

    log_debug "Preparing structure for module: $module_name"

    # Создаем базовую структуру директорий
    if ! safe_mkdir "$module_temp_dir/bin" "" "755"; then
        log_error "Failed to create bin directory for module: $module_name"
        return 1
    fi

    if ! safe_mkdir "$module_temp_dir/lib" "" "755"; then
        log_error "Failed to create lib directory for module: $module_name"
        return 1
    fi

    log_debug "Created directory structure for module: $module_name"

    # Создаем метаданные модуля для использования другими генераторами
    local metadata_file="$module_temp_dir/.module-metadata"
    local module_file="$module_path/module.yml"

    # Извлекаем базовую информацию о модуле
    local name version description
    if metadata_info=$(yaml_get_module_metadata "$module_file"); then
        while IFS='=' read -r key value; do
            case "$key" in
                "name") name="$value" ;;
                "version") version="$value" ;;
                "description") description="$value" ;;
            esac
        done <<< "$metadata_info"
    else
        log_error "Failed to extract metadata for module: $module_name"
        return 1
    fi

    local route_unknown=$(yaml_get_module_unknown_route "$module_file")

    # Записываем метаданные во временный файл
    cat > "$metadata_file" << EOF
MODULE_NAME=$(printf '%q' "$name")
MODULE_VERSION=$(printf '%q' "${version:-unknown}")
MODULE_DESCRIPTION=$(printf '%q' "${description:-}")
MODULE_SOURCE_PATH=$(printf '%q' "$module_path")
MODULE_TEMP_PATH=$(printf '%q' "$module_temp_dir")
GENERATION_TIMESTAMP=$(printf '%q' "$(date '+%Y-%m-%d %H:%M:%S')")
ROUTE_UNKNOWN=$(printf '%q' "$route_unknown")
EOF


    if [[ ! -f "$metadata_file" ]]; then
        log_error "Failed to create metadata file for module: $module_name"
        return 1
    fi

    log_debug "Created metadata file for module: $module_name"

    # Проверяем доступность исходных файлов модуля
    local files
    if files=$(yaml_get_module_files "$module_file"); then
        local missing_files=()

        while IFS= read -r file_name; do
            if [[ -n "$file_name" ]]; then
                local source_file="$module_path/$file_name"

                if [[ ! -f "$source_file" ]]; then
                    missing_files+=("$file_name")
                elif [[ ! -r "$source_file" ]]; then
                    log_error "Source file not readable: $file_name"
                    return 1
                fi
            fi
        done <<< "$files"

        if [[ ${#missing_files[@]} -gt 0 ]]; then
            log_error "Missing source files for module '$module_name': ${missing_files[*]}"
            return 1
        fi

        log_debug "All source files verified for module: $module_name"
    else
        log_warning "No files section found for module: $module_name"
    fi

    # Создаем временный файл со списком команд для использования другими генераторами
    local commands_file="$module_temp_dir/.module-commands"

    # Извлекаем команды модуля
    local command_index=0
    > "$commands_file"  # Очищаем файл

    while true; do
        local command_name=$(yaml_get "$module_file" ".specification.module.commands[$command_index].name")
        local command_function=$(yaml_get "$module_file" ".specification.module.commands[$command_index].function")
        local command_description=$(yaml_get "$module_file" ".specification.module.commands[$command_index].description")
        local command_usage=$(yaml_get "$module_file" ".specification.module.commands[$command_index].usage")

        if [[ -z "$command_name" || "$command_name" == "null" ]]; then
            break
        fi

        # Записываем информацию о команде (экранируем все значения)
        echo "COMMAND_${command_index}_NAME=$(printf '%q' "$command_name")" >> "$commands_file"
        echo "COMMAND_${command_index}_FUNCTION=$(printf '%q' "$command_function")" >> "$commands_file"
        echo "COMMAND_${command_index}_DESCRIPTION=$(printf '%q' "${command_description:-}")" >> "$commands_file"
        echo "COMMAND_${command_index}_USAGE=$(printf '%q' "${command_usage:-}")" >> "$commands_file"
        echo "# ---" >> "$commands_file"


        command_index=$((command_index + 1))

        # Защита от бесконечного цикла
        if [[ $command_index -gt 100 ]]; then
            break
        fi
    done

    echo "COMMANDS_COUNT=$command_index" >> "$commands_file"

    if [[ $command_index -gt 0 ]]; then
        log_debug "Extracted $command_index commands for module: $module_name"
    else
        log_debug "No commands found for module: $module_name"
    fi

    log_success "Module preparation completed: $module_name"
    return 0
}

main "$@"