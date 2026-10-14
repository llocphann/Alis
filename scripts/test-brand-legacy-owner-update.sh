#!/usr/bin/env bash
# BRAND-R01: retained inactive legacy unit must not block post-cutover update.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
awk '/^brand_legacy_owner_present\(\) \{/ {on=1} on {print} on && /^}/ {exit}' "$repo/setup" > "$tmp/fn"
[[ "$(grep -c '^brand_legacy_owner_present()' "$tmp/fn")" == 1 ]] || exit 1
source "$tmp/fn"
export XDG_CONFIG_HOME="$tmp/config"
mkdir -p "$XDG_CONFIG_HOME/systemd/user" "$XDG_CONFIG_HOME/quickshell/alis"
printf '%s\n' '//@ pragma ShellId alis' > "$XDG_CONFIG_HOME/quickshell/alis/shell.qml"
export OLD_ACTIVE=0 NEW_ACTIVE=0 OLD_ENABLED=disabled OLD_UNIT=1
systemctl() {
    [[ "${1:-}" == --user ]] || return 2
    shift
    case "${1:-}" in
        cat) [[ "$OLD_UNIT" == 1 ]] ;;
        is-active)
            [[ "${2:-}" == --quiet ]] || return 2
            case "${3:-}" in
                inir.service) [[ "$OLD_ACTIVE" == 1 ]] ;;
                alis.service) [[ "$NEW_ACTIVE" == 1 ]] ;;
                *) return 1 ;;
            esac ;;
        is-enabled) printf '%s\n' "$OLD_ENABLED" ;;
        *) return 2 ;;
    esac
}
block() { brand_legacy_owner_present || { echo "FAIL: accepted $1" >&2; exit 1; }; }
ready() { if brand_legacy_owner_present; then echo "FAIL: blocked $1" >&2; exit 1; fi; }
OLD_UNIT=0; ready 'fresh without old unit'
OLD_UNIT=1; OLD_ACTIVE=1; block 'live legacy shell'
OLD_ACTIVE=0; NEW_ACTIVE=0; block 'pre-cutover old unit even inactive'
NEW_ACTIVE=1; OLD_ENABLED=enabled; block 'old unit still enabled'
OLD_ENABLED=masked; block 'ambiguous old unit'
OLD_ENABLED=disabled; OLD_ACTIVE=1; block 'two active shell owners'
OLD_ACTIVE=0
mkdir -p "$XDG_CONFIG_HOME/systemd/user/niri.service.wants"
ln -s ../inir.service "$XDG_CONFIG_HOME/systemd/user/niri.service.wants/inir.service"
block 'lingering old compositor wants'
rm -- "$XDG_CONFIG_HOME/systemd/user/niri.service.wants/inir.service"
ready 'successful cutover while old unit remains for rollback'
OLD_ENABLED=static; ready 'static unlinked legacy unit'
# A real canonical cutover retires the original service OUTSIDE the systemd
# search path and masks its name; only that verified combination is allowed.
OLD_ENABLED=masked; block 'mask without trusted archive'
mkdir -p "$tmp/state/alis-cutover-backups"
printf '%s\n' '[Service]' 'BusName=org.kde.StatusNotifierWatcher' > "$tmp/state/alis-cutover-backups/retired-inir.service"
ln -s /dev/null "$XDG_CONFIG_HOME/systemd/user/inir.service"
export XDG_STATE_HOME="$tmp/state"
ready 'masked old unit with trusted original archive'
rm "$tmp/state/alis-cutover-backups/retired-inir.service"
block 'masked old unit without recovery archive'
printf '%s\n' '[Service]' 'BusName=org.kde.StatusNotifierWatcher' > "$tmp/state/alis-cutover-backups/retired-inir.service"
OLD_ACTIVE=1; block 'masked original service active'
OLD_ACTIVE=0
printf '%s\n' '//@ pragma ShellId inir' > "$XDG_CONFIG_HOME/quickshell/alis/shell.qml"
block 'unstaged canonical runtime'
echo 'PASS: update blocked until safe one-owner cutover; retained old unit permitted afterward'
