# Codebase Structure

## Directory Layout

```text
alis/
├── shell.qml                     # Root entry — loads services and selects panel family
├── ShellIiPanels.qml             # Material ii panel family
├── ShellWafflePanels.qml         # Windows 11 panel family
├── ShellAbyssPanels.qml          # Perimeter Liquid Shell family
├── GlobalStates.qml              # Runtime UI state
├── FamilyTransitionOverlay.qml   # Animated family switch
├── settings.qml                  # Settings GUI
├── waffleSettings.qml            # Waffle-specific settings GUI
├── welcome.qml                   # First-run wizard
├── killDialog.qml                # Process kill confirmation
├── modules/
│   ├── common/                   # Shared infrastructure
│   │   ├── Appearance.qml        # ii visual tokens
│   │   ├── Config.qml            # Central JsonAdapter config
│   │   ├── perimeter/            # Connected Perimeter core substrate
│   │   └── widgets/              # Reusable widgets + qmldir
│   ├── bar/                      # Classic Bar runtime
│   ├── background/               # Wallpaper + desktop widgets/items
│   ├── sidebarLeft/              # AI chat, music, widgets
│   ├── sidebarRight/             # Toggles, calendar, tools
│   ├── settings/                 # Config UI pages
│   ├── dock/                     # App dock
│   ├── overview/                 # Workspace overview + app search/task view
│   ├── wallpaperLauncher/        # Compact wallpaper carousel
│   ├── abyss/                    # Single perimeter field + embedded native content
│   │   ├── looks/                # Style, deterministic geometry and shader
│   │   ├── bar/                  # Five-zone horizontal/vertical modules
│   │   ├── content/              # Lazy sidebars, dock, popup, clipboard, launcher, OSD
│   │   └── settings/             # Abyss Style and output selection
│   ├── waffle/                   # Windows 11 family
│   │   ├── bar/                  # Bottom taskbar
│   │   ├── startMenu/            # Start menu with search
│   │   ├── actionCenter/         # Quick settings
│   │   ├── notificationCenter/   # Notification list + calendar
│   │   └── looks/Looks.qml       # Waffle visual tokens
│   ├── ii/                       # ii-family overlay/sidebar components
│   └── ...
├── services/                     # Runtime singletons (+ deferred services)
├── scripts/                      # Shell/fish/python helpers
├── sdata/                        # Install/update lifecycle and migrations
├── defaults/                     # Shipped default configuration/templates
├── translations/                 # Canonical en_US UI catalog + validators
├── distro/                       # Packaging/distribution data
├── assets/                       # Icons, wallpapers, systemd unit, desktop entry
├── docs/                         # Documentation and historical research
└── to-do/                        # Active Cloud Bot tasks
```

The live tree intentionally has no Orbit, Mascot, Workspace Strip, `barM3`, Pill-Bar, Islands-Bar, Scenic-Bar, or Frame-Bar module directory. Those systems are retired, not optional renderers.

## Directory Purposes

**modules/:** all UI modules organized by panel family and feature area.

**modules/common/:** shared config, visual infrastructure, perimeter infrastructure, and reusable widgets. `Config.qml` owns the typed runtime schema and the custom-widget persistence workaround.

**modules/common/perimeter/:** Connected Perimeter core substrate: topology and slot configuration, module registry/hosting, anchor publication/lookup, transient-surface routing, and connected geometry/input helpers. Existing bar popups consume this substrate through `modules/bar/StyledPopup.qml`; the retired full `iiPerimeter` runtime remains absent.

**modules/bar/:** the sole ii-family Bar implementation. It supports top/bottom/left/right placement and Classic geometry modes (Hug, Float, Rectangle, Card). Existing bar popups use `StyledPopup.qml`, which provides the connected-surface presentation path without introducing a second popup framework.

**modules/dock/:** the ii-family application Dock. Panel is the canonical supported Dock surface style; legacy persisted style values are normalized to `panel` during startup.

**modules/waffle/:** Windows 11-style panel family with its own bottom taskbar, Start menu, action center, notification center, visual tokens, and settings. Waffle is a separate family rather than a Dock or Classic Bar style.

**modules/abyss/:** independent perimeter-centric liquid family. `AbyssPerimeter.qml` owns one painter per output; `AbyssBodyHost.qml` owns lazy content and bounded input without painting; `looks/AbyssGeometry.js` and `looks/AbyssField.frag(.qsb)` own topology; `looks/AbyssStyle.qml` centralizes palette, motion and effects. Critical/specialist fallbacks share implementations rather than backend copies.

**modules/ii/:** ii-family-specific overlay/sidebar components.

**modules/background/:** per-output desktop surface, wallpaper renderer, desktop items, and desktop widgets.

**modules/overview/:** normal workspace overview/app search/task-view implementation. Orbit is not part of the live overview path.

**services/:** runtime singletons for audio, network, compositor IPC, theming, navigation, wallpaper, desktop layout, lyrics, and related backend behavior.

**scripts/:** CLI, theming, maintenance, and helper scripts.

**sdata/:** install/update lifecycle and append-only migration history.

**defaults/:** curated shipped defaults and platform/application templates.

**translations/:** the canonical English shell UI catalog `en_US.json` plus English-only validation tooling. The runtime does not ship or generate alternate shell UI locale catalogs.

**assets/:** static icons, images, wallpapers, systemd units, desktop entries, and related packaged data.

**docs/:** user/developer Markdown documentation and archived research/history.

**to-do/:** one active chatbot-work index under `cloud-bot/`; ChatGPT is the sole reasoning agent.

## Key File Locations

### Entry points
- `shell.qml` — root shell, services, IPC and family selection.
- `ShellIiPanels.qml` — ii-family loader.
- `ShellWafflePanels.qml` — Waffle-family loader.
- `ShellAbyssPanels.qml` / `ShellAbyssCriticalPanels.qml` — URL-loaded Abyss compositions.
- `modules/common/PanelFamilyPolicy.js` — normalization, cycling and default migration for three families.
- `settings.qml` — standalone Settings process/UI.
- `waffleSettings.qml` — Waffle settings.
- `welcome.qml` — first-run wizard.

### Configuration
- `modules/common/Config.qml` — typed `JsonAdapter` schema and persistence handling.
- `defaults/config.json` — curated default file.
- `Config.options.path.to.key` — runtime reads.
- `Config.setNestedValue("path.to.key", value)` — runtime writes.

Retired Bar keys such as `appearanceStyle`, `bar.m3`, `bar.pill`, and Bar-specific Islands state are not part of the live schema. Shared `m3*` Material color tokens, generic pill-shaped UI, and shared island skins remain valid where consumed by unrelated features. The active Ricelin island implementation is `modules/common/widgets/RicelinSurface.qml`; there is no `modules/pill` compatibility module.

### Classic Bar
- `modules/bar/` — Classic Bar runtime.
- `modules/bar/StyledPopup.qml` — existing popup abstraction with connected perimeter geometry/frame/mask integration.
- `modules/settings/BarConfig.qml` — canonical Classic Bar + Screen Edge settings page; no compatibility facade sits in front of it.
- `bar.bottom` + `bar.vertical` — placement.
- `bar.cornerStyle` — compatibility-only persisted field normalized to Hug (`0`); it is not a renderer selector.
- `bar.opacity` + `bar.borderless` — active Bar surface controls.
- `appearance.screenEdge.width` + `appearance.screenEdge.radius` + `appearance.screenEdge.physicalShadow` — physical perimeter controls surfaced by Bar settings.
- `bar.autoHide.showWhenPressingSuper` — Super-key reveal behavior.

### Dock
- `modules/dock/Dock.qml` — ii Dock runtime.
- `modules/settings/DockConfig.qml` — Dock settings; no legacy style selector.
- `dock.style` — compatibility key normalized to `panel` during startup.
- `SettingsPageRegistry.qml` — startup compatibility migration for legacy Dock styles and UI locale values.

### Connected Perimeter core
- `modules/common/perimeter/PerimeterTopology.qml` — canonical edge/alignment slot topology.
- `modules/common/perimeter/PerimeterConfig.qml` — perimeter configuration adapter.
- `modules/common/perimeter/ModuleRegistry.qml` and `PerimeterModuleHost.qml` — module registration/hosting contract.
- `modules/common/perimeter/AnchorRegistry.qml` and `AnchorPublisher.qml` — rendered-anchor publication and lookup.
- `modules/common/perimeter/SurfaceRouteController.qml` — transient-surface route coordination.
- `modules/common/perimeter/ConnectedSurfaceGeometry.qml`, `ConnectedSurfaceFrame.qml`, `ConnectedSurfaceConnector.qml`, and `ConnectedSurfaceMask.qml` — shared connected geometry/render/input primitives.

Connected popup presentation is already active through `StyledPopup.qml` for existing bar popups. The broad `iiPerimeter` composition cutover remains independently guarded by `PerimeterCutoverPolicy.qml` so connected popup geometry cannot accidentally drop legacy-only functionality.

### Overview and task view
- `modules/overview/Overview.qml` — workspace/window overview and navigation.
- `GlobalStates.qml` — live task-view/overview state.
- `shell.qml` — `taskview` IPC route to the normal task-view state.

### Settings
- `modules/settings/SettingsPageRegistryData.qml` — page metadata/search data.
- `modules/settings/SettingsPageRegistry.qml` — page compatibility routing plus startup normalization of legacy `dock.style` and `language.ui` values.
- Historical retired page indices remain hidden compatibility slots; TLP index 28 still redirects to System.

### Core services
- `modules/common/Appearance.qml` — ii visual tokens/style dispatch.
- `modules/waffle/looks/Looks.qml` — Waffle visual tokens.
- `services/Translation.qml` — English-only shell UI lookup using `translations/en_US.json`.
- `services/DevNavigation.qml` — semantic dev navigation/IPC.
- `services/GlobalActions.qml` — global actions.
- `services/CompositorService.qml` — Niri/Hyprland detection.

### Tests/checks
- `scripts/test-shell-surface-contracts.py` — focused Connected Popup/Dock/Waffle/en_US contract guard.
- `scripts/validate-maintainer-local.sh` — canonical maintainer local validation entry point.
- `scripts/test-local-distribution.sh` — local distribution test script.
- Translation validators live in `translations/tools/`.

## Naming Conventions

**Files**
- QML components: `PascalCase.qml`.
- Services: `PascalCase.qml`.
- Scripts: existing shell/python naming conventions in their owning directory.
- Config JSON: `config.json`.
- Shell UI translation catalog: `en_US.json`.

**Directories**
- Keep the established module names (`sidebarLeft/`, `sidebarRight/`, `actionCenter/`, etc.).
- Waffle-owned surfaces stay under `modules/waffle/`.
- Shared components belong under `modules/common/` only when they are genuinely family-independent.

## Where to Add New Code

**New shared QML component:** `modules/common/widgets/`.

**New module-specific component:** the owning live module directory.

**New service:** `services/` as a `PascalCase.qml` singleton, registered in `services/qmldir` when required.

**New script:** the appropriate existing `scripts/` category.

**New migration:** `sdata/migrations/` using the next sequential number. Existing migrations are append-only history.

**New config key:** update `modules/common/Config.qml`, every live consumer, and the owning Settings UI together; use `defaults/config.json` only for curated fresh-install differences.

**New shell UI text:** wrap the live literal in `Translation.tr(...)` and update the canonical `translations/en_US.json` catalog; do not create alternate shell UI locale catalogs or translation-generation flows.

**New Waffle component:** place it under `modules/waffle/` and keep its taskbar/settings contract separate from Classic Bar and Dock style compatibility.

**New Classic Bar component:** place it under `modules/bar/`; do not introduce a renderer-family selector as part of ordinary Bar changes.

## Connected Perimeter Status

The live shell supports ii and Waffle as separate panel families. Existing bar popups already use the shared connected geometry/render/input primitives through `StyledPopup.qml`, including top/bottom/left/right attachment and edge-origin reveal. The full configurable `iiPerimeter` composition runtime also exists under `modules/common/perimeter/` and `modules/perimeter/`, but its broad ownership cutover remains guarded until it can replace the legacy composition without dropping functionality.