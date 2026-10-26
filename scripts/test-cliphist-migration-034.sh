#!/usr/bin/env bash
# Exercise 034 after 051 canonicalizes the text watcher in a private HOME.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
export HOME="$root/home"
export XDG_CONFIG_HOME="$root/config"
startup="$XDG_CONFIG_HOME/niri/config.d/50-startup.kdl"
monolithic="$XDG_CONFIG_HOME/niri/config.kdl"
mkdir -p -- "$(dirname "$startup")"
source "$repo/sdata/migrations/034-cliphist-text-watcher.sh"
fail() { printf 'FAIL: 034 clipboard migration: %s\n' "$*" >&2; exit 1; }
text_line='spawn-at-startup "bash" "-c" "exec wl-paste --no-newline --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store"'
image_line='spawn-at-startup "bash" "-c" "exec wl-paste --type image --watch cliphist store"'
printf '%s\n%s\n' "$text_line" "$image_line" > "$startup"
baseline="$(sha256sum "$startup" | cut -d' ' -f1)"
if migration_check; then fail 'canonical --no-newline text watcher reported missing'; fi
migration_apply || fail 'idempotent 034 apply rejected valid canonical watcher'
[[ "$(sha256sum "$startup" | cut -d' ' -f1)" == "$baseline" ]] ||
    fail '034 modified the canonical clipboard config'
printf '%s\n%s\n' \
    'spawn-at-startup "bash" "-c" "wl-paste --type text --watch cliphist store"' \
    "$image_line" > "$startup"
if migration_check; then fail 'legacy text watcher reported missing'; fi
printf '%s\n' "$image_line" > "$startup"
printf '%s\n' "$text_line" > "$monolithic"
if migration_check; then fail 'active monolithic text watcher ignored'; fi
rm -- "$monolithic"
printf '%s\n%s\n' "// $text_line" "$image_line" > "$startup"
migration_check || fail 'image-only startup was not detected'
migration_apply || fail 'image-only startup could not restore text'
if migration_check; then fail 'restored text watcher still reports pending'; fi
[[ "$(grep -Ec '^[[:space:]]*spawn-at-startup.*wl-paste.*--type text' "$startup")" -eq 1 ]] ||
    fail 'missing or duplicate text watcher after repair'
printf '%s\n' "// $image_line" > "$startup"
baseline="$(sha256sum "$startup" | cut -d' ' -f1)"
if migration_check; then fail 'disabled image watcher triggered migration'; fi
migration_apply || fail 'no-op for disabled history should succeed'
[[ "$(sha256sum "$startup" | cut -d' ' -f1)" == "$baseline" ]] ||
    fail 'disabled clipboard configuration was rewritten'
printf 'PASS: 034 sees canonical 051 watcher, prevents duplication and preserves disabled history\n'
