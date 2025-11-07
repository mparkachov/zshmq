#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# bus - Manage the routing bus dispatcher.
# @usage: zshmq bus <command> [options]
# @summary: Provision, launch, or tear down the bus that fans messages to multiple topics.
# @description: Provides helpers to bootstrap the special `bus` topic, manage its dispatcher lifecycle, and forward bus messages to topics whose registry regex matches the payload.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -f, --foreground   (bus start) Run the dispatcher in the foreground.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

bus_print_usage() {
  printf '%s\n' 'Usage: zshmq bus <command> [options]'
  printf '%s\n' ''
  printf '%s\n' 'Commands:'
  printf '  new      Initialise the bus topic and registry entry\n'
  printf '  destroy  Remove the bus topic and associated assets\n'
  printf '  start    Launch the bus dispatcher (fan-out loop)\n'
  printf '  stop     Terminate the bus dispatcher\n'
}

bus_start_parser_definition() {
  zshmq_parser_defaults
  param BUS_CTX_PATH -p --path -- 'Runtime directory to target'
  flag BUS_FOREGROUND -f --foreground -- 'Run the bus dispatcher in the foreground'
}

bus_stop_parser_definition() {
  zshmq_parser_defaults
  param BUS_CTX_PATH -p --path -- 'Runtime directory to target'
}

bus_resolve_runtime() {
  path=$1
  zshmq_ensure_runtime_exists "$path" "bus"
}

bus_dispatch_ready() {
  runtime_root=$1
  topic_name=$2

  pid_path=${runtime_root}/${topic_name}.pid
  zshmq_check_dispatcher_running "$pid_path" >/dev/null
}

bus_publish_to_topic() {
  runtime_root=$1
  route_topic=$2
  message=$3

  topic_fifo_path=${runtime_root}/${route_topic}.fifo

  if [ ! -p "$topic_fifo_path" ]; then
    zshmq_log_debug 'bus dispatcher: fifo missing for topic=%s' "$route_topic"
    return 1
  fi

  if ! bus_dispatch_ready "$runtime_root" "$route_topic"; then
    zshmq_log_debug 'bus dispatcher: dispatcher offline for topic=%s' "$route_topic"
    return 1
  fi

  if ! { printf 'PUB|%s|%s\n' "$route_topic" "$message"; } > "$topic_fifo_path"; then
    zshmq_log_error 'bus dispatcher: failed to forward topic=%s' "$route_topic"
    return 1
  fi

  zshmq_log_trace 'bus dispatcher: forwarded topic=%s message=%s' "$route_topic" "$message"
  return 0
}

bus_route_message() {
  runtime_root=$1
  registry_path=$2
  message=$3

  if [ ! -f "$registry_path" ]; then
    zshmq_log_trace 'bus dispatcher: registry missing (%s)' "$registry_path"
    return 0
  fi

  delivered=0

  while IFS= read -r registry_line || [ -n "$registry_line" ]; do
    case $registry_line in
      ''|\#*)
        continue
        ;;
    esac
    route_topic=$registry_line
    route_regex=
    case $registry_line in
      *'	'*)
        route_topic=${registry_line%%	*}
        route_regex=${registry_line#*	}
        ;;
    esac

    if [ "$route_topic" = "bus" ]; then
      continue
    fi

    if [ -z "$route_regex" ]; then
      continue
    fi

    if printf '%s\n' "$message" | grep -E -- "$route_regex" >/dev/null 2>&1; then
      if bus_publish_to_topic "$runtime_root" "$route_topic" "$message"; then
        delivered=1
      fi
      continue
    fi

    match_status=$?
    if [ "$match_status" -eq 2 ]; then
      zshmq_log_error 'bus dispatcher: invalid regex for topic=%s regex=%s' "$route_topic" "$route_regex"
    fi
  done < "$registry_path"

  if [ "$delivered" -eq 0 ]; then
    zshmq_log_trace 'bus dispatcher: no routes matched message=%s' "$message"
  fi
}

zshmq_bus_loop() {
  bus_fifo_path=$1
  runtime_root=$2
  registry_path=$3

  trap 'exec 3>&-; exit 0' INT TERM HUP
  exec 3<>"$bus_fifo_path"

  while IFS= read -r line <&3; do
    case $line in
      PUB\|*)
        payload=${line#PUB|}
        origin_topic=${payload%%|*}
        message=${payload#*|}
        if [ "$origin_topic" != "bus" ]; then
          zshmq_log_trace 'bus dispatcher: ignoring pub for topic=%s' "$origin_topic"
          continue
        fi
        bus_route_message "$runtime_root" "$registry_path" "$message"
        ;;
      *)
        zshmq_log_trace 'bus dispatcher: ignored frame=%s' "$line"
        ;;
    esac
  done
}

bus_new() {
  runtime_root=$1

  if [ ! -d "$runtime_root" ]; then
    zshmq_log_error 'bus new: runtime directory not found: %s' "$runtime_root"
    return 1
  fi

  topic_new "$runtime_root" bus ''
  zshmq_log_debug 'bus new: prepared bus topic runtime=%s' "$runtime_root"
}

bus_stop_runtime() {
  runtime_root=$1
  pid_path=${runtime_root}/bus.pid

  zshmq_validate_runtime_path "$runtime_root" "bus stop" >/dev/null || return 1

  dispatcher_pid=$(zshmq_check_dispatcher_running "$pid_path" 2>/dev/null) || return 0

  kill "$dispatcher_pid" 2>/dev/null || :

  if ! zshmq_wait_for_process_termination "$dispatcher_pid" 5; then
    zshmq_log_error 'bus stop: dispatcher (pid=%s) did not terminate' "$dispatcher_pid"
    return 1
  fi

  rm -f "$pid_path"
  zshmq_log_debug 'bus stop: dispatcher stopped (pid=%s)' "$dispatcher_pid"
  return 0
}

bus_destroy() {
  runtime_root=$1

  zshmq_validate_runtime_path "$runtime_root" "bus destroy" >/dev/null || return 1

  if [ ! -d "$runtime_root" ]; then
    zshmq_log_trace 'bus destroy: runtime missing (%s)' "$runtime_root"
    return 0
  fi

  if ! bus_stop_runtime "$runtime_root"; then
    return 1
  fi

  topic_destroy "$runtime_root" bus ''
  pid_path=${runtime_root}/bus.pid
  rm -f "$pid_path"
  zshmq_log_debug 'bus destroy: removed bus assets runtime=%s' "$runtime_root"
}

bus_start() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'bus start: ZSHMQ_ROOT is not set'
      return 1
    fi
    # Ensure vendor parser modules are available when getoptions is missing.
    # shellcheck source=../vendor/getoptions/lib/getoptions_base.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_abbr.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_help.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  set +e
  zshmq_eval_parser bus_start bus_start_parser_definition "$@"
  status=$?
  set -e

  case $status in
    0)
      : "${ZSHMQ_REST:=}"
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
    zshmq_log_error 'bus start: unexpected argument -- %s' "$1"
    return 1
  fi

  target_path=${BUS_CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}
  runtime_root=$(bus_resolve_runtime "$target_path") || return 1

  bus_fifo_path=${runtime_root}/bus.fifo
  registry_path=$(topic_registry_path "$runtime_root")
  pid_path=${runtime_root}/bus.pid

  if [ ! -p "$bus_fifo_path" ]; then
    zshmq_log_error 'bus start: bus FIFO not found at %s (run bus new first)' "$bus_fifo_path"
    return 1
  fi

  if existing_pid=$(zshmq_check_dispatcher_running "$pid_path" 2>/dev/null); then
    zshmq_log_debug 'bus start: dispatcher already running (pid=%s)' "$existing_pid"
    return 1
  fi

  if [ "${BUS_FOREGROUND:-0}" = "1" ]; then
    zshmq_bus_loop "$bus_fifo_path" "$runtime_root" "$registry_path" &
    dispatcher_pid=$!
    printf '%s\n' "$dispatcher_pid" > "$pid_path"
    zshmq_log_debug 'Bus dispatcher started (pid=%s)' "$dispatcher_pid"

    bus_start_cleaned=0

    bus_start_cleanup() {
      if [ "${bus_start_cleaned}" -eq 1 ]; then
        return 0
      fi
      bus_start_cleaned=1
      trap - INT TERM HUP EXIT
      if [ -n "${dispatcher_pid:-}" ] && kill -0 "$dispatcher_pid" 2>/dev/null; then
        kill "$dispatcher_pid" 2>/dev/null || :
        wait "$dispatcher_pid" 2>/dev/null || :
      else
        wait "$dispatcher_pid" 2>/dev/null || :
      fi
      rm -f "$pid_path"
    }

    trap 'bus_start_cleanup; exit 130' INT
    trap 'bus_start_cleanup; exit 143' TERM
    trap 'bus_start_cleanup; exit 129' HUP
    trap 'bus_start_cleanup' EXIT

    wait "$dispatcher_pid"
    wait_status=$?
    bus_start_cleanup
    return "$wait_status"
  fi

  zshmq_bus_loop "$bus_fifo_path" "$runtime_root" "$registry_path" &
  dispatcher_pid=$!
  printf '%s\n' "$dispatcher_pid" > "$pid_path"
  zshmq_log_debug 'Bus dispatcher started (pid=%s)' "$dispatcher_pid"
}

bus_stop() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'bus stop: ZSHMQ_ROOT is not set'
      return 1
    fi
    # shellcheck source=../vendor/getoptions/lib/getoptions_base.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_abbr.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_help.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  set +e
  zshmq_eval_parser bus_stop bus_stop_parser_definition "$@"
  status=$?
  set -e

  case $status in
    0)
      : "${ZSHMQ_REST:=}"
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
    zshmq_log_error 'bus stop: unexpected argument -- %s' "$1"
    return 1
  fi

  target_path=${BUS_CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  runtime_root=$(zshmq_validate_runtime_path "$target_path" "bus stop") || return 1

  if [ ! -d "$runtime_root" ]; then
    zshmq_log_debug 'bus stop: runtime not found (%s)' "$runtime_root"
    return 0
  fi

  if ! bus_stop_runtime "$runtime_root"; then
    return 1
  fi

  return 0
}

bus() {
  set -eu

  log_level=${ZSHMQ_LOG_LEVEL:-INFO}
  target_path=${ZSHMQ_CTX_ROOT:-/tmp/zshmq}

  while [ $# -gt 0 ]; do
    case $1 in
      -p|--path)
        shift
        if [ $# -eq 0 ]; then
          zshmq_log_error 'bus: --path requires a value'
          return 1
        fi
        target_path=$1
        ;;
      -p=*|--path=*)
        target_path=${1#*=}
        ;;
      -d|--debug)
        log_level=DEBUG
        ;;
      -t|--trace)
        log_level=TRACE
        ;;
      -h|--help|help)
        bus_print_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        zshmq_log_error 'bus: unexpected option -- %s' "$1"
        return 1
        ;;
      *)
        break
        ;;
    esac
    shift || :
  done

  export ZSHMQ_LOG_LEVEL="$log_level"

  if [ $# -eq 0 ]; then
    bus_print_usage
    return 1
  fi

  subcommand=$1
  shift

  case $subcommand in
    new)
      runtime_root=$(bus_resolve_runtime "$target_path") || return 1
      if [ $# -gt 0 ]; then
        zshmq_log_error 'bus new: unexpected argument -- %s' "$1"
        return 1
      fi
      bus_new "$runtime_root"
      ;;
    destroy)
      if [ $# -gt 0 ]; then
        zshmq_log_error 'bus destroy: unexpected argument -- %s' "$1"
        return 1
      fi
      runtime_root=$(zshmq_validate_runtime_path "$target_path" "bus destroy") || return 1
      bus_destroy "$runtime_root"
      ;;
    start)
      bus_start --path "$target_path" "$@"
      ;;
    stop)
      bus_stop --path "$target_path" "$@"
      ;;
    -h|--help|help)
      bus_print_usage
      return 0
      ;;
    *)
      zshmq_log_error 'bus: unknown command -- %s' "$subcommand"
      bus_print_usage
      return 1
      ;;
  esac
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command bus
fi
