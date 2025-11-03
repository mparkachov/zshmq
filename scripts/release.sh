#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

: "${VERSION_FILE:=VERSION}"
: "${RELEASE_ARTIFACT:=zshmq}"
: "${ZSHMQ_BIN:=bin/zshmq.sh}"

"$REPO_ROOT/scripts/bootstrap.sh"

if [ -f "$VERSION_FILE" ]; then
  version=$(tr -d '\r\n' < "$VERSION_FILE")
else
  version=0.0.0
fi

if [ -z "$version" ]; then
  printf '%s\n' 'VERSION file is empty; set a semantic version before releasing.' >&2
  exit 1
fi

printf 'Building release %s\n' "$version" >&2

tmp=$(mktemp)
{
  printf '%s\n' '#!/usr/bin/env sh'
  printf 'ZSHMQ_EMBEDDED=1\n'
  printf 'ZSHMQ_VERSION=%s\n' "$version"
  for vendor in vendor/getoptions/lib/getoptions_base.sh vendor/getoptions/lib/getoptions_abbr.sh vendor/getoptions/lib/getoptions_help.sh; do
    printf '\n'
    sed '/^#!\/usr\/bin\/env sh/d' "$vendor"
  done
  printf '\n'
  sed '/^#!\/usr\/bin\/env sh/d' "lib/command_helpers.sh"
  printf '\n'
  sed '/^#!\/usr\/bin\/env sh/d' "lib/logging.sh"
  for lib in $(cd lib && ls *.sh | sort); do
    case "$lib" in
      command_helpers.sh|logging.sh)
        continue
        ;;
    esac
    printf '\n'
    sed '/^#!\/usr\/bin\/env sh/d' "lib/$lib"
  done
  printf '\n'
  tail -n +2 "$ZSHMQ_BIN"
} > "$tmp"

chmod +x "$tmp"
mv "$tmp" "$RELEASE_ARTIFACT"
chmod +x "$RELEASE_ARTIFACT"

if git rev-parse "v$version" >/dev/null 2>&1; then
  printf 'Tag v%s already exists; skipping tag creation.\n' "$version" >&2
else
  git tag "v$version"
  printf 'Created tag v%s\n' "$version" >&2
fi

printf 'Release artifact is available at %s\n' "$RELEASE_ARTIFACT" >&2
