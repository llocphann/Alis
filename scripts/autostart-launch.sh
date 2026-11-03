#!/usr/bin/env bash
# Launch an Alis-managed Niri autostart entry after the session tray watcher
# (org.kde.StatusNotifierWatcher) is ready on D-Bus so tray/taskbar icons do
# not race ahead of Quickshell and xembedsniproxy on cold login.

set -u

mode="${1:-app}"
target="${2:-}"

if [[ -z "$target" && -n "$mode" && "$mode" != "app" && "$mode" != "sh" ]]; then
    target="$mode"
    mode="app"
fi

if [[ -z "$target" ]]; then
    exit 0
fi

wait_for_tray_watcher() {
    command -v busctl >/dev/null 2>&1 || return 0
    local i
    for ((i = 0; i < 75; i++)); do
        if busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; then
            # Let Quickshell finish its first-frame (shellEntryReady) and Tier 3
            # initialization before cold-starting heavy autostart applications.
            sleep 1.0
            return 0
        fi
        sleep 0.2
    done
    return 0
}

stagger_autostart_slot() {
    command -v flock >/dev/null 2>&1 || return 0
    local lock_file="${XDG_RUNTIME_DIR:-/tmp}/alis-autostart-stagger.lock"
    (
        exec 8>"$lock_file"
        flock 8 || exit 0
        sleep 0.6
    ) 2>/dev/null || true
}

resolve_desktop_id() {
    local requested="$1"
    local stem="${requested%.desktop}"
    local dir file wm_class
    local -a search_dirs=(
        "${XDG_DATA_HOME:-$HOME/.local/share}/applications"
        "$HOME/.local/share/flatpak/exports/share/applications"
        "/var/lib/flatpak/exports/share/applications"
        "/usr/local/share/applications"
        "/usr/share/applications"
    )

    for dir in "${search_dirs[@]}"; do
        if [[ -f "$dir/$stem.desktop" ]]; then
            printf '%s\n' "$stem"
            return 0
        fi
    done

    for dir in "${search_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        for file in "$dir"/*.desktop; do
            [[ -f "$file" ]] || continue
            wm_class="$(awk -F= 'BEGIN{IGNORECASE=1} /^StartupWMClass=/{print $2; exit}' "$file" 2>/dev/null | tr -d '\r')"
            if [[ -n "$wm_class" && "${wm_class,,}" == "${stem,,}" ]]; then
                basename "$file" .desktop
                return 0
            fi
        done
    done

    printf '%s\n' "$stem"
}

wait_for_tray_watcher
stagger_autostart_slot

if [[ "$mode" == "sh" ]]; then
    exec bash -c "$target"
fi

resolved_id="$(resolve_desktop_id "$target")"
if command -v gtk-launch >/dev/null 2>&1; then
    exec gtk-launch "$resolved_id"
fi
exit 1
