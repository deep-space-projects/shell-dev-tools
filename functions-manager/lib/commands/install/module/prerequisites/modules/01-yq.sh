#!/bin/bash
# ============================================================================
# Prerequisite Check: yq utility
# ============================================================================

main() {
    local modules_list="$1"

    log_debug "Checking yq utility availability"

    # Проверяем доступность yq
    if is_command_exists yq; then
        local yq_version=$(yq --version 2>/dev/null | head -n1)
        log_success "yq is available: $yq_version"

        # Проверяем реализацию
        if echo "$yq_version" | grep -q "mikefarah/yq"; then
            log_debug "Using correct yq implementation (mikefarah/yq)"
        else
            log_warning "Found different yq implementation: $yq_version"
            log_info "Recommended: mikefarah/yq v4+"
        fi

        return 0
    else
        log_error "yq utility not found"

        # Показываем инструкции по установке
        local os_family=$(detect_os_family)
        log_info "Installation instructions:"
        case "$os_family" in
            "debian"|"rhel")
                log_info "  wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
                log_info "  chmod +x /usr/local/bin/yq"
                ;;
            "alpine")
                log_info "  apk add yq"
                ;;
        esac

        return 1
    fi
}

main "$@"