> Historical snapshot archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

# Abyss Integration — Completion Notes

Status: **integration phase complete** on `dev`.

This file is the compact handoff for future Alis work. The Abyss migration is
no longer an open architecture task. Future visual/perimeter defects should be
treated as ordinary optimization/refinement/bug-fix work unless runtime evidence
proves one of the contracts below is wrong.

## What is now authoritative

### 1. ii Bar popups

`StyledPopup.qml` is the normal ii Bar popup entry point:

```text
StyledPopup.qml
  -> ConnectedSurfaceGeometry.qml
  -> ConnectedSurfaceRevealClip.qml
  -> ConnectedSurfaceAbyssFrame.qml
       -> ConnectedSurfaceAbyssField.qml
       -> AbyssField.frag.qsb
  -> ConnectedSurfaceContentHost.qml
  -> ConnectedSurfaceBodyMask.qml
```

The production shader source/QSB are byte-identical to the locked G1/G2 assets.
Do not rebuild or casually replace them while fixing unrelated UI behavior.

### 2. Feature-owned Screen Edge bodies

`ConnectedSurfaceAbyssEdgeSurface.qml` adapts existing feature bodies to the
same Abyss field without introducing a second popup framework.

Current consumers:

- Sidebar Left/Right;
- Dock (top/bottom/left/right);
- Dashboard;
- Dashboard-owned Applications Search through the Dashboard field;
- Settings Overlay;
- Settings Focus.

Embedded Search must not render a second Abyss field on top of Dashboard.

### 3. Geometry ownership

- `ScreenEdges.qml` is the only physical Screen Edge renderer.
- Normal ii Bar/VerticalBar physical perimeter ownership remains part of that
  same locked frame.
- Connected Overlay surfaces keep owner rectangles only for SDF distance math.
- Overlay field/shadow/input are clipped at the real external-owner boundary.
- Tangent welding is **SDF-only**; content/input/shadow stay on the real inner
  Screen Edge boundary.
- `abyssFuseDepth = 30` and `abyssWeldDepth = 3` are validated production
  morphology constants. Do not change them as a cosmetic tweak without a new
  deliberate visual validation pass.
- Dormant tangent owner records must remain zero-sized unless the corresponding
  tangent edge is actually joined.

### 4. Motion and input

- Surface motion remains **slide-only** through `SurfaceMotion`.
- Do not add scale/fade/morph stages to solve geometry defects.
- `ConnectedSurfaceBodyMask` owns ii popup input; transparent full-output
  Overlay regions and shader-only fillets must not steal pointer input.
- Sidebar close translation must clear the whole native host plus Abyss/shadow
  overflow so no Screen Edge sliver remains after close.
- Sidebar Overlay placement uses `ExclusionMode.Ignore` so Screen Edge
  reservation is not applied twice.

### 5. Dashboard/Search stacking

The Abyss field is the connected plate/background. Dashboard content must render
above it. Dashboard-owned Applications Search shares that same field; do not
create an independent edge/contact renderer in `SearchWidget`.

### 6. Shadow ownership

- Physical Screen Edge, ii Bar `StyledPopup`, Dock, Sidebar and Dashboard use
  `appearance.screenEdge.physicalShadow` and Material `m3shadow` ink.
- Owner clipping must prevent connected-surface shadow from painting over
  Bar/Screen Edge pixels.
- Settings/OSK currently retain their older connected-body shadow owner.

### 7. Retired geometry

Do **not** restore these old patch families:

- `ConnectedSurfaceJoinFlares`;
- `PerimeterCornerShadow`;
- common `RoundCorner` wedge renderer;
- fake Screen Corner rounding paint;
- `joinFlareRadius` / `joinFlareCrossScale`;
- per-corner helper rectangles/wedges;
- same-layer helper-window welding.

The G1/G2 PoC under `scripts/abyss-corner-poc/` is evidence/test infrastructure,
not runtime architecture.

### 8. Waffle

Waffle remains a separate supported panel family. Do not migrate, delete or
"clean up" Waffle as a side effect of normal ii optimization work unless the
maintainer explicitly asks.

## Required checks before changing connected surfaces

1. Refetch current `dev`; concurrent work is common.
2. Read `README.md` §1.1 and `docs/PERIMETER.md`.
3. Inspect the caller and consumer before editing a shared primitive.
4. Never stack a new workaround on top of a fix that runtime evidence disproved;
   revert/surgically remove the failed change first.
5. Keep commits focused and never force-push/rebase shared `dev`.
6. Run the relevant static contracts.
7. For installed runtime parity, run:

```sh
scripts/abyss-corner-poc/verify-production-runtime.sh
```

8. For broad local validation, use:

```sh
bash scripts/validate-maintainer-local.sh
```

9. Runtime-sensitive geometry is accepted only after testing in the real
   Niri/Quickshell session.

## Phase transition

The Abyss integration/migration phase is complete. From this point forward:

- optimize existing code paths;
- fix concrete regressions;
- refine animation, layout, performance and interaction behavior;
- remove genuinely unreachable/stale code only after proving it has no active
  consumer;
- prefer simplifying an existing abstraction over adding another geometry layer.

Do not reopen the Abyss migration itself merely because a feature needs normal
polish.
