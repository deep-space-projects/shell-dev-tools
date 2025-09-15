#!/bin/bash
# ============================================================================
# Validator: Commands Section
# Validates module commands and their structure (supports space-separated commands)
# ============================================================================

main() {
    local module_path="$1"
    local module_file="$module_path/module.yml"
    local module_name=$(basename "$module_path")

    log_debug "Validating commands for module: $module_name"

    # Проверяем наличие секции commands
    local commands_section=$(yaml_get "$module_file" ".specification.module.commands")

    if [[ -z "$commands_section" || "$commands_section" == "null" ]]; then
        log_warning "No commands section found for module: $module_name"
        return 0  # Не критично - модуль может не экспортировать команды
    fi

    # Получаем список команд
    local commands
    if ! commands=$(yaml_get_module_commands "$module_file"); then
        log_error "Failed to parse commands section for module: $module_name"
        return 1
    fi

    if [[ -z "$commands" ]]; then
        log_warning "Empty commands section for module: $module_name"
        return 0
    fi

    # Счетчик команд
    local command_count=0
    local command_names=()

    # Проверяем каждую команду
    local command_index=0
    while true; do
        local command_name=$(yaml_get "$module_file" ".specification.module.commands[$command_index].name")
        local command_function=$(yaml_get "$module_file" ".specification.module.commands[$command_index].function")
        local command_description=$(yaml_get "$module_file" ".specification.module.commands[$command_index].description")
        local command_usage=$(yaml_get "$module_file" ".specification.module.commands[$command_index].usage")

        # Если команды закончились
        if [[ -z "$command_name" || "$command_name" == "null" ]]; then
            break
        fi

        command_count=$((command_count + 1))

        # Проверяем обязательные поля команды
        if [[ -z "$command_function" || "$command_function" == "null" ]]; then
            log_error "Missing 'function' field for command '$command_name' in module: $module_name"
            return 1
        fi

        # Проверяем корректность имени команды (теперь разрешаем пробелы)
        if [[ ! "$command_name" =~ ^([a-zA-Z0-9]|--?)[a-zA-Z0-9\ _=-]*[a-zA-Z0-9]$|^[a-zA-Z0-9]$ ]]; then
            log_error "Invalid command name format: '$command_name' (only letters, numbers, spaces, underscores and hyphens allowed)"
            return 1
        fi

        # Проверяем что команда не начинается и не заканчивается пробелом
        if [[ "$command_name" =~ ^[[:space:]]|[[:space:]]$ ]]; then
            log_error "Command name cannot start or end with whitespace: '$command_name'"
            return 1
        fi

        # Проверяем что нет двойных пробелов
        if [[ "$command_name" =~ [[:space:]]{2,} ]]; then
            log_error "Command name cannot contain multiple consecutive spaces: '$command_name'"
            return 1
        fi

        # Проверяем корректность имени функции
        if [[ ! "$command_function" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            log_error "Invalid function name format: '$command_function' (must be valid bash function name)"
            return 1
        fi

        # Проверяем уникальность имени команды
        for existing_name in "${command_names[@]}"; do
            if [[ "$existing_name" == "$command_name" ]]; then
                log_error "Duplicate command name: '$command_name' in module: $module_name"
                return 1
            fi
        done
        command_names+=("$command_name")

        # Проверяем наличие описания (рекомендуется)
        if [[ -z "$command_description" || "$command_description" == "null" ]]; then
            log_warning "Missing 'description' field for command '$command_name' in module: $module_name"
        fi

        # Проверяем наличие usage (рекомендуется)
        if [[ -z "$command_usage" || "$command_usage" == "null" ]]; then
            log_warning "Missing 'usage' field for command '$command_name' in module: $module_name"
        fi

        # Дополнительные проверки для команд с пробелами
        local word_count=$(echo "$command_name" | wc -w)
        if [[ $word_count -gt 5 ]]; then
            log_warning "Command name has many words ($word_count): '$command_name' - consider shorter names"
        fi

        log_debug "Command '$command_name' -> function '$command_function' validated ($word_count words)"

        command_index=$((command_index + 1))

        # Защита от бесконечного цикла
        if [[ $command_index -gt 100 ]]; then
            log_error "Too many commands in module: $module_name (limit: 100)"
            return 1
        fi
    done

    # Проверяем на потенциальные конфликты команд (команды которые могут пересекаться)
    if ! validate_command_conflicts "${command_names[@]}"; then
        log_error "Command conflicts detected in module: $module_name"
        return 1
    fi

    if [[ $command_count -eq 0 ]]; then
        log_warning "No valid commands found for module: $module_name"
    else
        log_debug "Found $command_count valid commands for module: $module_name"
    fi

    log_debug "Commands validation passed for module: $module_name"
    return 0
}

# Проверка конфликтов между командами
validate_command_conflicts() {
    local command_names=("$@")

    # Проверяем что короткие команды не являются префиксами длинных
    for ((i=0; i<${#command_names[@]}; i++)); do
        for ((j=i+1; j<${#command_names[@]}; j++)); do
            local cmd1="${command_names[i]}"
            local cmd2="${command_names[j]}"

            # Проверяем что одна команда не является началом другой
            if [[ "$cmd2" == "$cmd1 "* ]]; then
                log_error "Command conflict: '$cmd1' is a prefix of '$cmd2'"
                return 1
            elif [[ "$cmd1" == "$cmd2 "* ]]; then
                log_error "Command conflict: '$cmd2' is a prefix of '$cmd1'"
                return 1
            fi
        done
    done

    return 0
}

main "$@"