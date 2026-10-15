#!/usr/bin/env bash
# AUDIO-I01 controlled A/B: lock active graph quantum from this EasyEffects
# process only. This is not a global PipeWire setting or a permanent workaround.
set -euo pipefail

if (( $# == 0 )); then
    printf '%s\n' 'Usage: easyeffects-quantum-guard.sh COMMAND [ARG ...]' >&2
    exit 64
fi

if [[ "${ALIS_AUDIO_I01_LOCK_QUANTUM:-}" == "1" ]]; then
    # The owner may already have latency/quantum overrides. Do not clobber,
    # merge guesses, or proceed with an ambiguous diagnostic.
    if [[ -v PIPEWIRE_PROPS || -v PIPEWIRE_QUANTUM || -v PIPEWIRE_LATENCY ]]; then
        printf '%s\n' 'AUDIO-I01: explicit PIPEWIRE_PROPS/QUANTUM/LATENCY detected; refusing quantum-lock probe (exit 78).' >&2
        exit 78
    fi
    # PipeWire 1.6.9 filter.c reads PIPEWIRE_PROPS when pw_filter_connect()
    # creates EasyEffects filters. This does not force a particular quantum:
    # it prevents automatic changes while the decorated graph node is active.
    export PIPEWIRE_PROPS='{ node.lock-quantum = true }'
fi

exec "$@"
