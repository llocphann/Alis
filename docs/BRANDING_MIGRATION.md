# BRAND-R01 — Alis rename inventory, compatibility boundaries, and release gates

Updated: 2026-10-13. Tracking issue: [#64](https://github.com/llocphann/Alis/issues/64).

This is an implementation inventory, not a declaration of completion. The public product name is **Alis**. Existing persistent identities are not automatically safe to rename. Changes are developed on `dev` only; `stable` is untouched.

## Consumer map and classification

| Identifiers and references | Source examples / consumers | Category | Required transition |
|---|---|---|---|
| First-run heading, greeting, notification sender | `welcome.qml`, `services/FirstRunExperience.qml`, `modules/bootGreeting/BootGreeting.qml` | Public identity | Display Alis; retain `first_run.txt` and `welcomeWizard.completed/skipped` |
| Settings, Update UI, keybind help | `services/ShellUpdates.qml`, `modules/settings/SettingsPageRegistryData.qml`, `modules/bar/ShellUpdateIndicator.qml`, `services/deferred/NiriKeybinds.qml` | Public identity | Display Alis; do not rewrite saved style/layout enums |
| CLI and completions | `scripts/alis`, `scripts/alis`, `scripts/completions/*` | Public command plus compatibility alias | `alis` delegates to the existing internal `scripts/alis` engine; interactive installed `alis` CLI is temporarily blocked (exit 64), with sole systemd lifecycle exceptions; existing flags/IPC remain supported via `alis` |
| Runtime ShellId and selector | `shell.qml` (`ShellId alis`), `scripts/alis` (`qs -p`), `~/.config/quickshell/alis` | High-risk runtime interface | Keep one Quickshell session; coordinated switch required with rollback |
| User service and compositor wants links | `assets/systemd/alis.service`, `setup`, `Makefile`, Arch/Nix recipes, Niri startup KDL | High-risk session owner | A new unit must replace—not accompany—the old owner after tested stop/disable/migrate/start |
| Configuration roots and overrides | `scripts/lib/config-path.sh`, `sdata/migrations/019-config-dir-rename-compat.sh`, `sdata/migrations/061-alis-namespace-alias.sh`, `ALIS_*` | Persistent compatibility interface | Keep `alis` and `illogical-impulse` as current source of truth; optional checked `alis` symlinks only; no automatic directory move |
| Shared and per-user state | `services/FirstRunExperience.qml`, `modules/common/Config.qml`, scripts referencing XDG state/cache/data paths | User data | Do not reset themes, layouts, credentials, notes, models, wallpaper, wizard marker or custom overrides |
| IPC/DBus/Niri process selectors | `scripts/lib/ipc-registry.sh`, `docs/IPC.md`, ShellId, `org.kde.StatusNotifierWatcher` | Runtime ABI | Preserve established targets, function aliases and DBus watcher uniqueness |
| Native helper/Polkit interfaces | `native/alis-*`, `assets/helpers/alis-*`, `assets/polkit/org.alis.*` | Native ABI / privileged integration | Treat executable, socket and policy IDs as ABI until mapped and upgrade-tested |
| Install/update packaging | `setup`, `sdata/subcmd-install/3.files.sh`, Arch PKGBUILD/.SRCINFO, `nix/package.nix`, `Makefile` | Public installer with legacy package IDs | Ship public Alis CLI, desktop IDs and icon; hide legacy desktop launchers, retain `alis-shell` package and `alis.service` until coordinated ownership migration |
| Update URLs and docs | `sdata/lib/versioning.sh`, `scripts/release.sh`, `scripts/wiki-sync.sh`, `docs/INSTALL.md`, `docs/SETUP.md` | Public identity | Follow `llocphann/Alis`; keep historical commit SHA references |
| Optional Integration product | Alis-Intergration; API 1 `alis-intergration`, existing QML/data/helper/Polkit identities | Public name with retained compatibility contracts | [INT-R05 inventory](https://github.com/llocphann/Alis-Intergration/issues/7); display names change without moving installed data or security payloads |
| Third-party or historical names | Alis-Companion repository, Waffle/Aqua/Abyss, prior commits, archived investigations | External / historical | Do not rename without explicit authorization; do not falsify historical evidence |

## Safe rollout sequence

1. **Public and compatibility layer.** Use Alis-facing UI, commands, update links and packaged CLI forwarding without changing ShellId or runtime ownership.
2. **Read-only upgrade inventory.** Identify configuration roots, symlinks, stale per-user/system unit files, XDG overrides and foreign files before any migration.
3. **Transactional migration design.** Stage backups and rollback paths; make every operation idempotent, refuse conflicting real trees and preserve credentials/notes/models/first-run markers.
4. **Single-owner runtime cutover.** Switch Quickshell selector, service unit/wants and Niri entry points as one coordinated transaction after stopped-state and restart/cold-boot tests. Never enable parallel `alis.service` and `alis.service`.
5. **Package and ABI qualification.** Validate installed Arch/Nix/Make payloads, Polkit and native helpers, uninstall/reinstall and source-sync variations.
6. **Owner release acceptance.** Verify on physical Niri/Quickshell for greeting, updates, menus, popups, IPC, restart, fullscreen and rollback. Issue remains open until approval.

## Optional namespace aliases (R6 compatibility milestone)

`061-alis-namespace-alias` is deliberately optional. Run `alis migrate` (or `./setup migrate`), inspect its preview, and explicitly choose **Apply**. The migration only links each existing `$XDG_CONFIG_HOME/alis`, `$XDG_CACHE_HOME/alis`, `$XDG_DATA_HOME/alis`, and `$XDG_STATE_HOME/alis` as the corresponding `alis` path. Missing legacy roots are left alone.

Each XDG alias is optional and independent. When an Alis path already exists as a real directory or a foreign/dangling symlink (including the user's `~/.cache/alis`), migration 061 now prints `SKIP` for that path, keeps its contents intact, and creates aliases only for other free destinations. Existing unrelated paths do not cause repeated prompts or a failed update. If a link creation fails unexpectedly, only links made during that attempt are rolled back. It never copies or deletes legacy data, updates configuration contents, changes Quickshell's `ShellId`, or modifies a systemd unit. The shell continues using the legacy paths.

Undo an applied alias with `bash scripts/brand-namespace-rollback.sh --dry-run` to inspect the exact paths first. Run the explicit `--apply` option only after checking the results. The utility preflights all XDG destinations, refuses a foreign symlink or real directory, then unlinks *only* aliases pointing directly to `alis`. It never deletes an original `alis` directory. Manual unlink remains possible after independently verifying each alias. This is not a complete future migration of the runtime/state namespace, and it is not an automated owner-verified rollback.

Test coverage: `scripts/test-alis-namespace-alias.sh` and `scripts/test-brand-namespace-rollback.sh` use isolated XDG roots to check fresh install no-op, data preservation, idempotence, foreign/dangling symlink refusal, conflict preflight, dry run and reversible alias-only rollback.

## Owner desktop evidence

Run `bash scripts/brand-owner-audit.sh` from a local Alis checkout to inspect installed launcher paths, runtime service state, and XDG aliases **without writing state or restarting the shell**. It returns exit status **2** if both `alis.service` and `alis.service` are active, which is an explicit release blocker. Save its observations alongside owner screenshots after manually testing cold login, settings, IPC, popups and rollback. The script only reports facts; no owner-verified result is inferred from it. See [the R10 owner checklist](BRAND_R10_OWNER_ACCEPTANCE.md).

## Lossless uninstall ownership

Repo-managed Alis entries are removed only when their contents carry the expected Alis management marker (launcher and desktop files) or their SVG bytes equal the distributed Alis icon. Existing files with foreign content or symlinks are preserved. `scripts/test-brand-uninstall.sh` exercises both cases and verifies that XDG data aliases and original preference bytes are untouched. Existing `alis` runtime files retain their prior lifecycle behavior.

## Runtime ownership contract (R5)

`scripts/test-brand-single-owner.sh` verifies the current Quickshell `ShellId alis`, the sole `alis.service` process owner and StatusNotifierWatcher DBus bus name; it also rejects a second `alis.service` and enforces the forwarding CLI for both source and fallback runtime modes. This is intentionally a **strict-lossless compatibility release**: the user sees Alis, while established runtime/IPC/session selectors remain stable. Migrating the canonical selectors later is a separate owner-gated transaction, not an automatic package upgrade.

## Staged installation and rollback evidence (R9)

Run `bash scripts/test-brand-upgrade-rollback.sh` to stage a fresh Make installation, repeat installation as a simulated package upgrade, uninstall and reinstall. It verifies public and legacy entrypoint ownership, app-ID hiding, icon preservation and SHA-256 sentinels for an isolated user config and first-run marker. It also rejects foreign command collisions. The scenario **does not** invoke pacman, manage a user service, manipulate real user files, or prove a physical graphical login.

## Repo-copy update desktop IDs

Installer and packagers already distribute public `alis.desktop`, `alis-settings.desktop` and `alis.svg`; the previous `setup update` refreshed only legacy `alis*.desktop` and `alis.svg`. `sdata/lib/sync-alis-desktop.sh` is now invoked during repo-copy updates to reconcile the public IDs and icon without altering the legacy compatibility entries. It refreshes only marked `X-Alis-Managed=true` desktop files, keeps the Alis Shell launcher hidden so a second session is not exposed, quotes launcher paths containing spaces, and preserves foreign files/symlinks or custom icons. Regression: `scripts/test-alis-desktop-update.sh`.

## Setup entrypoint integrity

The reported local error `~/.config/quickshell/alis/setup: line 2951: e ;;` does not match the tracked dev source (line 2951 contains a valid `uninstall) run_uninstall ;;` case arm). To prevent recurrence during installs and updates, `sdata/lib/safe-setup-sync.sh` now validates source Bash syntax, writes the new setup to a temporary file in the destination directory, validates the staged copy, then atomically renames it over the managed runtime entrypoint. A corrupt source is rejected without touching the destination. `scripts/test-setup-sync-atomic.sh` verifies recovery from a truncated setup, invalid-source rejection, no partial files, source/target equality and foreign symlink preservation.

Recover an already corrupt local copy from a **healthy checkout** by using the helper directly; invoking the broken installed `setup` cannot repair itself. Back up the original file and inspect any user changes before replacing it. No other user data or preferences need to be reset.

## Migration 034 vs. 051 (R10 owner report)

After a successful update to `c8db67392`, Status displayed `034-cliphist-text-watcher` as pending even though the clipboard watcher had been normalized by migration 051. The historical 034 check searched for the literal `wl-paste --type text`, missing the canonical `wl-paste --no-newline --type text` form. Migration 034 now recognizes active text watchers in both startup and monolithic Niri configs, ignores commented watcher examples, respects intentionally disabled history and is idempotent when a watcher already exists. This avoids creating a second clipboard writer. The isolated regression `scripts/test-cliphist-migration-034.sh` covers the reported post-051 state, the original missing-text repair, disabled history and monolithic fallback. No live Niri config was changed.

## Standalone automated regression lane

GitHub Actions workflow `.github/workflows/brand-contracts.yml` runs a bounded, desktop-independent set of CLI, app ID, staged installer ownership, XDG namespace alias and pinned Arch snapshot contracts on `dev`. Its first confirmed successful run was [38430739766](https://github.com/llocphann/Alis/actions/runs/38430739766) at SHA `cf81808b8c8377d24f5fa917866edd47c2a7e5f5`. This gives independent evidence even when the full desktop/Niri canonical validator cannot execute in hosted CI; it **does not** replace owner visual acceptance, package installation on real hardware, or rollback validation.

## Present guardrails / open checks

- The `alis` launcher currently forwards to the legacy runtime, by design; it is not an independent session.
- `alis.service`, `ShellId alis`, `~/.config/alis`, XDG user state and `ALIS_*` overrides remain the active compatibility identities.
- Upgrades are **not** permitted to trigger a fresh wizard solely because of the rebrand.
- Optional namespace alias behavior is covered by a source regression test; a full primary namespace move, desktop rollback and full canonical validator PASS remain **not yet verified**.
- The full maintainer validator contains unrelated preexisting/parallel failures; record the exact SHA and log evidence before attributing failures to this work.

This matrix is used to prevent an unsafe bulk string replace; it does not supersede the owner's issue acceptance checklist.

## Temporary public CLI cutover (2026-10-14, BRAND-R01)

Use **`alis` exclusively** for interactive terminal commands, including `alis status`, `alis update`, `alis service restart`, `alis settings`, and `alis <ipc-target> <function>`. Installed public `alis` launchers in `bin/alis` refuse all ordinary commands (exit 64) and explain how to use Alis. The Nix public `alis` wrapper explicitly opts into the same guard. `alis` passes a one-hop internal delegation flag and then clears it in the underlying engine.

**Do not remove `scripts/alis`**: current QML buttons, the existing Niri keybinds, setup scripts and shell helper processes still depend on that runtime file. A running/installed `alis.service` may continue invoking `alis run --session` and `alis cleanup-orphans` **only under a systemd invocation context** (`INVOCATION_ID`); these are private lifecycle exceptions, not public CLI support. Keep `alis.service`, `ShellId alis`, XDG user data, helper/IPC ABI, and existing unit ownership unchanged. No parallel `alis.service` is created.

This is an **interface restriction, not a destructive rename**. It becomes effective after the installed public launcher is updated (repo-copy setup/update, Arch package upgrade, Make reinstall or Nix rebuild). Direct `scripts/alis` invocation is still an internal compatibility entrypoint; public shell completions and documentation should promote `alis`. Rollback of this gate is reverting this source change and refreshing the installed launcher; do not delete/move user preferences or overwrite foreign `~/.cache/alis`.

Regression: `bash scripts/test-brand-legacy-cli.sh`. Existing R9/R10 cold-login and owner visual checks remain required; never mark #64 owner verified solely from this contract.

### Update, Niri and desktop entry compatibility

- Repo-copy update now uses `alis` for its verified post-update shell restart. Fresh Niri keybinds use the Alis command, not the newly disabled public `alis` launcher. The optional input-method autostart from this historical milestone was retired by SET-R04.
- When updating existing Niri keybind/startup commands that still point at `/bin/alis` or `spawn-at-startup "alis"`, the updater makes a one-time `*.brand-cli.bak` copy of relevant *ordinary* Niri config files before changing those command positions. It does not follow symlinks when creating this backup; audit and restore owner-customized keybinds manually as needed.
- Old hidden desktop IDs (`alis.desktop` and `alis-settings.desktop`) stay installed for pinned-shortcut compatibility, but their `Exec` entries now route through `alis` in repository, Make, Nix and installer/repo-copy outputs. New desktop IDs remain `alis.desktop` and `alis-settings.desktop`.
- The unit `alis.service` and its private launcher path stay unchanged as the only session/tray owner, until a separately verified atomic runtime cutover. Never install a second `alis.service` alongside it.

**Owner test:** after the upgrade, inspect `alis status`, `alis help`, `alis settings`, `alis service status`, Niri keybinds and any pinned old shortcuts; then cold-login and confirm exactly one Quickshell session/tray watcher. No owner state was modified by CI.

## BRAND-R01 About identity and attribution (2026-10-14)

The Material `modules/settings/About.qml` and Waffle `modules/waffle/settings/pages/WAboutPage.qml` show **Alis** as the current product, link to `llocphann/Alis` for documentation and issues, and use the locally packaged `assets/icons/alis-owner-avatar.jpg` asset sourced from the owner's About screenshot. No runtime network fetch or configuration migration is required to show the avatar.

Both settings variants include a **Based on** section crediting Alis (`snowarch/Alis`) and illogical-impulse (`end-4/dots-hyprland`). These historical source URLs belong only to upstream credits, not to the product's update/support links. The system/distro card remains independent. Runtime compatibility names, services, the persisted config schema and the single Quickshell session owner remain unchanged.

The screenshot-sourced avatar image is approximately 59×59 pixels. Replace that static asset with an owner-provided high-resolution original if available; do not upscale it in source control. Run `python3 scripts/test-brand-about-identity.py` to check these assets and strings; physical Material/Waffle About rendering awaits R10 owner verification.
