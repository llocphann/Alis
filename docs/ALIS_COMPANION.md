# Alis Companion — integrated install, independently maintained source

Companion is an **integrated Alis feature**. Its implementation remains in
[Alis-Companion](https://github.com/llocphann/Alis-Companion), while the Alis
installer owns the user-visible install and update lifecycle.

## Installing and updating

Running `./setup install`, `./setup reinstall` or `./setup update` manages
Companion automatically — **no separate Git clone, checkbox, Companion install
command, or manual update is needed**. The selected compatible commit is recorded
in `sdata/companion-revision.txt`; `scripts/companion-manager.py` obtains this
exact revision in a dedicated cache and runs the Companion package's own build
and immutable-release installer. Even a no-op core update repairs a missing
Companion installation. Source fetch/build failures are reported as setup errors,
not as successful full Alis installations.

This desktop-user install uses `~/.local/share/alis-companion` or `XDG_DATA_HOME`,
and the managed source uses the user's `XDG_CACHE_HOME/alis/companion`.
Installation never writes to an owner's separate Companion source checkout,
requests root privileges for Companion, or modifies an existing foreign checkout.
The external repository is pinned rather than tracking an unreviewed moving
`main` revision. A later Alis update can advance the compatible source SHA.

The Companion package publishes under versioned `alis-companion/releases/<sha>`
directories and atomically updates `alis-companion/current`. An unsuccessful build
does not activate an incomplete release or delete old releases/user data.
After update, Alis refreshes Companion IPC when possible or restarts its shell.
`./setup uninstall` detaches only a release whose recorded Alis ownership
and active source SHA still match, retaining versioned releases, personal data
and any independently modified Companion installation.

**System package installation boundary:** staged/system `make install`,
Arch and Nix package builds are package-manager-owned and must remain offline,
noninteractive, and DESTDIR-safe. Their installer hooks do not yet bootstrap
Companion into an arbitrary user's HOME; for those installations, running
`./setup update` as the desktop user performs Companion synchronization.
Do not claim system package auto-install acceptance until its own package/dependency
or first-user-setup route is implemented and tested.

## Runtime and permissions

The core uses API 1 via `services/AlisCompanion.qml`,
`modules/abyss/AlisCompanionSurface.qml`, finite package discovery and a lazy
Settings adapter. Although installation is automatic, **Companion activation
and optional AI/model/Obsidian/memory permissions are not automatic**.
Aqua/Octo remains controlled by the user's existing
`abyss.companion.enabled` preference. No LLM is installed or launched at setup.

Settings → Companion presents the installed extension, or a repair message if
the compatible release cannot load. Retained IPC names (`aqua`, `alis-companion`),
existing user settings and private transcripts remain compatible.

Alis's canonical task board is [to-do/](../to-do/README.md). The standalone
Companion repository retains source, versioned implementation and tests, not
a separate active task board.
