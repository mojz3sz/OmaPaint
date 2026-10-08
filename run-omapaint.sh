#!/usr/bin/env bash
set -euo pipefail

launcher_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

if [ -x "${OMAPAINT_BINARY:-}" ]; then
    app_binary="$OMAPAINT_BINARY"
elif [ -x "$launcher_dir/build/omapaint" ]; then
    app_binary="$launcher_dir/build/omapaint"
elif [ -x "/usr/lib/omapaint/omapaint" ]; then
    app_binary="/usr/lib/omapaint/omapaint"
elif command -v omapaint >/dev/null 2>&1 && [ "$(command -v omapaint)" != "$0" ]; then
    app_binary="$(command -v omapaint)"
else
    echo "Nie znaleziono samodzielnej binarki OmaPaint." >&2
    echo "Zbuduj aplikację poleceniami: cmake -S . -B build && cmake --build build" >&2
    exit 1
fi

exec "$app_binary" "$@"
