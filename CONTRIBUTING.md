# Contributing to Alis

Alis is being developed on top of the cleaned Alis runtime baseline. The current architectural target and perimeter constraints live in [README.md](README.md) and [ARCHITECTURE.md](ARCHITECTURE.md); do not infer feature completion from those target documents alone.

## Branch model

| Branch | Role |
|---|---|
| `stable` | Default/stable branch. Promote tested work here deliberately. |
| `dev` | Active integration branch. Development changes land here first. |

Open development pull requests against `dev`, not `stable`. Do not base new work on the retired upstream `main` / `prerelease` workflow.

Because multiple changes may land on `dev` concurrently, refresh the branch before editing shared files and again before publishing a change. Resolve conflicts by rebuilding the change on the current `dev` state rather than overwriting unrelated work.

## Development setup

```bash
git clone https://github.com/llocphann/Alis.git
cd Alis
git switch dev
./setup install
alis run
```

The runtime still uses the `alis` launcher/configuration identity in many places. Do not rename runtime paths, IPC targets, package names, or service identifiers as part of unrelated changes.

For a clean supervised restart while developing:

```bash
alis restart
alis logs -f
```

Do not run `qs kill -c alis` or a bare `qs -c alis` for normal testing. The shell is designed to run under its supervised service lifecycle.

## Before opening a pull request

Run the checks that cover the subsystem you changed. The repository CI currently uses these entry points:

```bash
make test-local
fish scripts/qml-check.fish --all
python3 scripts/lib/generate-ipc-registry.py --check
```

`make test-local` is the aggregate non-QML release-boundary gate. It includes install/package lifecycle checks, doctor routing, optional-audio dependency policy, Equalizer Phase 1 architecture/service contracts, documentation verification, packaging contracts, and Nix module contracts.

For runtime-facing changes, also exercise the affected flow on a real session and inspect `alis logs`. For packaging/install changes, use dry-run or staged install paths rather than writing into the host filesystem just to test a package layout.

Keep each commit focused on one logical change. Prefer imperative, specific commit messages and avoid unrelated reformatting.

## Project structure

See [ARCHITECTURE.md](ARCHITECTURE.md) and [STRUCTURE.md](STRUCTURE.md) for the detailed layout. The main development areas are:

| Directory | What it contains |
|---|---|
| `modules/` | QML shell modules and surfaces |
| `modules/common/` | Shared configuration, appearance, and widget infrastructure |
| `modules/ii/` | Active Material ii / Classic presentation components |
| `modules/waffle/` | Active Waffle/Windows-style presentation family |
| `services/` | Runtime service singletons and integrations |
| `scripts/` | Launcher, checks, generators, and runtime helpers |
| `sdata/` | Install/update lifecycle, payload policy, and migrations |
| `defaults/` | Shipped configuration defaults |
| `distro/` | Distribution packaging |
| `nix/` | Nix package and module definitions |
| `translations/` | Localization data and tooling |

Both `ii` and `waffle` are active panel families. Shared runtime, service, IPC, and configuration changes must preserve both families when their contract is family-independent. Keep family-specific UI in its owning family instead of treating a family switch as perimeter module placement. Genuinely retired renderers or features should not be reintroduced without a deliberate architecture decision.

## Connected Perimeter invariant

The target shell has eight configurable perimeter placements: top-left, top-center, top-right, left-edge, right-edge, bottom-left, bottom-center, and bottom-right.

The preset documented in README is only a default composition. Modules must not acquire hard dependencies on a specific slot, and documentation must not describe a default placement as an architectural lock. Left/right sidebars are intended to be centered, content/config-sized edge surfaces rather than mandatory full-edge panels.

When touching this area, distinguish clearly between architecture that is specified and functionality that is actually implemented on the current `dev` HEAD.

## Configuration changes

Configuration has a single persistence/runtime pipeline. When adding or changing a user-facing key, update the relevant pieces together:

1. `modules/common/Config.qml` schema/default contract
2. `defaults/config.json`
3. Runtime consumer(s)
4. The owning active settings UI(s), when the value is user-configurable
5. Migration logic when an existing persisted key or data shape changes

Use the project's persistence APIs (for example `Config.setNestedValue(...)`) rather than assigning a persisted option directly and assuming it will be saved.

## Visual tokens

Use the owning family's active appearance/theme primitives instead of introducing per-component magic colors, radii, typography, or spacing. For ii components, for example:

```qml
color: Appearance.colors.colPrimary
radius: Appearance.rounding.normal
```

Waffle owns its family-specific visual tokens under `modules/waffle/looks/`. Shared components should not hard-code either family's presentation assumptions unless they are deliberately family-specific. Do not add dispatch logic for genuinely removed appearance systems.

## Compositor guards

Do not assume a compositor-specific API is universally available. Guard compositor-specific behavior using the existing compositor service contract, for example:

```qml
if (CompositorService.isNiri) { /* Niri-only */ }
if (CompositorService.isHyprland) { /* Hyprland-only */ }
```

## IPC functions

Keep IPC contracts typed and update generated/documented state when targets change:

```qml
IpcHandler {
    target: "myService"
    function getData(): string { return String(value) }
    function doThing(): void { /* ... */ }
}
```

After IPC changes, run:

```bash
python3 scripts/lib/generate-ipc-registry.py --check
```

and update `docs/IPC.md` when the public contract changes.

## New QML files

Follow nearby active components rather than retired-feature examples. New components should normally use bound component behavior and typed properties:

```qml
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services
```

Use one component per file, PascalCase filenames, and a stable root id such as `root` where consistent with the surrounding module.

## Null and optional-service safety

Optional services and integrations may be absent, unavailable, or not ready during startup. Prefer explicit fallbacks and guard nullable service state rather than assuming a backend always exists.

```qml
property var windows: NiriService.windows ?? []
property string name: NiriService.focusedWindow?.title ?? ""
```

The shell should degrade gracefully when optional binaries, hardware, permissions, or services are unavailable.

## High-risk shared areas

Changes to these areas can affect a large part of the shell and deserve narrower diffs plus broader validation:

- `modules/common/Appearance.qml`
- `modules/common/Config.qml`
- `GlobalStates.qml`
- `services/Translation.qml`
- shell/runtime composition and placement code
- install/update/payload lifecycle under `sdata/`

## Files that move together

| When you change... | Also inspect/update... |
|---|---|
| Config schema | `defaults/config.json` + consumer(s) + active settings UI(s) |
| A new service | `services/qmldir` |
| A new shared widget | `modules/common/widgets/qmldir` |
| IPC targets | generated IPC registry + `docs/IPC.md` |
| Runtime payload contents | canonical payload manifests/policy + all package consumers |
| Dependencies | installer/package definitions + `docs/PACKAGES.md` |
| Install paths | launcher/service/desktop/package/Nix consumers |

## Migrations

When a persisted config or data format changes between versions:

- Add the next migration under `sdata/migrations/` using the existing sequence and conventions.
- Migrations are sourced, not standalone programs; do not add top-level `exit` or `set -e` that can terminate the caller.
- Make migrations idempotent and safe to run more than once.
- Do not rewrite or reorder released migration history merely to make the sequence look cleaner.
- Preserve backup/rollback behavior for user-managed state.

## Translations

User-visible strings belong in the translation system. Follow existing keys and use `Translation.tr(...)` in QML where the surrounding code does so. Run the localization audit used by CI after translation changes.

## Releases

Release preparation and publication are maintainer workflows. Follow [docs/RELEASING.md](docs/RELEASING.md) for the version/package files that move together, stable/tag preconditions, validation commands, draft-release staging, Wiki synchronization, and recovery behavior.

Do not publish directly from `dev`, retarget the non-VCS Arch package to a moving branch, or bypass the release helper's preflight checks for routine releases.

## AI-assisted contributions

AI assistance is acceptable; unverified output is not. Before publishing AI-assisted work:

- Verify every API and path against the current repository or upstream documentation.
- Run the checks relevant to the changed subsystem.
- Exercise runtime behavior when the change cannot be validated statically.
- Describe meaningful validation in the pull request.
- Do not add generated boilerplate, drive-by restructuring, or attribution footers to unrelated project files.

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Getting help

GitHub Issues and Discussions are currently disabled for this private repository. For a change already under review, use its pull-request conversation. For questions that do not belong to an existing pull request, coordinate through the maintainer channel that granted repository access rather than relying on an unavailable issue tracker.
