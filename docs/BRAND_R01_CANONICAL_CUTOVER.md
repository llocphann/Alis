# BRAND-R01 — Canonical Alis cutover (work in progress)

**Branch:** `brand-r01-canonical-alis` (isolated from `dev` and `stable`).
**Status:** NOT INSTALLABLE. Do not checkout this branch as the active
`~/.config/quickshell/*` runtime or run its install/update pipeline yet.

## New owner requirement

All active product identities must become Alis: shell selector, systemd service,
CLI, Cargo crate and binary names, IPC/runtime paths, installation/package
metadata, environment variables and launchers. iNiR and illogical-impulse
remain *historical attribution only* in Settings → About.

## Recorded implementation

- Renamed Rust Cargo workspace members to `alis-*` and changed `Cargo.lock`.
- Renamed Rust source paths and corresponding Rust-internal references.
- Introduced canonical `scripts/alis` executable (no CLI forwarding wrapper).
- Changed Quickshell `ShellId` to `alis`.
- Introduced `assets/systemd/alis.service`; removed its old tracked unit file
  on this *feature* branch only.
- Updated initial Nix options, module paths, Rust dispatch and Make packaging.

These partial source changes are **not an installed/user migration**.

## Blocking tasks before branch can merge into dev

1. Replace all remaining runtime `inir` executable references in QML,
   generated keybinds, startup, desktop launchers and setup/update scripts.
2. Finish the full `alis.service` one-owner handoff: stop/disable legacy unit,
   remove only known old wants links, reload user daemon, start just one new unit,
   verify its D-Bus watcher, and roll back on failure. No dual services.
3. Migrate XDG config/cache/data/state roots and Quickshell config/runtime
   selector **without overwriting an existing Alis path or changing preference
   bytes**. Implement inspected backup and reversal, not blind string replace.
4. Finish Arch `PKGBUILD` and `.SRCINFO`, Nix, user service generators,
   Polkit/helper interfaces, native scripts and package-manager upgrade story.
   The existing `inir-shell` package is a separate package-manager migration.
5. Replace native source build and dispatch tests with genuinely verified Alis
   behaviors; update workflows without weakening assertions.
6. Obtain the full-resolution **new user-provided avatar** as an accessible
   original PNG/JPEG and replace the low-resolution screenshot-derived asset.
7. Pass Bash/QML/Qt/Rust/Nix/Arch contract checks and complete stopped-state,
   cold-login and rollback acceptance on the affected Niri/Quickshell desktop.

Do **not** claim the full rebrand done, owner-verified, or safe for installation
until every gate is met. Main `dev` retains the previously tested compatible
runtime and `stable` has not been changed.

## Evidence collection

Run `python3 scripts/brand-canonical-audit.py` in the checkout; nonzero
`--strict` status means actionable runtime identifiers remain. Historical
references in archived documentation, original licensing/attribution,
previous migrations, and explicit upgrade/rollback code are not target names.

## 2026-10-14 implementation verification

The canonical refactor branch is still **not approved for owner installation**.
Source-stage CI now exercises `bash -n`, Alis-only Cargo metadata and packaging,
canonical IPC registry generation/check, historical Keyring secret lookup,
and a fully isolated mock single-service cutover/rollback. The Nix package
build succeeded after fixing the setup Bash condition.

Additional fixes since the initial isolation:

- `Directories.shellConfig` now uses `~/.config/alis`, matching the installer.
- Live UI config-open actions, plugins, the Settings window title and the
  transition logo use Alis. The original upstream icon/name remains historical
  attribution in About.
- The owner-gated cutover checks for a canonical installed CLI and legacy
  active Niri hotkeys **before stopping** the original service. Old
  `90-user-extra.kdl` executable overrides are a release blocker until fixed.
- Old `illogical-impulse` config files can be copied losslessly into `alis`;
  differing old `inir` and original config.json files are refused. Recognized
  old Alis symlinks are saved for recovery.
- Backups live under a **separate** `alis-cutover-backups` root so state copied
  from `state/inir` does not nest under `state/alis/inir`.
- API secrets are read first from the Alis keyring and then, read-only, from
  the upstream namespace if no Alis record exists.
- Runtime-only tests have been updated for the new `alis` config root; tests
  covering historical migrations must retain their original paths.
- The generated CLI IPC registry now derives current metadata from
  `docs/IPC.md` and is checked as part of the source-stage workflow.

**Remaining gates:** historical/compatibility local validator suites must be
migrated *without weakening functional requirements*, the full packaging and
Quickshell runtime checks must pass, Arch/Nix upgrade semantics need an
end-to-end review, and a live Niri cold-login/rollback requires owner approval.
No source-stage PASS should be called full release acceptance. Do not
automatically enable `alis.service` while the old service is active.

## Owner-approved post-success service rollback (repo-copy only)

`scripts/brand-canonical-rollback.sh --dry-run` previews reverting **only**
the service/session owner. This is not an Arch/Nix package transaction, nor a
reverse merge of Alis-created user settings. The original verified `inir` CLI
must be restored and its `help` command must work; the interim disabled
public shim cannot serve as a rollback target.

Only on the owner's explicit decision, `--apply --owner-approved` stops
`alis.service`, replaces verified compositor symlinks with original unit
symlinks, and starts only `inir.service`. If the original service fails to
start, the script attempts to restore Alis and leaves user data unchanged.
Both unit files and **all** Alis/legacy XDG config, cache, data and state
directories are retained. Post-rollback live Niri/Quickshell checks, cold
login, backups and package-manager reversal remain separate owner-only gates.

A staged regression tests dry-run, consent, failed legacy start recovery,
single service ownership and SHA-preserved synthetic preference data.
