#!/usr/bin/env bash
# THEME-PERF-08: collect live metrics without restarting Quickshell.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/scripts/collect-auto-theme-runtime.py" "$@"
