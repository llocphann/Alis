# Alis Architecture

> A personal desktop shell built on [Quickshell](https://quickshell.org/) and Rust for the [Niri](https://github.com/YaLTeR/niri) Wayland compositor, centered on the Abyss Overlay perimeter.

**Stack**: QML (Quickshell), GLSL (single-SDF perimeter shader), Rust (`native/`), Bash, Python

Originally forked from [snowarch/iNiR](https://github.com/snowarch/iNiR) / [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland) (*illogical-impulse*). Maintained as an unversioned rolling desktop configuration on `dev` (`stable` for promoted snapshots).

---

## Entry Point & Startup Lifecycle

`shell.qml` → `ShellRoot` (Quickshell root, not `Item`/`Window`).

Startup flow:
1. Environment pragmas configure Qt scale, WebEngine, and Wayland rendering behavior.
2. Core singleton services force-instantiate (`Config`, `Appearance`, `GlobalStates`, `CompositorService`, `NiriService`, `Audio`, `Battery`, `Wallpapers`, `AppSearch`, `ColorPickerService`, etc.) while heavy optional/media backends (`CavaService`, `EqualizerService`) defer until demanded.
3. `Config.ready` gates family panel loading (`ShellAbyssPanels.qml`, `ShellWafflePanels.qml`, or `ShellIiPanels.qml`).
4. Theme and icon services (`MaterialThemeLoader`, `IconThemeService`) hydrate via `Qt.callLater`.
5. Optional external packages (`AlisCompanion` and `AlisIntergration`) probe Host API 1 manifests only when explicitly enabled.

---

## Panel Families

Three mutually exclusive panel families are switchable at runtime (`Super+Shift+W`), with **Abyss** and **Waffle** as the public user-facing families (`ii` migrates to `abyss` while sharing the Material token substrate):

| | **Abyss (Primary)** | **Waffle** | **Material II (Shared Substrate)** |
|---|---|---|---|
| Active when | `panelFamily === "abyss"` | `panelFamily === "waffle"` | normalized `panelFamily === "ii"` |
| Visual tokens | Palette-derived `AbyssStyle.*` + `Appearance.*` | `Looks.*` | `Appearance.*` |
| Presentation | One continuous SDF liquid Screen Edge perimeter | Windows 11-inspired Fluent surfaces | Layered Material surfaces |
| Bar / Edge | Five embedded module zones on any Screen Edge + corner Edgebars | Centered bottom taskbar | Classic Hug bar, four edges |
| Launcher / Dashboard | Edge-attached Overview, 4-column Dashboard, Local Music, Planners | Start-Menu-sized Dashboard & Search | Overview + Dashboard |
| Sidebars | Centered edge-welded Feature (`sidebarLeft`) & System (`sidebarRight`) | Action Center + Notification Center | Connected sidebars |
| Settings | Screen-Edge-welded Overlay Mode & floating Window Mode (`iRiS` plates) | Win11-style Settings (`waffleSettings.qml`) | Overlay / Window Settings |

Family URL loaders isolate inactive visual trees while services and config remain shared.

`Appearance.globalStyle` is runtime-clamped to `material`. Persisted legacy style values are migration input only and must not reactivate alternate shell-wide renderers. The retired Bar renderer families (`Islands`, `Scenic`, `Frame`, `M3`, and `Pill`) and retired modules (`Orbit`, `Mascot`, `Workspace Strip`) are absent from the live module graph.

Each panel uses `PanelLoader` (`LazyLoader` wrapper), activating only when `Config.ready`, its identifier is present in `enabledPanels`, and its `extraCondition` holds.

---

## Abyss Overlay Perimeter & Pyramid Popup Architecture

`modules/abyss/` is the centerpiece presentation engine:

- **Single-SDF Painter (`AbyssPerimeter.qml` + `looks/AbyssField.frag(.qsb)`)**: One output-local analytic SDF paints the inverted Screen Edge frame, embedded bar modules, corner Edgebars, popups, sidebars, Dashboard, Settings, Nexus overlay, and elevation shadows in one continuous union without per-box backdrop duplication.
- **Controller & Allocator (`AbyssSurfaceController.qml`, `looks/AbyssBodyPlacement.js`, `looks/AbyssVacancyBorrowing.js`)**:
  - Hosts up to 4 simultaneous mature `StyledPopup` slots (`styledPopup0..3`) plus generic popups (`AbyssGenericPopupPresenter`), sidebars (`leftPanel`, `rightPanel`), `dock`, `notification`, `osd`, `recording`, `dashboard`, `settings`, `nexus`, and `dialog`.
  - Resolves non-overlapping placements around physical anchors, stacking inward or adapting sizes via activation-order-aware Vacancy Borrowing (e.g., Edgebar + Sidebar coexistence, Overview + dual Sidebars).
- **Pyramid Popup Coordinator (`AbyssPyramidCoordinator.qml`, `looks/AbyssPyramidMotion.js`, `AbyssBodyHost.qml`)**:
  - Within a same-edge tangent neighborhood, Pyramid participants (`StyledPopup` slots, `AbyssGenericPopupPresenter`, `notification`, `osd`, and `AbyssRecordingBody`) order by resting area so larger surfaces anchor the Screen Edge base while smaller surfaces stack cleanly inward as the apex, emerging from and retracting into the lower peer's contour.
  - Closing snapshots preserve retract geometry while surviving peers reflow concurrently toward live allocator targets.
- **Global FIFO Hover-Order Close Sequencer (`AbyssSurfaceController.qml`, `AbyssSidebarReveal.qml`, `StyledPopup.qml`, `AbyssPopupContent.qml`, `AbyssRecordingBody.qml`)**:
  - Tracks first-hover activation order across all coexisting hover-driven surfaces (Edgebars, Sidebars, StyledPopups, Generic Popups, Dock, Recording).
  - When pointer hover/focus leaves multiple coexisting surfaces together, they retract in strict **FIFO hover order** (whichever surface was hovered first slides closed first, followed by subsequent surfaces after a clean stagger). Re-hovering cancels pending close immediately; pinned/shortcut-opened surfaces never block transient closes.
- **3-Edge Desktop Edit Stage (`DesktopEditStage`, `AbyssCustomizationDock`, `AbyssEdgeEditor`)**:
  - Shrinks and horizontally centers the live desktop preview while docking external customization controls (`Popups & Panels` / `Tabs` on Left, `Modules` on Bottom, `Screen Edge` / `Layout & Grid` / `Manage Widgets` on Right) with flexible `<= 80%` sizing and monotonic slide motion.
- **Reactive Surface Waves & Power Policy (`AbyssWaveController.qml`, `AbyssRenderPolicy.qml`)**:
  - Feeds Cava audio spectrum and interaction impulses into perimeter wave crests while automatically throttling idle animations under `power-saver` and evicting idle heavy overlay trees after 4 minutes (configurable via `Keep panels warm in RAM`).

---

## Core Subsystems & Services

### Screen Edge & Bar Modules (`modules/bar/`, `modules/abyss/bar/`)
- **Cava Equalizer (`BarCavaEqualizerModule.qml` + `services/deferred/CavaService.qml`)**: Single shared Cava subprocess across all visualizers; resolves active MPRIS / PipeWire playback streams (`alis-native accel cava-config` / `scripts/cava/resolve_audio_source.py`), folds stereo Left/Right channel frames into a true left-to-right bass→mid→treble bar equalizer (or linear mono bins), honors `bar.cava.mirror`, normalizes against CavaService's adaptive `normalizationCeiling`, settles cleanly to a 2px baseline on silence, and gates C++ scene-graph transitions on `root.visible` with zero `FrameAnimation`.
- **Battery Hardware Telemetry (`services/Battery.qml` + `modules/bar/BatteryPopup.qml`)**: Reads kernel sysfs `/sys/class/power_supply/<BAT>/uevent` and `charge_control_*_threshold` alongside UPower fallbacks to report accurate live wattage, voltage, remaining/full/design Wh capacity, health/wear percentage, cycle count, cell chemistry, physics-backed ETA fallbacks, charge-limit status, and quick `PowerProfiles` switching.
- **Connected Bar Popups (`modules/bar/StyledPopup.qml`)**: Rehosted directly into Abyss's SDF field when Abyss is active, or rendered via `ConnectedSurfaceAbyssFrame` + `ConnectedSurfaceRevealClip` + `ConnectedSurfaceBodyMask` in classic `ii` mode.

### Process-Isolated Circular Color Picker (`color-picker-worker.qml`, `services/ColorPicker*.qml`)
- Runs one disposable Quickshell worker process per pick (`ColorPickerService.qml`) so Wayland screencopy teardown never touches the long-lived shell process.
- Receives live Alis theme tokens and recent picks via `ALIS_COLOR_PICKER_THEME` to render a **circular auto-themed magnifier loupe** (`ColorPickerOverlay.qml`) backed by single-readback region sampling (`ColorPickerSampler.qml`).
- Supports immediate center-screen display upon capture readiness, dynamic wheel zoom (`5×`–`19×`), `1px` / `3×3` / `5×5` area averaging, `HEX` / `RGB` / `HSL` / `OKLCH` / `HSV` format cycling, live WCAG contrast ratios, 5 one-key color harmonies (`1`–`5`), interactive recent color recall (`6`–`0`), loupe lock/inspect mode (`L`) for direct mouse swatch/control clicks, pixel-accurate arrow stepping, and automatic `wl-copy` + `cliphist` sync.

### Dashboard, Local Music, Planners & Capture (`modules/dashboard/`, `modules/regionSelector/`)
- **Dashboard (`modules/dashboard/`)**: 4-column responsive widget grid, Sonora-inspired **Local Music** browser (embedded library sidebar, synced Lyrics stacked above a 10-band EQ with live electric-arc curve visualization in `EqualizerPanel.qml`), **Weekly & Yearly Planners**, user-managed **Custom Tabs**, and optional **Spaced Repetition** / **Exercises Tracker** tabs hosted from `Alis-Intergration`.
- **Region Selection (`modules/regionSelector/`)**: Full-screen `Super+Shift+S` capture (`Screenshot` + `Rect` default, `Recording`, `OCR`) with auto-hiding compact toolbar, inline capture annotation editor, and compositor-isolated post-capture notifications.
- **Left & Right Sidebars (`modules/sidebarLeft/`, `modules/sidebarRight/`)**: Left Sidebar hosts `Intelligence` (AI / `Alis-Companion`), `Translator`, `Tools`, and `News`; Right Sidebar hosts Quick Settings, sliders, calendar, and notifications.

### Production Rust Native Backend (`native/`)
The `native/` Rust workspace provides the default production backend via `scripts/native-dispatch`:
- **`alis-native`**: Fast accelerators (`cava-config`, `app-search`, `image-size`, `thumb-info`, plugin scanning, system telemetry).
- **`alis-theme`**: Wallpaper dominant color & K-means color-tag extraction, Material palette generation, and native editor/terminal/Cava/GTK/Qt theme syncing (`editors.rs`, `colortags.rs`).
- **`alis-mpdd`**: Persistent MPD IPC daemon with lean library snapshots (`--lean`) and automatic reconnect.
- **`alis-inputd`**: Input/hotkey helper daemon.

---

## Directory Structure

```text
shell.qml                     # Root entry — loads services, selects panel family
ShellAbyssPanels.qml          # Abyss Perimeter Liquid Shell family (primary)
ShellAbyssCriticalPanels.qml  # Critical Abyss lock/polkit/OSD composition
ShellWafflePanels.qml         # Windows 11-inspired Waffle family
ShellIiPanels.qml             # Shared Material ii family loader
GlobalStates.qml              # Runtime UI & cross-surface coordination state
FamilyTransitionOverlay.qml   # Animated family switch
color-picker-worker.qml       # Disposable process-isolated circular Color Picker worker
settings.qml                  # Standalone Settings window
waffleSettings.qml            # Waffle-specific Settings window
welcome.qml                   # First-run wizard
killDialog.qml                # Process kill confirmation

modules/
├── common/                   # Shared infrastructure
│   ├── Appearance.qml        # Material-clamped visual tokens
│   ├── Config.qml            # Central JsonAdapter config schema
│   ├── functions/            # ColorUtils (tonalStep, WCAG), FileUtils, StringUtils
│   ├── perimeter/            # Connected Perimeter core substrate
│   └── widgets/              # Reusable widgets + qmldir
├── abyss/                    # Single-SDF perimeter, Pyramid v2, FIFO close, Edit Stage
│   ├── looks/                # AbyssStyle, AbyssGeometry, AbyssBodyPlacement, AbyssField.frag
│   ├── bar/                  # Five embedded Screen Edge module zones
│   ├── content/              # Demand-loaded native overlay bodies
│   └── settings/             # URL-loaded Abyss Style & output configuration
├── bar/                      # Shared bar widgets (BarCavaEqualizerModule, BatteryPopup, StyledPopup, Clock, Tray)
├── background/               # Per-output desktop surface, wallpaper renderer, desktop items/widgets
├── dashboard/                # Dashboard grid, Local Music, Weekly/Yearly Planners, Custom Tabs
├── mediaControls/            # BarMediaPopup, EqualizerPanel (10-band EQ DSP canvas)
├── regionSelector/           # Screenshot, Recording, OCR & inline capture editor
├── recordingOsd/             # Embedded Recording controls (hosted by AbyssRecordingBody)
├── sidebarLeft/              # Intelligence (AI/Companion), Translator, Tools, News
├── sidebarRight/             # Quick Settings, Calendar, Notifications
├── settings/                 # Compact iRiS-guided Settings pages + SettingsPageRegistry
├── dock/                     # Panel Dock (AppSearch identity resolution, Alis Nexus icon)
├── overview/                 # Workspace overview + app/action/math search
├── wallpaperSelector/        # Wallpaper picker (Grid & Coverflow with Vim h/j/k/l + auto-baked favorites)
└── waffle/                   # Windows 11 family (Taskbar, Start Menu Dashboard, Action Center, Settings)

native/                       # Production Rust workspace (alis-native, alis-inputd, alis-mpdd, alis-theme)
services/                     # Runtime singletons (+ AlisCompanion, AlisIntergration, deferred/)
scripts/                      # CLI (`alis`), theming, setup recipes, silent regression validators
sdata/                        # Install/update lifecycle and append-only migrations
defaults/                     # Shipped defaults, templates, and Widget SDK
translations/                 # Canonical en_US shell UI catalog + validators
patches/                      # Local Quickshell stability patches
assets/                       # Custom SVG icons (including alis-nexus.svg), screenshots, systemd unit
```

---

## Config System & Tonal Surface Hierarchy

| Aspect | Details |
|--------|---------|
| Schema | `modules/common/Config.qml` — `JsonAdapter` |
| Defaults | `defaults/config.json` |
| User file | `~/.config/illogical-impulse/config.json` (preserved legacy namespace) |
| Read / Write | `Config.options.path.to.key` / `Config.setNestedValue("path.to.key", value)` |
| Ready gate | `Config.ready` (hot reload `watchChanges: true`, 50 ms debounce) |

When adding a live config key, update together: `modules/common/Config.qml`, all consumers, owning Settings UI, and `defaults/config.json` (only if fresh-install default differs). Unknown/stale JSON keys must never recreate retired surfaces. `Config.qml` intentionally keeps `customWidgetData` persistence outside `JsonAdapter` to avoid VME teardown crashes.

### Tonal Surface Layering
All Material/Abyss UI surfaces follow a strict stepped solid tonal hierarchy anchored on `Appearance.colors.colLayer0Base` / `colLayer1Base` (matching Home Dashboard `DashCard`):
- Primary container takes the auto-themed base surface (`colLayer0Base` / `colLayer1Base`).
- Nested cards, metric tiles, and controls step gently via `ColorUtils.tonalStep(base, dir * 0.020..0.044, satBoost)` (~2.0%–2.2% HSL lightness per tier; lightening while headroom exists and gently deepening when `hslLightness > 0.86`).
- Zero per-box decorative `Gradient` fills and zero flat neutral-gray washes; active toggle pills guarantee explicit `colBackgroundToggled` + WCAG `>= 5.0` contrast, centered icon+text alignment, and `Text.CurveRendering` for `MaterialSymbol`.

---

## Key Singletons

| Singleton | Domain |
|-----------|--------|
| `Config` | Shell-wide typed config persistence |
| `Appearance` | Material-clamped visual tokens & motion timings |
| `Translation` | English-only shell UI lookup (`translations/en_US.json`) |
| `GlobalStates` | Cross-panel visibility, output routing & focus leases |
| `DevNavigation` | Development-only semantic navigation (`alis dev ...`) |
| `Looks` | Waffle family visual tokens |
| `NiriService` / `CompositorService` | Niri IPC, workspaces, windows & compositor detection |
| `Audio` / `MprisController` | PipeWire mixer, active playback tracking & MPRIS duration/seek sync |
| `Battery` | Kernel sysfs `uevent` + UPower hardware telemetry & charge limits |
| `ColorPickerService` | Disposable circular color picker worker orchestration & clipboard sync |
| `AppSearch` / `IconThemeService` | Fuzzy app search, window identity remapping (including `alis-nexus`), icon lookup |
| `Wallpapers` / `MaterialThemeLoader` | Wallpaper transitions, previews & auto-theme generation |
| `Weather` / `Network` / `DateTime` | Polling services with coarse tick discipline |
| `DesktopItems` / `DesktopWidgetLayout` | Per-output desktop items and grid layout persistence |
| `LyricsService` | Synchronized media lyrics |
| `AlisCompanion` | Optional [Alis-Companion](https://github.com/llocphann/Alis-Companion) Host API 1 loader |
| `AlisIntergration` | Optional [Alis-Intergration](https://github.com/llocphann/Alis-Intergration) Host API 1 loader (`tlp`, `thinkfan`, `nexus`, `spaced_repetition`, `exercises_tracker`) |
| `SpacedRepetition` | Optional proxy delegating to `Alis-Intergration`'s `spaced_repetition` plugin |

---

## Classic Bar, Dock & Settings Compatibility

- **Classic Bar (`modules/bar/`)**: Sole `ii`-family Bar runtime supporting top/bottom/left/right placement and one structural Hug surface (`bar.cornerStyle` and `bar.showBackground` normalize at startup). `modules/settings/BarConfig.qml` colocates Bar and Screen Edge controls.
- **Dock (`modules/dock/`)**: **Panel** is the sole supported Dock style (`SettingsPageRegistry.qml` normalizes legacy persisted `dock.style` values to `panel`). `AppSearch.resolveWindowIdentity(toplevel)` remaps Quickshell-hosted `"Alis Nexus"` floating windows to `"alis-nexus"` so the Dock displays `assets/icons/alis-nexus.svg`.
- **Settings Compatibility (`SettingsPageRegistry.qml`)**: Preserves hidden compatibility slots for retired page indices (e.g., historical TLP index **28** redirects to **System**) and normalizes `language.ui` to canonical `en_US`.

---

## IPC System

Handlers register with `IpcHandler { target: "name" }` and are invoked via:

```text
alis <target> <function> [args]
```

The always-instantiated `dev` target exposes `list()`, `open(destination)`, `close()`, and `current()`. All IPC functions declare explicit return types. `taskview` remains a live route mapped to Overview/task-view.

---

## Theming Pipeline

```text
wallpaper image → alis-theme (Rust) / generate_colors_material.py → colors.json → MaterialThemeLoader → Appearance tokens → UI + external apps
```

`scripts/colors/applycolor.sh` and `alis-theme` synchronize GTK, Qt, terminals, Zed, VS Code, Cava, Spotify, and Discord/Vesktop themes alongside shell surfaces. Names such as `m3primary` / `m3surface` are Material color-token identifiers, not a retired Bar renderer.

---

## Distribution, Migrations & Daily Development

```bash
git clone https://github.com/llocphann/Alis.git
cd Alis
./setup install
```

- **Repo-sync install**: `./setup install` syncs into `~/.config/quickshell/alis/`.
- **Package-managed install**: `make install` installs into `/usr/share/quickshell/alis/`.
- **Migrations (`sdata/migrations/`)**: Append-only and idempotent; never rename, reorder, or delete existing migrations.
- **Service management**: Alis runs supervised under `alis.service` (`systemd --user`). Use `alis restart`, `alis logs`, `alis status`, `alis doctor`, and `alis settings` — never run raw `qs kill -c alis` / `qs -c alis`.
- **Silent verification**: Automated tests and stutter checks run via `bash scripts/validate-maintainer-local.sh` and offscreen/isolated harnesses (`env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen ...`) without stealing desktop focus.

---

## Connected Perimeter Status

Material connected presentation retains its existing ownership boundary:

- **Connected popup presentation is active by default** for existing `ii` bar popups through `StyledPopup.qml`. `ConnectedSurfaceGeometry` and `ConnectedSurfaceRevealClip` retain the slide-only lifecycle, while `ConnectedSurfaceAbyssFrame` renders the exact Abyss SDF union in the Overlay window using Top-layer Bar/Screen Edge owner records without repainting those owners. `ConnectedSurfaceBodyMask` keeps compositor input on the revealed rounded body only. Legacy `ConnectedSurfaceFrame` / `ConnectedSurfaceMask` remain available for Waffle and non-cutover shared surfaces; they are no longer the `ii` `StyledPopup` renderer.
- **Retired `iiPerimeter` composition remains absent.** Abyss is an independent family with its own output-local renderer, not a reactivation of that cutover. Material ScreenEdges keeps the same locked `FrameWindow` ownership, rounded workspace opening, Bar-owned inset rules, and reservation windows; its healthy paint backend is the texture-free `ScreenEdgeField` analytic SDF, with the former Shape/MultiEffect renderer retained only as a lazy shader-error fallback.

---

## Surface Ownership & Copy Contracts

The sections below document invariant shell ownership, copy brevity, and equalizer boundaries verified by automated repository checks.

### Settings Copy & Surface Ownership

- **Settings copy stays terse.** Section descriptions, helper lines, and control subtitles use only a few words or one short clause. Do not add paragraph-length explanation blocks inside Settings views.
- **Settings base surface has one owner.** Root window chrome and navigation rail ownership stay centralized so embedded and standalone Settings panes remain consistent.

### 2.1 Locked ownership contract — single Caelestia-style inverted frame

- In normal shell operation, Abyss renders the inverted corner/edge frame around the desktop while Normal Bar mode owns only the Bar body and active dock pills without duplicating peripheral backdrop layers.
- `scripts/test-shell-surface-contracts.py` is the regression gate guarding surface ownership, exclusive layer interactions, and edge anchoring.

## Equalizer implementation status

### Implemented

- `EqualizerService.qml` provides the Phase 1 backend/service contract and is disabled by default.

### Stabilizing

- Dashboard EQ preset visualization and per-preset EasyEffects synchronization hardening.

### Planned

- Live spectrum DSP feedback loops, custom curve persistence upgrades, and extended Sink profile routing remain planned/deferred rather than current release prerequisites.
