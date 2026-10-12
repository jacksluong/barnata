#!/bin/bash
# Cuts a release: tag, build, sign, notarize the app and the DMG, publish.
#
# Usage: Scripts/release.sh <version> [--dry-run] [note...]
#   <version>   semver without the leading v, e.g. 0.1.0
#   --dry-run   build and notarize only, no tag push and no GitHub release
#   note        one bullet item of the release notes, e.g. "Simplified the update panel."
set -euo pipefail

source "$(dirname "$0")/vars.sh"

VERSION="${1:-}"
shift || true
DRY_RUN=0
NOTES=""
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then
    DRY_RUN=1
  else
    NOTES+="${NOTES:+$'\n'}- ${arg}"
  fi
done

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: Scripts/release.sh <version> [--dry-run] [note...]" >&2
  exit 1
fi

echo "==> Release notes for v${VERSION}"
echo
echo "${NOTES:-(none)}"
echo
read -r -p "Continue? [y/N] " REPLY
[[ "$REPLY" =~ ^[Yy]$ ]] || { echo "cancelled"; exit 1; }

TAG="v${VERSION}"
RELEASE_DMG="${BUILD_DIR}/${APP_NAME}-${VERSION}.dmg"

cd "$REPO_ROOT"

echo "==> Checking the working tree"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is dirty, commit or stash first" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "tag ${TAG} already exists" >&2
  exit 1
fi

echo "==> Running tests"
swift test

echo "==> Tagging ${TAG}"
git tag -a "$TAG" -m "$TAG"

# build-app.sh reads the version back out of `git describe`, so the tag has to exist first.
# Any failure past this point leaves a local tag behind that nothing has pushed.
trap 'git tag -d "$TAG" >/dev/null 2>&1 || true' ERR

"${REPO_ROOT}/Scripts/build-app.sh"
"${REPO_ROOT}/Scripts/notarize.sh"
"${REPO_ROOT}/Scripts/make-dmg.sh"

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${BUILD_DIR}/${APP_NAME}.app/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || { echo "bundle says ${BUILT_VERSION}, expected ${VERSION}" >&2; exit 1; }

SHA256="$(shasum -a 256 "$RELEASE_DMG" | awk '{ print $1 }')"
trap - ERR

if [[ $DRY_RUN -eq 1 ]]; then
  git tag -d "$TAG"
  echo
  echo "==> Dry run finished. ${RELEASE_DMG##*/}, sha256 ${SHA256}"
  exit 0
fi

echo "==> Pushing ${TAG}"
git push origin "$TAG"

echo "==> Creating the GitHub release"
gh release create "$TAG" "$RELEASE_DMG" \
  --repo "$GITHUB_REPO" \
  --title "$TAG" \
  --notes "$NOTES"

echo
echo "==> Released ${TAG}"
echo "    ${RELEASE_DMG##*/}"
echo "    version ${VERSION}"
echo "    sha256  ${SHA256}"
