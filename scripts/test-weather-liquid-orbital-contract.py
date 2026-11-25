#!/usr/bin/env python3
"""Regression contract for Orbital Weather GPU membrane and visual-parity fallback."""

from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
WEATHER_DIR = ROOT / "modules/bar/weather"


def require(source: str, *features: str) -> None:
    for feature in features:
        if feature not in source:
            raise AssertionError(f"Weather liquid renderer lost {feature!r}")


def main() -> None:
    field = (WEATHER_DIR / "LiquidOrbitalField.qml").read_text(encoding="utf-8")
    shader_path = WEATHER_DIR / "LiquidOrbitalField.frag"
    shader = shader_path.read_text(encoding="utf-8")
    qsb = WEATHER_DIR / "LiquidOrbitalField.frag.qsb"
    orbital = (WEATHER_DIR / "OrbitalWeather.qml").read_text(encoding="utf-8")
    popup = (WEATHER_DIR / "WeatherPopupContent.qml").read_text(encoding="utf-8")
    dashboard = (ROOT / "modules/dashboard/DashWeather.qml").read_text(encoding="utf-8")

    # Primary path: keep the accepted single GPU membrane alive long enough to
    # compile/link. Shader visibility must never depend on its own Compiled state.
    require(
        field,
        "RENDERER CONTRACT (2026-09-25)",
        "ShaderEffect {",
        'fragmentShader: Qt.resolvedUrl("LiquidOrbitalField.frag.qsb")',
        "visible: root.shaderBackendAvailable",
        "GraphicsInfo.api !== GraphicsInfo.Software",
        "GraphicsInfo.api !== GraphicsInfo.Null",
        "seconds: root.timeSeconds",
        "regularRadius: root.regularNodeRadius",
        "selectedIndex: root.activeIndex",
        "nodeCount: root.hourAngles.length",
    )
    if "visible: status === ShaderEffect.Compiled" in field:
        raise AssertionError("ShaderEffect must not self-gate first render on Compiled status")
    if field.count("readonly property bool ready:") != 1:
        raise AssertionError("LiquidOrbitalField must expose exactly one ready property")
    if not qsb.is_file() or qsb.stat().st_size < 1000:
        raise AssertionError("Bundled Weather QSB is missing")

    qsb_tool = shutil.which("qsb") or "/usr/lib/qt6/bin/qsb"
    if Path(qsb_tool).is_file():
        with tempfile.TemporaryDirectory() as temp_dir:
            rebuilt = Path(temp_dir) / "LiquidOrbitalField.frag.qsb"
            subprocess.run(
                [qsb_tool, "--qt6", "-o", str(rebuilt), str(shader_path)],
                check=True,
                capture_output=True,
                text=True,
            )
            if rebuilt.read_bytes() != qsb.read_bytes():
                raise AssertionError("Bundled Weather QSB differs from its GLSL source")

    # The reference GPU shape remains one soft-unioned, wavy field.
    require(
        shader,
        "float softUnion(",
        "float ringDistance =",
        "fieldDistance = softUnion(",
        "float displacement =",
        "float neck =",
        "float foldPhase =",
        "float brightFold =",
        "float darkFold =",
        "float fineCaustic =",
        "float podAlpha =",
        "float halo =",
    )

    # Fallback parity: never expose the segmented capsule renderer again.
    require(
        field,
        "readonly property int sampleCount: 120",
        "let outerThickness = root.baseThickness",
        "let innerThickness = root.baseThickness * 0.96",
        "function liquidSample(angle: real, time: real): var",
        "function traceClosed(ctx, points): void",
        "for (let sheet = 0; sheet < 2; ++sheet)",
        "for (let band = 0; band < 3; ++band)",
        "for (let streak = 0; streak < 4; ++streak)",
        "visible: !root.shaderBackendAvailable",
        "|| liquidShader.status !== ShaderEffect.Compiled",
    )
    for forbidden in (
        "function drawBridgeMass(",
        "function drawMassUnion(",
        "function drawPulseLobe(",
        "root.drawBridgeMass(",
        "root.drawMassUnion(",
    ):
        if forbidden in field:
            raise AssertionError(
                f"Weather fallback regressed to segmented capsule topology: {forbidden!r}"
            )

    frame_block = field.split("FrameAnimation {", 1)[1].split("}", 1)[0]
    if "&& Appearance.effectsEnabled" in frame_block:
        raise AssertionError("Visual effects setting must not freeze liquid motion")

    require(
        orbital,
        "property bool liquidMode: false",
        "LiquidOrbitalField {",
        "hourAngles: root.hourAngles",
        "activeIndex: root.activeIndex",
        "animate: root.liquidAnimationActive",
    )
    require(
        popup,
        "liquidMode: true",
        "liquidAnimationActive: root.visible",
    )
    if "liquidMode: true" in dashboard:
        raise AssertionError("Dashboard must retain its simpler shared orbital view")

    print("Weather GPU membrane + parity fallback contract: PASS")


if __name__ == "__main__":
    main()
