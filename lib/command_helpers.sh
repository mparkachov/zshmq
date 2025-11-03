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
