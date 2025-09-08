# README.md

## Описание проекта

**dev-tools** - система управления bash-модулями для установки и развертывания утилит в системе. Dev-tools является утилитой-помощником для сборки и установки модулей, а не единой точкой исполнения.

## Проблема

Необходимо создать систему управления bash-модулями, которая позволяет:
1. Устанавливать модули как самостоятельные команды в систему
2. Управлять зависимостями и требованиями модулей
3. Обеспечивать модульную архитектуру самого dev-tools
4. Поддерживать системные и пользовательские модули

## Решение

Создание системы dev-tools, которая:
1. Поставляется отдельным скриптом с модульной архитектурой команд
2. Устанавливает модули как независимые команды в систему
3. Управляет зависимостями и валидацией модулей
4. Поддерживает гибкие политики обработки ошибок
5. Генерирует dispatcher'ы для команд модулей

## Установка

```shell
REPO="deep-space-projects/shell-dev-tools" BRANCH="main" BUILD_DIR="build" && wget -qO $BRANCH.zip  https://github.com/$REPO/archive/refs/heads/$BRANCH.zip  && unzip -q $BRANCH.zip -d $BUILD_DIR && bash $BUILD_DIR/shell-dev-tools-$BRANCH/functions-manager/bin/build.sh --privileged --daemon && rm -rf $BUILD_DIR && rm -f $BRANCH.zip && fman install --system --daemon
```

## Архитектура

### Структура dev-tools

```
{dev-tools-dir}/
├── bin/
│   └── dev-tools.sh                    # Основной исполняемый скрипт
├── lib/
│   ├── commands/                       # Команды dev-tools (модульная архитектура)
│   │   └── install/                    # Команда install
│   │       ├── install.sh              # Основной файл команды
│   │       ├── prerequisites/          # Проверка зависимостей
│   │       │   ├── check.sh            # Координатор prerequisites
│   │       │   └── modules/            # Модульные проверки
│   │       │       ├── 01-yq.sh        # Проверка yq
│   │       │       ├── 02-jq.sh        # Проверка jq
│   │       │       └── 03-system.sh    # Проверка системных утилит
│   │       ├── validators/             # Валидация модулей
│   │       │   ├── validation.sh       # Координатор валидации
│   │       │   └── modules/            # Модульные валидаторы
│   │       │       ├── 01-structure.sh # Структура YAML
│   │       │       ├── 02-metadata.sh  # Секция metadata
│   │       │       ├── 03-requirements.sh # Требования модуля
│   │       │       ├── 04-commands.sh  # Команды модуля
│   │       │       ├── 05-files.sh     # Существование файлов
│   │       │       └── 06-integration.sh # Интеграционные проверки
│   │       ├── generators/             # Генерация кода модулей
│   │       │   ├── generator.sh        # Координатор генерации
│   │       │   └── modules/            # Модульные генераторы
│   │       │       ├── 01-prepare.sh   # Подготовка временных директорий
│   │       │       ├── 02-dispatcher.sh # Генерация dispatcher'а
│   │       │       └── 03-library.sh   # Копирование библиотек
│   │       └── linker/                 # Линковка модулей в систему
│   │           ├── linker.sh           # Координатор линковки
│   │           └── modules/            # Модульные линкеры
│   │               ├── 01-validate.sh  # Проверка прав и конфликтов
│   │               ├── 02-install.sh   # Установка модулей
│   │               └── 03-symlink.sh   # Создание симлинков
│   ├── system/                         # Системные модули
│   │   ├── logger/
│   │   │   ├── module.yml
│   │   │   └── logger-lib.sh
│   │   ├── common/
│   │   │   ├── module.yml
│   │   │   └── common-lib.sh
│   │   ├── platform/
│   │   │   ├── module.yml
│   │   │   └── platform-lib.sh
│   │   ├── permissions/
│   │   │   ├── module.yml
│   │   │   └── permissions-lib.sh
│   │   └── modules/
│   │       ├── module.yml
│   │       └── modules-lib.sh
│   ├── core/                          # Core компоненты
│   │   ├── yaml.sh                    # Парсинг YAML через yq
│   │   ├── scanner.sh                 # Поиск и сканирование модулей
│   │   └── requirements-resolver.sh   # Разрешение зависимостей
└── templates/                         # Шаблоны для генерации
```


### Команда install

**Синтаксис:**
```shell script
dev-tools install [OPTIONS]

OPTIONS:
  --module-dirs=DIR1,DIR2    # Пользовательские директории с модулями (через запятую)
  --system                   # Установка системных модулей
  --recursive               # Рекурсивный поиск в подпапках модулей
  --verbose                 # Debug логирование
  --interactive             # Интерактивный режим (обязателен один из режимов)
  --daemon                  # Автоматический режим (обязателен один из режимов)
  --privileged              # Запрос прав администратора (сразу в начале)
  --error-policy=strict     # Политика ошибок: strict|soft|custom (default: strict)
```


### Архитектура команды install

**Функциональный подход с передачей через параметры:**

```
install.sh
    ↓ (module_dirs, system, recursive)
core/scanner.sh → modules_list[]
    ↓ (modules_list[])
prerequisites/check.sh → success/failure
    ↓ (modules_list[])
validators/validation.sh → validated_modules[]
    ↓ (validated_modules[])
generators/generator.sh → temp_dir
    ↓ (temp_dir, validated_modules[])
linker/linker.sh → success/failure
```


**Принципы передачи данных:**
1. **Никаких глобальных переменных** - все через параметры функций
2. **Возврат через stdout** - списки передаются через newline-separated format
3. **Exit codes для ошибок** - 0=success, 1=failure
4. **Source вместо exec** - все компоненты работают в одном процессе
5. **Перечитывание данных** - каждый компонент самостоятельно читает module.yml

### Логика работы install

**1. Сканирование модулей (core/scanner.sh):**
- INPUT: module_dirs, system, recursive
- OUTPUT: newline-separated список путей к директориям с module.yml
- Системные модули: hardcoded порядок logger→common→platform→modules→permissions
- Пользовательские модули: порядок передачи + лексикографический при рекурсии

**2. Prerequisites проверка:**
- INPUT: modules_list
- OUTPUT: success/failure (exit code)
- Модульная структура: 01-yq.sh, 02-jq.sh, 03-system.sh
- Каждый подмодуль загружается через source и вызывается функция

**3. Валидация модулей:**
- INPUT: modules_list
- OUTPUT: validated_modules[] (только прошедшие валидацию)
- Для каждого модуля: structure→metadata→requirements→commands→files→integration
- При ошибке валидации - поведение согласно error policy

**4. Генерация модулей:**
- INPUT: validated_modules[]
- OUTPUT: temp_dir с сгенерированными модулями
- Создает структуру: temp_dir/module_name/bin/module_name.sh + lib/module_name-lib.sh
- Генерирует dispatcher с поддержкой команд из module.yml

**5. Линковка в систему:**
- INPUT: temp_dir, validated_modules[]
- OUTPUT: success/failure
- Переносит в /usr/local/lib/module_name/
- Создает симлинки в /usr/local/bin/module_name

### Формат метаданных модуля (module.yml)

```yaml
version: 1.0.0

metadata:
  name: "docker-certificates"
  description: "Docker certificates management tools"
  version: "1.0.0"
  author: "Developer Name"

specification:
  module:
    requirements:
      environment:                # Обязательные переменные (установлены и не пусты)
        - DEV_TOOLS_DIR
      packages:
        list:
          - "openssl"
          - "curl"
          - "jq"
        overrides:               # Переопределение для дистрибутивов
          alpine: ["openssl-dev", "curl", "jq"]
          ubuntu: ["openssl", "curl", "jq"]

    commands:
      - name: "generate"
        function: "generate_certificate"
        description: "Generate SSL certificate for domain"
        usage: "generate <domain> [options]"

      - name: "install"
        function: "install_certificate"
        description: "Install certificate to system store"
        usage: "install <cert-file>"

    files:
      - "docker-certificates-lib.sh"
```


### Генерация модуля

**Результат генерации для модуля `super-star`:**
```
/tmp/dev-tools-install-$USER-$$/super-star/
├── bin/
│   └── super-star.sh          # Dispatcher с routing командами
└── lib/
    └── super-star-lib.sh      # Исходные функции модуля
```


**Генерируемый dispatcher:**
```shell script
#!/bin/bash
source "$(dirname "$0")/../lib/super-star-lib.sh"

case "$1" in
    "generate")
        shift
        generate_certificate "$@"
        ;;
    "install") 
        shift
        install_certificate "$@"
        ;;
    "help"|"")
        echo "Usage: super-star (generate|install|help)"
        echo ""
        echo "Commands:"
        echo "  generate    Generate SSL certificate for domain" 
        echo "  install     Install certificate to system store"
        ;;
    *)
        echo "Unknown command: $1"
        echo "Use 'super-star help' for available commands"
        exit 1
        ;;
esac
```


### Системные модули

**Системные модули dev-tools:**
- `logger` - система логирования (logger info, logger warning, logger_set_level, etc.)
- `common` - общие утилиты (handle_operation_error_quite, set_error_policy, detect_os, etc.)
- `platform` - системно-независимые функции (platform_user_exists, get_user_home, etc.)
- `permissions` - управление правами доступа (setup_permissions с флагами)
- `modules` - выполнение модулей (execute_module, execute_modules_in_directory)

**Двойное использование:**
1. **В dev-tools** - загружаются через source для использования функций
2. **При установке** - устанавливаются как обычные модули с dispatcher'ами

### Система обработки ошибок

**Политики ошибок (переменная EXEC_ERROR_POLICY):**
- `0="STRICT"` - любая ошибка останавливает выполнение
- `1="SOFT"` - логирует ошибку и продолжает выполнение
- `2="CUSTOM"` - настраиваемая обработка ошибок

**Функция handle_operation_error_quite:**
- Используется во всех критических операциях
- Принимает решение на основе установленной политики
- Логирует через единую систему логирования

### Принципы архитектуры

1. **Модульность команд** - каждая команда имеет собственную директорию
2. **Функциональный подход** - передача данных через параметры, не глобальные переменные
3. **Source вместо exec** - все компоненты в одном процессе для производительности
4. **Лексикографический порядок** - подмодули выполняются по именам файлов
5. **Самодостаточность модулей** - каждый модуль читает данные самостоятельно
6. **Единое логирование** - все компоненты используют system/logger
7. **Dispatcher генерация** - каждый модуль получает собственный интерфейс команд
8. **Безопасная установка** - все проверки перед мутирующими операциями

Данная архитектура обеспечивает простоту разработки, надежность выполнения, модульность системы и естественную интеграцию с командной строкой.
