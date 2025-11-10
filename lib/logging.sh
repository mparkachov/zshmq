#!/usr/bin/env sh
# shellcheck shell=sh

ZSHMQ_LOG_LEVEL=${ZSHMQ_LOG_LEVEL:-INFO}

zshmq_log_level_value() {
  level=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
  case $level in
    TRACE) printf '%s\n' 0 ;;
    DEBUG) printf '%s\n' 10 ;;
    INFO) printf '%s\n' 20 ;;
    WARN) printf '%s\n' 30 ;;
    ERROR) printf '%s\n' 40 ;;
    FATAL) printf '%s\n' 50 ;;
    *) printf '%s\n' 20 ;;
  esac
}

zshmq_log_threshold_value() {
  zshmq_log_level_value "${ZSHMQ_LOG_LEVEL:-INFO}"
}

zshmq_log_should_emit() {
  level_value=$(zshmq_log_level_value "$1")
  threshold=$(zshmq_log_threshold_value)
  [ "$level_value" -ge "$threshold" ]
}

zshmq_log_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

zshmq_log() {
  level=${1:-INFO}
  shift || :
  normalized=$(printf '%s' "$level" | tr '[:lower:]' '[:upper:]')
  zshmq_log_should_emit "$normalized" || return 0

    if [ $# -gt 0 ]; then
      format=$1
      shift || :
      if [ $# -gt 0 ]; then
        # shellcheck disable=SC2059
        message=$(printf "$format" "$@")
      else
        message=$format
      fi
    else
      message=
    fi

  timestamp=$(zshmq_log_timestamp)
  log_output=${ZSHMQ_LOG_OUTPUT:-/dev/stderr}
  printf '%s [%s] %s\n' "$timestamp" "$normalized" "$message" >> "$log_output"
}

zshmq_log_trace() {
  zshmq_log TRACE "$@"
}

zshmq_log_debug() {
  zshmq_log DEBUG "$@"
}

zshmq_log_info() {
  zshmq_log INFO "$@"
}

zshmq_log_warn() {
  zshmq_log WARN "$@"
}

zshmq_log_error() {
  zshmq_log ERROR "$@"
}

zshmq_log_fatal() {
  zshmq_log FATAL "$@"
}
