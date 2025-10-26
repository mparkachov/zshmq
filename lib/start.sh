#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# start - Launch the dispatcher loop for zshmq.
# @usage: zshmq start [--path PATH]
# @summary: Launch the dispatcher (default root: /tmp/zshmq) in the background.
# @description: Ensure the runtime directory is initialised, then spawn the dispatcher loop so publishers and subscribers can communicate via the main FIFO bus.
# @option: -p, --path PATH    Runtime directory to initialise (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -h, --help         Display command documentation and exit.
#*/

start_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Runtime directory to initialise'
}

zshmq_dispatch_loop() {
  bus_path=$1
  state_path=$2

  trap 'exec 3>&-; exit 0' INT TERM HUP

  # Keep the FIFO open even when no writers are connected.
  exec 3<>"$bus_path"

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
          while IFS='|' read -r pattern fifo_path; do
            [ -n "$pattern" ] || continue
            [ -n "$fifo_path" ] || continue
            if printf '%s\n' "$topic" | grep -E -- "$pattern" >/dev/null 2>&1; then
              if [ -p "$fifo_path" ]; then
                { printf '%s\n' "$message"; } >> "$fifo_path" 2>/dev/null || :
              fi
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

start() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      printf '%s\n' 'start: ZSHMQ_ROOT is not set' >&2
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
  zshmq_eval_parser start start_parser_definition "$@"
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
    printf 'start: unexpected argument -- %s\n' "$1" >&2
    return 1
  fi

  unset ZSHMQ_REST ||:

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    printf '%s\n' 'start: target path is empty' >&2
    return 1
  fi

  case $target in
    /|'')
      printf '%s\n' 'start: refusing to operate on root directory' >&2
      return 1
      ;;
  esac

  ctx_new --path "$target" >/dev/null

  runtime_root=${target%/}
  state_path=${ZSHMQ_STATE:-${runtime_root}/state}
  bus_path=${ZSHMQ_BUS:-${runtime_root}/bus}
  pid_path=${ZSHMQ_DISPATCH_PID:-${runtime_root}/dispatcher.pid}

  if [ ! -p "$bus_path" ]; then
    printf 'start: bus FIFO not found at %s\n' "$bus_path" >&2
    return 1
  fi

  if [ ! -f "$state_path" ]; then
    printf 'start: state file not found at %s\n' "$state_path" >&2
    return 1
  fi

  if [ -f "$pid_path" ]; then
    existing_pid=$(tr -d '\r\n' < "$pid_path" 2>/dev/null || :)
    if [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; then
      printf 'start: dispatcher already running (pid=%s)\n' "$existing_pid" >&2
      return 1
    fi
    rm -f "$pid_path"
  fi

  zshmq_dispatch_loop "$bus_path" "$state_path" &
  dispatcher_pid=$!
  printf '%s\n' "$dispatcher_pid" > "$pid_path"
  printf 'Dispatcher started (pid=%s)\n' "$dispatcher_pid"
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command start
fi
