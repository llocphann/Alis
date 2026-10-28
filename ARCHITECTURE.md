# Alis Architecture

> A complete desktop shell built on [Quickshell](https://quickshell.org/) for the [Niri](https://github.com/YaLTeR/niri) Wayland compositor.

**Version**: 1.0.1 · **Stack**: QML (Quickshell), Rust, Bash, Python

Originally forked from [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (illogical-impulse). Secondary Hyprland support is maintained.

---

## Entry Point

`shell.qml` → `ShellRoot` (Quickshell-specific root, not Item/Window).

Startup flow:
1. Environment pragmas configure Qt scale, WebEngine, etc.
2. Singleton services force-instantiated via dummy property bindings.
3. `Config.ready` triggers panel loading.
4. Theme and icon services are applied via `Qt.callLater`.
5. Hyprsunset, first-run wizard, and conflict killer are loaded.

## Panel Families

Three mutually exclusive UI families are switchable at runtime (`Super+Shift+W`):

| | **Material II** | **Waffle** | **Abyss** |
|---|---|---|---|
| Active when | normalized `panelFamily === "ii"` | `panelFamily === "waffle"` | `panelFamily === "abyss"` |
| Visual tokens | `Appearance.*` | `Looks.*` | Palette-derived `AbyssStyle.*` |
| Presentation | Layered Material surfaces | Windows-inspired Fluent surfaces | One perimeter-centric liquid body |
| Bar | Classic, four edges | Windows-style taskbar | Five zones embedded in any edge |
| Launcher | Overview | Start Menu | Edge-attached app/action search |
| Right panel | Sidebar + Notification Center | Action Center + Notification Center | Control/history edge deformation |
| Panels | `ii*` | `w*` and shared panels | `abyss*` and documented shared fallbacks |

Family URL loaders isolate inactive visual trees. Services/models remain shared.
Abyss is not an Abyss Island implementation; its original single SDF owns physical
perimeter, panel union and final silhouette shadow. Critical and specialist
fallbacks are listed in [Panel Families](docs/PANEL_FAMILIES.md).

The retired Bar renderer families (Islands, Scenic, Frame, M3 and Pill) are not runtime alternatives. Shared `island`, `pill` and `m3*` names may still appear where they describe unrelated live skins, widget shapes, Material color tokens, or other non-Bar behavior.

Each panel uses `PanelLoader` (LazyLoader wrapper):
```qml
PanelLoader {
    identifier: "iiBar"
    extraCondition: !(Config.options?.bar?.vertical ?? false)
    component: Bar {}
}
```

A panel loads only when `Config.ready`, its identifier is present in `enabledPanels`, and its `extraCondition` is true.

`Appearance.globalStyle` is runtime-clamped to `material`. Persisted legacy style values are migration input only and must not reactivate alternate shell-wide renderers.

## Directory Structure

```text
shell.qml                     # Root entry — loads services, selects panel family
ShellIiPanels.qml             # Material ii family
ShellWafflePanels.qml         # Windows 11 family
ShellAbyssPanels.qml          # Perimeter Liquid Shell family
GlobalStates.qml              # Runtime UI state
FamilyTransitionOverlay.qml   # Animated family switch
settings.qml                  # Settings GUI
waffleSettings.qml            # Waffle-specific settings GUI
welcome.qml                   # First-run wizard
killDialog.qml                # Process kill confirmation

modules/
├── common/                   # Shared infrastructure
│   ├── Appearance.qml        # ii visual tokens
│   ├── Config.qml            # Central JsonAdapter config
│   ├── perimeter/            # Connected Perimeter core substrate
│   └── widgets/              # Reusable widgets + qmldir
├── bar/                      # Classic Bar runtime
├── background/               # Wallpaper + desktop widgets/items
├── sidebarLeft/              # AI chat, music, widgets
├── sidebarRight/             # Toggles, calendar, tools
├── settings/                 # Config UI pages
├── dock/                     # App dock
├── overview/                 # Workspace overview + app search
├── wallpaperLauncher/        # Compact wallpaper carousel
├── abyss/                    # Original geometry, field, content and settings
│   ├── looks/                # Palette tokens, geometry policy and one shader
│   ├── bar/                  # Five embedded module zones
│   ├── content/              # Demand-loaded native bodies
│   └── settings/             # URL-loaded Abyss Style
├── waffle/                   # Windows 11 family
│   ├── bar/                  # Bottom taskbar
│   ├── startMenu/            # Start menu with search
│   ├── actionCenter/         # Quick settings
│   ├── notificationCenter/   # Notification list + calendar
│   ├── looks/Looks.qml       # Waffle visual tokens
│   └── ...
└── ...

services/                     # Runtime singletons (+ services/deferred/)
scripts/                      # Shell/fish/python helpers
sdata/                        # Install/update lifecycle and migrations
defaults/                     # Shipped defaults
translations/                 # Canonical en_US shell UI catalog + validators
assets/                       # Icons, wallpapers, systemd unit, desktop entry
docs/                         # User documentation
```

Orbit, Mascot, Workspace Strip, and the retired Bar renderer modules are intentionally absent from the live module graph.

## Config System

| Aspect | Details |
|--------|---------|
| Schema | `modules/common/Config.qml` — `JsonAdapter` |
| Defaults | `defaults/config.json` |
| User file | `~/.config/illogical-impulse/config.json` (legacy namespace from fork origin) |
| Read | `Config.options.path.to.key` |
| Write | `Config.setNestedValue("path.to.key", value)` |
| Ready gate | `Config.ready` |
| Hot reload | `watchChanges: true` |
| Debounce | 50 ms for reads and writes |

When adding a live config key, update together:
1. `modules/common/Config.qml` schema/default.
2. Consumer(s).
3. Settings UI for the owning family.
4. `defaults/config.json` only when the curated fresh-install preference differs.

Unknown/stale JSON keys are not schema-backed runtime features and must not recreate retired surfaces. `Config.qml` also intentionally keeps the custom-widget persistence workaround outside the `JsonAdapter`; do not collapse `customWidgetData` into the adapter without re-validating the VME crash workaround.

## Classic Bar Baseline

`modules/bar/` is the only ii Bar runtime. `modules/settings/BarConfig.qml` configures the same runtime rather than choosing a renderer family.

Supported baseline behavior includes:
- top, bottom, left, and right placement through `bar.bottom` + `bar.vertical`;
- one structural Hug surface; persisted `bar.cornerStyle` and `bar.showBackground` values are normalized at startup and never become selectable renderers;
- height, active rounding, background opacity, and borderless controls;
- Screen Edge width/radius/physical-shadow controls colocated with Bar appearance because that frame owns the Bar's physical perimeter;
- Classic audio spectrum settings;
- auto-hide, edge reveal, push-windows, and Super-key reveal (`bar.autoHide.showWhenPressingSuper`);
- clock, module order, workspaces, tray, resources, media, notifications, and utility modules.

Existing bar popups use `modules/bar/StyledPopup.qml`. That popup abstraction now composes the shared Connected Perimeter geometry/frame/mask primitives, so connected edge-attached presentation is the default popup path without a new user-facing toggle.

Waffle remains a separate panel family with its own taskbar settings and is not a Classic Bar appearance.

## Dock Baseline

The ii Dock remains a separate application surface from Waffle's taskbar. **Panel** is the only supported user-facing Dock style. `modules/settings/DockConfig.qml` no longer exposes Pill/macOS/Island/M3 style choices, and `SettingsPageRegistry.qml` normalizes legacy persisted `dock.style` values to `panel` during startup.

The retired `qs.modules.pill` compatibility module is gone. Ricelin remains an active shared surface skin at `modules/common/widgets/RicelinSurface.qml`; Dock, Search, and Sidebar consumers use that canonical component or `Appearance` tokens directly instead of routing through Pill-era aliases.

Waffle is a panel family, not a Dock style, and must not be folded into Dock style migration.

## Key Singletons

| Singleton | Domain |
|-----------|--------|
| `Config` | Shell-wide config read/write |
| `Appearance` | ii/shared visual tokens |
| `Translation` | English-only shell UI lookup (`en_US`) |
| `GlobalStates` | Panel visibility state |
| `DevNavigation` | Development-only semantic navigation |
| `Looks` | Waffle visual tokens |
| `NiriService` | Niri IPC, workspaces, windows |
| `Audio` | PipeWire volume/mute/mixer |
| `CompositorService` | Niri/Hyprland detection |
| `Weather` | Weather polling and location |
| `Network` | NetworkManager integration |
| `Wallpapers` | Wallpaper management and theming |
| `DesktopItems` | Desktop item persistence + undo |
| `DesktopWidgetLayout` | Per-output desktop-widget layout |
| `LyricsService` | Synchronized media lyrics |

Wallpaper pickers apply through `Wallpapers.applySelectionTarget()`. Live preview goes through `Wallpapers.previewWallpaper()` and does not write config or regenerate colors. `modules/background/Background.qml` owns the per-output desktop surface; desktop widget instances are mapped through `Config.options.background.widgets.outputOverrides`, `screenList`, and `layerOrder`.

These are stability boundaries: verify all dependents before reshaping them.

## Settings Compatibility

Settings page indices can be persisted externally, so retired slots remain compatibility concerns even when their UI is gone. The registry keeps retired indices hidden and redirects legacy selections instead of exposing the old feature pages. Historical TLP page index **28** continues to redirect to **System**.

The same registry owns startup compatibility normalization for retired Dock style values and legacy shell UI locale values. `dock.style` converges to `panel`; `language.ui` converges to canonical `en_US`.

This compatibility layer must never revive Orbit, Mascot, Workspace Strip, or a retired Bar renderer.

## IPC System

Handlers are registered with `IpcHandler { target: "name" }` and invoked with:

```text
alis <target> <function> [args]
```

The always-instantiated `dev` target provides session-only semantic navigation for lazy UI:
- `list()` — registered destinations as JSON;
- `open(destination)` — navigate to a named surface/view;
- `close()` — close navigable surfaces;
- `current()` — current destination or `"closed"`.

All IPC functions declare return types. Full reference: [docs/IPC.md](docs/IPC.md).

`taskview` remains a live shell route and maps to the normal Overview/task-view state; it is not an Orbit compatibility route.

## Theming Pipeline

Colors flow:

`wallpaper image → generate_colors_material.py → colors.json → MaterialThemeLoader → Appearance tokens → UI`

Theme generation is orchestrated by `scripts/colors/applycolor.sh`, which updates supported terminal, prompt, launcher, GTK, browser/editor and related application themes.

Names such as `m3primary`, `m3surface`, etc. are Material color-token identifiers and are not the retired M3 Bar renderer.

## Distribution

```bash
git clone https://github.com/llocphann/Alis.git
cd Alis
./setup
./setup install -y
./setup update
./setup doctor
./setup rollback
```

Two install modes are tracked in `version.json`:
- **Repo-sync**: `./setup install` → syncs to `~/.config/quickshell/alis/`.
- **Package-managed**: `make install` → copies to `/usr/share/quickshell/alis/`.

User config for running QML remains at `~/.config/illogical-impulse/config.json`. Shell scripts/CLI default to `~/.config/alis/` with a legacy fallback; those namespaces are not yet unified.

## Migrations

Migrations live under `sdata/migrations/`.
- append-only;
- idempotent;
- never rename/reorder/delete an existing migration;
- choose the next number from the current highest migration.

## Daily Development

```bash
alis run
alis restart
alis logs | tail -50
alis status
alis doctor
alis settings

alis <target> <function> [args...]
alis overview toggle
alis audio volumeUp
```

Never run raw `qs kill -c alis` / `qs -c alis` by hand. Alis runs under the compatibility unit `alis.service` (`systemd --user`); `alis restart` is the supported forced restart path.

## Connected Perimeter Status

Material connected presentation retains its existing ownership boundary:

- **Connected popup presentation is active by default** for existing ii bar popups through `StyledPopup.qml`. `ConnectedSurfaceGeometry` and `ConnectedSurfaceRevealClip` retain the slide-only lifecycle, while `ConnectedSurfaceAbyssFrame` renders the exact Abyss v2.31.0 SDF union in the Overlay window using Top-layer Bar/Screen Edge owner records without repainting those owners. `ConnectedSurfaceBodyMask` keeps compositor input on the revealed rounded body only. Legacy `ConnectedSurfaceFrame` / `ConnectedSurfaceMask` remain available for Waffle and non-cutover shared surfaces; they are no longer the ii StyledPopup renderer.
- **Retired `iiPerimeter` composition remains absent.** Abyss is an independent family with its own output-local renderer, not a reactivation of that cutover. Material ScreenEdges keeps the same locked FrameWindow ownership, rounded workspace opening, Bar-owned inset rules and reservation windows; its healthy paint backend is now the texture-free `ScreenEdgeField` analytic SDF, with the former Shape/MultiEffect renderer retained only as a lazy shader-error fallback.

Detailed contracts and local visual acceptance steps live in `docs/PERIMETER.md` and `docs/SHELL_SURFACE_CONTRACTS.md`.

## Localization Contract

Shell UI localization is English-only. `services/Translation.qml` exposes canonical `en_US`, loads `translations/en_US.json`, and does not scan or generate alternate locale catalogs. Legacy persisted `language.ui` values are normalized to `en_US` during startup. Locale/time formatting controls remain separate from shell UI language.

## Known Harmless Warnings

These log messages are safe to ignore:
- `Failed to create DBusObjectManagerInterface for "org.bluez"` — no Bluetooth adapter;
- `failed to register listener: ...PolicyKit1...` — another polkit agent running;
- `QSGPlainTexture: Mipmap settings changed` — Qt cosmetic;
- `Cannot open: file:///...coverart/...` — missing album-art cache;
- `$HYPRLAND_INSTANCE_SIGNATURE is unset` — expected when running on Niri.
