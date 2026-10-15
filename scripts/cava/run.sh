#!/usr/bin/env bash
set -euo pipefail

# CAVA's default native PipeWire latency request can change the audio graph's
# quantum. Clear only that child's default when the user supplied no override;
# an explicitly empty value is still an intentional override.
if [[ ! -v PIPEWIRE_PROPS && ! -v PIPEWIRE_LATENCY ]]; then
    export PIPEWIRE_PROPS='{ node.latency = null }'
fi

exec cava "$@"
