#!/usr/bin/env bash
# BRAND-R01: historical migrations must never undo an owner-approved cutover.
# Isolated XDG fixtures only; no changes to the active shell or service manager.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { printf 'FAIL: post-cutover migration guard: %s\n' "$*" >&2; exit 1; }
export HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config"
export XDG_STATE_HOME="$tmp/home/.local/state"
mkdir -p "$XDG_CONFIG_HOME/systemd/user" "$XDG_CONFIG_HOME/niri/config.d" \
  "$XDG_CONFIG_HOME/alis" "$XDG_CONFIG_HOME/illogical-impulse" \
  "$XDG_STATE_HOME/alis-cutover-backups"
unit="$XDG_CONFIG_HOME/systemd/user/alis.service"
new_unit="$XDG_CONFIG_HOME/systemd/user/alis.service"
retired="$XDG_STATE_HOME/alis-cutover-backups/retired-alis.service"
startup="$XDG_CONFIG_HOME/niri/config.d/50-startup.kdl"
printf '[Service]\nType=dbus\nBusName=org.kde.StatusNotifierWatcher\n' > "$retired"
printf '[Service]\nType=dbus\nBusName=org.kde.StatusNotifierWatcher\n' > "$new_unit"
ln -s /dev/null "$unit"
printf '%s\n' \
  '// user clipboard startup, preserved exactly' \
  'spawn-at-startup "bash" "-c" "exec wl-paste --no-newline --type text --watch ~/.config/quickshell/alis/scripts/native-dispatch clipboard-store"' \
  'spawn-at-startup "bash" "-c" "exec wl-paste --type image --watch cliphist store"' > "$startup"
printf '{"panelFamily":"abyss","owner":"canonical"}\n' > "$XDG_CONFIG_HOME/alis/config.json"
printf '{"panelFamily":"ii","owner":"historical"}\n' > "$XDG_CONFIG_HOME/illogical-impulse/config.json"
hash_old="$(sha256sum "$retired" | cut -d ' ' -f1)"
hash_startup="$(sha256sum "$startup" | cut -d ' ' -f1)"
hash_config="$(sha256sum "$XDG_CONFIG_HOME/alis/config.json" | cut -d ' ' -f1)"
for id in 021-systemd-single-instance 051-cliphist-single-watchers; do
  # shellcheck source=/dev/null
  source "$repo/sdata/migrations/$id.sh"
  if migration_check; then fail "$id is still pending after canonical owner handoff"; fi
  result="$(migration_apply)" || fail "$id direct apply rejected safe skip"
  [[ "$result" == *'SKIP: retired'* ]] || fail "$id did not explain historical no-op"
  [[ -L "$unit" && "$(readlink "$unit")" == /dev/null ]] ||
    fail "$id restored legacy unit instead of keeping it masked"
  [[ -f "$new_unit" ]] || fail "$id removed canonical unit"
  [[ "$(sha256sum "$retired" | cut -d ' ' -f1)" == "$hash_old" ]] ||
    fail "$id changed original recovery unit"
  [[ "$(sha256sum "$startup" | cut -d ' ' -f1)" == "$hash_startup" ]] ||
    fail "$id changed canonical clipboard watcher paths"
  [[ "$(sha256sum "$XDG_CONFIG_HOME/alis/config.json" | cut -d ' ' -f1)" == "$hash_config" ]] ||
    fail "$id changed canonical user data"
done
# An archive lost after cutover needs an audit warning, not an unsafe attempt
# to resurrect the old unit through an outdated migration.
rm -- "$retired"
source "$repo/sdata/migrations/021-systemd-single-instance.sh"
if migration_check; then fail 'missing recovery archive reactivated legacy service migration'; fi
source "$repo/sdata/migrations/051-cliphist-single-watchers.sh"
if migration_check; then fail 'missing recovery archive reactivated legacy clipboard migration'; fi
# A truly pre-cutover installation must retain historical migration behavior.
rm -- "$unit" "$new_unit"
printf '[Service]\nType=dbus\nBusName=org.kde.StatusNotifierWatcher\n' > "$unit"
printf '%s\n' \
  'spawn-at-startup "bash" "-c" "wl-paste --type text --watch cliphist store &"' \
  'spawn-at-startup "bash" "-c" "wl-paste --type image --watch cliphist store &"' > "$startup"
source "$repo/sdata/migrations/051-cliphist-single-watchers.sh"
migration_check || fail 'unmigrated duplicate legacy clipboard watchers were skipped'
migration_apply || fail 'pre-cutover clipboard normalization regressed'
if migration_check; then fail 'pre-cutover clipboard normalization remained pending'; fi
# Status should read the same canonical config path as the CLI and live QML.
source "$repo/sdata/lib/environment-variables.sh"
[[ "$(resolve_alis_config_dir)" == "$XDG_CONFIG_HOME/alis" ]] ||
  fail 'canonical configuration did not take precedence over historical path'
awk '/^show_status_environment\(\) \{/ {in_function=1} in_function && /local user_cfg=/ {print; exit}' "$repo/setup" |
  grep -Fq '$(resolve_alis_config_dir)/config.json' ||
  fail 'status reports old user config instead of canonical Alis config'
printf 'PASS: retired service and clipboard migrations cannot revert Alis ownership; legacy repairs retained; canonical status config\n'
