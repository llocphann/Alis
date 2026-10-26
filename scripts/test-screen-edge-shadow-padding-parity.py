#!/usr/bin/env python3
"""Require pixel-identical Screen Edge shadow with MultiEffect auto-padding disabled."""
from pathlib import Path
import os, shutil, subprocess, tempfile

if os.environ.get("ALIS_SCREEN_EDGE_PIXEL_PARITY") != "1":
    print("SKIP: Screen Edge pixel parity requires ALIS_SCREEN_EDGE_PIXEL_PARITY=1")
    raise SystemExit(0)

from PIL import Image, ImageChops
if not shutil.which("qs"):
    raise SystemExit("qs is required for Screen Edge shadow pixel parity")
if not os.environ.get("WAYLAND_DISPLAY"):
    raise SystemExit("WAYLAND_DISPLAY is required for Screen Edge shadow pixel parity")

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
    property int captures: 0

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
                preferredRendererType: Shape.CurveRenderer
                layer.enabled: true
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    blurMax: 15
                    shadowBlur: 1.0
                    autoPaddingEnabled: !root.optimized
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    shadowColor: Qt.rgba(0,0,0,0.70)
                }
                ShapePath {
                    id: path
                    fillColor: "#172630"
                    fillRule: ShapePath.OddEvenFill
                    strokeColor: "transparent"
                    strokeWidth: -1
                    readonly property real l: 10
                    readonly property real t: 10
                    readonly property real rgt: shape.width-10
                    readonly property real b: shape.height-10
                    readonly property real r: 25
                    startX: -50; startY: -50
                    PathLine { x: shape.width+50; y: -50 }
                    PathLine { x: shape.width+50; y: shape.height+50 }
                    PathLine { x: -50; y: shape.height+50 }
                    PathLine { x: -50; y: -50 }
                    PathMove { x: path.l+path.r; y: path.t }
                    PathLine { x: path.rgt-path.r; y: path.t }
                    PathArc { x:path.rgt; y:path.t+path.r; radiusX:path.r; radiusY:path.r; direction:PathArc.Clockwise }
                    PathLine { x:path.rgt; y:path.b-path.r }
                    PathArc { x:path.rgt-path.r; y:path.b; radiusX:path.r; radiusY:path.r; direction:PathArc.Clockwise }
                    PathLine { x:path.l+path.r; y:path.b }
                    PathArc { x:path.l; y:path.b-path.r; radiusX:path.r; radiusY:path.r; direction:PathArc.Clockwise }
                    PathLine { x:path.l; y:path.t+path.r }
                    PathArc { x:path.l+path.r; y:path.t; radiusX:path.r; radiusY:path.r; direction:PathArc.Clockwise }
                }
            }
        }
    }

    Timer {
        interval: 60
        repeat: true
        running: true
        onTriggered: {
            if (root.busy || ++root.frames < 5) return
            root.busy = true
            host.grabToImage(function(result) {
                const name=root.optimized ? "after.png" : "before.png"
                if (!result.saveToFile(Quickshell.env("EDGE_OUTPUT")+"/"+name)) {
                    console.error("EDGE_PARITY_FAIL_SAVE")
                    Qt.quit()
                    return
                }
                root.captures++
                if (!root.optimized) {
                    root.optimized=true
                    root.frames=0
                    root.busy=false
                } else {
                    console.info("EDGE_PARITY_CAPTURE_PASS",root.captures)
                    Qt.quit()
                }
            })
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-edge-shadow-") as tmp:
    root=Path(tmp)
    (root/"shell.qml").write_text(QML, encoding="utf-8")
    env=os.environ.copy()
    env.update(QT_QPA_PLATFORM="wayland", EDGE_OUTPUT=str(root))
    run=subprocess.run(["qs","-p",str(root),"--no-color"],env=env,text=True,
                       stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=15)
    assert run.returncode == 0 and "EDGE_PARITY_CAPTURE_PASS" in run.stdout, run.stdout[-4000:]
    before=Image.open(root/"before.png").convert("RGBA")
    after=Image.open(root/"after.png").convert("RGBA")
    diff=ImageChops.difference(before,after)
    changed=sum(any(px) for px in diff.getdata())
    maximum=max(high for _,high in diff.getextrema())
    assert changed == 0 and maximum == 0, (
        f"Screen Edge auto-padding changed visible pixels: changed={changed}, max={maximum}"
    )

print("SCREEN_EDGE_SHADOW_PADDING_PIXEL_PARITY_PASS")
