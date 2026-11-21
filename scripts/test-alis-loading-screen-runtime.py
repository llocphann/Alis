#!/usr/bin/env python3
"""Silent offscreen Quickshell runtime verification for AlisLoadingScreen,
gear-free SettingsPageLoadingOverlay, immediate AbyssBodyHost loading reveal,
Escape focus/input while loading, and single-spinner AbyssNexusContent continuity.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Static contract checks on AbyssPerimeter Escape / keyboardFocus while loading
perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
for host_id in ("dashboardBody", "settings", "nexusBody", "aux", "wallpaperBody", "clipboardBody", "controls", "utility", "leftPanel", "rightPanel"):
    assert f"({host_id}.ready || {host_id}.loadingPresentationActive)" in perimeter, (
        f"AbyssPerimeter WlrLayershell.keyboardFocus must accept {host_id}.loadingPresentationActive for Escape while loading"
    )
assert "!(host.ready || host.loadingPresentationActive)" in perimeter, (
    "AbyssPerimeter ensureEscapeFocus must include hosts in loadingPresentationActive"
)

# Static contract checks on standalone/Waffle Dashboard.qml cold-open loading shell & Escape
dashboard_standalone = (ROOT / "modules/dashboard/Dashboard.qml").read_text(encoding="utf-8")
for token in (
    'asynchronous: (Quickshell.env("QT_QUICK_BACKEND") !== "software") && status !== Loader.Ready',
    "visible: contentLoader.status === Loader.Ready",
    'objectName: "standaloneDashboardLoadingShell"',
    'objectName: "standaloneDashboardLoadingScreen"',
    "AlisLoadingScreen {",
    "root._contentPresented && contentLoader.status !== Loader.Ready",
    "transform: Translate { y: contentLoader.panelTranslateY }",
    'Translation.tr("Local Music")',
    '"music_note"',
    'Translation.tr("Planner")',
    '"calendar_month"',
    'Translation.tr("Spaced Repetition")',
    '"school"',
    'Translation.tr("Exercises")',
    '"fitness_center"',
    'Translation.tr("Dashboard")',
    '"dashboard"',
    "enabled: GlobalStates.dashboardOpen && contentLoader.status !== Loader.Ready",
    "onActivated: panelRoot.hide()",
):
    assert token in dashboard_standalone, f"Dashboard.qml cold-open loading contract missing: {token}"

# Static contract checks on DashboardContent.qml _firstSurfaceReady latch & tabLoading formula
dashboard_content = (ROOT / "modules/dashboard/DashboardContent.qml").read_text(encoding="utf-8")
for token in (
    "property bool _firstSurfaceReady: false",
    "property bool _surfaceCompleted: false",
    "readonly property bool _rawContentReady:",
    "function _syncFirstSurfaceReady(): void {",
    "on_RawContentReadyChanged: root._syncFirstSurfaceReady()",
    "readonly property bool contentReady: _firstSurfaceReady || _rawContentReady",
    "(!root._rawContentReady && (!root.embeddedSurface || root._firstSurfaceReady))",
):
    assert token in dashboard_content, f"DashboardContent.qml _firstSurfaceReady contract missing: {token}"

qmlformat = "/usr/lib/qt6/bin/qmlformat"
if Path(qmlformat).is_file():
    for rel in (
        "modules/dashboard/Dashboard.qml",
        "modules/dashboard/DashboardContent.qml",
        "modules/common/widgets/AlisLoadingScreen.qml",
        "modules/common/widgets/SettingsPageLoadingOverlay.qml",
    ):
        subprocess.run([qmlformat, str(ROOT / rel)], stdout=subprocess.DEVNULL, check=True)

if not shutil.which("qs"):
    print("SKIP: qs unavailable")
    raise SystemExit(0)

def make_panelwindow_free_stub(rel_path: str) -> str:
    txt = (ROOT / rel_path).read_text(encoding="utf-8")
    lines = ["import QtQuick", "Item {", "    id: root", "    property bool active: false", "    property var item: null"]
    seen = {"active", "item"}
    for line in txt.splitlines():
        ms = re.match(r"^    (signal\s+\w+.*)", line)
        if ms:
            lines.append("    " + ms.group(1))
            continue
        m = re.match(r"^    ((?:required\s+)?(?:readonly\s+)?property\s+(\S+)\s+(\w+))", line)
        if not m:
            continue
        ptype, pname = m.group(2), m.group(3)
        if pname in seen or pname in ("id", "x", "y", "width", "height", "visible", "enabled", "opacity", "z", "parent", "data", "children", "anchors"):
            continue
        seen.add(pname)
        if ptype == "bool": default = "false"
        elif ptype in ("int", "real", "double"): default = "0"
        elif ptype == "string": default = '""'
        elif ptype in ("var", "Item", "QtObject", "Component"): default = "null"
        elif ptype == "color": default = '"transparent"'
        else: continue
        lines.append(f"    property {ptype} {pname}: {default}")
    lines.append("    default property alias _stubContent: host.data")
    lines.append("    function open() {}")
    lines.append("    function close() {}")
    lines.append("    function popup() {}")
    lines.append("    function toggle() {}")
    lines.append("    Item { id: host }")
    lines.append("}")
    return "\n".join(lines)

def copy_modules_with_stubs(src_root: Path, dst_root: Path, stubs: dict[str, str]):
    dst_root.mkdir(parents=True, exist_ok=True)
    for p in src_root.iterdir():
        rel = str(p.relative_to(ROOT))
        if rel in stubs:
            (dst_root / p.name).write_text(stubs[rel], encoding="utf-8")
        elif p.is_dir() and any(s.startswith(rel + "/") for s in stubs):
            copy_modules_with_stubs(p, dst_root / p.name, stubs)
        else:
            (dst_root / p.name).symlink_to(p)

with tempfile.TemporaryDirectory(prefix="alis-loading-screen-rt-") as name:
    folder = Path(name)
    for entry in ["services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    stubs = {
        "modules/bar/StyledPopup.qml": make_panelwindow_free_stub("modules/bar/StyledPopup.qml"),
        "modules/common/widgets/ContextMenu.qml": make_panelwindow_free_stub("modules/common/widgets/ContextMenu.qml"),
    }
    copy_modules_with_stubs(ROOT / "modules", folder / "modules", stubs)
    cfg = folder / "config/alis"
    cfg.mkdir(parents=True)
    data = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
    data["panelFamily"] = "abyss"
    data["abyss"]["companion"]["enabled"] = False
    (cfg / "config.json").write_text(json.dumps(data), encoding="utf-8")

    # Slow dummy panel whose contentReady stays false until toggled by the test
    (folder / "DelayedPanel.qml").write_text(r'''
import QtQuick
Item {
    id: delayed
    property var participant: null
    property bool contentReady: false
    Rectangle { anchors.fill: parent; color: "#223344" }
}
''', encoding="utf-8")

    (folder / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss
import qs.modules.abyss.content
import qs.modules.dashboard

ShellRoot {
    id: root
    Component.onCompleted: {
        Quickshell.watchFiles = false
        GlobalStates.deferredPanelsReady = true
    }

    Item {
        id: stage
        width: 1000
        height: 700

        SettingsPageLoadingOverlay {
            id: settingsOverlay
            width: 400
            height: 300
            loading: true
            title: "Search & Services"
            icon: "settings"
        }

        AbyssSurfaceController {
            id: controller
            outputWidth: stage.width
            outputHeight: stage.height
            presentationItem: stage
        }

        // Opt-in immediate loading screen host (large surface)
        AbyssBodyHost {
            id: immediateHost
            anchors.fill: parent
            identity: "dashboard"
            edge: "bottom"
            controller: controller
            animatePresentation: false
            largeSurface: true
            showLoadingSurface: true
            loadingTitle: "Local Music"
            loadingIcon: "music_note"
            span: 680
            depth: 480
            along: 160
            open: true
            source: Qt.resolvedUrl("DelayedPanel.qml")
        }

        // Edge-connected host (Sidebar style) with immediate loading screen
        AbyssBodyHost {
            id: sidebarLoadingHost
            anchors.fill: parent
            identity: "leftPanel"
            edge: "left"
            controller: controller
            animatePresentation: false
            includeEdgeConnection: true
            showLoadingSurface: true
            loadingTitle: "Sidebar"
            loadingIcon: "view_sidebar"
            span: 320
            depth: 360
            along: 120
            open: true
            source: Qt.resolvedUrl("DelayedPanel.qml")
        }

        // Legacy default host (showLoadingSurface: false) must preserve original wait-for-ready contract
        AbyssBodyHost {
            id: legacyHost
            anchors.fill: parent
            identity: "legacyPopup"
            edge: "top"
            controller: controller
            animatePresentation: false
            largeSurface: true
            span: 400
            depth: 200
            along: 300
            open: true
            source: Qt.resolvedUrl("DelayedPanel.qml")
        }

        // Verify AbyssNexusContent mounts AlisLoadingScreen cleanly and avoids dual-spinner overlap
        AbyssNexusContent {
            id: nexusHostedPreview
            width: 400
            height: 300
            participant: ({ open: true, progress: 1, backgroundPreload: false, showLoadingSurface: true })
        }

        AbyssNexusContent {
            id: nexusStandalonePreview
            width: 400
            height: 300
            participant: ({ open: true, progress: 1, backgroundPreload: false, showLoadingSurface: false })
        }

        // Verify DashboardContent _firstSurfaceReady header stability & external tab jump loading
        DashboardContent {
            id: dashEmbedded
            width: 820
            height: 540
            embeddedSurface: true
            presentationActive: true
        }
    }

    function findByObjectName(item, target) {
        if (!item) return null
        if (item.objectName === target) return item
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) {
            const found = findByObjectName(kids[i], target)
            if (found) return found
        }
        return null
    }

    function hasSettingsGear(item) {
        if (!item) return false
        if (item.text === "settings" && item.iconSize !== undefined) return true
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) {
            if (hasSettingsGear(kids[i])) return true
        }
        return false
    }

    property int phase: 0
    Timer {
        interval: 180
        running: true
        repeat: true
        onTriggered: {
            try {
                if (root.phase === 0) {
                    // 1. SettingsPageLoadingOverlay mounts AlisLoadingScreen and NEVER renders settings gear even when page icon === "settings"
                    const screen = root.findByObjectName(settingsOverlay, "alisLoadingScreen")
                    if (!screen || !screen.visible)
                        throw new Error("SettingsPageLoadingOverlay missing visible AlisLoadingScreen")
                    if (root.hasSettingsGear(settingsOverlay))
                        throw new Error("SettingsPageLoadingOverlay still rendered retired settings gear glyph")
                    // Zero opacity must pause animations
                    screen.opacity = 0
                    if (screen.activeAnimation)
                        throw new Error("AlisLoadingScreen failed to pause animation when opacity === 0")
                    screen.opacity = 1
                    settingsOverlay.loading = false
                    if (settingsOverlay.visible || screen.activeAnimation)
                        throw new Error("SettingsPageLoadingOverlay failed to pause when loading=false")

                    // 2. Immediate host reveals popup with loading screen BEFORE contentReady becomes true
                    if (!immediateHost.contentItem.item || !sidebarLoadingHost.contentItem.item)
                        return // wait one tick for Loader
                    if (immediateHost.ready)
                        throw new Error("DelayedPanel became ready unexpectedly early")
                    if (immediateHost.availabilityProgress !== 1 || immediateHost.progress !== 1)
                        throw new Error("showLoadingSurface host did not reveal immediately: p=" + immediateHost.progress)
                    if (!immediateHost.loadingPresentationActive)
                        throw new Error("loadingPresentationActive was false while content unready")
                    const bodyLoader = root.findByObjectName(immediateHost, "abyssBodyLoadingScreen")
                    if (!bodyLoader || !bodyLoader.visible)
                        throw new Error("abyssBodyLoadingScreen not visible during unready reveal")
                    if (immediateHost.inputBounds.width <= 0)
                        throw new Error("loading popup must accept Escape input while loading")

                    // 2b. Edge-connected loading host keeps inputFrame enabled during loading
                    if (!sidebarLoadingHost.loadingPresentationActive || sidebarLoadingHost.inputBounds.width <= 0)
                        throw new Error("edge-connected loading host missing input bounds while loading")
                    if (!sidebarLoadingHost.hoverParent.enabled)
                        throw new Error("edge-connected loading host disabled inputFrame while loading")

                    // 3. Legacy host (showLoadingSurface: false) still waits for contentReady
                    if (legacyHost.progress !== 0 || legacyHost.inputBounds.width !== 0)
                        throw new Error("legacy host broke wait-for-ready contract")

                    // 4. AbyssNexusContent single-spinner continuity
                    const hostedLoad = root.findByObjectName(nexusHostedPreview, "nexusWorkspaceLoadingScreen")
                    const standaloneLoad = root.findByObjectName(nexusStandalonePreview, "nexusWorkspaceLoadingScreen")
                    if (!hostedLoad || !standaloneLoad)
                        throw new Error("nexusWorkspaceLoadingScreen missing in AbyssNexusContent")
                    if (hostedLoad.loading)
                        throw new Error("AbyssNexusContent rendered duplicate loading screen while host owns showLoadingSurface")
                    if (!standaloneLoad.loading)
                        throw new Error("Standalone AbyssNexusContent failed to show loading screen while workspaceLoader unready")

                    // 5. DashboardContent _firstSurfaceReady latch & external tab jump stability
                    const dashTabLoader = root.findByObjectName(dashEmbedded, "dashboardTabLoadingScreen")
                    if (!dashTabLoader)
                        throw new Error("dashboardTabLoadingScreen missing in DashboardContent")
                    // Before first page settles, embeddedSurface must NOT duplicate the host's loading screen
                    if (!dashEmbedded._firstSurfaceReady && dashTabLoader.tabLoading)
                        throw new Error("embedded DashboardContent showed duplicate tabLoading before _firstSurfaceReady")
                    if (!dashEmbedded.contentReady)
                        return // wait one tick for initial dashboardCanvas widgetsReady
                    if (!dashEmbedded._firstSurfaceReady)
                        throw new Error("DashboardContent did not latch _firstSurfaceReady after initial page settled")
                    if (dashTabLoader.tabLoading)
                        throw new Error("dashboardTabLoadingScreen stayed active after initial page settled")
                    // Trigger an external jump (not selectPage()) to Local Music and verify:
                    // (a) contentReady stays latched true so AbyssBodyHost keeps header steady
                    // (b) tabLoading activates cleanly inside the viewport while musicPage incubates
                    GlobalStates.dashboardPageId = "music"
                    if (!dashEmbedded.contentReady)
                        throw new Error("DashboardContent contentReady dropped to false on external tab jump (would cover header)")
                    if (dashEmbedded._rawContentReady)
                        throw new Error("expected musicPage to still be asynchronously incubating immediately after external jump")
                    if (!dashTabLoader.tabLoading)
                        throw new Error("dashboardTabLoadingScreen failed to activate on async external jump to Local Music")
                    if (dashTabLoader.title !== "Local Music" || dashTabLoader.icon !== "music_note")
                        throw new Error("dashboardTabLoadingScreen wrong metadata on external jump: " + dashTabLoader.title + "/" + dashTabLoader.icon)
                    // Also verify selectPage() / requestPage() to Planner keeps contentReady latched and shows Planner loading screen
                    dashEmbedded.requestPage("weeklyPlanner")
                    if (!dashEmbedded.contentReady)
                        throw new Error("DashboardContent contentReady dropped on requestPage(weeklyPlanner)")
                    if (!dashTabLoader.tabLoading || dashTabLoader.title !== "Planner" || dashTabLoader.icon !== "calendar_month")
                        throw new Error("dashboardTabLoadingScreen wrong state on requestPage(weeklyPlanner): loading=" + dashTabLoader.tabLoading + " title=" + dashTabLoader.title + " icon=" + dashTabLoader.icon)

                    // Now mark DelayedPanel ready and verify loading screen dismisses cleanly
                    immediateHost.contentItem.item.contentReady = true
                    sidebarLoadingHost.contentItem.item.contentReady = true
                    root.phase = 1
                } else if (root.phase === 1) {
                    if (!immediateHost.ready || !sidebarLoadingHost.ready)
                        throw new Error("hosts did not become ready after contentReady=true")
                    if (immediateHost.loadingPresentationActive || sidebarLoadingHost.loadingPresentationActive)
                        throw new Error("loadingPresentationActive stayed true after ready")
                    const bodyLoader = root.findByObjectName(immediateHost, "abyssBodyLoadingScreen")
                    if (bodyLoader && bodyLoader.loading)
                        throw new Error("abyssBodyLoadingScreen remained in loading state")
                    // 5b. Cold-open DashboardContent truth table: embeddedSurface=true suppresses duplicate
                    // tabLoading before _firstSurfaceReady, while embeddedSurface=false activates tabLoading immediately.
                    GlobalStates.dashboardSelectionRestored = true
                    GlobalStates.dashboardPageId = "weeklyPlanner"
                    const dashComp = Qt.createComponent(Qt.resolvedUrl("modules/dashboard/DashboardContent.qml"))
                    if (dashComp.status !== Component.Ready)
                        throw new Error("DashboardContent component failed: " + dashComp.errorString())
                    const coldEmbedded = dashComp.createObject(stage, {
                        width: 820, height: 540, embeddedSurface: true, presentationActive: true
                    })
                    const coldStandalone = dashComp.createObject(stage, {
                        width: 820, height: 540, embeddedSurface: false, presentationActive: true
                    })
                    if (!coldEmbedded || !coldStandalone)
                        throw new Error("failed to create cold-open DashboardContent instances")
                    const coldEmbTab = root.findByObjectName(coldEmbedded, "dashboardTabLoadingScreen")
                    const coldStdTab = root.findByObjectName(coldStandalone, "dashboardTabLoadingScreen")
                    if (coldEmbedded._firstSurfaceReady || coldEmbedded._rawContentReady || coldEmbedded.contentReady)
                        throw new Error("coldEmbedded should be unready while weeklyPlanner incubates (page=" + coldEmbedded.currentPageId + " first=" + coldEmbedded._firstSurfaceReady + " raw=" + coldEmbedded._rawContentReady + ")")
                    if (coldEmbTab.tabLoading)
                        throw new Error("coldEmbedded duplicated host loading screen before _firstSurfaceReady")
                    if (!coldStdTab.tabLoading || coldStdTab.title !== "Planner" || coldStdTab.icon !== "calendar_month")
                        throw new Error("coldStandalone failed to show tab loading screen on cold open: loading=" + coldStdTab.tabLoading + " title=" + coldStdTab.title)
                    coldEmbedded.destroy()
                    coldStandalone.destroy()

                    // 5c. Hidden background preload (warmContent=true, presentationActive=false on "dashboard")
                    // must NOT prematurely latch _firstSurfaceReady=true while async widgets are still loading.
                    GlobalStates.dashboardPageId = "dashboard"
                    const hiddenWarm = dashComp.createObject(stage, {
                        width: 820, height: 540, embeddedSurface: true, presentationActive: false, warmContent: true
                    })
                    if (!hiddenWarm)
                        throw new Error("failed to create hiddenWarm DashboardContent")
                    if (!hiddenWarm._rawContentReady && (hiddenWarm._firstSurfaceReady || hiddenWarm.contentReady))
                        throw new Error("hiddenWarm prematurely latched _firstSurfaceReady=true during construction while _rawContentReady=false")
                    hiddenWarm.destroy()

                    console.info("ALIS_LOADING_SCREEN_RUNTIME_PASS")
                    Qt.quit()
                }
            } catch (e) {
                console.error("ALIS_LOADING_SCREEN_RUNTIME_FAIL", e.message)
                Qt.quit()
            }
        }
    }
}
''', encoding="utf-8")

    env = os.environ.copy()
    for k in ["WAYLAND_DISPLAY", "DISPLAY", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"]:
        env.pop(k, None)
    env.update(
        QT_QPA_PLATFORM="offscreen",
        QT_QUICK_BACKEND="software",
        XDG_CONFIG_HOME=str(folder / "config"),
        XDG_STATE_HOME=str(folder / "state"),
        XDG_CACHE_HOME=str(folder / "cache"),
    )
    res = subprocess.run(["qs", "-p", str(folder), "--no-color"], env=env, text=True, capture_output=True, timeout=25)
    log = res.stdout + res.stderr
    bad = ["ALIS_LOADING_SCREEN_RUNTIME_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Cannot assign", "Cannot override FINAL"]
    if res.returncode != 0 or "ALIS_LOADING_SCREEN_RUNTIME_PASS" not in log or any(b in log for b in bad):
        print(log)
        raise SystemExit(1)

# ─── Part 2: Live offscreen Dashboard.qml async cold-open loading shell test ───
# Runs real Dashboard.qml (replacing only PanelWindow with an Item container in
# the temp dir) with QT_QUICK_BACKEND unset so asynchronous Loader incubation
# actually executes and proves:
# 1. standaloneDashboardLoadingShell appears immediately with dynamic page title/icon
# 2. inner dashboardTabLoadingScreen stays hidden (no duplicate animation) while incubating
# 3. standaloneDashboardLoadingShell dismisses once contentLoader reaches Loader.Ready
# 4. hide() dismisses cleanly
with tempfile.TemporaryDirectory(prefix="alis-dashboard-standalone-rt-") as name2:
    folder2 = Path(name2)
    for entry in ["services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder2 / entry).symlink_to(ROOT / entry)
    dash_test = dashboard_standalone.replace(
        "PanelWindow {\n        id: panelRoot",
        "Item {\n        id: panelRoot\n        property var screen: ({ width: 1920, height: 1080 })\n        width: 1920; height: 1080\n        property bool updatesEnabled\n        property real exclusiveZone\n        property color color\n        property var mask",
    )
    dash_test = re.sub(r"^\s*WlrLayershell\..*$", "", dash_test, flags=re.M)
    dash_test = re.sub(r"^\s*anchors\s*\{[^}]*\}", "", dash_test, flags=re.M | re.S)
    dash_test = re.sub(
        r"CompositorFocusGrab\s*\{.*?\n        \}",
        "Item { id: grab; property bool active: false }",
        dash_test,
        flags=re.S,
    )
    stubs2 = {
        "modules/bar/StyledPopup.qml": make_panelwindow_free_stub("modules/bar/StyledPopup.qml"),
        "modules/common/widgets/ContextMenu.qml": make_panelwindow_free_stub("modules/common/widgets/ContextMenu.qml"),
        "modules/dashboard/Dashboard.qml": dash_test,
    }
    copy_modules_with_stubs(ROOT / "modules", folder2 / "modules", stubs2)
    cfg2 = folder2 / "config/alis"
    cfg2.mkdir(parents=True)
    data2 = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
    data2["panelFamily"] = "waffle"
    data2["abyss"]["companion"]["enabled"] = False
    (cfg2 / "config.json").write_text(json.dumps(data2), encoding="utf-8")

    (folder2 / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.dashboard

ShellRoot {
    id: root
    Component.onCompleted: {
        Quickshell.watchFiles = false
        GlobalStates.dashboardSelectionRestored = true
        GlobalStates.dashboardPageId = "music"
        GlobalStates.dashboardOpen = true
    }
    Dashboard { id: standaloneDash }
    function findByObjectName(item, target) {
        if (!item) return null
        if (item.objectName === target) return item
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) {
            const f = findByObjectName(kids[i], target)
            if (f) return f
        }
        return null
    }
    property bool sawShellLoading: false
    property bool sawShellDismissed: false
    property int tick: 0
    Timer {
        interval: 15; running: true; repeat: true
        onTriggered: {
            try {
                root.tick++
                const win = standaloneDash.dashboardWindow
                const shell = win ? root.findByObjectName(win, "standaloneDashboardLoadingShell") : null
                const screen = win ? root.findByObjectName(win, "standaloneDashboardLoadingScreen") : null
                const tabLoad = win ? root.findByObjectName(win, "dashboardTabLoadingScreen") : null
                if (!shell || !screen)
                    throw new Error("standaloneDashboardLoadingShell or screen missing")
                if (shell.visible) {
                    root.sawShellLoading = true
                    if (screen.title !== "Local Music" || screen.icon !== "music_note")
                        throw new Error("wrong standalone loading metadata: " + screen.title + "/" + screen.icon)
                    if (tabLoad && tabLoad.visible)
                        throw new Error("duplicate inner dashboardTabLoadingScreen visible/animating behind standaloneDashboardLoadingShell")
                } else if (root.sawShellLoading) {
                    root.sawShellDismissed = true
                }
                if (root.sawShellDismissed) {
                    win.hide()
                    if (GlobalStates.dashboardOpen)
                        throw new Error("panelRoot.hide() did not clear GlobalStates.dashboardOpen")
                    console.info("STANDALONE_DASHBOARD_ASYNC_LOADING_PASS")
                    Qt.quit()
                } else if (root.tick >= 160) {
                    throw new Error("timeout waiting for standalone Dashboard async incubation: sawShell=" + root.sawShellLoading)
                }
            } catch (e) {
                console.error("STANDALONE_DASHBOARD_ASYNC_LOADING_FAIL", e.message)
                Qt.quit()
            }
        }
    }
}
''', encoding="utf-8")

    env2 = os.environ.copy()
    for k in ["WAYLAND_DISPLAY", "DISPLAY", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "QT_QUICK_BACKEND"]:
        env2.pop(k, None)
    env2.update(
        QT_QPA_PLATFORM="offscreen",
        XDG_CONFIG_HOME=str(folder2 / "config"),
        XDG_STATE_HOME=str(folder2 / "state"),
        XDG_CACHE_HOME=str(folder2 / "cache"),
    )
    res2 = subprocess.run(["qs", "-p", str(folder2), "--no-color"], env=env2, text=True, capture_output=True, timeout=25)
    log2 = res2.stdout + res2.stderr
    bad2 = ["STANDALONE_DASHBOARD_ASYNC_LOADING_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Cannot assign", "Cannot override FINAL"]
    if res2.returncode != 0 or "STANDALONE_DASHBOARD_ASYNC_LOADING_PASS" not in log2 or any(b in log2 for b in bad2):
        print(log2)
        raise SystemExit(1)

print("ALIS_LOADING_SCREEN_RUNTIME_PASS")
