#!/usr/bin/env python3
"""Silent offscreen Quickshell pixel + contract check for Quick Actions icons."""
import json
import os
import struct
import tempfile
import zlib
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]

# 1. Source contracts: MaterialSymbol & IconToolbarButton must default to Text.NativeRendering
ms_src = (ROOT / "modules" / "common" / "widgets" / "MaterialSymbol.qml").read_text()
assert "property int textRenderType: Text.NativeRendering" in ms_src, (
    "MaterialSymbol.qml must default textRenderType to Text.NativeRendering"
)
itb_src = (ROOT / "modules" / "common" / "widgets" / "IconToolbarButton.qml").read_text()
assert "property int iconRenderType: Text.NativeRendering" in itb_src, (
    "IconToolbarButton.qml must default iconRenderType to Text.NativeRendering"
)

ICONS = [
    "settings",
    "screenshot_region",
    "videocam",
    "stop_circle",
    "colorize",
    "edit_note",
    "keyboard",
    "keyboard_alt",
    "language",
    "mic",
    "mic_off",
    "cast",
    "cast_connected",
    "dark_mode",
    "light_mode",
    "eco",
    "balance",
    "energy_savings_leaf",
    "settings_slow_motion",
    "local_fire_department",
    "tune",
    "more_horiz",
    # Control icons that "keyboard" must remain visually distinct from:
    "work",
    "mail",
    "calendar_today",
]

QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

Window {
    id: root
    visible: true
    width: 1100
    height: 120
    color: "#11161d"

    readonly property var glyphNames: %s
    readonly property string outDir: %s

    Component.onCompleted: Quickshell.watchFiles = false

    Row {
        id: strip
        anchors.centerIn: parent
        spacing: 12

        Repeater {
            id: rep
            model: root.glyphNames
            delegate: Rectangle {
                required property string modelData
                width: 32
                height: 32
                color: "#11161d"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: modelData
                    iconSize: 20
                    color: "#ffffff"
                }
            }
        }
    }

    Timer {
        interval: 150
        running: true
        onTriggered: {
            let pending = rep.count
            for (let i = 0; i < rep.count; i++) {
                const item = rep.itemAt(i)
                const name = root.glyphNames[i]
                item.grabToImage(function(res) {
                    res.saveToFile(root.outDir + "/" + name + ".png")
                    pending--
                    if (pending === 0) {
                        console.info("QUICK_ACTIONS_ICONS_CAPTURED")
                        Qt.quit()
                    }
                })
            }
        }
    }
}
''' % (json.dumps(ICONS), json.dumps("__OUT_DIR__"))


def read_rgba_png(path: Path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path.name}: invalid PNG"
    pos = 8
    w = h = bit_depth = color_type = 0
    idat = bytearray()
    while pos < len(data):
        length = struct.unpack_from(">I", data, pos)[0]
        kind = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            w, h, bit_depth, color_type = struct.unpack_from(">IIBB", chunk)
        elif kind == b"IDAT":
            idat.extend(chunk)
        elif kind == b"IEND":
            break
    assert w > 0 and h > 0 and bit_depth == 8 and color_type in (2, 6), (
        f"{path.name}: unsupported PNG format {w}x{h} bd={bit_depth} ct={color_type}"
    )
    bpp = 4 if color_type == 6 else 3
    raw = zlib.decompress(bytes(idat))
    stride = w * bpp
    recon = bytearray(h * stride)
    for y in range(h):
        ftype = raw[y * (stride + 1)]
        src = y * (stride + 1) + 1
        dst = y * stride
        for x in range(stride):
            a = recon[dst + x - bpp] if x >= bpp else 0
            b = recon[dst - stride + x] if y > 0 else 0
            c = recon[dst - stride + x - bpp] if (x >= bpp and y > 0) else 0
            val = raw[src + x]
            if ftype == 0:
                p = 0
            elif ftype == 1:
                p = a
            elif ftype == 2:
                p = b
            elif ftype == 3:
                p = (a + b) >> 1
            elif ftype == 4:
                pa = abs(b - c)
                pb = abs(a - c)
                pc = abs(a + b - 2 * c)
                p = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            else:
                raise AssertionError(f"Unexpected PNG filter {ftype}")
            recon[dst + x] = (val + p) & 0xFF

    # Extract boolean foreground mask over #11161d background
    mask = []
    xs = []
    ys = []
    for y in range(h):
        for x in range(w):
            idx = y * stride + x * bpp
            r, g, b = recon[idx], recon[idx + 1], recon[idx + 2]
            fg = (r - 0x11) + (g - 0x16) + (b - 0x1D) > 320
            mask.append(fg)
            if fg:
                xs.append(x)
                ys.append(y)
    return w, h, mask, xs, ys


with tempfile.TemporaryDirectory(prefix="alis-icons-test-") as tmp:
    folder = Path(tmp)
    out_dir = folder / "pngs"
    out_dir.mkdir(parents=True, exist_ok=True)
    for entry in ["modules", "services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(QML.replace('"__OUT_DIR__"', json.dumps(str(out_dir))))

    config = folder / "config" / "alis"
    config.mkdir(parents=True, exist_ok=True)
    raw = json.loads((ROOT / "defaults" / "config.json").read_text())
    (config / "config.json").write_text(json.dumps(raw))

    env = {
        "QT_QPA_PLATFORM": "offscreen",
        "QT_QUICK_BACKEND": "software",
        "XDG_CONFIG_HOME": str(folder / "config"),
        "XDG_STATE_HOME": str(folder / "state"),
        "XDG_CACHE_HOME": str(folder / "cache"),
        "XDG_DATA_HOME": str(folder / "data"),
    }
    res = run_qs(folder, env, timeout=25)
    if res.returncode != 0 or "QUICK_ACTIONS_ICONS_CAPTURED" not in res.stdout:
        print(res.stdout)
        raise SystemExit(1)

    debug_copy = os.environ.get("ALIS_ICON_DUMP_DIR")
    if debug_copy:
        Path(debug_copy).mkdir(parents=True, exist_ok=True)
        for p in out_dir.glob("*.png"):
            (Path(debug_copy) / p.name).write_bytes(p.read_bytes())

    masks = {}
    for name in ICONS:
        png_path = out_dir / f"{name}.png"
        assert png_path.exists(), f"Missing PNG for {name}"
        w, h, mask, xs, ys = read_rgba_png(png_path)
        fg_count = len(xs)
        assert fg_count >= 12, f"{name}: too few foreground pixels ({fg_count})"
        bbox_w = max(xs) - min(xs) + 1
        bbox_h = max(ys) - min(ys) + 1
        aspect = bbox_w / max(1, bbox_h)
        density = fg_count / max(1, bbox_w * bbox_h)
        print(f"ICON {name:24s} fg={fg_count:4d} bbox={bbox_w:2d}x{bbox_h:2d} aspect={aspect:.2f} density={density:.2f}")
        assert bbox_w <= 22 and bbox_h <= 22, f"{name}: ASCII ligature fallback or clipping (bbox={bbox_w}x{bbox_h})"
        if name != "more_horiz":
            assert aspect <= 1.75, f"{name}: glyph aspect abnormal (bbox={bbox_w}x{bbox_h}, aspect={aspect:.2f})"
        assert 0.08 <= density <= 0.65, f"{name}: glyph contour density abnormal ({density:.2f}, fg={fg_count})"
        masks[name] = (fg_count, bbox_w, bbox_h, density, mask)

    kb_mask = masks["keyboard"][4]
    for other in ("work", "mail", "calendar_today"):
        diff = sum(1 for a, b in zip(kb_mask, masks[other][4]) if a != b)
        assert diff >= 25, f"'keyboard' too close to '{other}' (diff={diff}px)"

    kb = masks["keyboard"]
    print(f"QUICK_ACTIONS_ICONS_PASS count={len(ICONS)} keyboard_bbox={kb[1]}x{kb[2]} density={kb[3]:.2f}")
