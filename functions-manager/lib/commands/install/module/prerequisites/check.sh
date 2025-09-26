#!/bin/bash
# ============================================================================
# Prerequisites Check
# Coordinates prerequisite checking through modular components
# ============================================================================

# Главная функция проверки prerequisites
prerequisites_check() {
    local modules_list="$1"

    log_debug "Starting prerequisites check"

    # Определяем путь к prerequisites модулям
    local prerequisites_dir="${LIB_DIR}/commands/install/module/prerequisites"
    local modules_dir="${prerequisites_dir}/modules"

    if [[ ! -d "$modules_dir" ]]; then
        return $(handle_operation_error_quite "prerequisites_check" "Prerequisites modules directory not found: $modules_dir" 1)
    fi

    # Получаем список модулей в лексикографическом порядке
    local prerequisite_modules=()
    while IFS= read -r module_file; do
        if [[ -f "$module_file" && "$module_file" == *.sh ]]; then
            prerequisite_modules+=("$module_file")
        fi
    done <<< "$(find "$modules_dir" -name "*.sh" -type f 2>/dev/null | sort)"

    if [[ ${#prerequisite_modules[@]} -eq 0 ]]; then
        log_warning "No prerequisite modules found in: $modules_dir"
        return 0
    fi

    log_debug "Found ${#prerequisite_modules[@]} prerequisite modules"

    # Загружаем каждый модуль через source (код исполняется при загрузке)
    local failed_prerequisites=()

    for module_file in "${prerequisite_modules[@]}"; do
        local module_name=$(basename "$module_file" .sh)

        log_debug "Loading prerequisite module: $module_name"

        # Код модуля исполняется при source - результат через exit code
        if source "$module_file" "$modules_list"; then
            log_debug "Prerequisite check passed: $module_name"
        else
            log_warning "Prerequisite check failed: $module_name"
            failed_prerequisites+=("$module_name")
        fi
    done

    # Оценка результатов
    if [[ ${#failed_prerequisites[@]} -gt 0 ]]; then
        return $(handle_operation_error_quite "prerequisites_check" "Failed prerequisites: ${failed_prerequisites[*]}" 1)
    fi

    log_success "All prerequisites satisfied"
    return 0
}