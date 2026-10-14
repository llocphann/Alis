# Canonical Alis installation and rollback

Alis `dev` uses the canonical CLI, Quickshell selector, systemd service,
XDG roots and native binary names. Source integration does not migrate a
running installation. Track requirements and acceptance in [BRAND-R01](https://github.com/llocphann/Alis/issues/64).

## Legacy installation boundary

An installation owned by `inir.service` needs a deliberate single-owner
handoff. Normal setup/update and `alis migrate` refuse the legacy service;
never enable `alis.service` alongside it. Do not point an active legacy
Quickshell config at canonical source before inspecting the handoff.

`scripts/brand-canonical-cutover.sh --dry-run` checks the installed canonical
CLI, Quickshell selector, referenced Niri includes and legacy executable
shortcuts before touching services. `scripts/repair-niri-alis-keybinds.sh`
repairs supported active fragments, preserving hotkey actions and original
backup bytes. The cutover checks every referenced include, including nested
ones; unresolved or symlinked includes fail closed.

The cutover's apply mode requires the owner's explicit decision. It stops the
legacy owner, updates known service links, reloads the user daemon and starts
one canonical owner. Failed startup restores the previous service wiring.
It retains the original unit and configuration for recovery.

## Data and ownership

Canonical roots take precedence when present. Historic `inir` and
`illogical-impulse` configuration may be copied only when compatible with the
canonical destination; differing settings are refused. Preference, layout,
notes and wizard marker bytes must survive. Existing foreign files, launchers
and symlinks are not overwritten. Backups live in the independent
`alis-cutover-backups` state root, outside the state tree being copied.

New keyring entries use `application=alis`. A missing canonical entry falls
back to reading the original `illogical-impulse` secret without modifying it.
Historical migrations cannot recreate the retired config namespace after
canonical staging. Original project credits remain iNiR and illogical-impulse.

## Rollback

`scripts/brand-canonical-rollback.sh --dry-run` previews reverting the
service/session owner. This is not an Arch/Nix package transaction or a
reverse merge of user settings created after cutover. The original verified
CLI must be restored and its `help` command must work; a disabled compatibility
shim cannot serve as a rollback target.

On an explicit owner decision, `--apply --owner-approved` stops
`alis.service`, restores verified original service links and starts only
`inir.service`. If the original startup fails, it attempts to restore Alis.
Both units and all config/cache/data/state directories are retained.

## Validation scope

`python3 scripts/brand-canonical-audit.py --strict` audits active source
identities; historical attribution and explicit migration inputs remain
separate. The canonical contracts, config, keyring, cutover, rollback,
owner-audit, hotkey and uninstall tests use isolated fixtures. They do not
prove live service recovery, cold login or a package-manager upgrade.

Installation qualification also needs actual Arch/Nix upgrade semantics,
exclusive session/tray ownership, Niri shortcuts and IPC, popups, fullscreen,
recording, user-data preservation and live rollback. Full maintainer
validation and physical/owner acceptance remain independent gates. Evidence
is linked from GitHub Issues; a focused source result is not release approval.

## BRAND-R01 update compatibility when the previous service is retained

The old `inir.service` file stays available for owner-controlled recovery after
a successful cutover. Its presence alone is **not** a reason to block future
`alis update` commands. The update guard now allows updates **only** if the
canonical `alis.service` is active, legacy service inactive and
disabled/static, no legacy compositor `*.wants/inir.service` links remain,
and the installed runtime has `ShellId alis`. An old active/enabled unit,
missing canonical session, or partial migration still blocks updates.

To prepare a repo-copy cutover before switching services, use
`bash scripts/brand-canonical-stage.sh --dry-run`; staging is explicitly
owner-gated and must not run automatically. Then review
`bash scripts/brand-canonical-cutover.sh --dry-run` before making any
owner-authorized service changes. Package-managed users must upgrade using
their package manager. Source tests are not physical desktop verification.
