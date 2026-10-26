> Historical snapshot archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

# Unified Surface — Fresh Chat Handoff

Use this file only as an execution handoff for continuing Alis surface work in a new chat. Historical Abyss experiments live in `docs/UNIFIED_SURFACE_RESEARCH.md`; the active contracts are this file, `README.md`, `docs/PERIMETER.md` and `docs/SHELL_SURFACE_CONTRACTS.md`.

## Phase status — Abyss integration complete

The migration itself is closed. Use `docs/ABYSS_INTEGRATION_COMPLETE.md` as the
compact production baseline. Future work belongs to optimization, bug fixing and
refinement unless new runtime evidence disproves an architectural invariant.

## First actions

1. Refetch current `dev` before editing anything. Concurrent Dashboard / media / surface work may land between turns.
2. Read `README.md` §1.1 and §2.1.
3. Do not merge `stable` unless the maintainer explicitly asks.
4. Run source-contract review against the exact current SHA before creating a commit.
5. Runtime-sensitive geometry is not complete until the maintainer validates it in the real Niri/Quickshell session.

## Failed-fix rule — no patch stacking

If runtime evidence, regression tests or maintainer acceptance show that a fix did not solve the defect, revert that ineffective change before trying another implementation.

- Prefer a dedicated revert commit.
- If concurrent unrelated work makes a whole-commit revert unsafe, surgically revert only the failed change set in its own commit.
- Re-establish the last known-good baseline, identify the root cause, then use a materially different approach.
- Do not keep a disproven workaround and add another compensating patch on top.

## Frozen physical perimeter

The physical Screen Edge / normal ii Bar perimeter is locked.

- `modules/screenCorners/ScreenEdges.qml` owns one full-output `FrameWindow`.
- The healthy painter is one texture-free `ScreenEdgeField` analytic SDF: the full output minus one rounded workspace hole, with inward elevation composed in the same pass.
- The historical odd-even `ShapePath` with exactly four circular `PathArc` corners and its `MultiEffect` shadow remain only inside a lazy `ShaderEffect.Error` fallback and are not constructed on the healthy path.
- Normal ii Bar ownership changes only the matching inner-frame inset to Bar/VerticalBar thickness.
- `appearance.screenEdge.radius` through `PerimeterTokens.frameRadius` is the only physical corner-radius control and drives both the analytic field and its reference fallback.
- Horizontal/vertical Bar and the painted Screen Edge frame remain mapped across fullscreen; compositor stacking owns coverage.
- Waffle is a separate supported panel family and must not be changed as a side effect of ii perimeter work.

Do not add Bar-local or ScreenCorner-local `RoundCorner`, `PathArc`, wedge, contact rectangle, shadow band, fake rounded-screen overlay or a second healthy-path physical-edge renderer.

## Current production connected-surface architecture

### ii Bar popups

```text
StyledPopup.qml
  -> ConnectedSurfaceGeometry.qml
  -> ConnectedSurfaceRevealClip.qml
  -> ConnectedSurfaceAbyssFrame.qml
       -> ConnectedSurfaceAbyssField.qml
       -> AbyssField.frag.qsb
  -> ConnectedSurfaceContentHost.qml
  -> ConnectedSurfaceBodyMask.qml
  -> PerimeterTokens.qml
```

The accepted split-composition Abyss path keeps Bar/Screen Edge owner records in SDF math while clipping Overlay paint/shadow/input at the real owner boundary.

### Feature-owned Screen Edge bodies

`ConnectedSurfaceAbyssEdgeSurface.qml` adapts an existing body into the same Abyss field.

Current consumers:

- Left/Right Sidebar via `SidebarHost.qml`;
- Overview Dashboard;
- Settings Overlay;
- Settings Focus.

Dashboard-owned Applications Search shares the Dashboard Abyss field rather than creating an independent wedge/contact renderer.

### Direct square-seam consumers

Current Search/OSK/Waffle compatibility paths do not paint auxiliary endpoint wedges.

- standalone Search: square joined body edge;
- OSK: square top/bottom joined body edge;
- Waffle: shared `ConnectedSurfaceFrame` / `ConnectedSurfaceMask`, with connector paint disabled where required.

## Retired geometry — do not restore

The following are intentionally absent from runtime QML and exports:

- `ConnectedSurfaceJoinFlares`;
- `PerimeterCornerShadow`;
- common `RoundCorner`;
- `joinFlareRadius`;
- `joinFlareCrossScale`;
- fake-screen-rounding configuration and paint.

The source contracts should reject any reintroduction of those symbols.

## Sidebar close contract

`SidebarHost.qml` must use `ConnectedSurfaceAbyssEdgeSurface` and a single slide translation.

`hiddenTranslateDistance` must move the resident Sidebar body past the complete native host plus Abyss/shadow overflow on both left and right edges. During the close tail the field may remain resident, but neither body, weld nor shadow may leave a visible Screen Edge sliver.

Do not reintroduce:

- `sidebarBridgeGeometry`;
- `ConnectedSurfaceConnector` in SidebarHost;
- endpoint flare helpers;
- a second translation applied to the field.

## Dashboard / Settings contact contract

Dashboard and Settings use `ConnectedSurfaceAbyssEdgeSurface` at the bottom owner.

- The real Screen Edge/Bar owner thickness is passed into the adapter.
- The local connected body is transparent where the Abyss field owns fill/shadow.
- Dashboard Search shares Dashboard ownership.
- No full-overlay endpoint wedge may be drawn beside a centered Settings/Dashboard body.

## Source gates to keep aligned

At minimum, review these whenever connected-surface ownership changes:

- `scripts/test-abyss-production-surface-contract.py`
- `scripts/test-shell-surface-contracts.py`
- `scripts/test-perimeter-contracts.sh`
- `scripts/test-perimeter-source-contracts.sh`
- `scripts/test-perimeter-retirement-contract.sh`
- `scripts/test-perimeter-route-contracts.sh`
- `scripts/test-perimeter-compatibility-placement-contract.sh`
- `scripts/test-material-only-global-style-contract.py`

The runtime-QML retirement sweep must continue to reject the retired wedge/corner family.

## Live acceptance still required

Run the canonical local validator first:

```sh
bash scripts/validate-maintainer-local.sh
```

Then validate in the real Niri session:

1. Popup contact and hover/retract from representative Bar modules.
2. Left Sidebar open/close and Right Sidebar open/close; confirm no residual Screen Edge sliver after close.
3. Sidebar custom width and both default/compact right-sidebar content.
4. Dashboard open/retract and Dashboard <-> Applications Search transition.
5. Settings Overlay and Settings Focus bottom contact.
6. OSK top/bottom snap with no auxiliary wedge artifact.
7. top/bottom/left/right Bar placement where applicable.
8. fractional scaling and multi-output ownership.
9. fullscreen enter/exit without blank or stranded Bar/Screen Edge content.

Do not claim runtime success from source inspection alone.

## Broader unfinished v1.0 work

Use `to-do/cloud-bot/ABYSS.md` and `to-do/cloud-bot/RELEASE.md` as current unfinished-work lists; `docs/VALIDATION.md` defines the canonical local checks and separately labeled maintainer-only live acceptance. In particular, boot integrity, Screen Edge/Bar lifecycle, media/music, Dashboard/Overview, Calendar/Weather, ThinkFan/TLP and Material-only residue still require their listed source or live acceptance.

Remove completed items from the active handoff instead of accumulating historical checked tasks.
