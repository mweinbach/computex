#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ComputexHost"
BUILD_DIR="$ROOT_DIR/.build"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
BIN_PATH="$BUILD_DIR/release/$APP_NAME"

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

swift build -c release --package-path "$ROOT_DIR"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

BUNDLE_ID="${BUNDLE_ID:-com.mweinbach.computex.host}"
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

SIGN_IDENTITY="$(select_signing_identity)"
echo "Signing with: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/ComputexHost.entitlements" "$APP_DIR"

echo "Built and signed: $APP_DIR"
