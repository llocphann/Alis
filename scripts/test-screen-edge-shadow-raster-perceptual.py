#!/usr/bin/env python3
"""Owner-session A/B budget for low-cost Screen Edge shadow rendering."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

if os.environ.get("ALIS_SCREEN_EDGE_PERCEPTUAL") != "1":
    print("SKIP: Screen Edge perceptual A/B requires ALIS_SCREEN_EDGE_PERCEPTUAL=1")
    raise SystemExit(0)
if not shutil.which("qs"):
    raise SystemExit("qs is required for Screen Edge perceptual A/B")
if not os.environ.get("WAYLAND_DISPLAY"):
    raise SystemExit("WAYLAND_DISPLAY is required for Screen Edge perceptual A/B")

from PIL import Image, ImageChops, ImageStat

QML = r'''
import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import Quickshell

ShellRoot {
    id: root
    property bool optimized: false
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
            Shape {
                id: shape
                anchors.fill: parent
                antialiasing: true
                preferredRendererType: root.optimized
                    ? Shape.GeometryRenderer : Shape.CurveRenderer
                layer.enabled: true
                layer.textureSize: root.optimized
                    ? Qt.size(Math.ceil(width * 0.5), Math.ceil(height * 0.5))
                    : Qt.size(width, height)
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
                    readonly property real rgt: shape.width - 10
                    readonly property real b: shape.height - 10
                    readonly property real r: 25
                    startX: -50
                    startY: -50
                    PathLine { x: shape.width + 50; y: -50 }
                    PathLine { x: shape.width + 50; y: shape.height + 50 }
                    PathLine { x: -50; y: shape.height + 50 }
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
                const name = root.optimized ? "half.png" : "full.png"
                if (!result.saveToFile(Quickshell.env("EDGE_OUTPUT") + "/" + name)) {
                    console.error("EDGE_PERCEPTUAL_FAIL_SAVE")
                    Qt.quit()
                    return
                }
                if (!root.optimized) {
                    root.optimized = true
                    root.frames = 0
                    root.busy = false
                } else {
                    console.info("EDGE_PERCEPTUAL_CAPTURE_PASS")
                    Qt.quit()
                }
            })
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-edge-perceptual-") as tmp:
    root = Path(tmp)
    qml = root / "shell.qml"
    qml.write_text(QML, encoding="utf-8")
    env = os.environ.copy()
    env.update(QT_QPA_PLATFORM="wayland", EDGE_OUTPUT=str(root))
    run = subprocess.run(
        ["qs", "-p", str(root), "--no-color"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=20,
    )
    assert run.returncode == 0 and "EDGE_PERCEPTUAL_CAPTURE_PASS" in run.stdout, run.stdout[-4000:]

    full = Image.open(root / "full.png").convert("RGBA")
    half = Image.open(root / "half.png").convert("RGBA")
    assert full.size == half.size
    diff = ImageChops.difference(full, half)
    mean = ImageStat.Stat(diff).mean
    normalized_mae = sum(mean) / (4.0 * 255.0)
    # The maintainer explicitly permits up to ~1% visual deviation in exchange
    # for substantial Screen Edge savings. Keep the acceptance metric global
    # and deterministic; geometry/contract tests separately lock the silhouette.
    assert normalized_mae <= 0.01, (
        f"Screen Edge half-raster exceeds 1% mean pixel budget: {normalized_mae:.6f}"
    )

print(f"SCREEN_EDGE_LOW_COST_PERCEPTUAL_PASS mae={normalized_mae:.6f}")
