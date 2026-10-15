#!/usr/bin/env bash
# Generate cava config for internal widget usage (CavaProcess.qml)
# Usage: generate_config.sh <output_file> [framerate] [sensitivity] [bars] [stereo] [desktop_entry] [--print-config]
#
# All parameters after output_file are optional and fall back to sane defaults.
# Supports both PipeWire and PulseAudio systems.

set -euo pipefail

case "${1:-}" in
    -h|--help)
        echo "Usage: generate_config.sh <output_file> [framerate] [sensitivity] [bars] [stereo] [desktop_entry] [--print-config]"
        exit 0
        ;;
esac

OUTPUT_FILE="${1:-/tmp/cava_config.txt}"
FRAMERATE="${2:-30}"
SENSITIVITY="${3:-100}"
BARS="${4:-50}"
STEREO="${5:-false}"
DESKTOP_ENTRY="${6:-}"
PRINT_CONFIG="${7:-}"
if [[ -n "$PRINT_CONFIG" && "$PRINT_CONFIG" != "--print-config" ]]; then
    printf 'Unknown output mode: %s\n' "$PRINT_CONFIG" >&2
    exit 64
fi

# Detect audio backend (pipewire or pulseaudio)
get_audio_method() {
    if pactl info 2>/dev/null | grep -qi "PipeWire"; then
        echo "pipewire"
    else
        echo "pulse"
    fi
}

# Get the default sink's monitor source
get_default_monitor() {
    local default_sink
    default_sink=$(pactl get-default-sink 2>/dev/null || true)
    if [[ -n "$default_sink" ]]; then
        echo "${default_sink}.monitor"
        return
    fi
    echo "auto"
}

METHOD=$(get_audio_method)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVER="$SCRIPT_DIR/resolve_audio_source.py"
RESOLVED=""
if [[ -f "$RESOLVER" ]]; then
  RESOLVED=$(python3 "$RESOLVER" --desktop-entry "$DESKTOP_ENTRY" 2>/dev/null || true)
fi
if [[ -n "$RESOLVED" ]]; then
  MONITOR="$RESOLVED"
else
  MONITOR=$(get_default_monitor)
fi
CHANNELS="mono"
[[ "$STEREO" == "true" ]] && CHANNELS="stereo"

# Generate beside the published file so changed content can be committed with
# one atomic rename. Keep the running analyzer's file/inode untouched when the
# entire resolved configuration is identical (including source and backend).
mkdir -p -- "$(dirname -- "$OUTPUT_FILE")"
CANDIDATE="$(mktemp -- "${OUTPUT_FILE}.XXXXXX")"
trap 'rm -f -- "$CANDIDATE"' EXIT
cat > "$CANDIDATE" << EOF
[general]
framerate = ${FRAMERATE}
sensitivity = ${SENSITIVITY}
autosens = 1
bars = ${BARS}

[input]
method = ${METHOD}
source = ${MONITOR}

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 1000
bar_delimiter = 59
channels = ${CHANNELS}
mono_option = average

[smoothing]
noise_reduction = 20
EOF

if [[ "$PRINT_CONFIG" == "--print-config" ]]; then
    # The shared service compares exact bytes with its running process config,
    # rather than assuming the latest generated file was already in use.
    cat -- "$CANDIDATE"
fi
python3 - "$CANDIDATE" "$OUTPUT_FILE" <<'PY'
from pathlib import Path
import os
import sys

candidate, output = map(Path, sys.argv[1:])
try:
    unchanged = candidate.read_bytes() == output.read_bytes()
except FileNotFoundError:
    unchanged = False
if not unchanged:
    os.replace(candidate, output)
PY
if [[ "$PRINT_CONFIG" != "--print-config" ]]; then
    printf '%s\n' "$OUTPUT_FILE"
fi
