#!/usr/bin/env python3
"""Private Wayland runtime regression test for Waffle Popups, Dashboard, Settings & Exercises Tracker migration."""
import json
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from native_test_session import private_wayland, run_qs


HARNESS_QML = r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.settings
import qs.modules.waffle.bar as WaffleBar
import qs.modules.waffle.looks as WaffleLooks
import qs.modules.waffle.startMenu as WaffleStart

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false

    Loader {
        id: wafflePanelsLoader
        active: Config.ready
        source: Quickshell.shellPath("modules/waffle/ShellWafflePanelsImpl.qml")
    }

    Window {
        id: hostWin
        visible: true
        width: 1280
        height: 820
        color: "#1e1e1e"

        Rectangle {
            id: overlayHost
            anchors.fill: parent
        }

        SettingsOverlay {
            id: settingsOverlay
            embeddedHost: overlayHost
            settingsOpen: GlobalStates.useSettingsOverlay() && GlobalStates.settingsOverlayOpen
        }

        WaffleBar.WaffleBarContent {
            id: barProbe
            width: 1280
            height: 48
            opacity: 0
        }

        WaffleStart.StartPageContent {
            id: startProbe
            width: 640
            height: 680
            opacity: 0
        }
    }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        function check(cond, msg) {
            checks++
            if (!cond)
                throw new Error(msg)
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 6000)
                GlobalStates.shellEntryReady = true
                GlobalStates.deferredPanelsReady = true

                // 1. Legacy upgrade migration parity: pre-patch config had spaced_repetition=true and no exercises_tracker key
                check(Config.options.panelFamily === "waffle", "Expected panelFamily === waffle")
                tryCompare(AlisIntergration, "initialProbeDone", true, 6000)
                check(!Config.hasPersistedKey("integrations.alisIntergration.exercises_tracker"),
                    "Read-only legacy config should not backfill exercises_tracker into config.json")
                check(AlisIntergration.isPluginInstalled("exercises_tracker") === true
                    && !AlisIntergration.isPluginInstalled("spaced_repetition"),
                    "Expected only exercises_tracker plugin installed in base-v2 data dir")
                check(AlisIntergration.exercisesTrackerEnabled === true,
                    "Legacy active user config did not activate installed exercises_tracker=true")
                check(GlobalStates.useSettingsOverlay() === true,
                    "Waffle should default to fast in-process SettingsOverlay unless windowMode is enabled")

                // 2. ShellWafflePanelsImpl compiles & mounts without WorkspaceThumbnail duplicate-property failure
                tryCompare(wafflePanelsLoader, "status", Loader.Ready, 6000)
                check(wafflePanelsLoader.item !== null, "ShellWafflePanelsImpl item is null")

                // 3. Taskbar & Start Menu expose Dashboard entry points
                const barDashBtn = findChild(barProbe, "waffleDashboardButton")
                const startDashBtn = findChild(startProbe, "waffleStartDashboardButton")
                check(barDashBtn !== null && barDashBtn.visible === true, "waffleDashboardButton missing on Waffle taskbar")
                check(startDashBtn !== null && startDashBtn.visible === true, "waffleStartDashboardButton missing in Start Menu footer")

                // 4. Toggle Waffle Popups (Start Menu, Action Center, Notification Center, Widgets, Task View)
                GlobalStates.searchOpen = true
                wait(40)
                check(GlobalStates.searchOpen === true, "Start Menu did not open")

                GlobalStates.waffleActionCenterOpen = true
                wait(40)
                check(GlobalStates.waffleActionCenterOpen === true, "Action Center did not open")

                GlobalStates.waffleNotificationCenterOpen = true
                wait(40)
                check(GlobalStates.waffleNotificationCenterOpen === true, "Notification Center did not open")

                GlobalStates.waffleWidgetsOpen = true
                wait(40)
                check(GlobalStates.waffleWidgetsOpen === true, "Widgets panel did not open")

                GlobalStates.waffleTaskViewOpen = true
                wait(40)
                check(GlobalStates.waffleTaskViewOpen === true, "Task View did not open")

                WaffleLooks.WaffleNavigation.closeFlyouts()
                check(!GlobalStates.searchOpen && !GlobalStates.waffleActionCenterOpen
                    && !GlobalStates.waffleNotificationCenterOpen && !GlobalStates.waffleWidgetsOpen
                    && !GlobalStates.waffleTaskViewOpen,
                    "WaffleNavigation.closeFlyouts() did not reset all Waffle popups")

                // 5. Toggle Waffle Dashboard via WaffleNavigation
                WaffleLooks.WaffleNavigation.toggleDashboard("exercisesTracker")
                check(GlobalStates.dashboardOpen === true && GlobalStates.dashboardPageId === "exercisesTracker",
                    "WaffleNavigation.toggleDashboard did not open Dashboard on exercisesTracker")
                const dashLoader = findChild(wafflePanelsLoader.item, "waffleDashboardLoader")
                check(dashLoader !== null, "waffleDashboardLoader missing in ShellWafflePanelsImpl")
                tryVerify(() => dashLoader.item !== null, 5000)
                WaffleLooks.WaffleNavigation.toggleDashboard()
                check(GlobalStates.dashboardOpen === false, "Second toggleDashboard did not close Dashboard")

                // 6. Open Waffle Settings via WaffleNavigation (previously threw ReferenceError: SettingsPageRegistry is not defined)
                WaffleLooks.WaffleNavigation.openSettings("integrations", "exercises_tracker")
                check(GlobalStates.settingsOverlayOpen === true,
                    "WaffleNavigation.openSettings did not open in-process SettingsOverlay")
                check(GlobalStates.settingsOverlayRequestedPage === 38,
                    "Expected SettingsPageRegistry integrations route page 38, got " + GlobalStates.settingsOverlayRequestedPage)
                tryVerify(() => settingsOverlay.pageHost && !settingsOverlay.pageHost.loading && settingsOverlay.pageHost.currentItem !== null, 8000)

                // 7. Switching windowMode toggles useSettingsOverlay cleanly
                Config.setNestedValue("waffles.settings.windowMode", true)
                check(GlobalStates.useSettingsOverlay() === false, "waffles.settings.windowMode=true did not disable overlay mode")
                Config.setNestedValue("waffles.settings.windowMode", false)
                check(GlobalStates.useSettingsOverlay() === true, "waffles.settings.windowMode=false did not restore overlay mode")

                console.info("WAFFLE_POPUPS_DASHBOARD_SETTINGS_PASS", checks)
            } catch (err) {
                console.error("WAFFLE_POPUPS_DASHBOARD_SETTINGS_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 120
        running: true
        repeat: false
        onTriggered: test.run()
    }
}
"""


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-waffle-surfaces-") as tmp:
        private = Path(tmp)
        shell = private / "shell"
        shell.mkdir()
        for entry in (
            "services",
            "modules",
            "GlobalStates.qml",
            "qmldir",
            "scripts",
            "defaults",
            "translations",
            "assets",
        ):
            (shell / entry).symlink_to(ROOT / entry)
        (shell / "shell.qml").write_text(HARNESS_QML, encoding="utf-8")

        config_dir = private / "config/alis"
        config_dir.mkdir(parents=True)
        options = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
        options["panelFamily"] = "waffle"
        options["settingsUi"]["overlayMode"] = False  # Even when classic overlayMode=false, Waffle uses fast overlay unless waffles.settings.windowMode=true
        # Simulate pre-patch active user config without exercises_tracker key
        options["integrations"]["alisIntergration"] = {
            "tlp": False,
            "thinkfan": False,
            "nexus": False,
            "spaced_repetition": True,
        }
        (config_dir / "config.json").write_text(json.dumps(options), encoding="utf-8")

        import hashlib
        base_dir = private / "data/alis-intergration/current"
        base_dir.mkdir(parents=True)
        base_files = {}
        for rel_name in ("AlisSession.qml", "LICENSE"):
            raw = (ROOT / "assets/alis-intergration-base" / rel_name).read_bytes()
            (base_dir / rel_name).write_bytes(raw)
            base_files[rel_name] = hashlib.sha256(raw).hexdigest()
        base_manifest = json.loads((ROOT / "assets/alis-intergration-base/manifest.json").read_text(encoding="utf-8"))
        base_manifest.update({
            "layout": "base-v2",
            "sourceSha": "a" * 40,
            "files": base_files,
        })
        (base_dir / "manifest.json").write_text(json.dumps(base_manifest, indent=2), encoding="utf-8")

        ex_dir = private / "data/alis-intergration/plugins/exercises_tracker"
        ex_payloads = {
            "services/ExercisesTracker.qml": b"import QtQuick\nItem { property bool ready: true }\n",
            "modules/dashboard/DashboardExercisesTracker.qml": b"import QtQuick\nItem { implicitHeight: 64 }\n",
            "modules/settings/DashboardExercisesTrackerSettings.qml": b"import QtQuick\nItem { implicitHeight: 48 }\n",
            "scripts/integrations/exercises_tracker.py": b"print('{}')\n",
        }
        ex_hashes = {}
        for rel_path, content in ex_payloads.items():
            dst = ex_dir / rel_path
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_bytes(content)
            ex_hashes[rel_path] = hashlib.sha256(content).hexdigest()
        (ex_dir / "plugin-manifest.json").write_text(json.dumps({
            "id": "exercises_tracker",
            "version": "1.0.0",
            "hostApi": 1,
            "sourceSha": "a" * 40,
            "files": ex_hashes,
        }, indent=2), encoding="utf-8")
        (private / "data/alis-intergration/installed-plugins.json").write_text(
            json.dumps({"schemaVersion": 1, "plugins": ["exercises_tracker"]}, indent=2),
            encoding="utf-8",
        )

        runtime = private / "runtime"
        runtime.mkdir(mode=0o700)
        env = {
            k: v
            for k, v in os.environ.items()
            if k not in ("WAYLAND_DISPLAY", "DISPLAY", "NIRI_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE")
        }
        env.update(
            {
                "XDG_RUNTIME_DIR": str(runtime),
                "XDG_CONFIG_HOME": str(private / "config"),
                "XDG_STATE_HOME": str(private / "state"),
                "XDG_CACHE_HOME": str(private / "cache"),
                "XDG_DATA_HOME": str(private / "data"),
                "QT_NO_XDG_DESKTOP_PORTAL": "1",
            }
        )

        with private_wayland(private) as wayland_env:
            if wayland_env is not None:
                env.update(
                    {
                        k: v
                        for k, v in wayland_env.items()
                        if k in ("WAYLAND_DISPLAY", "NIRI_SOCKET", "DISPLAY", "XDG_RUNTIME_DIR")
                    }
                )
                env["QT_QPA_PLATFORM"] = "wayland"
            else:
                env["QT_QPA_PLATFORM"] = "offscreen"
                env["QT_QUICK_BACKEND"] = "software"
            res = run_qs(shell, env, timeout=45)

        bad_tokens = (
            "WAFFLE_POPUPS_DASHBOARD_SETTINGS_FAIL",
            "Property value set multiple times",
            "Type WorkspaceThumbnail unavailable",
            "Type WaffleTaskView unavailable",
            "ReferenceError:",
            "TypeError:",
            "Failed to load configuration",
            "Cannot assign to non-existent property",
        )
        if (
            res.returncode != 0
            or "WAFFLE_POPUPS_DASHBOARD_SETTINGS_PASS" not in res.stdout
            or any(tok in res.stdout for tok in bad_tokens)
        ):
            print(res.stdout)
            raise SystemExit(1)

    print(
        "WAFFLE_POPUPS_DASHBOARD_SETTINGS_PASS ShellWafflePanelsImpl, all 5 Waffle popups, Dashboard loader/buttons, SettingsOverlay route & legacy config migration"
    )


if __name__ == "__main__":
    main()
