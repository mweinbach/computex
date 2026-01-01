#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
BIN_PATH="$BUILD_DIR/debug/ComputexHost"

swift build -c debug --package-path "$ROOT_DIR"

codesign --force --sign - --entitlements "$ROOT_DIR/ComputexHost.entitlements" "$BIN_PATH"

"$BIN_PATH"
