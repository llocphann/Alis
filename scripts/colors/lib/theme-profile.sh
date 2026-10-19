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
    local record source="${ALIS_THEME_PROFILE_SOURCE:-unknown}"
    case "$source" in
        collector|qml-generator|qml-external) ;;
        *) source="other" ;;
    esac
    # Diagnostics only. Never emit paths, commands, colors or secrets.
    printf -v record '[THEME-PERF-04] scope=%s stage=%s ms=%d epoch_ms=%s pid=%s ppid=%s source=%s' \
        "$scope" "$stage" "$duration" "$((now / 1000000))" "$BASHPID" "$PPID" "$source"
    printf '%s\n' "$record" >&2
    if [[ -n "${ALIS_THEME_PROFILE_LOG:-}" && -f "$ALIS_THEME_PROFILE_LOG" && ! -L "$ALIS_THEME_PROFILE_LOG" ]]; then
        printf '%s\n' "$record" >> "$ALIS_THEME_PROFILE_LOG" || true
    fi
}
