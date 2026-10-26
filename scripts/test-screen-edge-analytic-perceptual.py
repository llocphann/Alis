#!/usr/bin/env python3
"""Owner-session A/B budget: pre-cutover MultiEffect vs analytic Screen Edge."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

if os.environ.get("ALIS_SCREEN_EDGE_ANALYTIC_PERCEPTUAL") != "1":
    print("SKIP: analytic Screen Edge A/B requires ALIS_SCREEN_EDGE_ANALYTIC_PERCEPTUAL=1")
    raise SystemExit(0)
if not shutil.which("qs"):
    raise SystemExit("qs is required for analytic Screen Edge A/B")
if not os.environ.get("WAYLAND_DISPLAY"):
    raise SystemExit("WAYLAND_DISPLAY is required for analytic Screen Edge A/B")

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
QSB = (ROOT / "modules/screenCorners/ScreenEdgeField.frag.qsb").resolve()
assert QSB.is_file() and QSB.stat().st_size > 1000

QML = r'''
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell

ShellRoot {
    id: root
    property bool analytic: false
    property int frames: 0
    property bool busy: false

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 420
        implicitHeight: 260
        color: "transparent"

        Item {
            id: host
            anchors.fill: parent

            // Exact low-cost path immediately before the analytic cutover:
            // half-resolution source + GeometryRenderer + MultiEffect.
            Shape {
                id: legacy
                anchors.fill: parent
                visible: !root.analytic
                antialiasing: true
                preferredRendererType: Shape.GeometryRenderer
                layer.enabled: true
                layer.textureSize: Qt.size(
                    Math.ceil(width * 0.5), Math.ceil(height * 0.5))
                layer.smooth: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    blurMax: 15
                    shadowBlur: 1.0
                    autoPaddingEnabled: false
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    shadowColor: Qt.rgba(0, 0, 0, 0.70)
                }

                ShapePath {
                    id: path
                    fillColor: "#172630"
                    fillRule: ShapePath.OddEvenFill
                    strokeColor: "transparent"
                    strokeWidth: -1
                    readonly property real l: 10
                    readonly property real t: 10
                    readonly property real rgt: legacy.width - 10
                    readonly property real b: legacy.height - 10
                    readonly property real r: 25

                    startX: -50
                    startY: -50
                    PathLine { x: legacy.width + 50; y: -50 }
                    PathLine { x: legacy.width + 50; y: legacy.height + 50 }
                    PathLine { x: -50; y: legacy.height + 50 }
                    PathLine { x: -50; y: -50 }
                    PathMove { x: path.l + path.r; y: path.t }
                    PathLine { x: path.rgt - path.r; y: path.t }
                    PathArc { x: path.rgt; y: path.t + path.r; radiusX: path.r; radiusY: path.r; direction: PathArc.Clockwise }
                    PathLine { x: path.rgt; y: path.b - path.r }
                    PathArc { x: path.rgt - path.r; y: path.b; radiusX: path.r; radiusY: path.r; direction: PathArc.Clockwise }
                    PathLine { x: path.l + path.r; y: path.b }
                    PathArc { x: path.l; y: path.b - path.r; radiusX: path.r; radiusY: path.r; direction: PathArc.Clockwise }
                    PathLine { x: path.l; y: path.t + path.r }
                    PathArc { x: path.l + path.r; y: path.t; radiusX: path.r; radiusY: path.r; direction: PathArc.Clockwise }
                }
            }

            ShaderEffect {
                id: field
                anchors.fill: parent
                visible: root.analytic
                blending: true
                property vector4d viewport: Qt.vector4d(width, height, 0, 0)
                property vector4d insets: Qt.vector4d(10, 10, 10, 10)
                property color frameColor: "#172630"
                property color shadowColor: Qt.rgba(0, 0, 0, 0.70)
                property vector4d params: Qt.vector4d(25, 15, 0.75, 0)
                property vector4d tileRect: Qt.vector4d(0, 0, width, height)
                fragmentShader: Qt.resolvedUrl(Quickshell.env("EDGE_QSB"))
            }
        }
    }

    Timer {
        interval: 75
        repeat: true
        running: true
        onTriggered: {
            if (root.busy || ++root.frames < 6)
                return
            root.busy = true
            host.grabToImage(function(result) {
                const name = root.analytic ? "analytic.png" : "legacy.png"
                if (!result.saveToFile(Quickshell.env("EDGE_OUTPUT") + "/" + name)) {
                    console.error("EDGE_ANALYTIC_AB_FAIL_SAVE")
                    Qt.quit()
                    return
                }
                if (!root.analytic) {
                    root.analytic = true
                    root.frames = 0
                    root.busy = false
                } else {
                    console.info("EDGE_ANALYTIC_AB_CAPTURE_PASS")
                    Qt.quit()
                }
            })
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-edge-analytic-ab-") as tmp:
    root = Path(tmp)
    qml = root / "shell.qml"
    qml.write_text(QML, encoding="utf-8")
    env = os.environ.copy()
    env.update(
        QT_QPA_PLATFORM="wayland",
        EDGE_OUTPUT=str(root),
        EDGE_QSB=QSB.as_uri(),
    )
    run = subprocess.run(
        ["qs", "-p", str(root), "--no-color"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    assert run.returncode == 0 and "EDGE_ANALYTIC_AB_CAPTURE_PASS" in run.stdout, run.stdout[-4000:]

    legacy = Image.open(root / "legacy.png").convert("RGBA")
    analytic = Image.open(root / "analytic.png").convert("RGBA")
    assert legacy.size == analytic.size

    diff = ImageChops.difference(legacy, analytic)
    mean = ImageStat.Stat(diff).mean
    global_mae = sum(mean) / (4.0 * 255.0)

    # Report a stricter local diagnostic over the visible perimeter/elevation
    # region as well. Global <=1% is the maintainer's acceptance budget; the
    # edge metric prevents a small affected area from hiding a gross local
    # mismatch during manual review.
    lp = legacy.load()
    ap = analytic.load()
    dp = diff.load()
    affected_sum = 0
    affected_count = 0
    for y in range(legacy.height):
        for x in range(legacy.width):
            if lp[x, y][3] > 0 or ap[x, y][3] > 0:
                affected_sum += sum(dp[x, y])
                affected_count += 4
    edge_mae = (
        affected_sum / (affected_count * 255.0)
        if affected_count else 0.0
    )

    assert global_mae <= 0.01, (
        f"analytic Screen Edge exceeds 1% global mean pixel budget: {global_mae:.6f}"
    )

print(
    "SCREEN_EDGE_ANALYTIC_PERCEPTUAL_PASS "
    f"global_mae={global_mae:.6f} edge_mae={edge_mae:.6f}"
)
