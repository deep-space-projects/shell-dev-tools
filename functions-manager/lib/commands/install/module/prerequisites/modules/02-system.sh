#!/bin/bash
# ============================================================================
# Prerequisite Check: System utilities
# ============================================================================

main() {
    local modules_list="$1"

    log_debug "Checking system utilities availability"

    # Список обязательных системных утилит
    local required_commands=(
        "find"
        "sort"
        "mkdir"
        "chmod"
        "chown"
        "basename"
        "dirname"
        "whoami"
        "id"
    )

    # Список рекомендуемых утилит
    local recommended_commands=(
        "wget"
        "curl"
        "sudo"
        "getent"
        "jq"
    )

    local missing_required=()
    local missing_recommended=()

    # Проверяем обязательные команды
    log_debug "Checking required system commands..."
    for cmd in "${required_commands[@]}"; do
        if is_command_exists "$cmd"; then
            log_debug "Required command OK: $cmd"
        else
            log_error "Missing required command: $cmd"
            missing_required+=("$cmd")
        fi
    done

    # Проверяем рекомендуемые команды
    log_debug "Checking recommended system commands..."
    for cmd in "${recommended_commands[@]}"; do
        if is_command_exists "$cmd"; then
            log_debug "Recommended command OK: $cmd"
        else
            log_warning "Missing recommended command: $cmd"
            missing_recommended+=("$cmd")
        fi
    done

    # Дополнительные проверки
    check_bash_features
    check_file_permissions

    # Оценка результатов
    if [[ ${#missing_required[@]} -gt 0 ]]; then
        log_error "Missing required system utilities: ${missing_required[*]}"
        show_system_installation_instructions "${missing_required[@]}"
        return 1
    fi

    if [[ ${#missing_recommended[@]} -gt 0 ]]; then
        log_info "Missing recommended utilities: ${missing_recommended[*]}"
        log_info "Some features may be limited"
    fi

    log_success "System utilities check passed"
    return 0
}

# Проверка возможностей bash
check_bash_features() {
    log_debug "Checking bash features..."

    # Проверяем версию bash
    if [[ -n "$BASH_VERSION" ]]; then
        log_debug "Bash version: $BASH_VERSION"

        # Проверяем поддержку массивов
        local test_array=("test")
        if [[ ${#test_array[@]} -eq 1 ]]; then
            log_debug "Bash arrays supported"
        else
            log_warning "Bash arrays may not work correctly"
        fi

        # Проверяем поддержку ассоциативных массивов (bash 4+)
        if declare -A test_dict 2>/dev/null; then
            log_debug "Associative arrays supported"
        else
            log_debug "Associative arrays not supported (bash < 4.0)"
        fi
    else
        log_warning "Not running in bash shell"
    fi
}

# Проверка прав доступа к системным директориям
check_file_permissions() {
    log_debug "Checking file system permissions..."

    # Проверяем доступ к /tmp
    if [[ -d "/tmp" && -w "/tmp" ]]; then
        log_debug "Temporary directory writable: /tmp"
    else
        log_error "Cannot write to temporary directory: /tmp"
        return 1
    fi

    # Проверяем возможность создания временных файлов
    local test_file="/tmp/dev-tools-test-$$"
    if touch "$test_file" 2>/dev/null; then
        rm -f "$test_file" 2>/dev/null
        log_debug "Can create temporary files"
    else
        log_error "Cannot create temporary files in /tmp"
        return 1
    fi

    return 0
}

# Показ инструкций по установке системных утилит
show_system_installation_instructions() {
    local missing_commands=("$@")

    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        return 0
    fi

    local os_family=$(detect_os_family)

    log_info "System utilities installation instructions:"

    case "$os_family" in
        "debian")
            log_info "  sudo apt-get update"
            log_info "  sudo apt-get install -y coreutils findutils ${missing_commands[*]}"
            ;;
        "rhel")
            log_info "  sudo yum install -y coreutils findutils ${missing_commands[*]}"
            log_info "  # or: sudo dnf install -y coreutils findutils ${missing_commands[*]}"
            ;;
        "alpine")
            log_info "  apk add coreutils findutils ${missing_commands[*]}"
            ;;
        *)
            log_info "  Install the following commands using your system's package manager:"
            for cmd in "${missing_commands[@]}"; do
                log_info "    - $cmd"
            done
            ;;
    esac
}

main "$@"