#!/usr/bin/env bash
# Migration 034: Restore the clipboard text watcher
#
# Clipboard history needs two wl-paste watchers: one for images and one for
# text. Migration 032 rewrites the text one to route through
# native-dispatch clipboard-store, but it only fires when a text watcher line is present. A
# 50-startup.kdl that lost the line entirely — hand-edited, merged from an older
# template, or replaced wholesale — keeps storing images and silently stores no
# text at all. The clipboard panel still opens; it just never sees anything you
# copy, so it serves an ever older history.

MIGRATION_ID="034-cliphist-text-watcher"
MIGRATION_TITLE="Restore the clipboard text watcher"
MIGRATION_DESCRIPTION="Adds back the wl-paste text watcher when 50-startup.kdl only spawns the image one. Without it nothing you copy reaches the clipboard history and the panel shows a frozen list."
MIGRATION_TARGET_FILE="~/.config/niri/config.d/50-startup.kdl"
MIGRATION_REQUIRED=true

_cliphist_startup_file="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.d/50-startup.kdl"
_cliphist_monolithic_file="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
_text_watcher='spawn-at-startup "bash" "-c" "wl-paste --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store \&"'

# Migrations 051/054 normalize startup to "wl-paste --no-newline --type
# text". Matching only "wl-paste --type text" causes a false pending 034
# even though there is already a healthy text watcher. Inspect active
# spawn lines, never commented examples or unrelated prose.
_cliphist_active_typed_watcher() {
    local file="$1" watcher_type="$2"
    [[ -f "$file" ]] || return 1
    awk -v target_type="$watcher_type" '
        /^[[:space:]]*\/\// { next }
        /^[[:space:]]*(spawn-at-startup|spawn-sh-at-startup)[[:space:]]/ && /wl-paste/ {
            if ($0 ~ ("wl-paste.*--type[[:space:]]+" target_type "([[:space:]]|$)")) found=1
        }
        END { exit (found ? 0 : 1) }
    ' "$file"
}

migration_check() {
    [[ -f "$_cliphist_startup_file" ]] || return 1

    # An active text watcher in either Niri startup location already
    # fulfills 034, including the canonical --no-newline form from 051.
    _cliphist_active_typed_watcher "$_cliphist_startup_file" text && return 1
    _cliphist_active_typed_watcher "$_cliphist_monolithic_file" text && return 1

    # Only repair a configured image-only clipboard history, not a disabled
    # watcher or a commented-out example.
    _cliphist_active_typed_watcher "$_cliphist_startup_file" image
}

migration_preview() {
    echo -e "${STY_GREEN}+ wl-paste --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store${STY_RST}"
    echo "  wl-paste --type image --watch cliphist store"
    echo ""
    echo "Only the image watcher is spawned, so copied text never reaches the"
    echo "clipboard history. Existing entries are left untouched."
}

migration_apply() {
    [[ -f "$_cliphist_startup_file" ]] || return 1
    # Applying an already-satisfied historical migration must be harmless,
    # including when the canonical --no-newline watcher is present.
    migration_check || return 0
    sed -i -E "\|wl-paste --type image|i\\${_text_watcher}" "$_cliphist_startup_file" || return 1
    _cliphist_active_typed_watcher "$_cliphist_startup_file" text
}
