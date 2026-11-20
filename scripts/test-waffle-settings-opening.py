#!/usr/bin/env python3
"""Check Waffle Settings through real launch buttons after switching from Abyss."""
import argparse
import json
import tempfile
from pathlib import Path

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]

QML = """
//@ pragma UseQApplication
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.modules.common
import qs.modules.dashboard as Dashboard
import qs.modules.waffle.looks as Waffle
import qs.modules.waffle.startMenu as Start
import qs.modules.waffle.actionCenter.mainPage as Action

ShellRoot {
    id: app
    Component.onCompleted: Quickshell.watchFiles = false
    PRODUCTION_ROUTER
    PRODUCTION_LOADER
    Dashboard.Dashboard { id: fullDashboard }
    property var overlay: SETTINGS_LOADER.item
    property int standaloneReceipts: 0
    IpcHandler {
        target: "fixture"
        function standaloneReady(): void { ++app.standaloneReceipts }
    }
    FloatingWindow {
        visible: true
        implicitWidth: 770
        implicitHeight: 825
        Item {
            anchors.fill: parent
            Dashboard.DashboardHeader { id: dashboard; anchors.top: parent.top; width: parent.width }
            Start.StartPageContent { id: start; anchors.fill: parent; anchors.topMargin: 50; anchors.bottomMargin: 56 }
            Action.MainPageFooter { id: footer; anchors.bottom: parent.bottom; width: parent.width; height: 44 }
        }
        TestCase {
            id: test
            optional: true
            when: false

            function byProperty(item, name, value) {
                if (!item) return null
                if (item[name] === value) return item
                for (const child of item.children ?? []) {
                    const found = byProperty(child, name, value)
                    if (found) return found
                }
                return null
            }
            function openRail(button, flag) {
                verify(!!button && button.visible, "Missing launch button: " + flag)
                GlobalStates[flag] = true
                mouseClick(button)
                tryVerify(() => GlobalStates.settingsOverlayOpen && !GlobalStates[flag], 7000)
                console.info("SETTINGS_CLICK", flag, SETTINGS_LOADER.active, !!app.overlay)
                tryVerify(() => app.overlay?.pageHost && app.overlay?.searchFieldItem, 7000,
                    "Settings request has no host")
                const field = app.overlay.searchFieldItem
                tryVerify(() => {
                    const win = field.Window.window
                    if (!win?.visible || !field.visible || field.width < 30 || app.overlay.pageHost.width < 200)
                        return false
                    const pt = field.mapToItem(null, field.width / 2, field.height / 2)
                    return pt.x >= 0 && pt.y >= 0 && pt.x < win.width && pt.y < win.height
                }, 4000, "Settings must map on the compositor with a reachable input")
                mouseClick(field)
                tryVerify(() => field.activeFocus, 2500)
                const title = findChild(field.QsWindow.window.contentItem, "waffleSettingsTitleBar")
                const dismissIcon = byProperty(title, "icon", "dismiss")
                verify(!!dismissIcon, "Missing Waffle close button")
                let saved = false
                title.parent.parent.grabToImage(result => {
                    saved = result.saveToFile(Quickshell.env("PROOF") + "/" + flag + ".png")
                })
                tryVerify(() => saved, 3500)
                mouseClick(dismissIcon)
                tryVerify(() => !GlobalStates.settingsOverlayOpen && !app.overlay._panelLoaded, 3000)
                console.info("SETTINGS_RAIL_PASS", flag)
            }
            function run() {
                try {
                    tryCompare(Config, "ready", true, 6000)
                    compare(Config.options.panelFamily, "abyss")
                    verify(!app.overlay)
                    Config.setNestedValue("panelFamily", "waffle")
                    tryVerify(() => Config.options.panelFamily === "waffle", 2000)
                    const startGear = findChild(start, "waffleStartSettingsButton")
                    const dashboardGear = byProperty(dashboard, "tooltip", "Settings")
                    openRail(startGear, "searchOpen")
                    openRail(findChild(footer, "waffleActionCenterSettingsButton"), "waffleActionCenterOpen")
                    openRail(dashboardGear, "dashboardOpen")
                    // Check full Waffle Dashboard sizing, taskbar clearance, and visual skin
                    const prevReduce = Config.options?.performance?.reduceAnimations ?? false
                    Config.setNestedValue("performance.reduceAnimations", true)
                    GlobalStates.dashboardOpen = true
                    tryVerify(() => fullDashboard.isWaffle && fullDashboard._presentedOpen, 4000,
                        "Waffle Dashboard did not present")
                    compare(fullDashboard.panelWidth, Waffle.Looks.startMenuPaneWidth)
                    compare(fullDashboard.panelHeight, Waffle.Looks.startMenuPaneHeight)
                    const dashWin = fullDashboard.dashboardWindow
                    verify(!!dashWin && !!dashWin.contentItem, "Waffle Dashboard window missing")
                    const captureTarget = findChild(dashWin.contentItem, "dashboardSurfaceBackground")
                    verify(!!captureTarget, "Waffle Dashboard surface background missing")
                    tryVerify(() => {
                        const cardPos = captureTarget.mapToItem(null, 0, 0)
                        const clearance = dashWin.height - (cardPos.y + fullDashboard.panelHeight)
                        return clearance >= 48 + fullDashboard.menuMargin - 2
                    }, 3000, "Waffle Dashboard overlapped 48px taskbar")
                    let dashSaved = false
                    captureTarget.grabToImage(result => {
                        dashSaved = result.saveToFile(Quickshell.env("PROOF") + "/waffle-dashboard.png")
                    })
                    tryVerify(() => dashSaved, 3500)
                    GlobalStates.dashboardOpen = false
                    tryVerify(() => !fullDashboard._contentPresented, 3000)
                    Config.setNestedValue("performance.reduceAnimations", prevReduce)
                    Config.setNestedValue("settingsUi.overlayStyle", "focus")
                    GlobalStates.searchOpen = true
                    mouseClick(startGear)
                    tryVerify(() => GlobalStates.settingsOverlayOpen && app.overlay?.level === 0 && app.overlay._panelLoaded,
                        4000, "Focus style must own the request after the rail unloads")
                    GlobalStates.settingsOverlayOpen = false
                    tryVerify(() => !app.overlay._panelLoaded, 3000)
                    Config.setNestedValue("waffles.settings.windowMode", true)
                    tryVerify(() => !GlobalStates.useSettingsOverlay() && !app.overlay, 4000)
                    for (const [idx, button] of [startGear, dashboardGear].entries()) {
                        const flag = idx === 0 ? "searchOpen" : "dashboardOpen"
                        GlobalStates[flag] = true
                        mouseClick(button)
                        tryVerify(() => app.standaloneReceipts === idx + 1, 20000,
                            "The real settings-window command must map an interactive Waffle window: " + flag)
                        verify(!GlobalStates[flag] && !GlobalStates.settingsOverlayOpen)
                    }
                    console.info("SETTINGS_ROUTE_PASS")
                } catch (e) {
                    console.error("SETTINGS_ROUTE_FAIL", String(e), e.stack)
                }
                Qt.quit()
            }
        }
    }
    Timer { interval: 400; running: true; onTriggered: test.run() }
}
"""

WINDOW_CHECK = """
    TestCase {
        id: windowProbe
        when: false
        optional: true
        function verifyStandalone() {
            try {
                tryCompare(root, "visible", true, 4000)
                const field = findChild(root.contentItem, "waffleSettingsSearchInput")
                tryVerify(() => field && field.visible && field.width > 30
                    && field.Window.window === root && root.width > 300, 5000)
                mouseClick(field)
                tryVerify(() => field.activeFocus, 2000)
                keyClick(Qt.Key_W)
                tryCompare(root, "settingsSearchText", "w", 2000)
                let saved = false
                field.grabToImage(result => {
                    saved = result.saveToFile(Quickshell.env("PROOF") + "/standalone.png")
                })
                tryVerify(() => saved, 3000)
                windowReceipt.running = true
            } catch (e) {
                console.error("STANDALONE_FAIL", String(e), e.stack)
                root.close()
            }
        }
    }
    Process {
        id: windowReceipt
        command: ["qs", "-p", Quickshell.env("ALIS_RUNTIME_DIR"), "ipc", "call", "fixture", "standaloneReady"]
        onExited: root.close()
    }
    Timer { interval: 500; running: true; onTriggered: windowProbe.verifyStandalone() }
"""


def production_shell(root):
    source = (root / "shell.qml").read_text()
    router = source[source.index('    IpcHandler {\n        target: "settings"'):
                    source.index('    // One owner for settingsNav')]
    old = '    LazyLoader {\n        id: settingsRailLoader'
    new = '    Loader {\n        id: settingsOverlayLoader'
    loader = new if new in source else old
    body = source[source.index(loader):source.index('    // === Panel Loaders ===')]
    return QML.replace("PRODUCTION_ROUTER", router).replace("PRODUCTION_LOADER", body).replace(
        "SETTINGS_LOADER", loader.rsplit(" ", 1)[-1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="alis-settings-route-") as tmp:
        folder = Path(tmp)
        for name in ("services", "modules", "GlobalStates.qml", "qmldir", "scripts", "defaults", "translations", "assets"):
            (folder / name).symlink_to(root / name)
        (folder / "shell.qml").write_text(production_shell(root))
        standalone = (root / "settings.qml").read_text().replace("import QtQuick\n", "import QtQuick\nimport QtTest\nimport Quickshell.Io\n", 1)
        window, end = standalone.rsplit("}", 1)
        (folder / "settings.qml").write_text(window + WINDOW_CHECK + "}" + end)
        with private_wayland(folder) as env:
            if not env or env.get("QT_QPA_PLATFORM") != "wayland":
                raise SystemExit("Private Wayland compositor unavailable")
            config = json.loads((root / "defaults/config.json").read_text())
            config["panelFamily"] = "abyss"
            config.setdefault("weather", {})["enable"] = False
            config.setdefault("waffles", {}).setdefault("settings", {})["windowMode"] = False
            config.setdefault("abyss", {}).setdefault("companion", {})["enabled"] = False
            for name in ("alis", "illogical-impulse"):
                path = folder / "config" / name / "config.json"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(json.dumps(config))
            result = run_qs(folder, dict(env, ALIS_RUNTIME_DIR=str(folder), TMPDIR=str(folder),
                                        PROOF=str(output)), timeout=85)
            if result.returncode or "SETTINGS_ROUTE_PASS" not in result.stdout:
                import subprocess
                for log in (folder / ".kwin-runtime/quickshell/by-id").glob("*/log.qslog"):
                    with (output / (log.parent.name + ".log")).open("w") as capture:
                        subprocess.run(["qs", "log", str(log)], stdout=capture, stderr=subprocess.STDOUT)
    (output / "runtime.log").write_text(result.stdout)
    print("\n".join(line for line in result.stdout.splitlines() if "SETTINGS_" in line or "STANDALONE_FAIL" in line))
    if result.returncode or "SETTINGS_ROUTE_PASS" not in result.stdout:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
