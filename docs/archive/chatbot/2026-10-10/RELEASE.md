> Historical snapshot archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../../to-do/README.md).

# Cloud Bot — Alis v1.0 release/source backlog

Migrated from root `README.md` §§3 and 6 on 2026-09-30. Existing unchecked boxes are release gates **not** proof that source work is missing on current `dev`; verify code and maintainer acceptance before doing or closing a task. Deterministic and human-only validation are separately classified in [`../local-bot/VALIDATION.md`](../../../VALIDATION.md).

## 3. v1.0 release blockers

Checkboxes below are **release gates**, not an assertion that no partial implementation exists. A line explicitly labeled **source-complete** may be checked once its source/contract work is complete; runtime-sensitive acceptance remains open until the relevant local/live validation passes.

> **Current release status (2026-09-25):** current `dev` has the production Rust cutover, Material-only public Global Theme boundary, Abyss connected-surface baseline, ThinkFan integration, compact System Monitor refinements, current Calendar/Weather composition and the existing media/equalizer implementation. Rust/native has dedicated parity/contract coverage. Remaining release work is primarily live desktop acceptance, hardware/compositor validation, the known Settings/navigation defect, final active-tree residue cleanup, and exact-candidate validation. Historical implementation sequences belong in Git history / `CHANGELOG.md`, not in this active checklist.

### A. Screen Edge and connected surfaces — P0

> **Latest perimeter correction:** the legacy round-wedge/corner renderer family is retired. Curved connected contact is Abyss-owned; otherwise the joined body edge stays square. Horizontal/vertical Bar PanelWindows and the canonical Screen Edge frame remain independently owned and mapped across fullscreen.

- [ ] **Screen Edge exists both while idle and while a window is maximized.** It must not disappear simply because no maximized window is present.
- [ ] **Bar survives fullscreen enter/exit without reload.** Horizontal and vertical ii Bar native surfaces and the painted Screen Edge `FrameWindow` stay mapped/updating; fullscreen coverage is owned by compositor stacking, not `visible`/`updatesEnabled` gates. Transparent reservation-only windows may release their exclusive zones independently. Leaving fullscreen must restore all Bar contents immediately without `alis restart` or shell reload.
- [ ] **Screen Edge width is configurable in Settings.** The setting must use one canonical configuration field, have a safe default/range and update the active edge without requiring an alternate renderer.
- [ ] **Screen Edge corner radius is configurable in Settings and defines the physical ii Bar/Screen Edge.** Default is 25px. Direct-attached surfaces do not derive a second legacy wedge radius from it; Abyss contact remains independently tokenized.
- [ ] **All connected surfaces use one direct-attachment contract.** No popup may invent a private gap or auxiliary round-wedge patch. Shared geometry/Abyss owns seam overlap, joined-edge ownership and shadow/input clipping.
- [ ] **No visible gap between bar/Screen Edge and popup body.** Shared geometry must own seam overlap so fractional scaling, animation and antialiasing do not expose a slit.
- [ ] **Left and right Sidebars connect to the vertical Screen Edge**, not to the top bar or bottom screen edge.
- [ ] Connected surfaces behave correctly for top/bottom/left/right bar placement, transformed outputs and fractional scale.
- [ ] Reverse retract / hover bridge keeps the source and popup visually and interactively continuous during close/reopen transitions.

### B. Popup interaction correctness — P0

> **Latest maintainer correction (2026-09-18):** direction-only translation is insufficient. During reveal/retract the popup body must remain full-size, translate toward/away from the owning edge, and be clipped at the resting attachment boundary so the hidden portion is visually underneath the Bar/Screen Edge. The connected body must not scale/shrink.

- [ ] Existing bar popups continue to use `modules/bar/StyledPopup.qml` and the shared connected-surface primitives.
- [ ] Popup placement anchors from the real visual source control / `hoverTarget`, not a loader or lifecycle wrapper.
- [ ] Keyboard focus, initial focus, Escape close and compositor focus-grab behavior remain correct.
- [ ] Outside-click close works without stealing input from transparent regions.
- [ ] Full-output click-catchers are owned by the same output as their popup on multi-monitor setups.
- [ ] Tray menu delayed-close logic cannot release the focus/grab of a newer active tray menu.
- [ ] No guessed `PanelWindow.active` / `onActiveChanged` style APIs are introduced without verifying the current Quickshell API.

### C. Thinkfan + System Monitor — P0

- [ ] **Thinkfan UI is integrated into the existing System Monitor popup** instead of living as a separate standalone popup.
- [ ] **Thinkfan settings are exposed in Settings** in the appropriate system-monitor/thermal area.
- [ ] Reuse the existing Thinkfan helper/service path; do not create a duplicate fan-control backend.
- [ ] Unsupported/missing Thinkfan environments fail gracefully and do not break System Monitor or Settings loading.
- [ ] Fan status/control state stays synchronized between Settings and the System Monitor popup.

### D. Settings correctness — P0

- [ ] **Settings > Bar renders real content** and no longer presents an empty page.
- [ ] Bar settings expose only supported v1.0 behavior; retired Dock/Bar renderer switches must not reappear through routing.
- [ ] Settings page loading remains lazy/deferred enough to avoid large synchronous rebuilds.
- [ ] Screen Edge width and Thinkfan controls are reachable through the normal Settings navigation.
- [ ] No user-facing setting remains that points to a removed runtime with no effect.
- [ ] Global Theme UI exposes **Material only**; no removed theme can still be selected, previewed or routed through Settings.

### E. Media Popup equalizer — P0

> **Latest maintainer correction (2026-09-19):** the DSP curve keeps a compact electric current visible at rest. Preset changes and direct band edits brighten the same current without increasing stroke width or jitter amplitude; the old oversized transient sweep/per-band growth is retired. This remains presentation-only and does not create a second DSP backend. Live visual/audio validation remains pending.

- [ ] The bar-attached Media Popup suppresses `PlayerControl`'s decorative `WaveVisualizer`; its **10-band DSP Equalizer** is the only live CAVA/analyzer surface in that popup. Other `PlayerControl` owners may still use the optional wave visualizer.
- [ ] The same Media Popup includes a **10-band DSP Equalizer** below the player card, using the existing optional `EqualizerService` / EasyEffects backend rather than a second ad-hoc equalizer process. User-facing bands are 31/63/125/250/500/1k/2k/4k/8k/16k Hz with the Serpantinum Flat/Bass/Treble/Vocal/Pop/Rock/Jazz/Classic curves.
- [ ] Confirm the required CAVA runtime/package is present in the supported install/package paths, or document/install it where currently missing. EasyEffects + socat remain optional capabilities and must degrade gracefully when absent.
- [ ] Equalizer/analyzer lifecycle is efficient: the bar popup owns no redundant decorative CAVA subscriber; the DSP analyzer starts only while the popup is presented and survives pause/resume, player switching and popup close/reopen.
- [ ] MPRIS controls, seek, volume and keyboard behavior do not regress while the visualizer/DSP controls are active.

### F. Clock Calendar / Weather composition — P0

> **Latest maintainer direction (2026-09-19):** Calendar is owned by Clock as a dedicated Obsidian-inspired connected popup. Weather is a separate two-tab connected popup: tab 1 is the 8-hour orbital forecast and tab 2 is detailed weather. Two circular indicators sit vertically centered on the popup's right edge; mouse-wheel/touchpad vertical scrolling moves between tabs. Tab content transitions vertically in the same direction as the navigation gesture using the shared element-move timing/easing, while the popup geometry itself remains fixed.

- [ ] **Clock hover:** horizontal Clock and the vertical Clock+Date cluster open the dedicated Calendar popup.
- [ ] **Weather tabs:** orbital forecast and detailed weather share one stable popup footprint and switch by wheel or the right-edge dot indicators.
- [ ] **Vertical slide transition:** the two pages move as a clipped vertical stack using the shared element-move motion token; scrolling down advances upward to Details, scrolling up returns downward to Orbit, and the popup body itself never resizes or translates.
- [ ] Preserve Alis DateTime/Weather service ownership, units, refresh behavior, location/error states and Material theme behavior.
- [ ] Calendar and Weather layouts remain usable across supported screen sizes/scales and do not depend on screenshot-specific dimensions.

### G. Material-only Global Theme cleanup — P0

Material is the **single canonical Global Theme** for Alis 1.0.

**Source-complete on current `dev`:**

- [x] Public Settings/Welcome/GlobalActions Global Theme selection is Material-only.
- [x] `Appearance.globalStyle` is runtime-clamped to `material`; legacy persisted values cannot reactivate alternate shell-wide renderers.
- [x] Retired Bar renderer families and Dock style families are absent from the live runtime graph; Dock compatibility converges to `panel`.
- [x] Legacy UI locale/style compatibility is normalization-only rather than an alternate runtime path.
- [x] Material-only regression guards cover Settings, global-style routing and public documentation contracts.

**Release acceptance still open:**

- [ ] Run a final active-tree residue audit and remove any remaining live non-Material Global Theme branch/asset/doc reference that is not required by a current supported caller or migration shim.
- [ ] Validate Material rendering across Bar, Screen Edge, connected popups, Sidebars, Overview, Settings and Waffle on the exact release candidate.

### H. Legacy/compatibility cleanup — P1

- [ ] Remove active reads/routes for retired renderer/style families when they no longer serve migration compatibility.
- [ ] Keep compatibility shims only where a current supported caller still needs the type/config name.
- [ ] Do not restore retired Pill/Mascot runtime behavior, historical Dock renderer families, Orbit/workspace experiments, removed Global Themes or similar dead presentation systems.
- [ ] Old persisted values must degrade safely to the supported v1.0 behavior instead of resurrecting removed renderers or themes.
- [ ] Keep Waffle separate and supported.


## 6. v1.0 hardening tasks — P1

- [ ] Audit every `StyledPopup` consumer for connector, anchor, focus and mask consistency.
- [ ] Test bottom-right and vertical-bar anchors explicitly; these expose clipping/placement errors easily.
- [ ] Remove fractional-scale seams and one-pixel antialiasing gaps without per-popup magic numbers.
- [ ] Confirm Settings remains responsive while visiting all heavy pages repeatedly.
- [ ] Confirm no `Type ... unavailable` failures through Sidebar Left/Right, Compact Sidebar, Overview, Waffle and Settings routes.
- [ ] Verify fullscreen transparent surfaces never land on the wrong output.
- [ ] Verify suspend/resume, lock/unlock and output hotplug do not leave stale popup/focus state.
- [ ] Audit packaging/runtime dependencies required by media visualization, Thinkfan and weather.
- [ ] Search the active tree for removed Global Theme names and eliminate live references outside intentional migration code/history.
