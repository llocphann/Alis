# Abyss Corner PoC for Alis ii

Developer-only visual research. This directory is excluded from the installed
Alis runtime and **does not modify ii production surfaces or Waffle**.

## Reference implementation

The field shader source and compiled QSB in this directory are copied from:

- upstream: `snowarch/Alis`
- release: `v2.31.0`
- commit: `9574fa424c0d1008e927454e933a7fbe292f9fb2`
- source: `modules/abyss/field/AbyssField.frag`
- QSB upstream Git blob: `1dc24922099d00d255b8e78c234d889f7220e616`
- license: GPL-3.0

Alis is also GPL-3.0. The QML wrapper/harness is a reduced Alis research
adaptation; the shader source and QSB are kept verbatim so the first visual test
uses Abyss's actual field math rather than a reimplementation.

## What is being tested

The PoC uses ordinary Abyss field bodies only:

```text
primary owner
tangent Screen Edge start
tangent Screen Edge end
popup -> joins: ["owner"] at center
      -> joins: ["owner", "frame-start|frame-end"] at a clamp extreme
```

The tangent owners are important: Alis popups can meet both their Bar/owner
edge and a perpendicular physical Screen Edge near an output corner. The
upstream QSB already exposes two explicit join slots, so this case must be
tested as one field instead of reintroducing a separately drawn corner.

The upstream shader evaluates rounded-box SDFs, keeps the plain union, then adds
a polynomial smooth-union fillet only for explicit joins.

Two geometry modes are intentionally kept separate:

### `card-owner` (default)

This is the relevant analogue for Alis `StyledPopup`.

It follows the settled Abyss Control Center/Card pattern:

- popup semantic/body rect stays intact;
- placement overlaps the owner by a small `weld`;
- popup declares an explicit join to the primary owner;
- when tangent-clamped, the same popup declares the QSB's second join to that
  physical Screen Edge owner;
- popup supplies a deep `fuse`;
- no corner helper, flare, sink or contact-plane offset exists.

### `edge-reach`

This reproduces the different `AbyssStage.meltInto()` rule used by pieces that
attach directly to a screen/frame edge:

```text
reach = min(width, height) / 2 + 1
```

Only the field rect is grown into the owner. The cyan guide remains the semantic
popup rect so this hidden extent is obvious.

Do **not** use this mode as evidence that a Bar popup should use edge-piece
geometry; it exists to prevent conflating the two upstream mechanisms.

## Run

```sh
scripts/abyss-corner-poc/run.sh
```

Defaults are deliberately exaggerated for visual inspection:

- yellow unified field;
- cyan semantic popup outline;
- magenta owner seam;
- popup radius 48 px;
- fuse 56 px;
- profile `diagnostic`.

Useful overrides:

```sh
ALIS_ABYSS_POC_EDGE=top|bottom|left|right \
ALIS_ABYSS_POC_MODE=card-owner|edge-reach \
ALIS_ABYSS_POC_PROFILE=diagnostic|upstream-relative \
ALIS_ABYSS_POC_SOURCE_T=0.5 \
ALIS_ABYSS_POC_OWNER_THICKNESS=56 \
ALIS_ABYSS_POC_POPUP_WIDTH=380 \
ALIS_ABYSS_POC_POPUP_HEIGHT=300 \
ALIS_ABYSS_POC_POPUP_RADIUS=48 \
ALIS_ABYSS_POC_FUSE=56 \
ALIS_ABYSS_POC_WELD=4 \
ALIS_ABYSS_POC_FRAME_THICKNESS=10 \
ALIS_ABYSS_POC_GUIDES=1 \
scripts/abyss-corner-poc/run.sh
```

Set `ALIS_ABYSS_POC_OUTPUT=<output-name>` on a multi-output desktop.





## Geometry profiles

The PoC separates visual diagnosis from upstream-scale calibration.

`diagnostic` is the default because the maintainer requested larger corners for
easy inspection:

```text
owner thickness 56
popup           380 x 300
radius          48
fuse            56
weld            4
screen edge      10
```

`upstream-relative` follows the default Abyss v2.31 scale much more closely:

```text
owner thickness 42
popup           360 x 300
radius          30
fuseDeep        30
weld            3
screen edge      10
```

The upstream values come from `AbyssStyle.qml` at density/melt defaults:
`radiusPanel = corner(30)`, `fuseDeep = 30 * density * meltDepth`,
`weld = 3 * density`, and the default Bar height is 42.

Select it with:

```sh
ALIS_ABYSS_POC_PROFILE=upstream-relative \
scripts/abyss-corner-poc/run.sh
```

Explicit geometry environment variables still override either profile.

## Capture the full live visual matrix

To avoid accepting a center-only case, capture all 12 mandatory combinations:

```text
top / bottom / left / right
×
sourceT 0.02 / 0.50 / 0.98
```

Run inside the real Wayland session:

```sh
ALIS_ABYSS_POC_OUTPUT=<output-name> \
scripts/abyss-corner-poc/capture-matrix.sh
```

The output defaults to `scripts/abyss-corner-poc/captures/` and contains:

- 12 full-output PNG screenshots;
- 12 focused junction PNGs (`*-detail.png`);
- one machine-readable geometry JSON and one Quickshell log per case;
- profile-specific `manifest-<mode>-<profile>.tsv`;
- profile-specific `session-<mode>-<profile>.json` with capture-tool and
  coordinate-space provenance;
- `contact-sheet-<mode>-<profile>.png` when ImageMagick is available;
- `detail-sheet-<mode>-<profile>.png` when ImageMagick is available.

The harness launches only this developer PoC and waits for its
`ALIS_ABYSS_POC` readiness marker. That marker is emitted only after the
full-output layer-shell window matches the selected `ShellScreen` dimensions
for at least three consecutive geometry probes; it is deliberately **not**
emitted from `Component.onCompleted`. The harness then persists that stable
output-local geometry, captures with `grim`, and terminates that exact PoC
process before moving to the next case. It does **not** restart, reload or
IPC-call the running Alis shell.

The focused crop is computed from the semantic popup/owner geometry and
`ShellScreen.x/y`, then passed to `grim -g` in compositor layout coordinates.
This avoids shrinking a 1440p/4K full screenshot just to inspect a 30–56 px
fillet, and it does not assume that Qt `devicePixelRatio` equals the
compositor's fractional output scale.

For the first acceptance pass, leave the default:

```sh
ALIS_ABYSS_POC_MODE=card-owner
```

The matrix harness rejects unknown mode/profile names instead of silently
labelling fallback geometry with the wrong artifact name.

Use `edge-reach` only as a diagnostic comparison after the card-owner matrix
has been reviewed.

## Run the complete G1 acceptance pair

For the normal acceptance run, prefer the wrapper so both profiles belong to
one timestamped evidence directory and the static source contract runs first:

```sh
ALIS_ABYSS_POC_OUTPUT=<output-name> \
scripts/abyss-corner-poc/capture-g1.sh
```

It forces `card-owner`, captures `diagnostic` then `upstream-relative`,
writes `g1-run.txt` with the repository HEAD plus the paired profile artifacts,
then runs `verify-g1-evidence.py`. Before capture, it refuses a non-empty
evidence directory and requires the G1 source scope (PoC, contract test and
runtime-exclusion record) to be clean. The run file records the PoC tree and
contract/runtime-exclusion blob SHAs so the screenshots can be tied to the
actual source revision. The verifier also checks requested-output consistency,
structural completeness, labels and expected center/start/end join metadata; it
does **not** approve visual morphology.

Set `ALIS_ABYSS_POC_CAPTURE_DIR` only when you intentionally want a specific
**new or empty** evidence directory.

## Acceptance before production work

The first gate is visual, not architectural:

1. the two junction corners must read as part of the popup/owner silhouette;
2. they must not look like blobs underneath the popup;
3. source position 0.50 must show only the primary owner join;
4. source positions 0.02 / 0.98 must remain one coherent silhouette while
   joining both the primary owner and the perpendicular Screen Edge;
5. all four edges must produce the same topology;
6. `card-owner` must be judged independently from `edge-reach`.

If this is not visually correct, discard/rework this PoC. Do not patch
`StyledPopup`, `ConnectedSurfaceJoinFlares`, Bar or ScreenEdges.


### Invalid evidence from pre-layout metadata

A live G1 attempt can contain all 24 screenshots and still be rejected if its
metadata was emitted before the layer-shell window reached full-output size.
Such an attempt must not be used for G1 morphology acceptance because the
focused crop and join labels may describe the transient pre-layout geometry.
After updating this harness, rerun `capture-g1.sh` into a fresh evidence
directory.


### Variants screen ownership

The `Variants` delegate owns Quickshell's injected `modelData`. It passes that
screen explicitly into `AbyssCornerPocWindow.targetScreen`; the window itself
must not redeclare `required modelData`. This keeps delegate construction
compatible with Quickshell's required-property initialization semantics.


## Production runtime preflight

After syncing/reloading the real Alis runtime, verify that the installed
runtime is actually using the cutover sources and exact locked shader before
judging production visuals:

```sh
scripts/abyss-corner-poc/verify-production-runtime.sh
```

For a non-default runtime root:

```sh
ALIS_RUNTIME_ROOT=/path/to/quickshell/runtime \
scripts/abyss-corner-poc/verify-production-runtime.sh
```

A PASS proves source/install parity only. It does not replace the final live
visual and interaction acceptance pass.
