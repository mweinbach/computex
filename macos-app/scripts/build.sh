#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ComputexHost"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BIN_PATH="$BUILD_DIR/release/$APP_NAME"

swift build -c release --package-path "$ROOT_DIR"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

BUNDLE_ID="${BUNDLE_ID:-com.openai.computex.host}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" >/dev/null

if xcrun -find swift-stdlib-tool >/dev/null 2>&1; then
  xcrun swift-stdlib-tool \
    --copy \
    --scan-executable "$APP_DIR/Contents/MacOS/$APP_NAME" \
    --destination "$APP_DIR/Contents/Frameworks" \
    --platform macosx \
    --strip-bitcode \
    --sign -
fi

codesign --force --deep --sign - --entitlements "$ROOT_DIR/ComputexHost.entitlements" "$APP_DIR"

echo "Built and signed: $APP_DIR"
