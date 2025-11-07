#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# ctx - Manage the runtime directory used by zshmq commands.
# @usage: zshmq ctx <command> [options]
# @summary: Manage the runtime directory (default: /tmp/zshmq).
# @description: Provides subcommands to initialise (`ctx new`) or delete (`ctx destroy`) the runtime directory where FIFOs, state files, and dispatcher metadata live.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
# @option: -d, --debug        Enable DEBUG log level.
# @option: -t, --trace        Enable TRACE log level.
# @option: -h, --help         Display command documentation and exit.
#*/

ctx_print_usage() {
  printf '%s\n' 'Usage: zshmq ctx <command> [options]'
  printf '%s\n' ''
  printf '%s\n' 'Commands:'
  printf '  new      Initialise the runtime directory\n'
  printf '  destroy  Remove the runtime directory (use --force to ignore leftovers)\n'
}

ctx_resolve_target() {
  target=$1
  zshmq_validate_runtime_path "$target" "ctx"
}

ctx_new_impl() {
  runtime_root=$1

  if [ ! -d "$runtime_root" ]; then
    mkdir -p "$runtime_root"
  fi

  zshmq_log_debug 'ctx new: initialised runtime=%s' "$runtime_root"
}

ctx_destroy_impl() {
  runtime_root=$1
  force=$2

  if [ ! -d "$runtime_root" ]; then
    zshmq_log_debug 'ctx destroy: runtime not found (%s)' "$runtime_root"
    return 0
  fi

  if [ "$force" = "1" ]; then
    rm -rf "$runtime_root"
    zshmq_log_debug 'ctx destroy: forcefully removed runtime=%s' "$runtime_root"
    return 0
  fi

  pid_override=${ZSHMQ_TOPIC_PID:-${ZSHMQ_DISPATCH_PID:-}}
  if [ -n "$pid_override" ]; then
    pid_path=$pid_override
    if [ -f "$pid_path" ]; then
      rm -f "$pid_path"
      zshmq_log_debug 'ctx destroy: removed pid=%s' "$pid_path"
    else
      zshmq_log_trace 'ctx destroy: pid missing (%s)' "$pid_path"
    fi
  else
    removed_pid=0
    for candidate in "$runtime_root"/*.pid; do
      if [ -f "$candidate" ]; then
        rm -f "$candidate"
        zshmq_log_debug 'ctx destroy: removed pid=%s' "$candidate"
        removed_pid=1
      fi
    done
    if [ "$removed_pid" -eq 0 ]; then
      zshmq_log_trace 'ctx destroy: pid missing (%s/*.pid)' "$runtime_root"
    fi
  fi

  remaining=$(find "$runtime_root" -mindepth 1 -maxdepth 1 -not -name '.' -not -name '..' -print -quit 2>/dev/null || :)
  if [ -n "${remaining:-}" ]; then
    zshmq_log_error 'ctx destroy: runtime contains files; re-run with --force to remove %s' "$runtime_root"
    return 1
  fi

  if ! rmdir "$runtime_root" 2>/dev/null; then
    zshmq_log_error 'ctx destroy: failed to remove directory %s' "$runtime_root"
    return 1
  fi

  zshmq_log_debug 'ctx destroy: cleaned runtime=%s' "$runtime_root"
}

ctx() {
  set -eu

  log_level=${ZSHMQ_LOG_LEVEL:-INFO}
  target_path=${ZSHMQ_CTX_ROOT:-/tmp/zshmq}

  while [ $# -gt 0 ]; do
    case $1 in
      -p|--path)
        shift
        if [ $# -eq 0 ]; then
          zshmq_log_error 'ctx: --path requires a value'
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
        ctx_print_usage
        return 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        zshmq_log_error 'ctx: unexpected option -- %s' "$1"
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
    ctx_print_usage
    return 1
  fi

  subcommand=$1
  shift

  runtime_root=$(ctx_resolve_target "$target_path") || return 1

  case $subcommand in
    new)
      if [ $# -gt 0 ]; then
        zshmq_log_error 'ctx new: unexpected argument -- %s' "$1"
        return 1
      fi
      ctx_new_impl "$runtime_root"
      ;;
    destroy)
      force=0
      while [ $# -gt 0 ]; do
        case $1 in
          -f|--force)
            force=1
            ;;
          -h|--help|help)
            ctx_print_usage
            return 0
            ;;
          --)
            shift
            break
            ;;
          -*)
            zshmq_log_error 'ctx destroy: unexpected option -- %s' "$1"
            return 1
            ;;
          *)
            zshmq_log_error 'ctx destroy: unexpected argument -- %s' "$1"
            return 1
            ;;
        esac
        shift || :
      done

      if [ $# -gt 0 ]; then
        zshmq_log_error 'ctx destroy: unexpected argument -- %s' "$1"
        return 1
      fi

      ctx_destroy_impl "$runtime_root" "$force"
      ;;
    *)
      zshmq_log_error 'ctx: unknown command -- %s' "$subcommand"
      ctx_print_usage
      return 1
      ;;
  esac
}

if command -v zshmq_register_command >/dev/null 2>&1; then
  zshmq_register_command ctx
fi
