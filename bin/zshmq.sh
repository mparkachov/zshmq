#!/usr/bin/env sh
set -eu

script_dir=$(
  CDPATH= cd -- "$(dirname -- "$0")" && pwd
)
if [ -n "${ZSHMQ_EMBEDDED:-}" ]; then
  ZSHMQ_ROOT=${script_dir}
else
  ZSHMQ_ROOT=$(
    CDPATH= cd -- "${script_dir}/.." && pwd
  )
fi
export ZSHMQ_ROOT
export ZSHMQ_VERSION=${ZSHMQ_VERSION:-$( [ -f "${ZSHMQ_ROOT}/VERSION" ] && cat "${ZSHMQ_ROOT}/VERSION" || printf '%s\n' '0.0.1' )}

if [ -z "${ZSHMQ_EMBEDDED:-}" ]; then
  # Load getoptions once so command implementations can rely on it.
  # shellcheck disable=SC1090
  . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
  # shellcheck disable=SC1090
  . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
  # shellcheck disable=SC1090
  . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/command_helpers.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/logging.sh"

  # Load command implementations after helper definitions.
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/ctx_new.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/ctx_destroy.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/start.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/stop.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/send.sh"
  # shellcheck disable=SC1091
  . "${ZSHMQ_ROOT}/lib/sub.sh"
fi

zshmq_command_list() {
  if [ -n "${ZSHMQ_COMMAND_REGISTRY:-}" ]; then
    zshmq_registered_commands
    return
  fi

  for path in "${ZSHMQ_ROOT}/lib"/*.sh; do
    [ -f "$path" ] || continue
    cmd=${path##*/}
    cmd=${cmd%.sh}
    [ "$cmd" = "command_helpers" ] && continue
    [ "$cmd" = "logging" ] && continue
    printf '%s\n' "$cmd"
  done
}

zshmq_show_command_help() {
  cmd=$1
  zshmq_command_file "$cmd" >/dev/null 2>&1 || {
    printf 'Unknown command: %s\n' "$cmd"
    return 1
  }
  zshmq_print_command_help "$cmd"
}

zshmq_show_help() {
  printf '%s\n' 'Zero Shell Message Queue (zshmq)'
  printf '%s\n' ''
  printf '%s\n' 'Usage: zshmq <command> [options]'
  printf '%s\n' ''
  printf '%s\n' 'Commands:'
  for cmd in $(zshmq_command_list); do
    summary=$(zshmq_command_summary "$cmd")
    printf '  %s - %s\n' "$cmd" "$summary"
  done
  printf '\n'
  printf '%s\n' 'Each command supports -h/--help plus -d/--debug and -t/--trace for log verbosity.'
  printf '%s\n' 'Run `zshmq help <command>` or `zshmq <command> --help` for command-specific documentation.'
}

if [ $# -eq 0 ]; then
  zshmq_show_help
  exit 0
fi

command_name=$1
shift

case $command_name in
  -h|--help|help)
    if [ $# -eq 0 ]; then
      zshmq_show_help
    else
      help_target=$1
      zshmq_show_command_help "$help_target"
    fi
    exit 0
    ;;
  --version)
    printf '%s\n' "${ZSHMQ_VERSION:-0.0.0}"
    exit 0
    ;;
  ctx_new)
    ctx_new "$@"
    ;;
  ctx_destroy)
    ctx_destroy "$@"
    ;;
  start)
    start "$@"
    ;;
  stop)
    stop "$@"
    ;;
  send)
    send "$@"
    ;;
  sub)
    sub "$@"
    ;;
  *)
    printf 'zshmq: unknown command -- %s\n' "$command_name" >&2
    printf '%s\n' '' >&2
    zshmq_show_help >&2
    exit 1
    ;;
 esac
