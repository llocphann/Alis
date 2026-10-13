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
| Configuration roots and overrides | `scripts/lib/config-path.sh`, `sdata/migrations/019-config-dir-rename-compat.sh`, `sdata/migrations/061-alis-namespace-alias.sh`, `INIR_*` | Persistent compatibility interface | Keep `inir` and `illogical-impulse` as current source of truth; optional checked `alis` symlinks only; no automatic directory move |
| Shared and per-user state | `services/FirstRunExperience.qml`, `modules/common/Config.qml`, scripts referencing XDG state/cache/data paths | User data | Do not reset themes, layouts, credentials, notes, models, wallpaper, wizard marker or custom overrides |
| IPC/DBus/Niri process selectors | `scripts/lib/ipc-registry.sh`, `docs/IPC.md`, ShellId, `org.kde.StatusNotifierWatcher` | Runtime ABI | Preserve established targets, function aliases and DBus watcher uniqueness |
| Native helper/Polkit interfaces | `native/inir-*`, `assets/helpers/inir-*`, `assets/polkit/org.inir.*` | Native ABI / privileged integration | Treat executable, socket and policy IDs as ABI until mapped and upgrade-tested |
| Install/update packaging | `setup`, `sdata/subcmd-install/3.files.sh`, Arch PKGBUILD/.SRCINFO, `nix/package.nix`, `Makefile` | Public installer with legacy package IDs | Ship public Alis CLI, desktop IDs and icon; hide legacy desktop launchers, retain `inir-shell` package and `inir.service` until coordinated ownership migration |
| Update URLs and docs | `sdata/lib/versioning.sh`, `scripts/release.sh`, `scripts/wiki-sync.sh`, `docs/INSTALL.md`, `docs/SETUP.md` | Public identity | Follow `llocphann/Alis`; keep historical commit SHA references |
| Third-party or historical names | Hadalird/Hadanion repositories, Waffle/Aqua/iRiS, prior commits, archived investigations | External / historical | Do not rename without explicit authorization; do not falsify historical evidence |

## Safe rollout sequence

1. **Public and compatibility layer.** Use Alis-facing UI, commands, update links and packaged CLI forwarding without changing ShellId or runtime ownership.
2. **Read-only upgrade inventory.** Identify configuration roots, symlinks, stale per-user/system unit files, XDG overrides and foreign files before any migration.
3. **Transactional migration design.** Stage backups and rollback paths; make every operation idempotent, refuse conflicting real trees and preserve credentials/notes/models/first-run markers.
4. **Single-owner runtime cutover.** Switch Quickshell selector, service unit/wants and Niri entry points as one coordinated transaction after stopped-state and restart/cold-boot tests. Never enable parallel `inir.service` and `alis.service`.
5. **Package and ABI qualification.** Validate installed Arch/Nix/Make payloads, Polkit and native helpers, uninstall/reinstall and source-sync variations.
6. **Owner release acceptance.** Verify on physical Niri/Quickshell for greeting, updates, menus, popups, IPC, restart, fullscreen and rollback. Issue remains open until approval.

## Optional namespace aliases (R6 compatibility milestone)

`061-alis-namespace-alias` is deliberately optional. Run `alis migrate` (or `./setup migrate`), inspect its preview, and explicitly choose **Apply**. The migration only links each existing `$XDG_CONFIG_HOME/inir`, `$XDG_CACHE_HOME/inir`, `$XDG_DATA_HOME/inir`, and `$XDG_STATE_HOME/inir` as the corresponding `alis` path. Missing legacy roots are left alone.

The alias preflight refuses real files, directories, dangling symlinks and foreign symlinks at any destination *before* creating any link. A failed link creation removes only links this attempt created, provided their targets still match. It never copies or deletes legacy data, updates configuration contents, changes Quickshell's `ShellId`, or modifies a systemd unit. The shell continues using the legacy paths.

To undo an applied alias manually, confirm it is a symlink pointing to the adjacent `inir` directory, then **unlink only that `alis` symlink** as the affected user (not its target). Do not delete the original `inir` directory. This is not a complete future migration of the runtime/state namespace, and it is not an automated owner-verified rollback.

Test coverage: `scripts/test-alis-namespace-alias.sh` uses isolated XDG roots to check fresh install no-op, preservation of sentinel bytes, idempotence, foreign/dangling symlink refusal, and conflict preflight.

## Owner desktop evidence

Run `bash scripts/brand-owner-audit.sh` from a local Alis checkout to inspect installed launcher paths, runtime service state, and XDG aliases **without writing state or restarting the shell**. Save its printed observations alongside owner screenshots after manually testing cold login, settings, IPC, popups and rollback. The script only reports facts; no owner-verified result is inferred from it.

## Standalone automated regression lane

GitHub Actions workflow `.github/workflows/brand-contracts.yml` runs a bounded, desktop-independent set of CLI, app ID, staged installer ownership, XDG namespace alias and pinned Arch snapshot contracts on `dev`. Its first confirmed successful run was [38430739766](https://github.com/llocphann/Alis/actions/runs/38430739766) at SHA `cf81808b8c8377d24f5fa917866edd47c2a7e5f5`. This gives independent evidence even when the full desktop/Niri canonical validator cannot execute in hosted CI; it **does not** replace owner visual acceptance, package installation on real hardware, or rollback validation.

## Present guardrails / open checks

- The `alis` launcher currently forwards to the legacy runtime, by design; it is not an independent session.
- `inir.service`, `ShellId inir`, `~/.config/inir`, XDG user state and `INIR_*` overrides remain the active compatibility identities.
- Upgrades are **not** permitted to trigger a fresh wizard solely because of the rebrand.
- Optional namespace alias behavior is covered by a source regression test; a full primary namespace move, desktop rollback and full canonical validator PASS remain **not yet verified**.
- The full maintainer validator contains unrelated preexisting/parallel failures; record the exact SHA and log evidence before attributing failures to this work.

This matrix is used to prevent an unsafe bulk string replace; it does not supersede the owner's issue acceptance checklist.
