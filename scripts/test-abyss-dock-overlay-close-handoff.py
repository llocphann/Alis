#!/usr/bin/env python3
"""Silent regression test for Dock reopen handoff when closing Nexus / large overlays."""
from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_source_contracts() -> None:
    perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    expected = (
        "&& !window.editorOpen && !settings.visualResident && !dashboardBody.visualResident "
        "&& !nexusBody.visualResident && !filesBody.visualResident && !controls.visualResident\n"
        "                    && !aux.visualResident && !clipboardBody.visualResident && !utility.visualResident"
    )
    assert expected in perimeter, "dock.open must wait until overlay bodies finish closing (visualResident === false)"

    nexus_host = (
        ROOT.parent / "Alis-Intergration/plugins/nexus/modules/nexus/NexusHost.qml"
    )
    if nexus_host.is_file():
        nh_text = nexus_host.read_text(encoding="utf-8")
        assert "if (root.hostedByAbyssPerimeter)" in nh_text, (
            "NexusHost.qml must skip standalone overlay reveal animation when hosted by AbyssPerimeter"
        )

    for rel in ("modules/abyss/content/AbyssNexusContent.qml", "modules/abyss/content/AbyssFilesContent.qml"):
        content = (ROOT / rel).read_text(encoding="utf-8")
        assert "property string _loadedTargetSource:" in content, f"{rel} missing _loadedTargetSource"
        assert "workspaceLoader.source.toString() !== root._targetSource" not in content, (
            f"{rel} must not compare file:// Loader.source URL against bare filesystem path"
        )

    body_host = (ROOT / "modules/abyss/AbyssBodyHost.qml").read_text(encoding="utf-8")
    assert "availabilityMotion.targetValue > 0 ? Easing.OutCubic : Easing.InCubic" in body_host, (
        "AbyssBodyHost availabilityMotion must key easing.type off availabilityMotion.targetValue"
    )
    assert "availabilityMotion.targetValue > 0 && AbyssStyle.motionOvershoot > 0" in body_host, (
        "AbyssBodyHost availabilityMotion settle duration must key off availabilityMotion.targetValue"
    )
    print("DOCK_OVERLAY_CLOSE_HANDOFF_SOURCE_PASS")


def test_runtime_handoff() -> None:
    if not shutil.which("qs"):
        print("SKIP: qs unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-dock-handoff-") as tmp:
        folder = Path(tmp)
        mods = folder / "modules/abyss"
        looks = mods / "looks"
        looks.mkdir(parents=True)
        for name in (
            "AbyssBodyHost.qml",
            "AbyssSurfaceController.qml",
            "AbyssParticipant.qml",
            "AbyssPyramidCoordinator.qml",
            "AbyssWaveController.qml",
            "qmldir",
        ):
            target = ROOT / "modules/abyss" / name
            if target.exists():
                (mods / name).symlink_to(target)
        for p in (ROOT / "modules/abyss/looks").iterdir():
            (looks / p.name).symlink_to(p)

        common = folder / "modules/common"
        widgets = common / "widgets"
        funcs = common / "functions"
        widgets.mkdir(parents=True)
        funcs.mkdir(parents=True)
        (common / "qmldir").write_text(
            "module qs.modules.common\nsingleton Appearance 1.0 Appearance.qml\nsingleton Config 1.0 Config.qml\n",
            encoding="utf-8",
        )
        (common / "Appearance.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property bool animationsEnabled: true\n"
            "  property bool effectsEnabled: false\n"
            "  property real fontSizeScale: 1.0\n"
            "  property var font: ({ family: { main: 'sans-serif' }, pixelSize: { normal: 14, small: 12 } })\n"
            "  property var sizes: ({ barHeight: 48 })\n"
            "  property var m3colors: ({ m3onSurface: '#ffffff', m3shadow: '#000000' })\n"
            "  property var colors: ({ colLayer0Base: '#121212', colLayer1Base: '#1e1e1e', colPrimary: '#80cbc4' })\n"
            "}\n",
            encoding="utf-8",
        )
        (common / "Config.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property bool ready: true\n"
            "  property var options: ({ dock: { height: 60 }, abyss: { waves: { enabled: false }, motion: { intensity: 0.5 }, effects: {} } })\n"
            "}\n",
            encoding="utf-8",
        )
        (funcs / "qmldir").write_text("module qs.modules.common.functions\nsingleton ColorUtils 1.0 ColorUtils.qml\n", encoding="utf-8")
        (funcs / "ColorUtils.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  function colorWithLightness(c, _l) { return c }\n"
            "}\n",
            encoding="utf-8",
        )
        (funcs / "md5.js").symlink_to(ROOT / "modules/common/functions/md5.js")
        (widgets / "qmldir").write_text("module qs.modules.common.widgets\nStyledText 1.0 StyledText.qml\n", encoding="utf-8")
        (widgets / "StyledText.qml").write_text("import QtQuick\nText { }\n", encoding="utf-8")

        svc = folder / "services"
        svc.mkdir()
        content_dir = mods / "content"
        content_dir.mkdir(parents=True)
        (content_dir / "AbyssNexusContent.qml").symlink_to(ROOT / "modules/abyss/content/AbyssNexusContent.qml")

        dummy_ws = folder / "DummyWorkspace.qml"
        dummy_ws.write_text(
            "import QtQuick\nimport qs.services\nItem {\n"
            "  property var nexus: null\n"
            "  property bool embeddedSurface: false\n"
            "  property bool bottomDocked: false\n"
            "  property bool transitionSettled: false\n"
            "  signal handleEscape()\n"
            "  Component.onCompleted: { AlisIntergration.loadCount++ }\n"
            "}\n",
            encoding="utf-8",
        )
        (svc / "AlisIntergration.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property bool nexusEnabled: true\n"
            "  property int loadCount: 0\n"
            "  property var nexus: ({ isOpen: false })\n"
            f"  function nexusWorkspaceSource() {{ return {repr(str(dummy_ws))} }}\n"
            "}\n",
            encoding="utf-8",
        )
        (svc / "qmldir").write_text(
            "module qs.services\n"
            "singleton WallpaperListener 1.0 WallpaperListener.qml\n"
            "singleton MemoryPressureService 1.0 MemoryPressureService.qml\n"
            "singleton AlisIntergration 1.0 AlisIntergration.qml\n",
            encoding="utf-8",
        )
        (svc / "WallpaperListener.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject { function wallpaperUrlForScreen(_s) { return '' } }\n",
            encoding="utf-8",
        )
        (svc / "MemoryPressureService.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  signal pressureExceeded()\n"
            "  function requestIdleGc() {}\n"
            "}\n",
            encoding="utf-8",
        )
        (folder / "GlobalStates.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property bool deferredPanelsReady: true\n"
            "  property bool screenLocked: false\n"
            "}\n",
            encoding="utf-8",
        )
        (folder / "AbyssRenderPolicy.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject {\n"
            "  property string abyssQuality: 'balanced'\n"
            "  property bool powerSaver: false\n"
            "}\n",
            encoding="utf-8",
        )
        (folder / "GameMode.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool active: false }\n", encoding="utf-8")
        (folder / "RecorderStatus.qml").write_text("pragma Singleton\nimport QtQuick\nQtObject { property bool isRecording: false }\n", encoding="utf-8")
        (folder / "AlisLoadingScreen.qml").write_text("import QtQuick\nItem { property bool loading: false; property string title: ''; property string icon: ''; property bool fillSurface: false }\n", encoding="utf-8")
        (folder / "Translation.qml").write_text(
            "pragma Singleton\nimport QtQuick\nQtObject { function tr(s) { return s } }\n",
            encoding="utf-8",
        )
        (folder / "qmldir").write_text(
            "module qs\n"
            "singleton GlobalStates 1.0 GlobalStates.qml\n"
            "singleton AbyssRenderPolicy 1.0 AbyssRenderPolicy.qml\n"
            "singleton GameMode 1.0 GameMode.qml\n"
            "singleton RecorderStatus 1.0 RecorderStatus.qml\n"
            "singleton Translation 1.0 Translation.qml\n"
            "AlisLoadingScreen 1.0 AlisLoadingScreen.qml\n",
            encoding="utf-8",
        )

        (mods / "DummyContent.qml").write_text("import QtQuick\nItem { property bool contentReady: true }\n", encoding="utf-8")

        shell_qml = r'''import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.abyss
import "modules/abyss/content"

ShellRoot {
    id: root
    property int checks: 0
    property bool nexusIsOpen: true
    Component.onCompleted: Quickshell.watchFiles = false
    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    QtObject {
        id: rootLoadTracker
        property int loads: 0
    }

    // Also provide rootLoadTracker cleanly via context property isn't needed if DummyWorkspace notifies via parent or child:
    AbyssSurfaceController {
        id: ctrl
        outputName: "TEST-1"
        outputWidth: 1920
        outputHeight: 1080
    }

    AbyssBodyHost {
        id: nexusBody
        width: 1920; height: 1080
        identity: "nexus"
        controller: ctrl
        edge: "bottom"
        along: 120; span: 1680; depth: 960
        largeSurface: true
        retainAfterFirstOpen: true
        monotonicNotificationReveal: true
        open: root.nexusIsOpen
        source: "DummyContent.qml"
    }

    AbyssBodyHost {
        id: standaloneParticipant
        width: 1920; height: 1080
        identity: "standaloneNexus"
        edge: "bottom"
        along: 120; span: 1680; depth: 960
        open: false
        source: "DummyContent.qml"
    }

    AbyssNexusContent {
        id: nexusContentUnderTest
        participant: standaloneParticipant
        outputName: "TEST-1"
    }

    AbyssBodyHost {
        id: dock
        width: 1920; height: 1080
        identity: "dock"
        controller: ctrl
        edge: "bottom"
        along: 760; span: 400; depth: 74
        open: !nexusBody.visualResident
        source: "DummyContent.qml"
    }

    TestCase {
        id: tc
        when: false
        optional: true
        function run() {
            try {
                tryVerify(() => nexusBody.ready && nexusBody.progress > 0.99, 2000)
                root.check(nexusBody.visualResident === true, "nexusBody must be visualResident when open")
                root.check(dock.open === false, "dock.open must stay false while nexusBody is open")

                // Close Nexus: while close animation is mid-flight, dock must stay closed
                root.nexusIsOpen = false
                root.check(nexusBody.open === false, "nexusBody.open flips false immediately")
                root.check(nexusBody.visualResident === true, "nexusBody.visualResident remains true during close animation")
                root.check(dock.open === false, "dock must NOT open while nexusBody is mid-close")

                // Wait for close animation to complete -> verify Dock opens with OutCubic (fast initial climb, not InCubic crawl)
                tryVerify(() => !nexusBody.visualResident, 2000)
                tryVerify(() => dock.open === true, 500)
                // wait ~65ms (approx 25-30% of 220ms OutCubic duration -> progress >= 0.45 vs ~0.02 for InCubic)
                wait(75)
                root.check(dock.progress > 0.35, "dock must open with OutCubic curve, got progress=" + dock.progress)
                tryVerify(() => dock.progress > 0.99, 2000)

                // Verify AbyssNexusContent loads bare-path workspace ONCE across open -> close -> reopen -> close
                const wsLoader = nexusContentUnderTest.children.find(c => c && c.status !== undefined && c.asynchronous !== undefined)
                root.check(Boolean(wsLoader), "AbyssNexusContent must contain workspaceLoader")
                standaloneParticipant.open = true
                tryVerify(() => wsLoader.status === Loader.Ready && wsLoader.item !== null, 2000)
                const firstItem = wsLoader.item
                root.check(AlisIntergration.loadCount === 1, "expected 1 workspace load on first open, got " + AlisIntergration.loadCount)

                standaloneParticipant.open = false
                tryVerify(() => !standaloneParticipant.visualResident, 2000)
                wait(40)
                root.check(wsLoader.item === firstItem && AlisIntergration.loadCount === 1,
                    "closing must NOT destroy/reload workspace item, loads=" + AlisIntergration.loadCount)

                standaloneParticipant.open = true
                tryVerify(() => standaloneParticipant.progress > 0.99, 2000)
                root.check(wsLoader.item === firstItem && AlisIntergration.loadCount === 1,
                    "reopening same source must reuse warm item without reload, loads=" + AlisIntergration.loadCount)

                standaloneParticipant.open = false
                tryVerify(() => !standaloneParticipant.visualResident, 2000)
                root.check(wsLoader.item === firstItem && AlisIntergration.loadCount === 1,
                    "second close must NOT reload workspace item, loads=" + AlisIntergration.loadCount)

                console.info("DOCK_OVERLAY_CLOSE_HANDOFF_RUNTIME_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("DOCK_OVERLAY_CLOSE_HANDOFF_FAIL", err.message, err.stack)
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
        if res.returncode != 0 or "DOCK_OVERLAY_CLOSE_HANDOFF_RUNTIME_PASS" not in out or re.search(
            r"DOCK_OVERLAY_CLOSE_HANDOFF_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign",
            out,
        ):
            print(out)
            sys.exit(1)
        for line in out.splitlines():
            if "DOCK_OVERLAY_CLOSE_HANDOFF_RUNTIME_PASS" in line:
                print(line.strip())


if __name__ == "__main__":
    test_source_contracts()
    test_runtime_handoff()
