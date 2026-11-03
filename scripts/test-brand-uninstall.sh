#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
export HOME="$root/home"
export XDG_CONFIG_HOME="$root/config"
export XDG_CACHE_HOME="$root/cache"
export XDG_STATE_HOME="$root/state"
export XDG_DATA_HOME="$root/data"
export XDG_BIN_HOME="$root/bin"
export DOTS_CORE_CONFDIR="$root/config/alis"
export REPO_ROOT="$repo"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
source "$repo/sdata/lib/uninstall.sh"
mkdir -p "$XDG_BIN_HOME" "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/icons/hicolor/scalable/apps" "$XDG_CONFIG_HOME"
mkdir -p "$XDG_STATE_HOME/quickshell/user"
printf '%s\n' 'very private notes' > "$XDG_STATE_HOME/quickshell/user/notes"
cp "$repo/scripts/alis" "$XDG_BIN_HOME/alis"
cp "$repo/assets/applications/alis.desktop" "$XDG_DATA_HOME/applications/alis.desktop"
cp "$repo/assets/applications/alis-settings.desktop" "$XDG_DATA_HOME/applications/alis-settings.desktop"
cp "$repo/assets/icons/desktop-symbolic.svg" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/alis.svg"
mkdir "$XDG_CONFIG_HOME/alis"
echo preserve > "$XDG_CONFIG_HOME/alis/preferences"
ln -s "$XDG_CONFIG_HOME/alis" "$XDG_CONFIG_HOME/alis"
uninstall_remove_alis_public_entries
for target in "$XDG_BIN_HOME/alis" "$XDG_DATA_HOME/applications/alis.desktop" "$XDG_DATA_HOME/applications/alis-settings.desktop" "$XDG_DATA_HOME/icons/hicolor/scalable/apps/alis.svg"; do
    [[ ! -e "$target" ]] || fail "Alis managed artifact remained: $target"
done
[[ "$(cat "$XDG_CONFIG_HOME/alis/preferences")" == preserve ]] || fail 'original config was deleted'
[[ -L "$XDG_CONFIG_HOME/alis" ]] || fail 'alias was deleted without explicit owner approval'
[[ "$(cat "$XDG_STATE_HOME/quickshell/user/notes")" == 'very private notes' ]] ||
    fail 'personal notes/state removed'
# Default uninstall must never classify personal state, config or managed-only
# public file names as unconditionally deletable.
for user_path in "$XDG_CONFIG_HOME/alis" "$XDG_STATE_HOME/quickshell/user" \
    "$XDG_BIN_HOME/alis" "$XDG_DATA_HOME/applications/alis.desktop"; do
    [[ -z "${ALIS_ONLY_PATHS[$user_path]:-}" ]] ||
        fail "protected/foreign ownership path in unconditional removal list: $user_path"
done
echo 'foreign launcher' > "$XDG_BIN_HOME/alis"
echo 'foreign desktop' > "$XDG_DATA_HOME/applications/alis.desktop"
echo 'foreign settings' > "$XDG_DATA_HOME/applications/alis-settings.desktop"
echo '<svg><!-- custom --></svg>' > "$XDG_DATA_HOME/icons/hicolor/scalable/apps/alis.svg"
uninstall_remove_alis_public_entries
[[ "$(cat "$XDG_BIN_HOME/alis")" == 'foreign launcher' ]] || fail 'foreign launcher modified'
[[ "$(cat "$XDG_DATA_HOME/applications/alis.desktop")" == 'foreign desktop' ]] || fail 'foreign desktop modified'
[[ "$(cat "$XDG_DATA_HOME/applications/alis-settings.desktop")" == 'foreign settings' ]] || fail 'foreign settings modified'
[[ "$(cat "$XDG_DATA_HOME/icons/hicolor/scalable/apps/alis.svg")" == '<svg><!-- custom --></svg>' ]] || fail 'custom icon modified'
uninstall_remove_alis_public_entries || fail 'idempotent no-op'
printf 'PASS: Alis uninstall removes only owned entries and preserves user data\n'
