#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# stop - Terminate the zshmq dispatcher loop.
# @usage: zshmq stop [--path PATH] [--topic TOPIC]
# @summary: Stop the dispatcher running for the given runtime directory (default: /tmp/zshmq).
# @description: Read the dispatcher PID from the runtime directory, send it SIGTERM, and remove the PID file once the dispatcher exits.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name whose dispatcher should be stopped.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

stop_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to target'
  param STOP_TOPIC -T --topic -- 'Topic whose dispatcher should be stopped'
}

stop() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'stop: ZSHMQ_ROOT is not set'
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
    zshmq_log_error 'stop: unexpected argument -- %s' "$1"
    return 1
  fi

  unset ZSHMQ_REST ||:

  topic=${STOP_TOPIC:-}
  if [ -n "$topic" ]; then
    case $topic in
      *'|'*|*'/'*|*'
'*)
        zshmq_log_error 'stop: topic contains invalid characters'
        return 1
        ;;
    esac
  fi

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'stop: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'stop: refusing to operate on root directory'
      return 1
      ;;
  esac

  runtime_root=${target%/}
  pid_path=${ZSHMQ_DISPATCH_PID:-}

  if [ -n "$topic" ]; then
    pid_path=${runtime_root}/${topic}.pid
  elif [ -z "$pid_path" ] && [ -n "${ZSHMQ_TOPIC:-}" ]; then
    topic_override=${ZSHMQ_TOPIC%.fifo}
    case $topic_override in
      /*)
        pid_path=${topic_override}.pid
        ;;
      '')
        pid_path=
        ;;
      *)
        pid_path=${runtime_root}/${topic_override}.pid
        ;;
    esac
  fi

  if [ -z "$pid_path" ] || [ ! -f "$pid_path" ]; then
    for candidate in "$runtime_root"/*.pid; do
      if [ -f "$candidate" ]; then
        pid_path=$candidate
        break
      fi
    done
  fi

  if [ -z "$pid_path" ] || [ ! -f "$pid_path" ]; then
    zshmq_log_debug 'Dispatcher is not running.'
    return 0
  fi

  dispatcher_pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
  if [ -z "$dispatcher_pid" ]; then
    rm -f "$pid_path"
    zshmq_log_debug 'Dispatcher is not running.'
    return 0
  fi

  if ! kill -0 "$dispatcher_pid" 2>/dev/null; then
    rm -f "$pid_path"
    zshmq_log_debug 'Dispatcher is not running.'
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
    zshmq_log_error 'stop: dispatcher (pid=%s) did not terminate' "$dispatcher_pid"
    return 1
  fi

  rm -f "$pid_path"
  zshmq_log_debug 'Dispatcher stopped (pid=%s)' "$dispatcher_pid"
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command stop
fi
