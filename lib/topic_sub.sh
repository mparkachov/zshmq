#!/usr/bin/env sh
# shellcheck shell=sh

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

# Subscriber helper functions now use shared utilities from command_helpers.sh

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

topic_sub() {
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
