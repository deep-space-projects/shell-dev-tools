#!/bin/bash
set -euo pipefail

# Универсальный скрипт настройки пользователя в контейнере
# Поддерживает: Debian, Ubuntu, RHEL, CentOS, Alpine, BusyBox

CONTAINER_USER="${1:-}"
CONTAINER_UID="${2:-}"
CONTAINER_GROUP="${3:-}"
CONTAINER_GID="${4:-}"

# Проверяем что все аргументы переданы
if [[ -z "$CONTAINER_USER" || -z "$CONTAINER_UID" || -z "$CONTAINER_GROUP" || -z "$CONTAINER_GID" ]]; then
    echo "ERROR: All arguments must be provided: <user> <uid> <group> <gid>" >&2
    echo "Received: user='$CONTAINER_USER', uid='$CONTAINER_UID', group='$CONTAINER_GROUP', gid='$CONTAINER_GID'" >&2
    exit 1
fi

echo "Настройка пользователя: $CONTAINER_USER ($CONTAINER_UID:$CONTAINER_GID)"

# Определяем тип системы
if command -v getent >/dev/null 2>&1; then
    # Система с getent (Debian, Ubuntu, RHEL, CentOS)
    USE_GETENT=true
    echo "Обнаружена система с getent"
else
    # Минимальные системы (Alpine, BusyBox)
    USE_GETENT=false
    echo "Обнаружена минимальная система без getent"
fi

# Функция проверки существования группы
group_exists() {
    if [[ "$USE_GETENT" == "true" ]]; then
        getent group "$1" >/dev/null 2>&1
    else
        grep -q "^$1:" /etc/group 2>/dev/null
    fi
}

# Функция проверки существования пользователя
user_exists() {
    if [[ "$USE_GETENT" == "true" ]]; then
        getent passwd "$1" >/dev/null 2>&1
    else
        grep -q "^$1:" /etc/passwd 2>/dev/null
    fi
}

# Создаем группу если не существует
if ! group_exists "${CONTAINER_GROUP}"; then
    echo "Создание группы: ${CONTAINER_GROUP} (${CONTAINER_GID})"
    if command -v groupadd >/dev/null 2>&1; then
        groupadd -g "${CONTAINER_GID}" "${CONTAINER_GROUP}"
    elif command -v addgroup >/dev/null 2>&1; then
        addgroup -g "${CONTAINER_GID}" "${CONTAINER_GROUP}"
    else
        echo "ERROR: Не найдена команда для создания группы (groupadd/addgroup)" >&2
        exit 1
    fi
else
    echo "Группа ${CONTAINER_GROUP} уже существует"
fi

# Работаем с пользователем
if user_exists "${CONTAINER_USER}"; then
    echo "Пользователь ${CONTAINER_USER} существует"

    # Получаем старый UID
    OLD_UID=$(id -u "${CONTAINER_USER}" 2>/dev/null || echo "")

    # Пытаемся изменить пользователя
    if command -v usermod >/dev/null 2>&1; then
        echo "Обновляем пользователя через usermod"
        usermod -u "${CONTAINER_UID}" -g "${CONTAINER_GROUP}" "${CONTAINER_USER}"

        # Исправляем права на файлы если UID изменился
        if [[ -n "$OLD_UID" && "$OLD_UID" != "$CONTAINER_UID" ]]; then
            echo "UID изменен с ${OLD_UID} на ${CONTAINER_UID} - исправляем права"
            find /home -user "${OLD_UID}" -exec chown "${CONTAINER_UID}:${CONTAINER_GID}" {} + 2>/dev/null || true
            find /opt -user "${OLD_UID}" -exec chown "${CONTAINER_UID}:${CONTAINER_GID}" {} + 2>/dev/null || true
            find /var -user "${OLD_UID}" -exec chown "${CONTAINER_UID}:${CONTAINER_GID}" {} + 2>/dev/null || true
        fi
    else
        echo "WARNING: usermod недоступен, пропускаем изменение UID пользователя ${CONTAINER_USER}"
        echo "Убедитесь что UID пользователя в образе совпадает с требуемым: ${CONTAINER_UID}"
    fi
else
    echo "Создание нового пользователя: ${CONTAINER_USER}"
    if command -v useradd >/dev/null 2>&1; then
        useradd -u "${CONTAINER_UID}" -g "${CONTAINER_GROUP}" -m -s /bin/bash "${CONTAINER_USER}" 2>/dev/null || \
        useradd -u "${CONTAINER_UID}" -g "${CONTAINER_GROUP}" "${CONTAINER_USER}"
    elif command -v adduser >/dev/null 2>&1; then
        # BusyBox adduser имеет другой синтаксис
        adduser -u "${CONTAINER_UID}" -G "${CONTAINER_GROUP}" -D -s /bin/bash "${CONTAINER_USER}"
    else
        echo "ERROR: Не найдена команда для создания пользователя (useradd/adduser)" >&2
        exit 1
    fi
fi

# Проверяем финальный результат
if user_exists "${CONTAINER_USER}"; then
    echo "Пользователь настроен: $(id ${CONTAINER_USER} 2>/dev/null || echo 'Информация недоступна')"
else
    echo "ERROR: Не удалось создать/настроить пользователя ${CONTAINER_USER}" >&2
    exit 1
fi

# ============================================================================
# НАСТРОЙКА CONTAINER-TOOLS
# ============================================================================

echo ""
echo "Настройка container-tools..."

# Получаем путь к container-tools (должен быть установлен в окружении)
CONTAINER_TOOLS="${CONTAINER_TOOLS:-/opt/container-tools}"

if [[ ! -d "$CONTAINER_TOOLS" ]]; then
    echo "WARNING: CONTAINER_TOOLS directory not found: $CONTAINER_TOOLS"
    echo "Пропускаем настройку container-tools"
else
    echo "Настройка прав доступа для: $CONTAINER_TOOLS"

    # Делаем все .sh файлы исполняемыми
    find "$CONTAINER_TOOLS" -name "*.sh" -type f -exec chmod +x {} \;

    # Устанавливаем права владения (если запущено под root)
    if [[ $EUID -eq 0 ]]; then
        chown -R "${CONTAINER_UID}:${CONTAINER_GID}" "$CONTAINER_TOOLS"
        echo "Установлены права владения: ${CONTAINER_USER}:${CONTAINER_GROUP}"
    else
        echo "WARNING: Не запущено под root, пропускаем установку владельца"
    fi

    # Проверяем ключевые файлы
    key_files=(
        "$CONTAINER_TOOLS/entrypoint/universal-entrypoint.sh"
        "$CONTAINER_TOOLS/core/logger.sh"
        "$CONTAINER_TOOLS/core/common.sh"
        "$CONTAINER_TOOLS/core/platform.sh"
        "$CONTAINER_TOOLS/core/permissions.sh"
        "$CONTAINER_TOOLS/core/process.sh"
    )

    missing_files=()
    for file in "${key_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        elif [[ ! -x "$file" ]]; then
            echo "WARNING: File not executable: $file"
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo "ERROR: Missing container-tools files:"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        exit 1
    fi

    echo "✅ Container-tools настроены успешно"
fi

echo ""
echo "Настройка пользователя завершена"