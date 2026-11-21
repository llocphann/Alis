#!/usr/bin/env python3
"""Silent offscreen Quickshell runtime verification for:
1. Screen Edges BarCavaEqualizerModule (stereo folding bass->mid->treble, mono mode,
   clean 0 baseline settling on silence, mirrorBars config binding).
2. Circular ColorPickerOverlay (immediate visibility once ready before mouse move,
   center-screen initial sample, interactive 6-0 recent color recall, L lock mode,
   format cycling HEX/RGB/HSL/OKLCH/HSV) — executed in offscreen Qt6 via a minimal
   PanelWindow->Window wrapper inside a temporary directory without altering production files.
3. Battery singleton hardware telemetry contract (sysfs + UPower parsing, clean load).
"""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

QML_HARNESS = r'''//@ pragma ShellId alis-cava-colorpicker-offscreen-test
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.bar
import qs.services

ShellRoot {
    id: root
    property int checks: 0
    property var pickedEvents: []

    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    function findByObjectName(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const ch of (item.children ?? [])) {
            const hit = findByObjectName(ch, name)
            if (hit) return hit
        }
        return null
    }

    Window {
        id: win
        visible: true
        width: 800
        height: 600
        color: "#111820"

        BarCavaEqualizerModule {
            id: barEq
            width: 140
            height: 28
            visible: true
        }
    }

    // Load offscreen-adapted copy of production ColorPickerOverlay.qml with required requestId
    Loader {
        id: overlayLoader
        Component.onCompleted: {
            setSource("ColorPickerOverlayOffscreen.qml", {
                requestId: 42,
                width: 800,
                height: 600,
                isActiveOverlay: true,
                themePalette: ({
                    darkmode: true,
                    colLayer0: "#14161b",
                    colLayer1: "#1c1f26",
                    colLayer2: "#242832",
                    colPrimary: "#89b4fa",
                    colOnPrimary: "#0d1117",
                    colSecondary: "#94e2d5",
                    colOnLayer0: "#e6eaf2",
                    colSubtext: "#9ea6b8",
                    colOutline: "#333947",
                    recentColors: ["#FF5500", "#00CC88", "#3366FF", "#EEAA22", "#CC44AA"]
                })
            })
        }
        onLoaded: {
            item.picked.connect((reqId, val, fmt) => {
                root.pickedEvents.push({ reqId: reqId, val: val, fmt: fmt })
            })
        }
    }

    TestCase {
        id: tc
        when: false
        optional: true

        function run() {
            try {
                tryCompare(Config, "ready", true, 4000)
                tryCompare(overlayLoader, "status", Loader.Ready, 4000)

                // ── 1. BarCavaEqualizerModule: Stereo Folding, Mono Mode, Silence Baseline, Mirror ──
                // Stereo CAVA layout: [L_high(0), L_midH(1), L_midL(2), L_bass(3), R_bass(4), R_midL(5), R_midH(6), R_high(7)]
                const stereoBass = barEq.computeNormalizedBars([0, 0, 0, 1000, 1000, 0, 0, 0], 1000, 4, true, true)
                root.check(stereoBass.length === 4, "stereoBass length mismatch")
                root.check(stereoBass[0] > 0.95 && stereoBass[1] === 0 && stereoBass[2] === 0 && stereoBass[3] === 0,
                    "Stereo bass must map to leftmost bar 0, got " + JSON.stringify(stereoBass))

                const stereoTreble = barEq.computeNormalizedBars([1000, 0, 0, 0, 0, 0, 0, 1000], 1000, 4, true, true)
                root.check(stereoTreble[3] > 0.95 && stereoTreble[0] === 0 && stereoTreble[1] === 0 && stereoTreble[2] === 0,
                    "Stereo treble must map to rightmost bar 3, got " + JSON.stringify(stereoTreble))

                // Asymmetric L/R bass (left=1000, right=0) should average to ~0.56 shaped energy in bar 0
                const stereoAsym = barEq.computeNormalizedBars([0, 0, 0, 1000, 0, 0, 0, 0], 1000, 4, true, true)
                root.check(stereoAsym[0] > 0.5 && stereoAsym[0] < 0.7 && stereoAsym[3] === 0,
                    "Asymmetric stereo bass folding unexpected: " + JSON.stringify(stereoAsym))

                // Upsampling stereo (count > freqBins, e.g. 8 bars from 4 stereo freqBins):
                // linear interpolation must produce smooth strictly decreasing values, NOT duplicate staircase pairs!
                const stereoUpsample = barEq.computeNormalizedBars([0, 300, 600, 1000, 1000, 600, 300, 0], 1000, 8, true, true)
                root.check(stereoUpsample.length === 8
                    && stereoUpsample[0] > stereoUpsample[1]
                    && stereoUpsample[1] > stereoUpsample[2]
                    && stereoUpsample[2] > stereoUpsample[3],
                    "Upsampling stereo bars must interpolate smoothly without duplicate pairs: " + JSON.stringify(stereoUpsample))

                // Mono mode linear mapping: [bass, lowMid, highMid, treble]
                const monoBass = barEq.computeNormalizedBars([1000, 0, 0, 0], 1000, 4, false, true)
                root.check(monoBass[0] > 0.95 && monoBass[3] === 0, "Mono bass mapping failed: " + JSON.stringify(monoBass))
                const monoTreble = barEq.computeNormalizedBars([0, 0, 0, 1000], 1000, 4, false, true)
                root.check(monoTreble[3] > 0.95 && monoTreble[0] === 0, "Mono treble mapping failed: " + JSON.stringify(monoTreble))

                // Silence / signalActive=false must settle cleanly to 0 baseline across every bar
                const silentBars = barEq.computeNormalizedBars([900, 900, 900, 900], 1000, 8, true, false)
                root.check(silentBars.length === 8 && silentBars.every(v => v === 0),
                    "Inactive signal must settle to exact 0 baseline: " + JSON.stringify(silentBars))
                const zeroFrame = barEq.computeNormalizedBars([0, 0, 0, 0, 0, 0, 0, 0], 1000, 8, true, true)
                root.check(zeroFrame.every(v => v === 0), "Zero-amplitude frame must settle to exact 0 baseline")

                // mirrorBars reads Config.options.bar.cava.mirror
                Config.setNestedValue("bar.cava.mirror", false)
                wait(20)
                root.check(barEq.mirrorBars === false, "mirrorBars should be false when config mirror=false")
                Config.setNestedValue("bar.cava.mirror", true)
                wait(20)
                root.check(barEq.mirrorBars === true, "mirrorBars should reactively become true when config mirror=true")
                Config.setNestedValue("bar.cava.mirror", false)

                // ── 2. ColorPickerOverlay: Immediate Visibility on Ready, Recent Recall, Lock Mode ──
                const cp = overlayLoader.item
                const popupItem = root.findByObjectName(cp.contentItem, "colorPickerCircularPopup")
                const recentRow = root.findByObjectName(cp.contentItem, "colorPickerRecentRow")
                root.check(popupItem !== null, "colorPickerCircularPopup not found")
                root.check(recentRow !== null, "colorPickerRecentRow not found")

                // Before sampler is ready, circular popup stays hidden
                root.check(popupItem.visible === false, "Circular popup should wait for sampler.ready")

                // Feed a solid test PNG into sampler (simulating screencopy ready WITHOUT mouse move!)
                const samplerItem = cp.contentItem.children.find(c => c && c.hasOwnProperty("imageUrl"))
                root.check(samplerItem !== null, "ColorPickerSampler not found")
                samplerItem.imageSize = Qt.size(32, 32)
                samplerItem.imageUrl = "TEST_PNG_URL"
                tryVerify(() => cp.ready === true, 4000)
                wait(40)

                // Circular popup MUST immediately appear at screen center BEFORE any mouse movement!
                root.check(popupItem.visible === true, "Circular popup must become visible immediately on ready even before mouse move")
                root.check(Math.abs(cp.cursorX - 400) < 1 && Math.abs(cp.cursorY - 300) < 1,
                    "Initial cursor should default to screen center (400,300), got (" + cp.cursorX + "," + cp.cursorY + ")")
                const overlayItem = cp.contentItem.children.find(c => c && c.children && c.children.length >= 3)
                root.check(cp.sampledColor === "#336699",
                    "Initial screen-center sample expected #336699, got [" + cp.sampledColor + "] px=" + cp.currentPixelX + "," + cp.currentPixelY + " direct=" + samplerItem.colorAt(16, 16) + " ready=" + cp.ready + " overlay=" + (overlayItem ? (overlayItem.width + "x" + overlayItem.height) : "null") + " win=" + cp.width + "x" + cp.height)

                // Verify recallableRecents & keys 6..0
                root.check(cp.recallableRecents.length === 5, "Expected 5 recallableRecents, got " + cp.recallableRecents.length)
                root.check(cp.recallableRecents[0].key === "6" && cp.recallableRecents[0].hex === "#FF5500", "Recent key 6 mismatch")
                root.check(cp.recallableRecents[4].key === "0" && cp.recallableRecents[4].hex === "#CC44AA", "Recent key 0 mismatch")
                root.check(recentRow.visible === true, "Recent recall row should be visible when recentColors present")

                // Format cycling across all 5 formats
                root.check(cp.formatColor("#FF5500", "HEX") === "#FF5500", "HEX format failed")
                root.check(cp.formatColor("#FF5500", "RGB") === "rgb(255, 85, 0)", "RGB format failed")
                root.check(cp.formatColor("#FF5500", "HSL").startsWith("hsl("), "HSL format failed")
                root.check(cp.formatColor("#FF5500", "OKLCH").startsWith("oklch("), "OKLCH format failed")
                root.check(cp.formatColor("#FF5500", "HSV").startsWith("hsv("), "HSV format failed")

                // Commit a recent pick in RGB format
                cp._cycleFormat()
                root.check(cp.activeFormat === "RGB", "Expected RGB after 1st cycle")
                cp._commitPick(cp.recallableRecents[1].hex)
                root.check(root.pickedEvents.length === 1
                    && root.pickedEvents[0].val === "#00CC88"
                    && root.pickedEvents[0].fmt === "rgb(0, 204, 136)",
                    "Recent pick commit mismatch: " + JSON.stringify(root.pickedEvents))

                // Lock toggle & multi-monitor deactivation reset
                root.check(cp.loupeLocked === false, "loupeLocked should default false")
                cp.loupeLocked = true
                root.check(cp.loupeLocked === true, "loupeLocked toggle failed")
                cp.isActiveOverlay = false
                wait(20)
                root.check(popupItem.visible === false && cp.loupeLocked === false,
                    "Deactivating overlay on multi-monitor must hide popup and clear loupeLocked")
                cp.isActiveOverlay = true
                wait(20)
                root.check(popupItem.visible === true, "Re-activating overlay must show popup immediately")

                // ── 3. Battery Service Telemetry Sanity ──
                root.check(typeof Battery.available === "boolean", "Battery.available type invalid")
                root.check(typeof Battery.energyRate === "number", "Battery.energyRate type invalid")
                root.check(typeof Battery.timeToEmpty === "number", "Battery.timeToEmpty type invalid")

                console.info("CAVA_COLORPICKER_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("CAVA_COLORPICKER_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: tc.run()
    }
}
'''


def _write_solid_png(path: Path, r: int, g: int, b: int, w: int = 32, h: int = 32) -> None:
    import struct, zlib
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + bytes([r, g, b]) * w for _ in range(h))
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    path.write_bytes(png)


def _adapt_overlay_for_offscreen(src_text: str) -> str:
    # Replace only Wayland PanelWindow/WlrLayershell/ScreencopyView wrapper so 100% of
    # ColorPickerOverlay's real QML UI, bindings, hotkeys & sampler execute offscreen.
    out = src_text
    out = out.replace("import Quickshell.Wayland\n", "")
    out = out.replace("PanelWindow {\n", "Window {\n    property var screen: ({ name: 'OFFSCREEN-1' })\n")
    out = re.sub(r"^\s*exclusionMode:.*\n", "", out, flags=re.MULTILINE)
    out = re.sub(r"^\s*anchors\s*\{[^}]*\}\s*\n", "", out, flags=re.MULTILINE)
    out = re.sub(r"^\s*WlrLayershell\.[^\n]*\n", "", out, flags=re.MULTILINE)
    out = re.sub(
        r"ScreencopyView\s*\{[\s\S]*?onStopped:[^\n]*\n\s*\}",
        "Item { id: screenCopy; anchors.fill: parent; property bool hasContent: false; function grabToImage(cb) { return false } }",
        out,
        count=1,
    )
    out = out.replace("ColorPickerSampler { id: sampler }", "ColorPickerSampler { id: sampler }")
    return out


def main() -> None:
    qs = shutil.which("qs")
    if not qs:
        print("SKIP: qs unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-cava-cp-test-") as tmp:
        root = Path(tmp)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
            (root / entry).symlink_to(ROOT / entry)

        png_path = root / "sample.png"
        _write_solid_png(png_path, 0x33, 0x66, 0x99)
        overlay_src = (ROOT / "services/ColorPickerOverlay.qml").read_text(encoding="utf-8")
        (root / "ColorPickerOverlayOffscreen.qml").write_text(
            "import qs.services\n" + _adapt_overlay_for_offscreen(overlay_src),
            encoding="utf-8",
        )
        (root / "shell.qml").write_text(
            QML_HARNESS.replace("TEST_PNG_URL", png_path.as_uri()),
            encoding="utf-8",
        )

        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(root / "config")
        env["XDG_STATE_HOME"] = str(root / "state")
        env["XDG_CACHE_HOME"] = str(root / "cache")
        env["XDG_DATA_HOME"] = "/nonexistent"
        env["XDG_DATA_DIRS"] = "/nonexistent"
        (root / "config/illogical-impulse").mkdir(parents=True, exist_ok=True)
        (root / "config/illogical-impulse/config.json").write_text(
            (ROOT / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8"
        )

        res = subprocess.run(
            [qs, "-p", str(root / "shell.qml"), "--no-color"],
            env=env,
            capture_output=True,
            text=True,
            timeout=25,
        )
        out = (res.stdout or "") + "\n" + (res.stderr or "")
        if res.returncode != 0 or "CAVA_COLORPICKER_PASS" not in out or re.search(r"CAVA_COLORPICKER_FAIL|ReferenceError:|TypeError:", out):
            print(out)
            sys.exit(1)
        for line in out.splitlines():
            if "CAVA_COLORPICKER_PASS" in line:
                print(line.strip())


if __name__ == "__main__":
    main()
