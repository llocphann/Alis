# BRAND-R01 — R10 owner desktop release acceptance

Issue: https://github.com/llocphann/Alis/issues/64

**Status: PENDING OWNER VERIFIED.** Automated CI and a read-only audit are not evidence of a successful physical Wayland/Quickshell session.

## Preparation (non-destructive)

Check out the exact `dev` commit proposed for acceptance and record its SHA. Run `bash scripts/brand-owner-audit.sh` **as the affected desktop user**, not with `sudo`. Save the command's complete output locally. If it exits **2** or reports both `inir.service` and `alis.service` active, stop acceptance: do not restart or enable a second owner.

Use a disposable account/VM to evaluate first-run behavior. Preserve the original account's configs, notes, layouts, credentials, models and wizard marker before exercising upgrade/rollback. Never publish sensitive config contents in the issue.

## Mandatory desktop checks

| Check | Expected result | Owner result |
|---|---|---|
| Fresh install (disposable user) | Alis first-run greeting/wizard and app names display correctly | PENDING |
| Existing user upgrade | Existing theme, wallpaper, layout, notes, models and first-run marker remain unchanged | PENDING |
| App entry IDs | One visible Alis Settings entry, hidden legacy `inir-settings.desktop`, no duplicate menu item | PENDING |
| CLI compatibility | `alis help`, `alis settings`, `alis status` work; legacy `inir` remains functional | PENDING |
| Session ownership | Exactly one Quickshell session and DBus tray watcher after login and restart | PENDING |
| Niri input/IPC | Shortcuts, `alis` IPC and compatible targets behave as before | PENDING |
| Popups/notifications | Settings, calendar, network, weather and notification popups render/respond | PENDING |
| Fullscreen and recording | Volume/brightness OSD and recording controls work without a second session | PENDING |
| Migration 061 | Opt-in XDG links preserve byte-identical original files; unrelated paths untouched | PENDING |
| Revert/rollback | Owner-approved snapshot rollback starts the original service and restores full settings | PENDING |
| Arch/Nix/source paths | Chosen production install mode survives upgrade/reinstall without ownership collisions | PENDING |

## Release decision

Collect screenshots/logs for each line, the exact tested SHA, Niri/Quickshell versions, install mode and UTC date. If a check fails, report a blocking issue. Mark **Owner Verified** and close Issue #64 only when every applicable check is recorded as PASS by the owner; code automation may never self-approve R10. Stable must remain untouched until the owner explicitly authorizes promotion.
