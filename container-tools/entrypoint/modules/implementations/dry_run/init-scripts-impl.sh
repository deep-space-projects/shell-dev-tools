#!/bin/bash
# ============================================================================
# DRY_RUN Init Scripts Execution Implementation
# ============================================================================

set -euo pipefail

check_init_scripts_directory() {
    tlog info "[DRY RUN] Would check directory: $CONTAINER_ENTRYPOINT_SCRIPTS"
    tlog info "[DRY RUN] Would execute all .sh files in lexicographic order"
    tlog info "[DRY RUN] Would apply error policy: $(cmn modes get-err)"
}

execute_init_scripts() {
    # В DRY_RUN показываем какие скрипты нашли бы
    if [[ -d "$CONTAINER_ENTRYPOINT_SCRIPTS" ]]; then
        scripts_found=()
        while IFS= read -r -d '' script; do
            scripts_found+=("$script")
        done < <(find "$CONTAINER_ENTRYPOINT_SCRIPTS" -maxdepth 1 -name "*.sh" -type f -print0 | sort -z)

        if [[ ${#scripts_found[@]} -gt 0 ]]; then
            tlog info "[DRY RUN] Found ${#scripts_found[@]} init scripts:"
            for script in "${scripts_found[@]}"; do
                tlog info "[DRY RUN]   - $(basename "$script")"
            done
            tlog info "[DRY RUN] Would execute them in lexicographic order"
        else
            tlog info "[DRY RUN] No .sh files found in $CONTAINER_ENTRYPOINT_SCRIPTS"
        fi
    else
        tlog info "[DRY RUN] Directory not found: $CONTAINER_ENTRYPOINT_SCRIPTS"
        tlog info "[DRY RUN] Would report no scripts to execute"
    fi
}