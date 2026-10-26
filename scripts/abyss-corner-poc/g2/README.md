# Abyss G2 split-composition PoC

Developer-only continuation of the accepted G1 field morphology. This directory
is beneath `scripts/abyss-corner-poc/`, which is excluded from the installed
runtime. It does not modify StyledPopup, Bar, ScreenEdges or Waffle.

## Gate being tested

Alis production owners and popups live in different layer-shell domains:

- owner: Top (Bar / physical Screen Edge);
- popup: Overlay (StyledPopup).

G2 reproduces that split with two real PanelWindows. The Overlay field receives
full output-local owner + frame + popup shape records, but its ShaderEffect
raster viewport is clipped to the inward popup/junction side of the attachment
seam.

The important invariant is:

```text
owner records participate in SDF distance/join math
!=
owner pixels are painted again in Overlay
```

The field paint rectangle can expand by fuse reach along the tangent axis, but
never crosses the primary owner seam on the attachment axis. At a clamp extreme
it is also clipped to the **inner boundary of the perpendicular physical Screen
Edge**, so the frame record influences SDF join math without repainting the
frame strip in Overlay. Cross-axis expansion is AA-only. This also makes
progress=0 disappear fully underneath the owner instead of leaving a smooth-
union tail.

A fake dark owner module with a green outline is drawn in the Top window. It
must remain intact while the yellow Overlay popup joins below/beside it.

## One-command live gate

Run on the real Wayland/Niri session:

```sh
ALIS_ABYSS_G2_OUTPUT=<output-name> \
scripts/abyss-corner-poc/g2/capture-g2.sh
```

The matrix is:

```text
top / bottom / left / right
x sourceT 0.02 / 0.50 / 0.98
x progress 1.00 / 0.55
= 24 cases
```

The run creates two focused sheets:

- `detail-sheet-progress-1p00.png`
- `detail-sheet-progress-0p55.png`

and then runs `verify-g2-evidence.py`.

Structural PASS proves:

- all 24 cases exist and target one output;
- Top owner + Overlay popup split is reported;
- exact center/start/end joins are preserved;
- the ShaderEffect paint bounds never cross into owner pixels;
- paint area remains local rather than full-output;
- mid-slide translation is the expected slide-only offset;
- input region is only the visible popup body and stays inward of the owner;
- attached/tangent-joined shadow sides are suppressed;
- keyboard focus is not captured by the PoC.

Structural PASS is not visual PASS. Inspect both sheets for:

1. one coherent Abyss shoulder at the seam;
2. fake owner module never covered by Overlay material;
3. no duplicate owner/frame tint;
4. no shadow drawn across the owner or tangent physical edge;
5. symmetric top/bottom/left/right and both clamp extremes;
6. progress 0.55 remains a pure cross-axis slide with unchanged body size.

Production cutover remains blocked until this live matrix is accepted.


### First live matrix finding

The first real Niri matrix structurally passed, but visual review rejected its
shadow path. The field/input scissor was correct; however the direct
`RectangularShadow` subtree still exposed a narrow black blur tongue over the
yellow external-owner strips, most clearly on left/right and tangent-clamped
cases.

That is a G2 failure, not an accepted cosmetic difference. The revised PoC
renders the complete RectangularShadow into a bounded private
`ShaderEffectSource`, then displays only an external-owner-clipped
`sourceRect`. The Abyss field geometry is unchanged. Re-run the same 24-case
matrix; owner strips must remain completely untouched while free-side shadow
remains visible.
