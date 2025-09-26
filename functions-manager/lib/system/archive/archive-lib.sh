#!/bin/bash
# Распаковать в директорию и удалить zip файл

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Загрузка нужной реализации модуля в зависимости от режима выполнения
__load_driver__() {
  local entrypoint_path="$SCRIPT_DIR"
  local driver_name="$1"

  if [[ -z "$driver_name" ]]; then
    log_error "Driver name is required for load_driver function"
    return 1
  fi

  local impl_file="$entrypoint_path/drivers/$driver_name-driver.sh"
  log_debug "Loading driver for archy: $(basename "$impl_file")"
  source "$impl_file"
}

__get_archive_type__() {
  local filename="$1"
  local basename_file=$(basename "$filename")
      
  # Сначала проверяем известные составные расширения
  case "$basename_file" in
    *.tar.gz|*.tar.bz2|*.tar.xz|*.tar.Z|*.tar.lz|*.tar.lzma)
      echo "tar"
      ;;
    *.zip)
      echo "zip"
      ;;         
    *)
      log_warning "unknow or unsupported archive extension: ${basename_file##*.}"
      return 1
      ;;
  esac
}


unarchive_file() {
  temp_dir=$(mktemp -d)

  # Функция для очистки
  cleanup() {
    log_info "Очищаем временные файлы..."
    rm -rf "$temp_dir"
  }

  # Устанавливаем trap на EXIT и сигналы
  trap cleanup EXIT INT TERM

  local strip=0
  local output_dir=$(pwd)
  local archive=""
  local remove_archive="no"

  #save args to forward it onto driver
  local args="$@"

  while [ $# -gt 0 ]; do
    case $1 in
      --strip=*)
        strip=${1#*=}
        shift
        ;;
      --rm)
        remove_archive="yes"
        shift
        ;;
      -o=*|--output-dir=*)
        output_dir=${1#*=}
        shift
        ;;
      -*)
        #skip unknown flags
        log_debug "skip unknown flag: $1"
        shift
        ;;
      *)
        archive="$1"
        shift
        break
        ;;
    esac
  done

  if [[ -z "$archive" ]]; then
    log_error "No archive file specified"
    return 1
  fi

  if [[ ! -f $archive ]]; then
    log_error "archive {$archive} not found!"
    return 1
  fi

  mkdir -p $output_dir

  if [[ ! -d $output_dir ]]; then
    log_error "output dir {$output_dir} not found or not directory!"
    return 1
  fi

  if ! archive_type=$(__get_archive_type__ $archive); then
    log_error "unknown archive {$archive} extension"
    return 1
  fi

  if ! __load_driver__ $archive_type; then
    log_error "driver not found for {$archive_type} extension"
    return 1
  fi

  if ! driver_unarchive "$temp_dir" "$archive"; then
    log_error "unarchive {$archive} failed"
    return 1
  fi

  # после того как разархивация произошла успешно, мы работаем с уровнями
  local source_dir="$temp_dir"
  log_info "Strip directories {$source_dir} onto depth of $strip"
  # Находим $strip вложенную директорию
  source_dir=$(find "$temp_dir" -mindepth $strip -maxdepth $strip -type d | head -1)

  if [[ -z "$source_dir" ]]; then
      log_error "Cannot find directory at strip level $strip"
      return 1
  fi

  log_info "Final directory: $source_dir"
  # Копируем содержимое в текущую директорию
  cp -r ${source_dir}/* ${output_dir}/

  if [[ $? -ne 0 ]]; then
    log_error "copy unzip archive {$archive} failed!"
    return 1
  fi

  # если архив не размечен к удалению, то копируем его в output директорию
  if [[ "$remove_archive" =~ ^(yes|true)$ ]]; then
    rm "$archive"
  fi

  log_success "Archive {$archive} successfully unzip and moved to target directory $output_dir with strip $strip directories toward"
  return 0
}

archive_file() {
  return 0
}
