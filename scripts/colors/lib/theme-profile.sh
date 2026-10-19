#!/usr/bin/env bash
# Optional profile trace. No processes or disk writes when profiling is disabled.
# Never print wallpaper paths, colors, secrets, or environment values.
theme_perf_stage() {
    [[ "${ALIS_THEME_PROFILE:-}" == "1" ]] || return 0
    local scope="$1" stage="$2" started="${3:-}"
    [[ "$started" =~ ^[0-9]+$ ]] || return 0
    local now duration
    now="$(date +%s%N)"
    duration=$(( (now - started) / 1000000 ))
    (( duration < 0 )) && duration=0
    printf '[THEME-PERF-04] scope=%s stage=%s ms=%d epoch_ms=%s\n' \
        "$scope" "$stage" "$duration" "$((now / 1000000))" >&2
}
