# ABYSS-R15 — Unified Screen Edge launchers (dev)

Canonical scope: [Issue #106](https://github.com/llocphann/Alis/issues/106). Feature code was merged into `dev` by [PR #109](https://github.com/llocphann/Alis/pull/109), commit `900f972c`. The installed owner desktop still requires `alis update` to fetch/sync `dev`, and native UX acceptance remains open. Do not merge to `stable` as a side effect.

## Available in this candidate

- **QuickNotes & Timers** is a single new catalog entry (`notesTimers`) which hosts the existing `QuickNotesPopup.qml`. Its Notes, Todo, Timers, pin and keyboard/editor logic remain the original implementations.
- **Notifications & Activities** is a single new catalog entry (`notificationActivity`) which hosts the existing `NotificationCenterPopup.qml` with its existing Notifications/Activity tabs and shared service/history.
- Both entries can be added, dragged and resized on Top/Bottom/Left/Right in **Edit Abyss Layout**. The add flow prevents a second enabled launcher of the same kind.
- Each launcher paints a circular icon by default. Select that module and toggle the icon control to hide just the icon; its bounded physical-edge mouse target persists. The `showIcon` setting is normalized and saved in the existing output profile.
- Existing ScreenCorners are not deleted. For an output with an enabled replacement, its *matching* legacy corner trigger is suppressed; disabling or removing the replacement restores that legacy entry. Other outputs and the `stable` branch remain unchanged.
- Notification toasts and older unrelated Bar timer indicator are left untouched. The new components do **not** create duplicate providers, timers or notification stores.

## Automatic placement with reversible per-output migration

1. The first startup with the converted code automatically **adds both launchers in memory** at the bottom left/right of every applicable output, even if the user already has a custom Edge layout. No original serialized placement entry is deleted.
2. Open Edit Abyss Layout to adjust either module to any Edge, change its size, hide its circular icon or remove it. **Done** persists the new layout and a per-output migration marker. Cancel retains the original profile and safe derived defaults.
3. If a module is removed or disabled and **Done** is pressed, the saved per-output/global migration marker ensures that the same module will **not** be automatically recreated after restarting. Its original corner hover fallback returns for that output.
4. To roll back to the old behavior, explicitly disable or remove both unified modules and save; no Notes/Todo/Timer/Notification/Activity stores are rewritten. Do not delete the user profile.

This is an **automatic default placement**, not a destructive rewriting of historical corner coordinates. New modules are initially seeded at the respective bottom corner; the owner can reposition them in the editor. Original corner size, style and history settings remain intact for fallback. Exact previous physical anchor geometry is **not imported**; output profiles and rollback remain explicitly controlled by the user.

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

- 4 edges, icon visible/hidden, 0px/nonzero widths, width-affects-modules, scaled and rotated modules
- compact/fractional scaling, multiple outputs and disconnected/reconnected screens; no doubled corner or phantom input masks
- automatic defaults on legacy configured/unconfigured and multiple output layouts; Editor Undo/Done, disable/remove rollback
- Notes Markdown reading/editing, Todo, pin/focus/Escape, timers while switching tabs
- Notification unread/history, Activity tab, explicit hotkeys and uninterrupted transient toasts; no extra marking-read on layout preview
- hover transfer and popup continuity without pop-in, premature close, stutter or duplicate processes
- before/after owner screenshots, native input events and installed source SHA

**Status:** Implemented in `dev` (focused ABYSS-R15 GitHub Actions check passed). Broad validator remains red on other environment/legacy checks. Native desktop/Owner acceptance is pending. Keep Issue #106 open; do not mark verified.
