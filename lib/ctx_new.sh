#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# ctx_new - Bootstrap the runtime directory used by zshmq commands.
# @usage: zshmq ctx_new [--path PATH]
# @summary: Bootstrap the runtime directory (default: /tmp/zshmq) and transport primitives.
# @description: Ensure the runtime root exists, reset the subscription state file, and recreate the main FIFO bus so other zshmq commands start from a clean slate.
# @option: -p, --path PATH    Target directory to initialise (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

ctx_new_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Target directory to initialise'
}

ctx_new() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ] ; then
      zshmq_log_error 'ctx_new: ZSHMQ_ROOT is not set'
      return 1
    fi
    # Load getoptions library from the vendored dependency.
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_base.sh"
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_abbr.sh"
    # shellcheck disable=SC1090
    . "${ZSHMQ_ROOT}/vendor/getoptions/lib/getoptions_help.sh"
  fi

  set +e
  zshmq_eval_parser ctx_new ctx_new_parser_definition "$@"
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
    zshmq_log_error 'ctx_new: unexpected argument -- %s' "$1"
    return 1
  fi

  unset ZSHMQ_REST ||:

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    zshmq_log_error 'ctx_new: target path is empty'
    return 1
  fi

  case $target in
    /|'')
      zshmq_log_error 'ctx_new: refusing to operate on root directory'
      return 1
      ;;
  esac

  if [ ! -d "$target" ]; then
    mkdir -p "$target"
  fi

  runtime_root=${target%/}
  state_path=${ZSHMQ_STATE:-${runtime_root}/state}
  bus_path=${ZSHMQ_BUS:-${runtime_root}/bus}

  if [ -z "$state_path" ]; then
    zshmq_log_error 'ctx_new: state path is empty'
    return 1
  fi

  if [ -z "$bus_path" ]; then
    zshmq_log_error 'ctx_new: bus path is empty'
    return 1
  fi

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
    zshmq_log_error 'ctx_new: state path is not a regular file: %s' "$state_path"
    return 1
  fi

  : > "$state_path"

  case $bus_path in
    */*)
      bus_dir=${bus_path%/*}
      ;;
    *)
      bus_dir=.
      ;;
  esac
  if [ "$bus_dir" != "." ] && [ ! -d "$bus_dir" ]; then
    mkdir -p "$bus_dir"
  fi

  if [ -e "$bus_path" ]; then
    if [ -p "$bus_path" ]; then
      rm -f "$bus_path"
    else
      zshmq_log_error 'ctx_new: bus path is not a FIFO: %s' "$bus_path"
      return 1
    fi
  fi

  mkfifo "$bus_path"

  printf '%s\n' "$target"
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command ctx_new
fi
