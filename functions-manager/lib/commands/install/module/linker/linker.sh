#!/bin/bash
# ============================================================================
# Module Linker
# Coordinates module installation through modular linkers
# ============================================================================

# Главная функция линковки модулей
linker_install() {
    local temp_dir="$1"
    local validated_modules="$2"

    log_debug "Starting module installation from: $temp_dir"

    # Централизованная конфигурация путей
    local target_lib_dir="/usr/local/lib/devtools/packages"
    local target_bin_dir=$(get_system_bin_dir)

    # Определяем путь к linker модулям
    local linkers_dir="${LIB_DIR}/commands/install/module/linker"
    local modules_dir="${linkers_dir}/modules"

    if [[ ! -d "$modules_dir" ]]; then
        return $(handle_operation_error_quite "linker_install" "Linker modules directory not found: $modules_dir" 1)
    fi

    # Получаем список линкеров в лексикографическом порядке
    local linker_modules=()
    while IFS= read -r linker_file; do
        if [[ -f "$linker_file" && "$linker_file" == *.sh ]]; then
            linker_modules+=("$linker_file")
        fi
    done <<< "$(find "$modules_dir" -name "*.sh" -type f 2>/dev/null | sort)"

    if [[ ${#linker_modules[@]} -eq 0 ]]; then
        return $(handle_operation_error_quite "linker_install" "No linker modules found in: $modules_dir" 1)
    fi

    log_debug "Found ${#linker_modules[@]} linker modules"

    # Применяем каждый линкер
    for linker_file in "${linker_modules[@]}"; do
        local linker_name=$(basename "$linker_file" .sh)

        log_debug "Running linker: $linker_name"

        # Каждый линкер получает:
        # 1. Путь к временной директории
        # 2. Список валидированных модулей
        # 3. Целевая директория для библиотек
        # 4. Целевая директория для бинарников
        if source "$linker_file" "$temp_dir" "$validated_modules" "$target_lib_dir" "$target_bin_dir"; then
            log_debug "Linker completed successfully: $linker_name"
        else
            return $(handle_operation_error_quite "linker_install" "Linker failed: $linker_name" 1)
        fi
    done

    log_success "Module installation completed successfully"
    return 0
}
