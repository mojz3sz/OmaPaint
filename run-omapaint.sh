#!/usr/bin/env bash
set -euo pipefail

launcher_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
if [ -f "$launcher_dir/quickpaint.qml" ]; then
    app_dir="$launcher_dir"
else
    app_dir="/usr/share/omapaint"
fi

exec quickshell -p "$app_dir/quickpaint.qml" "$@"
