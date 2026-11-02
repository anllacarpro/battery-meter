#!/usr/bin/env bash
# Build a release zip for GitHub Releases / Homebrew cask.
# Usage: scripts/release.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
if [[ -z "$VERSION" ]]; then
    echo "version required (argument or VERSION file)" >&2
    exit 64
fi

export BATTERY_METER_VERSION="$VERSION"
bash "$ROOT/scripts/bundle.sh"

DIST="$ROOT/dist"
ZIP="$DIST/Battery-Meter-${VERSION}.zip"
rm -rf "$DIST"
mkdir -p "$DIST"
(
    cd "$ROOT/build"
    ditto -c -k --sequesterRsrc --keepParent "Battery Meter.app" "$ZIP"
)

SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "Created $ZIP"
echo "sha256 $SHA"
echo
echo "Homebrew cask snippet:"
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA}\""
