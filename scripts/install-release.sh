#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/release_common.sh"

APP_BUNDLE="$(release::build_bundle_path)"
[[ -d "$APP_BUNDLE" ]] || release::fail "Missing build output: $APP_BUNDLE"

release::verify_bundle "$APP_BUNDLE"
release::install_bundle "$APP_BUNDLE"
