#!/bin/bash
# ============================================================================
# DRY_RUN Dependencies Waiting Implementation
# ============================================================================

set -euo pipefail

check_dependencies_scripts_directory() {
    tlog info "[DRY RUN] Would check directory: $CONTAINER_ENTRYPOINT_DEPENDENCIES"
    tlog info "[DRY RUN] Would execute all .sh files in lexicographic order"
    tlog info "[DRY RUN] Would apply TOTAL timeout: ${DEPENDENCY_TIMEOUT}s for all scripts combined"
    tlog info "[DRY RUN] Would apply error policy: $(cmn modes get-err)"
}

execute_dependencies_scripts() {
    # В DRY_RUN показываем какие скрипты нашли бы
    if [[ -d "$CONTAINER_ENTRYPOINT_DEPENDENCIES" ]]; then
        scripts_found=()
        while IFS= read -r -d '' script; do
            scripts_found+=("$script")
        done < <(find "$CONTAINER_ENTRYPOINT_DEPENDENCIES" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)

        if [[ ${#scripts_found[@]} -gt 0 ]]; then
            tlog info "[DRY RUN] Found ${#scripts_found[@]} dependency scripts:"
            for script in "${scripts_found[@]}"; do
                tlog info "[DRY RUN]   - $(basename "$script")"
            done
            tlog info "[DRY RUN] Would execute them with TOTAL timeout: ${DEPENDENCY_TIMEOUT}s"
        else
            tlog info "[DRY RUN] No .sh files found in $CONTAINER_ENTRYPOINT_DEPENDENCIES"
        fi
    else
        tlog info "[DRY RUN] Directory not found: $CONTAINER_ENTRYPOINT_DEPENDENCIES"
        tlog info "[DRY RUN] Would report no scripts to execute"
    fi
}