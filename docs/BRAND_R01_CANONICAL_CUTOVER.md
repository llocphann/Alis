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
