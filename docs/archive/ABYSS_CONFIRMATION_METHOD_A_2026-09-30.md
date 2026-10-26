# Abyss confirmation — Method A retry (2026-09-30)

> **Status: RETIRED / NOT ACTIVE.** The maintainer tested the Method A
> reintroduction and reported that it had no effect. Reverted at maintainer
> request. This record is historical, not an implementation instruction.

## Source snapshots (Git history)

- [Method A implementation](https://github.com/llocphann/Alis/commit/f502d87541274fd9025f97a6d79daa244c60919a) — `f502d87541274fd9025f97a6d79daa244c60919a`.
- [Active-source-popup anchoring follow-up](https://github.com/llocphann/Alis/commit/73d44691330c2404019b16127b21e562211c5056) — `73d44691330c2404019b16127b21e562211c5056`.
- Active-tree baseline before Method A: `7a64dcdc9919698ec9d385a466145787bbfccbc3`.
- See also [the earlier retirement and detailed design notes](ABYSS_RUNTIME_EXPERIMENTS_2026-09-29.md). The historical commit tree holds the entire QML, JS, shell, and test contents; do not duplicate executable copies in runtime directories.

## What was attempted

- Present Alis-owned close confirmations as native Abyss connected surfaces through `StyledPopup`, the existing `AbyssSurfaceController` popup slots, `AbyssBodyHost`, and Pyramid.
- Resolve live application anchors from System Tray, Bar taskbar, or Dock, refined to prefer a source that already owns an active app hover/popup.
- Keep an existing hover popup nearest the Screen Edge and request the next inward tier for its confirmation.
- When no source popup resolves, use the target output's Screen Edge center, following Volume/Brightness placement.
- Add runtime request queue, action/cancellation semantics, source-loss and output-handoff handling, critical prompt presentation, and targeted regression contracts. Preserve the Waffle and non-Abyss fallback behavior.

## Observed outcome and disposition

On 2026-09-30, the maintainer's live result was: **“không có tác dụng, revert và đưa vào archives.”** No narrower verified root cause is established by this report. Do not describe the former source contracts or synthetic tests as proof that this live experience worked.

The Method A implementation and its two added/modified test families were reverted *forward* on `dev` without rewriting shared history. All 21 paths introduced or modified by the implementation were restored to the pre-Method-A contents or removed if newly added. One independent later change in `modules/abyss/AbyssPerimeter.qml` was deliberately retained: `dialogBody.vacancyRole` forwarding from `liquid.activeDialog?.liquidVacancyRole`.

The archived implementation is retrievable at the exact Git commits linked above. Its 9 newly introduced runtime/test files are intentionally removed from the active tree; the other 12 paths return to their pre-Method-A versions (with the unrelated `dialogBody.vacancyRole` exception). Do not reintroduce this method by copying historic code without first reproducing the observed failure and defining a live Wayland acceptance case.

This attempt did **not** establish generic interception of application-native confirmation dialogs: Alis must not infer private app action semantics merely from a title such as "Quit?".
