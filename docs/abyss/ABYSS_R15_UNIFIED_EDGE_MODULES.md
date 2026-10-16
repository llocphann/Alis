# ABYSS-R15 — Unified Screen Edge launchers (candidate)

Canonical scope: [Issue #106](https://github.com/llocphann/Alis/issues/106). This candidate deliberately remains on the feature branch until reviewed on the installed native desktop. Do not merge to `stable` as a side effect.

## Available in this candidate

- **QuickNotes & Timers** is a single new catalog entry (`notesTimers`) which hosts the existing `QuickNotesPopup.qml`. Its Notes, Todo, Timers, pin and keyboard/editor logic remain the original implementations.
- **Notifications & Activities** is a single new catalog entry (`notificationActivity`) which hosts the existing `NotificationCenterPopup.qml` with its existing Notifications/Activity tabs and shared service/history.
- Both entries can be added, dragged and resized on Top/Bottom/Left/Right in **Edit Abyss Layout**. The add flow prevents a second enabled launcher of the same kind.
- Each launcher paints a circular icon by default. Select that module and toggle the icon control to hide just the icon; its bounded physical-edge mouse target persists. The `showIcon` setting is normalized and saved in the existing output profile.
- Existing ScreenCorners are not deleted. For an output with an enabled replacement, its *matching* legacy corner trigger is suppressed; disabling or removing the replacement restores that legacy entry. Other outputs and the `stable` branch remain unchanged.
- Notification toasts and older unrelated Bar timer indicator are left untouched. The new components do **not** create duplicate providers, timers or notification stores.

## Opt-in migration; do not silently rewrite owner data

1. Start Edit Abyss Layout on the target output.
2. Add `QuickNotes & Timers` and/or `Notifications & Activities` to the selected edge. Position and scale each in the usual editor; optionally hide its icon.
3. Commit via **Done**, never by modifying the notes/notifications stores. The existing legacy corner remains the fallback if that launcher is removed or disabled.
4. To roll back, disable or remove the new module, then save. This does not discard QuickNotes/Todo/Timers/history or earlier configuration values.

This is a **manual opt-in migration candidate**, not a fully automatic legacy-anchor migration. In particular existing configured module layouts are never overwritten on opening the editor. Automatic import of old corner geometry is **not yet implemented**.

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
- default and manually added layouts; Editor Undo/Done, disable/remove rollback
- Notes Markdown reading/editing, Todo, pin/focus/Escape, timers while switching tabs
- Notification unread/history, Activity tab, explicit hotkeys and uninterrupted transient toasts; no extra marking-read on layout preview
- hover transfer and popup continuity without pop-in, premature close, stutter or duplicate processes
- before/after owner screenshots, native input events and installed source SHA

**Status:** Source candidate / awaiting tests and installed-disk owner acceptance. Keep Issue #106 open; do not mark verified.
