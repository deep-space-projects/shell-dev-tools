#!/bin/bash
# ============================================================================
# Functions-Manager Builder
# Builds and installs fman system from sources
# ============================================================================

set -euo pipefail

# Определяем базовые пути
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly PROJECT_LIB_DIR="$PROJECT_DIR/lib"

# Загружаем системные модули для использования в build процессе
source "${PROJECT_LIB_DIR}/system/logger/logger-lib.sh"
source "${PROJECT_LIB_DIR}/system/fs/fs-lib.sh"
#source "${PROJECT_LIB_DIR}/system/platform/platform-lib.sh"

# Функция показа справки
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build and install fman system from sources.

OPTIONS:
  --output=PATH             Path to install fman binary (default: /usr/local/bin/functions-manager)
  --lib-dir=PATH            Path to install libraries (default: /usr/local/lib/devtools/packages)
  --verbose, -v             Enable debug logging
  --interactive             Interactive mode - ask for confirmations
  --daemon                  Daemon mode - no user interaction
  --privileged              Request privileges upfront
  --clean                   Clean previous installation before building
  --help, -h                Show this help message

Examples:
  $0 --interactive --verbose
  $0 --daemon --clean --privileged
  $0 --output=/opt/functions-manager --lib-dir=/opt/functions-manager-lib

EOF
}

# Главная функция сборки
build_dev_tools() {
    local output_path="/usr/local/bin/fman"
    local lib_dir="/usr/local/lib/devtools/functions-manager"
    local verbose=false
    local interactive=false
    local daemon=false
    local privileged=false
    local clean=false

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -0|--output=*)
                output_path="${1#*=}"
                shift
                ;;
            --lib-dir=*)
                lib_dir="${1#*=}"
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
            --clean)
                clean=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Валидация аргументов
    if [[ "$interactive" == false && "$daemon" == false ]]; then
        log_error "Must specify either --interactive or --daemon"
        exit 1
    fi

    if [[ "$interactive" == true && "$daemon" == true ]]; then
        log_error "Cannot specify both --interactive and --daemon"
        exit 1
    fi

    # Установка verbose режима
    if [[ "$verbose" == true ]]; then
        logger_set_level DEBUG
    fi

    # Проверка и подсказка как запустить
    if [[ "$privileged" == true ]]; then
        if [[ "$EUID" -ne 0 ]]; then
            log_error "Root privileges required for this operation"

            # Проверяем доступен ли sudo
            if command -v >/dev/null 2>&1; then
                log_info "Please run: $0 $*"
            else
                log_info "Please run as root user"
            fi

            exit 1
        else
            log_debug "Root privileges confirmed"
        fi
    fi

    log_header "Building Dev-Tools System"
    log_info "Project directory: $PROJECT_DIR"
    log_info "Target binary: $output_path"
    log_info "Target libraries: $lib_dir"

    # Этап 1: Инициализация и проверка
    log_step 1 "Validating project structure"
    if ! validate_project_structure; then
        log_error "Project structure validation failed"
        exit 1
    fi
    log_success "Project structure validated"

    # Этап 2: Очистка предыдущей установки
    if [[ "$clean" == true ]]; then
        log_step 2 "Cleaning previous installation"
        if ! clean_previous_installation "$output_path" "$lib_dir"; then
            log_error "Failed to clean previous installation"
            exit 1
        fi
        log_success "Previous installation cleaned"
    fi

    # Этап 3: Подготовка временной директории
    log_step 3 "Preparing build environment"
    local temp_dir
    if ! temp_dir=$(prepare_build_environment); then
        log_error "Failed to prepare build environment"
        exit 1
    fi
    log_success "Build environment prepared: $temp_dir"

    # Очистка временной директории при выходе
    trap "rm -rf '$temp_dir'" EXIT

    # Этап 4: Сборка fman
    log_step 4 "Building fman"
    if ! build_dev_tools_binary "$temp_dir" "$lib_dir"; then
        log_error "Failed to build fman"
        exit 1
    fi
    log_success "Dev-tools built successfully"

    # Этап 5: Интерактивное подтверждение
    if [[ "$interactive" == true ]]; then
        echo -n "Install fman to $output_path? [y/N]: "
        read -r response
        if [[ "$response" != [yY] && "$response" != [yY][eE][sS] ]]; then
            log_info "Installation cancelled by user"
            exit 0
        fi
    fi

    # Этап 6: Установка
    log_step 5 "Installing fman"
    if ! install_functions_manager "$temp_dir" "$output_path" "$lib_dir"; then
        log_error "Failed to install fman"
        exit 1
    fi
    log_success "Dev-tools installed successfully"

    # Этап 7: Проверка установки
    log_step 6 "Validating installation"
    if ! validate_installation "$output_path"; then
        log_error "Installation validation failed"
        exit 1
    fi
    log_success "Installation validated"

    # Этап 8: Интерактивное подтверждение
    log_step 8 "Install fman core libraries"
    if [[ "$interactive" == true ]]; then
        echo -n "Install fman core libraries? [y/N]: "
        read -r response
        if [[ "$response" == [yY] || "$response" == [yY][eE][sS] ]]; then
            fman install -d --system
        fi
    else
      fman install -d --system
    fi

    # Показываем итоговую информацию
    show_installation_summary "$output_path" "$lib_dir"
}

# Валидация структуры проекта
validate_project_structure() {
    log_debug "Validating project structure"

    # Проверяем основные директории
    local required_dirs=("lib" "lib/system" "lib/commands" "lib/core")
    for dir in "${required_dirs[@]}"; do
        local full_path="$PROJECT_DIR/$dir"
        if [[ ! -d "$full_path" ]]; then
            log_error "Missing required directory: $full_path"
            return 1
        fi
    done

    # Проверяем системные модули
    local system_modules=("logger" "os" "env" "modes" "fs" "users" "groups" "permissions" "commands" "scripts" "operations" "modules" "archive")
    for module in "${system_modules[@]}"; do
        local module_dir="$PROJECT_LIB_DIR/system/$module"
        if [[ ! -d "$module_dir" ]]; then
            log_error "Missing system module: $module"
            return 1
        fi

        if [[ ! -f "$module_dir/module.yml" ]]; then
            log_error "Missing module.yml for system module: $module"
            return 1
        fi

        if [[ ! -f "$module_dir/${module}-lib.sh" ]]; then
            log_error "Missing library file for system module: $module"
            return 1
        fi
    done

    log_debug "Project structure validation completed"
    return 0
}

# Очистка предыдущей установки
clean_previous_installation() {
    local output_path="$1"
    local lib_dir="$2"

    log_debug "Cleaning previous installation"

    # Удаляем исполняемый файл
    if [[ -f "$output_path" ]]; then
        log_debug "Removing previous binary: $output_path"
        if ! rm -f "$output_path" 2>/dev/null; then
            log_error "Failed to remove previous binary: $output_path"
            return 1
        fi
    fi

    # Удаляем библиотеки
    if [[ -d "$lib_dir" ]]; then
        log_debug "Removing previous libraries: $lib_dir"
        if ! rm -rf "$lib_dir" 2>/dev/null; then
            log_error "Failed to remove previous libraries: $lib_dir"
            return 1
        fi
    fi

    return 0
}

# Подготовка среды сборки
prepare_build_environment() {
    local temp_dir="/tmp/functions-manager-build-$(whoami)-$$"

    log_debug "Creating temporary build directory: $temp_dir"

    if ! safe_mkdir "$temp_dir" "" "755"; then
        log_error "Failed to create temporary directory: $temp_dir"
        return 1
    fi

    echo "$temp_dir"
    return 0
}

build_dev_tools_binary() {
    local temp_dir="$1"
    local target_lib_dir="$2"

    log_debug "Building fman structure"

    # Копируем все библиотеки в temp_dir/lib
    if ! cp -r "$PROJECT_LIB_DIR" "$temp_dir/"; then
        log_error "Failed to copy libraries to build directory"
        return 1
    fi

    # Создаем bin директорию в временной папке
    local bin_dir="$temp_dir/bin"
    if ! mkdir -p "$bin_dir"; then
        log_error "Failed to create bin directory"
        return 1
    fi

    # Создаем исполняемый файл fman.sh в bin директории
    local dev_tools_binary="$bin_dir/functions-manager.sh"

    cat > "$dev_tools_binary" << EOF
#!/bin/bash

set -euo pipefail

# Определяем путь к fman (относительно bin директории)
readonly DEV_TOOLS_DIR="$target_lib_dir"
readonly LIB_DIR="\${DEV_TOOLS_DIR}/lib"

# Загружаем системные модули в source для использования их функций
source "\${LIB_DIR}/system/logger/logger-lib.sh"
source "\${LIB_DIR}/system/modes/modes-lib.sh"
source "\${LIB_DIR}/system/env/env-lib.sh"
source "\${LIB_DIR}/system/operations/operations-lib.sh"
source "\${LIB_DIR}/system/commands/commands-lib.sh"
source "\${LIB_DIR}/system/fs/fs-lib.sh"
source "\${LIB_DIR}/system/os/os-lib.sh"
source "\${LIB_DIR}/system/archive/archive-lib.sh"

#source "\${LIB_DIR}/system/common/common-lib.sh"
#source "\${LIB_DIR}/system/platform/platform-lib.sh"
#source "\${LIB_DIR}/system/permissions/permissions-lib.sh"
#source "\${LIB_DIR}/system/modules/modules-lib.sh"

# Парсинг команды
readonly COMMAND="\${1:-}"

if [[ -z "\$COMMAND" ]]; then
    log_error "No command specified"
    echo "Usage: fman <command> [options]"
    echo "Available commands:"

    # Ищем команды в директориях commands
    for cmd_dir in "\${LIB_DIR}/commands"/*; do
        if [[ -d "\$cmd_dir" ]]; then
            cmd_name=\$(basename "\$cmd_dir")
            cmd_file="\${cmd_dir}/\${cmd_name}.sh"
            if [[ -f "\$cmd_file" ]]; then
                echo "  \$cmd_name"
            fi
        fi
    done
    exit 1
fi

# Поиск и выполнение команды
readonly COMMAND_DIR="\${LIB_DIR}/commands/\${COMMAND}"
readonly COMMAND_FILE="\${COMMAND_DIR}/\${COMMAND}.sh"

if [[ ! -d "\$COMMAND_DIR" ]]; then
    log_error "Unknown command: \$COMMAND"
    exit 1
fi

if [[ ! -f "\$COMMAND_FILE" ]]; then
    log_error "Command file not found: \$COMMAND_FILE"
    exit 1
fi

# Передаем управление команде (убираем первый аргумент и вызываем через source)
shift
set -- "\$@"
source "\$COMMAND_FILE"
EOF

    # Делаем файл исполняемым
    if ! chmod 755 "$dev_tools_binary"; then
        log_error "Failed to make fman binary executable"
        return 1
    fi

    # Проверяем синтаксис
    if ! bash -n "$dev_tools_binary" 2>/dev/null; then
        log_error "Generated fman binary has syntax errors"
        return 1
    fi

    log_debug "Dev-tools structure built successfully"
    return 0
}

# Установка fman в систему
install_functions_manager() {
    local temp_dir="$1"
    local output_path="$2"
    local lib_dir="$3"

    log_debug "Installing fman to system"

    # Создаем целевую директорию lib
    local lib_parent_dir=$(dirname "$lib_dir")
    if ! mkdir -p "$lib_parent_dir" 2>/dev/null; then
        log_error "Failed to create parent directory: $lib_parent_dir"
        return 1
    fi

    # Удаляем старую установку если есть
    if [[ -d "$lib_dir" ]]; then
        log_debug "Removing existing installation: $lib_dir"
        if ! rm -rf "$lib_dir" 2>/dev/null; then
            log_error "Failed to remove existing installation: $lib_dir"
            return 1
        fi
    fi

    # Копируем всю структуру (lib + bin) в целевую директорию
    if ! cp -r "$temp_dir" "$lib_dir" 2>/dev/null; then
        log_error "Failed to install fman structure to: $lib_dir"
        return 1
    fi

    # Создаем родительскую директорию для симлинка
    local bin_parent_dir=$(dirname "$output_path")
    if ! mkdir -p "$bin_parent_dir" 2>/dev/null; then
        log_error "Failed to create binary directory: $bin_parent_dir"
        return 1
    fi

    # Удаляем старый симлинк если есть
    if [[ -L "$output_path" ]]; then
        log_debug "Removing existing symlink: $output_path"
        if ! rm -f "$output_path" 2>/dev/null; then
            log_error "Failed to remove existing symlink: $output_path"
            return 1
        fi
    elif [[ -e "$output_path" ]]; then
        log_error "Target path exists but is not a symlink: $output_path"
        return 1
    fi

    # Создаем симлинк на исполняемый файл
    local source_binary="$lib_dir/bin/functions-manager.sh"
    if ! ln -s "$source_binary" "$output_path" 2>/dev/null; then
        log_error "Failed to create symlink: $output_path -> $source_binary"
        return 1
    fi

    log_debug "Dev-tools installation completed"
    return 0
}

# Валидация установки
validate_installation() {
    local output_path="$1"

    log_debug "Validating installation"

    # Проверяем что файл существует и исполняемый
    if [[ ! -f "$output_path" ]]; then
        log_error "Installed binary not found: $output_path"
        return 1
    fi

    if [[ ! -x "$output_path" ]]; then
        log_error "Installed binary not executable: $output_path"
        return 1
    fi

    # Тестируем выполнение
    if ! "$output_path" >/dev/null 2>&1; then
        # Это ожидаемо - без аргументов должен показать help и завершиться с ошибкой
        log_debug "Binary execution test completed (expected error)"
    fi

    # Проверяем синтаксис
    if ! bash -n "$output_path" 2>/dev/null; then
        log_error "Installed binary has syntax errors"
        return 1
    fi

    log_debug "Installation validation completed"
    return 0
}

# Показ итоговой информации
show_installation_summary() {
    local output_path="$1"
    local lib_dir="$2"

    log_info ""
    log_success "Dev-Tools Installation Complete!"
    log_info "========================================"
    log_info "Binary installed at: $output_path"
    log_info "Libraries installed at: $lib_dir"
    log_info ""
    log_info "Usage:"
    log_info "  fman install --system --interactive"
    log_info "  fman install --module-dirs=/path/to/modules --daemon"
    log_info "  fman uninstall --all --interactive"
    log_info ""
    log_info "Run 'fman' to see available commands"
}

# Точка входа
build_dev_tools "$@"