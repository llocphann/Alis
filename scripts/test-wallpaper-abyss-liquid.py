#!/usr/bin/env python3
"""WALL-R01: Abyss Liquid shares Panel material, not a separate accent palette.

The real QSB build and native Niri visual/pixel acceptance are separate gates.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
shader = (root / "modules/common/widgets/wallpaperTransitions/alisMelt.frag").read_text()
qml = (root / "modules/common/widgets/WallpaperCrossfader.qml").read_text()
abyss = (root / "modules/abyss/looks/AbyssField.qml").read_text()
style = (root / "modules/abyss/looks/AbyssStyle.qml").read_text()
binary = root / "modules/common/widgets/wallpaperTransitions/alisMelt.frag.qsb"

# Each named pigment must come from the exact same AbyssStyle property that
# AbyssField itself uses, including alpha-adjusted shadow/glow.
shared = {
    "liquidSurface": ("surface", "surface"),
    "liquidRaised": ("surfaceRaised", "raised"),
    "liquidRim": ("specular", "rim"),
    "liquidShadow": ("shadow", "shadow"),
    "liquidGlow": ("glow", "glow"),
}
assert "import qs.modules.abyss.looks" in qml
for uniform, (token, abyss_uniform) in shared.items():
    assert re.search(r"vec4\s+" + uniform + r"\s*;", shader), \
        f"shader missing {uniform} uniform"
    assert f"property color {uniform}: AbyssStyle.{token}" in qml, \
        f"{uniform} does not share AbyssStyle.{token}"
    assert f"property color {abyss_uniform}: AbyssStyle.{token}" in abyss, \
        f"Liquid and AbyssField disagree on shared material {token}"
    assert f"readonly property color {token}:" in style, \
        f"AbyssStyle does not expose {token}"

for uniform, token in {"liquidHighlightStrength": "highlightStrength",
                       "liquidMotionIntensity": "motionIntensity"}.items():
    assert re.search(r"float\s+" + uniform + r"\s*;", shader)
    assert f"property real {uniform}: AbyssStyle.{token}" in qml

assert "liquidAccent" not in shader and "liquidDepth" not in shader, \
    "accent-only paint system survived Panel material cutover"
assert "float columns =" not in shader and "floor(uv.x *" not in shader, \
    "old discrete stripe transition came back"
assert "noise2(" in shader and "signedFront" in shader and "refractOffset" in shader, \
    "organic fluid field or bounded refraction missing"
assert "fwidth(signedFront)" in shader, \
    "soft waterline needs screen-space anti-aliasing"
assert "ubuf.liquidSurface.a" in shader and "ubuf.liquidShadow.a" in shader, \
    "Panel opacity and premultiplied shadow strength must be honored"
assert "ubuf.liquidHighlightStrength" in shader and "ubuf.liquidGlow.rgb" in shader, \
    "Abyss material highlight/glow settings must shape the new shader"
assert shader.count("texture(source1,") >= 2 and shader.count("texture(source2,") >= 2, \
    "two wallpaper texture sources and exact endpoints must remain")
assert "if (p <= 0.0001)" in shader and "if (p >= 0.9999)" in shader, \
    "transition must preserve untinted 0/100 percent frames"
assert "fragColor = vec4(tinted, scene.a) * ubuf.qt_Opacity;" in shader, \
    "wallpaper alpha and Qt compositor opacity must remain intact"
assert "_shaderTexturePrimeSwaps < 2" in qml \
    and "function onFrameSwapped(): void" in qml, \
    "do not alter stable texture priming/presentation pipeline"
assert binary.is_file() and binary.stat().st_size > 100, \
    "deployed QSB must be bundled; GLSL-only changes do not render"
print("WALL-R01 Abyss Panel-material Liquid source contract: PASS (native visual untested)")
