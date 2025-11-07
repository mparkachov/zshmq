#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# topic - Manage topic assets within a runtime directory.
# @usage: zshmq topic <command> [options]
# @summary: Manage topic FIFOs and state files.
# @description: Provides subcommands to provision or remove the FIFO/state pair used by publishers and subscribers for a topic.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: --regex REGEX      (topic new/destroy) Optional routing regex recorded in the topics registry.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

topic_print_usage() {
  printf '%s\n' 'Usage: zshmq topic <command> [options]'
  printf '%s\n' ''
  printf '%s\n' 'Commands:'
  printf '  new      Initialise topic assets (-T/--topic required)\n'
  printf '  destroy  Remove topic assets    (-T/--topic required)\n'
  printf '  start    Launch the topic dispatcher (-T/--topic required)\n'
  printf '  stop     Terminate the topic dispatcher (-T/--topic required)\n'
  printf '  send     Publish a message      (-T/--topic required)\n'
  printf '  sub      Stream topic messages  (-T/--topic required)\n'
}

topic_registry_path() {
  runtime_root=$1
  printf '%s\n' "${runtime_root}/topics.reg"
}

topic_registry_normalize_regex() {
  printf '%s' "$1" | tr -d '\r'
}

topic_registry_upsert() {
  runtime_root=$1
  topic_name=$2
  topic_regex=$3

  registry_path=$(topic_registry_path "$runtime_root")
  tmp_registry="${registry_path}.tmp.$$"
  registry_dir=${registry_path%/*}
  if [ ! -d "$registry_dir" ]; then
    mkdir -p "$registry_dir"
  fi
  touch "$registry_path"

  found=0
  : > "$tmp_registry"

  while IFS= read -r registry_line || [ -n "$registry_line" ]; do
    # Preserve lines unrelated to topics (e.g. comments).
    case $registry_line in
      '')
        printf '\n' >> "$tmp_registry"
        continue
        ;;
      \#*)
        printf '%s\n' "$registry_line" >> "$tmp_registry"
        continue
        ;;
    esac
    entry_topic=$registry_line
    case $registry_line in
      *'	'*)
        entry_topic=${registry_line%%	*}
        ;;
    esac
    if [ "$entry_topic" = "$topic_name" ]; then
      found=1
      normalized_regex=$(topic_registry_normalize_regex "$topic_regex")
      printf '%s\t%s\n' "$topic_name" "$normalized_regex" >> "$tmp_registry"
    else
      printf '%s\n' "$registry_line" >> "$tmp_registry"
    fi
  done < "$registry_path"

  if [ "$found" -eq 0 ]; then
    normalized_regex=$(topic_registry_normalize_regex "$topic_regex")
    printf '%s\t%s\n' "$topic_name" "$normalized_regex" >> "$tmp_registry"
  fi

  mv "$tmp_registry" "$registry_path"
}

topic_registry_remove() {
  runtime_root=$1
  topic_name=$2

  registry_path=$(topic_registry_path "$runtime_root")
  if [ ! -f "$registry_path" ]; then
    return 0
  fi

  tmp_registry="${registry_path}.tmp.$$"
  removed=0
  : > "$tmp_registry"

  while IFS= read -r registry_line || [ -n "$registry_line" ]; do
    case $registry_line in
      '')
        printf '\n' >> "$tmp_registry"
        continue
        ;;
      \#*)
        printf '%s\n' "$registry_line" >> "$tmp_registry"
        continue
        ;;
    esac
    entry_topic=$registry_line
    case $registry_line in
      *'	'*)
        entry_topic=${registry_line%%	*}
        ;;
    esac
    if [ "$entry_topic" = "$topic_name" ]; then
      removed=1
      continue
    fi
    printf '%s\n' "$registry_line" >> "$tmp_registry"
  done < "$registry_path"

  mv "$tmp_registry" "$registry_path"
  if [ "$removed" -eq 1 ]; then
    return 0
  fi
  return 1
}

topic_require_topic() {
  subcommand=$1
  shift

  topic_name=
  topic_regex=

  while [ $# -gt 0 ]; do
    case $1 in
      -T|--topic)
        shift
        if [ $# -eq 0 ]; then
          zshmq_log_error 'topic %s: --topic requires a value' "$subcommand"
          return 1
        fi
        topic_name=$1
        ;;
      -T=*|--topic=*)
        topic_name=${1#*=}
        ;;
      --regex)
        shift
        if [ $# -eq 0 ]; then
          zshmq_log_error 'topic %s: --regex requires a value' "$subcommand"
          return 1
        fi
        topic_regex=$1
        ;;
      --regex=*)
        topic_regex=${1#*=}
        ;;
      --)
        shift
        break
        ;;
      -*)
        zshmq_log_error 'topic %s: unexpected option -- %s' "$subcommand" "$1"
        return 1
        ;;
      *)
        zshmq_log_error 'topic %s: unexpected argument -- %s' "$subcommand" "$1"
        return 1
        ;;
    esac
    shift
  done

  if [ $# -gt 0 ]; then
    zshmq_log_error 'topic %s: unexpected argument -- %s' "$subcommand" "$1"
    return 1
  fi

  if [ -z "${topic_name:-}" ]; then
    zshmq_log_error 'topic %s: --topic is required' "$subcommand"
    return 1
  fi

  case $topic_name in
    *'|'*)
      zshmq_log_error 'topic %s: topic must not contain "|"' "$subcommand"
      return 1
      ;;
    *'	'*)
      zshmq_log_error 'topic %s: topic must not contain tabs' "$subcommand"
      return 1
      ;;
    *'/'*)
      zshmq_log_error 'topic %s: topic must not contain "/"' "$subcommand"
      return 1
      ;;
    *'
'*)
      zshmq_log_error 'topic %s: topic must not contain newlines' "$subcommand"
      return 1
      ;;
    *' '*)
      zshmq_log_error 'topic %s: topic must not contain spaces' "$subcommand"
      return 1
      ;;
  esac

  TOPIC_NAME=$topic_name
  TOPIC_REGEX=$topic_regex
}

topic_ensure_runtime() {
  path=$1
  zshmq_ensure_runtime_exists "$path" "topic"
}

topic_new() {
  runtime_root=$1
  topic_name=$2
  topic_regex=${3-}

  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic_name}.state}
  topic_fifo_path=${ZSHMQ_TOPIC:-${runtime_root}/${topic_name}.fifo}

  case $state_path in
    */*)
      state_dir=${state_path%/*}
      ;;
    *)
      state_dir=.
      ;;
  esac
  if [ "$state_dir" != "." ] && [ ! -d "$state_dir" ]; then
    mkdir -p "$state_dir"
  fi

  if [ -e "$state_path" ] && [ ! -f "$state_path" ]; then
    zshmq_log_error 'topic new: state path is not a regular file: %s' "$state_path"
    return 1
  fi
  : > "$state_path"

  case $topic_fifo_path in
    */*)
      topic_dir=${topic_fifo_path%/*}
      ;;
    *)
      topic_dir=.
      ;;
  esac
  if [ "$topic_dir" != "." ] && [ ! -d "$topic_dir" ]; then
    mkdir -p "$topic_dir"
  fi

  if [ -e "$topic_fifo_path" ]; then
    if [ -p "$topic_fifo_path" ]; then
      rm -f "$topic_fifo_path"
    else
      zshmq_log_error 'topic new: topic FIFO path is not a FIFO: %s' "$topic_fifo_path"
      return 1
    fi
  fi

  if ! mkfifo "$topic_fifo_path"; then
    zshmq_log_error 'topic new: failed to create fifo at %s' "$topic_fifo_path"
    return 1
  fi

  topic_registry_upsert "$runtime_root" "$topic_name" "$topic_regex"

  zshmq_log_debug 'topic new: initialised topic=%s runtime=%s' "$topic_name" "$runtime_root"
}

topic_destroy() {
  runtime_root=$1
  topic_name=$2
  topic_regex=${3-}

  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic_name}.state}
  topic_fifo_path=${ZSHMQ_TOPIC:-${runtime_root}/${topic_name}.fifo}

  if [ -f "$state_path" ]; then
    rm -f "$state_path"
    zshmq_log_debug 'topic destroy: removed state=%s' "$state_path"
  else
    zshmq_log_trace 'topic destroy: state missing (%s)' "$state_path"
  fi

  if [ -p "$topic_fifo_path" ] || [ -f "$topic_fifo_path" ]; then
    rm -f "$topic_fifo_path"
    zshmq_log_debug 'topic destroy: removed fifo=%s' "$topic_fifo_path"
  else
    zshmq_log_trace 'topic destroy: fifo missing (%s)' "$topic_fifo_path"
  fi

  if topic_registry_remove "$runtime_root" "$topic_name"; then
    zshmq_log_debug 'topic destroy: removed registry entry topic=%s' "$topic_name"
  else
    zshmq_log_trace 'topic destroy: registry entry missing topic=%s' "$topic_name"
  fi
}

# Dispatcher helper functions now use shared utilities from command_helpers.sh

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
            zshmq_prune_state_file "$state_path" "dispatcher"
          fi
          zshmq_log_trace 'dispatcher: topic=%s message=%s' "$topic" "$message_body"
          while IFS= read -r fifo_path || [ -n "$fifo_path" ]; do
            [ -n "$fifo_path" ] || continue
            fifo_pid=$(zshmq_extract_fifo_pid "$fifo_path") || continue
            if ! zshmq_is_process_running "$fifo_pid"; then
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

#/**
# topic start - Launch the dispatcher loop for a topic.
# @usage: zshmq topic start --topic TOPIC [--path PATH]
# @summary: Spawn the topic dispatcher (default runtime: /tmp/zshmq) in the background.
# @description: Validates a runtime directory created by `ctx new`, then spawns the dispatcher loop so publishers and subscribers can exchange messages via the topic FIFO. Supports foreground mode for debugging.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name handled by this dispatcher.
# @option: -f, --foreground   Run the dispatcher in the foreground.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

topic_start_parser_definition() {
  zshmq_parser_defaults
  param TOPIC_START_CTX_PATH -p --path -- 'Runtime directory to target'
  param TOPIC_START_TOPIC -T --topic -- 'Topic name handled by this dispatcher'
  flag TOPIC_START_FOREGROUND -f --foreground -- 'Run the dispatcher in the foreground'
}

topic_start_cmd() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'topic start: ZSHMQ_ROOT is not set'
      return 1
    fi
    # shellcheck source=../vendor/getoptions/lib/getoptions_base.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_abbr.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_help.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  unset TOPIC_START_FOREGROUND || :

  set +e
  zshmq_eval_parser topic_start topic_start_parser_definition "$@"
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
    zshmq_log_error 'topic start: unexpected argument -- %s' "$1"
    return 1
  fi

  unset ZSHMQ_REST || :

  topic=${TOPIC_START_TOPIC:-}
  if [ -z "$topic" ]; then
    zshmq_log_error 'topic start: --topic is required'
    return 1
  fi

  target=${TOPIC_START_CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'topic start: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'topic start: refusing to operate on root directory'
      return 1
      ;;
  esac

  runtime_root=${target%/}
  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic}.state}
  topic_fifo_path=${ZSHMQ_TOPIC:-${runtime_root}/${topic}.fifo}
  pid_path=${ZSHMQ_TOPIC_PID:-${ZSHMQ_DISPATCH_PID:-${runtime_root}/${topic}.pid}}

  if [ ! -d "$target" ]; then
    zshmq_log_error 'topic start: runtime directory not found: %s' "$target"
    return 1
  fi

  if [ ! -p "$topic_fifo_path" ]; then
    zshmq_log_error 'topic start: topic FIFO not found at %s' "$topic_fifo_path"
    return 1
  fi

  if [ ! -f "$state_path" ]; then
    zshmq_log_error 'topic start: state file not found at %s' "$state_path"
    return 1
  fi

  if existing_pid=$(zshmq_check_dispatcher_running "$pid_path" 2>/dev/null); then
    zshmq_log_debug 'topic start: dispatcher already running (pid=%s)' "$existing_pid"
    return 1
  fi

  if [ "${TOPIC_START_FOREGROUND:-0}" = "1" ]; then
    zshmq_dispatch_loop "$topic_fifo_path" "$state_path" &
    dispatcher_pid=$!
    printf '%s\n' "$dispatcher_pid" > "$pid_path"
    zshmq_log_debug 'topic start: dispatcher started (pid=%s)' "$dispatcher_pid"

    topic_start_cleaned=0

    topic_start_cleanup() {
      if [ "${topic_start_cleaned}" -eq 1 ]; then
        return 0
      fi
      topic_start_cleaned=1
      trap - INT TERM HUP EXIT
      if [ -n "${dispatcher_pid:-}" ] && kill -0 "$dispatcher_pid" 2>/dev/null; then
        kill "$dispatcher_pid" 2>/dev/null || :
        wait "$dispatcher_pid" 2>/dev/null || :
      else
        wait "$dispatcher_pid" 2>/dev/null || :
      fi
      rm -f "$pid_path"
    }

    trap 'topic_start_cleanup; exit 130' INT
    trap 'topic_start_cleanup; exit 143' TERM
    trap 'topic_start_cleanup; exit 129' HUP
    trap 'topic_start_cleanup' EXIT

    wait "$dispatcher_pid"
    wait_status=$?
    topic_start_cleanup
    return "$wait_status"
  fi

  zshmq_dispatch_loop "$topic_fifo_path" "$state_path" &
  dispatcher_pid=$!
  printf '%s\n' "$dispatcher_pid" > "$pid_path"
  zshmq_log_debug 'topic start: dispatcher started (pid=%s)' "$dispatcher_pid"
}

#/**
# topic stop - Terminate the dispatcher loop for a topic.
# @usage: zshmq topic stop --topic TOPIC [--path PATH]
# @summary: Stop the dispatcher that serves a topic and remove its PID file.
# @description: Looks up the dispatcher PID for the requested topic (or via environment overrides), sends a termination signal, waits briefly for shutdown, and cleans up PID artifacts. No-op when the dispatcher is already stopped.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name whose dispatcher should be stopped.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

topic_stop_parser_definition() {
  zshmq_parser_defaults
  param TOPIC_STOP_CTX_PATH -p --path -- 'Runtime directory to target'
  param TOPIC_STOP_TOPIC -T --topic -- 'Topic name whose dispatcher should be stopped'
}

topic_stop_cmd() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'topic stop: ZSHMQ_ROOT is not set'
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
  zshmq_eval_parser topic_stop topic_stop_parser_definition "$@"
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
    zshmq_log_error 'topic stop: unexpected argument -- %s' "$1"
    return 1
  fi

  unset ZSHMQ_REST || :

  topic=${TOPIC_STOP_TOPIC:-}
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
    zshmq_log_error 'topic stop: --topic is required'
    return 1
  fi

  target=${TOPIC_STOP_CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'topic stop: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'topic stop: refusing to operate on root directory'
      return 1
      ;;
  esac

  runtime_root=${target%/}
  pid_env=${ZSHMQ_TOPIC_PID:-${ZSHMQ_DISPATCH_PID:-}}
  if [ -n "$pid_env" ]; then
    pid_path=$pid_env
  elif [ -n "$pid_override" ]; then
    pid_path=$pid_override
  else
    pid_path=${runtime_root}/${topic}.pid
  fi

  dispatcher_pid=$(zshmq_check_dispatcher_running "$pid_path" 2>/dev/null) || {
    zshmq_log_debug 'topic stop: dispatcher is not running.'
    return 0
  }

  kill "$dispatcher_pid" 2>/dev/null || :

  if ! zshmq_wait_for_process_termination "$dispatcher_pid" 5; then
    zshmq_log_error 'topic stop: dispatcher (pid=%s) did not terminate' "$dispatcher_pid"
    return 1
  fi

  rm -f "$pid_path"
  zshmq_log_debug 'topic stop: dispatcher stopped (pid=%s)' "$dispatcher_pid"
}

#/**
# topic send - Publish a message to the zshmq dispatcher.
# @usage: zshmq topic send --topic TOPIC [--path PATH] MESSAGE...
# @summary: Publish a message through the dispatcher FIFO.
# @description: Validate the runtime directory, ensure the dispatcher is running, and write the message to the topic-specific FIFO so subscribers receive it.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name for the published message (required).
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

topic_send_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to target'
  param TOPIC_SEND_TOPIC -T --topic -- 'Explicit topic to apply'
}

topic_send_trim() {
  # Trim leading and trailing whitespace in a POSIX-safe way.
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

topic_send_cmd() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'topic send: ZSHMQ_ROOT is not set'
      return 1
    fi
    # shellcheck source=../vendor/getoptions/lib/getoptions_base.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_abbr.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_help.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  # shellcheck disable=SC2034
  ZSHMQ_PARSER_USAGE='zshmq topic send --topic TOPIC [--path PATH] MESSAGE...'

  set +e
  zshmq_eval_parser topic_send topic_send_parser_definition "$@"
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

  topic=${TOPIC_SEND_TOPIC:-}
  if [ -z "$topic" ]; then
    zshmq_log_error 'topic send: --topic is required'
    return 1
  fi

  if [ $# -eq 0 ]; then
    zshmq_log_error 'topic send: message is required'
    return 1
  fi

  message=$1
  shift
  if [ $# -gt 0 ]; then
    message="$message $*"
  fi

  topic=$(topic_send_trim "$topic")
  if [ -z "$topic" ]; then
    zshmq_log_error 'topic send: topic must not be empty'
    return 1
  fi

  case $topic in
    *'|'*)
      zshmq_log_error 'topic send: topic must not contain "|"'
      return 1
      ;;
  esac

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  runtime_root=$(zshmq_ensure_runtime_exists "$target" "topic send") || return 1

  topic_fifo_path=${ZSHMQ_TOPIC:-${runtime_root}/${topic}.fifo}
  pid_path=${ZSHMQ_TOPIC_PID:-${ZSHMQ_DISPATCH_PID:-${runtime_root}/${topic}.pid}}

  if [ ! -p "$topic_fifo_path" ]; then
    zshmq_log_error 'topic send: topic FIFO not found at %s' "$topic_fifo_path"
    return 1
  fi

  if ! zshmq_check_dispatcher_running "$pid_path" >/dev/null 2>&1; then
    zshmq_log_error 'topic send: dispatcher is not running'
    return 1
  fi

  zshmq_log_trace 'topic send: topic=%s message=%s' "$topic" "$message"
  printf 'PUB|%s|%s\n' "$topic" "$message" > "$topic_fifo_path"
}

#/**
# topic sub - Subscribe to messages for a specific topic.
# @usage: zshmq topic sub --topic TOPIC [--path PATH]
# @summary: Register a subscriber FIFO and stream dispatched messages for TOPIC.
# @description: Validate the runtime directory, ensure the dispatcher is running, register the subscription with the dispatcher, and stream messages until interrupted.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -T, --topic TOPIC  Topic name to subscribe to.
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

topic_sub_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to target'
  param TOPIC_SUB_TOPIC -T --topic -- 'Topic name to subscribe to'
}

topic_sub_cleanup() {
  if [ "${TOPIC_SUB_CLEANED:-0}" -eq 1 ]; then
    return 0
  fi
  TOPIC_SUB_CLEANED=1

  if [ -n "${TOPIC_SUB_FIFO_FD:-}" ]; then
    eval "exec ${TOPIC_SUB_FIFO_FD}>&-" 2>/dev/null || :
  fi

  if [ "${TOPIC_SUB_REGISTERED:-0}" -eq 1 ] && [ -n "${TOPIC_SUB_TOPIC_FIFO_PATH:-}" ] && [ -n "${TOPIC_SUB_FIFO_PATH:-}" ]; then
    if [ -n "${TOPIC_SUB_DISPATCHER_PID:-}" ] && kill -0 "$TOPIC_SUB_DISPATCHER_PID" 2>/dev/null; then
      { printf 'UNSUB|%s\n' "$TOPIC_SUB_FIFO_PATH"; } > "$TOPIC_SUB_TOPIC_FIFO_PATH" 2>/dev/null || :
    fi
    TOPIC_SUB_REGISTERED=0
  fi

  if [ -n "${TOPIC_SUB_STATE_PATH:-}" ] && [ -f "${TOPIC_SUB_STATE_PATH:-}" ]; then
    tmp_state="${TOPIC_SUB_STATE_PATH}.tmp.$$"
    : > "$tmp_state"
    while IFS= read -r state_line || [ -n "$state_line" ]; do
      [ -n "$state_line" ] || continue
      state_fifo=$state_line
      if [ "$state_fifo" = "${TOPIC_SUB_FIFO_PATH:-}" ]; then
        rm -f "$state_fifo" 2>/dev/null || :
        continue
      fi
      fifo_pid=$(zshmq_extract_fifo_pid "$state_fifo") || continue
      if zshmq_is_process_running "$fifo_pid"; then
        if [ -p "$state_fifo" ]; then
          printf '%s\n' "$state_fifo" >> "$tmp_state"
        fi
      else
        rm -f "$state_fifo" 2>/dev/null || :
      fi
    done < "${TOPIC_SUB_STATE_PATH}"
    mv "$tmp_state" "${TOPIC_SUB_STATE_PATH}"
  fi

  if [ -n "${TOPIC_SUB_FIFO_PATH:-}" ] && [ -e "$TOPIC_SUB_FIFO_PATH" ]; then
    rm -f "$TOPIC_SUB_FIFO_PATH" 2>/dev/null || :
  fi
}

topic_sub_cmd() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'topic sub: ZSHMQ_ROOT is not set'
      return 1
    fi
    # shellcheck source=../vendor/getoptions/lib/getoptions_base.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_abbr.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck source=../vendor/getoptions/lib/getoptions_help.sh
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  # shellcheck disable=SC2034
  ZSHMQ_PARSER_USAGE='zshmq topic sub --topic TOPIC [--path PATH]'

  set +e
  zshmq_eval_parser topic_sub topic_sub_parser_definition "$@"
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
    zshmq_log_error 'topic sub: unexpected argument -- %s' "$1"
    return 1
  fi

  topic=${TOPIC_SUB_TOPIC:-}
  if [ -z "$topic" ]; then
    zshmq_log_error 'topic sub: --topic is required'
    return 1
  fi

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  runtime_root=$(zshmq_ensure_runtime_exists "$target" "topic sub") || return 1
  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic}.state}
  topic_fifo_path=${ZSHMQ_TOPIC:-${runtime_root}/${topic}.fifo}
  pid_path=${ZSHMQ_TOPIC_PID:-${ZSHMQ_DISPATCH_PID:-${runtime_root}/${topic}.pid}}

  if [ ! -f "$state_path" ]; then
    zshmq_log_error 'topic sub: state file not found at %s' "$state_path"
    return 1
  fi

  if [ ! -p "$topic_fifo_path" ]; then
    zshmq_log_error 'topic sub: topic FIFO not found at %s' "$topic_fifo_path"
    return 1
  fi

  if [ ! -f "$pid_path" ]; then
    zshmq_log_error 'topic sub: dispatcher pid file not found at %s' "$pid_path"
    return 1
  fi

  dispatcher_pid=$(zshmq_check_dispatcher_running "$pid_path") || {
    zshmq_log_error 'topic sub: dispatcher is not running'
    return 1
  }

  TOPIC_SUB_DISPATCHER_PID=$dispatcher_pid

  fifo_path=${runtime_root}/${topic}.$$
  if [ -e "$fifo_path" ]; then
    zshmq_log_error 'topic sub: subscriber fifo already exists at %s' "$fifo_path"
    return 1
  fi

  if ! mkfifo "$fifo_path"; then
    zshmq_log_error 'topic sub: failed to create fifo at %s' "$fifo_path"
    return 1
  fi

  TOPIC_SUB_TOPIC_FIFO_PATH=$topic_fifo_path
  TOPIC_SUB_FIFO_PATH=$fifo_path
  TOPIC_SUB_FIFO_FD=9
  TOPIC_SUB_CLEANED=0
  TOPIC_SUB_REGISTERED=0
  TOPIC_SUB_STATE_PATH=$state_path

  if [ -s "$state_path" ]; then
    zshmq_prune_state_file "$state_path" "sub"
  fi

  trap 'topic_sub_cleanup; exit 130' INT
  trap 'topic_sub_cleanup; exit 143' TERM
  trap 'topic_sub_cleanup; exit 129' HUP
  trap 'topic_sub_cleanup' EXIT

  if ! { printf 'SUB|%s\n' "$fifo_path"; } > "$topic_fifo_path"; then
    zshmq_log_error 'topic sub: failed to register with dispatcher'
    topic_sub_cleanup
    return 1
  fi
  TOPIC_SUB_REGISTERED=1

  if ! exec 9<>"$fifo_path"; then
    zshmq_log_error 'topic sub: unable to open fifo for reading'
    topic_sub_cleanup
    return 1
  fi

  zshmq_log_debug 'topic sub: subscribed to topic=%s fifo=%s' "$topic" "$fifo_path"

  while IFS= read -r line <&9 || [ -n "$line" ]; do
    zshmq_log_trace 'topic sub: received topic=%s message=%s' "$topic" "$line"
    printf '%s\n' "$line"
  done

  topic_sub_cleanup
}

topic() {
  set -eu

  log_level=${ZSHMQ_LOG_LEVEL:-INFO}
  target_path=${ZSHMQ_CTX_ROOT:-/tmp/zshmq}
  target_overridden=0

  export ZSHMQ_LOG_LEVEL="$log_level"

  while [ $# -gt 0 ]; do
    case $1 in
      -p|--path)
        shift
        if [ $# -eq 0 ]; then
          zshmq_log_error 'topic: --path requires a value'
          return 1
        fi
        target_path=$1
        target_overridden=1
        ;;
      -p=*|--path=*)
        target_path=${1#*=}
        target_overridden=1
        ;;
      -d|--debug)
        log_level=DEBUG
        ;;
      -t|--trace)
        log_level=TRACE
        ;;
      -h|--help|help)
        topic_print_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        zshmq_log_error 'topic: unexpected option -- %s' "$1"
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
    topic_print_usage
    return 1
  fi

  subcommand=$1
  shift

  case $subcommand in
    new)
      runtime_root=$(topic_ensure_runtime "$target_path") || return 1
      unset TOPIC_REGEX || :
      unset TOPIC_NAME || :
      topic_require_topic "$subcommand" "$@" || return 1
      topic_name=${TOPIC_NAME-}
      topic_regex=${TOPIC_REGEX-}
      topic_new "$runtime_root" "$topic_name" "$topic_regex"
      ;;
    destroy)
      runtime_root=$(topic_ensure_runtime "$target_path") || return 1
      unset TOPIC_REGEX || :
      unset TOPIC_NAME || :
      topic_require_topic "$subcommand" "$@" || return 1
      topic_name=${TOPIC_NAME-}
      topic_regex=${TOPIC_REGEX-}
      topic_destroy "$runtime_root" "$topic_name" "$topic_regex"
      ;;
    start)
      if [ "$target_overridden" -eq 1 ]; then
        topic_start_cmd --path "$target_path" "$@"
      else
        topic_start_cmd "$@"
      fi
      ;;
    stop)
      if [ "$target_overridden" -eq 1 ]; then
        topic_stop_cmd --path "$target_path" "$@"
      else
        topic_stop_cmd "$@"
      fi
      ;;
    send)
      if [ "$target_overridden" -eq 1 ]; then
        topic_send_cmd --path "$target_path" "$@"
      else
        topic_send_cmd "$@"
      fi
      ;;
    sub)
      if [ "$target_overridden" -eq 1 ]; then
        topic_sub_cmd --path "$target_path" "$@"
      else
        topic_sub_cmd "$@"
      fi
      ;;
    -h|--help|help)
      topic_print_usage
      return 0
      ;;
    *)
      zshmq_log_error 'topic: unknown command -- %s' "$subcommand"
      topic_print_usage
      return 1
      ;;
  esac
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command topic
fi
