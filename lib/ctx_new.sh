#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# ctx_new - Bootstrap the runtime directory used by zshmq commands.
# @usage: zshmq ctx_new [--path PATH]
# @summary: Bootstrap the runtime directory (default: /tmp/zshmq).
# @description: Bootstrap the runtime directory so other zshmq commands can operate on a known path.
# @option: -p, --path PATH    Target directory to initialise (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -h, --help         Display command documentation and exit.
#*/

ctx_new_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Target directory to initialise'
}

ctx_new() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      printf '%s\n' 'ctx_new: ZSHMQ_ROOT is not set' >&2
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
    printf 'ctx_new: unexpected argument -- %s\n' "$1" >&2
    return 1
  fi

  unset ZSHMQ_REST ||:

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    printf '%s\n' 'ctx_new: target path is empty' >&2
    return 1
  fi

  if [ ! -d "$target" ]; then
    mkdir -p "$target"
  fi

  state_file="${target%/}/state"
  if [ ! -f "$state_file" ]; then
    : > "$state_file"
  fi

  printf '%s\n' "$target"
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command ctx_new
fi
