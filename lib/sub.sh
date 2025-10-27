#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# sub - Subscribe to messages that match a topic pattern.
# @usage: zshmq sub [--path PATH] PATTERN
# @summary: Register a subscriber FIFO and print dispatched messages for PATTERN.
# @description: Validate the runtime directory, ensure the dispatcher is running, register the subscription with the dispatcher, and stream matching messages until interrupted.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

sub_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to target'
}

sub_extract_fifo_pid() {
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

sub_prune_state() {
  state_path=$1
  tmp_state="${state_path}.prune.$$"
  : > "$tmp_state"
  while IFS='|' read -r existing_pattern existing_fifo || [ -n "$existing_pattern" ]; do
    [ -n "$existing_pattern" ] || continue
    [ -n "$existing_fifo" ] || continue
    fifo_pid=$(sub_extract_fifo_pid "$existing_fifo")
    if [ -n "$fifo_pid" ] && kill -0 "$fifo_pid" 2>/dev/null; then
      if [ -p "$existing_fifo" ]; then
        printf '%s|%s\n' "$existing_pattern" "$existing_fifo" >> "$tmp_state"
      fi
    else
      rm -f "$existing_fifo" 2>/dev/null || :
    fi
  done < "$state_path"
  mv "$tmp_state" "$state_path"
}

sub_cleanup() {
  if [ "${SUB_CLEANED:-0}" -eq 1 ]; then
    return 0
  fi
  SUB_CLEANED=1

  if [ -n "${SUB_FIFO_FD:-}" ]; then
    eval "exec ${SUB_FIFO_FD}>&-" 2>/dev/null || :
  fi

  if [ "${SUB_REGISTERED:-0}" -eq 1 ] && [ -n "${SUB_BUS_PATH:-}" ] && [ -n "${SUB_PATTERN:-}" ] && [ -n "${SUB_FIFO_PATH:-}" ]; then
    if [ -n "${SUB_DISPATCHER_PID:-}" ] && kill -0 "$SUB_DISPATCHER_PID" 2>/dev/null; then
      { printf 'UNSUB|%s|%s\n' "$SUB_PATTERN" "$SUB_FIFO_PATH"; } > "$SUB_BUS_PATH" 2>/dev/null || :
    fi
    SUB_REGISTERED=0
  fi

  if [ -n "${SUB_STATE_PATH:-}" ] && [ -f "${SUB_STATE_PATH:-}" ]; then
    tmp_state="${SUB_STATE_PATH}.tmp.$$"
    : > "$tmp_state"
    while IFS= read -r state_line || [ -n "$state_line" ]; do
      [ -n "$state_line" ] || continue
      state_pattern=${state_line%%|*}
      state_fifo=${state_line#*|}
      if [ "${state_pattern}|${state_fifo}" = "${SUB_PATTERN:-}|${SUB_FIFO_PATH:-}" ]; then
        rm -f "$state_fifo" 2>/dev/null || :
        continue
      fi
      fifo_pid=$(sub_extract_fifo_pid "$state_fifo")
      if [ -n "$fifo_pid" ] && kill -0 "$fifo_pid" 2>/dev/null; then
        if [ -p "$state_fifo" ]; then
          printf '%s|%s\n' "$state_pattern" "$state_fifo" >> "$tmp_state"
        fi
      else
        rm -f "$state_fifo" 2>/dev/null || :
      fi
    done < "${SUB_STATE_PATH}"
    mv "$tmp_state" "${SUB_STATE_PATH}"
  fi

  if [ -n "${SUB_FIFO_PATH:-}" ] && [ -e "$SUB_FIFO_PATH" ]; then
    rm -f "$SUB_FIFO_PATH" 2>/dev/null || :
  fi
}

sub() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      zshmq_log_error 'sub: ZSHMQ_ROOT is not set'
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
  zshmq_eval_parser sub sub_parser_definition "$@"
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
    zshmq_log_error 'sub: pattern is required'
    return 1
  fi

  pattern=$1
  shift || :

  if [ $# -gt 0 ]; then
    zshmq_log_error 'sub: unexpected argument -- %s' "$1"
    return 1
  fi

  if [ -z "$pattern" ]; then
    zshmq_log_error 'sub: pattern must not be empty'
    return 1
  fi

  case $pattern in
    *'|'*)
      zshmq_log_error 'sub: pattern must not contain "|"'
      return 1
      ;;
  esac

  case $pattern in
    *'
'*)
      zshmq_log_error 'sub: pattern must not contain newlines'
      return 1
      ;;
  esac

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'sub: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'sub: refusing to operate on root directory'
      return 1
      ;;
  esac

  if [ ! -d "$target" ]; then
    zshmq_log_error 'sub: runtime directory not found: %s' "$target"
    return 1
  fi

  runtime_root=${target%/}
  state_path=${ZSHMQ_STATE:-${runtime_root}/state}
  bus_path=${ZSHMQ_BUS:-${runtime_root}/bus}
  pid_path=${ZSHMQ_DISPATCH_PID:-${runtime_root}/dispatcher.pid}

  if [ ! -f "$state_path" ]; then
    zshmq_log_error 'sub: state file not found at %s' "$state_path"
    return 1
  fi

  if [ ! -p "$bus_path" ]; then
    zshmq_log_error 'sub: bus FIFO not found at %s' "$bus_path"
    return 1
  fi

  if [ ! -f "$pid_path" ]; then
    zshmq_log_error 'sub: dispatcher pid file not found at %s' "$pid_path"
    return 1
  fi

  dispatcher_pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
  if [ -z "$dispatcher_pid" ] || ! kill -0 "$dispatcher_pid" 2>/dev/null; then
    zshmq_log_error 'sub: dispatcher is not running'
    return 1
  fi

  SUB_DISPATCHER_PID=$dispatcher_pid

  fifo_path=${runtime_root}/sub.$$
  if [ -e "$fifo_path" ]; then
    zshmq_log_error 'sub: subscriber fifo already exists at %s' "$fifo_path"
    return 1
  fi

  if ! mkfifo "$fifo_path"; then
    zshmq_log_error 'sub: failed to create fifo at %s' "$fifo_path"
    return 1
  fi

  SUB_PATTERN=$pattern
  SUB_BUS_PATH=$bus_path
  SUB_FIFO_PATH=$fifo_path
  SUB_FIFO_FD=9
  SUB_CLEANED=0
  SUB_REGISTERED=0
  SUB_STATE_PATH=$state_path

  if [ -s "$state_path" ]; then
    sub_prune_state "$state_path"
  fi

  trap 'sub_cleanup; exit 130' INT
  trap 'sub_cleanup; exit 143' TERM
  trap 'sub_cleanup; exit 129' HUP
  trap 'sub_cleanup' EXIT

  if ! { printf 'SUB|%s|%s\n' "$pattern" "$fifo_path"; } > "$bus_path"; then
    zshmq_log_error 'sub: failed to register with dispatcher'
    sub_cleanup
    return 1
  fi
  SUB_REGISTERED=1

  if ! exec 9<>"$fifo_path"; then
    zshmq_log_error 'sub: unable to open fifo for reading'
    sub_cleanup
    return 1
  fi

  zshmq_log_debug 'sub: subscribed to pattern=%s fifo=%s' "$pattern" "$fifo_path"

  while IFS= read -r line <&9 || [ -n "$line" ]; do
    zshmq_log_trace 'sub: received pattern=%s message=%s' "$pattern" "$line"
    printf '%s\n' "$line"
  done

  sub_cleanup
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command sub
fi
