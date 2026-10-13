#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$repo/sdata/lib/sync-alis-desktop.sh"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
fail() { printf 'FAIL: Alis desktop update: %s\n' "$*" >&2; exit 1; }
mkdir -p "$root/bin with spaces" "$root/data" "$root/source/assets/applications" "$root/source/assets/icons"
cp "$repo/assets/applications/alis.desktop" "$repo/assets/applications/alis-settings.desktop" "$root/source/assets/applications/"
cp "$repo/assets/icons/desktop-symbolic.svg" "$root/source/assets/icons/desktop-symbolic.svg"
src="$root/source"
dest="$root/data"
bash "$runner" "$src" "$root/bin with spaces" "$dest" >/dev/null ||
    fail 'fresh update did not reconcile Alis desktop IDs'
shell="$dest/applications/alis.desktop"
settings="$dest/applications/alis-settings.desktop"
icon="$dest/icons/hicolor/scalable/apps/alis.svg"
[[ -f "$shell" && -f "$settings" && -f "$icon" ]] ||
    fail 'Alis app IDs or icon missing after staged update'
grep -Fxq 'NoDisplay=true' "$shell" || fail 'shell entry became visible'
grep -Fxq 'Name=Alis Settings' "$settings" || fail 'settings name wrong'
if grep -Fxq 'NoDisplay=true' "$settings"; then fail 'settings entry hidden'; fi
grep -Fxq "Exec=\"$root/bin with spaces/alis\" settings" "$settings" ||
    fail 'Exec with spaces was not quoted'
grep -Fxq 'X-Alis-Managed=true' "$settings" || fail 'managed marker lost'
cmp -s "$src/assets/icons/desktop-symbolic.svg" "$icon" || fail 'icon bytes changed'
bash "$runner" "$src" "$root/bin with spaces" "$dest" >/dev/null ||
    fail 'update is not repeatable'

# A foreign desktop file and an unrelated icon belong to the user.
printf 'custom settings\n' > "$settings"
printf '<svg>custom</svg>\n' > "$icon"
bash "$runner" "$src" "$root/bin with spaces" "$dest" > "$root/skip.log" ||
    fail 'foreign collision should not block safe entries'
[[ "$(cat "$settings")" == 'custom settings' ]] || fail 'foreign settings overwritten'
[[ "$(cat "$icon")" == '<svg>custom</svg>' ]] || fail 'foreign icon overwritten'
grep -Fq 'SKIP foreign Alis desktop file' "$root/skip.log" ||
    fail 'foreign settings collision not reported'
grep -Fq 'SKIP foreign Alis icon' "$root/skip.log" ||
    fail 'foreign icon collision not reported'

# Foreign symlinks must never be followed/overwritten.
rm -- "$shell"
printf 'foreign shell file\n' > "$root/user-shell"
ln -s "$root/user-shell" "$shell"
bash "$runner" "$src" "$root/bin with spaces" "$dest" >/dev/null ||
    fail 'foreign shell symlink did not get skipped'
[[ -L "$shell" && "$(cat "$root/user-shell")" == 'foreign shell file' ]] ||
    fail 'foreign shell symlink/target changed'

# Malformed source must fail before modifying any existing user entries.
cp "$src/assets/applications/alis-settings.desktop" "$root/restore-settings"
sed -i '/^X-Alis-Managed=true$/d' "$src/assets/applications/alis-settings.desktop"
if bash "$runner" "$src" "$root/bin with spaces" "$dest" >/dev/null 2>&1; then
    fail 'missing source ownership marker accepted'
fi
[[ "$(cat "$settings")" == 'custom settings' ]] || fail 'malformed source changed user desktop entry'
grep -Fq 'sdata/lib/sync-alis-desktop.sh' "$repo/setup" ||
    fail 'repo-copy setup update path does not call public app-ID reconciliation'
printf 'PASS: repo-copy update installs Alis desktop IDs/icon and preserves foreign ownership\n'
