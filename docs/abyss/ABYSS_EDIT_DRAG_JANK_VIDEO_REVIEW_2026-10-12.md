# ABYSS-R03 — Edit Abyss Layout dragging and expanded-module Popup jank (owner video, 2026-10-12)

**Status:** OPEN, owner reports visible lag remains after source/focused-PASS work.
**Authoritative issue:** [ABYSS-R03](../../to-do/cloud-bot/REWORK_OPTIMIZATION.md).
**Inspected code SHA:** `d636addf4f58fe2136825392820a6d1924e615da` on Alis `dev`; source audit is read-only.
**Input:** user-shared `2026-10-12_14.01.54.mp4` in the ChatGPT conversation, not a Git attachment. No owner-private media copied into repository.
**Source changes:** none. This document records bounded video observations, feasible diagnosis paths and acceptance; it is not another task board.

## Acquisition and mathematical interpretation

- H.264, 1920×1200, 40.000 seconds in file metadata; 1200 fully decoded frames with presentation timestamps `0.000000 .. 39.966667`, separated by `0.033333/0.033334` seconds.
- This is a **30 Hz recorded sample rate**, NOT a measured Qt Quick / Quickshell rendering rate, input rate, desktop refresh rate, or delivered GPU FPS. Rendering between recordings is invisible, as are physical pointer event timestamps.
- The wallpaper region remains nearly static for most of the recording, allowing the top/left connected-body silhouette to be compared in a limited screen-space ROI. First ~14 seconds mostly show the normal desktop/context menu; edit mode becomes visibly active around 15 seconds.
- A repeat-frame check finds 53 strictly identical whole-image adjacent encoded frames among 1199 adjacencies (and 1146 nonidentical pairs). The **longest consecutive strictly identical run is just 2 adjacent pairs (~0.067s)**, not a multi-second full-screen recorder freeze. Low-difference static regions or a stationary cursor do not prove stalled QML animation.
- For one reproducible, deliberately narrow silhouette measurement, grayscale pixels `<27` inside `x∈[0,980), y∈[38,480)` were connected-component grouped (min connected dark area 7500 px). The largest component's bounding width changed from approx. **327 px** at frame 806 (`26.866667 s`) to **186 px** at frame 807 (`26.900000 s`), when the Resources-containing Top field reformed at Left. At frame 879 (`29.300000 s`) it spanned ~**150 px**, then ~**391 px** at frame 880 (`29.333333 s`) during the wide horizontal reveal/reflow. These are DARK-SILHOUETTE diagnostic extents, NOT native QML element widths or physical drag distances; visible recording/render aliasing and threshold sensitivity apply.
- The broadened content/connected field then retracts across approximately frames 912–918 (`30.400–30.600 s`, **~0.2 s recorded**). Do not describe the whole retract as an instantaneous teleport.
- The exact frame-to-frame changes are evidence of visible topological/layout discontinuity, not direct proof of a CPU/GPU bottleneck; no actual measured user-to-frame latency, frame-pacing p95/p99, or resource savings can be claimed.

## Bounded event timeline

| Recorded time | Directly visible |
| --- | --- |
| ~15–24 s | Edit Abyss Layout active, module positions and orientations change across Top and Left Screen Edges; editor panel below. |
| ~25.3–26.9 s | Expanded System Resources/connected dark material is present near Top and then reorients into Left on an adjacent-frame transition (~26.867→26.900 s). |
| ~27–29.3 s | Resources region remains attached to Left, then changes from a tall narrow surface to an outward horizontal surface (~29.300→29.333 s). |
| ~30.4–30.6 s | Connected Resources content/field retracts progressively across about six recorded frame intervals. |
| ~34.6 s | Edit overlay/presentation leaves the edited state. |

Visual description **does not** establish whether the large region at every moment is strictly the hosted `StyledPopup` versus the source module's own local deformation; trace exact QML object identities on the owner-installed build. The owner's subjective report is specifically severe lag while MOVING modules and when their popup/expanded content appears during movement.

## Source facts (read-only) and unproven diagnoses

- `modules/abyss/AbyssEdgeEditor.qml`: `MouseArea.onPositionChanged` maps each pressed pointer movement to `root.move`; `move` invokes `Placement.checkedMove` / `checkedGroupMove`, reassigns `draft`, `guides` and `editingEdge`, schedules toolbar relocation and emits a throttled `controller.impulse`. It does not write persistent Config until Save/Done. This is a concrete event chain, not measured hot-path duration.
- `modules/abyss/looks/AbyssLayout.js`: `geometry` can make up to eight corner-adjustment packing passes; `packGeometry` sorts and resolves collisions per Edge; `localSurfaces` derives connected material surfaces and can join them. A topology switch can change visible field shape. Count *actual* passes per gesture before assuming they are all exercised.
- `modules/abyss/bar/AbyssBar.qml`: `layoutRecords`, `renderedRecords` and `deformations` are derived from the editor draft/module geometry; `measuredExtents` are published via `Qt.callLater`; module input `Region.changed` responds to x/y/size. The dragged target intentionally bypasses x/y Behavior while eligible other modules use at most 140 ms `NumberAnimation`. `settleDimensionChange` completes animations upon edge/dimension changes. These contracts may produce a visible topology cut or additional work but are not proven sources of FPS loss.
- `modules/bar/Resources.qml` contains a `ResourcesPopup` tied to the module `hoverTarget`. `AbyssBarModule.qml` keeps the same content implementation under 90° rotations. `AbyssPerimeter.qml` also routes Popup requests and owns the shared output field; `AbyssBodyHost.qml` includes peer placement animation and special immediate editor geometry. Instrument the exact popup owner, activation lease, host allocation and actual paint/input region.
- Possible contributors to *test*, not established diagnoses: repetitive geometry/reactive binding churn, module resize/reorientation that completes animations, one-frame silhouette topology switching, Popup lifecycle/hover activation while dragging, and output field/native region invalidations. Do not implement speculative shader optimization or suppress user popups globally on this evidence.

## Controlled native reproduction / acceptance

1. **Identify build:** preserve actual owner-installed Alis SHA, renderer, screen refresh/scaling, Quickshell binary, power profile, module placements, editor mode and Popup state; compare exact pin to audited source. Recording 30 FPS alone cannot certify this.
2. **Split runs by causality:** (A) drag a module with all Popups/expanded content closed, same Edge; (B) same drag while its own popup is visible; (C) Top↔Left/Right transfers; (D) dense/locked neighbor repacking; (E) popup auto-hover triggers during active drag; (F) same runs with decorative waves/effects disabled only as controlled diagnostics. Keep functional output and owner config unchanged.
3. **Bounded measurement:** gather time-aligned real wl_pointer motion timestamps where available, QML handler entry/exit, `checkedMove`/packing pass counts and wall-times, measured extent publication, connected local surface/field geometry updates, popup open/close/anchor events, actual native region changes, and render `frameSwapped` timestamps. Distinguish frameSwapped from compositor *presented* FPS; if compositor presentation isn't accessible, label it unavailable.
4. **No false FPS inference:** report actual p50/p95/p99 and max duration of measured spans, stale frame runs under an actively moving pointer, counts of visible x/y jumps relative to mouse pointer, and exact source/capture receipt. No baseline source, no measured improvement claim.
5. **Only after diagnosis:** fix the smallest confirmed hot path or layout/popup ownership discontinuity. Preserve full-size rotated module content, typed Config, existing lock/multi-selection, four-edge continuity, hot corner connectedness, hover/popups outside a drag, and absence of blank workspace interception. Any drag-only hover popup suppression is a **separate A/B experiment requiring approval**, not an assumed product policy.
6. **Owner acceptance:** pointer tracks continuously, neighboring modules repack without bounce/teleport, expanding/shrinking Popup/connected surface does not stall or jerk, and post-drag/hover behavior remains intact on four edges and mixed sizes. Capture matched owner before/after frame/interaction evidence.

Preserve all previous ABYSS-R03 source/focused PASS receipts as scoped history; this owner's observed still-lagging reproduction reopens the product outcome. Existing `POP-I01` handles hover bridge **dismissal**, not drag-induced connected material jank, so do not equate them.
