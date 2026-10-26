# Canonical Alis installation and rollback

Alis `dev` uses the canonical CLI, Quickshell selector, systemd service,
XDG roots and native binary names. Source integration does not migrate a
running installation. Track requirements and acceptance in [BRAND-R01](https://github.com/llocphann/Alis/issues/64).

## Legacy installation boundary

An installation owned by `alis.service` needs a deliberate single-owner
handoff. Normal setup/update and `alis migrate` refuse the legacy service;
never enable `alis.service` alongside it. Do not point an active legacy
Quickshell config at canonical source before inspecting the handoff.

`scripts/brand-canonical-cutover.sh --dry-run` checks the installed canonical
CLI, Quickshell selector, referenced Niri includes and legacy executable
shortcuts before touching services. `scripts/repair-niri-alis-keybinds.sh`
repairs supported active fragments, preserving hotkey actions and original
backup bytes. Review `python3 scripts/brand-niri-runtime-paths.py --dry-run` for the
managed clipboard watcher paths and Autostart delimiters. Its approved apply
mode keeps helper arguments, user Autostart entries and original backup bytes.
The cutover checks every referenced include, including nested
ones; unresolved or symlinked includes fail closed.

The cutover's apply mode requires the owner's explicit decision. It stops the
legacy owner, updates known service links, reloads the user daemon and starts
one canonical owner. Failed startup restores the previous service wiring.
It retains the original unit and configuration for recovery. The previous
owner is stopped before copying the data roots so final shutdown writes are
included in the canonical snapshot.

## Data and ownership

Canonical roots take precedence when present. Historic `alis` and
`illogical-impulse` configuration may be copied only when compatible with the
canonical destination; differing settings are refused. Preference, layout,
notes and wizard marker bytes must survive. Existing foreign files, launchers
and symlinks are not overwritten. Backups live in the independent
`alis-cutover-backups` state root, outside the state tree being copied.

New keyring entries use `application=alis`. A missing canonical entry falls
back to reading the original `illogical-impulse` secret without modifying it.
Historical migrations cannot recreate the retired config namespace after
canonical staging. Original project credits remain Alis and illogical-impulse.

## Rollback

`scripts/brand-canonical-rollback.sh --dry-run` previews reverting the
service/session owner. This is not an Arch/Nix package transaction or a
reverse merge of user settings created after cutover. The original verified
CLI must support read-only `help`, directly or through its byte-identical
managed private engine. A generic disabled compatibility stub cannot serve
as a rollback target.

On an explicit owner decision, `--apply --owner-approved` stops
`alis.service`, restores verified original service links and starts only
`alis.service`. If the original startup fails, it attempts to restore Alis.
Both units and all config/cache/data/state directories are retained.
A managed historical public shim remains a valid service recovery target only
when its bytes equal the retained private engine, the original ShellId and
private systemd lifecycle guard are verified, and private `help` succeeds.
Generic disabled stubs, edited wrappers and symlinked engines remain blocked.

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

The old `alis.service` file stays available for owner-controlled recovery after
a successful cutover. Its presence alone is **not** a reason to block future
`alis update` commands. The update guard now allows updates **only** if the
canonical `alis.service` is active, legacy service inactive and
disabled/static, no legacy compositor `*.wants/alis.service` links remain,
and the installed runtime has `ShellId alis`. An old active/enabled unit,
missing canonical session, or partial migration still blocks updates.

To prepare a repo-copy cutover before switching services, use
`bash scripts/brand-canonical-stage.sh --dry-run`; staging is explicitly
owner-gated and must not run automatically. Then review
`bash scripts/brand-canonical-cutover.sh --dry-run` before making any
owner-authorized service changes. Package-managed users must upgrade using
their package manager. Source tests are not physical desktop verification.

## Transitional launcher bootstrap (before owner cutover)

A repo-copy desktop may retain a **managed compatibility** `~/.local/bin/alis`
launcher which forwards to the now-retired `alis` runtime. The source
`scripts/alis` is canonical but the installed launcher has not been updated.
Both `alis update` and service cutover intentionally refuse a dual-owner
state; demanding an already-canonical public CLI before staging created a
circular dependency.

`bash scripts/brand-canonical-stage.sh --dry-run` identifies the old managed
launcher without writing anything. On explicit owner approval,
`--apply --owner-approved` first prepares a separate canonical QML/native
runtime (or verifies a complete existing Alis runtime), then copies the old
managed launcher **byte-for-byte** to a unique
`~/.local/state/alis-cutover-backups/launcher-*/alis` directory, and atomically
installs the source canonical CLI at the user launcher path. It recognizes
only the signed-off historical wrapper markers plus the internal Alis
delegation. Unknown executables, symlinks, shadowing PATH commands, partial
runtime targets and package-managed installs are rejected. Already-canonical
launchers and completely staged runtime are left unchanged.

Staging **does not** stop either systemd unit, perform a data migration or
change Niri keybinds. While `alis.service` still owns the desktop, replacing
the public CLI can affect commands aimed at the old runtime; conduct the
subsequent cutover from a safe recovery-capable session. Run the separate
`brand-canonical-cutover.sh --dry-run` after staging, and do not apply that
cutover while any reported Niri, XDG, owner-unit, backup or package
qualification blocker remains. The original CLI backup is **not** a proof
of full service rollback; restored service startup and original engine have
separate release gates.

The dedicated regression verifies foreign and symlink launcher rejection,
explicit consent, byte-for-byte backup, complete-runtime idempotency,
native build, retained owner unit and untouched synthetic preferences and
first-run marker.

## Retain an existing user-owned Alis cache during cutover

An earlier Alis installation or another application may already have created
`$XDG_CACHE_HOME/alis`. If there is also a legacy `alis` or
`illogical-impulse` cache, the cutover leaves **both caches exactly as found**
rather than refusing a new session solely because a cache directory exists.
The dry-run prints `KEEP existing Alis cache unchanged; skip old cache copy`;
the apply mode neither merges nor removes either cache. Only an existing
**real directory** is skipped: an Alis cache symlink, file, or other non-directory
path fails closed and requires owner review.

This cache-only exception does not apply to `$XDG_CONFIG_HOME/alis`,
`$XDG_DATA_HOME/alis`, or `$XDG_STATE_HOME/alis`: preexisting foreign
destinations in those namespaces still block cutover to prevent silent
overwrites. The deterministic cutover test verifies unchanged hashes for both
caches across a successful service handoff and failure rollback, strict
rejection of non-cache collisions, and unchanged single-owner semantics.

After updating a reviewed repo checkout, rerun
`bash scripts/brand-canonical-cutover.sh --dry-run` to inspect **all**
remaining blockers before any owner-authorized live cutover. A green synthetic
test does not count as R10 desktop verification.

## Singleton D-Bus name repair (owner failure, October 14, 2026)

The owner observed a **real**, owner-approved service cutover failure:
`alis.service: Two services allocated for the same bus name
org.kde.StatusNotifierWatcher, refusing operation` (21:15:21 local time).
The initial rollback brought `alis.service` back to **active** and
`alis.service` to **not-found/inactive**. Merely stopping `alis.service`
does **not** retire its systemd unit, so the manager still reserves
`BusName=org.kde.StatusNotifierWatcher` for both installed units.

The canonical cutover now checks that the installed `alis` CLI exactly
matches the reviewed source (`cmp`) before the old desktop is stopped.
For a stale but recognized canonical launcher, review
`bash scripts/brand-canonical-stage.sh --dry-run`. Its separately
owner-approved apply preserves the previous launcher byte-for-byte under
`alis-cutover-backups/launcher-*/alis` and atomically installs the source
launcher. It does not stop either service. A complete already-staged Alis
runtime is retained.

At owner-authorized cutover, the script stops the old owner before copying
its final config/data/state, creates a verified original unit backup, moves
`alis.service` to
`$XDG_STATE_HOME/alis-cutover-backups/retired-alis.service` **outside
systemd's unit search path**, installs a `alis.service -> /dev/null` mask,
rewires the compositor's managed `*.wants` link, reloads the user manager,
and verifies **legacy unit = masked, canonical unit = loaded** before
starting Alis. The mask also prevents lower-priority package units from
reclaiming the old identity. A failed start attempts to restore the exact
original file, previous wants links and previous sole active service. No
cache/data root is deleted.

After a successful cutover, the original unit is **archived and masked**,
not an inactive `Type=dbus` unit left installed beside Alis. The setup
update guard admits this state only when the old unit is inactive, the
managed mask points to `/dev/null`, the verified archive still exists,
the old compositor wants link is absent and canonical `ShellId alis`
is staged. An old active unit, a missing archive or a foreign mask fails
closed.

The owner-approved `brand-canonical-rollback.sh` uses the reverse
transaction: archive the Alis unit outside the search path, remove only
the recognized legacy mask, restore the original unit from its verified
archive, rewire the compositor, daemon-reload and start the old owner.
If old startup fails it attempts to restore the canonical unit, mask and
links before restarting Alis. The two unit files must never be visible
to systemd with an identical `BusName` during the same reload.

**Acceptance is still pending.** The isolated regression mocks systemd's
duplicate-name failure and tests both switch directions, denied consent,
archive integrity and rollback restoration. A green synthetic test does
not substitute for an actual user-manager run and owner cold-login / IPC /
system tray / restore verification. Never retry `--apply` merely because a
new commit exists; first ensure the existing desktop is healthy, inspect
the current dry-run and have an independent recovery terminal available.
