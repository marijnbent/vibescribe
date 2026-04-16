#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/release_common.sh"

release::quit_running_app "$(release::app_name)"
"$SCRIPT_DIR/build-release.sh"
"$SCRIPT_DIR/install-release.sh"
