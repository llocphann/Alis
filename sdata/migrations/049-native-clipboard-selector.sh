#!/usr/bin/env bash
# Migration 049: Route existing clipboard text watchers through native-dispatch
#
# Existing installs that already applied migrations 032/034 still point wl-paste
# directly at clipboard-store.py. The reversible Rust trial selector only works
# when the watcher enters through scripts/native-dispatch. Python remains the
# default backend, so this migration changes routing without changing behavior.

MIGRATION_ID="049-native-clipboard-selector"
MIGRATION_TITLE="Route clipboard history through the native backend selector"
MIGRATION_DESCRIPTION="Updates an existing wl-paste text watcher to call native-dispatch clipboard-store. Python remains the default and Rust can be enabled or rolled back with INIR_NATIVE_BACKEND."
MIGRATION_TARGET_FILE="~/.config/niri/config.d/50-startup.kdl"
MIGRATION_REQUIRED=true

_cliphist_startup_file="${HOME}/.config/niri/config.d/50-startup.kdl"
_old_filter='~/.config/quickshell/inir/scripts/clipboard-store.py'
_new_filter='~/.config/quickshell/inir/scripts/native-dispatch clipboard-store'

migration_check() {
    [[ -f "$_cliphist_startup_file" ]] || return 1
    grep -Fq "$_old_filter" "$_cliphist_startup_file" 2>/dev/null
}

migration_preview() {
    echo -e "${STY_RED}- wl-paste --type text --watch ${_old_filter}${STY_RST}"
    echo -e "${STY_GREEN}+ wl-paste --type text --watch ${_new_filter}${STY_RST}"
    echo ""
    echo "Python remains the default backend. This only makes the existing watcher"
    echo "participate in the reversible Python/Rust selector."
}

migration_apply() {
    [[ -f "$_cliphist_startup_file" ]] || return 1

    sed -i "s|$_old_filter|$_new_filter|g" "$_cliphist_startup_file"

    grep -Fq "$_new_filter" "$_cliphist_startup_file"
}
