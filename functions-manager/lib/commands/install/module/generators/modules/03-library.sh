#!/bin/bash
# ============================================================================
# Generator: Library Files
# Copies and processes module library files
# ============================================================================

main() {
    local module_path="$1"
    local module_temp_dir="$2"
    local module_name=$(basename "$module_path")

    log_debug "Processing library files for module: $module_name"

    # Читаем метаданные модуля
    local metadata_file="$module_temp_dir/.module-metadata"

    if [[ ! -f "$metadata_file" ]]; then
        log_error "Module metadata file not found: $metadata_file"
        return 1
    fi

    source "$metadata_file"

    # Получаем список файлов модуля
    local module_file="$module_path/module.yml"
    local files

    if ! files=$(yaml_get_module_files "$module_file"); then
        log_warning "No files section found for module: $module_name"
        return 0
    fi

    __copy_files_to_destination "$files" "$module_path" "$module_temp_dir"

    if ! files=$(yaml_get_module_binaries "$module_file"); then
        log_warning "No bin files section found for module: $module_name"
    fi

    __copy_files_to_destination "$files" "$module_path" "$module_temp_dir"

    # Создаем дополнительные файлы если нужно
    if ! create_additional_files "$module_temp_dir" "$module_name"; then
        log_error "Failed to create additional files for module: $module_name"
        return 1
    fi

    log_success "Library processing completed for module: $module_name"
    return 0
}

__copy_files_to_destination() {
    local files=$1
    local module_path="$2"
    local module_temp_dir="$3"
    local module_name=$(basename "$module_path")

    if [[ -z "$files" ]]; then
        log_warning "Empty files section for module: $module_name"
        return 0
    fi

    local copied_files=()
    local failed_files=()

    # Копируем каждый файл
    while IFS= read -r file_name; do
        if [[ -n "$file_name" ]]; then
            log_debug "Processing file: $file_name"

            local source_file="$module_path/$file_name"
            local dest_file="$module_temp_dir/lib/$file_name"

            # Проверяем что исходный файл/директория существует
            if [[ ! -e "$source_file" ]]; then
                log_error "Source file/directory not found: $source_file"
                failed_files+=("$file_name")
                continue
            fi

            # Проверяем что файл/директория читаемая
            if [[ ! -r "$source_file" ]]; then
                log_error "Source file/directory not readable: $source_file"
                failed_files+=("$file_name")
                continue
            fi

            # Копируем файл или директорию
            if cp -r "$source_file" "$dest_file" 2>/dev/null; then
                log_debug "Copied file/directory: $file_name"

                # Устанавливаем правильные права доступа
                if [[ -d "$dest_file" ]]; then
                    log_debug "Setup rules for directory: $file_name"
                    # Для директорий
                    chmod 755 "$dest_file" 2>/dev/null || {
                        log_warning "Failed to set permissions for directory: $file_name"
                    }

                    # Рекурсивно устанавливаем права для содержимого
                    find "$dest_file" -type f -exec chmod 755 {} + 2>/dev/null || {
                        log_warning "Failed to set file permissions in directory: $file_name"
                    }

                    find "$dest_file" -type d -exec chmod 755 {} + 2>/dev/null || {
                        log_warning "Failed to set directory permissions in directory: $file_name"
                    }
                else
                    log_debug "Setup rules for file: $file_name"

                    chmod 644 "$dest_file" 2>/dev/null || {
                        log_warning "Failed to set permissions for: $file_name"
                    }

                    # Дополнительная обработка в зависимости от типа файла
                    if ! process_file_by_type "$dest_file" "$file_name" "$module_name"; then
                        log_warning "File processing failed for: $file_name"
                    fi

                fi

                copied_files+=("$file_name")
            else
                log_error "Failed to copy file: $source_file -> $dest_file"
                failed_files+=("$file_name")
            fi
        fi
    done <<< "$files"

    # Проверяем результаты
    local copied_count=${#copied_files[@]}
    local failed_count=${#failed_files[@]}

    if [[ $failed_count -gt 0 ]]; then
        log_error "Failed to copy files for module '$module_name': ${failed_files[*]}"
        return 1
    fi

    if [[ $copied_count -eq 0 ]]; then
        log_warning "No files were copied for module: $module_name"
    else
        log_debug "Successfully copied $copied_count files for module: $module_name"
    fi

}

# Обработка файла в зависимости от его типа
process_file_by_type() {
    local file_path="$1"
    local file_name="$2"
    local module_name="$3"

    case "$file_name" in
        *-lib.sh)
            # Библиотечный файл - проверяем синтаксис
            if ! bash -n "$file_path"; then
                log_error "Library file has syntax errors: $file_name"
                return 1
            fi
            log_debug "Library file syntax validated: $file_name"
            ;;
        *.sh)
            # Обычный shell скрипт - проверяем синтаксис
            if ! bash -n "$file_path"; then
                log_error "Script file has syntax errors: $file_name"
                return 1
            fi
            log_debug "Script file syntax validated: $file_name"
            ;;
        *.yml|*.yaml)
            # YAML файл - проверяем валидность
            if is_command_exists yq; then
                if ! yaml_validate "$file_path"; then
                    log_error "YAML file is invalid: $file_name"
                    return 1
                fi
                log_debug "YAML file validated: $file_name"
            fi
            ;;
        *.json)
            # JSON файл - проверяем валидность если есть jq
            if is_command_exists jq; then
                if ! jq empty "$file_path" 2>/dev/null; then
                    log_error "JSON file is invalid: $file_name"
                    return 1
                fi
                log_debug "JSON file validated: $file_name"
            fi
            ;;
        *)
            log_debug "File copied without specific processing: $file_name"
            ;;
    esac

    return 0
}

# Создание дополнительных файлов
create_additional_files() {
    local module_temp_dir="$1"
    local module_name="$2"

    # Создаем README файл для модуля (если его нет)
    local readme_file="$module_temp_dir/README.md"

    if [[ ! -f "$module_temp_dir/lib/README.md" ]]; then
        cat > "$readme_file" << EOF
# Module: $module_name

This is an auto-generated module directory.

## Structure

- \`bin/$module_name.sh\` - Main executable script
- \`lib/\` - Library files and dependencies

## Usage

Run \`$module_name help\` to see available commands.

## Installation

This module was installed via dev-tools.
EOF

        log_debug "Created README for module: $module_name"
    fi

    # Создаем файл версии
    local version_file="$module_temp_dir/.version"
    echo "$MODULE_VERSION" > "$version_file"

    return 0
}

main "$@"