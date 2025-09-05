#!/bin/bash
# ============================================================================
# Module Execution System
# Provides universal module execution with error policies
# ============================================================================

# Выполнение одного модуля
execute_module() {
    local module_path="$1"
    shift
    local args=("$@")

    if [[ -z "$module_path" ]]; then
        log_error "Module path is required"
        return 1
    fi

    if [[ ! -f "$module_path" ]]; then
        return $(handle_operation_error_quite "execute_module" "Module file not found: $module_path" 1)
    fi

    if [[ ! -x "$module_path" ]]; then
        return $(handle_operation_error_quite "execute_module" "Module file is not executable: $module_path" 1)
    fi

    log_debug "Executing module: $(basename "$module_path")"

    if bash "$module_path" "${args[@]}"; then
        log_debug "Module completed successfully: $(basename "$module_path")"
        return 0
    else
        local exit_code=$?
        return $(handle_operation_error_quite "execute_module" "Module failed: $(basename "$module_path")" $exit_code)
    fi
}

# Выполнение всех модулей в директории в лексикографическом порядке
execute_modules_in_directory() {
    local directory="$1"
    shift
    local args=("$@")

    if [[ -z "$directory" ]]; then
        log_error "Directory path is required"
        return 1
    fi

    if [[ ! -d "$directory" ]]; then
        return $(handle_operation_error_quite "execute_modules_in_directory" "Directory not found: $directory" 1)
    fi

    log_info "Executing modules in directory: $directory"

    local module_files=()
    while IFS= read -r -d '' file; do
        module_files+=("$file")
    done < <(find "$directory" -name "*.sh" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#module_files[@]} -eq 0 ]]; then
        log_warning "No executable modules found in directory: $directory"
        return 0
    fi

    log_debug "Found ${#module_files[@]} modules to execute"

    local failed_modules=()
    local success_count=0

    for module_file in "${module_files[@]}"; do
        if execute_module "$module_file" "${args[@]}"; then
            success_count=$((success_count + 1))
        else
            failed_modules+=("$(basename "$module_file")")
        fi
    done

    if [[ ${#failed_modules[@]} -eq 0 ]]; then
        log_success "All modules completed successfully ($success_count/${#module_files[@]})"
        return 0
    else
        log_warning "Some modules failed: ${failed_modules[*]}"
        log_info "Successful modules: $success_count/${#module_files[@]}"
        return 1
    fi
}