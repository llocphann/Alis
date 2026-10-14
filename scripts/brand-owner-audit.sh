#!/usr/bin/env bash
# BRAND-R01 owner evidence helper: read-only, no service operations or writes.
set -uo pipefail

audit_blocked=0
audit_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Audit the identity shipped by this checkout. The compatibility branch still
# uses inir.service; the isolated canonical branch MUST use alis.service.
# Never assume one unit is authoritative merely because it is installed.
expected_owner=unknown
if [[ -f "$audit_repo/shell.qml" ]] &&
   grep -Fxq '//@ pragma ShellId alis' "$audit_repo/shell.qml"; then
    expected_owner=alis
elif [[ -f "$audit_repo/shell.qml" ]] &&
     grep -Fxq '//@ pragma ShellId inir' "$audit_repo/shell.qml"; then
    expected_owner=inir
else
    printf 'BLOCKER: cannot establish this checkout\x27s ShellId.\n'
    audit_blocked=2
fi
printf 'BRAND-R01 desktop read-only audit\n'
printf 'Captured (UTC): %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'This is diagnostic evidence, not a substitute for owner visual approval.\n\n'

printf 'Public and legacy CLI paths:\n'
for cmd in alis inir qs; do
    if command -v "$cmd" >/dev/null 2>&1; then
        printf '  %s: %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '  %s: NOT FOUND\n' "$cmd"
    fi
done

if command -v alis >/dev/null 2>&1; then
    printf '\nInstalled Alis version (read-only):\n'
    alis version --json 2>&1 || printf '  Unable to read installed Alis version\n'
fi

printf '\nSession ownership (expected ShellId and sole unit: %s):\n' "$expected_owner"
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user show inir.service \
        --property=LoadState,ActiveState,SubState,MainPID,FragmentPath \
        --no-pager 2>&1 || printf '  User systemd unit unavailable\n'
    # An alis.service alias, if present, is diagnostic only. Never start it here.
    systemctl --user show alis.service \
        --property=LoadState,ActiveState,MainPID,FragmentPath \
        --no-pager 2>&1 || true
    # A second active service is a hard R10 release blocker. Read-only query.
    _inir_active="$(systemctl --user show inir.service -p ActiveState --value --no-pager 2>/dev/null || true)"
    _alis_active="$(systemctl --user show alis.service -p ActiveState --value --no-pager 2>/dev/null || true)"
    if [[ "$_inir_active" == active && "$_alis_active" == active ]]; then
        printf '\nBLOCKER: inir.service and alis.service are BOTH active. Do not verify the release.\n'
        audit_blocked=2
    fi
    case "$expected_owner" in
        alis)
            if [[ "$_alis_active" != active ]]; then
                printf '\nBLOCKER: canonical ShellId alis requires alis.service active; observed %s.\n' "${_alis_active:-unknown}"
                audit_blocked=2
            fi
            if [[ "$_inir_active" == active ]]; then
                printf 'BLOCKER: canonical Alis checkout still has legacy inir.service active.\n'
                audit_blocked=2
            fi
            # In a repo-copy cutover, a live old Type=dbus unit file retains
            # its BusName allocation even when the process is inactive.
            # Fresh canonical installs have no legacy unit or archive.
            _old_unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/inir.service"
            _retired_unit="${XDG_STATE_HOME:-$HOME/.local/state}/alis-cutover-backups/retired-inir.service"
            if [[ "$_alis_active" == active &&
                  ( -e "$_old_unit" || -L "$_old_unit" ||
                    -e "$_retired_unit" || -L "$_retired_unit" ) ]]; then
                if [[ -L "$_old_unit" &&
                      "$(readlink -- "$_old_unit")" == /dev/null &&
                      -f "$_retired_unit" && ! -L "$_retired_unit" ]] &&
                   grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' "$_retired_unit"; then
                    printf 'VERIFIED: original iNiR unit is masked; byte-retained rollback archive exists.\n'
                else
                    printf 'BLOCKER: original unit/archive may still allocate the Alis D-Bus name; review masked unit and retired archive.\n'
                    audit_blocked=2
                fi
            fi
            ;;
        inir)
            if [[ "$_inir_active" != active ]]; then
                printf '\nBLOCKER: compatibility ShellId inir requires inir.service active; observed %s.\n' "${_inir_active:-unknown}"
                audit_blocked=2
            fi
            ;;
    esac
else
    printf '  systemctl not installed\n'
    printf 'BLOCKER: cannot verify sole systemd user-session ownership.\n'
    audit_blocked=2
fi

printf '\nXDG namespace paths (no file contents inspected):\n'
for base in \
    "${XDG_CONFIG_HOME:-$HOME/.config}" \
    "${XDG_CACHE_HOME:-$HOME/.cache}" \
    "${XDG_DATA_HOME:-$HOME/.local/share}" \
    "${XDG_STATE_HOME:-$HOME/.local/state}"; do
    for name in inir alis; do
        path="$base/$name"
        if [[ -L "$path" ]]; then
            printf '  symlink: %s -> %s\n' "$path" "$(readlink -- "$path")"
        elif [[ -d "$path" ]]; then
            printf '  directory: %s\n' "$path"
        elif [[ -e "$path" ]]; then
            printf '  non-directory path: %s (review manually)\n' "$path"
        fi
    done
done

printf '\nDesktop launchers:\n'
for base in \
    "${XDG_DATA_HOME:-$HOME/.local/share}/applications" \
    /usr/local/share/applications \
    /usr/share/applications; do
    for entry in alis.desktop alis-settings.desktop inir.desktop inir-settings.desktop; do
        if [[ -f "$base/$entry" ]]; then
            printf '  %s: ' "$base/$entry"
            grep -m1 '^Name=' "$base/$entry" || printf '(no Name key)\n'
        fi
    done
done

cat <<'ACCEPTANCE'

Owner-only desktop acceptance checklist (record PASS/FAIL with screenshot/log):
  1. Fresh install: Alis welcome and desktop application labels display correctly.
  2. Upgrade: previous themes, layout, notes, AI model choices and wizard marker survive.
  3. Terminal: alis help/status/settings work; retired inir CLI is not a required public command.
  4. Session: expected ShellId/service matches the tested branch; one Quickshell tray watcher after cold login.
  5. Niri: keybinds, IPC routing, popups, fullscreen OSD and recorder still operate.
  6. Migration: no unexpected alis files; opt-in aliases never replace foreign data.
  7. Rollback: validate the original settings, CLI, service and data recovery only with owner approval.
Do not mark issue #64 owner-verified until these checks are completed.
ACCEPTANCE

exit "$audit_blocked"
