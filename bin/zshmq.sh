#!/usr/bin/env sh
# shellcheck source-path=SCRIPTDIR/..
set -eu

script_dir=$(
  CDPATH='' cd -- "$(dirname -- "$0")" && pwd
)
if [ -n "${ZSHMQ_EMBEDDED:-}" ]; then
  ZSHMQ_ROOT=${script_dir}
else
  ZSHMQ_ROOT=$(
    CDPATH='' cd -- "${script_dir}/.." && pwd
  )
fi
export ZSHMQ_ROOT
export ZSHMQ_VERSION="${ZSHMQ_VERSION:-$( [ -f "${ZSHMQ_ROOT}/VERSION" ] && cat "${ZSHMQ_ROOT}/VERSION" || printf '%s\n' '0.0.1' )}"

if [ -z "${ZSHMQ_EMBEDDED:-}" ]; then
  # Load getoptions once so command implementations can rely on it.
  # shellcheck source=../vendor/getoptions/lib/getoptions_base.sh
  . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
  # shellcheck source=../vendor/getoptions/lib/getoptions_abbr.sh
  . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
  # shellcheck source=../vendor/getoptions/lib/getoptions_help.sh
  . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  # shellcheck source=../lib/command_helpers.sh
  . "${ZSHMQ_ROOT}/lib/command_helpers.sh"
  # shellcheck source=../lib/logging.sh
  . "${ZSHMQ_ROOT}/lib/logging.sh"

  # Load command implementations after helper definitions.
  # shellcheck source=../lib/ctx.sh
  . "${ZSHMQ_ROOT}/lib/ctx.sh"
  # shellcheck source=../lib/topic.sh
  . "${ZSHMQ_ROOT}/lib/topic.sh"
  # shellcheck source=../lib/bus.sh
  . "${ZSHMQ_ROOT}/lib/bus.sh"
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
  printf '%s\n' "Run 'zshmq help <command>' or 'zshmq <command> --help' for command-specific documentation."
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
  ctx)
    ctx "$@"
    ;;
  topic)
    topic "$@"
    ;;
  bus)
    bus "$@"
    ;;
  *)
    printf 'zshmq: unknown command -- %s\n' "$command_name" >&2
    printf '%s\n' '' >&2
    zshmq_show_help >&2
    exit 1
    ;;
 esac
