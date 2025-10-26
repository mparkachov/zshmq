#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# send - Publish a message to the zshmq dispatcher.
# @usage: zshmq send [--path PATH] [--topic TOPIC] MESSAGE...
# @summary: Publish a message through the dispatcher FIFO.
# @description: Validate the existing runtime directory, ensure the dispatcher is running, and write the message to the bus so matching subscribers receive it.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Explicit topic to apply instead of inferring from MESSAGE (before the first colon).
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

send_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to target'
  param SEND_TOPIC -T --topic -- 'Explicit topic to apply'
}

send_trim() {
  # Trim leading and trailing whitespace.
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

send_ltrim() {
  # Trim leading whitespace only.
  printf '%s' "$1" | sed 's/^[[:space:]]*//'
}

send() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'send: ZSHMQ_ROOT is not set'
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
  zshmq_eval_parser send send_parser_definition "$@"
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

  if [ $# -eq 0 ]; then
    zshmq_log_error 'send: message is required'
    return 1
  fi

  message=$1
  shift
  if [ $# -gt 0 ]; then
    message="$message $*"
  fi

  topic=${SEND_TOPIC:-}
  body=$message

  if [ -z "$topic" ]; then
    case $message in
      *:*)
        topic_part=${message%%:*}
        body_part=${message#*:}
        topic=$(send_trim "$topic_part")
        body=$(send_ltrim "$body_part")
        ;;
      *)
        zshmq_log_error 'send: unable to infer topic; provide --topic or include "<topic>: <message>".'
        return 1
        ;;
    esac
  else
    topic=$(send_trim "$topic")
    body=$message
  fi

  if [ -z "$topic" ]; then
    zshmq_log_error 'send: topic must not be empty'
    return 1
  fi

  case $topic in
    *'|'*)
      zshmq_log_error 'send: topic must not contain "|"'
      return 1
      ;;
  esac

  case $body in
    *'|'*)
      zshmq_log_error 'send: message must not contain "|"'
      return 1
      ;;
  esac

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'send: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'send: refusing to operate on root directory'
      return 1
      ;;
  esac

  runtime_root=${target%/}
  bus_path=${ZSHMQ_BUS:-${runtime_root}/bus}
  pid_path=${ZSHMQ_DISPATCH_PID:-${runtime_root}/dispatcher.pid}

  if [ ! -d "$target" ]; then
    zshmq_log_error 'send: runtime directory not found: %s' "$target"
    return 1
  fi

  if [ ! -p "$bus_path" ]; then
    zshmq_log_error 'send: bus FIFO not found at %s' "$bus_path"
    return 1
  fi

  if [ -f "$pid_path" ]; then
    dispatcher_pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
  else
    dispatcher_pid=
  fi

  if [ -z "$dispatcher_pid" ] || ! kill -0 "$dispatcher_pid" 2>/dev/null; then
    zshmq_log_error 'send: dispatcher is not running'
    return 1
  fi

  zshmq_log_trace 'send: topic=%s message=%s' "$topic" "$body"
  printf 'PUB|%s|%s\n' "$topic" "$body" > "$bus_path"

  if ! zshmq_log_should_emit TRACE; then
    printf '%s|%s\n' "$topic" "$body"
  fi
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command send
fi
