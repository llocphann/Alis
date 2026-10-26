#!/usr/bin/env python3
"""Owner-session A/B: full-screen analytic field vs four perimeter tiles."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile

if os.environ.get("ALIS_SCREEN_EDGE_BANDED_PERCEPTUAL") != "1":
    print("SKIP: banded Screen Edge A/B requires ALIS_SCREEN_EDGE_BANDED_PERCEPTUAL=1")
    raise SystemExit(0)
if not shutil.which("qs"):
    raise SystemExit("qs is required for banded Screen Edge A/B")
if not os.environ.get("WAYLAND_DISPLAY"):
    raise SystemExit("WAYLAND_DISPLAY is required for banded Screen Edge A/B")

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
QSB = (ROOT / "modules/screenCorners/ScreenEdgeField.frag.qsb").resolve()
assert QSB.is_file() and QSB.stat().st_size > 1000

QML = r'''
import QtQuick
import Quickshell

ShellRoot {
    id: root
    property bool banded: false
    property int frames: 0
    property bool busy: false

    readonly property real inset: 10
    readonly property real radius: 25
    readonly property real shadow: 15
    readonly property real safeReach: Math.max(shadow, 2)
    readonly property real shallowExtent:
        Math.ceil(inset + safeReach)
    readonly property real deepExtent:
        Math.ceil(inset + radius + safeReach)


    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 420
        implicitHeight: 260
        color: "transparent"

        Item {
            id: host
            anchors.fill: parent

            component Field: ShaderEffect {
                blending: true
                property vector4d viewport: Qt.vector4d(host.width, host.height, 0, 0)
                property vector4d insets: Qt.vector4d(root.inset, root.inset, root.inset, root.inset)
                property color frameColor: "#172630"
                property color shadowColor: Qt.rgba(0, 0, 0, 0.70)
                property vector4d params: Qt.vector4d(root.radius, root.shadow, 0.75, 0)
                property vector4d tileRect: Qt.vector4d(x, y, width, height)
                fragmentShader: Qt.resolvedUrl(Quickshell.env("EDGE_QSB"))
            }

            Field {
                id: full
                anchors.fill: parent
                visible: !root.banded
            }

            Item {
                anchors.fill: parent
                visible: root.banded

                readonly property real hTop:
                    Math.min(height, root.deepExtent)
                readonly property real hBottom:
                    Math.min(Math.max(0, height - hTop), root.deepExtent)
                readonly property real hMiddle:
                    Math.max(0, height - hTop - hBottom)
                readonly property real hLeft:
                    Math.min(width, root.shallowExtent)
                readonly property real hRight:
                    Math.min(Math.max(0, width - hLeft), root.shallowExtent)
                readonly property real hArea:
                    width * (hTop + hBottom) + hMiddle * (hLeft + hRight)

                readonly property real vLeft:
                    Math.min(width, root.deepExtent)
                readonly property real vRight:
                    Math.min(Math.max(0, width - vLeft), root.deepExtent)
                readonly property real vMiddle:
                    Math.max(0, width - vLeft - vRight)
                readonly property real vTop:
                    Math.min(height, root.shallowExtent)
                readonly property real vBottom:
                    Math.min(Math.max(0, height - vTop), root.shallowExtent)
                readonly property real vArea:
                    height * (vLeft + vRight) + vMiddle * (vTop + vBottom)

                readonly property bool horizontal: hArea <= vArea

                Field {
                    x: parent.horizontal ? 0 : parent.vLeft
                    y: 0
                    width: parent.horizontal ? parent.width : parent.vMiddle
                    height: parent.horizontal ? parent.hTop : parent.vTop
                }
                Field {
                    x: parent.horizontal ? 0 : parent.vLeft
                    y: parent.height - (parent.horizontal
                        ? parent.hBottom : parent.vBottom)
                    width: parent.horizontal ? parent.width : parent.vMiddle
                    height: parent.horizontal ? parent.hBottom : parent.vBottom
                }
                Field {
                    x: 0
                    y: parent.horizontal ? parent.hTop : 0
                    width: parent.horizontal ? parent.hLeft : parent.vLeft
                    height: parent.horizontal ? parent.hMiddle : parent.height
                }
                Field {
                    x: parent.width - (parent.horizontal
                        ? parent.hRight : parent.vRight)
                    y: parent.horizontal ? parent.hTop : 0
                    width: parent.horizontal ? parent.hRight : parent.vRight
                    height: parent.horizontal ? parent.hMiddle : parent.height
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
                const name = root.banded ? "banded.png" : "full.png"
                if (!result.saveToFile(Quickshell.env("EDGE_OUTPUT") + "/" + name)) {
                    console.error("EDGE_BANDED_AB_FAIL_SAVE")
                    Qt.quit()
                    return
                }
                if (!root.banded) {
                    root.banded = true
                    root.frames = 0
                    root.busy = false
                } else {
                    console.info("EDGE_BANDED_AB_CAPTURE_PASS")
                    Qt.quit()
                }
            })
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-edge-banded-ab-") as tmp:
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
    assert run.returncode == 0 and "EDGE_BANDED_AB_CAPTURE_PASS" in run.stdout, run.stdout[-4000:]

    full = Image.open(root / "full.png").convert("RGBA")
    banded = Image.open(root / "banded.png").convert("RGBA")
    assert full.size == banded.size

    diff = ImageChops.difference(full, banded)
    mean = ImageStat.Stat(diff).mean
    global_mae = sum(mean) / (4.0 * 255.0)

    fp = full.load()
    bp = banded.load()
    dp = diff.load()
    affected_sum = 0
    affected_count = 0
    max_channel_delta = 0
    for y in range(full.height):
        for x in range(full.width):
            delta = dp[x, y]
            max_channel_delta = max(max_channel_delta, *delta)
            if fp[x, y][3] > 0 or bp[x, y][3] > 0:
                affected_sum += sum(delta)
                affected_count += 4
    edge_mae = (
        affected_sum / (affected_count * 255.0)
        if affected_count else 0.0
    )

    assert global_mae <= 0.01, (
        f"banded Screen Edge exceeds 1% global mean pixel budget: {global_mae:.6f}"
    )

print(
    "SCREEN_EDGE_BANDED_PERCEPTUAL_PASS "
    f"global_mae={global_mae:.6f} edge_mae={edge_mae:.6f} "
    f"max_channel_delta={max_channel_delta}"
)
