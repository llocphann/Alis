> Historical snapshot archived on 2026-10-10 from Alis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

# Unified Surface Composition Research

> **Historical research / superseded execution guidance.** Production Abyss cutover has already landed. Do not use this document as the active implementation contract. Current instructions live in `README.md` §1.1/§2.1, `docs/UNIFIED_SURFACE_HANDOFF.md`, `docs/PERIMETER.md` and `docs/SHELL_SURFACE_CONTRACTS.md`. References below to JoinFlares, RoundCorner, pre-cutover baselines or “not approved for production” describe the investigation history only.

Status: **archived research context**

Last active research synchronization: 2026-09-20.

## 1. Why this document exists

Alis needs Bar/Screen Edge connected popups, Sidebar, Dashboard, Settings Overlay and similar edge-attached surfaces to read as **one continuous material/silhouette**, closer to Caelestia.

The previous experiments attempted to synthesize the contact corners separately with:

- `ConnectedSurfaceJoinFlares`;
- Canvas/Bézier corner pieces;
- explicit `joinTop/joinBottom/joinLeft/joinRight` routing;
- mapped body geometry;
- contact-plane/inset calculations;
- seam-overlap compensation.

Those experiments could make some corners visible, but they repeatedly produced one or more of:

- a small gap at the Bar/Screen Edge seam;
- a shifted or floating corner;
- inconsistent results between Sidebar, Dashboard and Bar popups;
- corner disappearance after repeated hover/open-close cycles;
- consumer-specific offset logic;
- duplicated knowledge of Bar/Screen Edge thickness and seam ownership.

The user clarified the real product requirement:

> The contact corners should not look like corrective geometry painted around two unrelated rectangles. The connected Bar/Screen Edge and popup should behave like one common shape, and when a Bar module is reordered the connected popup topology should follow its new position automatically.

That requirement changes the architectural target. The desired result is not “better flares”; it is **unified surface composition**.

---

## 2. Revert/baseline status

The contact-corner experiment series was reverted by:

- `cef10e8923c24ef4cf4106237dfaa418c1abe4a9` — `revert: restore pre-contact-corner baseline`

The current production files involved in those experiments are byte-identical to the pre-experiment baseline at:

- `ad42c9326e34cdec6e2d7791a2a0664d8bbfb82f`

This was re-verified against current `dev` for all relevant paths, including:

- `modules/common/perimeter/ConnectedSurfaceJoinFlares`
- `modules/common/perimeter/ConnectedSurfaceFrame.qml`
- `modules/common/perimeter/ConnectedSurfaceRevealClip.qml`
- `modules/bar/StyledPopup.qml`
- `modules/waffle/bar/BarPopup.qml`
- `modules/sidebar/SidebarHost.qml`
- Sidebar left/right visible surface files
- `modules/overview/Overview.qml`
- `modules/overview/OverviewDashboard.qml`
- `modules/onScreenKeyboard/OnScreenKeyboard.qml`
- `modules/settings/SettingsOverlay.qml`
- `modules/settings/SettingsFocus.qml`
- Sidebar config/default schema files
- perimeter/shell-surface regression scripts
- `README.md`

Any later `dev` commits after the revert were unrelated work and did not reintroduce the corner experiment into those files.

### Do not resurrect the reverted patch stack

The following approaches are considered rejected as a production foundation:

1. Per-corner Canvas patches added on top of otherwise independent surfaces.
2. Generic `contactInset` inference.
3. Consumer-specific magic pixel offsets for Sidebar/Dashboard/Battery.
4. Shifting a mathematical contact plane merely to hide compositor/AA cracks.
5. A growing matrix of `joinTop/joinBottom/joinLeft/joinRight` plus special cases as the primary topology model.
6. Treating Screen Edge/Bar and Popup as separate silhouettes and attempting to fake a unified contour afterward.

The existing connected-surface helpers may remain as baseline code until a replacement is proven, but they must not constrain the new architecture.

---

## 3. What Caelestia actually does

Relevant Caelestia source areas examined:

- *modules/drawers/ContentWindow.qml*
- *modules/drawers/Panels.qml*
- `modules/bar/Bar.qml`
- *modules/bar/popouts/Wrapper.qml*
- *modules/bar/popouts/ClipWrapper.qml*
- `plugin/src/Caelestia/Blobs/blobgroup.*`
- `plugin/src/Caelestia/Blobs/blobshape.*`
- `plugin/src/Caelestia/Blobs/blobrect.*`
- `plugin/src/Caelestia/Blobs/blobinvertedrect.*`
- `plugin/src/Caelestia/Blobs/blobmaterial.*`
- `plugin/src/Caelestia/Blobs/shaders/blob.frag`
- plugin CMake/QML module packaging files.

### Core model

Caelestia does not draw an independent “join corner” between two windows.

Conceptually:

```text
one visual scene
└── BlobGroup
    ├── BlobInvertedRect   # screen/frame/border domain
    ├── BlobRect           # panel/popout A
    ├── BlobRect           # panel/popout B
    └── ...
         ↓
    SDF smooth union / sink
         ↓
    one resulting silhouette
```

Each participating shape contributes an SDF. The shader/material combines those fields. The curved shoulder at a contact point is therefore **the boundary of the union itself**, not a separate decorative object.

### Border sink

Caelestia's inverted frame participates in the same field. A panel entering the border can cause the border contour to yield/sink around it. This is why a popout can appear to grow naturally from an edge/frame instead of looking like one rounded rectangle touching another.

### Why module reordering works naturally

Caelestia's Bar popout placement follows the live source item position. The important semantic flow is:

```text
Bar module Item
    ↓ live mapToItem()/position binding
currentCenter / source rect
    ↓
popout rect position
    ↓
BlobRect position
    ↓
BlobGroup recomputes the common field
```

If the module is reordered, the source item moves. The popout rect moves. The SDF topology changes automatically.

The renderer does **not** need:

```text
if module is near right edge:
    draw a right contact corner
```

It only consumes the new rectangles.

This exactly matches the Alis requirement that moving a Bar module should cause its popup contact shape to follow automatically.

---

## 4. Existing Alis pieces worth keeping

The research does **not** imply rewriting the entire shell.

### 4.1 StyledPopup's source/anchor semantics are useful

`StyledPopup.qml` already owns valuable semantic behavior:

- `hoverTarget` points to the real source control;
- `_anchorWindow` and `_anchorScreen` derive ownership from that source;
- `_anchorRect()` explicitly touches target geometry and `QsWindow.windowTransform` because Quickshell mapping calls are not fully reactive by themselves;
- popup placement already follows module movement/output transforms;
- support exists for `anchorRect`, centered large surfaces and horizontal/vertical Bar ownership;
- hover-transfer/retract lifecycle is already solved separately from visual shape.

This anchor/ownership logic should be retained and adapted into a **shape registration feed**, not discarded.

### 4.2 ScreenEdges.FrameWindow is an important existing host candidate

The current Screen Edge implementation already has a full-output visual window with several useful properties:

- one instance per output;
- mapped persistently;
- click-through/input ignored;
- full-output coordinate space;
- frame geometry already represents the locked Screen Edge silhouette;
- Bar can be represented as a thicker edge in the same conceptual perimeter model;
- load ordering/stacking constraints are already documented because Niri can change same-layer stacking when surfaces are remapped.

This does **not** prove that ScreenEdges.FrameWindow must become the final unified host, but it makes it the strongest first candidate for a Bar/Screen Edge composition domain.

### 4.3 Current module-reorder infrastructure is sufficient as an input

Alis Bar modules are driven from configured layout/zone data. Reordering changes the real QML Item positions. Because popup ownership is already tied to the source Item, the future unified renderer can consume **live output-space rectangles** rather than storing contact-corner state.

---

## 5. Critical Qt/Quickshell constraint: one SDF cannot span independent scenegraphs

This is a fundamental constraint and must shape the architecture.

Each `QQuickWindow` has its own scenegraph/content root. Current Alis surfaces are often independent layer-shell windows:

```text
ScreenEdges FrameWindow  -> Top
Bar PanelWindow          -> Top
StyledPopup PanelWindow  -> Overlay
Sidebar PanelWindow      -> Overlay
Overview PanelWindow     -> Overlay
Settings PanelWindow     -> Overlay
```

The compositor receives the already-rendered textures/surfaces and composites them later.

Therefore a real GPU SDF union cannot be computed by placing one SDF shape in the Bar window and another SDF shape in the Popup window. They are already separate render targets by then.

### Consequence

All shapes that are supposed to form **one silhouette** must have a representation inside **one visual QQuickWindow/scenegraph**.

The interaction/content window may remain separate, but the common background/material silhouette needs a shared visual host.

This leads to the split:

```text
Visual host
  owns unified material / SDF silhouette

Content/input windows
  own controls, focus, pointer handling, keyboard input, semantic lifecycle
```

This is a promising hybrid architecture because Alis does not need to move all interactive content into a single monolithic window.

---

## 6. Visual composition domains, not necessarily one global host

A single global host for every shell surface is probably wrong.

### Why

Layering/scrim semantics differ.

Example: Settings Overlay currently includes an Overlay-layer scrim/glass backdrop plus the Settings card. If the Settings card's material background were drawn far below that in a Top-layer global host, the scrim would tint/cover it incorrectly.

So the correct abstraction is likely a **composition domain**:

> Shapes may union only when they share the same intended visual material/topology and can be rendered in a host at the correct stacking relationship.

Candidate domains:

### Domain A — ii edge material

Likely participants:

- Screen Edge frame;
- horizontal/vertical Bar material;
- Bar popout backgrounds;
- possibly Dashboard when directly attached;
- possibly Sidebar when directly attached.

This is the main Caelestia-like target.

### Domain B — Settings Overlay material

Possible participants:

- Settings card/body;
- a virtual/derived bottom owner edge when Overlay mode is attached to the physical perimeter.

It may require an Overlay-layer composition host or a local SDF composition inside the Settings Overlay window rather than the shared Top-layer edge host.

### Domain C — detached/non-unified surfaces

Examples may include context menus or windows that should not visually merge into the perimeter. They should not be forced into the common field.

This domain model needs more validation before implementation.

---

## 7. Renderer strategies evaluated

### Option A — Pure QML Shape/Canvas

**Recommendation: reject as the production architecture.**

Pros:

- easiest to prototype;
- no native ABI/package work;
- works with repo-copy immediately.

Cons:

- returns to hand-built geometry;
- hard to express robust many-shape smooth union;
- repeats the exact failure mode of the corner-flare experiments;
- topology becomes conditional QML rather than a field operation;
- difficult to guarantee identical results at arbitrary module positions and fractional scale.

It may be useful only for diagnostic sketches, not the target implementation.

### Option B — Full-screen QML ShaderEffect SDF

Alis already ships a compiled ShaderEffect example:

- `modules/common/widgets/FluidRipple.frag`
- `modules/common/widgets/FluidRipple.qsb`

So QSB assets already fit the runtime payload.

Pros:

- no C++ QML type required for a PoC;
- directly proves SDF math/topology;
- hot-reload friendly;
- compatible with repo-copy if the `.qsb` is committed;
- good way to validate frame + moving popup union before committing to native plugin infrastructure.

Risks:

- a full-output shader can be expensive, especially at high resolution/fractional scale;
- passing a dynamic registry of many rounded rects through ShaderEffect uniforms is awkward/limited;
- large fixed uniform arrays impose shape-count limits and work per fragment;
- full-screen fill-rate can dominate even when only small regions change;
- implementing efficient bounds/culling in pure QML is harder.

**Current view:** best minimal mathematical PoC, not automatically the final production renderer.

### Option C — Native QQuickItem/QSG material, Caelestia-style

Pros:

- strongest production direction;
- shape-specific/padded geometry can reduce fill-rate;
- natural dynamic shape registry;
- one material can consume multiple shape records;
- closest to Caelestia's proven architecture;
- can implement inverted frame + rounded rect smooth union cleanly;
- allows explicit scenegraph batching/culling and future shadow integration.

Risks:

- Alis currently has no native QML rendering plugin;
- Qt ABI/version compatibility matters;
- adds CMake/build/package complexity;
- repo-copy update cannot merely copy source if a binary module must be rebuilt;
- Arch package can no longer remain architecture-neutral for that capability;
- Nix default currently uses `stdenvNoCC` for the shell;
- installation/discovery of a QML plugin must be made reliable for Quickshell.

**Current view:** likely production renderer if PoC proves the topology and packaging work is designed first.

### Option D — Hybrid

Recommended research direction:

1. validate math/topology with a small QML/QSB PoC;
2. define the registry/domain API independent of renderer;
3. only then implement the same API with native QSG if performance/shape-count requires it.

This reduces the risk of building packaging infrastructure before the surface model itself is proven.

---

## 8. Packaging and runtime implications

### Current repo-copy model

The installed shell payload is primarily synchronized files under the runtime root. QML and committed `.qsb` assets work naturally with this.

A native `.so` QML plugin changes that assumption:

- it must be built for the current architecture;
- against a compatible Qt;
- installed at a QML import path;
- rebuilt when plugin source/Qt ABI changes.

### Native packaging boundary

A native QML renderer would introduce a stronger packaging requirement than the current file-only surface path: it needs an architecture- and Qt-compatible module installed on the QML import path. Treat that module as a separate capability package rather than compiling inside the runtime update path.


### Current Nix shell

The default shell package currently uses a no-compiler style packaging path and wraps QML import/plugin paths from dependencies. A native renderer likely requires a separate derivation/module package and then a wrapped shell variant, similar in spirit to the workflow parser split but using Qt CMake/QML tooling.

### Required packaging research before native implementation

Do not begin a production C++ renderer until these questions have concrete answers:

1. Where will the plugin live for repo-copy installs?
2. Will `alis update` detect source/plugin ABI mismatch?
3. Who builds it for repo-copy users?
4. Is it an optional package plus capability detection, or mandatory?
5. How is `QML2_IMPORT_PATH`/Qt 6 import discovery configured consistently for:
   - repo-copy;
   - Arch;
   - Nix;
   - source/developer runs?
6. How will Qt/Quickshell upgrades trigger rebuilds?
7. What is the fallback if the plugin is missing or incompatible?

No “download/build during shell startup” path should be introduced.

---

## 9. Blur/material/shadow is a major unresolved design area

Moving the visual background out of the content window affects more than color.

Current Bar and popup implementations can own:

- compositor blur region;
- local wallpaper fallback blur;
- opacity/transparency;
- border;
- material effects;
- shadow;
- input mask.

A unified visual host must define ownership explicitly.

### Recommended separation to investigate

```text
Unified visual host:
- fill/material silhouette
- common border if any
- common shadow
- compositor blur request for the union if host/layer allows it

Content windows:
- controls/content
- focus
- hover/click
- keyboard
- semantic open/close lifecycle
- transparent background
- shape-aware input region
```

### Important difficulty

If the visual host is on `Top` but a popup content window is on `Overlay`, blur/material may visually align but stacking around other Overlay surfaces must be tested.

Settings Overlay is the clearest example where a Top-layer host is insufficient because of scrim ordering.

Blur support therefore may force different visual domains/hosts by layer.

---

## 10. Input/mask architecture

A unified **visual** host should ideally remain input-transparent.

The content/input windows should continue to own:

- `MouseArea`/`HoverHandler`;
- keyboard focus;
- close-on-outside-click catcher;
- popup masks;
- sidebar interaction;
- Settings interaction.

This preserves the mature interaction lifecycle while replacing only the way backgrounds are composed.

The future registry should not use input geometry as its source of truth. It should consume visual/output-space rectangles registered from the same semantic surface controllers.

---

## 11. Proposed PoC architecture — no production cutover yet

### Goal

Prove one invariant:

> A Bar/source module can move/reorder and its attached popup background remains one smoothly-unioned silhouette with the edge/frame without any corner-specific code.

### Minimal PoC graph

```text
OutputSurfacePrototype
├── UnifiedSurfaceRegistry
│   ├── frame record
│   ├── bar record
│   └── popup record
│
├── UnifiedSurfaceRenderer
│   └── SDF union
│
└── live anchor adapter
    └── a real Bar module Item or controlled fake item
```

### Shape record draft

Keep the registry renderer-agnostic.

Each shape record should describe something close to:

```text
id
domainId
kind: frame | roundedRect
outputName
rect in output logical coordinates
radius
enabled
materialRole
z/topology role only if mathematically required
```

Avoid:

```text
joinTop
joinBottom
joinLeft
joinRight
topLeftFlare
rightContactInset
```

Those are symptoms of the old architecture.

### Coordinate system

Use **output-local logical coordinates** as the registry contract.

Conversion rules:

1. Source Item/controller maps its live rect into output/window coordinates.
2. Registry stores logical coordinates.
3. Renderer receives device-pixel ratio separately and handles AA in the rendering layer.
4. Fractional scaling tests must verify the same silhouette at DPR 1.0 and fractional output scales.
5. Never bake AA compensation into semantic rects.

### Frame record

The prototype frame should reproduce the locked Screen Edge/Bar silhouette numerically but must not modify production `ScreenEdges.qml`.

The PoC may derive the same configured:

- screen-edge width;
- screen rounding;
- Bar thickness/orientation;
- Bar visibility/ownership.

The locked production frame remains untouched until cutover is explicitly approved.

### Popup record

The PoC popup rect should be driven from a live source anchor:

```text
module Item
  -> source/output mapping
  -> popup layout/clamp
  -> registry rect
```

Move/reorder the source and require that only the rect changes.

### Required topology tests

1. module centered on horizontal top Bar;
2. module near left side;
3. module near right side;
4. popup clamped to Screen Edge;
5. bottom Bar;
6. left Vertical Bar;
7. right Vertical Bar;
8. popup opening/closing while source moves;
9. fractional scale;
10. two simultaneous registered popup shapes for stress, even if production only allows one at first.

### Strict PoC rejection condition

Reject the design if the renderer needs source-specific code such as:

```text
if battery ...
if clock ...
if atRightEdge then draw corner ...
```

The only accepted special distinction should be generic shape types/material roles needed by the SDF model.

---

## 12. Animation contract

Animation should change **shape parameters/rects**, not swap corner assets.

For a connected popup:

- body rect slides from behind/inside the owner region into resting rect;
- SDF recomputes continuously;
- union shoulder emerges naturally;
- no bounce/overshoot that visually detaches the silhouette.

The previous discussion preferred monotonic connected motion. That remains a good target, but do not modify current production animation until the new renderer is proven.

Bar module reorder should be treated as live geometry movement. The union should follow continuously without explicit corner transitions.

---

## 13. Shadow strategy

Caelestia's common-surface model makes a strong case for **one shadow for the resulting union**, rather than separate Screen Edge and popup shadows that must meet perfectly.

For the PoC:

- first validate fill silhouette with no shadow;
- then add a shadow from the union alpha/SDF;
- compare with current locked Screen Edge shadow visually;
- do not change production shadow ownership during PoC.

A production migration gate should require equivalent or better:

- no double shadow at joins;
- no shadow gap;
- no shadow discontinuity during module movement;
- acceptable GPU cost.

---

## 14. Blur strategy to research next

This remains unresolved and is one of the top three blockers.

Questions:

1. Can a full-output input-transparent Top-layer visual host request compositor blur only inside the union shape via a Quickshell `BackgroundEffect.blurRegion`/mask that follows the renderer?
2. Does Niri honor dynamic complex blur regions at the required cadence?
3. If blur region can only be described with ordinary regions/items, can the SDF host expose a conservative rectangle union without visibly blurring outside material?
4. Is the current Material default usually opaque enough that unified blur can be deferred?
5. How should Settings Overlay handle blur behind its Overlay-layer scrim/card domain?

PoC should begin with opaque Material fill so SDF correctness is isolated from blur.

---

## 15. Native renderer/API research to do before coding it

If the QSB PoC passes, study a minimal native plugin rather than copying all Caelestia physics/features.

Likely minimal types:

```text
Alis.Surface
├── SurfaceGroup
├── SurfaceRect
├── SurfaceFrame / SurfaceInvertedRect
└── internal SurfaceMaterial
```

Do not initially port:

- spring deformation;
- velocity physics;
- unrelated blob effects;
- general feature registries;
- arbitrary legacy compatibility.

Production renderer requirements:

- dynamic child shape discovery/registration;
- dirty flags only when shape/material data changes;
- bounded geometry around affected regions where possible;
- one material/shader per composition domain;
- deterministic logical->device coordinate transform;
- no source-module-specific branches;
- stable hot reload behavior;
- explicit missing-plugin fallback.

License note: both Alis and Caelestia repositories are GPL-family compatible for adaptation, but copied/adapted source must retain the appropriate notices and attribution. Re-check exact per-file headers before porting code.

---

## 16. Native vs QSB PoC recommendation

Recommended sequence:

### Phase U0 — research completion

No production changes.

Close the remaining questions:

- Niri visual-host stacking/lifetime;
- compositor blur ownership;
- package/import path for native plugin;
- exact minimal SDF equations needed from Caelestia;
- performance budget.

### Phase U1 — isolated QSB PoC

Create a non-production prototype that:

- uses one visual window/domain;
- draws frame + one moving rounded popup rect;
- does smooth union/sink;
- consumes a live/fake moving anchor;
- has no corner-specific code;
- measures GPU/frame cost.

The prototype may use a fixed small shape array because it is a math/topology experiment, not the final registry implementation.

### Phase U2 — dynamic registry PoC

Only after U1 passes:

- define renderer-independent registry;
- test module reorder and multiple rects;
- validate DPR/fractional scaling and multi-monitor mapping.

### Phase U3 — choose renderer

If QSB cost/API is acceptable, a pure shader host may remain viable.

If not, implement minimal native QSG module behind the **same registry contract**.

### Phase U4 — first production cutover

Cut over only:

- Screen Edge/Bar visual background;
- one class of `StyledPopup`.

Keep content/input windows unchanged.

No Sidebar/Dashboard/Settings migration yet.

### Phase U5+

Migrate each surface class only after the previous class passes visual/runtime gates.

---

## 17. Production migration gates

Each cutover must pass all applicable gates.

### Visual

- one continuous silhouette;
- no 1 px seam in light or dark theme;
- no floating/offset corners;
- no double border;
- no double shadow;
- popup contact follows live module movement;
- correct topology near every screen edge;
- correct fractional scale.

### Runtime

- no popup hover/open-close regression;
- no blank Bar after fullscreen;
- no remap/stacking regression on Niri;
- hotplug/multi-monitor stable;
- no stale geometry after Bar reorder;
- no input interception by visual host.

### Performance

Establish baseline and candidate measurements:

- idle GPU cost;
- opening animation;
- module reorder;
- one popup;
- multiple shapes;
- 1080p/1440p/4K if practical;
- fractional scale.

Do not accept a visually correct full-screen shader if it creates unacceptable continuous fill-rate cost.

### Packaging

Before native renderer promotion:

- repo-copy lifecycle is specified;
- Arch package exists;
- Nix package/variant exists;
- plugin discovery is deterministic;
- missing/incompatible plugin fails clearly;
- no runtime compilation/download.

### Rollback

Every production phase should remain switchable back to the current baseline until that phase is certified.

Do not delete old connected-surface implementation in the same commit that first enables the new renderer.

---

## 18. Parts likely to remain vs retire

### Likely to remain

- Bar module layout/reordering logic;
- source Items and hover targets;
- `StyledPopup` semantic open/close state;
- anchor/output ownership logic;
- click-outside/focus handling;
- content windows;
- Screen Edge configuration tokens;
- current locked physical dimensions/radii as input parameters;
- Sidebar/Dashboard/Settings content trees.

### Likely to change

- ownership of Bar/Screen Edge/popup backgrounds;
- popup visual background path;
- shadow ownership;
- blur ownership;
- surface/background masks.

### Likely to retire after successful cutover

- `ConnectedSurfaceJoinFlares` as the contact topology solution;
- explicit corner/edge join routing used solely to synthesize shoulders;
- contact-inset/contact-plane compensation logic;
- duplicate per-consumer seam fixes;
- any corner asset whose only job is to fake union between independent silhouettes.

Do not retire them before the new composition domain has proven production parity.

---

## 19. Open questions

### Highest priority

1. **Niri stacking/lifetime**
   - Can the proposed visual host remain below all content windows it supports without remap-related reorder?
   - Is `Top` sufficient for Bar popouts that currently use `Overlay`, or does the visual background need its own Overlay-domain host?

2. **Blur/material**
   - How to transfer native compositor blur from current Bar/popup windows to a unified visual host without over-blurring the output?
   - How to handle transparent Material configurations and wallpaper fallback effects?

3. **Native plugin lifecycle**
   - What exact package/import strategy preserves the simplicity of `alis update`?
   - Should repo-copy users require a separately installed `alis-surface-renderer` package?

### Secondary

4. How much of Caelestia's border-sink shader is needed for Alis' locked frame geometry?
5. Can a bounded ShaderEffect prototype render only an affected strip/union bbox instead of full output?
6. How should auto-hidden Bar geometry participate while hidden/revealing?
7. How should Settings Overlay form a local composition domain under its scrim?
8. Should Dashboard visually union with Screen Edge through the global edge domain, or a local domain whose host is correctly layered?
9. How many simultaneous shapes must production support?
10. How should shadow and blur bounds expand the renderer's dirty/bounding geometry?

---

## 20. Immediate next research tasks

Do these **before writing production code**:

1. Trace exact layer-shell stacking and remap behavior for:
   - ScreenEdges FrameWindow;
   - Bar;
   - StyledPopup;
   - a hypothetical visual host.
2. Prototype/inspect Quickshell blur-region possibilities for an input-transparent visual host.
3. Design native plugin install/import lifecycle for repo-copy, Arch and Nix.
4. Extract the minimum Caelestia SDF equations/data layout required for:
   - rounded rect;
   - inverted frame;
   - smooth union;
   - border sink.
5. Define a renderer-neutral registry API and shape-count budget.
6. Specify an isolated U1 PoC that does not touch current production surfaces.

No commit beyond documentation should be made until those points are understood well enough to choose the PoC implementation deliberately.


---

## 21. U0 blocker resolution — 2026-09-20 continuation

This section records the research performed after the initial handoff. It is still
**research/design only**. No production surface, renderer, package, or geometry was
changed by this work.

Research was resumed from \`dev\` at:

- \`7ae39986719b0127c24c10ade9b8ec1ad84c32fb\`
- \`docs(surface): capture unified composition research handoff\`

That commit is exactly one commit above the research synchronization point
\`c233d1c4aaac911d7fd2e8daac9fb3857f740860\`, and its only changed files are:

- \`docs/UNIFIED_SURFACE_HANDOFF.md\`
- \`docs/UNIFIED_SURFACE_RESEARCH.md\`

Therefore the handoff commit itself did not alter any production file and did not
resurrect the reverted Canvas/flare/contact-plane work.

### 21.1 Niri/Smithay same-layer lifetime is not stack-neutral

Current Niri maps layer surfaces through Smithay's \`LayerMap\`. Smithay stores
mapped layer surfaces in an insertion-ordered \`IndexSet\`:

- \`map_layer()\` inserts a newly mapped surface;
- \`unmap_layer()\` removes it with \`shift_remove()\`;
- a later remap inserts it again at the end;
- Niri reverses the layer iterator to obtain its render/input order.

Niri's own render code explicitly says that \`LayerMap\` returns layers in reverse
stacking order and applies \`.rev()\` for rendering. Its input lookup uses the same
reversed ordering.

Architectural consequence:

> A visual host whose relationship to other same-layer Alis surfaces matters
> must remain mapped. Shape enable/disable, opacity and registry membership may
> change; the host's Wayland surface lifetime must not be used as an animation or
> visibility mechanism.

This independently validates the existing Alis fullscreen lifecycle locks on
\`ScreenEdges.FrameWindow\` and the Bar.

Upstream references inspected:

- Niri \`src/handlers/layer_shell.rs\`, current main during research:
  \`7256ccf6274a1f953c6987ade34ea1c0e4944c27\`
- Niri \`src/niri.rs\`, especially \`layers_in_render_order()\`
- Smithay \`desktop/wayland/layer.rs\`, \`LayerMap::{map_layer,unmap_layer,layers_on}\`

### 21.2 Top cannot be the sole visual domain for an Overlay popout

Current Alis layering is materially different between the perimeter and
popouts:

- \`ScreenEdges.FrameWindow\`: \`WlrLayer.Top\`
- Classic Bar: Top-layer panel semantics
- \`StyledPopup\` presentation window: \`WlrLayer.Overlay\`
- \`StyledPopup\` click-outside catcher: \`WlrLayer.Overlay\`
- Settings overlay: normally \`WlrLayer.Overlay\`, with deliberate temporary
  transitions to Bottom/Top for native-dialog/Polkit semantics.

Niri renders Overlay above the rest of the normal shell composition. It can render
fullscreen/overview content above Top while Overlay remains above it. Therefore a
Top-only material host cannot be the complete visual background for a popup whose
content intentionally remains Overlay: during fullscreen/overview the popup
content could remain visible while its Top-layer material disappears underneath
the client.

Rejected for the first production design:

1. moving existing Overlay popout content down to Top merely to share a host;
2. moving the persistent physical Screen Edge host permanently to Overlay;
3. repeatedly mapping/unmapping a second visual host to chase popup lifetime.

The preferred domain split is now:

\`\`\`text
Top base domain
  persistent physical perimeter / Bar material

Overlay attached-surface domain
  popup-local unified material
  = virtual owner edge/frame representation + popup rounded rect
  rendered inside the same Overlay scenegraph as the popup when possible
\`\`\`

The phrase "virtual owner edge/frame representation" does **not** mean a contact
patch. It is a generic frame/owner shape record evaluated by the same SDF as the
popup. The shader never selects a left/right contact corner. The popup's live
output-space rectangle is the only moving topology input.

For \`StyledPopup\`, the strongest first production candidate is therefore to keep
its full-output Overlay \`PanelWindow\` and let that window eventually render the
local unified SDF material behind its existing content. This avoids introducing a
second same-layer visual/content ordering relationship. The persistent Top frame
continues underneath; the Overlay domain draws only the affected attachment
region and visually occludes the identical material below it.

A separate persistent Overlay visual host remains possible later for domains with
multiple content windows, but it needs an explicit creation-order contract and
tests against other Overlay surfaces. It is no longer required for U1.

### 21.3 Blur is surface-owned protocol state, not shader-alpha state

Quickshell's \`BackgroundEffect.blurRegion\` is a client request through
\`ext-background-effect-v1\`. The protocol attaches the effect to one
\`wl_surface\` and accepts a copied \`wl_region\` in surface-local coordinates.
The blur region is double-buffered with the surface commit.

Niri's current implementation caches that blur region as rectangles and uses it as
a transformed subregion for the background effect.

Quickshell \`Region\` can compose regions and supports rounded-rectangle/per-corner
radii, but the protocol payload is still a Wayland region rather than an arbitrary
SDF/alpha texture.

Consequences:

- the SDF result cannot simply be passed as \`blurRegion\`;
- a loose bounding rectangle is unacceptable for translucent material because
  transparent pixels outside the SDF fill would expose blur that should not exist;
- compositor blur must be requested by the same Wayland surface/layer that owns
  the visible translucent material;
- Top and Overlay composition domains therefore need their own blur requests.

The production abstraction should be:

\`\`\`text
one renderer-neutral shape registry
    ├── SDF projection     -> fill / border / common shadow
    └── Region projection  -> compositor blur request
\`\`\`

The Region projection is generic geometry derived from the same shape records. It
must not contain source-module names or corner/contact flags.

Exact SDF-to-\`wl_region\` fidelity is not required for U1. A later production
experiment may compare:

- ordinary rounded-rect Region union;
- a bounded scanline/rect decomposition of the final SDF;
- disabling compositor blur for configurations where an accurate dynamic region
  is too expensive.

U1 deliberately uses opaque fill and no compositor blur so that field topology is
measured independently.

### 21.4 Shadow ownership belongs to the unified renderer

Niri layer-rule shadows are surface-geometry shadows. The compositor sees layer
surface geometry, not Alis' arbitrary SDF alpha silhouette. They are therefore
not a correct source for the future common connected-surface shadow.

Production target:

- unified renderer owns one shadow derived from the union field/alpha;
- content windows own no competing connected-body shadow;
- current Screen Edge \`MultiEffect\` and connected-popup shadows stay untouched
  until an actual migration phase.

U1 order remains:

1. prove fill;
2. optionally prove a field-derived shadow in a separate U1b step;
3. do not migrate production shadow ownership.

### 21.5 Settings remains a local Overlay composition domain

\`SettingsOverlay.qml\` currently combines:

- a full-output Overlay window;
- optional full-screen \`GlassBackground\` backdrop blur;
- scrim dimming;
- click-outside interaction;
- a Settings card with its own existing depth treatment;
- special layer changes for native dialogs and Polkit.

Its card material must not be moved into the persistent Top edge domain. If/when
Settings receives SDF attachment behavior, it should be composed inside the
Settings Overlay domain so the ordering remains:

\`\`\`text
background/app
  -> Settings backdrop blur
  -> Settings scrim
  -> Settings unified card/edge material
  -> Settings content
\`\`\`

This closes the earlier question of whether one global visual host should own
Settings: it should not.

---

## 22. QSB versus native QSG — architecture decision for the PoC

### 22.1 U1 uses QSB

U1 should use a QML \`ShaderEffect\` with a committed precompiled \`.qsb\`.

Reasons:

- Alis already ships and loads \`FluidRipple.qsb\` by relative URL;
- Qt 6 \`ShaderEffect\` is explicitly designed to consume offline-compiled QSB
  shader packs;
- no new C++ QML module or ABI is required;
- repo-copy/source installs can consume a committed QSB exactly like the existing
  shader asset;
- U1 needs to validate field math and bounds, not a native registry implementation.

The shader compiler is a **developer/build-time** dependency only. Runtime must
never compile or download shader source.

### 22.2 Native QSG remains a production candidate, not a U1 prerequisite

Caelestia's current Blob implementation confirms the production benefits of native
QSG:

- bounded QSG geometry rather than one permanent full-output fragment pass;
- C++ shape/group registry;
- one custom QSG material with batched shape uniforms;
- dirty/polish updates localized to affected shapes;
- the inverted frame is rendered as four frame strips with an inner hole rather
  than a full-screen quad.

But this requires a compiled QML module. Caelestia builds \`Caelestia.Blobs\`
with \`qt_add_qml_module()\`, compiles shaders with \`qt_add_shaders()\`, and
installs the backing library, plugin, \`qmldir\`, and typeinfo under the Qt QML
import hierarchy.

Alis must not add that infrastructure merely to run U1.

### 22.3 Proposed native package boundary if U3 selects QSG

If U3 demonstrates that QSB cannot meet the production shape-count/fill-rate
budget, the native module should be a separate capability package:

\`\`\`text
URI: Alis.Surface

SurfaceGroup
SurfaceRect
SurfaceFrame
internal SurfaceMaterial
\`\`\`

Suggested installation boundary:

\`\`\`text
Arch:
  /usr/lib/qt6/qml/Alis/Surface/
    qmldir
    *.qmltypes
    plugin/backing .so files as generated by Qt CMake

Nix:
  <store>/lib/qt-6/qml/Alis/Surface/
\`\`\`

Use \`qt_add_qml_module()\` and \`qt_add_shaders()\`; do not hand-maintain plugin
metadata that Qt can generate.

A future native surface capability should follow a narrow lifecycle pattern:

- native capability has its own Arch/Nix package;
- runtime shell can remain separately deployable;
- developer-only build helpers do not install into runtime.

### 22.4 Repo-copy and fallback contract for a future native renderer

A future native renderer must not turn \`alis update\` into a compiler.

Recommended contract:

\`\`\`text
repo-copy/default capability:
  committed QSB renderer available

package-manager enhanced capability:
  optional/required Alis.Surface native QML module
  wrapper exposes deterministic capability flag/import path
\`\`\`

Do not statically import an optional native module from a QML file that must also
work without it. Keep native and QSB renderer implementations in separate lazily
loaded QML files, so the fallback file can load without parsing
\`import Alis.Surface\`.

Qt plugin compatibility also matters: Qt rejects plugins built against a higher
minor Qt than the runtime's lower minor, and binary compatibility assumes a
compatible toolchain/system environment. Arch/Nix packages should therefore
rebuild the renderer as part of normal Qt package rebuilds rather than treating
the plugin as a forever-compatible copied binary.

No runtime download/build path is approved.

---

## 23. Minimum Caelestia Blob model actually needed by Alis

Current Caelestia \`blob.frag\` contains substantially more behavior than Alis
needs initially. The minimum transferable mathematical model is:

### Rounded rectangle SDF

U1 needs one rounded rectangle distance function. Per-corner radii may be kept in
the shader API for future use, but the first popup can use one radius.

Conceptually:

\`\`\`text
dRect = sdRoundedBox(pixel, center, halfSize, radius)
\`\`\`

### Circular smooth union

Caelestia currently uses a circular smooth minimum whose support is local to the
two fields:

\`\`\`text
smin(a, b, k)
\`\`\`

U1 should use the same class of operation rather than a hand-drawn shoulder.

### Inverted frame

The physical perimeter is represented as outer box minus rounded inner workspace:

\`\`\`text
dOuter = sdBox(...)
dInner = sdRoundedBox(...)
dFrame = smooth-max(dOuter, -dInner, kFrame)
\`\`\`

\`kFrame\` must be clamped to the thinnest frame side so the smooth-max fillet
cannot exceed the available border thickness.

The locked Alis Screen Edge/Bar dimensions are inputs to this frame record.
U1 does not modify \`ScreenEdges.qml\`.

### Border sink

A plain union between a popup and an inverted frame is not always sufficient to
produce the Caelestia-style owner edge yielding around the entering body.

The minimum generic sink model is:

1. for each frame side, compute how far the popup's opposite edge has penetrated
   past the frame's inner wall;
2. clamp that penetration to the physical frame thickness;
3. weight it by lateral distance from the popup extent and perpendicular proximity
   to the relevant inner wall;
4. take the maximum generic sink contribution;
5. subtract it from \`dInner\`;
6. rebuild \`dFrame\`;
7. smooth-union the popup field with the frame field.

This may use four frame-side distance calculations because the frame itself has
four sides. It must not branch on popup/module identity, source position labels or
contact-corner flags.

### Bounding/fill-rate strategy

Caelestia does not rely on a permanent full-output fragment pass. Its native
inverted frame uses explicit frame-strip geometry and regular blob shapes use
padded bounds.

The QSB U1 analogue should be:

- one full-output **window/coordinate domain**;
- one **bounded ShaderEffect item** covering only the popup plus the neighboring
  owner-frame region, expanded by smoothing/AA/shadow padding;
- pass \`effectOrigin\` so the fragment shader still evaluates in output-local
  logical coordinates;
- include a diagnostic full-output mode only for correctness/performance
  comparison.

This preserves one scenegraph/field while avoiding full-screen fill rate in the
normal PoC path.

Do not split the contact into separate corner ShaderEffects.

---

## 24. Exact isolated U1 SDF PoC specification

U1 is now sufficiently specified to implement later, but this research commit does
**not** implement it.

### 24.1 Isolation boundary

Proposed location:

\`\`\`text
scripts/unified-surface/
  U1Shell.qml
  U1Surface.qml
  U1Surface.frag
  U1Surface.qsb
  README.md
  build-shader.sh      # developer-only; optional
\`\`\`

No production module imports U1.

No changes to:

- \`modules/screenCorners/ScreenEdges.qml\`
- \`modules/bar/Bar.qml\`
- \`modules/bar/StyledPopup.qml\`
- Sidebar/Dashboard/Settings production files
- existing connected-surface helpers

### 24.2 Host contract

U1 creates one full-output, input-transparent \`PanelWindow\` on one selected
output.

Required properties:

- transparent window color;
- \`ExclusionMode.Ignore\`;
- zero-size/click-through input mask;
- persistent mapping for the lifetime of the test;
- no \`visible\` toggling while shapes animate;
- no exclusive zone;
- explicit test layer chosen at launch.

Run the same PoC separately in:

- Top mode, to reproduce the perimeter host semantics;
- Overlay mode, to validate the local popup-domain semantics.

Do not change layer dynamically in one mapped instance because that would
confound the stacking/lifetime test.

### 24.3 Registry contract used by U1

U1 may use fixed properties rather than a dynamic model. The data contract still
matches the future registry:

\`\`\`text
outputSizeLogical

frame:
  outerRect
  innerRect
  innerRadius
  sideInsets

popup:
  enabled
  rect
  radius

material:
  color
  smoothK
\`\`\`

Coordinates are output-local logical coordinates.

Not allowed:

\`\`\`text
joinTop
joinBottom
joinLeft
joinRight
leftFlare
rightFlare
contactInset
moduleName
batterySpecialCase
\`\`\`

### 24.4 Shader uniforms

Minimum U1 uniforms:

\`\`\`text
qt_Matrix
qt_Opacity

effectOrigin
effectSize
outputSize

frameOuter
frameInner
frameRadius

popupRect
popupRadius
popupEnabled

smoothK
materialColor
\`\`\`

Fragment-space output coordinate:

\`\`\`text
pixel = effectOrigin + qt_TexCoord0 * effectSize
\`\`\`

The shader owns only SDF evaluation and material output. Popup placement/clamping
remains a controller/layout concern.

### 24.5 Moving source/anchor

The first test source can be synthetic:

\`\`\`text
fake module x/y
  -> ordinary popup placement/clamp function
  -> popup output-local rect
  -> shader uniform
\`\`\`

Animate/sweep the fake module through the Bar rather than dragging inside the
input-transparent visual host.

A second U1 run may feed a real Bar module anchor through the existing
\`StyledPopup\`-style mapping semantics, but still must not replace production
popup rendering.

The renderer sees only the resulting popup rectangle. It does not know which
module produced it.

### 24.6 Bounded effect rectangle

Normal mode computes a CPU/QML bounding box from:

- popup rect;
- the adjacent frame strip needed for the field interaction;
- \`2 * smoothK\` safety padding;
- one AA pixel in physical space;
- future shadow padding when U1b is enabled.

The effect rectangle may extend to the screen corner when the popup is near an
edge. This is enough for corner topology tests without shading the entire output.

Diagnostic mode renders the same equations full-output. For identical uniforms,
pixels inside the bounded region must match the full-output reference within the
normal AA tolerance.

### 24.7 Test matrix

Required geometry cases:

| Axis | Cases |
| --- | --- |
| Horizontal Bar | top-center, top-left, top-right, bottom-center, bottom-left, bottom-right |
| Vertical Bar | left-center, left-top, left-bottom, right-center, right-top, right-bottom |
| Clamp | popup unclamped, clamped to each applicable screen side |
| Motion | slow sweep, fast sweep, opening/closing while source moves |
| Scale | 1.0, 1.25, 1.5, 1.75, 2.0 where compositor setup permits |
| Resolution | 1080p, 1440p, 4K where available |
| Shape stress | one popup, then two generic popup records in diagnostic extension |

Top/bottom/left/right variants must be produced by frame/rect data, not separate
shader source variants.

### 24.8 U1 pass/fail gates

**Topology — PASS only if all hold**

- no visible transparent seam between frame and popup during static or moving
  attachment;
- no independently drawn corrective corner/flare exists;
- moving the source changes only popup placement data and the shoulder follows;
- near-screen-edge clamping does not require a topology flag;
- top/bottom/left/right use the same shader equations;
- bounded and full-output reference renders agree inside the bounded region.

**Scale/AA — PASS only if all hold**

- no persistent 1-physical-pixel gap appears at tested fractional scales;
- semantic logical rects are not modified by AA compensation;
- AA is derived from the field derivative/\`fwidth\`, not magic offsets.

**Lifetime/input — PASS only if all hold**

- visual host intercepts no pointer/keyboard input;
- moving/opening/closing test shapes never unmaps/remaps the host;
- Top-mode test survives enter/exit fullscreen without a blank/reordered PoC host;
- Overlay-mode test remains visually above fullscreen as expected.

**Performance — PASS only if all hold**

Measure a control scene, bounded U1, and diagnostic full-output U1 under the same
refresh/resolution.

- bounded U1 creates no sustained idle animation/redraw once geometry is still;
- moving-shape p95 frame time is no more than 10% above the control scene;
- missed-frame ratio increases by no more than 1 percentage point relative to the
  control scene;
- bounded U1 must materially outperform the full-output diagnostic at 1440p/4K;
  if it does not, investigate before U2;
- any configuration that only works acceptably by leaving a permanent full-output
  shader active is not automatically eligible for production.

The relative gates are intentional: they avoid inventing an absolute GPU
millisecond budget that would be meaningless across user hardware.

**Architecture — FAIL immediately if any hold**

- shader/QML code contains module-specific contact branches;
- a contact plane is shifted solely to hide AA/compositor cracks;
- the PoC requires production \`ScreenEdges\`, Bar or \`StyledPopup\` geometry to
  change;
- runtime needs \`qsb\`, a compiler, CMake, network access or a native plugin;
- blur correctness is used to excuse an SDF topology defect.

### 24.9 U1 rollback

U1 is additive under \`scripts/unified-surface/\`. Rollback is deletion of that
directory plus its research-only launch instructions.

Because no production file references U1, rollback must leave the installed shell
byte-identical to the pre-U1 production behavior.

---

## 25. Decision gates after U1

If U1 fails field topology, stop and revise the mathematical model. Do not proceed
to registry or package work.

If U1 passes topology but fails bounded performance, investigate a minimal native
QSG renderer under the same data contract.

If U1 passes both topology and performance, proceed to U2 and test a real dynamic
shape registry before deciding whether native QSG is necessary.

Only U3 may choose the production renderer.

Production cutover still requires explicit maintainer approval and remains
separate from this research/documentation work.


---

## 26. Direction change: Abyss v2.31.0 is now the primary reference

The maintainer explicitly changed the implementation reference from Caelestia to
upstream Alis **Abyss v2.31.0**.

Primary upstream baseline:

- repository: `snowarch/Alis`
- release: `v2.31.0`
- commit: `9574fa424c0d1008e927454e933a7fbe292f9fb2`
- field source: *modules/abyss/field/AbyssField.qml*
- shader: `modules/abyss/field/AbyssField.frag`
- compiled shader: `modules/abyss/field/AbyssField.frag.qsb`
- shape attachment reference: *modules/abyss/stage/AbyssStage.qml*
- card reference: *modules/abyss/control/AbyssControlCenter.qml*
- morph/body reference: *modules/abyss/components/AbyssMorphSurface.qml*

Caelestia research remains useful historical context for the general "one field,
one silhouette" idea, but it is no longer the implementation template.

### 26.1 Why Abyss is a better Alis reference

Abyss and Alis already share the relevant runtime architecture:

- Quickshell;
- Qt Quick/QML;
- Wayland layer-shell;
- Niri;
- ShaderEffect/QSB assets;
- full-output per-screen visual windows.

Therefore the surface field can be studied and ported without translating a
native C++/QSG Blob implementation first.

### 26.2 Exact Abyss field rule

Abyss stores ordinary rounded-box bodies and combines them in one shader pass.

The shader always keeps the plain union:

```text
united = min(united, body)
```

Then, only for an explicitly declared relationship, it adds:

```text
smoothUnion(owner, child, child.fuse)
```

A body therefore melts only into the body named by its `joins` relation. It
does not automatically fuse into every nearby surface.

The polynomial smooth minimum is the upstream Abyss implementation, not a new
Alis formula.

### 26.3 Do not conflate Abyss edge pieces with Abyss cards

Two upstream mechanisms must remain distinct.

**Edge piece attachment** — `AbyssStage.meltInto()`:

```text
reach = min(width, height) / 2 + 1
field shape grows into screen/frame owner
joins = pieceEdge:<side> or frame
```

This is appropriate for a piece directly attached to a screen/frame edge.

**Card/popup attachment** — e.g. `AbyssControlCenter`:

```text
bodyRect remains the card body
placement overlaps owner by a small weld
joins = island / origin field id
fuse = fuseDeep
```

This second model is the closer analogue for Alis `StyledPopup`.

Do not apply the large edge-piece `reach` to production Bar popups merely
because it makes a visible corner.

### 26.4 Current isolated PoC

Implementation commits:

- `c2a15b9b87e5d8cb144405fc5ef8dec01126716a` —
  `research(surface): add Abyss-faithful corner PoC`
- `0a39ba386849c96248393b52ea4fd10552c57856` —
  `test(surface): lock Abyss corner morphology`

Location:

```text
scripts/abyss-corner-poc/
```

It is excluded by `sdata/runtime-exclusions.json`; no production QML imports it.

The PoC carries the **exact upstream v2.31.0** `AbyssField.frag` and
`AbyssField.frag.qsb`. The Alis wrapper only supplies a two-body field:

```text
owner
popup -> joins: "owner"
```

It supports two explicit modes:

- `card-owner` — default and relevant to `StyledPopup`;
- `edge-reach` — diagnostic reproduction of `AbyssStage.meltInto()`.

No production Bar, ScreenEdges, StyledPopup, Sidebar, Dashboard, Settings or
Waffle file is changed by the PoC.

### 26.5 Current morphology gate

The intentionally enlarged `card-owner` default uses:

```text
owner thickness = 56
popup = 380 x 300
popup radius = 48
weld = 4
fuse = 56
```

A source-level regression test recomputes the same rounded-box and polynomial
smooth-union field. The left shoulder must:

- extend roughly 31 px immediately below the owner seam;
- taper monotonically;
- be roughly 8–16 px wide at depth 8;
- converge to <= 0.6 px by depth 56.

This is designed to reject the previous failure mode where a separate-looking
blob/corner sits underneath the popup.

### 26.6 Validation status

For `c2a15b...`, the canonical CI count changed from the immediate pre-PoC
baseline:

```text
before: 107 PASS / 24 FAIL / 2 SKIP
after:  108 PASS / 24 FAIL / 2 SKIP
```

The new Abyss PoC contract passed. The existing 24 failures were not introduced
by the PoC. Nix package validation also passed.

Live desktop/GPU appearance is still required before any production cutover.

### 26.7 Production boundary remains strict

Until live inspection accepts the PoC:

- do not modify `StyledPopup.qml`;
- do not modify Bar/ScreenEdges geometry;
- do not restore U1 border-sink/cornerFill/contact-plane experiments;
- do not add Canvas/flare correction geometry;
- do not touch Waffle;
- keep the immutable ii `SurfaceMotion` slide-only contract.

If the PoC looks wrong, revise or discard only `scripts/abyss-corner-poc/`.

If the `card-owner` silhouette is accepted, the next production experiment is
an **ii-only** field-backed popup background that reuses existing anchor/content
lifecycle while feeding generic owner/popup body records to an Abyss-style field.


### 26.8 Calibrated profiles, matrix harness and ABI lock

Additional PoC commits:

- `ff54e4b47578e271271bd023d9a39e4793213c62` —
  `test(surface): add live Abyss corner matrix capture`
- `b50f93f8eed288c42faf9b6c90296a6ef93b7c32` —
  `research(surface): add calibrated Abyss corner profiles`
- `204ece1d96d117d49371a0ed6a2399635dfa757d` —
  `test(surface): lock Abyss field shader ABI`

The default **diagnostic** profile is deliberately enlarged for visual review:

```text
owner thickness 56
popup           380 x 300
radius          48
fuse            56
weld            4
```

The **upstream-relative** profile follows Abyss v2.31 defaults more closely:

```text
owner thickness 42
popup           360 x 300
radius          30
fuseDeep        30
weld            3
```

Those upstream-relative values are grounded in
*modules/abyss/style/AbyssStyle.qml*:

- `radiusPanel = corner(30)`;
- `fuseDeep = 30 * density * meltDepth` at default factors;
- `weld = 3 * density`;
- default Bar height is 42.

The source contract recomputes the polynomial smooth-union contour for both
profiles. The diagnostic profile must have a large, monotonic shoulder that
converges to the popup side; the upstream-relative profile must preserve the
same topology at the smaller upstream-scale values.

The live matrix harness:

```text
scripts/abyss-corner-poc/capture-matrix.sh
```

captures all twelve required cases:

```text
top / bottom / left / right
x
sourceT 0.02 / 0.50 / 0.98
```

Each case launches only the isolated PoC, waits for the
`ALIS_ABYSS_POC` readiness marker, captures with `grim`, and terminates that
exact PoC process. It does not restart/reload/IPC-call the running Alis shell.

The exact upstream v2.31 `AbyssField.frag.qsb` ABI is now guarded. The wrapper
must provide all twenty shape uniforms, five blocks each for radii/fuse/join/
also/paints/glass, plus viewport/screen/field/material and backdrop uniforms.

The PoC intentionally keeps `paintsA..E = 0`: in Abyss v2.31 the shader comments
and implementation state that paints flags no longer alter union topology/fill;
they are retained for QML-side shadow ownership. The PoC has no shadow/material
migration, so this is deliberate.

### 26.9 Current live acceptance gate

Do not begin production integration before the live matrix is visually reviewed.

First capture the enlarged topology:

```sh
ALIS_ABYSS_POC_PROFILE=diagnostic \
scripts/abyss-corner-poc/capture-matrix.sh
```

On a multi-output session, select the target explicitly:

```sh
ALIS_ABYSS_POC_OUTPUT=<output-name> \
ALIS_ABYSS_POC_PROFILE=diagnostic \
scripts/abyss-corner-poc/capture-matrix.sh
```

Then capture the upstream-scale comparison:

```sh
ALIS_ABYSS_POC_PROFILE=upstream-relative \
scripts/abyss-corner-poc/capture-matrix.sh
```

PASS requires the contact sheet to show, for every edge and clamp extreme:

1. the junction curve reads as part of one owner/popup silhouette;
2. no separate-looking blob sits under/behind the popup;
3. the two shoulders taper into the popup sides rather than floating away;
4. clamping near output corners does not require a corner-specific branch;
5. the smaller upstream-relative profile preserves the same topology.

If any case fails, revise/revert only `scripts/abyss-corner-poc/`. Do not patch
production `StyledPopup`, Bar, ScreenEdges or Waffle.

### 26.10 Focused live evidence and multi-owner corner coverage

The first 12-case harness still made the actual 30–56 px fillet small inside a
full-output screenshot. Two additional developer-only commits tighten the live
acceptance gate without touching production:

- `e7700ea31c5ff07edda001ef0f00674e33f217c0` —
  `test(surface): add focused Abyss contact captures`
- `f72af8b8407e796eb117402d1057da47f257aa9d` —
  `test(surface): cover Abyss corner multi-owner joins`

Each live case now persists a plain-number `ALIS_ABYSS_POC` JSON record with
the selected output's layout origin/size and the semantic popup geometry. The
harness keeps the full-output PNG and also asks `grim -g` for a focused
junction crop in compositor layout coordinates. This deliberately avoids using
Qt `devicePixelRatio` as a compositor-scale proxy.

The previous two-body PoC was sufficient for a centered Bar/popup junction but
did not prove the actual Alis corner case: a popup can be attached to its
primary Bar/owner **and** reach a perpendicular physical Screen Edge.

The isolated field therefore now contains four ordinary records:

```text
owner                 # primary Bar/attachment owner
frame-start           # perpendicular Screen Edge at tangent start
frame-end             # perpendicular Screen Edge at tangent end
popup
```

The popup relationship is geometry-derived and uses the existing two Abyss QSB
join slots:

```text
center:        joins = ["owner"]
start clamp:   joins = ["owner", "frame-start"]
end clamp:     joins = ["owner", "frame-end"]
```

There is still no module identity, corner flag, Canvas flare, `RoundCorner`,
`contactInset`, contact plane or border-sink helper. The tangent frame bodies
are real field owners. The default Alis Screen Edge thickness used by the PoC
is 10 logical px and may be overridden only as a geometry input with
`ALIS_ABYSS_POC_FRAME_THICKNESS`.

This matters for production planning because current `StyledPopup` already
derives adjacent Screen Edge attachment from resting body geometry. A future
field-backed paint path must preserve that generic geometry behavior rather
than replace it with per-popup corner choices.

Source-side validation after the multi-owner change:

```text
scripts/test-abyss-corner-poc-contract.py  PASS
canonical validator                       115 PASS / 22 FAIL / 2 SKIP
Nix package                               PASS
```

The 22 canonical failures are the same baseline count as the immediate
pre-change revision. They are not introduced by the PoC. Live GPU appearance is
still unproven and remains the hard gate.

The matrix output now includes both:

```text
contact-sheet-card-owner-<profile>.png
detail-sheet-card-owner-<profile>.png
```

For `sourceT=0.50`, visually inspect the single primary-owner join. For
`sourceT=0.02` and `0.98`, inspect the **two-owner** corner: the primary join
and perpendicular Screen Edge must read as one continuous silhouette without a
separate blob or hand-drawn corner.

Production `StyledPopup`, `ConnectedSurfaceFrame`, Bar, ScreenEdges and Waffle
remain unchanged by these commits.

### 26.11 Production composition-domain finding — upstream one field, Alis split layers

A follow-up source audit of exact upstream
`snowarch/Alis@9574fa424c0d1008e927454e933a7fbe292f9fb2` found an
architectural precondition that the morphology PoC does not model by itself.

Upstream Abyss does **not** ask a popup field in one window to visually weld to
an owner painted by another window. In *AbyssBar.qml*, one full-output
`barWindow` builds a single `fieldShapes` registry by concatenating the
Island, Control Center, Stage/cards, edit surfaces and Dock bodies, then gives
that registry to one `AbyssField`. Control Center/cards publish their rounded
body records into that same field and join an owner record there. The owner and
the joined card therefore share both the output-local coordinate system and the
paint/composition domain.

Alis production currently has a different ownership boundary:

```text
Bar / ScreenEdges        Top-layer surfaces
StyledPopup              separate full-output Overlay surface
```

`StyledPopup` already derives anchor/body placement and tangent Screen Edge
contact from geometry, but its current `ConnectedSurfaceFrame` paints only the
popup-side presentation. The isolated Abyss PoC, by contrast, paints the primary
owner, tangent frame owners and popup together inside its one Overlay field.

Therefore a direct copy of the PoC field wrapper into `StyledPopup` is **not**
an approved production design. The full owner/frame records would enlarge the
field paint bounds and could repaint the Bar or physical Screen Edge in the
Overlay surface, double-painting their material and potentially covering Bar
content or changing physical-edge shadow/effect ownership.

This does not invalidate the current morphology gate. The existing diagnostic
and upstream-relative matrices still answer the first question: does the exact
Abyss SDF/join model produce the desired connected silhouette?

If that gate passes, add a second isolated composition experiment before any
production cutover. Its purpose is to preserve the owner records as **field
math/join participants** without making the popup Overlay repaint the complete
owners. The candidate design to test is:

```text
output-local shape registry
  owner
  optional tangent frame owner
  popup
        |
        +-- exact Abyss SDF/join math
        |
        +-- popup/junction-limited paint viewport
             + existing attachment-boundary reveal/clip
             + existing popup content/input lifecycle
```

The paint viewport/scissor is a renderer-composition boundary, not a
corner-selection mechanism: shape records remain generic and geometry-derived.
A production-style PoC may expose an explicit `paintBounds`/viewport override
while keeping the owner records in full output-local coordinates. The tangent
Screen Edge should likewise participate in the SDF join without repainting the
entire persistent physical edge.

Gate order is now:

1. **G1 — morphology:** run and visually accept both existing 12-case
   `card-owner` matrices on the real Wayland/Niri/GPU session.
2. **G2 — split composition:** only after G1 passes, use an isolated
   developer-only PoC to reproduce Alis' actual owner/popup composition
   boundary and verify that a local Overlay field can use owner geometry without
   duplicate owner paint.
3. Only after G2 acceptance may production integration design advance to a
   `StyledPopup` cutover experiment.

G2 must explicitly verify no Bar-module occlusion, no duplicate Bar/Screen Edge
material, no physical-edge shadow discontinuity, all four attachment edges,
both tangent clamps, slide-under open/close, input/focus preservation and
fractional-scale behavior.

Do not solve this boundary by moving Bar/ScreenEdges, changing their geometry,
adding same-layer helper windows, restoring corner-specific flags, or touching
Waffle. If a local paint viewport cannot preserve the Abyss morphology, keep the
experiment isolated and research another composition strategy.

### 26.12 Shader viewport feasibility — math owners do not require full-owner paint bounds

The exact committed Abyss v2.31 shader provides a source-side answer to the
composition question above. `AbyssField.frag` reconstructs the output-space
sample position as:

```glsl
vec2 p = u.viewport.xy + qt_TexCoord0 * max(u.viewport.zw, vec2(1.0));
```

Every `shapeN` record remains expressed in screen/output pixels. The shader then
evaluates every rounded-box body and explicit join against that output-space
`p`. Therefore the shader math does **not** require the pass viewport to equal
the union of all owner bounds.

Upstream *AbyssField.qml* currently derives `pass.x/y/width/height` from the
union of all shapes as its normal render-bounds policy. That is an upstream
wrapper choice/optimization, not a coordinate-system requirement of the QSB.

This confirms a concrete G2 experiment is possible without shortening owner
records or introducing corner-specific geometry:

```text
full output-local owner records
+ full output-local popup record
+ exact join indices / fuse
              |
              v
small ShaderEffect viewport around popup + junction
```

The local viewport must still include the complete possible smooth-union
shoulder plus antialiasing reach. It also has to follow the animated popup during
the 300 ms slide so no shoulder is clipped mid-motion. Those bounds must be
derived from generic geometry and fuse, not from edge/module names.

Alis already has a compatible clipping primitive for the other half of this
problem: `ConnectedSurfaceRevealClip` keeps children in full-output
coordinates and clips them at the resting attachment boundary. A G2 PoC can
therefore test a field pass with output-local shapes, local paint bounds and the
existing slide-under reveal semantics without moving the production Bar or
ScreenEdges.

Two contracts remain intentionally unresolved until that isolated experiment:

- **input:** `Region` cannot consume shader alpha. The current
  `ConnectedSurfaceMask` includes Bézier-connector strip approximations that
  belong to the old flare renderer. Do not silently carry those strips into the
  final Abyss cutover. G2 must determine the minimum generic input/hover region
  needed for body interaction and Bar-to-popup pointer transfer.
- **shadow:** the Abyss field shader itself does not replace Alis' popup
  free-side shadow ownership. G2 must prove a popup-only shadow path that does
  not repaint or shadow the Top-layer Bar/Screen Edge and does not require the
  obsolete flare renderer to remain underneath.

These are composition/input/effect gates, not reasons to alter G1. The existing
live morphology matrix remains the next action.

### 26.13 Live crop coordinate chain and artifact provenance

The focused `grim -g` crop path has now been checked end-to-end against the
upstream coordinate contracts instead of relying on DPR intuition.

Quickshell's current `QuickshellScreenInfo` implementation exposes
`ShellScreen.x/y` directly from `QScreen::geometry().x/y()`, and
`ShellScreen.width/height` from `QScreen::size()`. Qt's High DPI contract
states that window and screen geometry are reported in device-independent
coordinates. Niri likewise defines output placement and output size in logical
(scaled) pixels. Finally, grim documents `-g` as accepting compositor
**layout coordinates** and specifically uses xdg-output logical geometry when
available.

The current focused-crop construction is therefore the correct coordinate
chain for Niri/Wayland:

```text
ShellScreen.x/y        # output origin in logical/global layout space
+
popup geometry         # output-local Qt logical coordinates
=
grim -g geometry       # compositor layout coordinates
```

Do **not** multiply the crop by `devicePixelRatio`. DPR controls raster density
and can differ from the compositor's logical layout scale; applying it here
would move/resize the requested layout region instead of merely increasing
capture pixels.

The live harness was hardened in two source-only commits after this audit:

- `1d67202d9b54c626779956ef991ae4454a93859c` —
  `test(surface): preserve Abyss matrix provenance`
- `1d5a4c0cf80d19b437c1732a4fecb7eb6b7f4f48` —
  `test(surface): validate Abyss capture labels`

The first prevents the second G1 profile run from overwriting the first run's
manifest. Artifacts are now profile-specific:

```text
manifest-card-owner-diagnostic.tsv
session-card-owner-diagnostic.json
manifest-card-owner-upstream-relative.tsv
session-card-owner-upstream-relative.json
```

The session JSON records the requested profile/mode, Quickshell/grim executable
paths, Wayland display and the explicit coordinate-space rule
`compositor-layout-logical` with DPR crop application disabled.

The second commit rejects unknown `ALIS_ABYSS_POC_MODE` or
`ALIS_ABYSS_POC_PROFILE` values. Previously the QML window would correctly
fall back to `card-owner` / `diagnostic` while the shell harness kept the
invalid environment string in filenames and manifest labels, which could create
mislabelled visual evidence.

These harness changes do not alter SDF math, shape geometry, joins, fuse,
Screen Edge ownership or production runtime.

No live GPU matrix was executed from the repository-only audit environment, so
G1 remains **UNPROVEN**. Also do not carry forward the older source-side PASS
count as proof for the two harness commits without rerunning the contract on the
maintainer machine.

The next local sequence should therefore begin with:

```sh
python3 scripts/test-abyss-corner-poc-contract.py

ALIS_ABYSS_POC_OUTPUT=<output-name> \
ALIS_ABYSS_POC_PROFILE=diagnostic \
scripts/abyss-corner-poc/capture-matrix.sh

ALIS_ABYSS_POC_OUTPUT=<output-name> \
ALIS_ABYSS_POC_PROFILE=upstream-relative \
scripts/abyss-corner-poc/capture-matrix.sh
```

Review the two `detail-sheet-card-owner-*.png` files and their matching
profile-specific manifests/session metadata before any G2 work.

### 26.14 One-command G1 evidence bundle

To reduce operator error during the real-session gate, commit
`6211d6fbd6fed92a93ff92d935b84d32d400184f`
(`test(surface): bundle Abyss G1 evidence run`) adds:

```text
scripts/abyss-corner-poc/capture-g1.sh
```

This wrapper is developer-only and runtime-excluded with the rest of the PoC.
It does not change any SDF, geometry or production code.

The wrapper deliberately makes the acceptance sequence stricter:

1. G1 is forced to `card-owner`; an `edge-reach` request is rejected.
2. The source contract runs before any screenshot is taken.
3. Both required profiles run in order:
   `diagnostic`, then `upstream-relative`.
4. Unless the maintainer explicitly sets `ALIS_ABYSS_POC_CAPTURE_DIR`, one
   timestamped directory contains the complete paired attempt.
5. `g1-run.txt` records the actual checkout HEAD, requested output, mode and
   profile pair, so later review cannot accidentally mix artifacts from
   different source revisions.

The preferred live command is now:

```sh
ALIS_ABYSS_POC_OUTPUT=<output-name> \
scripts/abyss-corner-poc/capture-g1.sh
```

The resulting evidence directory should contain both detail sheets, both
profile-specific manifests, both profile-specific session JSON files, all 24
full/focused PNG pairs' case artifacts, and `g1-run.txt`.

G1 remains unproven until this wrapper is run on the maintainer's actual
Wayland/Niri/GPU session and the detail sheets are visually accepted. Do not
start G2 merely because the wrapper or static contract succeeds.

### 26.15 G1 evidence integrity verifier

Commit `a4c7263160c52583d5718222593b796fc6b5356a`
(`test(surface): verify Abyss G1 evidence integrity`) adds a structural verifier:

```text
scripts/abyss-corner-poc/verify-g1-evidence.py
```

The G1 wrapper now runs it automatically after both profile matrices.

The verifier is intentionally narrower than visual acceptance. It proves that a
candidate evidence directory is internally coherent before a maintainer judges
the pixels. It checks:

- `g1-run.txt` exists and records a full 40-character source SHA;
- both `card-owner` manifests and session JSON files exist;
- each profile has exactly 12 unique edge/source cases;
- every referenced full PNG, focused PNG, metadata JSON and log exists;
- mode/profile labels agree between manifest and metadata;
- all cases in a profile target one output, and both profiles target the same
  output;
- profile radius/fuse/weld metadata matches the locked diagnostic or
  upstream-relative values;
- `sourceT=0.50` reports exactly `["owner"]`;
- `sourceT=0.02` reports `["owner", "frame-start"]`;
- `sourceT=0.98` reports `["owner", "frame-end"]`;
- tangent-start/end flags match those joins;
- session metadata keeps `compositor-layout-logical` detail crops with DPR
  explicitly disabled.

The verifier prints:

```text
G1 evidence structure: PASS
```

only for structural/provenance integrity. It then explicitly states that visual
morphology is **not** auto-approved. Missing ImageMagick detail sheets produce a
warning rather than a structural failure because all 12 individual focused
captures still exist.

`capture-matrix.sh` also canonicalizes its capture directory to an absolute
path before writing manifests. This makes manifest file references portable
across later review shells instead of depending on the capture process' working
directory.

A repository-side mirror of the static source assertions after this commit
found no failures, including the locked morphology values and 16,765-byte QSB
size. This still does not replace running the actual Python contract and live G1
wrapper on the maintainer desktop.

The remaining hard boundary is unchanged: **no G2 and no production cutover
until the live images themselves pass review.**


### 26.16 G1 source/evidence freshness lock

A final provenance audit found two cases that could make otherwise complete
evidence ambiguous: a locally modified G1 source scope could still share the
same recorded `repo_head`, and reusing a custom capture directory could leave
an older detail sheet behind.

The wrapper now refuses both conditions. Before the static contract or any
screenshot, it requires a new/empty evidence directory and a clean scoped set of
PoC/contract/runtime-exclusion files. It does not require the entire Alis
working tree to be clean, so unrelated development remains unaffected.

The run manifest now adds:

- `poc_tree_sha`;
- `contract_blob_sha`;
- `runtime_exclusions_blob_sha`;
- `source_scope_clean=true`;
- `evidence_dir_was_empty=true`.

The verifier requires these fields to be valid and also checks that each
profile's session `requestedOutput` agrees with `g1-run.txt`, and that a
non-empty requested output is the one actually rendered.

This is still harness hardening only. It does not change production geometry,
does not touch Waffle, and does not unlock G2 without a live visual PASS.


### 26.17 Live G1 exposed a pre-layout readiness race

The maintainer's first actual Wayland/Niri/GPU run produced all 24 captures but
failed the structural verifier at `top / 0.50 / diagnostic`: the saved metadata
contained `joins=["owner","frame-start"]` instead of the center-case
`["owner"]`.

The failure path is deterministic from the PoC lifecycle. The old readiness
payload was emitted directly in `Component.onCompleted`. A layer-shell
`PanelWindow` can complete QML construction before its anchored full-output
geometry has settled. During that transient state the source-position formula
can clamp `semanticPopup.x/y` to `tangentInset`, which makes
`atTangentStart` true. The capture harness then waited for that early marker,
slept for its warmup, and captured pixels later. Therefore the persisted
metadata—and the focused `grim -g` crop derived from it—could describe a
different geometry state from the actual screenshot.

This attempt cannot be used to decide morphology in either direction.

The fix changes readiness semantics, not field geometry:

- no readiness marker is emitted from `Component.onCompleted`;
- a 50 ms repeating probe waits until the PoC window dimensions match the
  selected `ShellScreen` dimensions;
- the dimensions must remain unchanged for at least three consecutive probes;
- the one-shot readiness payload then records `screenWidth`, `screenHeight`,
  `geometryStable` and `readinessStableTicks`;
- structural verification requires stable geometry and equality between the
  captured output dimensions and the screen dimensions.

No shader, fuse, weld, radius, join policy or production surface changed. G1
therefore remains pending a fresh complete live run.


### 26.18 G1 accepted; G2 split-composition implementation

The real Niri evidence directory
`g1-20260920T150214Z` passed the structural verifier on `eDP-1`, and both
focused profile sheets were visually accepted. G1 is therefore closed.

G2 now tests the actual Alis layer split rather than another same-window
field:

```text
Top owner window
  primary Bar/owner
  perpendicular Screen Edge owners
  fake owner module

Overlay popup window
  full owner/frame/popup SDF records
  local ShaderEffect raster viewport
  popup content/input/shadow
```

The important implementation result is that a rectangular local raster viewport
is sufficient only after clipping **both classes of external owner**. Clipping
just at the primary attachment seam prevents Bar repaint, but a clamp case would
still rasterize the perpendicular `frame-start` / `frame-end` strip because
that owner shape extends across the output.

The corrected G2 viewport therefore applies two independent generic half-plane
constraints:

1. primary attachment seam: never rasterize into the Bar/primary-owner side;
2. tangent clamp boundary: when the popup joins a perpendicular physical edge,
   never rasterize into that frame strip.

The owner records remain present in the exact Abyss SDF calculation, so the
smooth-union fillet immediately **outside** each external owner is preserved.
Only pixels already owned and painted by the Top domain are excluded from the
Overlay raster.

The popup input proxy uses the same owner exclusions. Shadow is still a
separate rectangular production-compatible path: the attached side is clipped,
and a tangent side is also clipped when that physical edge is joined.

Cross-axis field bounds deliberately expand only by AA reach, not fuse reach.
Fuse expansion is tangent-only. This avoids a closing popup leaving a visible
smooth-union tail after its full body has slid underneath the owner.

The G2 live matrix is 24 cases:

```text
4 edges x 3 source positions x progress {1.00, 0.55}
```

Structural verification checks layer ownership, join labels, pure slide
translation, local paint-area ratio, primary/tangent owner exclusion, body-only
input, shadow suppression and provenance. Visual acceptance still remains
mandatory before production cutover.


### 26.19 G2 live finding: RectangularShadow needs texture isolation

The first 24-case G2 live run structurally passed but exposed a visual failure:
direct `RectangularShadow` clipping is not a sufficient ownership boundary for
split composition. A narrow black blur tongue remained visible over Top-layer
external-owner strips.

This is consistent with the renderer model: RectangularShadow's effective
material extends outside its nominal Item by blur/spread reach. Tracking only
the nominal parent clip rectangle can therefore prove the intended bounds
without proving that the effect's final pixels respect them.

The revised G2 path makes the ownership boundary explicit in the rendered
artifact:

```text
complete rounded shadow
  -> bounded private texture
  -> external-owner-clipped sourceRect
  -> Overlay scene
```

The same `clipExternalOwners(rect)` function now governs three independent
Overlay domains:

- Abyss field raster bounds;
- pointer input body bounds;
- displayed shadow texture bounds.

This removes duplicated half-plane logic and prevents future divergence between
visual paint, hit testing and shadow ownership. It is a composition fix, not a
new corner/flare geometry path.

The new verifier requires `shadowIsolation=texture-source-rect`, records the
displayed shadow rect, and checks that it cannot enter either the primary owner
or a joined perpendicular Screen Edge. Live visual revalidation remains the
gate.


### 26.20 G2 standalone shader packaging failure

The second live split-composition sheet made a separate failure visible: there
was no yellow Abyss field at all. Only the Top fake owner, cyan semantic outline,
dark shadow and regular Overlay content were present. Desktop pixels remained
visible through the popup body.

This invalidates the prior assumption that a structural geometry PASS implied
the field renderer had participated.

The G2 runner uses its own directory as the Quickshell config root. A relative
shader URL escaping that root (`../AbyssField.frag.qsb`) is not a valid
standalone packaging contract. G2 now packages the locked QSB inside its own
config root. It is not a rebuilt or modified shader: Git stores the local G2
asset with the same blob SHA as the locked G1/upstream QSB.

The live contract now also consumes `ShaderEffect.status` and `log`.
Readiness cannot be emitted until the field reports `ShaderEffect.Compiled`,
and the verifier rejects shader errors/warnings before considering geometry.

This separates three independent G2 conditions that must all pass:

1. shader asset is actually loaded/renderable;
2. field/input/shadow respect external-owner composition boundaries;
3. the resulting live morphology is visually coherent.

No production cutover is authorized until all three pass in one fresh matrix.


### 26.21 G2 accepted and production StyledPopup cutover

The final G2 matrix is accepted. Unlike the earlier structurally valid but
shader-transparent attempts, the accepted evidence visibly renders the Abyss
field while preserving split-composition ownership.

Production reuses that architecture directly: full output-local owner records
remain in SDF math; a local owner-clipped viewport controls Overlay paint; the
popup shadow is isolated through a clipped private texture; input is body-only;
and the existing reveal/content lifecycle remains slide-only.

A post-cutover parity audit found one important morphology detail that the first
production translation had omitted: accepted G2 used `fuse = 30` and
`weld = 3`. Production now carries both as explicit perimeter tokens.
`ConnectedSurfaceGeometry.seamOverlap` supplies the primary-owner weld and the
tangent screen margin becomes `screenEdgeThickness - abyssWeldDepth`; the Abyss
frame still clips paint/shadow/input at the real owner boundary. This preserves
the validated SDF relation without repainting or stealing input from the owner.

The exact production shader/QSB remains byte-identical to the locked G1/G2
asset. Canvas flare and connector-strip input geometry are intentionally absent
from ii `StyledPopup`; those primitives remain only for Waffle/non-cutover
surfaces.

Production live acceptance is the only remaining gate.
