#!/bin/bash
# ============================================================================
# YAML Parser
# Wrapper functions for yq utility with fallback handling
# ============================================================================

# Проверка доступности yq
yaml_check_availability() {
    if ! is_command_exists yq; then
        log_error "yq utility is required but not found"
        log_info "Please install yq: https://github.com/mikefarah/yq"
        return 1
    fi

    # Проверяем версию yq (v4+ предпочтительно)
    local yq_version=$(yq --version 2>/dev/null | head -n1)
    log_trace "Using yq: $yq_version"

    return 0
}

# Получить зависимости модуля
yaml_get_module_dependencies() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local dependencies
    if dependencies=$(yaml_get_array "$module_file" ".specification.module.dependencies.modules"); then
        echo "$dependencies"
        return 0
    fi

    return 1
}

# Получить значение из YAML файла
yaml_get() {
    local yaml_file="$1"
    local yaml_path="$2"

    if [[ -z "$yaml_file" || -z "$yaml_path" ]]; then
        log_error "Usage: yaml_get <file> <path>"
        return 1
    fi

    if [[ ! -f "$yaml_file" ]]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    if ! yaml_check_availability; then
        return 1
    fi

    local result
    if result=$(yq eval "$yaml_path" "$yaml_file" 2>/dev/null); then
        # Проверяем что результат не null
        if [[ "$result" == "null" ]]; then
            return 1
        fi
        echo "$result"
        return 0
    else
        log_debug "Failed to get YAML path '$yaml_path' from '$yaml_file'"
        return 1
    fi
}

# Получить массив значений из YAML
yaml_get_array() {
    local yaml_file="$1"
    local yaml_path="$2"

    if [[ -z "$yaml_file" || -z "$yaml_path" ]]; then
        log_error "Usage: yaml_get_array <file> <path>"
        return 1
    fi

    if ! yaml_check_availability; then
        return 1
    fi

    local result
    if result=$(yq eval "${yaml_path}[]?" "$yaml_file" 2>/dev/null); then
        if [[ -n "$result" && "$result" != "null" ]]; then
            echo "$result"
            return 0
        fi
    fi

    return 1
}

# Проверить валидность YAML файла
yaml_validate() {
    local yaml_file="$1"

    if [[ -z "$yaml_file" ]]; then
        log_error "Usage: yaml_validate <file>"
        return 1
    fi

    if [[ ! -f "$yaml_file" ]]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    if ! yaml_check_availability; then
        return 1
    fi

    if yq eval '.' "$yaml_file" >/dev/null 2>&1; then
        log_debug "YAML file is valid: $yaml_file"
        return 0
    else
        log_error "Invalid YAML file: $yaml_file"
        return 1
    fi
}

# Получить метаданные модуля
yaml_get_module_metadata() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local name version description author

    name=$(yaml_get "$module_file" ".metadata.name")
    version=$(yaml_get "$module_file" ".metadata.version")
    description=$(yaml_get "$module_file" ".metadata.description")
    author=$(yaml_get "$module_file" ".metadata.author")

    # Проверяем обязательные поля
    if [[ -z "$name" ]]; then
        log_error "Missing required field: metadata.name"
        return 1
    fi

    echo "name=$name"
    echo "version=${version:-unknown}"
    echo "description=${description:-}"
    echo "author=${author:-}"

    return 0
}

# Получить метаданные модуля
yaml_get_module_unknown_route() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local route_unknown

    route_unknown=$(yaml_get "$module_file" ".specification.module.routes.unknown")

    if [[ -z "$route_unknown" ]]; then
        route_unknown="false"
    fi

    echo $route_unknown
    return 0
}

# Получить команды модуля
yaml_get_module_commands() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local commands
    if commands=$(yaml_get_array "$module_file" ".specification.module.commands"); then
        echo "$commands"
        return 0
    fi

    return 1
}

# Получить требования модуля к переменным окружения
yaml_get_module_env_requirements() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local env_vars
    if env_vars=$(yaml_get_array "$module_file" ".specification.module.requirements.environment"); then
        echo "$env_vars"
        return 0
    fi

    return 1
}

# Получить требования модуля к пакетам
yaml_get_module_package_requirements() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local packages
    if packages=$(yaml_get_array "$module_file" ".specification.module.requirements.packages.list"); then
        echo "$packages"
        return 0
    fi

    return 1
}

# Получить файлы модуля
yaml_get_module_files() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local files
    if files=$(yaml_get_array "$module_file" ".specification.module.files"); then
        echo "$files"
        return 0
    fi

    return 1
}

# Получить файлы модуля
yaml_get_module_binaries() {
    local module_file="$1"

    if [[ ! -f "$module_file" ]]; then
        log_error "Module file not found: $module_file"
        return 1
    fi

    local files
    if files=$(yaml_get_array "$module_file" ".specification.module.binaries"); then
        echo "$files"
        return 0
    fi

    return 1
}