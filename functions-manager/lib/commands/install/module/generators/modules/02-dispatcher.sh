#!/bin/bash
# ============================================================================
# Generator: Dispatcher Script
# Generates main executable script with command routing (table-based approach)
# ============================================================================

main() {
    local module_path="$1"
    local module_temp_dir="$2"
    local module_name=$(basename "$module_path")

    log_debug "Generating dispatcher for module: $module_name"

    # Читаем метаданные модуля
    local metadata_file="$module_temp_dir/.module-metadata"
    local commands_file="$module_temp_dir/.module-commands"

    if [[ ! -f "$metadata_file" ]]; then
        log_error "Module metadata file not found: $metadata_file"
        return 1
    fi

    if [[ ! -f "$commands_file" ]]; then
        log_error "Module commands file not found: $commands_file"
        return 1
    fi

    # Загружаем метаданные
    source "$metadata_file"
    source "$commands_file"

    # Устанавливаем значения по умолчанию для переменных
    MODULE_NAME="${MODULE_NAME:-$module_name}"
    MODULE_VERSION="${MODULE_VERSION:-unknown}"
    MODULE_DESCRIPTION="${MODULE_DESCRIPTION:-No description available}"
    COMMANDS_COUNT="${COMMANDS_COUNT:-0}"

    # Создаем главный исполняемый файл
    local dispatcher_file="$module_temp_dir/bin/$module_name.sh"

    log_debug "Creating dispatcher script: $dispatcher_file"

    # Генерируем заголовок
    generate_dispatcher_header "$dispatcher_file" "$module_name"

    # Загружаем библиотеки
    generate_library_loading "$dispatcher_file" "$module_path"

    # Генерируем таблицу команд
    generate_commands_table "$dispatcher_file"

    # Генерируем функции
    generate_helper_functions "$dispatcher_file" "$module_name"

    # Генерируем main функцию
    generate_main_function "$dispatcher_file" "$module_name" "${ROUTE_UNKNOWN:-false}"

    # Добавляем точку входа
    cat >> "$dispatcher_file" << EOF

# Точка входа
main "\$@"
EOF

    # Делаем файл исполняемым и проверяем синтаксис
    if ! chmod 755 "$dispatcher_file"; then
        log_error "Failed to make dispatcher executable: $dispatcher_file"
        return 1
    fi

    if ! bash -n "$dispatcher_file" 2>/dev/null; then
        log_error "Generated dispatcher has syntax errors: $dispatcher_file"
        return 1
    fi

    log_success "Dispatcher generated successfully for module: $module_name ($COMMANDS_COUNT commands)"
    return 0
}

# Генерация заголовка
generate_dispatcher_header() {
    local dispatcher_file="$1"
    local module_name="$2"

    # Генерируем dispatcher
    cat > "$dispatcher_file" << 'EOF'
#!/bin/bash
# ============================================================================
# AUTO-GENERATED MODULE DISPATCHER
EOF

    # Добавляем метаинформацию
    cat >> "$dispatcher_file" << EOF
# Module: $MODULE_NAME
# Version: $MODULE_VERSION
# Description: $MODULE_DESCRIPTION
# Generated: $GENERATION_TIMESTAMP
# ============================================================================

set -euo pipefail

get_script_path() {
    local source="\${BASH_SOURCE[0]}"
    local dir=""

    # Разрешаем симлинки
    while [ -L "\$source" ]; do
        dir="\$(cd -P "\$(dirname "\$source")" >/dev/null 2>&1 && pwd)"
        source="\$(ls -l "\$source" | awk '{print \$NF}')"
        [[ \$source != /* ]] && source="\$dir/\$source"
    done

    echo "\$source"
}

readonly REAL_SCRIPT_PATH="\$(get_script_path)"
readonly REAL_SCRIPT_DIR="\$(cd "\$(dirname "\${REAL_SCRIPT_PATH}")" >/dev/null 2>&1 && pwd)"
readonly MODULE_DIR="\$(dirname "\${REAL_SCRIPT_DIR}")"
readonly LIB_DIR="\${MODULE_DIR}/lib"
EOF
}

# Генерация загрузки библиотек
generate_library_loading() {
    local dispatcher_file="$1"
    local module_path="$2"

    local module_file="$module_path/module.yml"

    # Загружаем зависимые модули
    local module_dependencies
    if module_dependencies=$(yaml_get_module_dependencies "$module_file" 2>/dev/null); then
        cat >> "$dispatcher_file" << EOF
# Загружаем зависимые модули
EOF
        while IFS= read -r dep_module; do
            if [[ -n "$dep_module" ]]; then
                cat >> "$dispatcher_file" << EOF
for dep_lib in "\${MODULE_DIR}/../$dep_module/lib"/*.sh; do
    [[ -f "\$dep_lib" ]] && source "\$dep_lib"
done
EOF
            fi
        done <<< "$module_dependencies"

        cat >> "$dispatcher_file" << EOF

EOF
    fi

    # Загружаем библиотеки модуля
    local files
    if files=$(yaml_get_module_files "$module_file"); then
        cat >> "$dispatcher_file" << EOF
# Загружаем библиотеки модуля
EOF
        while IFS= read -r file_name; do
            if [[ -n "$file_name" && "$file_name" == *-lib.sh ]]; then
                cat >> "$dispatcher_file" << EOF
source "\${LIB_DIR}/$file_name"
EOF
            fi
        done <<< "$files"

        cat >> "$dispatcher_file" << EOF

EOF
    fi
}

# Генерация таблицы команд
generate_commands_table() {
    local dispatcher_file="$1"

    cat >> "$dispatcher_file" << EOF
# Таблица команд модуля
declare -A MODULE_COMMANDS=(
EOF

    # Добавляем каждую команду в таблицу
    for ((i=0; i<COMMANDS_COUNT; i++)); do
        local cmd_name_var="COMMAND_${i}_NAME"
        local cmd_function_var="COMMAND_${i}_FUNCTION"

        local cmd_name="${!cmd_name_var:-unknown_command_$i}"
        local cmd_function="${!cmd_function_var:-unknown_function_$i}"

        cat >> "$dispatcher_file" << EOF
    ["$cmd_name"]="$cmd_function"
EOF
    done

    cat >> "$dispatcher_file" << EOF
)

# Информация о командах для help
declare -A COMMAND_DESCRIPTIONS=(
EOF

    # Добавляем описания команд
    for ((i=0; i<COMMANDS_COUNT; i++)); do
        local cmd_name_var="COMMAND_${i}_NAME"
        local cmd_desc_var="COMMAND_${i}_DESCRIPTION"

        local cmd_name="${!cmd_name_var:-unknown_command_$i}"
        local cmd_desc="${!cmd_desc_var:-No description}"

        cat >> "$dispatcher_file" << EOF
    ["$cmd_name"]="$cmd_desc"
EOF
    done

    cat >> "$dispatcher_file" << EOF
)

declare -A COMMAND_USAGE=(
EOF

    # Добавляем usage информацию
    for ((i=0; i<COMMANDS_COUNT; i++)); do
        local cmd_name_var="COMMAND_${i}_NAME"
        local cmd_usage_var="COMMAND_${i}_USAGE"

        local cmd_name="${!cmd_name_var:-unknown_command_$i}"
        local cmd_usage="${!cmd_usage_var:-No usage info}"

        cat >> "$dispatcher_file" << EOF
    ["$cmd_name"]="$cmd_usage"
EOF
    done

    cat >> "$dispatcher_file" << EOF
)

EOF
}

# Генерация вспомогательных функций
generate_helper_functions() {
    local dispatcher_file="$1"
    local module_name="$2"

    cat >> "$dispatcher_file" << EOF
# Функция помощи
show_help() {
    echo "Usage: $module_name <command> [options]"
    echo ""
    echo "Description: $MODULE_DESCRIPTION"

    if [[ \${#MODULE_COMMANDS[@]} -gt 0 ]]; then
        echo ""
        echo "Available commands:"

        for cmd_name in "\${!MODULE_COMMANDS[@]}"; do
            local desc="\${COMMAND_DESCRIPTIONS[\$cmd_name]:-No description}"
            printf "  %-20s %s\n" "\$cmd_name" "\$desc"
        done

        echo ""
        echo "Use '$module_name <command> --help' for command-specific help"
    fi
}

# Функция помощи для конкретной команды
show_command_help() {
    local command="\$1"

    if [[ -n "\${MODULE_COMMANDS[\$command]:-}" ]]; then
        echo "Command: \$command"
        echo "Description: \${COMMAND_DESCRIPTIONS[\$command]:-No description}"
        echo "Usage: \${COMMAND_USAGE[\$command]:-No usage info}"
    else
        echo "Unknown command: \$command"
        return 1
    fi
}

# Поиск команды (поддержка частичного совпадения)
find_command() {
    local input_command="\$1"

    # Точное совпадение
    if [[ -n "\${MODULE_COMMANDS[\$input_command]:-}" ]]; then
        echo "\$input_command"
        return 0
    fi

    # Частичное совпадение (если есть пробелы в input)
    for cmd_name in "\${!MODULE_COMMANDS[@]}"; do
        if [[ "\$cmd_name" == "\$input_command"* ]]; then
            echo "\$cmd_name"
            return 0
        fi
    done


    return 1
}

EOF
}

# Генерация main функции
generate_main_function() {
    local dispatcher_file="$1"
    local module_name="$2"
    local route_unknown="$3"

    cat >> "$dispatcher_file" << EOF
# Главная функция диспетчеризации
main() {
    local args=("\$@")

    # Обработка случая без аргументов или help
    if [[ \${#args[@]} -eq 0 || "\${args[0]}" == "help" || "\${args[0]}" == "--help" || "\${args[0]}" == "-h" ]]; then
        show_help
        return 0
    fi

    # Строим команду из аргументов (поддерживаем команды с пробелами)
    local command_found=""
    local remaining_args=()

    # Пробуем команды от самых длинных к коротким
    for ((i=\${#args[@]}; i>=1; i--)); do
        local test_command=""
        for ((j=0; j<i; j++)); do
            if [[ \$j -eq 0 ]]; then
                test_command="\${args[j]}"
            else
                test_command="\$test_command \${args[j]}"
            fi
        done

        if [[ -n "\${MODULE_COMMANDS[\$test_command]:-}" ]]; then
            command_found="\$test_command"

            # Собираем оставшиеся аргументы
            for ((j=i; j<\${#args[@]}; j++)); do
                remaining_args+=("\${args[j]}")
            done
            break
        fi
    done

    # Если команда не найдена
    if [[ -z "\$command_found" ]]; then
        # выполняем routing в fallback
        if [[ $route_unknown == "true" ]]; then
            __unknown__ "\${args[@]}"
            return $?
        fi

        echo "Error: Unknown command '\${args[*]}'" >&2
        echo "Use '$module_name help' to see available commands" >&2
        return 1
    fi

    # Проверяем --help для найденной команды
    if [[ \${#remaining_args[@]} -gt 0 && ("\${remaining_args[0]}" == "--help" || "\${remaining_args[0]}" == "-h") ]]; then
        show_command_help "\$command_found"
        return 0
    fi

    # Выполняем команду
    local function_name="\${MODULE_COMMANDS[\$command_found]}"
    "\$function_name" "\${remaining_args[@]}"
}
EOF
}

main "$@"