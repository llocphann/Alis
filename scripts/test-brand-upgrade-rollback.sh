#!/usr/bin/env bash
# BRAND-R01 R9: staged fresh/upgrade/reinstall/rollback without a desktop or user mutations.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
fail() { printf 'FAIL: BRAND-R01 staged upgrade: %s\n' "$*" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
stage="$tmp/package-root"
home="$tmp/home"
mkdir -p "$home/.config/alis" "$home/.local/state/quickshell/user" "$stage"
printf 'settings private, unchanged\n' > "$home/.config/alis/config.json"
printf 'owner-welcome-complete\n' > "$home/.local/state/quickshell/user/first_run.txt"
before_config="$(sha256sum "$home/.config/alis/config.json" | cut -d' ' -f1)"
before_marker="$(sha256sum "$home/.local/state/quickshell/user/first_run.txt" | cut -d' ' -f1)"
make_args=("DESTDIR=$stage" "PREFIX=/usr")
install_staged() { make -s install-bin install-desktop install-icon "${make_args[@]}"; }
uninstall_staged() { make -s uninstall-bin uninstall-desktop uninstall-icon "${make_args[@]}"; }
check_staged() {
    [[ -x "$stage/usr/bin/alis" ]] || fail 'public Alis command absent'
    [[ ! -e "$stage/usr/bin/alis" ]] || fail 'retired Alis command unexpectedly installed'
    grep -Fxq 'Name=Alis Settings' "$stage/usr/share/applications/alis-settings.desktop" ||
        fail 'Alis Settings entry missing'
    [[ ! -e "$stage/usr/share/applications/alis-settings.desktop" ]] ||
        fail 'retired Alis Settings entry unexpectedly packaged'
    [[ -s "$stage/usr/share/icons/hicolor/scalable/apps/alis.svg" ]] ||
        fail 'public icon absent'
}
check_user_data() {
    [[ "$(sha256sum "$home/.config/alis/config.json" | cut -d' ' -f1)" == "$before_config" ]] ||
        fail 'owner configuration changed by package operations'
    [[ "$(sha256sum "$home/.local/state/quickshell/user/first_run.txt" | cut -d' ' -f1)" == "$before_marker" ]] ||
        fail 'First Run marker changed by package operations'
}
install_staged
check_staged
check_user_data
# Package refresh must be idempotent, then uninstall must touch only staged files.
install_staged
check_staged
check_user_data
uninstall_staged
[[ ! -e "$stage/usr/bin/alis" ]] || fail 'Alis command remains after staged uninstall'
[[ ! -e "$stage/usr/share/applications/alis-settings.desktop" ]] ||
    fail 'Alis desktop entry remains after staged uninstall'
[[ ! -e "$stage/usr/share/icons/hicolor/scalable/apps/alis.svg" ]] ||
    fail 'Alis icon remains after staged uninstall'
check_user_data
# Downgrade/reinstall is able to restore the same compatibility IDs.
install_staged
check_staged
check_user_data
# Fail closed rather than overwriting a conflicting user-owned launcher.
printf 'foreign owner\n' > "$stage/usr/bin/alis"
if install_staged >/dev/null 2>&1; then
    fail 'upgrade overwrote a foreign-owned public command'
fi
[[ "$(cat "$stage/usr/bin/alis")" == 'foreign owner' ]] ||
    fail 'foreign launcher was mutated'
check_user_data
printf '%s\n' 'PASS: staged clean install, repeat upgrade, uninstall, reinstall and foreign-file collision'
