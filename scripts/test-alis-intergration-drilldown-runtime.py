#!/usr/bin/env python3
"""Headless Quickshell UI runtime test for Integrations drill-down, Weekly Planner Calendar Sync, and Search actions."""
from __future__ import annotations

from contextlib import nullcontext
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INTERGRATION_ROOT = ROOT.parent / "Alis-Intergration"
sys.path.insert(0, str(ROOT / "scripts"))
from native_test_session import private_wayland, run_qs


QML = r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.settings
import qs.modules.dashboard

Window {
    id: root
    visible: true
    width: 1120
    height: 820
    color: "#151920"
    Component.onCompleted: Quickshell.watchFiles = false

    IntegrationsConfig {
        id: integrationsPage
        width: parent.width
        height: parent.height
        visible: true
    }

    DashboardWeeklyPlanner {
        id: weeklyPlanner
        anchors.fill: parent
        visible: false
        presentationActive: false
    }

    Loader {
        id: servicesLoader
        anchors.fill: parent
        visible: false
        active: true
        source: Quickshell.shellPath("modules/settings/ServicesConfig.qml")
    }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0
        function check(ok, msg) {
            checks++
            if (!ok)
                throw new Error(msg)
        }
        function find(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            for (const child of item.children ?? []) {
                const found = find(child, name)
                if (found) return found
            }
            return null
        }
        function hasText(item, needle) {
            if (!item) return false
            if (typeof item.text === "string" && item.text.includes(needle)) return true
            for (const c of item.children ?? []) {
                if (hasText(c, needle)) return true
            }
            return false
        }
        function collectTruncated(item, out) {
            if (!item || !item.visible) return
            if (item.truncated === true && typeof item.text === "string" && item.text.length > 0 && item.width > 0)
                out.push(`${item.text} (w=${Math.round(item.width)}, cw=${Math.round(item.contentWidth ?? -1)})`)
            for (const c of item.children ?? [])
                collectTruncated(c, out)
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 6000)
                tryCompare(AlisIntergration, "initialProbeDone", true, 6000)

                // 1. Integrations management list shows installed nexus + uninstalled plugins, NO bulk buttons or modal popup.
                check(AlisIntergration.isPluginInstalled("nexus") === true, "Expected nexus fixture installed")
                check(!AlisIntergration.isPluginInstalled("tlp"), "Expected tlp uninstalled")
                check(find(integrationsPage, "integrationPluginModal") === null, "Deprecated modal popup still mounted")
                check(find(integrationsPage, "integrationSystemHelpersCard") === null, "External System Helpers card still mounted")
                check(find(integrationsPage, "integrationCalendarSyncCard") === null, "Calendar Sync card should not be in Integrations")
                check(find(integrationsPage, "integrationWorkflowsCard") === null, "Workflows card should not be in Integrations")
                check(integrationsPage.slideProgress === 0 && !integrationsPage.detailOpen, "Expected initial Management list view")
                check(integrationsPage.activeSubViewTitle === "", "Expected empty activeSubViewTitle on Management list")

                const viewport = find(integrationsPage, "integrationDrillDownViewport")
                const listView = find(integrationsPage, "integrationListView")
                const detailView = find(integrationsPage, "integrationDetailView")
                check(!!viewport && !!listView && !!detailView, "Drill-down viewport/views missing")
                wait(60)
                check(Math.abs(listView.x) < 1 && Math.abs(detailView.x - viewport.width) < 1,
                    `Initial drill-down positions wrong: listView.x=${listView.x}, detailView.x=${detailView.x}, width=${viewport.width}`)

                // 2. Clicking uninstalled plugin row must NOT slide into Settings.
                const tlpCard = find(integrationsPage, "integrationPluginCard_tlp")
                const tlpDownload = find(integrationsPage, "integrationInstall_tlp")
                const tlpSettings = find(integrationsPage, "integrationOpenSettings_tlp")
                check(!!tlpCard && !!tlpDownload && tlpDownload.visible, "Download & Install button missing for uninstalled tlp")
                check(!tlpSettings || !tlpSettings.visible, "Settings button must stay hidden when tlp is uninstalled")
                mouseClick(tlpCard, tlpCard.width * 0.35, tlpCard.height * 0.5)
                wait(120)
                check(!integrationsPage.detailOpen && integrationsPage.slideProgress === 0 && integrationsPage.selectedPluginId === "",
                    "Clicking uninstalled plugin row must NOT open detail settings")
                check(!AlisIntergration.spacedRepetitionDemanded && !AlisIntergration.exercisesTrackerDemanded,
                    "Viewing Integrations management list must NOT eagerly demand SR/ET workers")

                // 2b. Clicking Download & Install fetches & installs ONLY that plugin cleanly, then opens its detail & Uninstall works.
                mouseClick(tlpDownload, tlpDownload.width * 0.5, tlpDownload.height * 0.5)
                tryVerify(() => AlisIntergration.isPluginInstalled("tlp") && !AlisIntergration.managerBusy, 8000)
                const tlpSettingsAfter = find(integrationsPage, "integrationOpenSettings_tlp")
                check(!!tlpSettingsAfter && tlpSettingsAfter.visible, "TLP Settings button did not appear after Download & Install")
                mouseClick(tlpSettingsAfter, tlpSettingsAfter.width * 0.5, tlpSettingsAfter.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", true, 2000)
                tryCompare(integrationsPage, "selectedPluginId", "tlp", 2000)
                Config.setNestedValue("integrations.alisIntergration.tlp", true)
                const tlpCenterPill = find(integrationsPage, "integrationHeaderCenterPill")
                check(!!tlpCenterPill && tlpCenterPill.visible, "integrationHeaderCenterPill missing in TLP detail header")
                tryVerify(() => find(tlpCenterPill, "tlpStatusBadgeButton") !== null, 3000)
                const tlpStandaloneBar = find(find(integrationsPage, "integrationPluginSettings"), "tlpTopStatusSubTab")
                check(!tlpStandaloneBar || !tlpStandaloneBar.visible, "Embedded TLP must hide duplicate standalone status bar")
                Config.setNestedValue("integrations.alisIntergration.tlp", false)
                const uninstallTlp = find(integrationsPage, "integrationUninstallPluginButton")
                check(!!uninstallTlp && uninstallTlp.visible, "Uninstall button missing in detail view")
                mouseClick(uninstallTlp, uninstallTlp.width * 0.5, uninstallTlp.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", false, 2000)
                tryVerify(() => !AlisIntergration.isPluginInstalled("tlp") && !AlisIntergration.managerBusy, 8000)

                // 3. Clicking installed plugin Settings slides horizontally (list slides left, detail slides in from right).
                const nexusSettingsBtn = find(integrationsPage, "integrationOpenSettings_nexus")
                check(!!nexusSettingsBtn && nexusSettingsBtn.visible, "Settings button missing for installed nexus")
                mouseClick(nexusSettingsBtn, nexusSettingsBtn.width * 0.5, nexusSettingsBtn.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", true, 2000)
                tryCompare(integrationsPage, "slideProgress", 1.0, 2000)
                check(integrationsPage.activeSubViewTitle === "Alis Nexus",
                    `Expected activeSubViewTitle 'Alis Nexus', got '${integrationsPage.activeSubViewTitle}'`)
                wait(40)
                check(Math.abs(detailView.x) < 1 && Math.abs(listView.x + viewport.width) < 1,
                    `Slid-in positions wrong: listView.x=${listView.x}, detailView.x=${detailView.x}, width=${viewport.width}`)
                const capTabsRail = find(integrationsPage, "integrationCapabilityTabs")
                check(!capTabsRail || !capTabsRail.visible, "Nexus must not show capability tabs bar")
                const centerPill = find(integrationsPage, "integrationHeaderCenterPill")
                const helpersBtn = find(integrationsPage, "integrationPluginHelpersButton")
                check(!!centerPill && centerPill.visible && !!helpersBtn && helpersBtn.visible,
                    "Centered compact helpers toggle pill missing from detailView header")
                const depsCard = find(integrationsPage, "integrationPluginDependenciesCard")
                check(!!depsCard && !depsCard.visible, "Compact Dependencies & Diagnostics drawer should start collapsed")
                mouseClick(helpersBtn, helpersBtn.width * 0.5, helpersBtn.height * 0.5)
                tryCompare(depsCard, "visible", true, 2000)
                wait(450)
                mouseClick(helpersBtn, helpersBtn.width * 0.5, helpersBtn.height * 0.5)
                tryCompare(depsCard, "visible", false, 2000)
                tryVerify(() => find(integrationsPage, "alisIntergrationNexusTodoSettings") !== null, 3000)
                const nexusTodoCard = find(integrationsPage, "alisIntergrationNexusTodoSettings")
                const nexusVault = find(integrationsPage, "nexusVaultPath")
                const nexusPattern = find(integrationsPage, "nexusTodoNotePattern")
                const nexusQuickFolder = find(integrationsPage, "nexusQuickNoteFolder")
                check(!!nexusTodoCard && nexusTodoCard.visible && !!nexusVault && nexusVault.visible
                    && !!nexusPattern && nexusPattern.visible && !!nexusQuickFolder && nexusQuickFolder.visible,
                    "Unified Nexus single-tab settings must render Nexus vault, To-do, and Quick Notes together")

                // 3b. Nexus Shortcuts sub-tab Escape priority: first Escape closes Shortcuts sub-tab (& clears recordingActionId),
                // second Escape exits Nexus detail view.
                const openShortcutsBtn = find(integrationsPage, "openNexusShortcutsTabButton")
                tryVerify(() => !!openShortcutsBtn && openShortcutsBtn.visible, 3000)
                mouseClick(openShortcutsBtn, openShortcutsBtn.width * 0.5, openShortcutsBtn.height * 0.5)
                const pluginSettingsLoader = find(integrationsPage, "integrationPluginSettings")
                tryVerify(() => pluginSettingsLoader?.item?.shortcutsTabOpen === true, 2000)
                check(nexusTodoCard.visible === false, "Opening Nexus Shortcuts sub-tab must hide To-do & Quick Notes card")
                const shortcutScope = find(integrationsPage, "nexusShortcutCaptureScope")
                check(!!shortcutScope, "nexusShortcutCaptureScope missing")
                shortcutScope.recordingActionId = "commandPalette"
                check(integrationsPage.handleEscape() === true, "First handleEscape must close Nexus Shortcuts sub-tab")
                check(pluginSettingsLoader.item.shortcutsTabOpen === false, "First Escape did not close Nexus shortcutsTabOpen")
                check(nexusTodoCard.visible === true, "Closing Nexus Shortcuts sub-tab must restore To-do & Quick Notes card")
                check(shortcutScope.recordingActionId === "", "Closing Shortcuts sub-tab must clear recordingActionId")
                check(integrationsPage.detailOpen === true && integrationsPage.selectedPluginId === "nexus",
                    "First Escape from Nexus Shortcuts sub-tab must stay inside Nexus detail view")
                check(integrationsPage.handleEscape() === true, "Second handleEscape must exit Nexus detail view")
                tryCompare(integrationsPage, "detailOpen", false, 2000)
                tryCompare(integrationsPage, "slideProgress", 0.0, 2000)
                wait(40)
                check(integrationsPage.activeSubViewTitle === "", "activeSubViewTitle must clear after exiting detail view")

                // 4. Clicking Back slides back to Management list; handleEscape also reverses drill-down.
                mouseClick(nexusSettingsBtn, nexusSettingsBtn.width * 0.5, nexusSettingsBtn.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", true, 2000)
                tryCompare(integrationsPage, "slideProgress", 1.0, 2000)
                const backBtn = find(integrationsPage, "integrationBackButton")
                check(!!backBtn && backBtn.visible, "integrationBackButton missing in detail header")
                mouseClick(backBtn, backBtn.width * 0.5, backBtn.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", false, 2000)
                tryCompare(integrationsPage, "slideProgress", 0.0, 2000)
                wait(40)
                check(Math.abs(listView.x) < 1 && integrationsPage.handleEscape() === false,
                    "handleEscape when already on Management list should return false")
                mouseClick(nexusSettingsBtn, nexusSettingsBtn.width * 0.5, nexusSettingsBtn.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", true, 2000)
                check(integrationsPage.handleEscape() === true, "handleEscape must consume Back from detail view")
                tryCompare(integrationsPage, "detailOpen", false, 2000)
                tryCompare(integrationsPage, "slideProgress", 0.0, 2000)
                check(integrationsPage.activateSettingsSearchSection("To-do"), "Search deep link to installed Nexus Todo failed")
                tryCompare(integrationsPage, "detailOpen", true, 2000)
                check(integrationsPage.selectedPluginId === "nexus" && integrationsPage.selectedCapability?.settings === "nexus",
                    "Installed Nexus deep link did not open unified Nexus settings")
                tryVerify(() => find(integrationsPage, "nexusTodoNotePattern")?.visible === true
                    && find(integrationsPage, "nexusQuickNoteFolder")?.visible === true, 2000)
                integrationsPage.exitSubView()
                tryCompare(integrationsPage, "detailOpen", false, 2000)
                tryCompare(integrationsPage, "slideProgress", 0.0, 2000)
                wait(40)

                // 4b. Spaced Repetition: Download & Install, python3 in Dependencies & Diagnostics, and zero truncated labels at narrow detailWidth <= 462.
                const srDownload = find(integrationsPage, "integrationInstall_spaced_repetition")
                check(!!srDownload && srDownload.visible, "Download & Install button missing for spaced_repetition")
                mouseClick(srDownload, srDownload.width * 0.5, srDownload.height * 0.5)
                tryVerify(() => AlisIntergration.isPluginInstalled("spaced_repetition") && !AlisIntergration.managerBusy, 8000)
                Config.setNestedValue("integrations.alisIntergration.spaced_repetition", true)
                tryCompare(AlisIntergration, "spacedRepetitionEnabled", true, 2000)
                const srSettingsBtn = find(integrationsPage, "integrationOpenSettings_spaced_repetition")
                check(!!srSettingsBtn && srSettingsBtn.visible, "Settings button missing for installed spaced_repetition")
                mouseClick(srSettingsBtn, srSettingsBtn.width * 0.5, srSettingsBtn.height * 0.5)
                tryCompare(integrationsPage, "detailOpen", true, 2000)
                tryCompare(integrationsPage, "selectedPluginId", "spaced_repetition", 2000)
                check(integrationsPage.activeSubViewTitle === "Spaced Repetition",
                    `Expected activeSubViewTitle 'Spaced Repetition', got '${integrationsPage.activeSubViewTitle}'`)
                tryVerify(() => find(integrationsPage, "alisIntergrationSpacedRepetitionSettings") !== null, 3000)
                const srHelpersBtn = find(integrationsPage, "integrationPluginHelpersButton")
                const srDepsCard = find(integrationsPage, "integrationPluginDependenciesCard")
                check(!!srHelpersBtn && srHelpersBtn.visible && !!srDepsCard && !srDepsCard.visible,
                    "Spaced Repetition compact helpers drawer must start collapsed with header toggle visible")
                mouseClick(srHelpersBtn, srHelpersBtn.width * 0.5, srHelpersBtn.height * 0.5)
                tryCompare(srDepsCard, "visible", true, 2000)
                check(hasText(srDepsCard, "python3"), "Spaced Repetition Dependencies & Diagnostics must display python3")
                check(hasText(srDepsCard, "python3 · Ready"), "Spaced Repetition Dependencies & Diagnostics must show python3 · Ready")
                wait(450)
                mouseClick(srHelpersBtn, srHelpersBtn.width * 0.5, srHelpersBtn.height * 0.5)
                tryCompare(srDepsCard, "visible", false, 2000)

                // Narrow-width truncation check (detailView.width <= 462, plus page widths 560, 664, 760, 904, 1120)
                const srSettingsCard = find(integrationsPage, "alisIntergrationSpacedRepetitionSettings")
                for (const targetW of [462, 560, 664, 760, 904, 1120]) {
                    integrationsPage.width = targetW
                    if (targetW === 462)
                        tryVerify(() => detailView.width > 0 && detailView.width <= 462, 2000)
                    wait(80)
                    const truncated = []
                    collectTruncated(srSettingsCard, truncated)
                    check(truncated.length === 0,
                        `Spaced Repetition settings labels elided at page width=${targetW} (detailWidth=${Math.round(detailView.width)}): ${truncated.join("; ")}`)
                }
                integrationsPage.width = Qt.binding(() => root.width)
                integrationsPage.exitSubView()
                tryCompare(integrationsPage, "detailOpen", false, 2000)
                tryCompare(integrationsPage, "slideProgress", 0.0, 2000)
                wait(40)

                // 5. Weekly Planner Calendar Sync side panel toggles & dismisses cleanly.
                integrationsPage.visible = false
                weeklyPlanner.visible = true
                weeklyPlanner.presentationActive = true
                wait(80)
                const calAction = find(weeklyPlanner, "plannerCalendarSyncAction")
                check(!!calAction && calAction.visible, "plannerCalendarSyncAction toolbar button missing")
                mouseClick(calAction, calAction.width * 0.5, calAction.height * 0.5)
                tryCompare(weeklyPlanner, "sideView", "calendar", 2000)
                const sidePanel = find(weeklyPlanner, "plannerSharedSidePanel")
                tryVerify(() => sidePanel && sidePanel.visible && sidePanel.item !== null, 3000)
                check(weeklyPlanner.handleEscape() === true && weeklyPlanner.sideView === "",
                    "Escape / handleEscape did not dismiss Calendar Sync panel")
                const yearModeBtn = find(weeklyPlanner, "plannerModeYear")
                check(!!yearModeBtn && yearModeBtn.visible, "plannerModeYear toggle missing")
                mouseClick(yearModeBtn, yearModeBtn.width * 0.5, yearModeBtn.height * 0.5)
                wait(80)
                check(!!calAction && calAction.visible, "Calendar Sync button must stay available in Year planner mode")
                mouseClick(calAction, calAction.width * 0.5, calAction.height * 0.5)
                tryCompare(weeklyPlanner, "sideView", "calendar", 2000)
                tryVerify(() => sidePanel && sidePanel.visible && sidePanel.item !== null, 3000)
                check(weeklyPlanner.handleEscape() === true && weeklyPlanner.sideView === "",
                    "Calendar Sync panel did not toggle/dismiss in Year mode")

                // 6. ServicesConfig -> Search exposes relocated Search/Launcher controls.
                weeklyPlanner.visible = false
                tryCompare(servicesLoader, "status", Loader.Ready, 4000)
                const servicesPage = servicesLoader.item
                servicesLoader.visible = true
                wait(60)
                check(servicesPage.activateSettingsSearchSection("Search"), "ServicesConfig failed to focus Search section")
                wait(40)
                check(hasText(servicesPage, "Package actions in Search")
                    && hasText(servicesPage, "Setup actions in Search")
                    && hasText(servicesPage, "Custom actions in Search")
                    && hasText(servicesPage, "Launcher result delay (ms)"),
                    "ServicesConfig Search section missing relocated launcher controls")

                console.info("DRILLDOWN_PLANNER_RUNTIME_PASS", checks)
            } catch (err) {
                console.error("DRILLDOWN_PLANNER_RUNTIME_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 100
        running: true
        repeat: false
        onTriggered: test.run()
    }
}
"""


OFFSCREEN_CONTEXT_MENU_STUB = """import QtQuick
Loader {
    id: root
    active: false
    property var model: []
    property Item anchorItem: parent
    property real padding: 4
    property bool noSmoothClosing: false
    property bool closeOnFocusLost: true
    property bool keyboardGrab: true
    property bool closeOnHoverLost: true
    property bool closeOnHoverLostAfterEntered: false
    property int closeOnHoverLostDelay: 500
    property bool anchorHovered: false
    property bool closeOnOutsideClick: false
    property var anchorRect: null
    property var popupAdjustment: null
    property bool scaleContent: false
    property bool cursorSlide: false
    property var cursorAnchorWindow: null
    property real cursorAnchorX: 0
    property real cursorAnchorY: 0
    property real visualMargin: 8
    property bool popupAbove: true
    property int popupSide: 0
    property real ambientShadowWidth: 1
    property color panelFallbackColor: "transparent"
    property real panelRadius: 8
    property real panelBorderWidth: 0
    property color panelBorderColor: "transparent"
    signal focusCleared()
    function grabFocus() {}
    function close() { root.active = false }
    function requestOpen() { root.active = true }
    function requestOpenAt(x, y, newModel) { if (newModel !== undefined) root.model = newModel; root.active = true }
}
"""


def _install_offscreen_modules_overlay(folder: Path, host_root: Path) -> None:
    mod_link = folder / "modules"
    if mod_link.is_symlink():
        mod_link.unlink()
    mod_link.mkdir(parents=True, exist_ok=True)
    for child in (host_root / "modules").iterdir():
        if child.name == "common":
            common_dir = mod_link / "common"
            common_dir.mkdir(parents=True, exist_ok=True)
            for cchild in child.iterdir():
                if cchild.name == "widgets":
                    w_dir = common_dir / "widgets"
                    w_dir.mkdir(parents=True, exist_ok=True)
                    for wchild in cchild.iterdir():
                        if wchild.name == "ContextMenu.qml":
                            (w_dir / "ContextMenu.qml").write_text(OFFSCREEN_CONTEXT_MENU_STUB, encoding="utf-8")
                        else:
                            (w_dir / wchild.name).symlink_to(wchild)
                else:
                    (common_dir / cchild.name).symlink_to(cchild)
        else:
            (mod_link / child.name).symlink_to(child)


def main() -> None:
    if not INTERGRATION_ROOT.is_dir():
        print("SKIP: drill-down runtime test requires companion Alis-Intergration repo")
        raise SystemExit(0)

    with tempfile.TemporaryDirectory(prefix="alis-drilldown-runtime-") as tmp:
        folder = Path(tmp)
        for entry in (
            "services",
            "modules",
            "GlobalStates.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
        ):
            (folder / entry).symlink_to(ROOT / entry)
        (folder / "shell.qml").write_text(QML, encoding="utf-8")

        config_dir = folder / "config/alis"
        config_dir.mkdir(parents=True)
        cfg = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
        cfg["performance"]["reduceAnimations"] = True
        cfg["integrations"]["alisIntergration"]["nexus"] = True
        (config_dir / "config.json").write_text(json.dumps(cfg), encoding="utf-8")

        def build_offscreen_env() -> dict[str, str]:
            e = {
                k: v
                for k, v in os.environ.items()
                if k not in ("WAYLAND_DISPLAY", "DISPLAY", "NIRI_SOCKET", "HYPRLAND_INSTANCE_SIGNATURE")
            }
            for kind in ("config", "state", "cache", "data"):
                d = folder / kind
                d.mkdir(parents=True, exist_ok=True)
                e[f"XDG_{kind.upper()}_HOME"] = str(d)
            e.update({
                "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software",
            })
            return e

        use_offscreen = os.environ.get("QT_QPA_PLATFORM") == "offscreen"
        ctx = nullcontext(build_offscreen_env()) if use_offscreen else private_wayland(folder)
        native_wayland = False
        try:
            env = ctx.__enter__()
            if not use_offscreen and env is not None:
                native_wayland = True
        except RuntimeError:
            ctx = nullcontext(build_offscreen_env())
            env = ctx.__enter__()

        try:
            if env is None:
                env = build_offscreen_env()
                native_wayland = False
            if not native_wayland:
                _install_offscreen_modules_overlay(folder, ROOT)

            data_dir = Path(env.get("XDG_DATA_HOME", folder / "data"))
            spec = importlib.util.spec_from_file_location("mgr", ROOT / "scripts/alis-intergration-manager.py")
            mgr = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mgr)
            integ_home = data_dir / "alis-intergration"
            mgr.operate("install-base", integ_home, ROOT)
            mgr.operate("install-plugin", integ_home, ROOT, plugin_id="nexus", source_dir=INTERGRATION_ROOT)

            env.setdefault("QT_QUICK_BACKEND", "software")
            env["ALIS_INTERGRATION_SOURCE"] = str(INTERGRATION_ROOT)
            res = run_qs(folder, env, timeout=30)
            bad = (
                "DRILLDOWN_PLANNER_RUNTIME_FAIL",
                "ReferenceError:",
                "TypeError:",
                "Cannot assign to non-existent property",
                "Unable to assign",
            )
            if res.returncode != 0 or "DRILLDOWN_PLANNER_RUNTIME_PASS" not in res.stdout or any(b in res.stdout for b in bad):
                print(res.stdout)
                raise SystemExit(1)
            for line in res.stdout.splitlines():
                if "DRILLDOWN_PLANNER_RUNTIME_PASS" in line:
                    print(line.strip())
        finally:
            ctx.__exit__(None, None, None)


if __name__ == "__main__":
    main()
