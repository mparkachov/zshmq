#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# stop - Terminate the zshmq dispatcher loop.
# @usage: zshmq stop [--path PATH]
# @summary: Stop the dispatcher running for the given runtime directory (default: /tmp/zshmq).
# @description: Read the dispatcher PID from the runtime directory, send it SIGTERM, and remove the PID file once the dispatcher exits.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -h, --help         Display command documentation and exit.
#*/

stop_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to target'
}

stop() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      printf '%s\n' 'stop: ZSHMQ_ROOT is not set' >&2
      return 1
    fi
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  set +e
  zshmq_eval_parser stop stop_parser_definition "$@"
  status=$?
  set -e

  case $status in
    0)
      eval "set -- $ZSHMQ_REST"
      ;;
    1)
      return 1
      ;;
    2)
      return 0
      ;;
  esac

  if [ $# -gt 0 ]; then
    printf 'stop: unexpected argument -- %s\n' "$1" >&2
    return 1
  fi

  unset ZSHMQ_REST ||:

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    printf '%s\n' 'stop: target path is empty' >&2
    return 1
  fi

  case $target in
    /|'')
      printf '%s\n' 'stop: refusing to operate on root directory' >&2
      return 1
      ;;
  esac

  runtime_root=${target%/}
  pid_path=${ZSHMQ_DISPATCH_PID:-${runtime_root}/dispatcher.pid}

  if [ ! -f "$pid_path" ]; then
    printf '%s\n' 'Dispatcher is not running.'
    return 0
  fi

  dispatcher_pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
  if [ -z "$dispatcher_pid" ]; then
    rm -f "$pid_path"
    printf '%s\n' 'Dispatcher is not running.'
    return 0
  fi

  if ! kill -0 "$dispatcher_pid" 2>/dev/null; then
    rm -f "$pid_path"
    printf '%s\n' 'Dispatcher is not running.'
    return 0
  fi

  kill "$dispatcher_pid" 2>/dev/null || :

  for attempt in 1 2 3 4 5; do
    if ! kill -0 "$dispatcher_pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done

  if kill -0 "$dispatcher_pid" 2>/dev/null; then
    printf 'stop: dispatcher (pid=%s) did not terminate\n' "$dispatcher_pid" >&2
    return 1
  fi

  rm -f "$pid_path"
  printf 'Dispatcher stopped (pid=%s)\n' "$dispatcher_pid"
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command stop
fi
