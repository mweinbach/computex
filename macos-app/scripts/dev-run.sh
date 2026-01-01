#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ComputexHost"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$BUILD_DIR/debug/$APP_NAME.app"
BIN_PATH="$BUILD_DIR/debug/$APP_NAME"
APP_BIN="$APP_DIR/Contents/MacOS/$APP_NAME"

swift build -c debug --package-path "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_BIN"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

select_signing_identity() {
  if [[ -n "${SIGN_ID:-}" ]]; then
    echo "$SIGN_ID"
    return
  fi

  local identity
  identity=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\\(Apple Development:.*\\)"/\\1/p' | head -n 1)
  if [[ -z "$identity" ]]; then
    identity=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\\(Developer ID Application:.*\\)"/\\1/p' | head -n 1)
  fi
  if [[ -z "$identity" ]]; then
    echo "-"
  else
    echo "$identity"
  fi
}

BUNDLE_ID="${BUNDLE_ID:-com.mweinbach.computex.host.dev}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist" >/dev/null

SIGN_IDENTITY="$(select_signing_identity)"
echo "Signing with: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/ComputexHost.entitlements" "$APP_DIR"

"$APP_BIN"
