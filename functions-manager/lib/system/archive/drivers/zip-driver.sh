#!/bin/bash

driver_unarchive() {
  local target_dir=$1
  local archive=$2
  unzip $archive -d "$target_dir"
  return $?
}