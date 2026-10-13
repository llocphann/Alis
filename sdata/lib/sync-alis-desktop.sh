#!/usr/bin/env bash
# Reconcile public Alis desktop IDs after repo-copy UPDATE.
# This does not change the legacy inir.service, ShellId, XDG user state, or
# the user's existing foreign Alis desktop entries/icon.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    printf 'Usage: sync-alis-desktop.sh REPO_ROOT XDG_BIN_HOME XDG_DATA_HOME\n' >&2
    exit 2
fi
repo="$1"
bin_home="$2"
data_home="$3"
app_dir="$data_home/applications"
icon_dir="$data_home/icons/hicolor/scalable/apps"

# Verify all source artifacts before changing the destination.
for entry in alis.desktop alis-settings.desktop; do
    src="$repo/assets/applications/$entry"
    [[ -f "$src" ]] || { printf 'Alis desktop source missing: %s\n' "$src" >&2; exit 1; }
    grep -Fxq 'X-Alis-Managed=true' "$src" ||
        { printf 'Alis desktop ownership marker missing: %s\n' "$src" >&2; exit 1; }
    grep -Fxq 'Icon=alis' "$src" ||
        { printf 'Alis desktop icon ID missing: %s\n' "$src" >&2; exit 1; }
    grep -q '^Exec=' "$src" ||
        { printf 'Alis desktop Exec missing: %s\n' "$src" >&2; exit 1; }
done
grep -Fxq 'NoDisplay=true' "$repo/assets/applications/alis.desktop" ||
    { printf 'Alis shell entry must stay hidden (single session)\n' >&2; exit 1; }
if grep -Fxq 'NoDisplay=true' "$repo/assets/applications/alis-settings.desktop"; then
    printf 'Alis Settings entry must remain visible\n' >&2
    exit 1
fi
src_icon="$repo/assets/icons/desktop-symbolic.svg"
[[ -f "$src_icon" ]] || { printf 'Alis icon source missing\n' >&2; exit 1; }

mkdir -p -- "$app_dir" "$icon_dir"

sync_entry() {
    local entry="$1" action="$2"
    local source="$repo/assets/applications/$entry"
    local target="$app_dir/$entry"
    local tmp=""

    if [[ -e "$target" || -L "$target" ]]; then
        if [[ ! -f "$target" || -L "$target" ]] ||
                ! grep -Fxq 'X-Alis-Managed=true' "$target"; then
            printf 'SKIP foreign Alis desktop file: %s\n' "$target"
            return 0
        fi
    fi

    tmp="$(mktemp "$app_dir/.alis-entry.XXXXXXXX")"
    # Quote executable path for freedesktop Exec when XDG_BIN_HOME contains
    # spaces; awk avoids sed replacement metacharacter corruption.
    if ! awk -v cmd="Exec=\"${bin_home}/alis\" $action" '
        /^Exec=/ {print cmd; found++; next}
        {print}
        END {if (found != 1) exit 1}
    ' "$source" > "$tmp"; then
        rm -f -- "$tmp"
        printf 'Unable to render %s\n' "$entry" >&2
        return 1
    fi
    chmod 644 "$tmp"
    if ! mv -fT -- "$tmp" "$target"; then
        rm -f -- "$tmp"
        return 1
    fi
}

sync_entry alis.desktop 'service restart'
sync_entry alis-settings.desktop settings

icon_target="$icon_dir/alis.svg"
if [[ -e "$icon_target" || -L "$icon_target" ]]; then
    if [[ ! -f "$icon_target" || -L "$icon_target" ]] ||
            ! cmp -s -- "$src_icon" "$icon_target"; then
        printf 'SKIP foreign Alis icon: %s\n' "$icon_target"
    fi
else
    tmp="$(mktemp "$icon_dir/.alis-icon.XXXXXXXX")"
    if ! install -m 644 -- "$src_icon" "$tmp"; then
        rm -f -- "$tmp"
        exit 1
    fi
    if ! mv -fT -- "$tmp" "$icon_target"; then
        rm -f -- "$tmp"
        exit 1
    fi
fi
printf 'Alis desktop IDs reconciled; legacy inir IDs and session remain unchanged.\n'
