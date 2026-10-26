#!/usr/bin/env bash
set -euo pipefail

here="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -n "${QS:-}" ]]; then
    qs_bin="$QS"
elif command -v qs >/dev/null 2>&1; then
    qs_bin="$(command -v qs)"
elif command -v quickshell >/dev/null 2>&1; then
    qs_bin="$(command -v quickshell)"
else
    printf 'Missing Quickshell executable (qs/quickshell).\n' >&2
    exit 127
fi

exec "$qs_bin" -n -p "$here"
