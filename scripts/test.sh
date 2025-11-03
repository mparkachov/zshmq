#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

: "${SHELLSPEC:=vendor/shellspec/shellspec}"
: "${SHELLSPEC_SHELL:=/bin/sh}"
SHELLSPEC_FLAGS=${SHELLSPEC_FLAGS-}

"$REPO_ROOT/scripts/bootstrap.sh"

if [ ! -e "$SHELLSPEC" ]; then
  printf '%s\n' 'ShellSpec submodule missing. Run git submodule update --init --recursive.' >&2
  exit 1
fi

set -- "$SHELLSPEC" --shell "$SHELLSPEC_SHELL"
if [ -n "$SHELLSPEC_FLAGS" ]; then
  set -- "$@" $SHELLSPEC_FLAGS
fi

exec "$@"
