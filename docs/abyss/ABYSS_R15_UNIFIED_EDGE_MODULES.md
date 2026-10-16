# ABYSS-R15 — Unified Screen Edge launchers (dev)

Canonical scope: [Issue #106](https://github.com/llocphann/Alis/issues/106). Feature code was merged into `dev` by [PR #109](https://github.com/llocphann/Alis/pull/109), commit `900f972c`. The installed owner desktop still requires `alis update` to fetch/sync `dev`, and native UX acceptance remains open. Do not merge to `stable` as a side effect.

## Available in this candidate

- **QuickNotes & Timers** is a single new catalog entry (`notesTimers`) which hosts the existing `QuickNotesPopup.qml`. Its Notes, Todo, Timers, pin and keyboard/editor logic remain the original implementations.
- **Notifications & Activities** is a single new catalog entry (`notificationActivity`) which hosts the existing `NotificationCenterPopup.qml` with its existing Notifications/Activity tabs and shared service/history.
- Both entries can be added, dragged and resized on Top/Bottom/Left/Right in **Edit Abyss Layout**. The add flow prevents a second enabled launcher of the same kind.
- A live launcher always paints a circular icon and only the icon receives hover. **Settings → Modules → Show icon** is the same access-mode switch as **Module Behavior**: off unmounts that module popup/input and restores the legacy corner Edgebar; on remounts the saved icon module. Earlier per-output `showIcon` values remain in stored profiles without creating invisible hover sources.
- Existing ScreenCorners are not deleted. For an output with an enabled replacement, its *matching* legacy corner trigger is suppressed; disabling or removing the replacement restores that legacy entry. Other outputs and the `stable` branch remain unchanged.
- Notification toasts and older unrelated Bar timer indicator are left untouched. The new components do **not** create duplicate providers, timers or notification stores.

## Independent access modes in the Modules subtab

Go to **Alis Settings → Abyss → Modules & Behavior → Modules** (Bar modules).
Configure each feature with its single canonical **Show icon** switch:

- **Show Quick Notes & Timers icon**: On = **Module Icon**; Off = **Edgebar Hover**.
- **Show Notifications & Activities icon**: On = **Module Icon**; Off = **Edgebar Hover**.

There are **no duplicate per-feature mode selectors in Behavior & clock**.
Settings search for **Quick Notes & Notifications access modes** navigates
to **Modules**, not Behavior & clock. The choices persist immediately and
can be mixed independently on one output or across multiple outputs.

When a switch is on, the visible circular icon is the only hover source
for that feature, with no name tooltip. When off, that feature's module
popup/input is unmounted and its former corner Edgebar Hover returns.
A previously stored per-output module position is retained for switching
back. Earlier `iconVisibility.hide` profiles are interpreted as Edgebar
only until a new explicit mode is set. No separate invisible hover module
remains. Runtime corner eligibility still respects fullscreen and native
Niri Overview corner ownership.

**Edit Abyss Layout** controls physical placement/size/enable/remove only,
not these access-mode switches.

## Exclusive hover ownership across Bar lifecycle

When either feature selects **Module Icon** (or enables its Settings **Show icon**
switch), the legacy ScreenCorners hover window is **not eligible to load**
for that feature for as long as the Abyss panel family is active. This
suppression is derived directly from the chosen access mode, and **never**
depends on transient `GlobalStates.barOpen`, auto-hide/reveal, module
availability, output Bar inclusion or popup animation state.

- **Quick Notes → Module Icon:** bottom-left legacy dwell popup stops receiving
  hover entirely; only the placed Notes/Timers icon can open Quick Notes.
- **Notifications → Module Icon:** bottom-right legacy dwell popup and its
  legacy host are disabled; only the Notifications/Activities icon owns hover.
- **Edgebar Hover:** only the selected feature's legacy corner popup returns;
  the corresponding module icon/popup is unmounted.
- Independent mixed modes work; the classic **ii** panel family keeps its
  original ScreenCorners interactions and is unaffected by Abyss settings.

A secondary `hoverAllowed` guard on the mature legacy Quick Notes popup
revokes mouse-hover activation in the same binding turn as the corner Loader
deactivates. Existing editor focus and data stores remain unchanged. Confirm
with actual pointer hover on both the icon and physical bottom corner after
switching, including while the Bar auto-hides.

## Window padding and local Edge paint

Quick Notes and Notification launcher icons are small localized Edge sources,
not full-width/full-height window reservations. Their presence must **not**
inflate the base inset/padding of any Edge, even in the default
`edgeWidthAffectsModules` and `singleModuleExpansion=edge` settings. Each
icon still has a bounded local liquid-surface bump, independent of corner
padding or other Bar modules. Actual large modules retain their previous
full-Edge reservation policy; an intentionally different configured thickness
for an Edge is preserved rather than forcibly equalized.

## Automatic placement with reversible per-output migration

1. The first startup with the converted code automatically **adds both launchers in memory** at the bottom left/right of every applicable output, even if the user already has a custom Edge layout. No original serialized placement entry is deleted.
2. Open Edit Abyss Layout to adjust either module to any Edge, change its size or remove it. **Done** persists the new layout and a per-output migration marker. Use the **Show icon** controls in Alis Settings for switching between the Module Icon and legacy Edgebar. Cancel retains the original profile and safe derived defaults.
3. If a module is removed or disabled and **Done** is pressed, the saved per-output/global migration marker ensures that the same module will **not** be automatically recreated after restarting. Its original corner hover fallback returns for that output.
4. To roll back to the old behavior, explicitly disable or remove both unified modules and save; no Notes/Todo/Timer/Notification/Activity stores are rewritten. Do not delete the user profile.

This is an **automatic default placement**, not a destructive rewriting of historical corner coordinates. New modules are initially seeded at the respective bottom corner; the owner can reposition them in the editor. Original corner size, style and history settings remain intact for fallback. Exact previous physical anchor geometry is **not imported**; output profiles and rollback remain explicitly controlled by the user.

## Owner-reported fixes (popup rims, Settings icons and Edge hover)

- **Popup rim:** when a Quick Notes / Notifications popup overlaps its own local Edge launcher, skip only that same-kind mini-surface during clearance; unrelated module surfaces are still respected. This prevents the self-inflated 48px+ attachment clearance that exaggerated the inner border near screen corners.
- **Settings icon toggles:** The now-deprecated `abyss.modules.iconVisibility` `inherit/show/hide` values are retained for old-profile migration only. Settings switches now write `abyss.modules.notesTimersMode` and `notificationActivityMode` directly, synchronized with Module Behavior. Hiding an icon switches the feature to its *real* Edgebar popup, not a visually hidden module.
- **Module Icon hover:** The two unified popup sources opt into `strictSourceHover`, recognizing only the painted icon's exact MouseArea. Their compositor input masks have no iconless fallback. Legacy corner hover is handled separately whenever the corresponding feature's mode is Edgebar. Other mature popup hover behavior remains unchanged.

## Checks and review gates

Source assertion checks and an additional Node placement/profile regression have been added under `scripts/test-abyss-unified-edge-modules*`. Locally run:

```sh
python3 scripts/test-abyss-unified-edge-modules-contract.py
node scripts/test-abyss-unified-edge-modules.mjs
python3 scripts/test-abyss-module-layout.py
node scripts/test-abyss-full-size-modules.mjs
node scripts/test-abyss-multi-selection.mjs
```

A source contract cannot prove native Quickshell/Niri behavior. **No PASS claim is made here for unrun tests.** Owner validation is still required for:

- 4 edges and all four mixed Quick Notes/Notifications access mode combinations; Show icon toggle synchronization with Module Behavior, icon-only hover, no name tooltip, no invisible module hitboxes, 0px/nonzero widths, width-affects-modules, scaled and rotated modules
- compact/fractional scaling, multiple outputs and disconnected/reconnected screens; no doubled corner or phantom input masks
- automatic defaults on legacy configured/unconfigured and multiple output layouts; mode change in Alis Settings independently of Editor Undo/Done; layout Editor Undo/Done, disable/remove rollback
- Notes Markdown reading/editing, Todo, pin/focus/Escape, timers while switching tabs
- Notification unread/history, Activity tab, explicit hotkeys and uninterrupted transient toasts; no extra marking-read on layout preview
- unchanged Window Padding on all four Edges when launcher icons are added/removed, changed to Edgebar Hover, or moved, plus hover transfer and popup continuity without pop-in, premature close, stutter or duplicate processes
- before/after owner screenshots, native input events and installed source SHA

**Status:** Implemented in `dev` (focused ABYSS-R15 GitHub Actions check passed). Broad validator remains red on other environment/legacy checks. Native desktop/Owner acceptance is pending. Keep Issue #106 open; do not mark verified.
