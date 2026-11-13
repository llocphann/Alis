#!/usr/bin/env python3
"""Native Quickshell runtime verification for Left Sidebar + Alis-Companion:
1. Tab indicator (`ToolbarTabBar.activeIndicator`) tracks every tab switch in
   4-tab compact mode (`ai`, `translator`, `news`, `tools`) without freezing
   behind `[ai, translator, tools]` or painting a duplicate button pill.
2. Switching across non-adjacent tabs (`ai -> news -> translator -> tools -> ai`)
   keeps loaded tab views (`AiChat` / `AquaCompanionChatView`) alive and keeps
   `embeddedCloud.editing` stable without teardown/rebuild stutter.
3. Clicking the `Pocket` tab inside Left Sidebar (`embeddedMode: true`) opens
   Pocket ONLY inside Left Sidebar (`embeddedCloud.pocketOpen === true`) while
   `AquaPocket.opened === false` and the desktop Companion's floating
   `AquaTalkCloud` stays hidden (`floatingCloud.visible === false`).
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
COMPANION_REPO = REPO.parent / "Alis-Companion"

if not shutil.which("qs") or not os.environ.get("WAYLAND_DISPLAY"):
    print("SKIP: native Sidebar Left tabs + Pocket runtime requires Quickshell + Wayland")
    raise SystemExit(0)

if not COMPANION_REPO.is_dir():
    print("SKIP: sibling Alis-Companion repo unavailable")
    raise SystemExit(0)

QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.sidebarLeft
import "companion_pkg/services" as CompServices
import "companion_pkg/modules/abyss/companion" as CompUi

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 960
        implicitHeight: 740
        color: "#0b1112"

        Item {
            id: mockActor
            x: 680
            y: 580
            width: 72
            height: 64
            visible: true
            property bool inputReady: true
            property string expression: "idle"
            property string activity: "idle"
            property bool pocketDragActive: false
            property real pocketDragX: 0
            property real pocketDragY: 0
        }

        CompUi.AquaTalkCloud {
            id: floatingCloud
            actor: mockActor
            outputWidth: win.width
            outputHeight: win.height
            allowed: true
            embeddedMode: false
        }

        SidebarLeftContent {
            id: sidebar
            x: 16
            y: 16
            width: 440
            height: 680
            panelVisible: true
            externalConnectedSurface: true
            aiChatEnabled: true
            translatorEnabled: true
            newsEnabled: true
            toolsEnabled: true
        }

        CompUi.AquaCompanionChatView {
            id: companionSidebarProbe
            parent: sidebar
            x: 0
            y: 0
            width: 400
            height: 540
            visible: true
        }
    }

    TestCase {
        id: test
        when: false
        optional: true

        function check(ok, msg) {
            if (!ok)
                throw new Error(msg);
        }

        function findByObjectName(item, targetName) {
            if (!item)
                return null;
            if (item.objectName === targetName)
                return item;
            const kids = item.data ?? item.children ?? [];
            for (let i = 0; i < kids.length; ++i) {
                const found = findByObjectName(kids[i], targetName);
                if (found)
                    return found;
            }
            return null;
        }

        function findTabButtons(item, out) {
            if (!item)
                return out;
            if (item.materialSymbol !== undefined && item.showLabel !== undefined && item.current !== undefined)
                out.push(item);
            const kids = item.children ?? [];
            for (let i = 0; i < kids.length; ++i)
                findTabButtons(kids[i], out);
            return out;
        }

        function runAll() {
            try {
                tryCompare(Config, "ready", true, 5000);
                GlobalStates.sidebarLeftOpen = true;
                Config.setNestedValue("panelFamily", "abyss");
                Config.setNestedValue("abyss.companion.enabled", true);
                Config.setNestedValue("abyss.companion.pocketEnabled", true);
                CompServices.AquaPocket.hostAvailable = true;

                const indicator = findByObjectName(sidebar, "activeIndicator");
                check(Boolean(indicator), "Missing ToolbarTabBar activeIndicator in SidebarLeftContent");

                const buttons = findTabButtons(sidebar, []).sort((a, b) => a.x - b.x);
                check(buttons.length === 4, "Expected 4 sidebar tab buttons, got " + buttons.length);

                // 1. Verify initial activeIndicator on Tab 0 (Intelligence) and single-pill styling
                tryVerify(() => indicator.width > 60 && Math.abs(indicator.x - buttons[0].x) <= 1.5
                    && Math.abs(indicator.width - buttons[0].width) <= 1.5, 3000);
                check(buttons[0].colBackgroundToggled.a === 0,
                    "ToolbarTabButton must not paint a second opaque background pill over activeIndicator");

                // Wait for staggered tab prewarm to instantiate all 4 tabs cleanly
                wait(420);
                const innerSurface = findByObjectName(sidebar, "sidebarLeftInnerSurface");
                const swipe = innerSurface?.children?.[0] ?? null;
                check(Boolean(swipe) && swipe.count === 4, "Expected SwipeView with 4 tab loaders");
                const aiItemInitial = swipe.itemAt(0)?.item ?? null;
                check(Boolean(aiItemInitial), "Initial AI tab item should be loaded");

                // 2. Click Tab 3 (News) and verify activeIndicator glides to Tab 3 (NEVER stuck at x=0!)
                const newsIndex = sidebar.tabButtonList.findIndex(t => t.id === "news");
                check(newsIndex >= 0, "Missing news tab in tabButtonList");
                buttons[newsIndex].clicked();

                tryVerify(() => {
                    const b = findTabButtons(sidebar, []);
                    const target = indicator.targetItem;
                    return Boolean(target)
                        && target.current === true
                        && Math.abs(indicator.x - target.x) <= 1.5
                        && Math.abs(indicator.width - target.width) <= 1.5
                        && indicator.x > 80;
                }, 3000);

                // Verify AI tab instance was NOT destroyed when jumping to News, and embeddedCloud.editing stayed true
                check(swipe.itemAt(0)?.item === aiItemInitial,
                    "Switching from Intelligence to News must keep AiChat loaded without destroying/recreating it");
                check(companionSidebarProbe.cloud.editing === true,
                    "Embedded Companion cloud must keep editing === true while host sidebar remains open");

                // 3. Cycle through Translator -> Tools -> Intelligence and verify indicator alignment every time
                for (const id of ["translator", "tools", "ai"]) {
                    const idx = sidebar.tabButtonList.findIndex(t => t.id === id);
                    check(idx >= 0, "Missing tab " + id);
                    const curButtons = findTabButtons(sidebar, []);
                    const btn = curButtons.find(b => b.index === idx);
                    check(Boolean(btn), "Missing button delegate for index " + idx);
                    btn.clicked();
                    tryVerify(() => {
                        const target = indicator.targetItem;
                        return swipe.currentIndex === idx
                            && sidebar.selectedTabId === id
                            && Boolean(target)
                            && Math.abs(indicator.x - target.x) <= 1.5
                            && Math.abs(indicator.width - target.width) <= 1.5;
                    }, 3000);
                }
                check(swipe.itemAt(0)?.item === aiItemInitial,
                    "AiChat instance must remain identical across full 4-tab roundtrip");

                // 4. Verify clicking Pocket tab in Left Sidebar NEVER opens floating Companion Pocket Popup!
                const embeddedCloud = companionSidebarProbe.cloud;
                const pocketBtn = findByObjectName(embeddedCloud, "aquaUnifiedPocketTab");
                const chatBtn = findByObjectName(embeddedCloud, "aquaUnifiedChatTab");
                check(Boolean(pocketBtn) && pocketBtn.visible, "Missing aquaUnifiedPocketTab in embedded cloud");
                check(Boolean(chatBtn) && chatBtn.visible, "Missing aquaUnifiedChatTab in embedded cloud");
                check(!floatingCloud.visible && !floatingCloud.pocketOpen && !CompServices.AquaPocket.opened,
                    "Floating Companion Pocket popup must start closed");

                pocketBtn.clicked();
                wait(80);
                check(embeddedCloud.pocketOpen === true,
                    "Clicking Left Sidebar Pocket tab must open Pocket inside embedded Left Sidebar cloud");
                check(Boolean(embeddedCloud.activePocketPane) && embeddedCloud.activePocketPane.visible,
                    "Embedded AquaPocketPane must be visible inside Left Sidebar");
                check(CompServices.AquaPocket.opened === false,
                    "Clicking Left Sidebar Pocket tab MUST NOT set global AquaPocket.opened = true");
                check(floatingCloud.pocketOpen === false && floatingCloud.visible === false,
                    "Clicking Left Sidebar Pocket tab MUST NOT open floating Companion Pocket popup");

                // Switch back to Chat inside Left Sidebar
                chatBtn.clicked();
                wait(60);
                check(embeddedCloud.pocketOpen === false && embeddedCloud.editing === true,
                    "Clicking Chat tab in Left Sidebar must return to embedded Chat view");
                check(floatingCloud.visible === false && CompServices.AquaPocket.opened === false,
                    "Floating Companion popup must remain closed when returning to Chat in Left Sidebar");

                // Verify direct desktop Companion Pocket still works independently
                CompServices.AquaPocket.opened = true;
                wait(60);
                check(floatingCloud.pocketOpen === true && floatingCloud.visible === true,
                    "Desktop Companion floating Pocket popup must still open when triggered directly on Companion");
                check(embeddedCloud.pocketOpen === false,
                    "Desktop Companion floating Pocket popup must not force Left Sidebar into Pocket tab");
                CompServices.AquaPocket.close();

                console.info("SIDEBAR_TABS_AND_POCKET_PASS");
            } catch (err) {
                console.error("SIDEBAR_TABS_AND_POCKET_FAIL:", err.message, err.stack ?? "");
            }
            Qt.quit();
        }
    }

    Timer {
        interval: 150
        running: true
        repeat: false
        onTriggered: test.runAll()
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-sidebar-pocket-") as tmp:
    folder = Path(tmp)
    for name in (
        "modules",
        "services",
        "GlobalStates.qml",
        "settings.qml",
        "qmldir",
        "assets",
        "scripts",
        "defaults",
        "translations",
    ):
        (folder / name).symlink_to(REPO / name)
    (folder / "companion_pkg").symlink_to(COMPANION_REPO)
    (folder / "shell.qml").write_text(QML, encoding="utf-8")

    env = os.environ.copy()
    env["XDG_CONFIG_HOME"] = str(folder / "config")
    env["XDG_STATE_HOME"] = str(folder / "state")
    env["XDG_CACHE_HOME"] = str(folder / "cache")
    env["XDG_DATA_HOME"] = str(folder / "data")
    for sub in ("config/illogical-impulse", "state", "cache", "data/alis-companion"):
        (folder / sub).mkdir(parents=True, exist_ok=True)
    # Symlink current companion release for AlisCompanion availability if needed
    live_comp = Path.home() / ".local/share/alis-companion/current"
    if live_comp.exists():
        (folder / "data/alis-companion/current").symlink_to(live_comp.resolve())

    proc = subprocess.run(
        ["dbus-run-session", "--", "qs", "-p", str(folder), "--no-color"],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    out = proc.stdout or ""
    if (
        proc.returncode != 0
        or "SIDEBAR_TABS_AND_POCKET_PASS" not in out
        or "SIDEBAR_TABS_AND_POCKET_FAIL" in out
    ):
        print(out)
        raise SystemExit(1)
    print("SIDEBAR_TABS_AND_POCKET_PASS")
