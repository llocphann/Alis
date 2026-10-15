#!/usr/bin/env bash
# AUDIO-I01: keep graph quantum steady for native EasyEffects launched by Alis.
# Set ALIS_AUDIO_I01_LOCK_QUANTUM=0 to disable this provisional mitigation.
set -euo pipefail

if (( $# == 0 )); then
    printf '%s\n' 'Usage: easyeffects-quantum-guard.sh COMMAND [ARG ...]' >&2
    exit 64
fi

if [[ "${ALIS_AUDIO_I01_LOCK_QUANTUM:-1}" != "0" ]]; then
    # Respect owner PipeWire environment overrides, even explicitly empty ones.
    # They take precedence; EasyEffects must remain launchable in this case.
    if [[ -v PIPEWIRE_PROPS || -v PIPEWIRE_QUANTUM || -v PIPEWIRE_LATENCY ]]; then
        printf '%s\n' 'AUDIO-I01: existing PipeWire environment override; starting without Alis quantum lock.' >&2
    else
        # PipeWire 1.6.9 pw_filter_connect reads this into new filter nodes.
        # This does not set global clock.force-quantum metadata.
        export PIPEWIRE_PROPS='{ node.lock-quantum = true }'
    fi
fi

exec "$@"
