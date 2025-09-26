#!/bin/bash
# ============================================================================
# Module Scanner
# Finds and collects modules from system and user directories
# ============================================================================

# Поиск и сбор модулей
scanner_find_modules() {
    local module_dirs="$1"
    local system="$2"
    local recursive="$3"

    local found_modules=()

    # 1. Системные модули (если указано)
    if [[ "$system" == "true" ]]; then
        log_debug "Collecting system modules..."

        # Hardcoded порядок системных модулей (TODO)
        local system_modules=("logger" "os" "env" "modes" "fs" "users" "groups" "permissions" "commands" "scripts" "operations" "modules" "archive")

        for module_name in "${system_modules[@]}"; do
            local module_dir="${LIB_DIR}/system/${module_name}"

            # Преобразуем в абсолютный путь
            local absolute_module_dir=$(cd "$module_dir" && pwd 2>/dev/null)

            if [[ -f "$absolute_module_dir/module.yml" ]]; then
                found_modules+=("$absolute_module_dir")
                log_debug "Added system module: $module_name ($absolute_module_dir)"
            else
                handle_operation_error_quite "scanner_find_modules" "System module not found: $module_name ($module_dir)" 1
                return 1
            fi
        done

        log_info "Found ${#found_modules[@]} system modules"
    fi

    # 2. Пользовательские модули (если указано)
    if [[ -n "$module_dirs" ]]; then
        log_debug "Collecting user modules from: $module_dirs"

        # Разбиваем module_dirs по запятым
        IFS=',' read -ra dirs_array <<< "$module_dirs"

        for dir in "${dirs_array[@]}"; do
            # Удаляем лишние пробелы
            dir="${dir// /}"

            if [[ -z "$dir" ]]; then
                continue
            fi

            # Преобразуем в абсолютный путь
            local absolute_dir=$(cd "$dir" && pwd 2>/dev/null)
            if [[ -z "$absolute_dir" ]]; then
                handle_operation_error_quite "scanner_find_modules" "Directory not found or inaccessible: $dir" 1
                return 1
            fi

            log_debug "Scanning directory: $absolute_dir (recursive=$recursive)"

            local dir_modules=()
            if ! dir_modules=($(scanner_scan_directory "$absolute_dir" "$recursive")); then
                handle_operation_error_quite "scanner_find_modules" "Failed to scan directory: $absolute_dir" 1
                return 1
            fi

            # Добавляем найденные модули (уже с абсолютными путями)
            for module_path in "${dir_modules[@]}"; do
                found_modules+=("$module_path")
                local module_name=$(basename "$module_path")
                log_debug "Added user module: $module_name ($module_path)"
            done
        done

        log_info "Found ${#dir_modules[@]} user modules"
    fi

    # Проверяем что нашли хотя бы один модуль
    if [[ ${#found_modules[@]} -eq 0 ]]; then
        log_warning "No modules found"
        return 1
    fi

    # Возвращаем найденные модули через stdout
    printf '%s\n' "${found_modules[@]}"
    return 0
}

# Сканирование одной директории
scanner_scan_directory() {
    local directory="$1"
    local recursive="$2"

    local found_modules=()

    if [[ "$recursive" == "true" ]]; then
        # Рекурсивный поиск module.yml файлов
        while IFS= read -r module_file; do
            if [[ -n "$module_file" ]]; then
                local module_dir=$(dirname "$module_file")
                # Преобразуем в абсолютный путь
                local absolute_module_dir=$(cd "$module_dir" && pwd 2>/dev/null)
                if [[ -n "$absolute_module_dir" ]]; then
                    found_modules+=("$absolute_module_dir")
                fi
            fi
        done <<< "$(find "$directory" -name "module.yml" -type f 2>/dev/null | sort)"

    else
        # Прямой поиск в директории
        if [[ -f "$directory/module.yml" ]]; then
            found_modules+=("$directory")
        fi

        # Также проверяем прямые поддиректории
        for subdir in "$directory"/*/; do
            if [[ -d "$subdir" && -f "$subdir/module.yml" ]]; then
                # Убираем trailing slash и преобразуем в абсолютный путь
                local clean_subdir="${subdir%/}"
                local absolute_subdir=$(cd "$clean_subdir" && pwd 2>/dev/null)
                if [[ -n "$absolute_subdir" ]]; then
                    found_modules+=("$absolute_subdir")
                fi
            fi
        done
    fi

    # Возвращаем найденные модули
    printf '%s\n' "${found_modules[@]}"
    return 0
}
