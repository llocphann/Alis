# Connected Surfaces

Material II uses a shared connected-surface presentation layer, not the retired full `iiPerimeter` composition runtime. Abyss owns a separate continuous liquid perimeter; Waffle remains a separate supported family.

## Authoritative renderers

ii Bar popouts use:

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

Existing feature-owned bodies that attach directly to Screen Edge use
`ConnectedSurfaceAbyssEdgeSurface.qml`. It adapts an already-laid-out body into
the same Abyss field, welds only the SDF record under the owner with
`abyssWeldDepth`, and clips field/shadow pixels at the real owner boundary.
Sidebar, Dashboard, Settings and Dock use this adapter.

ii Bar popup, Dock, Sidebar and Dashboard shadows share the public Screen Edge
shadow controls (`appearance.screenEdge.physicalShadow`) and raw Material
`m3shadow` ink. This keeps connected-edge depth visually aligned with the
physical perimeter while the existing owner clip prevents shadow from painting
across Bar/Screen Edge pixels. Connected Settings uses the same physical
elevation controls; the standalone OSK retains its independent legacy
shadow owner.

The old standalone corner/wedge painters are retired and must remain absent:

- `ConnectedSurfaceJoinFlares`;
- `PerimeterCornerShadow`;
- `RoundCorner`;
- the `joinFlareRadius` / `joinFlareCrossScale` token family;
- fake screen-rounding paint in `ScreenCorners.qml`.

Waffle/non-cutover surfaces may still use `ConnectedSurfaceFrame` and
`ConnectedSurfaceMask`, but that frame no longer paints endpoint wedges.
Search and OSK likewise keep direct square joined edges until explicitly moved to
an Abyss adapter.

## Screen Edge ownership

For Material II, `modules/screenCorners/ScreenEdges.qml` is the only physical Screen Edge
renderer. Its output ownership and locked rounded-workspace geometry are unchanged by Abyss. Each output
has one full-screen `FrameWindow`, one primary `ScreenEdgeField` analytic SDF painter, and transparent
reservation windows. Bar ownership changes only the matching inner-frame inset. The analytic field paints
the physical frame and inward elevation in one texture-free fragment pass; it does not allocate the former
offscreen Shape/MultiEffect shadow chain. The historical odd-even `ShapePath`, four circular `PathArc`
segments and `MultiEffect` remain inside a lazy loader only for `ShaderEffect.Error` recovery and are
not constructed on the healthy path. Do not add a Bar-local shadow or another Screen Edge painter.

Transparent Material surfaces still use independent Material shadow ink:
surface alpha must never turn `Appearance.colors.colShadow` transparent.
Connected Abyss elevation is derived from a second viewport of the same
locked SDF field as the visible body, then blurred and texture-cropped to
the real owner boundary. The shadow mask includes the smooth-union fillets;
a separate rectangular body shadow does not. Screen Edge retains its own
physical frame shadow, and Dashboard cards draw their elevation outside the
card content clip.

`ScreenCorners.qml` is interaction-only: Sidebar hot corners, Orbit,
bottom-left Quick Notes and brightness/volume gestures. Quick Notes attaches a
lazy `StyledPopup` to the physical corner, follows the same Bar-vs-Screen Edge
owner thickness (including auto-hide handoff), and does not add Screen Edge
paint. `ScreenCorners.qml` must not paint fake rounded corners.

## Sidebar contract

`SidebarHost.qml` owns left/right placement and lifecycle. The content body
starts at the inner Screen Edge boundary; `ConnectedSurfaceAbyssEdgeSurface`
owns the joined field. During close, `hiddenTranslateDistance` moves the body
past the complete native host plus Abyss/shadow overflow so neither body nor
field can remain visible as a sliver.

## Dashboard and Settings

Bottom-connected Dashboard and Settings surfaces use
`ConnectedSurfaceAbyssEdgeSurface` with the real Screen Edge/Bar owner
thickness. Their local body rectangles are transparent while the Abyss field owns
the visible fill and shadow. No full-overlay wedge/flare helper is allowed.

## Contributor rules

- preserve `StyledPopup.qml` as the normal ii Bar-popout entry point;
- use the existing Abyss adapter for Material curved connected contact; do not recreate Canvas/Shape wedge patches;
- keep Material's physical Screen Edge renderer separate from its Overlay surfaces;
- preserve output ownership, slide/retract lifecycle, focus and click-through input;
- keep Waffle supported without reintroducing legacy corner painters;
- do not reintroduce `modules/perimeter/`, `iiPerimeter`, cutover registries or feature-slot composition.

Static contracts do not replace live Niri acceptance at left/right/top/bottom
attachment and fractional scaling.

## Abyss ownership

`AbyssPerimeter.qml` is the sole Abyss painter per output. The root unloads Material/Waffle compositions before selecting it. `AbyssGeometry.js` subtracts a rounded workspace opening from the screen and supplies edge-attached deformation records. One original `AbyssField.frag.qsb` smooth-unions those records, then paints the final fill/rim/shadow once. Abyss does not use the Abyss Island field, separate panel backgrounds or corner patches.

The visual layer-shell host stays mapped on Top in default fullscreen mode, with empty input and no paint when suppressed. Explicit visible-in-fullscreen uses Overlay while still releasing reservations. Bar and pinned dock reserve only persistent depth on their own edge through transparent, input-free windows; auto-hide reserves only the thin perimeter. Sidebars, popups and transient content reserve zero space.

Input is the union of ready, open content rectangles and thin reveal triggers. The workspace opening is excluded. Closing drops input/focus eligibility before motion finishes; unsupported or uncompiled paint accepts no content input. Notification/OSD placement and output selection use the same stale-safe output policy. Perpendicular panels avoid overlapping content and sealed corner pockets, including throughout retraction.

The renderer has no time uniform, recurring animation or per-module effect pass. A static wallpaper texture is optional, bounded and disabled by Performance mode. See [Abyss evidence](ABYSS.md) for tested geometry, visual captures and remaining environment acceptance.
