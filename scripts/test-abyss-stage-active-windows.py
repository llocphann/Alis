#!/usr/bin/env python3
"""Silent regression test for Change Wallpaper scaled & auto-themed active windows."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_shader_qsb_fresh() -> None:
    qsb = Path("/usr/lib/qt6/bin/qsb")
    frag = ROOT / "modules/abyss/looks/AbyssStageWindowTheme.frag"
    qsb_out = ROOT / "modules/abyss/looks/AbyssStageWindowTheme.frag.qsb"
    assert frag.is_file() and qsb_out.is_file(), "Shader source or compiled .qsb missing"
    if not qsb.exists():
        print("SKIP: qsb compiler unavailable")
        return
    with tempfile.TemporaryDirectory(prefix="alis-qsb-check-") as tmp:
        rebuilt = Path(tmp) / "rebuilt.frag.qsb"
        res = subprocess.run(
            [str(qsb), "--qt6", "-o", str(rebuilt), str(frag)],
            capture_output=True,
            text=True,
        )
        assert res.returncode == 0, f"qsb compile failed: {res.stderr}"
        assert rebuilt.read_bytes() == qsb_out.read_bytes(), (
            "AbyssStageWindowTheme.frag.qsb is stale compared to AbyssStageWindowTheme.frag"
        )
    print("STAGE_ACTIVE_WINDOWS_SHADER_QSB_PASS")


def test_source_contracts() -> None:
    perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    stage_windows = (ROOT / "modules/abyss/looks/AbyssStageActiveWindows.qml").read_text(encoding="utf-8")
    qmldir = (ROOT / "modules/abyss/looks/qmldir").read_text(encoding="utf-8")

    assert 'stageCapturesDesktop: window.editStageMode === "abyss"' in perimeter
    assert '|| (window.editStageMode === "wallpaper" && window.desktopHasApps)' in perimeter, (
        "wallpaper stage with active apps must capture desktop interior at scaled coords"
    )
    assert "id: stageActiveWindowsLoader" in perimeter
    assert "sourceComponent: Component {" in perimeter
    assert "AbyssStageActiveWindows {" in perimeter
    assert "captureScreen: window.screen" in perimeter
    assert "stageVisible: window.editStageVisible" in perimeter
    assert "target: stageActiveWindowsLoader.item ?? null" in perimeter
    assert "function onCaptureReadyChanged()" in perimeter
    assert "const waitStageCapture = window.editStageMode === \"wallpaper\"" in perimeter
    assert "visible: window.editStageVisible && !window.widgetStageEditing && window.desktopHasApps" in perimeter
    assert "AbyssStageActiveWindows 1.0 AbyssStageActiveWindows.qml" in qmldir

    for tok in (
        "ScreencopyView",
        "grabToImage",
        "frozenScreenImage",
        "fallbackShader",
        "captureTimeoutTimer",
        "AbyssStageWindowTheme.frag.qsb",
        "StageWindowLayout.isAppAutoThemed",
        "StageWindowLayout.subRectUv",
        "ColorAnimation",
    ):
        assert tok in stage_windows, f"AbyssStageActiveWindows missing token: {tok}"
    print("STAGE_ACTIVE_WINDOWS_SOURCE_CONTRACT_PASS")


def test_js_layout() -> None:
    js_path = ROOT / "modules/abyss/looks/AbyssStageWindowLayout.js"
    src = js_path.read_text(encoding="utf-8")
    program = src + r"""
const assert = require("node:assert/strict");

const IN = { left: 10, right: 10, top: 48, bottom: 10 };
const W = 1920, H = 1200; // workW = 1900, workH = 1142
const WS = [
    { id: 1, idx: 1, output: "eDP-1", is_active: false, active_window_id: 7 },
    { id: 2, idx: 2, output: "eDP-1", is_active: true, active_window_id: 3 },
    { id: 9, idx: 1, output: "HDMI-A-1", is_active: true, active_window_id: 99 }
];

// 1. Single tiled centered window matching real Niri layout
{
    const wins = [
        { id: 3, app_id: "antigravity", title: "Antigravity", workspace_id: 2, is_focused: true, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [1850, 1102], window_size: [1850, 1102], tile_pos_in_workspace_view: null } },
        { id: 7, app_id: "kitty", title: "OtherWS", workspace_id: 1, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [900, 900] } },
        { id: 99, app_id: "firefox", title: "OtherOut", workspace_id: 9, is_focused: true, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [1000, 900] } }
    ];
    const items = layoutNiriWorkspaceWindows(wins, WS, "eDP-1", W, H, IN);
    assert.equal(items.length, 1);
    assert.equal(items[0].id, 3);
    assert.equal(items[0].x, 10 + Math.round((1900 - 1850) / 2)); // 35
    assert.equal(items[0].y, 48 + Math.round((1142 - 1102) / 2)); // 68
    assert.equal(items[0].width, 1850);
    assert.equal(items[0].height, 1102);
    assert.equal(items[0].z, 1);
}

// 2. Two side-by-side columns fitting inside workW -> centered strip with 15px gap
{
    const wins = [
        { id: 10, app_id: "kitty", title: "Left", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [920, 1100] } },
        { id: 11, app_id: "firefox", title: "Right", workspace_id: 2, is_focused: true, is_floating: false, layout: { pos_in_scrolling_layout: [2, 1], tile_size: [920, 1100] } }
    ];
    const items = layoutNiriWorkspaceWindows(wins, WS, "eDP-1", W, H, IN);
    assert.equal(items.length, 2);
    const totalW = 920 + 15 + 920; // 1855
    const startX = 10 + Math.round((1900 - totalW) / 2); // 33
    assert.equal(items[0].x, startX);
    assert.equal(items[1].x, startX + 920 + 15);
}

// 3. Overflowing 3 columns -> focused column stays inside work bounds, off-screen C1 & C3 excluded when non-intersecting
{
    const wins = [
        { id: 20, app_id: "a", title: "C1", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [1900, 1100] }, focus_timestamp: { secs: 100, nanos: 0 } },
        { id: 21, app_id: "b", title: "C2", workspace_id: 2, is_focused: true, is_floating: false, layout: { pos_in_scrolling_layout: [2, 1], tile_size: [1900, 1100] }, focus_timestamp: { secs: 200, nanos: 0 } },
        { id: 22, app_id: "c", title: "C3", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [3, 1], tile_size: [1900, 1100] }, focus_timestamp: { secs: 50, nanos: 0 } }
    ];
    const items = layoutNiriWorkspaceWindows(wins, WS, "eDP-1", W, H, IN);
    assert(items.some(w => w.id === 21));
    const c2 = items.find(w => w.id === 21);
    assert(c2.x >= IN.left && c2.x + c2.width <= W - IN.right);
    assert(!items.some(w => w.id === 20), "off-screen column C1 should be excluded from visible desktop windows");
    assert(!items.some(w => w.id === 22), "off-screen column C3 should be excluded from visible desktop windows");
}

// 3b. Unfocused visible window (clicked outside onto desktop, active_window_id null) + overflow focus_timestamp anchor
{
    const unfocusedWs = [
        { id: 2, idx: 2, output: "eDP-1", is_active: true, active_window_id: null }
    ];
    const wins = [
        { id: 40, app_id: "kitty", title: "Older", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [1890, 1100] }, focus_timestamp: { secs: 100, nanos: 0 } },
        { id: 41, app_id: "org.alis.Files", title: "Alis Files", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [2, 1], tile_size: [1890, 1100] }, focus_timestamp: { secs: 500, nanos: 0 } }
    ];
    const items = layoutNiriWorkspaceWindows(wins, unfocusedWs, "eDP-1", W, H, IN);
    assert.equal(items.length, 1);
    assert.equal(items[0].id, 41);
    assert.equal(items[0].appId, "org.alis.Files");
}

// 4. Stacked vertical rows + floating window overlay (z: 2)
{
    const wins = [
        { id: 30, app_id: "a", title: "Top", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [1, 1], tile_size: [920, 540] } },
        { id: 31, app_id: "b", title: "Bot", workspace_id: 2, is_focused: false, is_floating: false, layout: { pos_in_scrolling_layout: [1, 2], tile_size: [920, 540] } },
        { id: 32, app_id: "settings", title: "Float", workspace_id: 2, is_focused: true, is_floating: true, layout: { tile_size: [800, 600], tile_pos_in_workspace_view: [400, 200] } }
    ];
    const items = layoutNiriWorkspaceWindows(wins, WS, "eDP-1", W, H, IN);
    assert.equal(items.length, 3);
    assert(items[1].y > items[0].y + items[0].height);
    assert.equal(items[2].z, 2);
    assert.equal(items[2].x, IN.left + 400);
    assert.equal(items[2].y, IN.top + 200);
}

// 5. Shadow-padded screenshot alignment + UV subrect normalization
{
    const g1 = previewImageGeometry(1850, 1102, 1882, 1144);
    assert.equal(g1.fillMode, "pad");
    assert.equal(g1.x, -16);
    assert.equal(g1.y, -16);

    const uv = subRectUv(35, 68, 1850, 1102, 1920, 1200);
    assert(Math.abs(uv.u0 - 35 / 1920) < 1e-6);
    assert(Math.abs(uv.v0 - 68 / 1200) < 1e-6);
    assert(Math.abs(uv.uw - 1850 / 1920) < 1e-6);
    assert(Math.abs(uv.vh - 1102 / 1200) < 1e-6);
}

// 6. Auto-theming app eligibility matrix
{
    const autoCfg = {
        theme: "auto",
        wallpaperTheming: {
            enableAppsAndShell: true,
            enableVSCode: true,
            enableTerminal: true,
            enableQtApps: true,
            enableChrome: true,
            enableSpicetify: true,
            enableSteam: true,
            vscodeEditors: { antigravity: true, code: false },
            terminals: { kitty: true, alacritty: false }
        }
    };
    assert.equal(isAppAutoThemed("antigravity", autoCfg), true);
    assert.equal(isAppAutoThemed("code", autoCfg), false);
    assert.equal(isAppAutoThemed("kitty", autoCfg), true);
    assert.equal(isAppAutoThemed("alacritty", autoCfg), false);
    assert.equal(isAppAutoThemed("org.alis.Files", autoCfg), true);
    assert.equal(isAppAutoThemed("alis-files", autoCfg), true);
    assert.equal(isAppAutoThemed("org.gnome.Nautilus", autoCfg), true);
    assert.equal(isAppAutoThemed("org.kde.dolphin", autoCfg), true);
    assert.equal(isAppAutoThemed("org.mozilla.firefox", autoCfg), true);
    assert.equal(isAppAutoThemed("app.zen_browser.zen", autoCfg), true);
    assert.equal(isAppAutoThemed("spotify", autoCfg), true);
    assert.equal(isAppAutoThemed("steam", autoCfg), true);
    assert.equal(isAppAutoThemed("steam_app_730", autoCfg), false);
    assert.equal(isAppAutoThemed("mpv", autoCfg), false);
    assert.equal(isAppAutoThemed("unknown-game-bin", autoCfg), false);
    assert.equal(isAppAutoThemed("antigravity", { theme: "gruvbox", wallpaperTheming: autoCfg.wallpaperTheming }), false);
    assert.equal(isAppAutoThemed("antigravity", { theme: "auto", wallpaperTheming: { enableAppsAndShell: false } }), false);
}

console.log("STAGE_ACTIVE_WINDOWS_JS_PASS");
"""
    res = subprocess.run(["node"], input=program, cwd=ROOT, capture_output=True, text=True)
    if res.returncode != 0 or "STAGE_ACTIVE_WINDOWS_JS_PASS" not in res.stdout:
        print(res.stdout)
        print(res.stderr)
        sys.exit(1)
    print("STAGE_ACTIVE_WINDOWS_JS_PASS")


def test_qml_lint() -> None:
    if not shutil.which("fish"):
        print("SKIP: fish unavailable")
        return
    res = subprocess.run(
        ["fish", "scripts/qml-check.fish", "modules/abyss/looks/AbyssStageActiveWindows.qml", "modules/abyss/AbyssPerimeter.qml"],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        print(res.stdout)
        print(res.stderr)
        sys.exit(1)
    print("STAGE_ACTIVE_WINDOWS_QML_CHECK_PASS")


def test_qml_runtime() -> None:
    if not shutil.which("qs"):
        print("SKIP: qs unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-stage-active-wins-") as tmp:
        folder = Path(tmp)
        looks_dir = folder / "modules/abyss/looks"
        looks_dir.mkdir(parents=True)
        (looks_dir / "AbyssStageActiveWindows.qml").symlink_to(ROOT / "modules/abyss/looks/AbyssStageActiveWindows.qml")
        (looks_dir / "AbyssStageWindowLayout.js").symlink_to(ROOT / "modules/abyss/looks/AbyssStageWindowLayout.js")
        (looks_dir / "AbyssStageWindowTheme.frag.qsb").symlink_to(ROOT / "modules/abyss/looks/AbyssStageWindowTheme.frag.qsb")

        svc_dir = folder / "services"
        svc_dir.mkdir()
        (svc_dir / "qmldir").write_text(
            "module qs.services\n"
            "singleton CompositorService 1.0 CompositorService.qml\n"
            "singleton NiriService 1.0 NiriService.qml\n"
            "singleton MaterialThemeLoader 1.0 MaterialThemeLoader.qml\n"
            "singleton WindowPreviewService 1.0 WindowPreviewService.qml\n"
            "singleton AppSearch 1.0 AppSearch.qml\n"
            "singleton RecorderStatus 1.0 RecorderStatus.qml\n"
            "singleton GameMode 1.0 GameMode.qml\n",
            encoding="utf-8",
        )
        (svc_dir / "CompositorService.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool isNiri: true; property bool isHyprland: false }\n", encoding="utf-8")
        (svc_dir / "NiriService.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property var allWorkspaces: []; property var windows: [] }\n", encoding="utf-8")
        (svc_dir / "MaterialThemeLoader.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool previewActive: false; property var _previewBaseline: null }\n", encoding="utf-8")
        (svc_dir / "WindowPreviewService.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property var previewCache: ({})\n"
            "  function getPreviewUrl(id) { return previewCache[id]?.path ?? '' }\n"
            "}\n",
            encoding="utf-8",
        )
        (svc_dir / "AppSearch.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  function resolveWindowIdentity(w) { return w?.app_id ?? '' }\n"
            "  function getIconSource(_id) { return '' }\n"
            "}\n",
            encoding="utf-8",
        )
        (svc_dir / "RecorderStatus.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool isRecording: false }\n", encoding="utf-8")
        (svc_dir / "GameMode.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool active: false }\n", encoding="utf-8")

        common_dir = folder / "modules/common"
        widgets_dir = common_dir / "widgets"
        widgets_dir.mkdir(parents=True)
        (common_dir / "qmldir").write_text(
            "module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\nsingleton Config 1.0 Config.qml\n",
            encoding="utf-8",
        )
        (common_dir / "Appearance.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property bool animationsEnabled: false\n"
            "  property var m3colors: ({ darkmode: true })\n"
            "  property var colors: ({ colLayer0Base: '#121518', colLayer1Base: '#1a1e22', colPrimary: '#5ec7d6', colOutlineVariant: '#444444', colOnLayer1: '#ffffff' })\n"
            "  property var font: ({ pixelSize: { small: 13 } })\n"
            "}\n",
            encoding="utf-8",
        )
        (common_dir / "Config.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property var options: ({ appearance: { theme: 'auto', wallpaperTheming: { enableAppsAndShell: true, enableVSCode: true, vscodeEditors: { antigravity: true } } } })\n"
            "}\n",
            encoding="utf-8",
        )
        (widgets_dir / "qmldir").write_text("module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\n", encoding="utf-8")
        (widgets_dir / "StyledText.qml").write_text("import QtQuick\nText { }\n", encoding="utf-8")

        shell_qml = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common

ShellRoot {
    id: root
    property int checks: 0
    Component.onCompleted: Quickshell.watchFiles = false
    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    Item {
        id: outerCanvas
        width: 1920
        height: 1200

        Item {
            id: stage
            width: 1920
            height: 1200
            property real stageScale: 0.83
            transform: [
                Scale { xScale: stage.stageScale; yScale: stage.stageScale },
                Translate { x: 163; y: 16 }
            ]

            Loader {
                id: winLoader
                anchors.fill: parent
                active: true
                source: "modules/abyss/looks/AbyssStageActiveWindows.qml"
                onLoaded: {
                    if (item) {
                        item.captureScreen = null
                        item.outputName = "eDP-1"
                        item.edgeInsets = ({ left: 10, right: 10, top: 48, bottom: 10 })
                        item.stageVisible = true
                        item.activeSession = true
                    }
                }
            }
        }
    }

    TestCase {
        id: tc
        when: false
        optional: true
        function run() {
            try {
                NiriService.allWorkspaces = [
                    { id: 2, idx: 2, output: "eDP-1", is_active: true, is_focused: true, active_window_id: null }
                ]
                NiriService.windows = [
                    {
                        id: 3, app_id: "antigravity", title: "Antigravity", workspace_id: 2,
                        is_focused: false, is_floating: false,
                        layout: { pos_in_scrolling_layout: [1, 1], tile_size: [920, 1102], window_size: [920, 1102] }
                    },
                    {
                        id: 4, app_id: "org.alis.Files", title: "Alis Files", workspace_id: 2,
                        is_focused: false, is_floating: false,
                        layout: { pos_in_scrolling_layout: [2, 1], tile_size: [920, 1102], window_size: [920, 1102] }
                    }
                ]
                tryVerify(() => winLoader.item && winLoader.item.windowItems.length === 2, 2000)
                const item = winLoader.item
                tryVerify(() => item.captureFailed === true, 1000)
                root.check(item.captureFailed === true, "offscreen null captureScreen cleanly sets captureFailed fallback")
                root.check(item.themePreviewMix === 1.0, "auto theme enables window preview mix")
                root.check(String(item.basePrimaryColor) === "#5ec7d6", "baseline primary color frozen on entry")
                const nextColors = Object.assign({}, Appearance.colors, { colPrimary: "#e07a5f" })
                Appearance.colors = nextColors
                root.check(String(item.basePrimaryColor) === "#5ec7d6", "baseline remains frozen when target palette shifts")
                root.check(String(item.animatedTargetPrimary) === "#e07a5f", "target primary tracks new wallpaper palette")
                const tiles = item.children.find(c => c && c.children && Array.from(c.children).some(d => d && d.width === 920))
                const delegates = Array.from(tiles.children).filter(c => c && c.width === 920 && c.height === 1102)
                root.check(delegates.length === 2, "expected both unfocused visible window delegates")
                root.check(delegates.every(d => d.autoThemed === true), "both unfocused antigravity and org.alis.Files must be autoThemed")
                const firstWin = delegates[0]
                const expectedX = 10 + Math.round((1900 - (920 + 15 + 920)) / 2)
                const scaledTopLeft = firstWin.mapToItem(outerCanvas, 0, 0)
                const scaledBotRight = firstWin.mapToItem(outerCanvas, firstWin.width, firstWin.height)
                root.check(Math.abs(scaledTopLeft.x - (163 + expectedX * 0.83)) < 1.5,
                    "scaled window x must follow Desktop Stage scale, got " + scaledTopLeft.x)
                root.check(Math.abs(scaledTopLeft.y - (16 + 68 * 0.83)) < 1.5,
                    "scaled window y must follow Desktop Stage scale, got " + scaledTopLeft.y)
                root.check(Math.abs((scaledBotRight.x - scaledTopLeft.x) - 920 * 0.83) < 1.5,
                    "scaled window width must equal 920*0.83, got " + (scaledBotRight.x - scaledTopLeft.x))
                console.info("STAGE_ACTIVE_WINDOWS_RUNTIME_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("STAGE_ACTIVE_WINDOWS_RUNTIME_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer { interval: 40; running: true; repeat: false; onTriggered: tc.run() }
}
'''
        (folder / "shell.qml").write_text(shell_qml, encoding="utf-8")
        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env["QT_QPA_PLATFORM"] = "offscreen"
        env["XDG_CONFIG_HOME"] = str(folder / "config")
        env["XDG_STATE_HOME"] = str(folder / "state")
        env["XDG_CACHE_HOME"] = str(folder / "cache")

        res = run_qs(folder, env, timeout=15)
        out = (res.stdout or "") + "\n" + (res.stderr or "")
        if res.returncode != 0 or "STAGE_ACTIVE_WINDOWS_RUNTIME_PASS" not in out or re.search(
            r"STAGE_ACTIVE_WINDOWS_RUNTIME_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign",
            out,
        ):
            print(out)
            sys.exit(1)
        for line in out.splitlines():
            if "STAGE_ACTIVE_WINDOWS_RUNTIME_PASS" in line:
                print(line.strip())


def _write_png_rgba(path: Path, pixels: list[list[tuple[int, int, int, int]]]) -> None:
    h = len(pixels)
    w = len(pixels[0])
    rows = []
    for row_px in pixels:
        row = bytearray([0])
        for r, g, b, a in row_px:
            row.extend((r, g, b, a))
        rows.append(bytes(row))
    raw = b"".join(rows)

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def _read_png_rgba(path: Path, px: int, py: int) -> tuple[int, int, int, int]:
    data = path.read_bytes()
    pos = 8
    idat = bytearray()
    w = h = ct = 0
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        ctype = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            w, h, _bd, ct = struct.unpack(">IIBB", chunk[:10])
        elif ctype == b"IDAT":
            idat.extend(chunk)
    raw = zlib.decompress(bytes(idat))
    bpp = 4 if ct == 6 else 3
    stride = w * bpp
    prev = bytearray(stride)
    rows: list[bytes] = []
    idx = 0
    for _y in range(h):
        ft = raw[idx]
        idx += 1
        cur = bytearray(raw[idx:idx + stride])
        idx += stride
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            if ft == 1:
                cur[i] = (cur[i] + a) & 0xFF
            elif ft == 2:
                cur[i] = (cur[i] + b) & 0xFF
            elif ft == 3:
                cur[i] = (cur[i] + ((a + b) >> 1)) & 0xFF
            elif ft == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                cur[i] = (cur[i] + pr) & 0xFF
        rows.append(bytes(cur))
        prev = cur
    off = px * bpp
    px_vals = rows[py][off:off + bpp]
    return (px_vals[0], px_vals[1], px_vals[2], px_vals[3] if bpp == 4 else 255)


def test_shader_gpu_remap() -> None:
    if not shutil.which("qml6"):
        print("SKIP: qml6 unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-stage-shader-gpu-") as tmp:
        td = Path(tmp)
        src_png = td / "src.png"
        out_png = td / "out.png"
        # 128x128 synthetic Alis Files palette blocks:
        # (x<64, y<42): bg #120e18 | (x>=64, y<42): sidebar pill #2a2138
        # (x<64, 42<=y<84): selected row #6b4f8c | (x>=64, 42<=y<84): primary #d0bcff
        # (y>=84): blue folder icon #2196f3
        pixels = []
        for y in range(128):
            row = []
            for x in range(128):
                if y >= 84:
                    row.append((0x21, 0x96, 0xF3, 255))
                elif y >= 42:
                    row.append((0x6B, 0x4F, 0x8C, 255) if x < 64 else (0xD0, 0xBC, 0xFF, 255))
                else:
                    row.append((0x12, 0x0E, 0x18, 255) if x < 64 else (0x2A, 0x21, 0x38, 255))
            pixels.append(row)
        _write_png_rgba(src_png, pixels)

        qsb_path = ROOT / "modules/abyss/looks/AbyssStageWindowTheme.frag.qsb"
        qml_path = td / "shader_test.qml"
        qml_path.write_text(
            f'''import QtQuick
import QtQuick.Window

Window {{
    id: win
    width: 128; height: 128; visible: true
    color: "black"
    property var grabbed: null

    Image {{
        id: liveSrc
        anchors.fill: parent
        source: "file://{src_png}"
        visible: true
    }}

    Image {{
        id: frozenImg
        anchors.fill: parent
        visible: false
        smooth: true
        mipmap: true
        source: win.grabbed ? win.grabbed.url : ""
    }}

    ShaderEffect {{
        id: eff
        anchors.fill: parent
        visible: win.grabbed !== null && frozenImg.status === Image.Ready
        property var screenTex: frozenImg
        property vector4d uvRect: Qt.vector4d(0, 0, 1, 1)
        property vector4d tileSize: Qt.vector4d(128, 128, 0, 1.0)
        property vector4d baseBg: Qt.vector4d(0x14/255, 0x12/255, 0x18/255, 1.0)
        property vector4d targetBg: Qt.vector4d(0x1a/255, 0x11/255, 0x0d/255, 1.0)
        property vector4d baseSurface: Qt.vector4d(0x1d/255, 0x1b/255, 0x20/255, 1.0)
        property vector4d targetSurface: Qt.vector4d(0x26/255, 0x1c/255, 0x16/255, 1.0)
        property vector4d basePrimary: Qt.vector4d(0xd0/255, 0xbc/255, 0xff/255, 0.0)
        property vector4d targetPrimary: Qt.vector4d(0xff/255, 0xb5/255, 0x98/255, 0.0)
        fragmentShader: "file://{qsb_path}"
    }}

    Timer {{
        interval: 60; running: true; repeat: false
        onTriggered: {{
            liveSrc.grabToImage(function(res) {{
                win.grabbed = res;
                liveSrc.visible = false;
                snapTimer.start();
            }});
        }}
    }}

    Timer {{
        id: snapTimer
        interval: 160; running: false; repeat: false
        onTriggered: {{
            eff.grabToImage(function(r) {{
                r.saveToFile("{out_png}");
                Qt.quit();
            }});
        }}
    }}
}}
''',
            encoding="utf-8",
        )

        with private_wayland(td) as env:
            res = subprocess.run(["qml6", str(qml_path)], env=env, capture_output=True, text=True, timeout=20)
        assert res.returncode == 0 and out_png.is_file(), f"GPU shader test failed: {res.stderr}"

        bg = _read_png_rgba(out_png, 20, 20)
        pill = _read_png_rgba(out_png, 96, 20)
        sel = _read_png_rgba(out_png, 20, 62)
        prim = _read_png_rgba(out_png, 96, 62)
        icon = _read_png_rgba(out_png, 64, 108)

        for name, px in (("bg", bg), ("pill", pill), ("sel", sel), ("prim", prim), ("icon", icon)):
            assert px[3] == 255, f"{name} alpha expected 255, got {px}"
        assert bg[0] > bg[2], f"bg expected warm R > B shift, got {bg}"
        assert pill[0] > pill[2], f"sidebar pill expected warm R > B shift, got {pill}"
        assert sel[0] > sel[2], f"selected row expected warm R > B shift, got {sel}"
        assert prim[0] > prim[2], f"primary accent expected warm R > B shift, got {prim}"
        assert icon[2] > icon[0] + 120, f"blue folder icon expected B > R + 120, got {icon}"
        print(f"STAGE_ACTIVE_WINDOWS_SHADER_GPU_PASS bg={bg} pill={pill} sel={sel} prim={prim} icon={icon}")


if __name__ == "__main__":
    test_shader_qsb_fresh()
    test_source_contracts()
    test_js_layout()
    test_qml_lint()
    test_qml_runtime()
    test_shader_gpu_remap()
