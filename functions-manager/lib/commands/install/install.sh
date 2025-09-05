#!/bin/bash

install() {
    local module_dirs=""
    local system=false
    local recursive=false
    local verbose=false
    local interactive=false
    local daemon=false
    local privileged=false
    local error_policy="strict"

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --module-dirs=*)
                module_dirs="${1#*=}"
                shift
                ;;
            --system)
                system=true
                shift
                ;;
            -r|--recursive)
                recursive=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -d|--daemon)
                daemon=true
                shift
                ;;
            --privileged)
                privileged=true
                shift
                ;;
            --error-policy=*)
                error_policy="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Валидация обязательных параметров
    if [[ "$interactive" == false && "$daemon" == false ]]; then
        log_error "Must specify either --interactive or --daemon"
        exit 1
    fi

    if [[ "$interactive" == true && "$daemon" == true ]]; then
        log_error "Cannot specify both --interactive and --daemon"
        exit 1
    fi

    if [[ "$system" == false && -z "$module_dirs" ]]; then
        log_error "Must specify either --system or --module-dirs"
        exit 1
    fi

    # Установка verbose режима
    if [[ "$verbose" == true ]]; then
        logger_set_level DEBUG
    fi

    # Запрос прав администратора если нужно
    if [[ "$privileged" == true ]]; then
        if ! sudo -n true 2>/dev/null; then
            log_info "Requesting administrative privileges..."
            sudo -v || {
                log_error "Administrative privileges required"
                exit 1
            }
        fi
    fi

    # Установка политики ошибок
    set_error_policy "$error_policy"

    log_header "Starting Module Installation"

    # Определяем путь к install команде
    local install_dir="${LIB_DIR}/commands/install"

    # 1. Загрузка core компонентов
    log_step 1 "Loading core components"
    source "${LIB_DIR}/core/scanner.sh"
    source "${LIB_DIR}/core/yaml.sh"
    source "${LIB_DIR}/core/requirements-resolver.sh"
    log_success "Core components loaded"

    # 2. Сканирование модулей
    log_step 2 "Scanning for modules"
    local modules_list
    if ! modules_list=$(scanner_find_modules "$module_dirs" "$system" "$recursive"); then
        log_error "Failed to find modules"
        exit 1
    fi

    local module_count=$(echo "$modules_list" | wc -l)
    if [[ -z "$modules_list" || "$module_count" -eq 0 ]]; then
        log_warning "No modules found for installation"
        exit 0
    fi

    log_success "Found $module_count modules"

    # Показываем все найденные модули
    log_info "Found modules:"
    while IFS= read -r module_path; do
        if [[ -n "$module_path" ]]; then
            local module_name=$(basename "$module_path")
            log_info "  - $module_name ($module_path)"
        fi
    done <<< "$modules_list"

    # 3. Prerequisites проверка
    log_step 3 "Checking prerequisites"
    source "${install_dir}/prerequisites/check.sh"
    if ! prerequisites_check "$modules_list"; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    log_success "Prerequisites check passed"

    # 4. Валидация модулей
    log_step 4 "Validating modules"
    source "${install_dir}/validators/validation.sh"
    local validated_modules
    if ! validated_modules=$(validators_validate "$modules_list"); then
        log_error "Module validation failed"
        exit 1
    fi

    local validated_count=$(echo "$validated_modules" | wc -l)
    if [[ -z "$validated_modules" || "$validated_count" -eq 0 ]]; then
        log_error "No modules passed validation"
        exit 1
    fi
    log_success "Validated $validated_count modules"

    # 5. Генерация модулей
    log_step 5 "Generating modules"
    source "${install_dir}/generators/generator.sh"
    local temp_dir
    if ! temp_dir=$(generators_generate "$validated_modules"); then
        log_error "Module generation failed"
        exit 1
    fi
    log_success "Modules generated in: $temp_dir"

    # Очистка временной директории при выходе
    trap "rm -rf '$temp_dir'" EXIT

    # 6. Интерактивное подтверждение (если включено)
    if [[ "$interactive" == true ]]; then
        log_info "About to install $validated_count modules:"
        while IFS= read -r module_path; do
            local module_name=$(basename "$module_path")
            log_info "  - $module_name"
        done <<< "$validated_modules"

        echo -n "Proceed with installation? [y/N]: "
        read -r response
        if [[ "$response" != [yY] && "$response" != [yY][eE][sS] ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi

    # 7. Линковка и установка
    log_step 6 "Installing modules"
    source "${install_dir}/linker/linker.sh"
    if ! linker_install "$temp_dir" "$validated_modules"; then
        log_error "Module installation failed"
        exit 1
    fi

    log_success "Installation completed successfully!"
    log_info "Installed $validated_count modules"

    # Показываем установленные модули
    while IFS= read -r module_path; do
        local module_name=$(basename "$module_path")
        log_info "  ✓ $module_name"
    done <<< "$validated_modules"
}

install "$@"