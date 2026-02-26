#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CURRENT_VERSION=$(grep 'version = "' "$REPO_DIR/default.nix" | head -1 | sed 's/.*version = "\(.*\)";/\1/')
echo "Current version: $CURRENT_VERSION"

LATEST_VERSION=$(curl -sf https://registry.npmjs.org/dev3000/latest | jq -r '.version')
echo "Latest npm version: $LATEST_VERSION"

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
  echo "Already up to date."
  exit 0
fi

echo "Updating from $CURRENT_VERSION to $LATEST_VERSION..."

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

TARBALL_URL="https://registry.npmjs.org/dev3000/-/dev3000-${LATEST_VERSION}.tgz"
curl -sfL "$TARBALL_URL" -o "$WORK_DIR/dev3000.tgz"

SRC_HASH=$(nix hash path --mode flat "$WORK_DIR/dev3000.tgz")
echo "Source hash: $SRC_HASH"

# Extract, strip devDependencies, generate production-only package-lock.json
mkdir -p "$WORK_DIR/package"
tar -xzf "$WORK_DIR/dev3000.tgz" -C "$WORK_DIR/package" --strip-components=1
jq 'del(.devDependencies)' "$WORK_DIR/package/package.json" > "$WORK_DIR/package/package.json.tmp"
mv "$WORK_DIR/package/package.json.tmp" "$WORK_DIR/package/package.json"

(cd "$WORK_DIR/package" && npm install --package-lock-only --ignore-scripts 2>/dev/null)

NPM_DEPS_HASH=$(prefetch-npm-deps "$WORK_DIR/package/package-lock.json" 2>/dev/null)
echo "NPM deps hash: $NPM_DEPS_HASH"

# Update default.nix (use temp file for macOS/Linux portability)
sed "s|version = \"$CURRENT_VERSION\"|version = \"$LATEST_VERSION\"|" "$REPO_DIR/default.nix" \
  | sed "s|hash = \".*\"|hash = \"$SRC_HASH\"|" \
  | sed "s|npmDepsHash = \".*\"|npmDepsHash = \"$NPM_DEPS_HASH\"|" \
  > "$REPO_DIR/default.nix.tmp"
mv "$REPO_DIR/default.nix.tmp" "$REPO_DIR/default.nix"

cp "$WORK_DIR/package/package-lock.json" "$REPO_DIR/package-lock.json"

echo "Updated d3k to $LATEST_VERSION"

# Set GitHub Actions outputs if running in CI
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "VERSION=$LATEST_VERSION" >> "$GITHUB_OUTPUT"
  echo "UPDATED=true" >> "$GITHUB_OUTPUT"
fi
