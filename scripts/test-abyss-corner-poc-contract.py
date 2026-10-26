#!/usr/bin/env python3
"""Static guard for the developer-only Abyss-faithful corner PoC."""
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[1]
POC = ROOT / "scripts" / "abyss-corner-poc"

field = (POC / "AbyssField.frag").read_text(encoding="utf-8")
wrapper = (POC / "AbyssCornerField.qml").read_text(encoding="utf-8")
window = (POC / "AbyssCornerPocWindow.qml").read_text(encoding="utf-8")
shell = (POC / "shell.qml").read_text(encoding="utf-8")
readme = (POC / "README.md").read_text(encoding="utf-8")
capture = (POC / "capture-matrix.sh").read_text(encoding="utf-8")
g1_capture = (POC / "capture-g1.sh").read_text(encoding="utf-8")
g1_verify = (POC / "verify-g1-evidence.py").read_text(encoding="utf-8")
exclusions = json.loads((ROOT / "sdata" / "runtime-exclusions.json").read_text(encoding="utf-8"))

assert "scripts/abyss-corner-poc" in exclusions["excludedPaths"]
assert "required property var modelData" not in window, (
    "PoC window must not duplicate the Variants delegate modelData requirement"
)
assert "property var targetScreen: null" in window
assert "screen: root.targetScreen" in window
assert "required property var modelData" in shell
assert "targetScreen: modelData" in shell
assert "9574fa424c0d1008e927454e933a7fbe292f9fb2" in wrapper
assert "9574fa424c0d1008e927454e933a7fbe292f9fb2" in readme
assert (POC / "AbyssField.frag.qsb").stat().st_size == 16765

for token in (
    "float roundedBox(",
    "float smoothUnion(",
    "return mix(b, a, h) - k * h * (1.0 - h);",
    "united = min(united, smoothUnion(other, bodies[i], k));",
):
    assert token in field, f"upstream Abyss field primitive missing: {token}"

for token in (
    'id: "owner"',
    'id: "popup"',
    'id: "frame-start"',
    'id: "frame-end"',
    'joins: root.popupJoins',
    'const joins = ["owner"]',
    'joins.push("frame-start")',
    'joins.push("frame-end")',
    'root.geometryMode !== "edge-reach"',
    "Math.min(root.popupWidth, root.popupHeight) / 2 + 1",
    "root.ownerThickness - root.weld",
    "root.fuse",
):
    assert token in window, f"PoC geometry contract missing: {token}"

for forbidden in (
    "cornerFill",
    "borderSink",
    "contactInset",
    "contactPlane",
    "ConnectedSurfaceJoinFlares",
    "RoundCorner",
    "modules/waffle",
):
    assert forbidden not in wrapper + window, f"rejected geometry leaked into PoC: {forbidden}"





# Lock the ShaderEffect ABI expected by the exact upstream QSB. Qt provides
# qt_Matrix/qt_Opacity automatically; every application uniform must remain
# available on the wrapper.
for index in range(20):
    assert f"readonly property vector4d shape{index}:" in wrapper, (
        f"Abyss QSB shape uniform missing: shape{index}"
    )

for prefix in ("radii", "fuse", "join", "also", "paints", "glass"):
    for suffix in "ABCDE":
        assert f"readonly property vector4d {prefix}{suffix}:" in wrapper, (
            f"Abyss QSB block uniform missing: {prefix}{suffix}"
        )

for token in (
    "readonly property vector4d viewport:",
    "readonly property vector2d screen:",
    "readonly property vector4d field:",
    "readonly property color tint:",
    "readonly property color rim:",
    "readonly property vector4d edge:",
    "readonly property vector4d glass:",
    "readonly property vector4d edgeWave:",
    "readonly property vector4d waveClock:",
    "readonly property Item backdrop:",
):
    assert token in wrapper, f"Abyss QSB ABI uniform missing: {token}"

# In Abyss v2.31 paints flags no longer alter field topology/fill in GLSL; they
# are retained for QML-side shadow ownership. Keeping them zero in this
# topology-only PoC is therefore deliberate, not an omitted material path.
assert "the union does not treat them differently any more." in field
assert "united = min(united, bodies[i]);" in field

# Lock both profiles. Diagnostic deliberately enlarges the corner; the
# upstream-relative profile follows Abyss v2.31 defaults closely.
for token in (
    'ALIS_ABYSS_POC_PROFILE',
    'value === "upstream-relative" ? value : "diagnostic"',
    'root.upstreamRelative ? 42 : 56',
    'root.upstreamRelative ? 360 : 380',
    'root.upstreamRelative ? 30 : 48',
    'root.upstreamRelative ? 3 : 4',
    'root.upstreamRelative ? 30 : 56',
    'ALIS_ABYSS_POC_FRAME_THICKNESS',
):
    assert token in window, f"profile morphology drifted: {token}"

assert 'String(raw).trim().length === 0' in window, (
    "empty environment variables must not collapse profile defaults to zero"
)

for token in (
    "outputX: Number(root.screen?.x ?? 0)",
    "outputY: Number(root.screen?.y ?? 0)",
    "outputWidth: Number(root.width)",
    "outputHeight: Number(root.height)",
    "devicePixelRatio: Number(root.devicePixelRatio)",
    "popupX: Number(root.semanticPopup.x)",
    "popupY: Number(root.semanticPopup.y)",
    "ownerThickness: Number(root.ownerThickness)",
    "frameThickness: Number(root.frameThickness)",
    "joins: root.popupJoins",
    "atTangentStart: root.atTangentStart",
    "atTangentEnd: root.atTangentEnd",
    "screenWidth: Number(root.screen?.width ?? 0)",
    "screenHeight: Number(root.screen?.height ?? 0)",
    "geometryStable: root.outputGeometryReady",
    "readinessStableTicks: root.readinessStableTicks",
    "readonly property bool outputGeometryReady:",
    "function probeReadiness()",
    "root.readinessStableTicks < 3",
    "Timer {",
):
    assert token in window, f"capture metadata drifted: {token}"

assert "Component.onCompleted: console.info(" not in window, (
    "G1 readiness must not snapshot pre-layout PanelWindow geometry"
)


def rounded_box(x, y, cx, cy, half_w, half_h, radius):
    radius = min(radius, half_w, half_h)
    qx = abs(x - cx) - (half_w - radius)
    qy = abs(y - cy) - (half_h - radius)
    return (
        math.hypot(max(qx, 0.0), max(qy, 0.0))
        + min(max(qx, qy), 0.0)
        - radius
    )


def smooth_union(a, b, k):
    h = max(0.0, min(1.0, 0.5 + 0.5 * (b - a) / k))
    return b * (1.0 - h) + a * h - k * h * (1.0 - h)


screen_w = 900.0


def shoulder_extensions(owner_h, popup_w, popup_h, popup_r, weld, fuse, depths):
    popup_x = (screen_w - popup_w) / 2.0
    popup_y = owner_h - weld

    def field_distance(x, y):
        owner = rounded_box(
            x, y,
            screen_w / 2.0, owner_h / 2.0,
            screen_w / 2.0 + 2.0 * fuse, owner_h / 2.0,
            0.0,
        )
        popup = rounded_box(
            x, y,
            popup_x + popup_w / 2.0, popup_y + popup_h / 2.0,
            popup_w / 2.0, popup_h / 2.0,
            popup_r,
        )
        return min(owner, popup, smooth_union(owner, popup, fuse))

    extensions = []
    for depth in depths:
        y = owner_h + depth
        x = popup_x - max(80.0, 2.0 * fuse)
        while x <= popup_x + 1.0:
            if field_distance(x, y) <= 0.0:
                extensions.append(popup_x - x)
                break
            x += 0.05
        else:
            raise AssertionError(f"no joined field at depth {depth}")
    return extensions


diagnostic_depths = (1, 4, 8, 16, 24, 48, 56)
diagnostic = shoulder_extensions(56, 380, 300, 48, 4, 56, diagnostic_depths)
assert 24.0 <= diagnostic[0] <= 40.0, diagnostic
for previous, current in zip(diagnostic, diagnostic[1:]):
    assert current <= previous + 0.15, diagnostic
assert 8.0 <= diagnostic[2] <= 16.0, diagnostic
assert diagnostic[-1] <= 0.6, diagnostic

upstream_depths = (1, 4, 8, 16, 24, 30)
upstream = shoulder_extensions(42, 360, 300, 30, 3, 30, upstream_depths)
assert 9.0 <= upstream[0] <= 16.0, upstream
for previous, current in zip(upstream, upstream[1:]):
    assert current <= previous + 0.15, upstream
assert 0.8 <= upstream[2] <= 3.0, upstream
assert upstream[-1] <= 0.6, upstream



# The live visual matrix must cover every edge and both clamp extremes without
# touching/restarting the production shell. The extremes are specifically the
# two-owner case: primary owner plus perpendicular physical Screen Edge.
assert 'shapes: [' in window
assert "root.frameStartShape" in window
assert "root.frameEndShape" in window
assert "root.popupShape" in window
assert "root.atTangentStart" in window
assert "root.atTangentEnd" in window

for token in (
    "for edge in top bottom left right",
    "for source_t in 0.02 0.50 0.98",
    "ALIS_ABYSS_POC_MODE",
    "ALIS_ABYSS_POC_PROFILE",
    "Invalid ALIS_ABYSS_POC_MODE",
    "Invalid ALIS_ABYSS_POC_PROFILE",
    "ALIS_ABYSS_POC",
    "grim",
    'grim -g "$detail_geometry"',
    "manifest-${mode}-${profile}.tsv",
    "session-${mode}-${profile}.json",
    "detailCropCoordinates",
    "devicePixelRatioAppliedToCrop",
    "metadata_json",
    "contact-sheet-",
    "detail-sheet-",
):
    assert token in capture, f"live matrix harness missing: {token}"

for forbidden in (
    "alis restart",
    "alis reload",
    "ipc call",
    "modules/waffle",
):
    assert forbidden not in capture, f"live matrix may affect production: {forbidden}"

for token in (
    "G1 acceptance must use ALIS_ABYSS_POC_MODE=card-owner",
    "python3 \"$repo_root/scripts/test-abyss-corner-poc-contract.py\"",
    "g1-run.txt",
    "repo_head=",
    "poc_tree_sha=",
    "contract_blob_sha=",
    "runtime_exclusions_blob_sha=",
    "source_scope_clean=true",
    "evidence_dir_was_empty=true",
    "G1 evidence directory must be new or empty",
    'git -C "$repo_root" diff --quiet',
    'git -C "$repo_root" diff --cached --quiet',
    "ls-files --others --exclude-standard",
    "for profile in diagnostic upstream-relative",
    "ALIS_ABYSS_POC_MODE=card-owner",
    "detail-sheet-card-owner-diagnostic.png",
    "detail-sheet-card-owner-upstream-relative.png",
    'python3 "$here/verify-g1-evidence.py" "$out_dir"',
):
    assert token in g1_capture, f"G1 wrapper contract missing: {token}"

for forbidden in (
    "edge-reach",
    "alis restart",
    "alis reload",
    "modules/waffle",
):
    assert forbidden not in g1_capture, f"G1 wrapper may change acceptance scope: {forbidden}"

for token in (
    "G1 evidence structure: PASS",
    "Visual morphology is NOT auto-approved",
    "manifest-card-owner-{profile}.tsv",
    "session-card-owner-{profile}.json",
    '["owner", "frame-start"]',
    '["owner", "frame-end"]',
    '"compositor-layout-logical"',
    '"repo_head"',
    '"poc_tree_sha"',
    '"contract_blob_sha"',
    '"runtime_exclusions_blob_sha"',
    '"source_scope_clean"',
    '"evidence_dir_was_empty"',
    '"requestedOutput"',
    '"geometryStable"',
    '"readinessStableTicks"',
    '"screenWidth"',
    '"screenHeight"',
):
    assert token in g1_verify, f"G1 evidence verifier contract missing: {token}"

print("Abyss corner PoC contract: PASS")
