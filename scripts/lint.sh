#!/usr/bin/env sh
set -eu
set -f

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH='' cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

: "${SHELLCHECK:=shellcheck}"
SHELLCHECK_FLAGS=${SHELLCHECK_FLAGS-}
SHELLCHECK_SHELL=${SHELLCHECK_SHELL:-sh}
DEFAULT_SHELLCHECK_FLAGS=${SHELLCHECK_DEFAULT_FLAGS:---exclude=SC1091}

if ! command -v "$SHELLCHECK" >/dev/null 2>&1; then
  printf '%s\n' 'shellcheck command not found. Install shellcheck to use scripts/lint.sh.' >&2
  exit 127
fi

if [ "$#" -gt 0 ]; then
  # shellcheck disable=SC2086
  exec "$SHELLCHECK" --shell="$SHELLCHECK_SHELL" ${DEFAULT_SHELLCHECK_FLAGS:-} ${SHELLCHECK_FLAGS:-} "$@"
fi

WORK_TMP=${TMPDIR:-"$REPO_ROOT/tmp"}
if [ ! -d "$WORK_TMP" ]; then
  mkdir -p "$WORK_TMP"
fi

FILE_LIST=$(mktemp "$WORK_TMP/shellcheck.XXXXXX")

cleanup() {
  rm -f "$FILE_LIST"
}

trap cleanup EXIT HUP INT TERM

DEFAULT_DIRS="bin lib scripts spec"
for dir in $DEFAULT_DIRS; do
  if [ -d "$dir" ]; then
    find "$dir" -type f -name '*.sh' -print >> "$FILE_LIST"
  fi
done

if [ ! -s "$FILE_LIST" ]; then
  printf '%s\n' 'No shell scripts found. Add targets or pass files explicitly.' >&2
  exit 0
fi

set --
while IFS= read -r target || [ -n "$target" ]; do
  [ -n "$target" ] || continue
  set -- "$@" "$target"
done < "$FILE_LIST"

# shellcheck disable=SC2086
exec "$SHELLCHECK" --shell="$SHELLCHECK_SHELL" ${DEFAULT_SHELLCHECK_FLAGS:-} ${SHELLCHECK_FLAGS:-} "$@"
