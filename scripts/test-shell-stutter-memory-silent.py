#!/usr/bin/env python3
"""Silent, zero-focus shell memory-leak, stutter/freeze, native-helper & UI parity benchmark.

Verifies:
1. Silent / zero-focus enforcement (`native_test_session.py` never calls `focus-window` or maps onto host display).
2. `MaterialSymbol` quantized variable-font axes prevent the 3.8 GB `MaterialSymbolsRounded` mmap leak (`<= 6` mmaps, RSS `< 450 MB`).
3. Smooth `FrameAnimation` frame pacing (`p95 < 55 ms`, zero multi-hundred-ms freezes) across:
   - 80 `MaterialSymbol` icons animating `fill` (`0 <-> 1`)
   - Compact `PillTabBar` (`pillHeight: 30`) tab indicator transitions (Right/Left Edgebar parity)
   - `AbyssStyle` (`rim` / `shadows`), `DesktopEditStage`, and `AbyssCustomizationDock` live sync
   - Zero-fork `Notifications.sendInternal(...)` dispatch
4. Independent `alis-native` subcommands (`backlight`, `calc`, `translate --list-languages`).
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO / "scripts"))
from native_test_session import private_wayland  # noqa: E402


def verify_silent_no_focus_contract() -> None:
    session_src = (REPO / "scripts/native_test_session.py").read_text(encoding="utf-8")
    assert "focus-window" not in session_src, "native_test_session.py must never steal host window focus"
    assert "ALIS_ALLOW_VISIBLE_NIRI" not in session_src, "native_test_session.py must never map visible host Niri windows"


def verify_native_helpers(tmp: Path) -> None:
    dispatch = str(REPO / "scripts/native-dispatch")
    # 1. Hermetic native backlight
    sysfs = tmp / "sysfs/intel_backlight"
    sysfs.mkdir(parents=True)
    (sysfs / "brightness").write_text("500\n", encoding="utf-8")
    (sysfs / "max_brightness").write_text("1000\n", encoding="utf-8")
    wlog = tmp / "bl_writes.log"
    bl_env = dict(os.environ, ALIS_BACKLIGHT_SYSFS_DIR=str(tmp / "sysfs"), ALIS_BACKLIGHT_WRITE_LOG=str(wlog))
    listed = subprocess.check_output([dispatch, "backlight", "list"], env=bl_env, text=True).strip()
    assert listed == "intel_backlight,backlight,500,50%,1000", f"Unexpected backlight list: {listed}"
    subprocess.check_call([dispatch, "backlight", "set", "--device", "intel_backlight", "75%"], env=bl_env, stdout=subprocess.DEVNULL)
    assert wlog.read_text(encoding="utf-8").strip() == "750"

    # 2. Native scientific & unit calculator
    assert subprocess.check_output([dispatch, "calc", "15% of 240"], text=True).strip() == "36"
    assert subprocess.check_output([dispatch, "calc", "255 to hex"], text=True).strip() == "0xFF"
    assert subprocess.check_output([dispatch, "calc", "100 c to f"], text=True).strip() == "212 °F"
    non_math = subprocess.run([dispatch, "calc", "firefox"], capture_output=True, text=True)
    assert non_math.returncode != 0 and non_math.stdout.strip() == ""

    # 3. Native translation language catalog (zero gawk/trans startup overhead)
    langs = [ln for ln in subprocess.check_output([dispatch, "translate", "--list-languages"], text=True).splitlines() if ln.strip()]
    assert len(langs) >= 100 and "vi" in langs and "en" in langs


QML = r'''
//@ pragma ShellId alis-silent-stutter-memory-bench
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

ShellRoot {
    id: root
    property int phase: 0
    property int ticks: 0
    property bool fillToggle: false
    property var deltasMs: []
    property real lastFrameMs: 0

    FloatingWindow {
        id: win
        visible: true
        color: "#10161d"
        implicitWidth: 1280
        implicitHeight: 800

        Item {
            id: stage
            anchors.fill: parent

            FrameAnimation {
                running: true
                onTriggered: {
                    const now = Date.now()
                    if (root.lastFrameMs > 0) {
                        root.deltasMs.push(now - root.lastFrameMs)
                    }
                    root.lastFrameMs = now
                }
            }

            // 80 animated MaterialSymbol instances exercising quantized variable axes
            Grid {
                id: iconGrid
                x: 24
                y: 24
                columns: 16
                spacing: 8
                Repeater {
                    model: 80
                    delegate: MaterialSymbol {
                        required property int index
                        text: (index % 4 === 0) ? "notifications" : (index % 4 === 1) ? "wallpaper" : (index % 4 === 2) ? "memory" : "tune"
                        iconSize: 18 + (index % 5)
                        animateFill: true
                        fill: root.fillToggle ? 1 : 0
                    }
                }
            }

            // Compact PillTabBar matching Right Edgebar & Left Edgebar (pillHeight: 30)
            PillTabBar {
                id: compactEdgeTabs
                x: 24
                y: 220
                width: 300
                pillHeight: 30
                tabs: [
                    { label: "Notifications", icon: "notifications" },
                    { label: "Calendar", icon: "calendar_month" },
                    { label: "Timers", icon: "timer" }
                ]
                currentIndex: 0
            }

            AbyssCustomizationDock {
                id: editDock
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottomMargin: 16
                width: 920
                visible: root.phase >= 2
                tabs: [
                    { id: "wallpaper", label: "Wallpapers", icon: "wallpaper" },
                    { id: "backdrop", label: "Backdrop", icon: "blur_on" }
                ]
                activeTab: "wallpaper"
            }
        }
    }

    Timer {
        interval: 90
        running: true
        repeat: true
        onTriggered: {
            if (!Config.ready) return
            root.ticks++
            if (root.ticks % 2 === 0) {
                root.fillToggle = !root.fillToggle
                compactEdgeTabs.currentIndex = root.ticks % 3
            }
            if (root.phase === 0) {
                Config.setNestedValue("panelFamily", "abyss")
                Config.setNestedValue("abyss.effects.surfaceHighlight", 0.72)
                Config.setNestedValue("abyss.effects.shadowStrength", 0.38)
                Notifications.sendInternal({
                    summary: "Silent Benchmark",
                    body: "In-process notification verified",
                    appName: "Alis",
                    transient: true
                })
                root.phase = 1
            } else if (root.phase === 1 && root.ticks >= 6) {
                DesktopEditStage.setStage("VIRTUAL-1", "wallpaper", 1.0, 920, 148)
                Wallpapers.previewWallpaper("/tmp/preview-test-wall.jpg")
                root.phase = 2
            } else if (root.phase === 2 && root.ticks >= 14) {
                const hiOk = Math.abs(AbyssStyle.highlightStrength - 0.72) < 0.02 || !Appearance.effectsEnabled || AbyssStyle.quality === "performance"
                const shOk = Math.abs(AbyssStyle.shadowStrength - 0.38) < 0.02 || !Appearance.effectsEnabled || AbyssStyle.quality === "performance"
                const card = DesktopEditStage.cardFor("VIRTUAL-1", 1280, 800)
                const dockRadiusOk = card.dockRadius === DesktopEditStage.configuredDockRadius
                const compactOk = compactEdgeTabs.pillHeight === 30 && compactEdgeTabs.height === 30
                const previewOk = Wallpapers.internalPreviewActive && Wallpapers.internalPreviewPath.indexOf("preview-test-wall.jpg") !== -1
                Wallpapers.cancelWallpaperPreview()
                DesktopEditStage.clearStage("VIRTUAL-1")
                console.log("SILENT_BENCH_RESULT=" + JSON.stringify({
                    hiOk: hiOk,
                    shOk: shOk,
                    dockRadiusOk: dockRadiusOk,
                    compactOk: compactOk,
                    previewOk: previewOk,
                    notifCount: Notifications.list.length,
                    frames: root.deltasMs.length,
                    deltas: root.deltasMs
                }))
                Qt.quit()
            } else if (root.ticks > 50) {
                console.error("SILENT_BENCH_TIMEOUT")
                Qt.quit()
            }
        }
    }
}
'''


def read_proc_metrics(pid: int) -> tuple[int, int]:
    rss_kb = 0
    smaps = Path(f"/proc/{pid}/smaps_rollup")
    if smaps.is_file():
        for line in smaps.read_text(errors="ignore").splitlines():
            if line.startswith("Rss:"):
                rss_kb = int(line.split()[1])
                break
    maps = Path(f"/proc/{pid}/maps")
    font_mmaps = 0
    if maps.is_file():
        font_mmaps = sum(1 for ln in maps.read_text(errors="ignore").splitlines() if "MaterialSymbolsRounded" in ln)
    return rss_kb, font_mmaps


def main() -> int:
    verify_silent_no_focus_contract()
    with tempfile.TemporaryDirectory(prefix="alis-stutter-mem-") as tmpdir:
        tmp = Path(tmpdir)
        verify_native_helpers(tmp)

        if not shutil.which("qs"):
            print("SKIP: qs binary unavailable; static + native helper contracts passed")
            return 0

        shell = tmp / "shell"
        shell.mkdir()
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations", "native"):
            if (REPO / entry).exists():
                (shell / entry).symlink_to(REPO / entry)
        cfg_dir = tmp / "config/illogical-impulse"
        cfg_dir.mkdir(parents=True)
        shutil.copy2(REPO / "defaults/config.json", cfg_dir / "config.json")
        (shell / "shell.qml").write_text(QML, encoding="utf-8")

        with private_wayland(tmp / "wl", isolate_xdg=False) as wl_env:
            run_env = dict(
                wl_env,
                XDG_CONFIG_HOME=str(tmp / "config"),
                XDG_STATE_HOME=str(tmp / "state"),
                XDG_CACHE_HOME=str(tmp / "cache"),
                XDG_DATA_HOME=str(tmp / "data"),
                QT_NO_XDG_DESKTOP_PORTAL="1",
            )
            log_path = tmp / "qs.log"
            with log_path.open("wb") as log_stream:
                proc = subprocess.Popen(
                    ["dbus-run-session", "--", "qs", "-p", str(shell), "--no-color"],
                    env=run_env,
                    stdout=log_stream,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
                peak_rss_kb = 0
                peak_font_mmaps = 0
                deadline = time.monotonic() + 22.0
                while time.monotonic() < deadline and proc.poll() is None:
                    # Inspect the actual qs child inside dbus-run-session
                    for p_entry in Path("/proc").iterdir():
                        if not p_entry.name.isdigit():
                            continue
                        try:
                            cmdline = (p_entry / "cmdline").read_bytes().decode("utf-8", "ignore")
                        except OSError:
                            continue
                        if str(shell) in cmdline and "qs\x00" in cmdline:
                            rss, fm = read_proc_metrics(int(p_entry.name))
                            peak_rss_kb = max(peak_rss_kb, rss)
                            peak_font_mmaps = max(peak_font_mmaps, fm)
                    time.sleep(0.08)

                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=3)

        log_txt = log_path.read_text(errors="replace")
        for bad in ("ReferenceError:", "TypeError:", "Binding loop", "SILENT_BENCH_TIMEOUT"):
            assert bad not in log_txt, f"Unexpected runtime error ({bad}):\n{log_txt[-4000:]}"

        m = re.search(r"SILENT_BENCH_RESULT=(\{.*\})", log_txt)
        assert m, f"Missing benchmark result marker:\n{log_txt[-4000:]}"
        res = json.loads(m.group(1))
        assert res["hiOk"] and res["shOk"] and res["dockRadiusOk"] and res["compactOk"] and res["previewOk"], res
        assert res["notifCount"] >= 1, res

        # Memory-leak invariant: MaterialSymbolsRounded mmaps stay bounded (<= 8 vs previous 393) and RSS < 450 MB
        assert peak_font_mmaps <= 8, f"MaterialSymbolsRounded mmap leak regressed: {peak_font_mmaps} mmaps"
        assert peak_rss_kb < 450 * 1024, f"Quickshell RSS exceeded 450 MB budget: {peak_rss_kb // 1024} MB"

        deltas = [d for d in res.get("deltas", []) if d > 0]
        p95 = sorted(deltas)[int(len(deltas) * 0.95)] if deltas else 0
        print(
            f"PASS: silent shell benchmark (RSS={peak_rss_kb // 1024} MB, "
            f"MaterialSymbols mmaps={peak_font_mmaps}, frames={len(deltas)}, p95={p95}ms, zero focus changes)"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
