#!/usr/bin/env bash
# Read-only bounded owner-session diagnostics. No shell restart, config write,
# remap, privilege, audio access, or continuous background job.
set -uo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
output_dir="${1:-${TMPDIR:-/tmp}/hadalis-abyss-hover-$(date +%Y%m%d-%H%M%S)}"
mkdir -p -- "$output_dir" || exit 1
# Preserve a single uploadable bundle, including partial diagnostic evidence
# when an IPC call fails. Keep the original exit status in the bundle.
archive_capture() {
    local rc=$?
    trap - EXIT
    printf 'collector_exit_status=%d\n' "$rc" > "$output_dir/run-result.txt"
    local archive="${output_dir%/}.tar.gz"
    if command -v tar >/dev/null 2>&1; then
        if tar -czf "$archive" -C "$output_dir" .; then
            printf 'UPLOAD ONLY THIS FILE: %s\n' "$archive"
        else
            printf 'ERROR: archive creation failed; raw evidence: %s\n' "$output_dir" >&2
            if ((rc == 0)); then rc=3; fi
        fi
    else
        printf 'ERROR: tar is unavailable; raw evidence: %s\n' "$output_dir" >&2
        if ((rc == 0)); then rc=127; fi
    fi
    exit "$rc"
}
trap archive_capture EXIT

if ! command -v qs >/dev/null 2>&1; then
    printf 'qs unavailable; no runtime test performed.\n' | tee "$output_dir/config-error.txt" >&2
    exit 127
fi

# The production launcher (scripts/alis) targets a *path*: qs -p DIR ipc call.
# Bare qs ipc call instead looks for a nonexistent "default" config. Resolve
# the live alis path to avoid targeting a stale install or a different shell.
candidates=()
if [[ -n "${HADALIS_QS_CONFIG:-}" ]]; then
    candidates+=("$HADALIS_QS_CONFIG")
else
    if command -v jq >/dev/null 2>&1; then
        while IFS= read -r qml; do
            [[ -n "$qml" ]] && candidates+=("${qml%/shell.qml}")
        done < <(qs list --all --json 2>/dev/null | jq -r '
            .[] | (.config_path // .configPath // empty)
            | select(type=="string" and endswith("/shell.qml"))
        ' 2>/dev/null)
    fi
    while IFS= read -r qml; do
        [[ -n "$qml" ]] && candidates+=("${qml%/shell.qml}")
    done < <(qs list --all 2>/dev/null | sed -n 's/^[[:space:]]*Config path:[[:space:]]*//p' | grep '/shell\.qml$' || true)
    candidates+=("${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/alis"
        "$repo_root" /usr/local/share/quickshell/alis /usr/share/quickshell/alis)
fi

resolved_config=""
for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    if [[ "$candidate" == */shell.qml ]]; then candidate="${candidate%/shell.qml}"; fi
    [[ -f "$candidate/shell.qml" ]] || continue
    # An unrelated Quickshell config must never receive the diagnostics.
    grep -q '^//@ pragma ShellId alis' "$candidate/shell.qml" || continue
    canonical="$(realpath -e -- "$candidate" 2>/dev/null || printf '%s' "$candidate")"
    listing="$(qs -p "$canonical" list 2>/dev/null)" || continue
    [[ -n "$listing" && "$listing" != No\ running\ instances* ]] || continue
    resolved_config="$canonical"
    break
done
if [[ -z "$resolved_config" ]]; then
    {
        printf 'ERROR: no running Alis Quickshell instance found.\n'
        printf 'Inspect: qs list --all\n'
        printf 'Optional: HADALIS_QS_CONFIG=/path/to/running/alis\n'
        printf 'No shell was started or changed by this script.\n'
    } | tee "$output_dir/config-error.txt" >&2
    exit 3
fi
qs_cmd=(qs -p "$resolved_config")

# Capture a bounded live IPC inventory and critical host status. Both are
# read-only; they distinguish wrong instance / missing critical family from a
# missing optional Perimeter before assuming a method-specific failure.
qs_show_rc=0
"${qs_cmd[@]}" ipc show > "$output_dir/ipc-targets.txt" 2>&1 || qs_show_rc=$?
printf 'ipc_show_exit_status=%d\n' "$qs_show_rc" > "$output_dir/ipc-preflight-status.txt"
host_status_rc=0
"${qs_cmd[@]}" ipc call abyssHostProbe status > "$output_dir/abyss-host-status.txt" 2>&1 || host_status_rc=$?
printf 'abyss_host_status_exit_status=%d\n' "$host_status_rc" >> "$output_dir/ipc-preflight-status.txt"
snapshot_preflight_rc=0
"${qs_cmd[@]}" ipc call abyssHoverProbe snapshot > "$output_dir/hover-preflight.txt" 2>&1 || snapshot_preflight_rc=$?
printf 'hover_preflight_exit_status=%d\n' "$snapshot_preflight_rc" >> "$output_dir/ipc-preflight-status.txt"

source_mismatch=false
{
    printf 'capture_utc=%s\n' "$(date -u +%FT%TZ)"
    printf 'git_HEAD=%s\n' "$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf unavailable)"
    printf 'git_branch=%s\n' "$(git -C "$repo_root" branch --show-current 2>/dev/null || printf unavailable)"
    printf 'qs_binary=%s\n' "$(command -v qs)"
    printf 'qs_config_requested=%s\n' "${HADALIS_QS_CONFIG:-auto}"
    printf 'qs_config_resolved=%s\n' "$resolved_config"
    installed_sha="$(git -C "$resolved_config" rev-parse HEAD 2>/dev/null || true)"
    printf 'installed_git_HEAD=%s\n' "${installed_sha:-unavailable}"
    for rel in shell.qml modules/abyss/AbyssPerimeter.qml modules/abyss/looks/AbyssGeometry.js; do
        if [[ -f "$resolved_config/$rel" && -f "$repo_root/$rel" ]]; then
            if cmp -s -- "$resolved_config/$rel" "$repo_root/$rel"; then
                printf 'installed_vs_checkout[%s]=MATCH\n' "$rel"
            else
                printf 'installed_vs_checkout[%s]=DIFFERENT\n' "$rel"
                source_mismatch=true
            fi
        else
            printf 'installed_vs_checkout[%s]=MISSING\n' "$rel"
            source_mismatch=true
        fi
    done
    printf 'capture=6s frame-only, then 100 bounded hover snapshots at 150ms spacing\n'
    printf 'caveat=source checkout SHA is not proof of installed shell identity\n'
} > "$output_dir/identity.txt"

# Fail CLOSED on stale/mismatched installed source. 'alis restart' alone
# restarts the installed copy; it does not sync checkout QML into that copy.
if [[ "$source_mismatch" == true ]]; then
    {
        printf 'ERROR: installed Alis QML does not match this dev checkout.\n'
        printf 'Run the supported Hadalis setup update from this checkout, then restart Alis.\n'
        printf 'From repo: ./setup update --local  (sync this dev checkout; skip git pull)\n'
        printf 'Then: alis restart; bash scripts/collect-abyss-hover-frames.sh\n'
        printf 'No FPS or hover conclusion can be drawn from this stale runtime.\n'
    } | tee "$output_dir/config-error.txt" >&2
    exit 4
fi

# A successful 'alis restart' may leave the critical host registered before
# deferred panels and the optional Perimeter have mounted. The IPC CLI can even
# return exit 0 for 'Target not found.'. Do not misreport this boot race as a
# frame failure. Never remount or alter any shell surface to "fix" readiness.
printf 'Waiting up to 25 seconds for Abyss Perimeter and frame probe readiness...\n' >&2
probe_ready=0
for ((attempt=0; attempt<100; attempt++)); do
    host_ready_rc=0
    "${qs_cmd[@]}" ipc call abyssHostProbe status > "$output_dir/abyss-host-status.txt" 2>&1 || host_ready_rc=$?
    hover_ready_rc=0
    "${qs_cmd[@]}" ipc call abyssHoverProbe snapshot > "$output_dir/hover-preflight.txt" 2>&1 || hover_ready_rc=$?
    printf 'attempt=%03d utc=%s host_exit=%d hover_exit=%d host=%s hover_prefix=%s\n' \
        "$attempt" "$(date -u +%FT%T.%3NZ)" "$host_ready_rc" "$hover_ready_rc" \
        "$(tr '\n' ' ' < "$output_dir/abyss-host-status.txt" | cut -c1-500)" \
        "$(tr '\n' ' ' < "$output_dir/hover-preflight.txt" | cut -c1-200)" \
        >> "$output_dir/readiness-trace.log"
    if ((host_ready_rc == 0 && hover_ready_rc == 0)) \
            && grep -Fq '"family":"abyss"' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"deferredPanelsReady":true' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"perimeterLoaded":true' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"perimeterActive":true' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"nativeFirstFramesReady":true' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"diagnosticUnmounted":false' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"coldRecreatePending":false' "$output_dir/abyss-host-status.txt" \
            && grep -Fq '"family":"abyss"' "$output_dir/hover-preflight.txt" \
            && grep -Eq '"outputCount":[1-9][0-9]*' "$output_dir/hover-preflight.txt" \
            && grep -Fq '"fieldReady":true' "$output_dir/hover-preflight.txt"; then
        probe_ready=1
        printf 'ready_attempt=%d\n' "$attempt" >> "$output_dir/identity.txt"
        break
    fi
    if ((attempt < 99)); then sleep .25; fi
done
if ((probe_ready == 0)); then
    {
        printf 'ERROR: Abyss host did not become ready during a bounded 25s poll.\n'
        printf 'See readiness-trace.log, abyss-host-status.txt, hover-preflight.txt.\n'
        printf 'No frame/hover diagnosis was attempted and no UI was altered.\n'
    } | tee "$output_dir/readiness-error.txt" >&2
    exit 7
fi
"${qs_cmd[@]}" ipc show > "$output_dir/ipc-targets-ready.txt" 2>&1 || true
printf 'Abyss Perimeter is ready; proceeding with bounded sampling.\n' >&2

# Phase 1: open/close/reverse the panel on the intended output while frame
# samples are enabled. Do not interleave IPC polling into this window.
printf 'PHASE 1/2: open, close and reverse Abyss panels during the next six seconds.\n' >&2
frame_start_rc=0
"${qs_cmd[@]}" ipc call abyssHoverProbe startFrames > "$output_dir/frame-start.txt" 2>&1 || frame_start_rc=$?
# Quickshell may print 'Target not found.' and still return exit status 0.
# Require the exact success receipt, not just the CLI process status.
if ((frame_start_rc != 0)) || ! grep -Eq '"started"[[:space:]]*:[[:space:]]*true' "$output_dir/frame-start.txt"; then
    {
        printf 'ERROR: startFrames did not confirm an active handler (qs exit=%s).\n' "$frame_start_rc"
        printf 'The IPC CLI can exit 0 even for Target not found.\n'
        printf 'Inspect ipc-targets.txt, abyss-host-status.txt, hover-preflight.txt and identity.txt.\n'
    } | tee "$output_dir/diagnostic-error.txt" >&2
    exit 5
fi
sleep 6
frame_stop_rc=0
"${qs_cmd[@]}" ipc call abyssHoverProbe stopFrames > "$output_dir/frame-intervals.txt" 2>&1 || frame_stop_rc=$?
if ((frame_stop_rc != 0)) || ! grep -Fq '"sample":"QQuickWindow frameSwapped wall-clock intervals (ms)"' "$output_dir/frame-intervals.txt" || ! grep -Eq '"count"[[:space:]]*:[[:space:]]*[1-9][0-9]*' "$output_dir/frame-intervals.txt"; then
    {
        printf 'ERROR: stopFrames did not return a valid frame summary (qs exit=%s).\n' "$frame_stop_rc"
        printf 'Inspect frame-intervals.txt and installed runtime parity.\n'
    } | tee "$output_dir/diagnostic-error.txt" >&2
    exit 6
fi

# Phase 2: cross the Popup/Screen Edge seam, then enter empty desktop.
# Snapshots are boolean state and geometry only, not user content.
printf 'PHASE 2/2: OPEN A POPUP NOW and slowly cross its Screen Edge connector.\n' >&2
printf 'Sampling hover for about 24 seconds; reproduce the transfer and any dismissal.\n' >&2
printf 'Two seconds to move the pointer away from this terminal...\n' >&2
sleep 2
failed=0
popup_seen=0
popup_open_transitions=0
popup_dismissed_after_seen=0
previous_popup_open=0
for ((i=0; i<100; i++)); do
    printf 'sample=%02d utc=%s\n' "$i" "$(date -u +%FT%T.%3NZ)" >> "$output_dir/hover-snapshots.log"
    snapshot_rc=0
    snapshot_output="$("${qs_cmd[@]}" ipc call abyssHoverProbe snapshot 2>&1)" || snapshot_rc=$?
    printf '%s\n' "$snapshot_output" >> "$output_dir/hover-snapshots.log"
    if ((snapshot_rc != 0)) || [[ "$snapshot_output" != *'"family":"abyss"'* ]]; then
        printf 'error=invalid_snapshot qs_exit=%d\n' "$snapshot_rc" >> "$output_dir/hover-snapshots.log"
        failed=$((failed + 1))
    else
        # Track only objective observed open/close transitions; do not infer
        # physical mouse motion or a hover-loss cause from the last sample.
        if [[ "$snapshot_output" == *'"liquidPopupsOpen":true'* ]]; then
            popup_seen=1
            if ((previous_popup_open == 0)); then
                popup_open_transitions=$((popup_open_transitions + 1))
            fi
            previous_popup_open=1
        elif ((previous_popup_open == 1)); then
            popup_dismissed_after_seen=$((popup_dismissed_after_seen + 1))
            previous_popup_open=0
        fi
    fi
    sleep .15
done
{
    printf 'snapshot_failures=%d\n' "$failed"
    printf 'popup_seen_during_capture=%d\n' "$popup_seen"
    printf 'popup_open_transition_count=%d\n' "$popup_open_transitions"
    printf 'popup_open_to_closed_transition_count=%d\n' "$popup_dismissed_after_seen"
    printf 'popup_open_to_closed_transition_observed=%d\n' "$((popup_dismissed_after_seen>0))"
} >> "$output_dir/identity.txt"
if ((popup_seen == 0)); then
    printf 'WARNING: no Popup opened during the 100 hover samples.\n' \
        | tee "$output_dir/hover-not-observed.txt" >&2
fi
printf 'Diagnostic folder: %s\n' "$output_dir"
printf 'Archive created on exit; upload only the .tar.gz file printed below.\n'
if ((failed>0)); then exit 2; fi
