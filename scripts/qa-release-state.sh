#!/usr/bin/env bash
# Is this checkout a build that still has to be published, one that already
# was, or a mistake?
#
# The updater on every display compares version numbers, so two different
# builds must never carry the same one: displays that have the first would
# never take the second. This script compares the checkout with the QA
# release of its version (tag vX.Y.Z-qa, which records the commit it was
# built from) and prints one line:
#
#   publish    no vX.Y.Z-qa release yet: build and publish it
#   published  vX.Y.Z-qa exists and was built from the same app files: nothing to do
#
# and fails when vX.Y.Z-qa (or the promoted vX.Y.Z) exists but the app files
# differ: bump "version" in package.json.
#
# Needs: git with the release tags fetched, node, gh (GH_TOKEN), GITHUB_REPOSITORY.
set -euo pipefail

# Everything that ends up in the installer.
APP_PATHS=(main.js preload.js display-scale.js recovery.html package.json package-lock.json resources build)

version=$(node -p "require('./package.json').version")
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "package.json version '$version' is not X.Y.Z" >&2; exit 1
fi

for tag in "v$version-qa" "v$version"; do
  sha=$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json targetCommitish -q .targetCommitish 2>/dev/null || true)
  [ -n "$sha" ] || continue
  git fetch --quiet origin "refs/tags/$tag:refs/tags/$tag" 2>/dev/null || true
  if ! git cat-file -e "$tag^{commit}" 2>/dev/null; then
    echo "Release $tag exists but its commit cannot be read here. Bump \"version\" in package.json." >&2; exit 1
  fi
  if git diff --quiet "$tag^{commit}" HEAD -- "${APP_PATHS[@]}"; then
    echo "published"; exit 0
  fi
  echo "FieldLinkKiosk $version is already published ($tag) and the app has changed since:" >&2
  git diff --stat "$tag^{commit}" HEAD -- "${APP_PATHS[@]}" >&2
  echo "Bump \"version\" in package.json (and package-lock.json: npm install --package-lock-only)." >&2
  exit 1
done
echo "publish"
