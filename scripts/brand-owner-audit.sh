#!/usr/bin/env bash
# BRAND-R01 owner evidence helper: read-only, no service operations or writes.
set -uo pipefail

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

printf '\nSession ownership (legacy inir.service remains authoritative):\n'
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user show inir.service \
        --property=LoadState,ActiveState,SubState,MainPID,FragmentPath \
        --no-pager 2>&1 || printf '  User systemd unit unavailable\n'
    # An alis.service alias, if present, is diagnostic only. Never start it here.
    systemctl --user show alis.service \
        --property=LoadState,ActiveState,MainPID,FragmentPath \
        --no-pager 2>&1 || true
else
    printf '  systemctl not installed\n'
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
  3. Terminal: alis help/status/settings and legacy inir commands work identically.
  4. Session: exactly one active Quickshell tray watcher; no duplicate session after reboot/restart.
  5. Niri: keybinds, IPC routing, popups, fullscreen OSD and recorder still operate.
  6. Migration: no unexpected alis files; opt-in aliases never replace foreign data.
  7. Rollback: validate snapshot restore and service start only with owner approval.
Do not mark issue #64 owner-verified until these checks are completed.
ACCEPTANCE
