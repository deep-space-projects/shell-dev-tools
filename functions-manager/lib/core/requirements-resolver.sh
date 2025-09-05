#!/bin/bash
# ============================================================================
# Requirements Resolver
# Checks and validates module requirements (environment vars, packages)
# ============================================================================

# Проверка требований к переменным окружения
requirements_check_environment() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    log_debug "Checking environment requirements for: $(basename "$(dirname "$module_file")")"

    # Получаем список требуемых переменных
    local env_vars
    if ! env_vars=$(yaml_get_module_env_requirements "$module_file"); then
        log_debug "No environment requirements found"
        return 0
    fi

    local missing_vars=()

    # Проверяем каждую переменную
    while IFS= read -r var_name; do
        if [[ -n "$var_name" ]]; then
            local var_value="${!var_name}"

            if [[ -z "$var_value" ]]; then
                missing_vars+=("$var_name")
                log_debug "Missing environment variable: $var_name"
            else
                log_debug "Environment variable OK: $var_name"
            fi
        fi
    done <<< "$env_vars"

    # Проверяем результат
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        return 1
    fi

    log_debug "All environment requirements satisfied"
    return 0
}

# Проверка требований к пакетам
requirements_check_packages() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    log_debug "Checking package requirements for: $(basename "$(dirname "$module_file")")"

    # Получаем список требуемых пакетов
    local packages
    if ! packages=$(yaml_get_module_package_requirements "$module_file"); then
        log_debug "No package requirements found"
        return 0
    fi

    local missing_packages=()

    # Проверяем каждый пакет
    while IFS= read -r package_name; do
        if [[ -n "$package_name" ]]; then
            if ! requirements_check_single_package "$package_name"; then
                missing_packages+=("$package_name")
                log_debug "Missing package: $package_name"
            else
                log_debug "Package OK: $package_name"
            fi
        fi
    done <<< "$packages"

    # Проверяем результат
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_warning "Missing required packages:"
        for package in "${missing_packages[@]}"; do
            log_warning "  - $package"
        done

        # Показываем инструкции по установке
        requirements_show_package_install_instructions "${missing_packages[@]}"

        return 1
    fi

    log_debug "All package requirements satisfied"
    return 0
}

# Проверка одного пакета
requirements_check_single_package() {
    local package_name="$1"

    if [[ -z "$package_name" ]]; then
        return 1
    fi

    # Простая проверка через is_command_exists
    if is_command_exists "$package_name"; then
        return 0
    fi

    # Дополнительные проверки для известных пакетов
    case "$package_name" in
        "openssl")
            is_command_exists openssl
            ;;
        "curl")
            is_command_exists curl
            ;;
        "jq")
            is_command_exists jq
            ;;
        "yq")
            is_command_exists yq
            ;;
        "git")
            is_command_exists git
            ;;
        "docker")
            is_command_exists docker
            ;;
        *)
            # Для неизвестных пакетов пробуем как команду
            is_command_exists "$package_name"
            ;;
    esac
}

# Показ инструкций по установке пакетов
requirements_show_package_install_instructions() {
    local packages=("$@")

    if [[ ${#packages[@]} -eq 0 ]]; then
        return 0
    fi

    local os_family=$(detect_os_family)

    log_info "Installation instructions for missing packages:"

    case "$os_family" in
        "debian")
            log_info "  sudo apt-get update && sudo apt-get install -y ${packages[*]}"
            ;;
        "rhel")
            log_info "  sudo yum install -y ${packages[*]}"
            log_info "  # or: sudo dnf install -y ${packages[*]}"
            ;;
        "alpine")
            log_info "  apk add ${packages[*]}"
            ;;
        *)
            log_info "  Please install the following packages using your system's package manager:"
            for package in "${packages[@]}"; do
                log_info "    - $package"
            done
            ;;
    esac
}

# Проверка всех требований модуля
requirements_check_all() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local module_name=$(basename "$(dirname "$module_file")")
    log_debug "Checking all requirements for module: $module_name"

    local failed_checks=()

    # Проверяем переменные окружения
    if ! requirements_check_environment "$module_file"; then
        failed_checks+=("environment")
    fi

    # Проверяем пакеты
    if ! requirements_check_packages "$module_file"; then
        failed_checks+=("packages")
    fi

    # Проверяем результат
    if [[ ${#failed_checks[@]} -gt 0 ]]; then
        log_error "Requirements check failed for module '$module_name': ${failed_checks[*]}"
        return 1
    fi

    log_debug "All requirements satisfied for module: $module_name"
    return 0
}

# Получение информации о требованиях модуля
requirements_get_info() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local module_name=$(basename "$(dirname "$module_file")")

    echo "module=$module_name"

    # Переменные окружения
    local env_vars
    if env_vars=$(yaml_get_module_env_requirements "$module_file"); then
        local env_count=$(echo "$env_vars" | wc -l)
        echo "env_vars_count=$env_count"
        echo "env_vars=$env_vars"
    else
        echo "env_vars_count=0"
    fi

    # Пакеты
    local packages
    if packages=$(yaml_get_module_package_requirements "$module_file"); then
        local packages_count=$(echo "$packages" | wc -l)
        echo "packages_count=$packages_count"
        echo "packages=$packages"
    else
        echo "packages_count=0"
    fi

    return 0
}