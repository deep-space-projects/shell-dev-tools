#!/bin/bash
# ============================================================================
# Common Functions for Container Tools
# Provides platform detection, basic utilities and common functions
# ============================================================================

# Обработка ошибок согласно политике EXEC_ERROR_POLICY
handle_operation_result() {
    local operation_name="Operation"
    local error_message="${2:-Operation failed}"
    local exit_code=1
    local error_policy=$(get_current_error_policy)

    # Парсим именованные параметры
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--operation=*)
                operation_name="${1#*=}"
                shift
                ;;
            -e|--error-message=*)
                error_message="${1#*=}"
                shift
                ;;
            -c|--exit-code=*)
                exit_code="${1#*=:}"
                shift
                ;;
            -e|--error-policy=*)
                error_policy="${1#*=:}"
                shift
                ;;
            *)
                log_error "Unknow parameters: $@"
                exit 1
                ;;
        esac
    done


    case "$error_policy" in
        "${ERROR_POLICY_STRICT}")
            log_error "Failed to $operation_name"
            log_error "$error_message"
            exit $exit_code
            ;;
        "${ERROR_POLICY_SOFT}")
            log_warning "Failed to $operation_name, continuing due to soft error policy"
            log_warning "$error_message"
            return 0
            ;;
        "${ERROR_POLICY_CUSTOM}")
            log_warning "Failed to $operation_name (custom error handling)"
            log_warning "$error_message"
            return $exit_code
            ;;
        *)
            log_warning "Failed to $operation_name, unknown error policy: $(get_error_policy_name)"
            log_warning "$error_message"
            return $exit_code
            ;;
    esac
}

handle_operation_error_quite() {
  handle_operation_result \
        --operation=$1 \
        --error-message=$2
        --exit-code=$3
  return $?
}