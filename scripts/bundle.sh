#!/usr/bin/env bash
# Builds a release binary and wraps it in "build/Battery Meter.app" (ad hoc signed).
#   --install  also quits any running copy and installs to ~/Applications/Battery Meter.app
set -euo pipefail

INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *) echo "usage: $0 [--install]" >&2; exit 64 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${BATTERY_METER_VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
if [[ -z "$VERSION" ]]; then
    echo "VERSION file missing or empty" >&2
    exit 64
fi

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Battery Meter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/BatteryMeter" "$APP/Contents/MacOS/BatteryMeter"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleIdentifier</key>
    <string>com.noodlexz.BatteryMeter</string>
    <key>CFBundleName</key>
    <string>Battery Meter</string>
    <key>CFBundleDisplayName</key>
    <string>Battery Meter</string>
    <key>CFBundleExecutable</key>
    <string>BatteryMeter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>27.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ $INSTALL -eq 1 ]]; then
    DEST="$HOME/Applications/Battery Meter.app"
    # Not running is fine.
    osascript -e 'quit app "Battery Meter"' >/dev/null 2>&1 || true
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    ditto "$APP" "$DEST"
    echo "Installed $DEST"
fi
