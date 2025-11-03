#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

: "${VERSION_FILE:=VERSION}"
: "${RELEASE_ARTIFACT:=zshmq}"

VERSION=${VERSION:-}

if [ -z "$VERSION" ]; then
  printf '%s\n' 'Usage: VERSION=<semver> ./scripts/publish.sh' >&2
  exit 1
fi

printf '%s\n' "$VERSION" > "$VERSION_FILE"
printf 'Updated %s to %s\n' "$VERSION_FILE" "$VERSION" >&2

if git diff --quiet -- "$VERSION_FILE"; then
  :
else
  git add "$VERSION_FILE"
  git commit -m "Release $VERSION"
fi

"$REPO_ROOT/scripts/release.sh" >/dev/null

git add "$RELEASE_ARTIFACT"
if git commit --amend --no-edit >/dev/null 2>&1; then
  :
else
  git commit -m "Release $VERSION"
fi

git add "$RELEASE_ARTIFACT" "$VERSION_FILE"
g_version=$(tr -d '\r\n' < "$VERSION_FILE")
git tag -f "v$g_version"
git push origin HEAD
git push origin --tags
gh release create "v$g_version" "$RELEASE_ARTIFACT" --title "v$g_version" --notes "Release $g_version" --latest >/dev/null
