#!/usr/bin/env python3
"""Production contract for the Screen Edge analytic single-pass field."""

from __future__ import annotations

import math
from pathlib import Path
import random
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "modules/screenCorners"
frag_path = BASE / "ScreenEdgeField.frag"
qml_path = BASE / "ScreenEdgeField.qml"
qsb_path = BASE / "ScreenEdgeField.frag.qsb"

frag = frag_path.read_text(encoding="utf-8")
qml = qml_path.read_text(encoding="utf-8")
runtime = (BASE / "ScreenEdges.qml").read_text(encoding="utf-8")
fallback_qml = (BASE / "ScreenEdgeLegacyFallback.qml").read_text(encoding="utf-8")

for token in (
    "float roundedBox(",
    "float qMax = max(q.x, q.y);",
    "if (q.x <= 0.0 || q.y <= 0.0)",
    "return qMax - radius;",
    "return length(q) - radius;",
    "bool axisDeep =",
    "bool centralCore =",
    "if (axisDeep && centralCore)",
    "fragColor = vec4(0.0);",
    "float d = roundedBox(",
    "vec2 p = u.tileRect.xy + qt_TexCoord0 * u.tileRect.zw;",
    "float shadowResponse(float d, float aa, float reach)",
    "if (u.shadowColor.a <= 0.0)",
    "float sharpReach = max(aa, reach / 15.0);",
    "float midReach = max(sharpReach, reach / 3.0);",
    "0.175 * smoothstep(-sharpReach, 0.0, d)",
    "0.250 * smoothstep(-midReach, 0.0, d)",
    "0.075 * smoothstep(-reach, 0.0, d)",
    "if (d <= -reach)",
    "if (d <= -aa)",
    "fragColor = u.shadowColor * innerShadow * u.qt_Opacity;",
    "if (d >= aa)",
    "float innerShadow = u.shadowColor.a > 0.0 ? 0.5 : 0.0;",
    "float frameCover = smoothstep(-aa, aa, d);",
    "vec3 frameRgb = u.frameColor.rgb * frameCover;",
    "vec3 shadowRgb = u.shadowColor.rgb * innerShadow;",
    "float shadowAlpha = u.shadowColor.a * innerShadow;",
    "fragColor = u.frameColor * u.qt_Opacity;",
):
    assert token in frag, token

# The candidate's performance boundary is intentionally strict: no texture
# inputs/captures and no general-purpose blur path.
for forbidden in (
    "sampler2D",
    "texture(",
    "textureLod(",
    "imageLoad(",
    "u.frameColor.rgb * frameAlpha",
    "u.shadowColor.rgb * shadowAlpha",
):
    assert forbidden not in frag, forbidden

for token in (
    "Item {",
    "readonly property real topShallowExtent:",
    "readonly property real bottomShallowExtent:",
    "readonly property real leftShallowExtent:",
    "readonly property real rightShallowExtent:",
    "readonly property real topDeepExtent:",
    "readonly property real bottomDeepExtent:",
    "readonly property real leftDeepExtent:",
    "readonly property real rightDeepExtent:",
    "readonly property real horizontalArea:",
    "readonly property real verticalArea:",
    "readonly property bool horizontalCornerBands:",
    "readonly property real topBandX:",
    "readonly property real topBandWidth:",
    "readonly property real leftBandY:",
    "readonly property real leftBandHeight:",
    "readonly property bool shaderError:",
    "component Band: ShaderEffect {",
    "property vector4d viewport: root.viewportUniform",
    "property vector4d insets: root.insetsUniform",
    "property vector4d params: root.paramsUniform",
    "property vector4d tileRect: Qt.vector4d(x, y, width, height)",
    'fragmentShader: Qt.resolvedUrl("ScreenEdgeField.frag.qsb")',
):
    assert token in qml, token
assert qml.count("Band {") == 4, "Screen Edge field must use four perimeter tiles"
for forbidden in ("ShaderEffectSource", "MultiEffect", "ShapePath", "PathArc"):
    assert forbidden not in qml, forbidden

assert qsb_path.is_file() and qsb_path.stat().st_size > 1000, (
    "Packaged ScreenEdgeField QSB is missing"
)

# Production ownership: the analytic field is the normal painter. The former
# Shape/MultiEffect renderer is only constructed on ShaderEffect.Error.
for token in (
    "ScreenEdgeField {",
    "id: frameField",
    "leftInset: frameWindow.frameLeftInset",
    "topInset: frameWindow.frameTopInset",
    "rightInset: frameWindow.frameRightInset",
    "bottomInset: frameWindow.frameBottomInset",
    "radius: root.rounding",
    "elevationEnabled: frameWindow.physicalShadowActive",
    "id: legacyFramePainter",
    "active: frameField.shaderError",
    'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")',
):
    assert token in runtime, token
assert runtime.index("ScreenEdgeField {") < runtime.index("id: legacyFramePainter")
fallback = runtime[runtime.index("id: legacyFramePainter"):]
assert 'Qt.resolvedUrl("ScreenEdgeLegacyFallback.qml")' in fallback
assert "import QtQuick.Shapes" not in runtime
assert "import QtQuick.Effects" not in runtime
assert "MultiEffect {" in fallback_qml
assert "ShapePath {" in fallback_qml


def f32(value: float) -> float:
    return struct.unpack("<f", struct.pack("<f", float(value)))[0]


assert f32(f32(f32(0.175) + f32(0.250)) + f32(0.075)) == f32(0.5), (
    "full-frame shadow fast path must equal the three accepted band weights"
)


def legacy_rounded_box_from_q(qx: float, qy: float, radius: float) -> float:
    qx, qy, radius = f32(qx), f32(qy), f32(radius)
    px = f32(max(qx, 0.0))
    py = f32(max(qy, 0.0))
    squared = f32(f32(px * px) + f32(py * py))
    length = f32(math.sqrt(squared))
    qmax = f32(max(qx, qy))
    return f32(f32(length + f32(min(qmax, 0.0))) - radius)


def optimized_rounded_box_from_q(qx: float, qy: float, radius: float) -> float:
    qx, qy, radius = f32(qx), f32(qy), f32(radius)
    qmax = f32(max(qx, qy))
    if qx <= 0.0 or qy <= 0.0:
        return f32(qmax - radius)
    squared = f32(f32(qx * qx) + f32(qy * qy))
    return f32(f32(math.sqrt(squared)) - radius)


# The straight-edge shortcut is not an approximation: with at most one positive
# q component the legacy length(max(q, 0)) + min(max(q), 0) algebra collapses
# to max(q.x, q.y). Check float32 operation results directly across edge,
# corner and interior quadrants so the optimization cannot drift numerically.
float_rng = random.Random(0x53515254)
for _ in range(200000):
    qx = f32(float_rng.uniform(-128.0, 128.0))
    qy = f32(float_rng.uniform(-128.0, 128.0))
    radius = f32(float_rng.uniform(0.0, 96.0))
    legacy_bits = struct.pack("<f", legacy_rounded_box_from_q(qx, qy, radius))
    optimized_bits = struct.pack(
        "<f", optimized_rounded_box_from_q(qx, qy, radius)
    )
    assert legacy_bits == optimized_bits, (
        "straight-edge rounded-box shortcut changed float32 output"
    )


def sd_round_box(
    x: float,
    y: float,
    width: float,
    height: float,
    left: float,
    top: float,
    right: float,
    bottom: float,
    radius: float,
) -> float:
    lo_x, lo_y = max(left, 0.0), max(top, 0.0)
    hi_x = max(lo_x, width - max(right, 0.0))
    hi_y = max(lo_y, height - max(bottom, 0.0))
    hx = max((hi_x - lo_x) * 0.5, 0.0)
    hy = max((hi_y - lo_y) * 0.5, 0.0)
    cx, cy = (lo_x + hi_x) * 0.5, (lo_y + hi_y) * 0.5
    r = min(max(radius, 0.0), hx, hy)
    qx = abs(x - cx) - (hx - r)
    qy = abs(y - cy) - (hy - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def reference_inside(
    x: float,
    y: float,
    width: float,
    height: float,
    left: float,
    top: float,
    right: float,
    bottom: float,
    radius: float,
) -> bool:
    l, t = max(left, 0.0), max(top, 0.0)
    rgt = max(l, width - max(right, 0.0))
    bot = max(t, height - max(bottom, 0.0))
    rad = min(max(radius, 0.0), (rgt - l) * 0.5, (bot - t) * 0.5)
    if not (l <= x <= rgt and t <= y <= bot):
        return False
    if l + rad <= x <= rgt - rad or t + rad <= y <= bot - rad:
        return True
    cx = l + rad if x < l + rad else rgt - rad
    cy = t + rad if y < t + rad else bot - rad
    return (x - cx) ** 2 + (y - cy) ** 2 <= rad ** 2


def band_layout(
    width: float,
    height: float,
    left: float,
    top: float,
    right: float,
    bottom: float,
    radius: float,
    shadow_reach: float,
):
    safe = max(shadow_reach, 2.0)
    rad = max(0.0, radius)

    top_shallow = math.ceil(max(0.0, top) + safe)
    bottom_shallow = math.ceil(max(0.0, bottom) + safe)
    left_shallow = math.ceil(max(0.0, left) + safe)
    right_shallow = math.ceil(max(0.0, right) + safe)

    top_deep = math.ceil(max(0.0, top) + rad + safe)
    bottom_deep = math.ceil(max(0.0, bottom) + rad + safe)
    left_deep = math.ceil(max(0.0, left) + rad + safe)
    right_deep = math.ceil(max(0.0, right) + rad + safe)

    h_top = min(height, top_deep)
    h_bottom = min(max(0.0, height - h_top), bottom_deep)
    h_middle = max(0.0, height - h_top - h_bottom)
    h_left = min(width, left_shallow)
    h_right = min(max(0.0, width - h_left), right_shallow)
    h_area = width * (h_top + h_bottom) + h_middle * (h_left + h_right)

    v_left = min(width, left_deep)
    v_right = min(max(0.0, width - v_left), right_deep)
    v_middle = max(0.0, width - v_left - v_right)
    v_top = min(height, top_shallow)
    v_bottom = min(max(0.0, height - v_top), bottom_shallow)
    v_area = height * (v_left + v_right) + v_middle * (v_top + v_bottom)

    horizontal = h_area <= v_area
    if horizontal:
        rects = (
            (0.0, 0.0, width, h_top),
            (0.0, height - h_bottom, width, h_bottom),
            (0.0, h_top, h_left, h_middle),
            (width - h_right, h_top, h_right, h_middle),
        )
        chosen_area = h_area
    else:
        rects = (
            (v_left, 0.0, v_middle, v_top),
            (v_left, height - v_bottom, v_middle, v_bottom),
            (0.0, 0.0, v_left, height),
            (width - v_right, 0.0, v_right, height),
        )
        chosen_area = v_area

    return horizontal, h_area, v_area, chosen_area, rects


def band_covers(x: float, y: float, layout) -> bool:
    rects = layout[4]
    return any(
        rw > 0.0
        and rh > 0.0
        and rx <= x < rx + rw
        and ry <= y < ry + rh
        for rx, ry, rw, rh in rects
    )


def band_area_ratio(width, height, inset, radius, shadow):
    layout = band_layout(
        width, height, inset, inset, inset, inset, radius, shadow
    )
    return layout[3] / (width * height)


# Adaptive orientation keeps the same four draws and selects the smaller
# strict-lossless perimeter partition for each output geometry.
assert band_area_ratio(1920, 1080, 10, 25, 15) < 0.097
assert band_area_ratio(3840, 2160, 10, 25, 15) < 0.049
assert band_layout(1920, 1080, 10, 10, 10, 10, 25, 15)[0] is False
assert band_layout(1080, 1920, 10, 10, 10, 10, 25, 15)[0] is True


rng = random.Random(0x53435245454E)
for _ in range(50000):
    width = rng.uniform(320.0, 7680.0)
    height = rng.uniform(240.0, 2160.0)
    left, top, right, bottom = [rng.uniform(1.0, 96.0) for _ in range(4)]
    radius = rng.uniform(0.0, 96.0)
    x = rng.uniform(-4.0, width + 4.0)
    y = rng.uniform(-4.0, height + 4.0)
    d = sd_round_box(x, y, width, height, left, top, right, bottom, radius)
    inside = reference_inside(
        x, y, width, height, left, top, right, bottom, radius
    )

    # Mirror the production deep-interior guard and prove it can only reject
    # pixels whose exact SDF is already beyond the complete shadow/AA band.
    l, t = max(left, 0.0), max(top, 0.0)
    rgt = max(l, width - max(right, 0.0))
    bot = max(t, height - max(bottom, 0.0))
    hx = max((rgt - l) * 0.5, 0.0)
    hy = max((bot - t) * 0.5, 0.0)
    clamped_radius = min(max(radius, 0.0), hx, hy)
    shadow_reach = rng.uniform(0.0, 32.0)
    safe_reach = max(shadow_reach, 2.0)
    axis_deep = (
        x >= l + safe_reach
        and x <= rgt - safe_reach
        and y >= t + safe_reach
        and y <= bot - safe_reach
    )
    central_core = (
        (x >= l + clamped_radius and x <= rgt - clamped_radius)
        or (y >= t + clamped_radius and y <= bot - clamped_radius)
    )
    if axis_deep and central_core:
        assert d <= -safe_reach + 1e-7, (
            "deep-interior guard rejected a potentially visible fragment"
        )

    if 0.0 <= x < width and 0.0 <= y < height:
        layout = band_layout(
            width, height, left, top, right, bottom, radius, shadow_reach
        )
        if not band_covers(x, y, layout):
            assert axis_deep and central_core, (
                "banded raster omitted a fragment outside the proven transparent core"
            )
            assert d <= -safe_reach + 1e-7
    # Ignore an infinitesimal mathematical boundary where either sign is an
    # equivalent coverage convention; everywhere else classification is exact.
    if abs(d) > 1e-7:
        assert (d < 0.0) == inside

compiler = shutil.which("qsb") or "/usr/lib/qt6/bin/qsb"
if Path(compiler).is_file():
    with tempfile.TemporaryDirectory(prefix="alis-screen-edge-qsb-") as tmp:
        rebuilt = Path(tmp) / qsb_path.name
        subprocess.run(
            [compiler, "--qt6", "-o", str(rebuilt), str(frag_path)],
            check=True,
            capture_output=True,
            text=True,
        )
        assert rebuilt.read_bytes() == qsb_path.read_bytes(), (
            "ScreenEdgeField QSB differs from GLSL source"
        )

print("SCREEN_EDGE_ANALYTIC_FIELD_CONTRACT_PASS")
