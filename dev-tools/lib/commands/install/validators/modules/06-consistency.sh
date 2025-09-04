#!/bin/bash
# ============================================================================
# Validator: Module Consistency
# Validates consistency between module.yml declarations and actual files
# ============================================================================

main() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    log_debug "Validating consistency for module: $module_name"

    # Проверяем соответствие объявленных команд и функций в файлах
    if ! validate_commands_functions_consistency "$module_path"; then
        return 1
    fi

    # Проверяем соответствие объявленных файлов и их содержимого
    if ! validate_files_content_consistency "$module_path"; then
        return 1
    fi

    log_debug "Consistency validation passed for module: $module_name"
    return 0
}

# Проверка соответствия команд и функций
validate_commands_functions_consistency() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    # Получаем объявленные команды
    local commands_section=$(yaml_get "$module_file" ".specification.module.commands")
    if [[ -z "$commands_section" || "$commands_section" == "null" ]]; then
        log_debug "No commands to validate for module: $module_name"
        return 0
    fi

    local declared_functions=()
    local command_index=0

    # Собираем все объявленные функции
    while true; do
        local command_function=$(yaml_get "$module_file" ".specification.module.commands[$command_index].function")

        if [[ -z "$command_function" || "$command_function" == "null" ]]; then
            break
        fi

        declared_functions+=("$command_function")
        command_index=$((command_index + 1))

        # Защита от бесконечного цикла
        if [[ $command_index -gt 100 ]]; then
            break
        fi
    done

    if [[ ${#declared_functions[@]} -eq 0 ]]; then
        log_debug "No functions declared in commands for module: $module_name"
        return 0
    fi

    # Получаем файлы модуля
    local files
    if ! files=$(yaml_get_module_files "$module_file"); then
        log_error "Cannot validate functions - no files declared for module: $module_name"
        return 1
    fi

    # Проверяем наличие объявленных функций в файлах
    local missing_functions=()

    for function_name in "${declared_functions[@]}"; do
        local function_found=false

        while IFS= read -r file_name; do
            if [[ -n "$file_name" ]]; then
                local file_path="$module_path/$file_name"

                if [[ -f "$file_path" && -r "$file_path" ]]; then
                    # Ищем определение функции в файле
                    if grep -q "^[[:space:]]*${function_name}[[:space:]]*(" "$file_path" 2>/dev/null; then
                        function_found=true
                        log_debug "Function '$function_name' found in file: $file_name"
                        break
                    fi
                fi
            fi
        done <<< "$files"

        if [[ "$function_found" == false ]]; then
            log_error "Function '$function_name' declared in commands but not found in module files"
            missing_functions+=("$function_name")
        fi
    done

    if [[ ${#missing_functions[@]} -gt 0 ]]; then
        log_error "Missing function implementations in module '$module_name': ${missing_functions[*]}"
        return 1
    fi

    log_debug "All declared functions found in module files for: $module_name"
    return 0
}

# Проверка соответствия файлов и их содержимого
validate_files_content_consistency() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    # Получаем файлы модуля
    local files
    if ! files=$(yaml_get_module_files "$module_file"); then
        log_debug "No files to validate for module: $module_name"
        return 0
    fi

    # Проверяем каждый файл на соответствие ожидаемому содержимому
    while IFS= read -r file_name; do
        if [[ -n "$file_name" ]]; then
            local file_path="$module_path/$file_name"

            if [[ -f "$file_path" && -r "$file_path" ]]; then
                # Проверки в зависимости от типа файла
                case "$file_name" in
                    *-lib.sh)
                        # Библиотечный файл должен содержать функции
                        if ! grep -q "^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(" "$file_path" 2>/dev/null; then
                            log_warning "Library file '$file_name' does not contain function definitions"
                        fi
                        ;;
                    *.sh)
                        # Исполняемый файл должен иметь shebang
                        local first_line=$(head -n1 "$file_path" 2>/dev/null)
                        if [[ ! "$first_line" =~ ^#! ]]; then
                            log_warning "Script file '$file_name' missing shebang"
                        fi
                        ;;
                    *.yml|*.yaml)
                        # YAML файлы должны быть валидными
                        if ! yaml_validate "$file_path" 2>/dev/null; then
                            log_error "Invalid YAML file: $file_name"
                            return 1
                        fi
                        ;;
                esac

                log_debug "File content consistency OK: $file_name"
            fi
        fi
    done <<< "$files"

    return 0
}

main "$@"