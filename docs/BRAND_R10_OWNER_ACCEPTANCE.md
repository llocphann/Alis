# BRAND-R01 — R10 owner desktop release acceptance

Issue: https://github.com/llocphann/Alis/issues/64

**Status: PENDING OWNER VERIFIED.** Automated CI and a read-only audit are not evidence of a successful physical Wayland/Quickshell session.

## Preparation (non-destructive)

Check out the **exact branch and commit** proposed for acceptance and record its SHA. Run `bash scripts/brand-owner-audit.sh` **as the affected desktop user**, not with `sudo`. Save the command's complete output locally. The audit compares the checked-out `shell.qml` ShellId with the active systemd unit: `dev` compatibility runtime expects only `inir.service`, while the isolated canonical Alis runtime expects only `alis.service`. A missing expected unit, the wrong active unit, or both units active is a **BLOCKER (exit 2)**. Do not start a second owner to silence the audit. This source audit alone does not prove the installed ShellId matches the running desktop; separately verify installed SHA and systemd unit content.

Use a disposable account/VM to evaluate first-run behavior. Preserve the original account's configs, notes, layouts, credentials, models and wizard marker before exercising upgrade/rollback. Never publish sensitive config contents in the issue.

## Mandatory desktop checks

| Check | Expected result | Owner result |
|---|---|---|
| Fresh install (disposable user) | Alis first-run greeting/wizard and app names display correctly | PENDING |
| Existing user upgrade | Existing theme, wallpaper, layout, notes, models and first-run marker remain unchanged | PENDING |
| App entry IDs | One visible Alis Settings entry, hidden legacy `inir-settings.desktop`, no duplicate menu item | PENDING |
| Public CLI | `alis help`, `alis settings`, `alis status` work; no legacy `inir` public CLI required (it is disabled on current `dev` and removed in the canonical source branch) | PENDING |
| Session ownership | Exactly one Quickshell session/DBus tray watcher after cold login and restart; canonical release runs `alis.service` only with `ShellId alis`, no concurrent `inir.service` | PENDING |
| Niri input/IPC | Shortcuts, `alis` IPC and compatible targets behave as before | PENDING |
| Popups/notifications | Settings, calendar, network, weather and notification popups render/respond | PENDING |
| Fullscreen and recording | Volume/brightness OSD and recording controls work without a second session | PENDING |
| XDG data cutover | Original iNiR/upstream config/cache/data/state bytes remain intact; Alis copies match and foreign Alis paths refuse overwrite (existing migration 061 aliases must be handled explicitly) | PENDING |
| Revert/rollback | Owner-approved cutover failure restores the original owner; explicit rollback after a successful live cutover is still a separate release blocker | PENDING |
| Arch/Nix/source paths | Chosen production install mode survives upgrade/reinstall without ownership collisions | PENDING |

## Release decision

Collect screenshots/logs for each line, the exact tested SHA, Niri/Quickshell versions, install mode and UTC date. If a check fails, report a blocking issue. Mark **Owner Verified** and close Issue #64 only when every applicable check is recorded as PASS by the owner; code automation may never self-approve R10. Stable must remain untouched until the owner explicitly authorizes promotion.

## Branch-specific release boundary

The `brand-r01-canonical-alis` branch is **not installable or owner-verified** as of this source-stage checklist. Its simulated one-owner cutover does **not** validate a real Arch/Nix package migration, cold boot, live data-path rollback or all local validator contracts. Keep `dev` and `stable` untouched; do not merge or run the canonical cutover against the owner's active desktop until all gates pass and the owner authorizes that exact tested SHA. Historical iNiR attribution belongs only under About → Based on; Aqua and Waffle are independent upstream product names.
