#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# dispatch - Manage dispatcher processes for zshmq topics.
# @usage: zshmq dispatch <command> [options]
# @summary: Start or stop the dispatcher that routes messages for a topic.
# @description: Provides subcommands to launch the background dispatcher loop (`dispatch start`) or terminate it (`dispatch stop`). Each subcommand accepts shared options for selecting the runtime directory and topic, along with the standard logging controls.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name handled by the dispatcher subcommand.
# @option: -f, --foreground   (dispatch start) Run the dispatcher in the foreground.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

dispatch_print_usage() {
  printf '%s\n' 'Usage: zshmq dispatch <command> [options]'
  printf '%s\n' ''
  printf '%s\n' 'Commands:'
  printf '  start  Launch the dispatcher for a topic\n'
  printf '  stop   Terminate the dispatcher for a topic\n'
}

dispatch_start_parser_definition() {
  zshmq_parser_defaults
  param DISPATCH_CTX_PATH -p --path -- 'Runtime directory to target'
  param DISPATCH_TOPIC -T --topic -- 'Topic name handled by this dispatcher'
  flag DISPATCH_FOREGROUND -f --foreground -- 'Run the dispatcher in the foreground'
}

dispatcher_extract_fifo_pid() {
  fifo_path=$1
  name=${fifo_path##*/}
  pid=${name##*.}
  case $pid in
    ''|*[!0-9]*)
      printf '%s\n' ''
      return 1
      ;;
  esac
  printf '%s\n' "$pid"
  return 0
}

dispatcher_prune_state() {
  state_path=$1
  tmp_state="${state_path}.dispatcher.$$"
  : > "$tmp_state"
  while IFS= read -r fifo || [ -n "$fifo" ]; do
    [ -n "$fifo" ] || continue
    fifo_pid=$(dispatcher_extract_fifo_pid "$fifo")
    if [ -n "$fifo_pid" ] && kill -0 "$fifo_pid" 2>/dev/null; then
      if [ -p "$fifo" ]; then
        printf '%s\n' "$fifo" >> "$tmp_state"
      fi
    else
      rm -f "$fifo" 2>/dev/null || :
    fi
  done < "$state_path"
  mv "$tmp_state" "$state_path"
}

zshmq_dispatch_loop() {
  topic_fifo_path=$1
  state_path=$2

  trap 'exec 3>&-; exit 0' INT TERM HUP

  # Keep the FIFO open even when no writers are connected.
  exec 3<>"$topic_fifo_path"

  while IFS= read -r line <&3; do
    case $line in
      SUB\|*)
        entry=${line#SUB|}
        if [ -n "$entry" ]; then
          [ -f "$state_path" ] || : > "$state_path"
          if ! grep -F -- "$entry" "$state_path" >/dev/null 2>&1; then
            printf '%s\n' "$entry" >> "$state_path"
          fi
        fi
        ;;
      UNSUB\|*)
        entry=${line#UNSUB|}
        if [ -n "$entry" ] && [ -f "$state_path" ]; then
          tmp_state="${state_path}.tmp.$$"
          : > "$tmp_state"
          while IFS= read -r state_line || [ -n "$state_line" ]; do
            [ "$state_line" = "$entry" ] && continue
            printf '%s\n' "$state_line" >> "$tmp_state"
          done < "$state_path"
          mv "$tmp_state" "$state_path"
        fi
        ;;
      PUB\|*)
        payload=${line#PUB|}
        topic=${payload%%|*}
        message=${payload#*|}
        if [ -f "$state_path" ] && [ -n "$topic" ]; then
          message_body=$message
          if [ -s "$state_path" ]; then
            dispatcher_prune_state "$state_path"
          fi
          zshmq_log_trace 'dispatcher: topic=%s message=%s' "$topic" "$message_body"
          while IFS= read -r fifo_path || [ -n "$fifo_path" ]; do
            [ -n "$fifo_path" ] || continue
            fifo_pid=$(dispatcher_extract_fifo_pid "$fifo_path")
            if [ -z "$fifo_pid" ] || ! kill -0 "$fifo_pid" 2>/dev/null; then
              continue
            fi
            if [ -p "$fifo_path" ]; then
              zshmq_log_trace 'dispatcher: deliver topic=%s message=%s fifo=%s' "$topic" "$message_body" "$fifo_path"
              { printf '%s\n' "$message_body"; } >> "$fifo_path" 2>/dev/null || :
            fi
          done < "$state_path"
        fi
        ;;
      *)
        :
        ;;
    esac
  done
}

dispatch_start() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'dispatch start: ZSHMQ_ROOT is not set'
      return 1
    fi
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  unset DISPATCH_FOREGROUND ||:

  set +e
  zshmq_eval_parser dispatch_start dispatch_start_parser_definition "$@"
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
    zshmq_log_error 'dispatch start: unexpected argument -- %s' "$1"
    return 1
  fi

  unset ZSHMQ_REST ||:

  topic=${DISPATCH_TOPIC:-}
  if [ -z "$topic" ]; then
    zshmq_log_error 'dispatch start: --topic is required'
    return 1
  fi

  target=${DISPATCH_CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'dispatch start: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'dispatch start: refusing to operate on root directory'
      return 1
      ;;
  esac

  runtime_root=${target%/}
  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic}.state}
  topic_fifo_path=${ZSHMQ_TOPIC:-${runtime_root}/${topic}.fifo}
  pid_path=${ZSHMQ_DISPATCH_PID:-${runtime_root}/${topic}.pid}

  if [ ! -d "$target" ]; then
    zshmq_log_error 'dispatch start: runtime directory not found: %s' "$target"
    return 1
  fi

  if [ ! -p "$topic_fifo_path" ]; then
    zshmq_log_error 'dispatch start: topic FIFO not found at %s' "$topic_fifo_path"
    return 1
  fi

  if [ ! -f "$state_path" ]; then
    zshmq_log_error 'dispatch start: state file not found at %s' "$state_path"
    return 1
  fi

  if [ -f "$pid_path" ]; then
    existing_pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      zshmq_log_debug 'dispatch start: dispatcher already running (pid=%s)' "$existing_pid"
      return 1
    fi
    rm -f "$pid_path"
  fi

  if [ "${DISPATCH_FOREGROUND:-0}" = "1" ]; then
    zshmq_dispatch_loop "$topic_fifo_path" "$state_path" &
    dispatcher_pid=$!
    printf '%s\n' "$dispatcher_pid" > "$pid_path"
    zshmq_log_debug 'Dispatcher started (pid=%s)' "$dispatcher_pid"

    dispatch_start_cleaned=0

    dispatch_start_cleanup() {
      if [ "${dispatch_start_cleaned}" -eq 1 ]; then
        return 0
      fi
      dispatch_start_cleaned=1
      trap - INT TERM HUP EXIT
      if [ -n "${dispatcher_pid:-}" ] && kill -0 "$dispatcher_pid" 2>/dev/null; then
        kill "$dispatcher_pid" 2>/dev/null || :
        wait "$dispatcher_pid" 2>/dev/null || :
      else
        wait "$dispatcher_pid" 2>/dev/null || :
      fi
      rm -f "$pid_path"
    }

    trap 'dispatch_start_cleanup; exit 130' INT
    trap 'dispatch_start_cleanup; exit 143' TERM
    trap 'dispatch_start_cleanup; exit 129' HUP
    trap 'dispatch_start_cleanup' EXIT

    wait "$dispatcher_pid"
    wait_status=$?
    dispatch_start_cleanup
    return "$wait_status"
  fi

  zshmq_dispatch_loop "$topic_fifo_path" "$state_path" &
  dispatcher_pid=$!
  printf '%s\n' "$dispatcher_pid" > "$pid_path"
  zshmq_log_debug 'Dispatcher started (pid=%s)' "$dispatcher_pid"
}

dispatch_stop_parser_definition() {
  zshmq_parser_defaults
  param DISPATCH_CTX_PATH -p --path -- 'Runtime directory to target'
  param DISPATCH_TOPIC -T --topic -- 'Topic name whose dispatcher should be stopped'
}

dispatch_stop() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'dispatch stop: ZSHMQ_ROOT is not set'
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
  zshmq_eval_parser dispatch_stop dispatch_stop_parser_definition "$@"
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
    zshmq_log_error 'dispatch stop: unexpected argument -- %s' "$1"
    return 1
  fi

  unset ZSHMQ_REST ||:

  topic=${DISPATCH_TOPIC:-}
  pid_override=
  if [ -z "$topic" ] && [ -n "${ZSHMQ_TOPIC:-}" ]; then
    topic_source=$ZSHMQ_TOPIC
    topic_basename=${topic_source##*/}
    topic=${topic_basename%.fifo}
    case $topic_source in
      /*)
        pid_override=${topic_source%.fifo}.pid
        ;;
      *)
        pid_override=
        ;;
    esac
  fi

  if [ -z "$topic" ]; then
    zshmq_log_error 'dispatch stop: --topic is required'
    return 1
  fi

  target=${DISPATCH_CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'dispatch stop: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'dispatch stop: refusing to operate on root directory'
      return 1
      ;;
  esac

  runtime_root=${target%/}
  pid_path=${ZSHMQ_DISPATCH_PID:-}
  if [ -z "$pid_path" ]; then
    if [ -n "$pid_override" ]; then
      pid_path=$pid_override
    else
      pid_path=${runtime_root}/${topic}.pid
    fi
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
    zshmq_log_error 'dispatch stop: dispatcher (pid=%s) did not terminate' "$dispatcher_pid"
    return 1
  fi

  rm -f "$pid_path"
  zshmq_log_debug 'Dispatcher stopped (pid=%s)' "$dispatcher_pid"
}

dispatch() {
  set -eu

  log_level=${ZSHMQ_LOG_LEVEL:-INFO}

  while [ $# -gt 0 ]; do
    case $1 in
      -d|--debug)
        log_level=DEBUG
        shift
        ;;
      -t|--trace)
        log_level=TRACE
        shift
        ;;
      -h|--help|help)
        dispatch_print_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      start|stop)
        break
        ;;
      *)
        break
        ;;
    esac
  done

  export ZSHMQ_LOG_LEVEL=$log_level

  if [ $# -eq 0 ]; then
    dispatch_print_usage
    return 1
  fi

  subcommand=$1
  shift

  case $subcommand in
    start)
      dispatch_start "$@"
      ;;
    stop)
      dispatch_stop "$@"
      ;;
    -h|--help|help)
      dispatch_print_usage
      ;;
    *)
      zshmq_log_error 'dispatch: unknown command -- %s' "$subcommand"
      dispatch_print_usage
      return 1
      ;;
  esac
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command dispatch
fi
