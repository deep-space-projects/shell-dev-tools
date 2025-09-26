#!/bin/bash
# ============================================================================
# Module Generator
# Coordinates module generation through modular generators
# ============================================================================

# Главная функция генерации модулей
generate_modules() {
    local validated_modules="$1"

    log_debug "Starting module generation"

    # Создаем временную директорию для генерации
    local temp_dir="/tmp/dev-tools-install-$(whoami)-$$"
    log_info "Creating temporary directory: $temp_dir"

    if ! safe_mkdir "$temp_dir" "" "755"; then
        return $(handle_operation_error_quite "generate_modules" "Failed to create temporary directory: $temp_dir" 1)
    fi

    # Определяем путь к generator модулям
    local generators_dir="${LIB_DIR}/commands/install/module/generators"
    local modules_dir="${generators_dir}/modules"

    if [[ ! -d "$modules_dir" ]]; then
        return $(handle_operation_error_quite "generate_modules" "Generator modules directory not found: $modules_dir" 1)
    fi

    # Получаем список генераторов в лексикографическом порядке
    local generator_modules=()
    while IFS= read -r generator_file; do
        if [[ -f "$generator_file" && "$generator_file" == *.sh ]]; then
            generator_modules+=("$generator_file")
        fi
    done <<< "$(find "$modules_dir" -name "*.sh" -type f 2>/dev/null | sort)"

    if [[ ${#generator_modules[@]} -eq 0 ]]; then
        return $(handle_operation_error_quite "generate_modules" "No generator modules found in: $modules_dir" 1)
    fi

    log_debug "Found ${#generator_modules[@]} generator modules"

    # Обрабатываем каждый модуль из validated_modules
    local generated_modules=()
    local failed_modules=()
    local total_modules=0

    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            total_modules=$((total_modules + 1))
            local module_name=$(basename "$module_path")

            log_debug "Generating module: $module_name"

            if generate_single_module "$module_path" "$temp_dir" "${generator_modules[@]}"; then
                generated_modules+=("$module_name")
                log_debug "Module generation completed: $module_name"
            else
                failed_modules+=("$module_name")
                log_warning "Module generation failed: $module_name"
            fi
        fi
    done <<< "$validated_modules"

    # Оценка результатов
    local generated_count=${#generated_modules[@]}
    local failed_count=${#failed_modules[@]}

    log_info "Module generation completed: $generated_count/$total_modules successful"

    if [[ $failed_count -gt 0 ]]; then
        handle_operation_error_quite "generate_modules" "Failed module generations: ${failed_modules[*]}" 1
    fi

    # Проверяем что есть хотя бы один сгенерированный модуль
    if [[ $generated_count -eq 0 ]]; then
        return $(handle_operation_error_quite "generate_modules" "No modules were successfully generated" 1)
    fi

    log_success "Module generation completed successfully"

    # Возвращаем путь к temporary directory
    echo "$temp_dir"
    return 0
}

# Генерация одного модуля
generate_single_module() {
    local module_path="$1"
    local temp_dir="$2"
    shift 2
    local generator_modules=("$@")

    local module_name=$(basename "$module_path")

    log_debug "Processing module generation: $module_name"

    # Создаем директорию модуля во временной папке
    local module_temp_dir="$temp_dir/$module_name"
    if ! safe_mkdir "$module_temp_dir" "" "755"; then
        log_error "Failed to create module temp directory: $module_temp_dir"
        return 1
    fi

    # Применяем каждый генератор к модулю
    local failed_generators=()

    for generator_file in "${generator_modules[@]}"; do
        local generator_name=$(basename "$generator_file" .sh)

        log_debug "Running generator '$generator_name' for module '$module_name'"

        # Каждый генератор получает:
        # 1. Путь к исходному модулю
        # 2. Путь к временной директории модуля
        if source "$generator_file" "$module_path" "$module_temp_dir"; then
            log_debug "Generator '$generator_name' completed for module '$module_name'"
        else
            log_error "Generator '$generator_name' failed for module '$module_name'"
            failed_generators+=("$generator_name")
        fi
    done

    # Проверяем результат генерации
    if [[ ${#failed_generators[@]} -gt 0 ]]; then
        log_error "Module '$module_name' generation failed in generators: ${failed_generators[*]}"
        return 1
    fi

    # Проверяем что создалась правильная структура модуля
    if ! validate_generated_module_structure "$module_temp_dir" "$module_name"; then
        log_error "Generated module structure is invalid: $module_name"
        return 1
    fi

    log_debug "Module '$module_name' generated successfully"
    return 0
}

# Валидация структуры сгенерированного модуля
validate_generated_module_structure() {
    local module_temp_dir="$1"
    local module_name="$2"

    # Проверяем основную структуру
    if [[ ! -d "$module_temp_dir/bin" ]]; then
        log_error "Missing bin directory in generated module: $module_name"
        return 1
    fi

    if [[ ! -d "$module_temp_dir/lib" ]]; then
        log_error "Missing lib directory in generated module: $module_name"
        return 1
    fi

    # Проверяем главный исполняемый файл
    local main_script="$module_temp_dir/bin/$module_name.sh"
    if [[ ! -f "$main_script" ]]; then
        log_error "Missing main script in generated module: $module_name.sh"
        return 1
    fi

    # Проверяем что скрипт исполняемый
    if [[ ! -x "$main_script" ]]; then
        log_error "Main script is not executable: $module_name.sh"
        return 1
    fi

    # Проверяем наличие библиотек в lib
    local lib_files_count=$(find "$module_temp_dir/lib" -name "*.sh" -type f 2>/dev/null | wc -l)
    if [[ $lib_files_count -eq 0 ]]; then
        log_warning "No library files found in generated module: $module_name"
    fi

    log_debug "Generated module structure validated: $module_name"
    return 0
}