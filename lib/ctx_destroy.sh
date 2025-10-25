#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# ctx_destroy - Remove the runtime directory created by ctx_new.
# @usage: zshmq ctx_destroy [--path PATH]
# @summary: Remove the runtime directory (default: /tmp/zshmq) and its state file.
# @description: Delete the state file created by ctx_new and remove the runtime directory if it is now empty.
# @option: -p, --path PATH    Target directory to remove (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -h, --help         Display command documentation and exit.
#*/

ctx_destroy_parser_definition() {
  zshmq_parser_defaults
  param CTX_PATH -p --path -- 'Target directory to remove'
}

ctx_destroy() {
  set -eu

  if ! command -v getoptions >/dev/null 2>&1; then
    if [ -z "${ZSHMQ_ROOT:-}" ]; then
      printf '%s\n' 'ctx_destroy: ZSHMQ_ROOT is not set' >&2
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
  zshmq_eval_parser ctx_destroy ctx_destroy_parser_definition "$@"
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
    printf 'ctx_destroy: unexpected argument -- %s\n' "$1" >&2
    return 1
  fi

  unset ZSHMQ_REST ||:

  target=${CTX_PATH:-${ZSHMQ_CTX_ROOT:-/tmp/zshmq}}

  if [ -z "$target" ]; then
    printf '%s\n' 'ctx_destroy: target path is empty' >&2
    return 1
  fi

  case $target in
    /|'')
      printf '%s\n' 'ctx_destroy: refusing to operate on root directory' >&2
      return 1
      ;;
  esac

  if [ -d "$target" ]; then
    if [ -f "${target%/}/state" ]; then
      rm -f "${target%/}/state"
    fi
    remaining=$(find "$target" -mindepth 1 -maxdepth 1 -not -name '.' -not -name '..' -print -quit 2>/dev/null || :)
    if [ -z "${remaining:-}" ]; then
      rmdir "$target" 2>/dev/null || :
    fi
  fi

  printf '%s\n' "$target"
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command ctx_destroy
fi
