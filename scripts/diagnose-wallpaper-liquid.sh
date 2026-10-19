#!/usr/bin/env bash
# WALL-R02: passive Liquid shader probe. Do not restart Quickshell.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/scripts/diagnose-wallpaper-liquid.py" "$@"
