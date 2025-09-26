#!/bin/bash

# Глобальные переменные
module_dirs=""
system=false
recursive=false
verbose=false
interactive=false
daemon=false
privileged=false
error_policy="strict"
install_mode="module"
github=false
repo=""
release=""
branch="main"
entrypoint=""

##
# Парсит аргументы командной строки и устанавливает соответствующие переменные
#
# @param $@ - все переданные аргументы командной строки
# @global module_dirs - строка с путями к директориям модулей (разделенные :)
# @global system - флаг использования системных модулей
# @global recursive - флаг рекурсивного поиска модулей
# @global verbose - флаг детального вывода
# @global interactive - флаг интерактивного режима
# @global daemon - флаг daemon режима
# @global privileged - флаг запроса административных прав
# @global error_policy - политика обработки ошибок
# @global github - флаг загрузки модулей из GitHub
# @global repo - название GitHub репозитория
# @global branch - название ветки GitHub репозитория
# @return 0 при успехе, выход с кодом 1 при неизвестном параметре
##
__parse_arguments() {
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
            --github)
                github=true
                daemon=true
                recursive=true
                shift
                ;;
            --repo=*)
                repo="${1#*=}"
                shift
                ;;
            --release=*|--tag=*)
                release="${1#*=}"
                shift
                ;;
            --branch=*)
                branch="${1#*=}"
                shift
                ;;
            --entrypoint=*)
                entrypoint="${1#*=}"
                shift
                ;;
            --mode=*)
                install_mode="${1#*=}"
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
}

##
# Проверяет корректность переданных аргументов и их комбинаций
#
# Валидирует следующие правила:
# - Должен быть указан либо --interactive, либо --daemon (но не оба)
# - При использовании --github обязательно указание --repo
# - Должен быть указан один из: --system, --module-dirs или --github
#
# @global interactive - флаг интерактивного режима
# @global daemon - флаг daemon режима
# @global github - флаг загрузки из GitHub
# @global repo - название репозитория
# @global system - флаг системных модулей
# @global module_dirs - пути к директориям модулей
# @return выход с кодом 1 при ошибке валидации
##
__validate_arguments() {
    if [[ "$interactive" == false && "$daemon" == false ]]; then
        log_error "Must specify either --interactive or --daemon"
        exit 1
    fi

    if [[ "$interactive" == true && "$daemon" == true ]]; then
        log_error "Cannot specify both --interactive and --daemon"
        exit 1
    fi

    if [[ "$github" == true && -z "$repo" ]]; then
        log_error "Must specify --repo when using --github"
        exit 1
    fi

    if [[ "$system" == false && -z "$module_dirs" && "$github" == false ]]; then
        log_error "Must specify either --system, --module-dirs, or --github"
        exit 1
    fi
}

##
# Инициализирует среду выполнения на основе переданных параметров
#
# Выполняет следующие действия:
# - Устанавливает уровень логирования при включенном verbose режиме
# - Запрашивает административные права при необходимости
# - Устанавливает политику обработки ошибок
#
# @global verbose - флаг детального вывода
# @global privileged - флаг административных прав
# @global error_policy - политика обработки ошибок
# @return выход с кодом 1 при ошибке получения прав администратора
##
__initialize_environment() {
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
}

##
# Загружает основные компоненты системы, необходимые для работы
#
# Подключает следующие модули:
# - scanner.sh - для поиска модулей
# - yaml.sh - для работы с YAML файлами
# - requirements-resolver.sh - для разрешения зависимостей
#
# @global LIB_DIR - путь к директории библиотек
# @return выход с кодом 1 при ошибке загрузки любого компонента
##
__load_core_components() {
    source "${LIB_DIR}/core/scanner.sh"
    source "${LIB_DIR}/core/yaml.sh"
    source "${LIB_DIR}/core/requirements-resolver.sh"
    log_success "Core components loaded"
}

##
# Загружает модули из указанного GitHub репозитория
#
# Выполняет следующие действия:
# - Создает временную директорию для загрузки
# - Загружает архив репозитория с GitHub
# - Извлекает архив
# - Добавляет извлеченную директорию к списку директорий модулей
#
# @global github - флаг загрузки из GitHub
# @global repo - название репозитория (формат: owner/repo)
# @global release - название релиза
# @global branch - название ветки
# @global module_dirs - пути к директориям модулей (обновляется)
# @return выход с кодом 1 при различных ошибках
##
__download_github_modules() {
    # Создаем временную директорию
    local github_temp_dir="/tmp/dev-tools-install-$(whoami)-$$/vcs/github/${repo}"
    mkdir -p "$github_temp_dir"

    local short_repo_name=$(basename "$repo")

    local zip_file
    local download_url
    local extracting_point="$github_temp_dir/$entrypoint"

    if [[ ! -z "$release" ]]; then
      download_url="https://github.com/${repo}/archive/refs/tags/${release}.zip"
      zip_file="${github_temp_dir}/${release}.zip"
    elif [[ ! -z "$branch" ]]; then
      download_url="https://github.com/${repo}/archive/refs/heads/${branch}.zip"
      zip_file="${github_temp_dir}/${branch}.zip"
    else
      log_error "Failed to get downloaded url"
      exit 1
    fi

    log_info "Downloading from: $download_url"
    if ! wget -qO "$zip_file" "$download_url"; then
        log_error "Failed to download from GitHub repository: $repo (url: $download_url)"
        exit 1
    fi

    log_info "Extracting archive..."
    if ! unarchive_file --strip=1 --rm --output-dir="$github_temp_dir" "$zip_file"; then
        log_error "Failed to extract downloaded archive"
        exit 1
    fi

    log_info "GitHub Entrypoint: $extracting_point"
    tree $github_temp_dir

    # Добавляем извлеченную директорию к module_dirs
    if [[ -n "$extracting_point" ]]; then
        if [[ -n "$module_dirs" ]]; then
            module_dirs="$module_dirs:$extracting_point"
        else
            module_dirs="$extracting_point"
        fi
    else
        log_error "Could not find extracted repository directory"
        exit 1
    fi

    log_success "GitHub repository downloaded and extracted"
}

##
# Сканирует указанные директории на наличие модулей
#
# @global module_dirs - пути к директориям модулей
# @global system - флаг системных модулей
# @global recursive - флаг рекурсивного поиска
# @return выход с кодом 1 при ошибке сканирования, 0 при отсутствии модулей
# @stdout список найденных модулей (по одному на строку)
##
__scan_modules() {
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

    echo "$modules_list"
}

##
# Проверяет системные требования для установки найденных модулей
#
# @param $1 - список модулей для проверки (по одному на строку)
# @global install_dir - путь к директории команды install
# @return выход с кодом 1 при неудовлетворенных требованиях
##
__check_prerequisites() {
    local modules_list="$1"

    source "${install_dir}/module/prerequisites/check.sh"
    if ! prerequisites_check "$modules_list"; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    log_success "Prerequisites check passed"
}

##
# Валидирует найденные модули на корректность структуры и содержимого
#
# @param $1 - список модулей для валидации (по одному на строку)
# @global install_dir - путь к директории команды install
# @return выход с кодом 1 при ошибке валидации
# @stdout список валидированных модулей (по одному на строку)
##
__validate_modules() {
    local modules_list="$1"

    source "${install_dir}/module/validators/validation.sh"
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

    echo "$validated_modules"
}

##
# Генерирует конфигурационные файлы и подготавливает модули к установке
#
# @param $1 - список валидированных модулей (по одному на строку)
# @global install_dir - путь к директории команды install
# @return выход с кодом 1 при ошибке генерации
# @stdout путь к временной директории с сгенерированными файлами
##
__generate_modules() {
    local validated_modules="$1"

    source "${install_dir}/module/generators/generator.sh"
    local temp_dir
    if ! temp_dir=$(generate_modules "$validated_modules"); then
        log_error "Module generation failed"
        exit 1
    fi
    log_success "Modules generated in: $temp_dir"

    echo "$temp_dir"
}

##
# Запрашивает у пользователя подтверждение установки в интерактивном режиме
#
# @param $1 - список модулей для установки (по одному на строку)
# @global interactive - флаг интерактивного режима
# @return выход с кодом 0 при отказе пользователя
##
__request_installation_confirmation() {
    local validated_modules="$1"

    if [[ "$interactive" == false ]]; then
        return 0
    fi

    local validated_count=$(echo "$validated_modules" | wc -l)
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
}

##
# Выполняет финальную установку модулей в систему
#
# @param $1 - путь к временной директории с подготовленными модулями
# @param $2 - список валидированных модулей (по одному на строку)
# @global install_dir - путь к директории команды install
# @return выход с кодом 1 при ошибке установки
##
__install_modules() {
    local temp_dir="$1"
    local validated_modules="$2"

    source "${install_dir}/module/linker/linker.sh"
    if ! linker_install "$temp_dir" "$validated_modules"; then
        log_error "Module installation failed"
        exit 1
    fi

    local validated_count=$(echo "$validated_modules" | wc -l)
    log_success "Installation completed successfully!"
    log_info "Installed $validated_count modules"

    # Показываем установленные модули
    while IFS= read -r module_path; do
        local module_name=$(basename "$module_path")
        log_info "  ✓ $module_name"
    done <<< "$validated_modules"
}

##
# Главная функция установки модулей
#
# Координирует весь процесс установки, включая:
# - Парсинг и валидацию аргументов
# - Инициализацию среды
# - Загрузку компонентов
# - Поиск и валидацию модулей
# - Генерацию и установку
#
# @param $@ - аргументы командной строки
# @return выход с кодом ошибки при неудаче
##
install() {
    # Парсинг и валидация аргументов
    __parse_arguments "$@"
    __validate_arguments
    __initialize_environment

    case $install_mode in
        module)
            __install_module__ "$@"
            return $?
            ;;
        binaries)
            __install_binaries__ "$@"
            return $?
            ;;
        *)
            tlog error "Unknow install mode: $install_mode"
            return 1
    esac
}

__install_module__() {
    log_header "Starting Module Installation"

    # Определяем путь к install команде
    local install_dir="${LIB_DIR}/commands/install"

    # Загрузка и подготовка
    log_step 1 "Loading core components"
    __load_core_components

    log_step 2 "Downloading external modules"
    if [[ "$github" == true ]]; then
        log_info "Downloading external modules from GitHub"
        __download_github_modules
    fi

    # Поиск и обработка модулей
    log_step 3 "Scanning for modules"
    local modules_list
    modules_list=$(__scan_modules)

    log_step 4 "Checking prerequisites"
    __check_prerequisites "$modules_list"

    log_step 5 "Validating modules"
    local validated_modules
    validated_modules=$(__validate_modules "$modules_list")

    # Создание и Очистка временной директории при выходе
    log_step 6 "Generating modules"
    local temp_dir
    temp_dir=$(__generate_modules "$validated_modules")
    trap "rm -rf '$temp_dir'" EXIT

    # Подтверждение и установка
    __request_installation_confirmation "$validated_modules"

    log_step 7 "Installing modules"
    __install_modules "$temp_dir" "$validated_modules"
}

__install_binaries__() {
    log_header "Starting Binaries Installation"
    log_error "Unsupported install type"
    exit 10
}

# Запуск установки с переданными аргументами
install "$@"