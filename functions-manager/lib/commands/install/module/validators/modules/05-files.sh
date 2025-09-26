#!/bin/bash
# ============================================================================
# Validator: Files Section
# Validates existence and accessibility of module files
# ============================================================================

main() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    log_debug "Validating files for module: $module_name"

    # Получаем список файлов модуля
    local files
    if ! files=$(yaml_get_module_files "$module_file"); then
        log_warning "No files section found for module: $module_name"
        return 0  # Не критично - модуль может не иметь дополнительных файлов
    fi

    if [[ -z "$files" ]]; then
        log_warning "Empty files section for module: $module_name"
        return 0
    fi

    local missing_files=()
    local unreadable_files=()
    local file_count=0

    # Проверяем каждый файл
    while IFS= read -r file_name; do
        if [[ -n "$file_name" ]]; then
            file_count=$((file_count + 1))
            local file_path="$module_path/$file_name"

            log_debug "Checking file: $file_name"

            # Проверяем существование файла
            if [[ ! -f "$file_path" ]]; then
                log_error "Missing file: $file_name (expected at: $file_path)"
                missing_files+=("$file_name")
                continue
            fi

            # Проверяем читаемость файла
            if [[ ! -r "$file_path" ]]; then
                log_error "File not readable: $file_name"
                unreadable_files+=("$file_name")
                continue
            fi

            # Проверяем что файл не пустой
            if [[ ! -s "$file_path" ]]; then
                log_warning "File is empty: $file_name"
            fi

            # Дополнительные проверки для shell скриптов
            if [[ "$file_name" == *.sh ]]; then
                validate_shell_script "$file_path" "$file_name"
            fi

            # Дополнительные проверки для lib файлов
            if [[ "$file_name" == *-lib.sh ]]; then
                validate_library_file "$file_path" "$file_name"
            fi

            log_debug "File OK: $file_name"
        fi
    done <<< "$files"

    # Проверяем результаты
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        log_error "Missing files in module '$module_name': ${missing_files[*]}"
        return 1
    fi

    if [[ ${#unreadable_files[@]} -gt 0 ]]; then
        log_error "Unreadable files in module '$module_name': ${unreadable_files[*]}"
        return 1
    fi

    if [[ $file_count -eq 0 ]]; then
        log_warning "No files specified for module: $module_name"
    else
        log_debug "All $file_count files validated for module: $module_name"
    fi

    log_debug "Files validation passed for module: $module_name"
    return 0
}

# Валидация shell скрипта
validate_shell_script() {
    local file_path="$1"
    local file_name="$2"

    # Проверяем shebang
    local first_line=$(head -n1 "$file_path" 2>/dev/null)
    if [[ ! "$first_line" =~ ^#!.*/bash ]]; then
        log_warning "Shell script '$file_name' missing proper bash shebang"
    fi

    # Базовая проверка синтаксиса bash (если исполняемый)
    if [[ -x "$file_path" ]]; then
        if ! bash -n "$file_path" 2>/dev/null; then
            log_error "Shell script '$file_name' has syntax errors"
            return 1
        fi
    fi

    return 0
}

# Валидация библиотечного файла
validate_library_file() {
    local file_path="$1"
    local file_name="$2"

    # Проверяем что это библиотека функций
    if ! grep -q "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$file_path" 2>/dev/null; then
        log_warning "Library file '$file_name' does not seem to contain function definitions"
    fi

    # Проверяем синтаксис
    if ! bash -n "$file_path" 2>/dev/null; then
        log_error "Library file '$file_name' has syntax errors"
        return 1
    fi

    return 0
}

main "$@"