#!/bin/bash

set -euo pipefail

# Загрузка нужной реализации модуля в зависимости от режима выполнения
load_module_implementation() {
    local module_name="$1"

    if [[ -z "$module_name" ]]; then
        log_error "Module name is required for load_module_implementation"
        return 1
    fi

    local impl_file
    case "$(get_exec_mode_name)" in
        "DRY_RUN")
            impl_file="${CONTAINER_TOOLS}/entrypoint/modules/implementations/dry_run/${module_name}-impl.sh"
            ;;
        *)
            impl_file="${CONTAINER_TOOLS}/entrypoint/modules/implementations/standard/${module_name}-impl.sh"
            ;;
    esac

    if [[ ! -f "$impl_file" ]]; then
        log_error "Implementation file not found: $impl_file"
        return 1
    fi

    log_debug "Loading $(get_exec_mode_name) implementation: $(basename "$impl_file")"
    source "$impl_file"
}

export -f load_module_implementation