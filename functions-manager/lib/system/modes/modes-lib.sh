#!/bin/bash
# ============================================================================
# Common Functions for Container Tools
# Provides platform detection, basic utilities and common functions
# ============================================================================

readonly EXEC_MODE_STANDARD="STANDARD"
readonly EXEC_MODE_SKIP_ALL="SKIP_ALL"
readonly EXEC_MODE_INIT_ONLY="INIT_ONLY"
readonly EXEC_MODE_DEBUG="DEBUG"
readonly EXEC_MODE_DRY_RUN="DRY_RUN"

declare -A EXEC_MODES=(
    [0]="${EXEC_MODE_STANDARD}"      # Полный запуск
    [1]="${EXEC_MODE_SKIP_ALL}"      # Пропустить все, только exec команду
    [2]="${EXEC_MODE_INIT_ONLY}"     # Только инициализация, без основной команды
    [3]="${EXEC_MODE_DEBUG}"         # Режим отладки с детальными логами
    [4]="${EXEC_MODE_DRY_RUN}"       # Показать что будет выполнено, но не выполнять
)

# Получение текущего режима выполнения как строки
get_current_exec_mode() {
    local mode="$EXEC_MODE"
    echo $(get_exec_mode_name_by_code $mode)
}

get_exec_mode_name_by_code() {
    local mode="$1"

    # Проверка на пустоту
    if [[ -z "$mode" ]]; then
        echo "ERROR: Mode code is empty" >&2
        return 1
    fi

    # Проверка что это число (опционально, но полезно)
    if ! [[ "$mode" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Mode code must be a number: '$mode'" >&2
        return 1
    fi

    # Проверка существования ключа в массиве
    if [[ -z "${EXEC_MODES[$mode]+_}" ]]; then
        echo "ERROR: Unknown mode code: '$mode'" >&2
        return 1
    fi

    # Возвращаем значение
    echo "${EXEC_MODES[$mode]}"
    return 0
}

set_exec_mode() {
    local new_mode="$1"

    # Проверка на пустоту
    if [[ -z "$new_mode" ]]; then
        echo "Error: Execution mode is required" >&2
        return 1
    fi

    local resolved_mode=""

    # Если передано число - используем как есть
    if [[ "$new_mode" =~ ^[0-9]+$ ]]; then
        resolved_mode="$new_mode"
    else
        # Если передана строка - пытаемся найти соответствующий числовой код
        resolved_mode=$(__resolve_exec_mode_name_to_code "$new_mode")
        if [[ $? -ne 0 ]]; then
            echo "Error: Unknown mode name: '$new_mode'" >&2
            return 1
        fi
    fi

    # Проверяем что resolved_mode валидный
    if [[ -z "${EXEC_MODES[$resolved_mode]+_}" ]]; then
        echo "Error: Invalid execution mode: $resolved_mode" >&2
        return 1
    fi

    # Устанавливаем переменную
    set_env_var_quite "EXEC_MODE" "$resolved_mode" "subprocess"
    return $?
}

# Вспомогательная функция для резолвинга имени политики в код
__resolve_exec_mode_name_to_code() {
    local exec_mode="$1"

    # Ищем exec_mode в значениях ERROR_POLICY_NAMES
    for code in "${!EXEC_MODES[@]}"; do
        if [[ "${EXEC_MODES[$code]}" == "$exec_mode" ]]; then
            echo "$code"
            return 0
        fi
    done

    # Если не нашли - пробуем case-insensitive поиск
    for code in "${!EXEC_MODES[@]}"; do
        if [[ "${EXEC_MODES[$code],,}" == "${exec_mode,,}" ]]; then
            echo "$code"
            return 0
        fi
    done

    return 1
}

readonly ERROR_POLICY_STRICT="STRICT"
readonly ERROR_POLICY_SOFT="SOFT"
readonly ERROR_POLICY_CUSTOM="CUSTOM"

declare -A ERROR_POLICY_NAMES=(
    [0]="${ERROR_POLICY_STRICT}"        # Любая ошибка = остановка
    [1]="${ERROR_POLICY_SOFT}"          # Логируем ошибку и продолжаем
    [2]="${ERROR_POLICY_CUSTOM}"        # Настраиваемая политика
)

# Получение текущей политики ошибок как строки
get_current_error_policy() {
    local policy="${ERROR_POLICY:-0}"
    echo $(get_error_policy_name_by_code $policy)
}

get_error_policy_name_by_code() {
    local policy="$1"

    # Проверка на пустоту
    if [[ -z "$policy" ]]; then
        echo "ERROR: Policy code is empty" >&2
        return 1
    fi

    # Проверка что это число
    if ! [[ "$policy" =~ ^[0-9]+$ ]]; then
        echo "ERROR: Policy code must be a number: '$policy'" >&2
        return 1
    fi

    # Проверка существования ключа в массиве
    if [[ -z "${ERROR_POLICY_NAMES[$policy]+_}" ]]; then
        echo "ERROR: Unknown policy code: '$policy'" >&2
        return 1
    fi

    # Возвращаем значение
    echo "${ERROR_POLICY_NAMES[$policy]}"
    return 0
}

set_error_policy() {
    local new_policy="$1"

    # Проверка на пустоту
    if [[ -z "$new_policy" ]]; then
        echo "Error: Error policy is required" >&2
        return 1
    fi

    local resolved_policy=""

    # Если передано число - используем как есть
    if [[ "$new_policy" =~ ^[0-9]+$ ]]; then
        resolved_policy="$new_policy"
    else
        # Если передана строка - пытаемся найти соответствующий числовой код
        resolved_policy=$(__resolve_error_policy_name_to_code "$new_policy")
        if [[ $? -ne 0 ]]; then
            echo "Error: Unknown policy name: '$new_policy'" >&2
            return 1
        fi
    fi

    # Проверяем что resolved_policy валидный
    if [[ -z "${ERROR_POLICY_NAMES[$resolved_policy]+_}" ]]; then
        echo "Error: Invalid error policy: $resolved_policy" >&2
        return 1
    fi

    # Устанавливаем переменную
    set_env_var_quite "ERROR_POLICY" "$resolved_policy" "subprocess"
    return $?
}

# Вспомогательная функция для резолвинга имени политики в код
__resolve_error_policy_name_to_code() {
    local exec_mode="$1"

    # Ищем exec_mode в значениях ERROR_POLICY_NAMES
    for code in "${!ERROR_POLICY_NAMES[@]}"; do
        if [[ "${ERROR_POLICY_NAMES[$code]}" == "$exec_mode" ]]; then
            echo "$code"
            return 0
        fi
    done

    # Если не нашли - пробуем case-insensitive поиск
    for code in "${!ERROR_POLICY_NAMES[@]}"; do
        if [[ "${ERROR_POLICY_NAMES[$code],,}" == "${exec_mode,,}" ]]; then
            echo "$code"
            return 0
        fi
    done

    return 1
}

export EXEC_MODE_STANDARD EXEC_MODE_SKIP_ALL EXEC_MODE_INIT_ONLY EXEC_MODE_DEBUG EXEC_MODE_DRY_RUN
export ERROR_POLICY_STRICT ERROR_POLICY_SOFT ERROR_POLICY_CUSTOM
export -f get_current_exec_mode get_exec_mode_name_by_code set_exec_mode
export -f get_current_error_policy get_error_policy_name_by_code set_error_policy
