#!/usr/bin/env sh
# shellcheck shell=sh

: "${ZSHMQ_COMMAND_REGISTRY:=}"

zshmq_register_command() {
  cmd=$1
  case " ${ZSHMQ_COMMAND_REGISTRY} " in
    *" ${cmd} "*)
      :
      ;;
    *)
      if [ -n "${ZSHMQ_COMMAND_REGISTRY}" ]; then
        ZSHMQ_COMMAND_REGISTRY="${ZSHMQ_COMMAND_REGISTRY} ${cmd}"
      else
        ZSHMQ_COMMAND_REGISTRY="${cmd}"
      fi
      ;;
  esac
}

zshmq_command_file() {
  command=$1
  if [ -z "${ZSHMQ_ROOT:-}" ]; then
    return 1
  fi
  file="${ZSHMQ_ROOT}/lib/${command}.sh"
  if [ -f "$file" ]; then
    printf '%s\n' "$file"
    return 0
  fi
  return 1
}

zshmq_command_metadata() {
  command=$1
  key=$2
  file=$(zshmq_command_file "$command") || return 1
  sed -n "s/^[[:space:]]*# *@${key}:[[:space:]]*//p" "$file"
}

zshmq_registered_commands() {
  for cmd in $ZSHMQ_COMMAND_REGISTRY; do
    [ -n "$cmd" ] && printf '%s\n' "$cmd"
  done
}

zshmq_command_summary() {
  command=$1
  summary=$(zshmq_command_metadata "$command" summary | sed -n '1p')
  if [ -n "$summary" ]; then
    printf '%s\n' "$summary"
  else
    printf '%s\n' 'Undocumented command.'
  fi
}

zshmq_parser_defaults() {
  usage_text=${ZSHMQ_PARSER_USAGE:-"zshmq <command>"}
  setup REST help:usage -- "Usage: ${usage_text}" ''
  msg -- 'Options:'
  flag ZSHMQ_HELP -h --help -- 'Display command documentation and exit.'
  flag ZSHMQ_DEBUG -d --debug -- 'Enable DEBUG log level.'
  flag ZSHMQ_TRACE -t --trace -- 'Enable TRACE log level.'
}

zshmq_print_command_help() {
  command=$1
  display_command=$(printf '%s' "$command" | tr '_' ' ')
  usage=$(zshmq_command_metadata "$command" usage | sed -n '1p')
  if [ -z "$usage" ]; then
    usage="zshmq $display_command"
  fi

  printf 'Command: %s\n' "$display_command"
  printf 'Usage: %s\n' "$usage"
  printf '\n'

  description=$(zshmq_command_metadata "$command" description)
  if [ -n "$description" ]; then
    printf '%s\n' "$description"
    printf '\n'
  else
    summary=$(zshmq_command_metadata "$command" summary | sed -n '1p')
    if [ -n "$summary" ]; then
      printf '%s\n\n' "$summary"
    fi
  fi

  options=$(zshmq_command_metadata "$command" option)
  if [ -n "$options" ]; then
    printf 'Options:\n'
    zshmq_command_metadata "$command" option | while IFS= read -r line; do
      printf '  %s\n' "$line"
    done
  fi
}

zshmq_eval_parser() {
  command=$1
  parser_fn=$2
  shift 2
  ZSHMQ_PARSER_USAGE=$(zshmq_command_metadata "$command" usage | sed -n '1p')
  if [ -z "$ZSHMQ_PARSER_USAGE" ]; then
    display_command=$(printf '%s' "$command" | tr '_' ' ')
    ZSHMQ_PARSER_USAGE="zshmq $display_command"
  fi
  unset ZSHMQ_HELP ||:
  unset ZSHMQ_DEBUG ||:
  unset ZSHMQ_TRACE ||:
  # shellcheck disable=SC2039
  eval "$(getoptions "$parser_fn" zshmq_parse_runner)" || return 1
  zshmq_parse_runner "$@"
  # shellcheck disable=SC2034
  ZSHMQ_REST=$REST
  if [ "${ZSHMQ_TRACE:-0}" = "1" ]; then
    ZSHMQ_LOG_LEVEL=TRACE
  elif [ "${ZSHMQ_DEBUG:-0}" = "1" ]; then
    ZSHMQ_LOG_LEVEL=DEBUG
  fi
  : "${ZSHMQ_LOG_LEVEL:=INFO}"
  export ZSHMQ_LOG_LEVEL
  if [ "${ZSHMQ_HELP:-0}" = "1" ]; then
    zshmq_print_command_help "$command"
    return 2
  fi
  return 0
}

# Shared validation and utility functions
# IMPORTANT: After modifying these shared functions, always run the test suite:
#   ./scripts/test.sh
# These functions are used across multiple commands, so changes may have wide impact.

zshmq_validate_runtime_path() {
  path=$1
  context=${2:-zshmq}

  if [ -z "$path" ]; then
    zshmq_log_error '%s: target path is empty' "$context"
    return 1
  fi

  case $path in
    /|'')
      zshmq_log_error '%s: refusing to operate on root directory' "$context"
      return 1
      ;;
  esac

  printf '%s\n' "${path%/}"
}

zshmq_ensure_runtime_exists() {
  path=$1
  context=${2:-zshmq}

  validated_path=$(zshmq_validate_runtime_path "$path" "$context") || return 1

  if [ ! -d "$validated_path" ]; then
    zshmq_log_error '%s: runtime directory not found: %s' "$context" "$validated_path"
    return 1
  fi

  printf '%s\n' "$validated_path"
}

zshmq_read_pid_file() {
  pid_path=$1
  if [ ! -f "$pid_path" ]; then
    return 1
  fi
  pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
  if [ -z "$pid" ]; then
    return 1
  fi
  printf '%s\n' "$pid"
}

zshmq_is_process_running() {
  pid=$1
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

zshmq_check_dispatcher_running() {
  pid_path=$1
  dispatcher_pid=$(zshmq_read_pid_file "$pid_path") || return 1
  if ! zshmq_is_process_running "$dispatcher_pid"; then
    rm -f "$pid_path"
    return 1
  fi
  printf '%s\n' "$dispatcher_pid"
}

zshmq_wait_for_process_termination() {
  pid=$1
  max_attempts=${2:-5}
  attempt=1

  while [ "$attempt" -le "$max_attempts" ]; do
    if ! zshmq_is_process_running "$pid"; then
      return 0
    fi
    sleep 1
    attempt=$((attempt + 1))
  done

  return 1
}

zshmq_extract_fifo_pid() {
  fifo_path=$1
  name=${fifo_path##*/}
  pid=${name##*.}
  case $pid in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  printf '%s\n' "$pid"
}

zshmq_prune_state_file() {
  state_path=$1
  tmp_suffix=${2:-prune}

  tmp_state="${state_path}.${tmp_suffix}.$$"
  : > "$tmp_state"

  while IFS= read -r fifo_path || [ -n "$fifo_path" ]; do
    [ -n "$fifo_path" ] || continue
    fifo_pid=$(zshmq_extract_fifo_pid "$fifo_path") || continue
    if zshmq_is_process_running "$fifo_pid"; then
      if [ -p "$fifo_path" ]; then
        printf '%s\n' "$fifo_path" >> "$tmp_state"
      fi
    else
      rm -f "$fifo_path" 2>/dev/null || :
    fi
  done < "$state_path"

  mv "$tmp_state" "$state_path"
}
