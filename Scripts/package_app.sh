#!/bin/sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec /usr/bin/env bash "$SCRIPT_DIR/package_app.bash" "$@"
