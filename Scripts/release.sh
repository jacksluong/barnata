#!/bin/bash
# Cuts a release: tag, build, sign, notarize, publish, bump the cask.
#
# Usage: Scripts/release.sh <version> [--dry-run]
#   <version>   semver without the leading v, e.g. 0.1.0
#   --dry-run   build and notarize only, no tag push and no GitHub release
set -euo pipefail

source "$(dirname "$0")/vars.sh"

VERSION="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: Scripts/release.sh <version> [--dry-run]" >&2
  exit 1
fi
TAG="v${VERSION}"
RELEASE_ZIP="${BUILD_DIR}/${APP_NAME}-${VERSION}.zip"

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
git tag -a "$TAG" -m "Barnata ${VERSION}"

# build-app.sh reads the version back out of `git describe`, so the tag has to exist first.
# Any failure past this point leaves a local tag behind that nothing has pushed.
trap 'git tag -d "$TAG" >/dev/null 2>&1 || true' ERR

"${REPO_ROOT}/Scripts/build-app.sh"
"${REPO_ROOT}/Scripts/notarize.sh"

BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${BUILD_DIR}/${APP_NAME}.app/Contents/Info.plist")"
[[ "$BUILT_VERSION" == "$VERSION" ]] || { echo "bundle says ${BUILT_VERSION}, expected ${VERSION}" >&2; exit 1; }

SHA256="$(shasum -a 256 "$RELEASE_ZIP" | awk '{ print $1 }')"
trap - ERR

if [[ $DRY_RUN -eq 1 ]]; then
  git tag -d "$TAG"
  echo
  echo "==> Dry run finished. ${RELEASE_ZIP##*/}, sha256 ${SHA256}"
  exit 0
fi

echo "==> Pushing ${TAG}"
git push origin "$TAG"

echo "==> Creating the GitHub release"
gh release create "$TAG" "$RELEASE_ZIP" \
  --repo "$GITHUB_REPO" \
  --title "Barnata ${VERSION}" \
  --notes "Install with \`brew install --cask ${CASK_TOKEN}\`."

CASK="${TAP_DIR}/Casks/${CASK_NAME}.rb"
if [[ -f "$CASK" ]]; then
  echo "==> Bumping ${CASK}"
  sed -i '' -e "s/^  version \".*\"$/  version \"${VERSION}\"/" -e "s/^  sha256 \".*\"$/  sha256 \"${SHA256}\"/" "$CASK"
  echo "    commit and push ${TAP_DIR} to publish it"
else
  echo "==> No cask at ${CASK}; set these by hand in ${TAP_REPO}"
fi

echo
echo "==> Released ${TAG}"
echo "    version ${VERSION}"
echo "    sha256  ${SHA256}"
