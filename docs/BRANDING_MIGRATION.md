# BRAND-R01 — Alis rename inventory, compatibility boundaries, and release gates

Updated: 2026-10-13. Tracking issue: [#64](https://github.com/llocphann/Alis/issues/64).

This is an implementation inventory, not a declaration of completion. The public product name is **Alis**. Existing persistent identities are not automatically safe to rename. Changes are developed on `dev` only; `stable` is untouched.

## Consumer map and classification

| Identifiers and references | Source examples / consumers | Category | Required transition |
|---|---|---|---|
| First-run heading, greeting, notification sender | `welcome.qml`, `services/FirstRunExperience.qml`, `modules/bootGreeting/BootGreeting.qml` | Public identity | Display Alis; retain `first_run.txt` and `welcomeWizard.completed/skipped` |
| Settings, Update UI, keybind help | `services/ShellUpdates.qml`, `modules/settings/SettingsPageRegistryData.qml`, `modules/bar/ShellUpdateIndicator.qml`, `services/deferred/NiriKeybinds.qml` | Public identity | Display Alis; do not rewrite saved style/layout enums |
| CLI and completions | `scripts/inir`, `scripts/alis`, `scripts/completions/*` | Public command plus compatibility alias | `alis` delegates to current `inir` process owner; both commands must accept old flags/IPC |
| Runtime ShellId and selector | `shell.qml` (`ShellId inir`), `scripts/inir` (`qs -p`), `~/.config/quickshell/inir` | High-risk runtime interface | Keep one Quickshell session; coordinated switch required with rollback |
| User service and compositor wants links | `assets/systemd/inir.service`, `setup`, `Makefile`, Arch/Nix recipes, Niri startup KDL | High-risk session owner | A new unit must replace—not accompany—the old owner after tested stop/disable/migrate/start |
| Configuration roots and overrides | `scripts/lib/config-path.sh`, `sdata/migrations/019-config-dir-rename-compat.sh`, `INIR_*` | Persistent compatibility interface | Preserve `~/.config/inir` and `illogical-impulse` resolution; dry-run, backup and collision checks before moving |
| Shared and per-user state | `services/FirstRunExperience.qml`, `modules/common/Config.qml`, scripts referencing XDG state/cache/data paths | User data | Do not reset themes, layouts, credentials, notes, models, wallpaper, wizard marker or custom overrides |
| IPC/DBus/Niri process selectors | `scripts/lib/ipc-registry.sh`, `docs/IPC.md`, ShellId, `org.kde.StatusNotifierWatcher` | Runtime ABI | Preserve established targets, function aliases and DBus watcher uniqueness |
| Native helper/Polkit interfaces | `native/inir-*`, `assets/helpers/inir-*`, `assets/polkit/org.inir.*` | Native ABI / privileged integration | Treat executable, socket and policy IDs as ABI until mapped and upgrade-tested |
| Install/update packaging | `setup`, `sdata/subcmd-install/3.files.sh`, Arch PKGBUILD/.SRCINFO, `nix/package.nix`, `Makefile` | Public installer with legacy package IDs | Install Alis CLI; retain installed `inir-shell` package and `inir.service` until coordinated ownership migration |
| Update URLs and docs | `sdata/lib/versioning.sh`, `scripts/release.sh`, `scripts/wiki-sync.sh`, `docs/INSTALL.md`, `docs/SETUP.md` | Public identity | Follow `llocphann/Alis`; keep historical commit SHA references |
| Third-party or historical names | Hadalird/Hadanion repositories, Waffle/Aqua/iRiS, prior commits, archived investigations | External / historical | Do not rename without explicit authorization; do not falsify historical evidence |

## Safe rollout sequence

1. **Public and compatibility layer.** Use Alis-facing UI, commands, update links and packaged CLI forwarding without changing ShellId or runtime ownership.
2. **Read-only upgrade inventory.** Identify configuration roots, symlinks, stale per-user/system unit files, XDG overrides and foreign files before any migration.
3. **Transactional migration design.** Stage backups and rollback paths; make every operation idempotent, refuse conflicting real trees and preserve credentials/notes/models/first-run markers.
4. **Single-owner runtime cutover.** Switch Quickshell selector, service unit/wants and Niri entry points as one coordinated transaction after stopped-state and restart/cold-boot tests. Never enable parallel `inir.service` and `alis.service`.
5. **Package and ABI qualification.** Validate installed Arch/Nix/Make payloads, Polkit and native helpers, uninstall/reinstall and source-sync variations.
6. **Owner release acceptance.** Verify on physical Niri/Quickshell for greeting, updates, menus, popups, IPC, restart, fullscreen and rollback. Issue remains open until approval.

## Present guardrails / open checks

- The `alis` launcher currently forwards to the legacy runtime, by design; it is not an independent session.
- `inir.service`, `ShellId inir`, `~/.config/inir`, XDG user state and `INIR_*` overrides remain the active compatibility identities.
- Upgrades are **not** permitted to trigger a fresh wizard solely because of the rebrand.
- Real desktop acceptance, collision-safe data migration and full canonical validator PASS are **not yet verified**.
- The full maintainer validator contains unrelated preexisting/parallel failures; record the exact SHA and log evidence before attributing failures to this work.

This matrix is used to prevent an unsafe bulk string replace; it does not supersede the owner's issue acceptance checklist.
