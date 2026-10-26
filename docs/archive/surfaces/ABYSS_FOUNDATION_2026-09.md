> Historical Abyss foundation archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. Its early family policy and checkpoint instructions are superseded. Current [design](../../ABYSS_LIQUID_MASS.md) and [categorized tasks](../../../to-do/README.md) govern new work; pending hardware acceptance remains open.

# Abyss — Perimeter Liquid Shell

## Phase 0 audit

Audit baseline: `b66aaf32037e7fe7436fc4f0f3a3a3d16ff78e61` on `dev`.
The desktop concept is a geometry reference; its wallpaper, labels and cyan
palette are not data or configuration requirements.

The repository was surveyed across entry points, modules, services, defaults,
install/update and packaging paths, documentation and regression scripts.
Focused reads covered:

- `shell.qml`, `GlobalStates.qml`, `FamilyTransitionOverlay.qml`,
  `ShellIiPanels.qml`, `ShellWafflePanels.qml`, both critical compositions and
  `modules/ii/ShellIiPanelsImpl.qml`;
- `Config.qml`, `Directories.qml`, settings registry, Modules, Bar, Dock,
  welcome profiles and family-related service/CLI consumers;
- `ScreenEdges.qml`, `ScreenCorners.qml`, `docs/PERIMETER.md`, the common
  perimeter manifests, Abyss field adapter/shader, Bar/BarContent/Workspaces,
  Dock/DockApps and SidebarHost;
- ResourceUsage demand leases, MPRIS, Notifications, clipboard model,
  TaskbarApps/AppSearch, Niri workspace/output APIs, GameMode and theme pipeline;
- canonical maintainer validator, family/critical isolation, input lifecycle,
  perimeter, module manifests, startup, IPC generation and packaging contracts.

Findings:

1. Families currently enter through URL-based critical/deferred loaders. Several
   ii boundaries use `!== waffle`; a third family requires explicit selection.
2. Material's physical Screen Edge is geometry-locked. It paints one rounded
   workspace hole per output and reserves work area with transparent windows.
   Its painter, corners, insets and fullscreen mapping must remain unchanged.
3. The existing connected field wraps upstream Abyss. It joins separately owned
   overlay bodies and crops their paint at owner boundaries. Abyss needs a
   different composition: one final silhouette for all perimeter deformations.
4. Common IPC routers already live in the root. No new presentation component
   should register an existing target. Shared critical flows can be source-loaded
   behind Abyss panel IDs rather than copied.
5. Bar presets provide five zones in both orientations. Services and app/workspace
   identity are reusable; Material pill hosts and surface painters are not.
6. Expanded overlays must reserve zero space. Input must be the union of actual
   content rectangles, with the workspace hole excluded. Closing content must
   immediately release its input region, even while geometry retracts.
7. Resource polling is demand-driven. New consumers must balance keepAlive and
   releaseKeepAlive. Geometry/effect state must be stable at rest.
8. Local validation is authoritative for source contracts. Actual output hotplug,
   mixed DPI, suspend and desktop interactions require separate runtime evidence.

## Implementation plan

1. Add the `abyss` family boundary, safe lazy tree, panel IDs, migration,
   selection and a short input-free transition. Keep `ii` as the default and
   normalize unknown families to `ii`.
2. Prove a single deterministic SDF silhouette using one shared ShaderEffect.
   Intersecting perpendicular deformations require a real union; a sampled
   Shape contour would need an additional boolean-geometry implementation.
   Subtract one rounded workspace opening from the screen; deform that opening
   for edge-attached content. One silhouette owns fill, rim and optional shadow.
   Transparent reservations remain separate from the visual host.
3. Embed an Abyss-owned five-zone bar and reuse workspace, tray, media, weather,
   battery and system models through plain content controls.
4. Add dock retraction, one connected popup and sidebars through the same contour
   records. Validate their union before adding effects or secondary surfaces.
5. Add demand-loaded clipboard/launcher/notification content and transient OSD
   records; retain documented shared fallbacks for critical and specialist flows.
6. Add bounded motion, palette-derived material tokens, performance presets and
   focused settings. Real backdrop refraction requires evidence; an honest static
   absorption/specular fallback takes precedence over an expensive unproven pass.
7. Run behavioral geometry/family tests, parser/module checks, runtime captures
   and the canonical validator on the final committed SHA. Record each milestone
   and distinguish source validation from environment acceptance.

Topology precedes interaction, legibility, motion, glass and glow. Abyss is not
an Abyss Island implementation. No Material tree duplication or corner patches
are part of this plan.


## Foundation checkpoint (phases 1–2)

- Family skeleton: `69c90e79f`, pushed to `dev`. Three-family policy tests and
  existing transition/critical isolation tests pass. Qt 6.11.2 parses the new tree.
- Native foundation: original `AbyssField.frag(.qsb)`, `AbyssGeometry.js`,
  `AbyssStyle.qml`, `AbyssPerimeter.qml` and the Abyss critical entry. Config gains
  an isolated `abyss.*` namespace; existing palettes and Material geometry stay intact.
- Visual: [actual GPU topology capture](../../evidence/abyss/phase2-topology.png),
  Quickshell 0.3.1 / Wayland / OpenGL, 1100 × 700 logical pixels. The shader reports
  compiled. Perimeter, popup, sidebar and dock share one silhouette and shadow.
  This is a renderer capture, not multi-monitor or full desktop acceptance.
- Input: foundation host and reservation windows have empty input masks and no
  keyboard focus. Expanded content will add bounded regions in the next milestone.
- Geometry tests execute the production JS for four bar/dock directions and
  scales 1, 1.25, 1.5 and 2. Opposing deformations preserve the workspace center.
- A perpendicular placement rule keeps popup/dock content out of sidebars. It
  also prevents intersecting panels sealing an isolated corner workspace pocket.
  The renderer still computes the union; this is content placement, not corner paint.
- Idle: no timer or time uniform in the field; geometry and color bindings are
  unchanged at rest. One ShaderEffect per output, no per-module texture passes.
- Baseline validator on `b66aaf3` found pre-existing stale `IslandPanel` and update
  availability assertions (the latter also fails the aggregate distribution test).
  Baseline is not green. Parser probing also skipped because `/usr/bin/qmlformat`
  version detection fails; the explicit `/usr/lib/qt6/bin/qmlformat` parser works.
- Next: embedded content, bounded input, native bar, dock, sidebar and popup.


## Embedded bar checkpoint (phase 3)

Inspected the two orientation presets, workspace IDs/output resolution, tray
interaction, MPRIS metadata and resource polling leases. Added `abyss/bar/*` and
`AbyssButton`; the perimeter now hosts bar content and its five shallow bulges.
Shared services are reused and no bar module owns a surface background. The
transparent reservation includes the maximum 5 px bar bulge. Only the actual
bar bounds receive input; the center stays empty.

[GPU bar capture](../../evidence/abyss/phase3-bar.png) uses actual workspace, tray,
MPRIS and clock data. Runtime testing caught a final `AbstractButton.icon`
collision, then an `onSurface` token initialized as a handler-shaped name rather
than the intended color. The API now uses `textColor`/`textColorMuted`; the runtime
measured text contrast is 16.40:1 against the deep surface. Qt fonts and palette
are inherited. Five-zone ordering/deduplication/visibility use the tested pure
geometry policy. Resource consumers release their lease when hidden or destroyed.

A pre-existing `DateTime.qml` missing-root-id warning was exposed by the capture
and remains queued for an independent correction. Sidebar, dock and popup
content are the next milestone; this checkpoint does not claim functional core
acceptance yet. Native tray menus deliberately keep the existing shared control.


## Connected content checkpoint (phases 4–6)

Inspected DockApps/TaskbarApps and sorting demand, physical sidebar role routing,
MPRIS controls, brightness output resolution, Cliphist pin/copy/delete contracts
and LauncherSearch actions. `AbyssBodyHost` supplies a deformation record and a
clipped content rectangle without painting a body. `AbyssPerimeter` consumes all
records in the same field and unions only live content input rectangles.

- [Dock capture](../../evidence/abyss/phase4-dock.png): pinned/running app icons and
  launcher grow from the selected edge; right click toggles pinning through the
  existing service. No dock background, gap or second shadow is painted.
- [Sidebar capture](../../evidence/abyss/phase5-sidebar.png): shared CPU/RAM/GPU/storage,
  output brightness, audio, Wi-Fi/Bluetooth/DND, media, locations and weather
  appear as typography and fine separators inside a right-edge deformation.
- [Popup capture](../../evidence/abyss/phase6-popup.png): bar-origin media, sidebar and
  dock share one silhouette. Perpendicular placement keeps content and the
  workspace opening connected. Calendar/resources/weather/battery/audio use the
  same host, with content loaded only for the chosen kind.
- Tools navigation is native. AI chat and local music deliberately use the
  existing content implementation when their tabs are requested. These are
  specialist content fallbacks, not separately owned Material shell panels.
- Native clipboard reuses Cliphist history, search, text pins, copy/delete and
  two-step clear. Native launcher reuses LauncherSearch actions/prefixes and
  AppSearch, with output-local workspaces/window activation. Both enter through
  the bottom deformation and demand-load their existing deferred services.
- Every host releases input immediately on close while its contour retracts.
  Wayland runtime recorded live bounded rectangles and `0×0` for all closed
  hosts. Loader bodies were ready for dock, system sidebar, popup, launcher and
  clipboard. This does not substitute for manual click/drag/fullscreen acceptance.
- Bar auto-hide and dock edge reveal have thin bounded triggers and finite close
  timers. Dock sorting and resources use balanced demand leases. Body motion is
  bounded and observes disabled animations.

Qt 6.11.2 parsed the new QML. Production geometry and family tests pass. Real GPU
captures caught missing deferred-service imports, which are corrected. Existing
DateTime root-id and TaskbarApps initial binding-loop diagnostics remain under
review; the second notification-server warning comes from running the capture
alongside the installed shell. No notification backend is duplicated in Abyss.
Next: native notifications/OSD, effects, settings integration and complete local
validation. Full desktop and multi-output acceptance remain outstanding.


## Secondary content and routing checkpoint (phase 8 foundation)

Inspected notification popup/history policy and actions, all three OSD trigger
paths, volume protection, keyboard/touchpad indicators, critical fallback sources
and the Alt+Tab router. Added native notification/history and status OSD content.
[Notification capture](../../evidence/abyss/phase8-notification.png) uses a real local
freedesktop notification fixture on an isolated D-Bus session; it is labelled
validation data. [OSD capture](../../evidence/abyss/phase8-osd.png) uses the shared Audio
value. Both have only the final perimeter silhouette and finite retraction.

Root-owned `osd`, `osdVolume` and `osdInput` IPC handlers forward internal signals
to the active presentation. Material retains its existing trigger/timeout logic;
Waffle retains its indicator renderer and gains working shared volume/hide input.
Abyss observes existing Audio/Brightness/Keyboard/MPRIS state with one bounded
OSD timeout. Popup notifications use one scrollable swell, inherit DND/quiet-hour
and GameMode policy and preserve actions/dismiss/history. A notification center
replaces the system sidebar's physical slot while open. Popups yield to active
bar/launcher content rather than overlapping its controls.

Abyss uses the shared no-visual Alt+Tab controller. The previous two-family
predicate would forward Abyss commands to an absent Material visual tree; it now
selects that tree only for `ii`. Overlay/control-panel/dashboard are documented
shared demand-loaded fallbacks alongside critical/screenshot/OSK/update flows.
Changing family clears ordinary presentation state without dismissing lock or
polkit. Direct config changes share family migration at the root boundary.

The actual native Wayland layer-shell host loaded, opened/closed sidebar, OSD and
notification center without an Abyss QML diagnostic after two semantic fixes
(read-only indicator kind and Flow implicitHeight). Unsupported/uncompiled paint
never receives keyboard or body input. Fullscreen remains Top/mapped by default;
explicit visible-in-fullscreen opts into Overlay and still releases reservations.
Production host regression now exercises deferred loading, output binding,
immediate input release and unload/reopen in QML. Existing transition/input,
family/geometry, local manifest and generated IPC registry checks pass.
Phase 7 richer material/motion, settings and full acceptance are next.


## Material and motion checkpoint (phase 7)

[Wallpaper material capture](../../evidence/abyss/phase7-material.png) is a real GPU
render with the desktop's selected static wallpaper, live content and Quality
settings. Topology still comes from the original single SDF. A hidden static
Image texture is decoded at bounded output resolution; the same field pass adds
a five-tap wallpaper blur, local normal-based UV refraction, deep absorption,
palette rim, glow and silhouette shadow. This is wallpaper glass; application
pixels are not captured. Missing/animated wallpaper uses the palette body.
Performance disables the texture, refraction, glow and shadow. Balanced uses
blur without refraction; Quality permits explicit refraction and a small settle.
Global low-power/GameMode effects gating and reduced motion remain authoritative.

Body motion pulls inward over 180–260 ms, then settles only when Quality
overshoot is present (at most 2.5%). Close drops input before retraction.
Intensity controls bounded timing; zero/global reduced motion changes geometry
synchronously. Bar auto-hide also retracts thickness, with a thin reservation
throughout hover reveal. Persistent pinned docks reserve their actual inward
depth; temporary panel/popups keep zero exclusive zone. Reservation windows
remain transparent with empty input masks.

Production host runtime tests pass, including synchronous reduced-motion close.
Geometry tests add small logical views and a flood-fill of the actual union to
reject sealed workspace pockets across four orientations and combined layouts.
Shared service fixes are separate: `04d0e0148` restores the uptime root callback;
`1f21dffce` coalesces TaskbarApps identity resolution outside a binding, preserving
pins/filtering/order/Niri authority under an executed production-model regression.
The latest GPU capture has neither prior shared-service diagnostic. Settings,
docs, full-shell switching and performance qualification are next.


## Configuration checkpoint (phase 9)

Inspected both settings-family selectors, the welcome profile, settings page
registry and launcher actions. Modules and Waffle Settings now select all three
families through the shared router, preserving disabled-panel preferences. Welcome
also offers Abyss; Material remains the default. The common settings registry
hides Material/Waffle-only pages for Abyss without renumbering persisted slots.

`abyss/settings/*` supplies URL-loaded Abyss Style groups for Performance,
Surface, Motion, Refraction & Glass, Perimeter, Bar & Dock, and Panels. Bar layout
editing and output selection reuse canonical config keys. Output selection keeps
at least one live output and safely resolves stale selections. Reduced motion is
global. Settings is a shared standalone fallback; it is not another shell-body
painter. [Actual settings capture](../../evidence/abyss/phase9-settings.png) loaded the
new page in Wayland Quickshell with no QML reference/type/binding diagnostic.

Panel-family, perimeter, architecture, structure, config and IPC docs now describe
three independent families, native ownership and shared fallbacks. The generated
IPC registry classifies root-owned OSD as shared. Next: complete regression
validation, repeated full-shell switching and native input/idle qualification.
No hardware multi-output or desktop acceptance is inferred from these checks.


## Native qualification checkpoint (2026-09-27)

Final code: `58aae0b91e214deeafb9c58841dc57273ac2cb7c`, tree
`08dc1bcffb50b350ce4205afb074b6080d61ccf6`. **Core status: NOT_COMPLETE.**
The implemented core is qualified locally within the one-output scope described below. Physical
multi-output/hotplug/suspend and desktop resize acceptance remain open.

Switching, input and idle measurements below use code `47718a415`. The final
delta excludes unloaded content loaders from the popup layout; it is covered
by an executed rendered-Qt regression and the final native capture. Each artifact
records its own SHA. Family ownership, field/mask geometry and idle workload are
unchanged by that content-layout correction.

Inspected the root family loaders and shared IPC lifetime, Qt ShaderEffect
readiness/cache behavior, Niri/GameMode fullscreen size heuristic, compositor
layer/input state and shared OSD bindings. Runtime evidence led to nine focused
corrections:

| Commit | Change and observed reason |
| --- | --- |
| `b92f1d4dd` | Release the outgoing critical/deferred family before constructing the next. The previous lifecycle registered duplicate shared `background` IPC and discarded an owner. The executed old-source control reproduces duplicate registrations. |
| `ff6a1cd1d` | Gate field input on a presented frame, supported graphics backend and absence of shader error. Qt's QSB reflection cache can draw a recreated effect while its new manager remains Uncompiled; Compiled-only gating hid content on the second visit. The old predicate fails the real-GPU recreation test; five cold/cached creations, malformed QSB and software fail-closed checks pass. |
| `bb9dde2b0` | Hold a transparent, input-free 3 px reservation during family handoff. Gapless tiled clients otherwise temporarily fill the output, triggering the existing fullscreen-size heuristic and hiding incoming reservations. |
| `609a75ef4` | Resolve OSD border style flags through Appearance. Old value/media indicators reproduce ReferenceError for bare auroraEverywhere/alisEverywhere; production components now instantiate cleanly. |
| `12e210182` | Keep the guard per output during fullscreen and for 80 ms after exit. Fullscreen clients ignore exclusive zones; unfullscreen tiled clients become distinguishable before family reservations return. The guard has alpha 0, empty input, no keyboard focus and settled zone 0. |
| `1758ce02d` | Preserve Qt `list<string>` pins and ignore patterns with sequence normalization. `Array.isArray` rejected these real config values. The old-source Qt list test fails; pin/unpin now retains other pins and the live app model resolves installed apps. |
| `d1ff545fc` | Release the desktop widget-toggle binding when its background owner is destroyed. The restored app workload exposed 15 late-binding TypeErrors during switching; the nullable owner now yields false during teardown. |
| `47718a415` | Remove the outgoing Waffle host's Material clipboard fallback. Its inverse family predicate could incubate an unowned transparent full-screen window while leaving Waffle. Wayland trace showed default full input and pointer enter on clipboardPanel with all ordinary state closed; stopping the shell restored clicks. The old-source lifecycle control creates Material on exit; the corrected loader preserves Waffle's native clipboard and never constructs that owner. |
| `58aae0b91` | Hide inactive popup content loaders from the layout. Qt retains their previous implicit size after unload; the old media loader left a blank gap and clipped calendar weeks. The old-source rendered-window control fails. The final popup fits all 42 days after media/weather changes and at 1.5x typography; the native capture shows all six rows. |

Changed code: `shell.qml`, `FamilyWorkAreaGuard.qml`, `FamilyWorkAreaHold.qml`,
root `qmldir`, `modules/waffle/ShellWafflePanelsImpl.qml`, `modules/abyss/looks/AbyssField.qml`, shared OSD value/media indicators, `background/Background.qml`, `services/TaskbarApps.qml`, `modules/abyss/content/AbyssPopupContent.qml` and
six focused shell/shader/controller/Qt-list/clipboard/popup regression scripts. Material's production
`modules/screenCorners/ScreenEdges.qml` has **zero diff** against audit baseline
`b66aaf3`. Waffle remains an independent supported family.

### Environment and source identity

Quickshell 0.3.1, Qt 6.11.2, Niri 26.04, Wayland/OpenGL on the AMD Radeon 740M
host. The nested compositor has one winit output, 1920 x 1200, scale 1, zero gaps
and full-width columns. The owner desktop remains running. The shell uses a
private D-Bus session, isolated XDG profile, production defaults and a static
wallpaper. The archive uses the supported Python helper fallback.

[Source hashes](../../evidence/abyss/phase9-native-identity.json) and the
[instrumentation patch](../../evidence/abyss/phase9-native-harness.patch) identify six
copies with frame counters/state observations plus isolated config/popup test
commands. Production rendering and family logic otherwise match the code tree.
Native pointer/keyboard events use wlr virtual pointer and wtype. The winit
window stays visible because an occluded nested output defers frame callbacks.
1590 other production files match their Git blobs, including symlink targets.
These are local native-device checks, not human physical-device acceptance or CI.

### Observed behavior

[Switching evidence](../../evidence/abyss/phase9-switching.json): 20 complete animated
Material -> Abyss -> Waffle -> Abyss -> Material cycles, then four reduced-motion
cycles. Four additional animation-disabled cycles are in the
[native input evidence](../../evidence/abyss/phase9-native-input.json). Each transition
has exactly one active/loaded family, one Abyss painter in Abyss and one Material
Screen Edge in ii; default Waffle has no Screen Edge. Launcher opened before
leaving Abyss releases exclusive keyboard focus and app clicks. No crash, stale
ordinary state, duplicate IPC, QML reference/type error or binding loop was found
in the qualified run.

Native input checks pass for center/all four edges, bare-desktop right click, launcher/sidebar Escape,
four bar orientations with bounded popup/sidebar/dock geometry, bar auto-hide,
dock hover reveal/retract, fullscreen suppression, explicit fullscreen Overlay,
unfullscreen restoration, workspace round trip, compositor resize/move and
pointer titlebar drag. Output scale 1 -> 1.25 -> 1.5 -> 2 -> 1 passes with live
field readiness and app input at every step. This is one compositor output;
it does not prove simultaneous mixed-DPI displays.

The Qt probe's client-decoration corner resize did not change dimensions; a
product cause was not established. Compositor resize succeeds and near-edge
app clicks remain live. Physical desktop resize acceptance is still pending.
The source-archive preview helper also reports exit 126 from its pre-existing
non-executable self-invocation; window identity/icon rows work, thumbnail fallback
is not qualified here. Shared icon lookup warnings for unavailable fallback identifiers
are also separate from the QML error checks. These limitations are retained in the evidence.

### Idle and recovery measurements

[Bounded measurements](../../evidence/abyss/phase9-idle.json) use a fresh QS process
for each family, the same full-width input client/static wallpaper/default pins,
10 s warm-up and one 20 s sample per idle mode. Abyss uses Balanced with
refraction off. CPU is the QS process percentage of one logical core; resident
memory excludes child processes. Presented scene frames are not GPU utilization.

| Mode | Seconds | CPU, one core | RSS after, MiB | Perimeter frames | Separate bar frames |
| --- | ---: | ---: | ---: | ---: | ---: |
| ii / idle | 20.0 | 4.9% | 871.37 | 0 | 16 |
| abyss / idle | 20.0 | 3.4% | 678.89 | 6 | included |
| abyss / eight finite sidebar open-close cycles | 7.181 | 9.33% | 682.19 | 222 | included |
| abyss / idle after interactions | 20.0 | 3.15% | 680.82 | 8 | included |

Eight finite sidebar open/close cycles repaint while moving; after a 5 s settle,
the next sample returns to occasional clock/resource updates. No sustained
60/120 fps loop was observed. These bounded observations are not a statistical
speedup claim. Earlier samples with rejected typed pins or a narrow client column
are superseded; only the restored app workload is tabulated here.

### Final native appearance

[1920 x 1200 native capture](../../evidence/abyss/phase9-native.jpg) and
[capture metadata](../../evidence/abyss/phase9-native-capture.json) use final code
`58aae0b91`, the selected city wallpaper, Quality/refraction, Tools and a native
calendar connected to the same field. This image is an actual compositor capture;
the earlier cropped-calendar capture was rejected. All six calendar rows and the
related-settings action are visible in the final image. The image's Quality
settings are separate from the Balanced performance measurements.

### Acceptance boundary and next readiness

| Gate | Local result / remaining scope |
| --- | --- |
| Family routing, owners and cleanup | Native repeated switching plus executed loader/IPC regression. |
| One field, embedded bar/dock/sidebar/popup | Production geometry/flood-fill tests and native GPU capture; no independent body fill/shadow owners. |
| Input and fullscreen | Native event checks pass within one output; physical client-decoration resize remains open. |
| Material and Waffle | Local regressions and native tree/input checks; Material Screen Edge source unchanged. |
| Idle renderer | Bounded scene-frame and process measurements below; no sustained frame loop observed. |
| Multi-output/hotplug/mixed DPI/suspend | **PENDING: only eDP-1 hardware is attached.** Single nested-output scale tests are separate evidence. |
| Canonical source/package acceptance | Run the exact-HEAD local command after this evidence publication; its printed SHA and final result are the authority. |

Reproduce local acceptance with:

```sh
PATH=/usr/lib/qt6/bin:$PATH bash scripts/validate-maintainer-local.sh --current-repo --strict-qml
```

This clean-clones the committed HEAD, checks repository regressions and the
required QML parser. A PASS applies only to its printed SHA. Nix is deferred and
non-blocking. No GitHub Actions status is used as a substitute for local checks.

Next readiness is hardware desktop acceptance: two outputs with different scales,
output-targeted popups/focus, fullscreen isolated to one display, hotplug and
suspend/resume, plus a physical-client resize gesture. Retain **NOT_COMPLETE**
until those gates close; do not expand secondary surface ports first.
