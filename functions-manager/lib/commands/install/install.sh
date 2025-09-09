#!/bin/bash

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
# @return 0 при успехе, 1 при неизвестном параметре
##
parse_arguments() {
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
                shift
                ;;
            --repo=*)
                repo="${1#*=}"
                shift
                ;;
            --branch=*)
                branch="${1#*=}"
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
                return 1
                ;;
        esac
    done
    return 0
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
# @return 0 при успехе, 1-4 при различных ошибках валидации
##
validate_arguments() {
    if [[ "$interactive" == false && "$daemon" == false ]]; then
        log_error "Must specify either --interactive or --daemon"
        return 1
    fi

    if [[ "$interactive" == true && "$daemon" == true ]]; then
        log_error "Cannot specify both --interactive and --daemon"
        return 2
    fi

    if [[ "$github" == true && -z "$repo" ]]; then
        log_error "Must specify --repo when using --github"
        return 3
    fi

    if [[ "$system" == false && -z "$module_dirs" && "$github" == false ]]; then
        log_error "Must specify either --system, --module-dirs, or --github"
        return 4
    fi

    return 0
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
# @return 0 при успехе, 1 при ошибке получения прав администратора
##
initialize_environment() {
    # Установка verbose режима
    if [[ "$verbose" == true ]]; then
        logger_set_level DEBUG
    fi

    # Запрос прав администратора если нужно
    if [[ "$privileged" == true ]]; then
        if ! sudo -n true 2>/dev/null; then
            log_info "Requesting administrative privileges..."
            if ! sudo -v; then
                log_error "Administrative privileges required"
                return 1
            fi
        fi
    fi

    # Установка политики ошибок
    set_error_policy "$error_policy"
    return 0
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
# @return 0 при успехе, 1 при ошибке загрузки любого компонента
##
load_core_components() {
    log_step 1 "Loading core components"

    if ! source "${LIB_DIR}/core/scanner.sh"; then
        log_error "Failed to load scanner.sh"
        return 1
    fi

    if ! source "${LIB_DIR}/core/yaml.sh"; then
        log_error "Failed to load yaml.sh"
        return 1
    fi

    if ! source "${LIB_DIR}/core/requirements-resolver.sh"; then
        log_error "Failed to load requirements-resolver.sh"
        return 1
    fi

    log_success "Core components loaded"
    return 0
}

##
# Загружает модули из указанного GitHub репозитория
#
# Выполняет следующие действия:
# - Создает временную директорию для загрузки
# - Загружает архив репозитория с GitHub
# - Извлекает архив
# - Добавляет извлеченную директорию к списку директорий модулей
# - Настраивает очистку временных файлов
#
# @global github - флаг загрузки из GitHub
# @global repo - название репозитория (формат: owner/repo)
# @global branch - название ветки
# @global module_dirs - пути к директориям модулей (обновляется)
# @return 0 при успехе или если GitHub не используется, 1-4 при различных ошибках
##
download_github_modules() {
    if [[ "$github" == false ]]; then
        return 0
    fi

    log_step "1.5" "Downloading modules from GitHub"

    # Создаем временную директорию
    local github_temp_dir="/tmp/dev-tools-install-$(whoami)-$$/vcs/github/${repo}/${branch}"
    if ! mkdir -p "$github_temp_dir"; then
        log_error "Failed to create temporary directory: $github_temp_dir"
        return 1
    fi

    # Очистка GitHub временной директории при выходе
    trap "rm -rf '/tmp/dev-tools-install-$(whoami)-$$'" EXIT

    local zip_file="${github_temp_dir}/${branch}.zip"
    local download_url="https://github.com/${repo}/archive/refs/heads/${branch}.zip"

    log_info "Downloading from: $download_url"
    if ! wget -qO "$zip_file" "$download_url"; then
        log_error "Failed to download from GitHub repository: $repo (branch: $branch)"
        return 2
    fi

    log_info "Extracting archive..."
    if ! unzip -q "$zip_file" -d "$github_temp_dir"; then
        log_error "Failed to extract downloaded archive"
        return 3
    fi

    # Удаляем zip файл после извлечения
    rm -f "$zip_file"

    # Добавляем извлеченную директорию к module_dirs
    local extracted_dir=$(find "$github_temp_dir" -maxdepth 1 -type d -name "*${repo##*/}*" | head -1)
    if [[ -n "$extracted_dir" ]]; then
        if [[ -n "$module_dirs" ]]; then
            module_dirs="$module_dirs:$extracted_dir"
        else
            module_dirs="$extracted_dir"
        fi
    else
        log_error "Could not find extracted repository directory"
        return 4
    fi

    log_success "GitHub repository downloaded and extracted"
    return 0
}

##
# Сканирует указанные директории на наличие модулей
#
# @global module_dirs - пути к директориям модулей
# @global system - флаг системных модулей
# @global recursive - флаг рекурсивного поиска
# @return 0 при успехе, 1 при ошибке сканирования, 2 при отсутствии модулей
# @stdout список найденных модулей (по одному на строку)
##
scan_modules() {
    log_step 2 "Scanning for modules"
    local modules_list
    if ! modules_list=$(scanner_find_modules "$module_dirs" "$system" "$recursive"); then
        log_error "Failed to find modules"
        return 1
    fi

    local module_count=$(echo "$modules_list" | wc -l)
    if [[ -z "$modules_list" || "$module_count" -eq 0 ]]; then
        log_warning "No modules found for installation"
        return 2
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
    return 0
}

##
# Проверяет системные требования для установки найденных модулей
#
# @param $1 - список модулей для проверки (по одному на строку)
# @global install_dir - путь к директории команды install
# @return 0 при успехе, 1 при неудовлетворенных требованиях
##
check_prerequisites() {
    local modules_list="$1"

    log_step 3 "Checking prerequisites"
    if ! source "${install_dir}/prerequisites/check.sh"; then
        log_error "Failed to load prerequisites checker"
        return 1
    fi

    if ! prerequisites_check "$modules_list"; then
        log_error "Prerequisites check failed"
        return 1
    fi

    log_success "Prerequisites check passed"
    return 0
}

##
# Валидирует найденные модули на корректность структуры и содержимого
#
# @param $1 - список модулей для валидации (по одному на строку)
# @global install_dir - путь к директории команды install
# @return 0 при успехе, 1-2 при различных ошибках валидации
# @stdout список валидированных модулей (по одному на строку)
##
validate_modules() {
    local modules_list="$1"

    log_step 4 "Validating modules"
    if ! source "${install_dir}/validators/validation.sh"; then
        log_error "Failed to load validators"
        return 1
    fi

    local validated_modules
    if ! validated_modules=$(validators_validate "$modules_list"); then
        log_error "Module validation failed"
        return 1
    fi

    local validated_count=$(echo "$validated_modules" | wc -l)
    if [[ -z "$validated_modules" || "$validated_count" -eq 0 ]]; then
        log_error "No modules passed validation"
        return 2
    fi

    log_success "Validated $validated_count modules"
    echo "$validated_modules"
    return 0
}

##
# Генерирует конфигурационные файлы и подготавливает модули к установке
#
# @param $1 - список валидированных модулей (по одному на строку)
# @global install_dir - путь к директории команды install
# @return 0 при успехе, 1 при ошибке загрузки генератора, 2 при ошибке генерации
# @stdout путь к временной директории с сгенерированными файлами
##
generate_modules() {
    local validated_modules="$1"

    log_step 5 "Generating modules"
    if ! source "${install_dir}/generators/generator.sh"; then
        log_error "Failed to load generator"
        return 1
    fi

    local temp_dir
    if ! temp_dir=$(generators_generate "$validated_modules"); then
        log_error "Module generation failed"
        return 2
    fi

    log_success "Modules generated in: $temp_dir"

    # Очистка временной директории при выходе
    trap "rm -rf '$temp_dir'" EXIT

    echo "$temp_dir"
    return 0
}

##
# Запрашивает у пользователя подтверждение установки в интерактивном режиме
#
# @param $1 - список модулей для установки (по одному на строку)
# @global interactive - флаг интерактивного режима
# @return 0 при подтверждении или неинтерактивном режиме, 1 при отказе пользователя
##
request_installation_confirmation() {
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
        return 1
    fi

    return 0
}

##
# Выполняет финальную установку модулей в систему
#
# @param $1 - путь к временной директории с подготовленными модулями
# @param $2 - список валидированных модулей (по одному на строку)
# @global install_dir - путь к директории команды install
# @return 0 при успехе, 1-2 при различных ошибках установки
##
install_modules() {
    local temp_dir="$1"
    local validated_modules="$2"

    log_step 6 "Installing modules"
    if ! source "${install_dir}/linker/linker.sh"; then
        log_error "Failed to load linker"
        return 1
    fi

    if ! linker_install "$temp_dir" "$validated_modules"; then
        log_error "Module installation failed"
        return 2
    fi

    local validated_count=$(echo "$validated_modules" | wc -l)
    log_success "Installation completed successfully!"
    log_info "Installed $validated_count modules"

    # Показываем установленные модули
    while IFS= read -r module_path; do
        local module_name=$(basename "$module_path")
        log_info "  ✓ $module_name"
    done <<< "$validated_modules"

    return 0
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
# @return 0 при успешной установке, выход с соответствующим кодом ошибки при неудаче
##
install() {
    # Инициализация переменных со значениями по умолчанию
    local module_dirs=""
    local system=false
    local recursive=false
    local verbose=false
    local interactive=false
    local daemon=false
    local privileged=false
    local error_policy="strict"
    local github=false
    local repo=""
    local branch="main"

    # Парсинг и валидация аргументов
    if ! parse_arguments "$@"; then
        log_error "Failed to parse arguments"
        return 1
    fi

    if ! validate_arguments; then
        log_error "Arguments validation failed"
        return 2
    fi

    # Инициализация среды
    if ! initialize_environment; then
        log_error "Environment initialization failed"
        return 3
    fi

    log_header "Starting Module Installation"

    # Определяем путь к install команде
    local install_dir="${LIB_DIR}/commands/install"

    # Загрузка и подготовка
    if ! load_core_components; then
        log_error "Failed to load core components"
        return 4
    fi

    if ! download_github_modules; then
        log_error "Failed to download GitHub modules"
        return 5
    fi

    # Поиск и обработка модулей
    local modules_list
    if ! modules_list=$(scan_modules); then
        log_error "Failed to scan modules"
        return 6
    fi

    if ! check_prerequisites "$modules_list"; then
        log_error "Prerequisites check failed"
        return 7
    fi

    local validated_modules
    if ! validated_modules=$(validate_modules "$modules_list"); then
        log_error "Module validation failed"
        return 8
    fi

    local temp_dir
    if ! temp_dir=$(generate_modules "$validated_modules"); then
        log_error "Module generation failed"
        return 9
    fi

    # Подтверждение и установка
    if ! request_installation_confirmation "$validated_modules"; then
        log_info "Installation cancelled"
        return 0  # Не ошибка, пользователь отменил
    fi

    if ! install_modules "$temp_dir" "$validated_modules"; then
        log_error "Module installation failed"
        return 10
    fi

    log_success "Installation process completed successfully"
    return 0
}

# Запуск установки с переданными аргументами
install "$@"