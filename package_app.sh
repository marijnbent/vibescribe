#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :AppName' "$ROOT_DIR/release/Release.plist")"

"$ROOT_DIR/scripts/build-release.sh"

LEGACY_OUTPUT="$ROOT_DIR/$APP_NAME.app"
rm -rf "$LEGACY_OUTPUT"
ditto "$ROOT_DIR/build/Release/$APP_NAME.app" "$LEGACY_OUTPUT"

printf 'Created %s\n' "$LEGACY_OUTPUT"
