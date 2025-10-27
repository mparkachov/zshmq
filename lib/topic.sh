#!/usr/bin/env sh
# shellcheck shell=sh

#/**
# topic - Manage topic assets within a runtime directory.
# @usage: zshmq topic <command> [options]
# @summary: Manage topic FIFOs and state files.
# @description: Provides subcommands to provision or remove the FIFO/state pair used by publishers and subscribers for a topic.
# @option: -p, --path PATH    Runtime directory to target (defaults to $ZSHMQ_CTX_ROOT or /tmp/zshmq).
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
}

topic_require_topic() {
  subcommand=$1
  shift

  topic_name=

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
    *'/'*)
      zshmq_log_error 'topic %s: topic must not contain "/"' "$subcommand"
      return 1
      ;;
    *'
'*)
      zshmq_log_error 'topic %s: topic must not contain newlines' "$subcommand"
      return 1
      ;;
  esac

  printf '%s\n' "$topic_name"
}

topic_ensure_runtime() {
  path=$1

  if [ -z "$path" ]; then
    zshmq_log_error 'topic: target path is empty'
    return 1
  fi

  case $path in
    /|'')
      zshmq_log_error 'topic: refusing to operate on root directory'
      return 1
      ;;
  esac

  if [ ! -d "$path" ]; then
    zshmq_log_error 'topic: runtime directory not found: %s' "$path"
    return 1
  fi

  printf '%s\n' "${path%/}"
}

topic_new() {
  runtime_root=$1
  topic_name=$2

  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic_name}.state}
  bus_path=${ZSHMQ_BUS:-${runtime_root}/${topic_name}.topic}

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
      zshmq_log_error 'topic new: bus path is not a FIFO: %s' "$bus_path"
      return 1
    fi
  fi

  if ! mkfifo "$bus_path"; then
    zshmq_log_error 'topic new: failed to create fifo at %s' "$bus_path"
    return 1
  fi

  zshmq_log_debug 'topic new: initialised topic=%s runtime=%s' "$topic_name" "$runtime_root"
}

topic_destroy() {
  runtime_root=$1
  topic_name=$2

  state_path=${ZSHMQ_STATE:-${runtime_root}/${topic_name}.state}
  bus_path=${ZSHMQ_BUS:-${runtime_root}/${topic_name}.topic}

  if [ -f "$state_path" ]; then
    rm -f "$state_path"
    zshmq_log_debug 'topic destroy: removed state=%s' "$state_path"
  else
    zshmq_log_trace 'topic destroy: state missing (%s)' "$state_path"
  fi

  if [ -p "$bus_path" ] || [ -f "$bus_path" ]; then
    rm -f "$bus_path"
    zshmq_log_debug 'topic destroy: removed fifo=%s' "$bus_path"
  else
    zshmq_log_trace 'topic destroy: fifo missing (%s)' "$bus_path"
  fi
}

topic() {
  set -eu

  log_level=${ZSHMQ_LOG_LEVEL:-INFO}
  target_path=${ZSHMQ_CTX_ROOT:-/tmp/zshmq}

  export ZSHMQ_LOG_LEVEL=$log_level

  while [ $# -gt 0 ]; do
    case $1 in
      -p|--path)
        shift
        if [ $# -eq 0 ]; then
          zshmq_log_error 'topic: --path requires a value'
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

  export ZSHMQ_LOG_LEVEL=$log_level

  if [ $# -eq 0 ]; then
    topic_print_usage
    return 1
  fi

  subcommand=$1
  shift

  runtime_root=$(topic_ensure_runtime "$target_path") || return 1

  case $subcommand in
    new)
      topic_name=$(topic_require_topic "$subcommand" "$@") || return 1
      topic_new "$runtime_root" "$topic_name"
      ;;
    destroy)
      topic_name=$(topic_require_topic "$subcommand" "$@") || return 1
      topic_destroy "$runtime_root" "$topic_name"
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
