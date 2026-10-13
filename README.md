# Alis — v1.0 Release Plan / Development Contract

> This README is the current product and execution contract for completing **Alis 1.0**.
> It intentionally contains only active requirements, release blockers, architecture constraints and validation gates. Historical implementation notes, one-off commit hashes and stale migration narratives belong in Git history / `CHANGELOG.md`, not here.
>
> **Target:** `1.0`  
> **Primary development branch:** `dev`  
> **Stable baseline:** `stable`  
> **Scope refresh:** 2026-09-28
>
> **Current `dev` snapshot (2026-09-28):**
> - The qualified **Rust native workspace is the production backend**. `inir-native`, `inir-inputd`, `inir-mpdd` and `inir-theme` are built/shipped by supported install paths; Python implementations remain an explicit rollback/fail-soft path rather than the default selector.
> - **Material is the only public shell-wide Global Theme**. Legacy persisted theme/style values are migration input only and must normalize to supported Material behavior rather than reactivate retired renderers.
> - **Abyss and Waffle are the public panel families.** Material/`ii` panel values migrate to Abyss; Material remains the shared color/theme system, not a third panel family. Abyss inherits mature content and backends through one output-local liquid surface. Existing ii source is compatibility/reuse input, not permission to restore a public Material panel mode.
> - **Waffle remains a supported independent panel family** and must not be removed or treated as legacy during ii cleanup.
> - Source/contract completion is not the same as release acceptance: runtime-sensitive gates still require the canonical local validator and live Niri/Quickshell checks on the exact candidate SHA.

## 1. Source-of-truth and workflow

Requirement precedence:

1. the maintainer's newest explicit instruction;
2. this README's active v1.0 scope and architecture constraints;
3. the current implementation on `dev`;
4. `stable` only as a behavioral/architectural comparison baseline;
5. older docs, historical notes and retired implementation details.

Working rules:

- **Local and Cloud AI use [GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen) as the only active task tracker.** Deduplicate by stable code, follow the latest owner priorities, then actionable non-deferred features and their related rework/bugs. No task Markdown ledgers.
- Work directly on **`dev`**. Do not create or switch to another branch unless the maintainer explicitly requests it.
- Refetch the latest **`dev`** before every significant audit and immediately before every write/ref update. Use `stable` only when a behavioral comparison is actually needed; never merge into or mutate `stable` as part of normal development.
- Re-read the current target file and its caller/consumer before changing architecture.
- Do **not** create a pull request unless explicitly requested.
- Do **not** depend on GitHub Actions for the current development cycle; the maintainer performs the authoritative local test pass.
- Keep commits focused and fix forward. Do not rewrite shared history.
- **Do not stack patches on top of a failed fix.** If local/runtime tests or maintainer evidence show that a fix commit did not solve the reported defect, revert that ineffective change before trying another implementation. Prefer a dedicated revert commit; if concurrent work makes a whole-commit revert unsafe, surgically revert the exact failed change set in its own commit. Re-establish the last known-good baseline, re-investigate the root cause, then implement a different approach. Never retain a disproven workaround merely as a base for another compensating patch.
- Canonical local validator: `bash scripts/validate-maintainer-local.sh`.
- A task is not release-complete merely because code exists. Runtime-sensitive items remain open until locally validated on the intended desktop environment.
- **Settings copy stays terse.** Visible helper/description text should be only a few words or one short clause; never put paragraph-length explanation on the main Settings surface. Put necessary detail in a tooltip or documentation instead.
- **Settings base surface has one owner.** In Material, paint `Appearance.colors.colLayer0` exactly once for each Settings surface, preserving its global transparency. Keep inner page/content containers transparent; do not repaint, locally alpha-tint, or stack the structural fill.

### 1.1 Fresh-chat handoff — read before editing perimeter/UI geometry

This section is the **maintainer handoff for new chat sessions**. Read it before touching Screen Edge, Bar, popup, Sidebar, Dashboard, Settings overlay or any shared perimeter primitive. If another section appears to conflict with this handoff, the maintainer's newest explicit instruction wins.

**Maintainer workflow lock (2026-09-25):** Alis development is `dev`-only. Do not create feature/fix branches and do not open pull requests unless the maintainer explicitly asks for them. Refetch and re-read the latest `dev` target before every write, then commit focused changes directly to `dev`. `stable` is comparison-only unless the maintainer explicitly changes that rule.

**Failed-fix rule — no patch stacking:** when a proposed fix is shown by runtime evidence, regression testing or maintainer acceptance to be ineffective, revert that fix before attempting a replacement. Do not layer a second workaround over the failed approach. Restore the last known-good behavior, identify why the previous approach failed, then implement a materially different root-cause fix. Preserve concurrent unrelated work by reverting only the failed change set when necessary.

**2026-09-28 scope override:** The maintainer explicitly authorized the Abyss Screen Edge/Bar/popup rework. The historical ii geometry locks below apply to preserved ii sources, not the new Abyss field. Abyss keeps a thick, flat resting edge; optional waves, transparency and blur add presentation without replacing mature content. With these effects off, preserve the old Material layout. Waffle remains independent. Read §11–12 for current priorities.

**Frozen / do-not-touch unless the maintainer explicitly asks:**

- **Physical Screen Edge geometry is locked.** Do not redesign, refactor or "clean up" `modules/screenCorners/ScreenEdges.qml` while working on Popup/Sidebar/Dashboard. The accepted model is one full-screen `FrameWindow` whose primary painter is the texture-free `ScreenEdgeField` analytic rounded-workspace SDF, plus transparent reservation windows. The former odd-even `ShapePath` / four-`PathArc` / `MultiEffect` renderer is retained only as a lazy `ShaderEffect.Error` fail-safe; it is not constructed on the healthy path.
- **Normal ii Bar/VerticalBar perimeter geometry is locked together with Screen Edge.** Do not add Bar-local `RoundCorner`, `PathArc`, rectangle, wedge, contact patch, shadow band or fallback geometry. Bar position top/bottom/left/right is represented only by changing the matching inner-frame inset to Bar/VerticalBar thickness inside the existing Screen Edge frame.
- The only approved curvature control for that physical perimeter is `appearance.screenEdge.radius` through `PerimeterTokens.frameRadius` (default **25px**, supported range **0–96px**).
- `appearance.screenEdge.physicalShadow` is the public connected-edge depth control and is shared by the physical frame, ii Bar `StyledPopup`, Dock, Sidebar and Dashboard. The older `appearance.screenEdge.shadow` key remains only for Settings/OSK compatibility paths.
- Auto-hide behavior is also frozen for current geometry work: when ii Bar auto-hide is enabled, Bar relinquishes physical-edge ownership back to `ScreenEdges.qml`. Do not reintroduce `autoHideScreenEdge` or another Bar-local physical edge.
- Waffle is a separate supported panel family. Do not change Waffle geometry as a side effect of ii perimeter work.

**Connected-surface policy — legacy round-wedge geometry retired:**

- **Physical Screen Edge geometry remains locked** to the single full-screen rounded workspace opening below. `ScreenEdgeField` is the normal painter; the historical odd-even Shape/MultiEffect renderer is error fallback only.
- ii Bar popups keep the production iRiS SDF union through `StyledPopup`.
- Sidebar, Dashboard and Settings use `ConnectedSurfaceIrisEdgeSurface`, which adapts their real body rectangle to the same iRiS field without a standalone wedge/corner helper.
- Dashboard-owned Applications Search inherits the Dashboard `ConnectedSurfaceIrisEdgeSurface`; the embedded `SearchWidget` must not paint a second field. Dock also uses `ConnectedSurfaceIrisEdgeSurface` on top/bottom/left/right so its body is one iRiS-connected block with Screen Edge. OSK, standalone/non-cutover Search and current Waffle bodies keep direct square joined edges without auxiliary endpoint wedges.
- `ConnectedSurfaceJoinFlares`, `PerimeterCornerShadow`, common `RoundCorner`, fake screen-rounding paint and the `joinFlare*` token family are retired.
- Sidebar close translation must clear the complete native left/right host plus iRiS/shadow overflow so no visible sliver survives at Screen Edge.
- Runtime-sensitive geometry remains open until the maintainer validates left/right/top/bottom and fractional-scale behavior in the real Niri session.

**Known-good physical perimeter invariants to preserve during all future popup work:**

```text
ScreenEdges.qml
└── FrameWindow (full output, ExclusionMode.Ignore)
    ├── ScreenEdgeField (primary, texture-free analytic SDF)
    │   └── one rounded inner workspace hole + inward elevation
    └── Loader (ShaderEffect.Error only)
        └── legacy ShapePath OddEvenFill + 4 PathArc + MultiEffect fallback

normal ii Bar:
top/bottom  -> owned inner inset = Appearance.sizes.barHeight
left/right  -> owned inner inset = Appearance.sizes.verticalBarWidth

other sides -> inner inset = Screen Edge thickness
radius      -> PerimeterTokens.frameRadius
```

**Fresh-session procedure before a perimeter edit:**

1. Read this section and §2.1 completely.
2. Refetch current `dev` and re-read the exact target file plus its consumers immediately before writing.
3. Treat `SCREEN-EDGE-GEOMETRY-LOCK` and `BAR-SCREEN-EDGE-CORNER-LOCK` as hard guards.
4. For ii Popup work, inspect the iRiS frame/field/body-mask path. For Sidebar/Dashboard/Settings inspect `ConnectedSurfaceIrisEdgeSurface`; Dashboard-owned Applications Search shares that Dashboard field, while standalone Search/OSK/Waffle preserve direct square attachment unless explicitly migrated. Avoid editing locked physical perimeter files.
5. Update `scripts/test-shell-surface-contracts.py` whenever ownership or geometry contracts change intentionally.
6. Do not claim runtime success until the maintainer has run `inir update` / `inir restart` and visually validated the result.

### 1.2 iRiS integration phase status

The iRiS migration is complete and is now the production baseline. Before any
future perimeter/connected-surface optimization, read
[the archived migration notes](docs/archive/surfaces/IRIS_INTEGRATION_COMPLETE.md). New work should focus on optimization,
bug fixing and refinement rather than reopening the migration.

Optimization research is centralized under [docs/optimization](docs/optimization/README.md); pending implementation is tracked in [GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen). Superseded documents are indexed in [the archive](docs/archive/README.md).

**Fullscreen Bar lifecycle lock (maintainer-approved 2026-09-19):**

- Horizontal and vertical ii Bar `PanelWindow` surfaces must remain **mapped and updating while a client is fullscreen**. Do not gate Bar `visible`, `updatesEnabled`, Loader lifetime or content visibility on `GameMode.hasFullscreenOnOutput()`.
- Niri/compositor stacking naturally covers Top-layer Bar surfaces during fullscreen. Explicitly unmapping/remapping the Bar caused a confirmed regression where Bar contents stayed blank after leaving fullscreen until Quickshell was reloaded.
- The painted Screen Edge `FrameWindow` must also remain mapped and updating across fullscreen. It shares the same Top-layer stacking domain as the Bar; destroying/recreating only the frame can remap the Bar-thick physical perimeter above `BarContent` after fullscreen exits. Niri already renders focused fullscreen clients above Top-layer surfaces.
- The four transparent Screen Edge `ReservationWindow` surfaces may still unmap during fullscreen to release their exclusive work-area reservation. This reservation lifecycle must remain separate from the persistent painted frame lifecycle.



## 2. v1.0 product direction

Alis remains a Quickshell desktop shell built on the existing iNiR architecture. The v1.0 priority is **UI/UX quality without throwing away working iNiR behavior**.

Required direction:

- preserve existing iNiR services, state, routing, popup contents and proven interaction behavior;
- use **Caelestia as the visual/composition reference** for connected edge surfaces;
- make popups appear to grow/morph from their real source surface instead of looking like detached floating cards;
- keep keyboard focus, Escape close, outside-click close, hover transfer, multi-output ownership and compositor behavior intact;
- prefer shared fixes in existing abstractions over per-popup forks;
- **do not build a second popup framework**;
- Niri remains the primary compositor target; preserve existing Hyprland compatibility;
- Waffle remains a supported separate panel family and must not be removed as part of ii/perimeter cleanup;
- **Material is the only supported Global Theme for v1.0.** All other Global Theme families, selectors, runtime branches and stale compatibility paths must be removed unless a narrow migration shim is required only to normalize old persisted values to Material.

Retired per-component renderer/style experiments must not be revived merely to preserve obsolete configuration values.

### 2.1 Locked ownership contract — single Caelestia-style inverted frame

The maintainer requires the physical Screen Edge corners to match Caelestia without painted edge/corner patches, wedges or overlay geometry.

**Four-corner geometry lock (maintainer-approved 2026-09-19):** the live-validated inverted-frame silhouette remains the canonical visual reference for Alis. The maintainer subsequently approved one controlled degree of freedom: `appearance.screenEdge.radius` may change the radius of that same quarter-circle geometry (default **25px**, range **0–96px**). The healthy renderer now expresses that exact rounded workspace opening analytically in `ScreenEdgeField`; the historical odd-even `ShapePath` with four circular `PathArc` corners is retained as the lazy shader-error reference/fallback. Future Bar, popup, reservation, scaling, refactor or compositor work must preserve the same concentric placement and circular-corner silhouette. If a later change deforms, offsets, double-rounds or adds a second physical painter, restore the locked `ScreenEdges.qml` model rather than compensating elsewhere.

**Bar + Screen Edge corner lock (maintainer-approved 2026-09-19):** the current top/bottom/left/right normal ii Bar endpoint corners and the four Screen Edge corners are one canonical perimeter geometry. The Bar is not allowed to own a second corner renderer. Its owned edge only changes the corresponding inner-frame inset from Screen Edge thickness to Bar/VerticalBar body thickness; the same `PerimeterTokens.frameRadius` drives the analytic rounded-workspace SDF and its four-`PathArc` error fallback. Future work must restore this exact model if the Bar or Screen Edge corners regress. Only the existing radius setting may intentionally change their curvature.


- **Normal Bar mode owns only the Bar body.** Horizontal and vertical Bar runtimes must not paint `roundDecorators`, Screen Edge contact rectangles, Bar-local Screen Edge fallback bands, physical-edge shadow rectangles, `RoundCorner` wedges, or any synthetic perimeter extension outside the body.
- **`ScreenEdges.qml` is the only physical Screen Edge renderer.** Each output has exactly one painted full-screen frame surface.
- The healthy frame painter is one analytic SDF: the full output minus one rounded inner workspace rectangle. This preserves the isolated geometry of Caelestia's `BlobInvertedRect` without four strips/corner patches or an offscreen blur source. The old odd-even path remains only inside the lazy shader-error fallback.
- **Normal ii Bar is treated as a thicker side of that same frame.** This follows Caelestia `ContentWindow.qml`: when Bar owns top/bottom, the matching inner-frame inset becomes `Appearance.sizes.barHeight`; when VerticalBar owns left/right it becomes `Appearance.sizes.verticalBarWidth`. The other three sides remain the Screen Edge thickness. Therefore the two inward Bar endpoint corners are produced by the same locked rounded workspace hole, not by Bar-local patches.
- **Connected curvature is iRiS-owned, not patch-owned.** `StyledPopup` and the shared edge adapter use the exact iRiS SDF path. Sidebar/Dashboard/Settings consume `ConnectedSurfaceIrisEdgeSurface`; Dashboard-owned Applications Search shares the Dashboard field, while standalone Search/OSK/Waffle keep direct square seams. No standalone round-wedge painter remains.
- Caelestia's border defaults are preserved: Screen Edge thickness defaults to **10px** and corner radius defaults to **25px**. The full-output `FrameWindow` is the outer physical bound for the analytic field; the 50px padded outer path remains in the error fallback as the historical clipping reference. Radius is user-adjustable through Settings without changing renderer ownership.
- The full-screen visual `FrameWindow` follows Caelestia's layer-shell placement contract: it is anchored to all four physical output edges and uses `ExclusionMode.Ignore` without setting an `exclusiveZone`, so edge reservations cannot inset the painted frame. The four thin `ReservationWindow` surfaces are transparent compositor reservations only; they set the positive edge `exclusiveZone` and otherwise remain in normal exclusion semantics. They never paint Screen Edge pixels and therefore cannot change the frame silhouette.
- Physical Screen Edge elevation is owned by the same **single analytic `ScreenEdgeField` pass** as the frame fill. It must not introduce an offscreen capture, blur pyramid, edge/corner renderer, gradient band, radial patch, wedge, rectangle or second healthy-path geometry. Defaults retain Material `m3shadow`, logical size **15px**, and alpha **0.70**; the old `MultiEffect` settings exist only in the shader-error fallback.
- Screen Edge and ii Bar popup depth are synchronized: `appearance.screenEdge.physicalShadow` drives the locked physical frame and every ii `StyledPopup`, using the same Material `m3shadow` ink. The older `appearance.screenEdge.shadow` contract remains internal to Sidebar/Dashboard/Settings/OSK and must never be read by `ScreenEdges.qml`.
- When the ii Bar uses auto-hide, it relinquishes physical-edge ownership to `ScreenEdges.qml`; there is no `autoHideScreenEdge` substitute inside Bar/VerticalBar.
- `scripts/test-shell-surface-contracts.py` is the regression gate. Together with `scripts/test-screen-edge-analytic-field-contract.py`, it locks the single `FrameWindow`, analytic rounded-hole geometry, all four Bar-aware inset formulas, the shared radius owner, and the lazy four-`PathArc` reference fallback. Do not restore `CornerWindow`, painted `EdgeWindow`, Bar-local `RoundCorner`/`PathArc` geometry, separate physical shadow geometry or shared shadow ownership.

## Equalizer implementation status

### Implemented

`EqualizerService.qml` provides the Phase 1 backend/service contract and is disabled by default. It owns the optional 10-band DSP state, EasyEffects transport boundary, preset curves and consumer-driven lifecycle without creating a second equalizer backend.

### Stabilizing

The existing backend is being stabilized around transport probing, EasyEffects lifecycle changes, state synchronization and live visual/audio validation in the Media Popup. These are hardening tasks; they do not imply that the open release gates below have already passed.

### Planned

Further equalizer presentation experiments are planned/deferred rather than current release prerequisites. The v1.0 release-blocker list below remains the authority for required source and live validation.

## 3. v1.0 release blockers

Active correctness, release, presentation and performance tasks are tracked in [GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen), with stable task codes. See [canonical validation](docs/VALIDATION.md) for SHA-pinned local checks and separate maintainer desktop acceptance.

## 3.1 Latest maintainer runtime findings

Current open/reconciliation tasks start in [GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen), following [AGENTS.md](AGENTS.md) priorities. Original source-complete notes and past checkpoints remain in [the archive](docs/archive/README.md).

## 4. Connected-surface architecture contract

The existing connected-surface paths remain authoritative:

```text
ii Bar popups:
modules/bar/StyledPopup.qml
  -> modules/common/perimeter/ConnectedSurfaceGeometry.qml
  -> modules/common/perimeter/ConnectedSurfaceRevealClip.qml
  -> modules/common/perimeter/ConnectedSurfaceIrisFrame.qml
       -> modules/common/perimeter/ConnectedSurfaceIrisField.qml
  -> modules/common/perimeter/ConnectedSurfaceContentHost.qml
  -> modules/common/perimeter/ConnectedSurfaceBodyMask.qml
  -> modules/common/perimeter/PerimeterTokens.qml

feature-owned Screen Edge bodies:
Sidebar / Dashboard / Settings
  -> modules/common/perimeter/ConnectedSurfaceIrisEdgeSurface.qml
  -> modules/common/perimeter/ConnectedSurfaceIrisFrame.qml

direct square-seam compatibility:
Waffle -> ConnectedSurfaceFrame.qml + ConnectedSurfaceMask.qml
Dock / Search / OSK -> feature-owned body geometry, no auxiliary wedge painter
```

Rules:

- `StyledPopup.qml` remains the entry point for existing ii Bar popouts.
- Curved connected contact is owned by iRiS; direct-seam surfaces keep square joined body edges.
- `ConnectedSurfaceJoinFlares`, `PerimeterCornerShadow`, common `RoundCorner` and the `joinFlare*` token family are retired and must not be recreated.
- Consumers provide content and source ownership; they must not recreate connector/stem geometry, private edge gaps or standalone corner wedges.
- Keep source-aware placement, owner clipping and shaped input regions.
- Preserve top/bottom/left/right attachment and output ownership.
- Fix shared geometry when the defect is systemic; do not paper over the same seam bug in every popup.

## 5. Required functionality that must not regress

- MPRIS player switching, play/pause, previous/next, seek and volume;
- CAVA / visualizer behavior where supported;
- keyboard navigation, initial focus and Escape close;
- click-outside close and transparent-region click-through semantics;
- hover-open / hover-transfer behavior;
- system tray and nested tray menus;
- Dock/task drag and reorder flows;
- Sidebar role routing, resize/edit behavior and open/close state;
- multi-output routing and source-screen ownership;
- fullscreen, lock, suspend/resume and compositor transitions;
- Niri primary behavior and existing Hyprland compatibility;
- Material theme tokens, palette and component rendering;
- Waffle family routing.

## 6. v1.0 hardening tasks — P1

See [GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen) for correctness, release acceptance and refinement.

## 7. Local release validation — P0 gate

See [`docs/VALIDATION.md`](docs/VALIDATION.md) for the canonical validator contract and the separately labeled maintainer-only live checklist.

## 8. v1.0 definition of done

Alis can be called **1.0** only when:

- every P0 release blocker above is completed and locally validated;
- no known empty/broken Settings route remains for supported features;
- connected surfaces visually read as one coherent bar/edge continuation, not detached cards;
- no required behavior depends on a dead/half-enabled renderer or undocumented migration path;
- **Material is the only active Global Theme**, with non-Material values removed from normal runtime/UI and legacy values safely normalized;
- the broad `iiPerimeter` runtime is either removed or retained only for a clearly documented active responsibility;
- media visualization, Thinkfan and weather dependencies are packaged/documented correctly;
- supported panel families, the Material theme and compositor targets pass the release smoke matrix;
- release notes / `CHANGELOG.md` describe user-visible 1.0 behavior after the implementation stabilizes.

## 9. Explicit non-goals for 1.0

Do not spend the 1.0 cycle on:

- a new popup framework parallel to `StyledPopup`;
- reviving retired renderer/style experiments;
- rebuilding the old Pill or Mascot runtime;
- preserving or reintroducing multiple Global Theme families after the Material-only cleanup;
- copying Serpantinum's right-side weather panel;
- cosmetic documentation history that does not help implement or validate 1.0;
- hosted-CI cleanup while Actions usage is intentionally not part of the maintainer validation loop.

## 10. Documentation hygiene

To avoid future contradictions:

- keep this README focused on **current** v1.0 requirements, invariants and release gates;
- classify each actionable maintainer request in GitHub Issues by its stable feature/rework/bug code, deduplicate and follow the owner's latest priority;
- use [the documentation index](docs/README.md) for references and [the archive](docs/archive/README.md) for historical evidence; keep unfinished/bot-complete-unverified work in open GitHub Issues;
- treat the Material-only Global Theme rule as canonical anywhere older documentation still describes multiple Global Themes;
- do not pin transient implementation status to old commit hashes here;
- put historical changes in `CHANGELOG.md` / Git history;
- when code removes a feature/runtime/theme, remove or update its user-facing setting and stale documentation in the same change where practical;
- when an older document conflicts with the newest maintainer instruction or this active v1.0 contract, update/remove the stale statement instead of maintaining two competing rules.

If the maintainer gives a newer explicit instruction, that instruction supersedes this document and this README should be refreshed to match it.

## 11. Current unfinished handoff

Start at [GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen) and [AGENTS.md](AGENTS.md); older Markdown task lists are historical pointers only. Always verify current `dev`.

## 12. New-conversation continuation

For both Local and Cloud AI, read `AGENTS.md`, [open GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen) and current `dev`. Search/update the matching Issue, follow priorities, and continue within authorized scope. Do not start from superseded historical prompts or SHAs.

