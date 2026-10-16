#!/usr/bin/env python3
"""WALL-R01 visual/source contract: organic, theme-driven Liquid shader."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
shader = (root / "modules/common/widgets/wallpaperTransitions/alisMelt.frag").read_text()
qml = (root / "modules/common/widgets/WallpaperCrossfader.qml").read_text()
binary = root / "modules/common/widgets/wallpaperTransitions/alisMelt.frag.qsb"

uniforms = {
    "liquidAccent": "m3primary",
    "liquidDepth": "m3primaryContainer",
    "liquidHighlight": "m3secondary",
}
for name, token in uniforms.items():
    assert re.search(r"vec4\s+" + name + r"\s*;", shader), f"shader missing {name} uniform"
    assert f"property color {name}: Appearance.m3colors.{token}" in qml, \
        f"{name} does not track theme palette {token}"

assert "float columns =" not in shader, "legacy discrete stripes still present"
assert "floor(uv.x *" not in shader, "stripes/column index still present"
assert "edgeTint" not in shader, "old baked purple rim still present"
assert "noise2(" in shader and "signedFront" in shader and "refractOffset" in shader, \
    "organic front, surface refraction, or noise deformation missing"
assert shader.count("texture(source1,") >= 2 and shader.count("texture(source2,") >= 2, \
    "keep exact first/last wallpaper endpoints and the two textures"
assert "if (p <= 0.0001)" in shader and "if (p >= 0.9999)" in shader, \
    "the transition must present exact untinted endpoints"
assert "fragColor = vec4(tinted, scene.a) * ubuf.qt_Opacity;" in shader, \
    "final wallpaper alpha and Qt opacity must be preserved"
assert "property bool _shaderTexturePrimePending" in qml \
    and "function onFrameSwapped(): void" in qml, \
    "do not remove the Owner-tested texture/frame handoff"
assert binary.is_file() and binary.stat().st_size > 100, "compiled QSB asset is missing"
print("WALL-R01 Abyss Liquid source contract: PASS (native visual performance untested)")
