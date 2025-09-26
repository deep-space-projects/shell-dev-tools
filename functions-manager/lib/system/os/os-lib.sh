#!/bin/bash
# ============================================================================
# OS Family Constants
# Константы для определения семейств операционных систем
# ============================================================================

# OS Family Constants (enum-like)
readonly OS_DEBIAN="debian"
readonly OS_RHEL="rhel"
readonly OS_ALPINE="alpine"
readonly OS_UNKNOWN="unknown"

# Массив всех поддерживаемых OS
readonly OS_SUPPORTED=("$OS_DEBIAN" "$OS_RHEL" "$OS_ALPINE")

# Функция для валидации OS family
is_supported_os() {
    local fail_on_unsupported=1
    local os_to_check=""

    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fail)
                fail_on_unsupported=0
                shift
                ;;
            *)
                # Все оставшиеся аргументы - команда/функция и её параметры
                os_to_check=("$@")
                break
                ;;
        esac
    done

    local os
    for os in "${OS_SUPPORTED[@]}"; do
        if [[ "$os" == "$os_to_check" ]]; then
            return 0
        fi
    done

    if [[ $fail_on_unsupported == 0 ]]; then
        exit 1
    fi

    return 1
}

# Функция для получения всех поддерживаемых OS как строку
get_supported_os_list() {
    printf '%s\n' "${OS_SUPPORTED[@]}"
}

# Определяем тип операционной системы
detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${ID:-unknown}"
    elif command -v lsb_release >/dev/null 2>&1; then
        lsb_release -si | tr '[:upper:]' '[:lower:]'
    elif [[ -f /etc/redhat-release ]]; then
        echo "${OS_RHEL}"
    elif [[ -f /etc/debian_version ]]; then
        echo "${OS_DEBIAN}"
    else
        echo "unknown"
    fi
}

# Определяем семейство ОС
detect_os_family() {
    local os=$(detect_os)

    case "$os" in
        ubuntu|debian|linuxmint)
            echo "${OS_DEBIAN}"
            ;;
        rhel|centos|fedora|ol|rocky|almalinux)
            echo "${OS_RHEL}"
            ;;
        alpine)
            echo "${OS_ALPINE}"
            ;;
        *)
            echo "${OS_UNKNOWN}"
            ;;
    esac
}

# Проверяем, является ли система минимальной (BusyBox)
is_minimal_system() {
    # Проверяем наличие BusyBox
    if command -v busybox >/dev/null 2>&1; then
        return 0
    fi

    # Проверяем признаки минимальной системы
    if [[ ! -d /usr/bin ]] || [[ $(ls /usr/bin | wc -l) -lt 10 ]]; then
        return 0
    fi

    return 1
}

# Функция для определения подходящей bin директории
get_system_bin_dir() {
    local os_family=$(detect_os_family)

    case "$os_family" in
        "$OS_ALPINE")
            # В Alpine/BusyBox системах используем /usr/bin
            echo "/usr/bin"
            ;;
        "$OS_DEBIAN"|"$OS_RHEL")
            # В полноценных системах используем /usr/local/bin
            echo "/usr/local/bin"
            ;;
        "$OS_UNKNOWN")
            # Для неизвестных систем проверяем минимальность
            if is_minimal_system; then
                echo "/usr/bin"
            else
                echo "/usr/local/bin"
            fi
            ;;
        *)
            # По умолчанию используем /usr/local/bin
            echo "/usr/local/bin"
            ;;
    esac
}


# Экспорт констант
export OS_DEBIAN OS_RHEL OS_ALPINE OS_UNKNOWN
export -a OS_SUPPORTED
export -f is_supported_os get_supported_os_list is_minimal_system
export -f get_system_bin_dir