#!/usr/bin/env bash
set -euo pipefail

if [[ ! -v PIPEWIRE_PROPS && ! -v PIPEWIRE_LATENCY ]]; then
    export PIPEWIRE_PROPS='{ node.latency = null }'
fi

exec cava "$@"
