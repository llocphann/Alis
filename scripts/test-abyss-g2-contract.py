#!/usr/bin/env python3
from pathlib import Path
import json
import math

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "scripts" / "abyss-corner-poc"
G2 = BASE / "g2"

shell = (G2 / "shell.qml").read_text(encoding="utf-8")
scenario = (G2 / "G2Scenario.qml").read_text(encoding="utf-8")
field = (G2 / "AbyssSplitField.qml").read_text(encoding="utf-8")
capture = (G2 / "capture-g2.sh").read_text(encoding="utf-8")
verify = (G2 / "verify-g2-evidence.py").read_text(encoding="utf-8")
readme = (G2 / "README.md").read_text(encoding="utf-8")
exclusions = json.loads((ROOT / "sdata" / "runtime-exclusions.json").read_text(encoding="utf-8"))
gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")

assert "scripts/abyss-corner-poc" in exclusions["excludedPaths"]
assert "/scripts/abyss-corner-poc/g2/captures/" in gitignore, (
    "G2 live evidence must remain local-only and must not dirty the source scope"
)
assert 'out_dir="${ALIS_ABYSS_G2_CAPTURE_DIR:-$here/captures/g2-$stamp}"' in capture
assert (BASE / "AbyssField.frag.qsb").stat().st_size == 16765
assert (G2 / "AbyssField.frag.qsb").stat().st_size == 16765
assert (G2 / "AbyssField.frag.qsb").read_bytes() == (BASE / "AbyssField.frag.qsb").read_bytes()
assert "fragmentShader: Qt.resolvedUrl(\"AbyssField.frag.qsb\")" in field
assert "shaderCompiled: pass.status === ShaderEffect.Compiled" in field
assert "shaderLog: pass.log" in field
assert "required property rect paintBounds" in field
assert "root.effectivePaintBounds" in field
assert "readonly property vector4d viewport:" in field

for index in range(20):
    assert f"readonly property vector4d shape{index}:" in field
for prefix in ("radii", "fuse", "join", "also", "paints", "glass"):
    for suffix in "ABCDE":
        assert f"readonly property vector4d {prefix}{suffix}:" in field

for token in (
    "WlrLayershell.layer: WlrLayer.Top",
    "WlrLayershell.layer: WlrLayer.Overlay",
    'WlrLayershell.namespace: "alis:abyss-g2-owner"',
    'WlrLayershell.namespace: "alis:abyss-g2-popup"',
    "root.ownerShape",
    "root.frameStartShape",
    "root.frameEndShape",
    "root.popupShape",
    "clipExternalOwners",
    "paintRespectsOwnerSeam",
    "paintRespectsTangentOwners",
    "shadowRespectsOwnerSeam",
    "shadowRespectsTangentOwners",
    'shadowIsolation: "texture-source-rect"',
    "ShaderEffectSource",
    "sourceItem: shadowTextureSource",
    "sourceRect: Qt.rect(",
    "hideSource: true",
    "root.horizontal && root.atTangentStart",
    "root.horizontal && root.atTangentEnd",
    "!root.horizontal && root.atTangentStart",
    "!root.horizontal && root.atTangentEnd",
    "visible-body-only",
    "WlrKeyboardFocus.None",
    "RectangularShadow",
    "root.readinessStableTicks < 3",
    "&& splitField.shaderCompiled",
    "shaderCompiled: splitField.shaderCompiled",
    "shaderLog: String(splitField.shaderLog || \"\")",
):
    assert token in scenario, f"G2 scenario contract missing: {token}"

for forbidden in (
    "ConnectedSurfaceJoinFlares",
    "cornerFill",
    "borderSink",
    "contactInset",
    "modules/waffle",
):
    assert forbidden not in scenario + field, f"rejected geometry leaked into G2: {forbidden}"

for token in (
    "for progress in 1.00 0.55",
    "for edge in top bottom left right",
    "for source_t in 0.02 0.50 0.98",
    "ALIS_ABYSS_G2",
    "grim -g",
    "verify-g2-evidence.py",
    "G2 evidence directory must be new or empty",
):
    assert token in capture, f"G2 capture harness missing: {token}"

for token in (
    "G2 evidence structure: PASS",
    "Visual split-composition is NOT auto-approved",
    "paintRespectsOwnerSeam",
    "paintRespectsTangentOwners",
    "shadowIsolation",
    "shadowRespectsOwnerSeam",
    "shadowRespectsTangentOwners",
    "paint/input/shadow reachable",
    "area_ratio >= 0.30",
    "visible-body-only",
    "animationOffset",
    "attached-side shadow is enabled",
    "Abyss shader was not compiled",
    "Abyss shader log is not empty",
):
    assert token in verify, f"G2 verifier missing: {token}"

assert "required property var modelData" not in scenario
assert "required property var modelData" in shell
assert "targetScreen: modelData" in shell

# Numeric oracle: the local raster bounds may expand by fuse only tangentially,
# must stay inward of the owner seam, and mid-slide must remain pure translation.
def geometry(edge: str, source: float, progress: float, W=1920.0, H=1080.0):
    owner, popup_w, popup_h, fuse, weld, frame, aa = 42.0, 360.0, 300.0, 30.0, 3.0, 10.0, 2.0
    horizontal = edge in ("top", "bottom")
    tangent_extent = W if horizontal else H
    tangent_popup = popup_w if horizontal else popup_h
    inset = frame - weld
    start = max(inset, min(tangent_extent - tangent_popup - inset,
                           source * tangent_extent - tangent_popup / 2))
    if edge == "top":
        rest = [start, owner - weld, popup_w, popup_h]
        seam = owner
    elif edge == "bottom":
        rest = [start, H - owner - popup_h + weld, popup_w, popup_h]
        seam = H - owner
    elif edge == "left":
        rest = [owner - weld, start, popup_w, popup_h]
        seam = owner
    else:
        rest = [W - owner - popup_w + weld, start, popup_w, popup_h]
        seam = W - owner

    cross = popup_h if horizontal else popup_w
    offset = (1 - progress) * cross
    x, y, w, h = rest
    if edge == "top":
        y -= offset
    elif edge == "bottom":
        y += offset
    elif edge == "left":
        x -= offset
    else:
        x += offset

    if horizontal:
        raw = [x - fuse - aa, y - aa, w + 2 * (fuse + aa), h + 2 * aa]
    else:
        raw = [x - aa, y - fuse - aa, w + 2 * aa, h + 2 * (fuse + aa)]
    l, t = max(0.0, raw[0]), max(0.0, raw[1])
    r, b = min(W, raw[0] + raw[2]), min(H, raw[1] + raw[3])
    if edge == "top":
        t = max(t, seam)
    elif edge == "bottom":
        b = min(b, seam)
    elif edge == "left":
        l = max(l, seam)
    else:
        r = min(r, seam)

    at_start = math.isclose(start, inset, abs_tol=0.01)
    at_end = math.isclose(start + tangent_popup,
                          tangent_extent - inset, abs_tol=0.01)
    if horizontal and at_start:
        l = max(l, frame)
    if horizontal and at_end:
        r = min(r, W - frame)
    if not horizontal and at_start:
        t = max(t, frame)
    if not horizontal and at_end:
        b = min(b, H - frame)
    return (x, y, w, h), (l, t, max(0, r-l), max(0, b-t)), seam, offset

for edge in ("top", "bottom", "left", "right"):
    for source in (0.02, 0.50, 0.98):
        for progress in (1.0, 0.55):
            body, paint, seam, offset = geometry(edge, source, progress)
            if edge == "top":
                assert paint[1] >= seam
            elif edge == "bottom":
                assert paint[1] + paint[3] <= seam
            elif edge == "left":
                assert paint[0] >= seam
            else:
                assert paint[0] + paint[2] <= seam
            if math.isclose(source, 0.02, abs_tol=0.001):
                if edge in ("top", "bottom"):
                    assert paint[0] >= 10
                else:
                    assert paint[1] >= 10
            if math.isclose(source, 0.98, abs_tol=0.001):
                if edge in ("top", "bottom"):
                    assert paint[0] + paint[2] <= 1920 - 10
                else:
                    assert paint[1] + paint[3] <= 1080 - 10
            assert paint[2] * paint[3] < 0.30 * 1920 * 1080
            expected = (1 - progress) * (300 if edge in ("top", "bottom") else 360)
            assert math.isclose(offset, expected, abs_tol=1e-9)

print("Abyss G2 split-composition contract: PASS")
