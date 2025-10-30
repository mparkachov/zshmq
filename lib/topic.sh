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
  printf '  send     Publish a message      (-T/--topic required)\n'
  printf '  sub      Stream topic messages  (-T/--topic required)\n'
}

topic_registry_path() {
  runtime_root=$1
  printf '%s\n' "${runtime_root}/topics"
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
    entry_regex=
    case $registry_line in
      *'	'*)
        entry_topic=${registry_line%%	*}
        entry_regex=${registry_line#*	}
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
  esac

  TOPIC_NAME=$topic_name
  TOPIC_REGEX=$topic_regex
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

topic() {
  set -eu

  log_level=${ZSHMQ_LOG_LEVEL:-INFO}
  target_path=${ZSHMQ_CTX_ROOT:-/tmp/zshmq}
  target_overridden=0

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

  export ZSHMQ_LOG_LEVEL=$log_level

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
    send)
      if [ "$target_overridden" -eq 1 ]; then
        CTX_PATH=$target_path topic_send "$@"
      else
        topic_send "$@"
      fi
      ;;
    sub)
      if [ "$target_overridden" -eq 1 ]; then
        CTX_PATH=$target_path topic_sub "$@"
      else
        topic_sub "$@"
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
