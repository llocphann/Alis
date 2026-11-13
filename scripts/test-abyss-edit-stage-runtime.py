#!/usr/bin/env python3
"""Native Quickshell runtime verification for the Abyss Desktop Edit Stage:
1. Entering Widgets, Abyss Layout, Dashboard Layout, or Settings Layout Edit Mode
   shrinks the Desktop Stage into a centered proportional card (`s <= 0.83`).
2. Abyss Screen Edges (`AbyssField` + `AbyssBar` + `AbyssEdgeEditor` + panels)
   scale and translate together with the shrunk Desktop Stage.
3. The 2-tier Customization Control Dock mounts OUTSIDE and IMMEDIATELY BELOW
   the shrunk Desktop Stage at 1:1 UI scale, welded via `AbyssEditStageFrame`.
4. Exiting Edit Mode restores full 1:1 desktop geometry cleanly.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import sys as _silent_sys
if os.environ.get("ALIS_SILENT_TEST_MODE") != "1":
    raise SystemExit(subprocess.call([_silent_sys.executable, str(Path(__file__).resolve().parent / "native_test_session.py"), "--", _silent_sys.executable, __file__, *_silent_sys.argv[1:]]))

REPO = Path(__file__).resolve().parents[1]
if not shutil.which("qs") or not os.environ.get("WAYLAND_DISPLAY"):
    print("SKIP: native Abyss edit stage runtime (Quickshell/Wayland unavailable)")
    raise SystemExit(0)

QML = r'''
import QtQuick
import QtQuick.Window
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import qs.modules.background.widgets

ShellRoot {
    id: root
    property int step: 0
    property bool failed: false
    property real widgetsBottomW: 0
    property real widgetsBottomH: 0
    property real widgetsRightW: 0
    property real widgetsRightH: 0

    function check(ok, msg): bool {
        if (ok)
            return true;
        console.error("STAGE_EDIT_FAIL:", msg);
        root.failed = true;
        Qt.quit();
        return false;
    }

    function findByObjectName(item, targetName) {
        if (!item)
            return null;
        if (item.objectName === targetName)
            return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) {
            const found = findByObjectName(kids[i], targetName);
            if (found)
                return found;
        }
        return null;
    }

    QtObject {
        id: widgetWindowContext
        readonly property string screenName: Quickshell.screens[0]?.name ?? "STAGE_TEST"
    }

    QtObject {
        id: mockManager
        property bool shown: false
        property Item externalDockParent: null
    }

    FloatingWindow {
        id: win
        visible: true
        implicitWidth: 1600
        implicitHeight: 900
        color: "#060d10"

        readonly property string outputName: Quickshell.screens[0]?.name ?? "STAGE_TEST"
        readonly property bool presented: true
        readonly property var nativeInsets: ({ left: 16, top: 48, right: 16, bottom: 16 })
        function bodyInsets(edge, along, span) { return nativeInsets; }

        readonly property bool editorOpen: GlobalStates.abyssEditing
            && GlobalStates.abyssEditorTargetOutput === outputName
        readonly property bool dashboardStageEditing: dashboardBody.open
            && ((dashboardBody.contentItem.item?.editMode ?? false)
                || (dashboardBody.contentItem.item?.tabNamingActive ?? false))
        readonly property bool settingsStageEditing: settingsBody.open
            && (settingsBody.contentItem.item?.editMode ?? false)
        readonly property bool widgetStageEditing: GlobalStates.widgetEditMode
        readonly property bool wallpaperStageEditing: GlobalStates.wallpaperLauncherOpen
            && DesktopEditStage.wallpaperStageEnabled

        readonly property string editStageMode: !DesktopEditStage.stageEnabled ? ""
            : editorOpen ? "abyss"
            : settingsStageEditing ? "settings"
            : dashboardStageEditing ? "dashboard"
            : widgetStageEditing ? "widgets"
            : wallpaperStageEditing ? "wallpaper"
            : ""
        property string retainedEditStageMode: ""
        readonly property string displayEditStageMode: editStageMode.length > 0
            ? editStageMode : retainedEditStageMode
        readonly property var externalWidgetEditor: GlobalStates.desktopWidgetEditors[outputName] ?? null

        readonly property real stageDockW: displayEditStageMode === "abyss" ? editor.desiredDockWidth
            : displayEditStageMode === "widgets" ? (externalWidgetEditor?.desiredDockWidth ?? 960)
            : displayEditStageMode === "dashboard" ? (dashboardBody.contentItem.item?.editDockWidth ?? 940)
            : displayEditStageMode === "settings" ? (settingsBody.contentItem.item?.editDockWidth ?? 960)
            : displayEditStageMode === "wallpaper" ? (stageWallpaperLoader.item?.desiredDockWidth ?? 980)
            : 960
        readonly property real stageDockH: displayEditStageMode === "abyss" ? editor.desiredDockHeight
            : displayEditStageMode === "widgets" ? (externalWidgetEditor?.desiredDockHeight ?? 168)
            : displayEditStageMode === "dashboard" ? (dashboardBody.contentItem.item?.editDockHeight ?? 168)
            : displayEditStageMode === "settings" ? (settingsBody.contentItem.item?.editDockHeight ?? 168)
            : displayEditStageMode === "wallpaper" ? (stageWallpaperLoader.item?.desiredDockHeight ?? 176)
            : 168

        readonly property real rawStageLeftW: displayEditStageMode === "abyss" ? editor.desiredLeftDockWidth
            : displayEditStageMode === "dashboard" ? (dashboardBody.contentItem.item?.editLeftDockWidth ?? 0)
            : 0
        readonly property real rawStageLeftH: displayEditStageMode === "abyss" ? editor.desiredLeftDockHeight
            : displayEditStageMode === "dashboard" ? (dashboardBody.contentItem.item?.editLeftDockHeight ?? 0)
            : 0
        readonly property real rawStageRightW: displayEditStageMode === "abyss" ? editor.desiredRightDockWidth
            : displayEditStageMode === "widgets" ? (externalWidgetEditor?.desiredRightDockWidth ?? 248)
            : displayEditStageMode === "dashboard" ? (dashboardBody.contentItem.item?.editRightDockWidth ?? 0)
            : 0
        readonly property real rawStageRightH: displayEditStageMode === "abyss" ? editor.desiredRightDockHeight
            : displayEditStageMode === "widgets" ? (externalWidgetEditor?.desiredRightDockHeight ?? 460)
            : displayEditStageMode === "dashboard" ? (dashboardBody.contentItem.item?.editRightDockHeight ?? 0)
            : 0

        function syncStage(): void {
            if (editStageMode.length > 0) {
                retainedEditStageMode = editStageMode;
                const hasLeft = editStageMode === "abyss"
                    || (editStageMode === "dashboard" && rawStageLeftW > 160);
                const hasRight = editStageMode === "abyss" || editStageMode === "widgets"
                    || (editStageMode === "dashboard" && rawStageRightW > 160);
                DesktopEditStage.setStage(
                    outputName,
                    editStageMode,
                    1.0,
                    stageDockW,
                    stageDockH,
                    hasLeft ? rawStageLeftW : 0,
                    hasLeft ? rawStageLeftH : 0,
                    hasRight ? rawStageRightW : 0,
                    hasRight ? rawStageRightH : 0,
                    hasLeft ? 1.0 : 0.0,
                    hasRight ? 1.0 : 0.0
                );
            } else {
                DesktopEditStage.clearStage(outputName);
                retainedEditStageMode = "";
            }
        }

        Connections {
            target: win.externalWidgetEditor
            function onManagerShownChanged() { win.syncStage(); }
        }

        onEditStageModeChanged: syncStage()
        onStageDockWChanged: if (editStageMode.length > 0) syncStage()
        onStageDockHChanged: if (editStageMode.length > 0) syncStage()
        onRawStageLeftWChanged: if (editStageMode.length > 0) syncStage()
        onRawStageRightWChanged: if (editStageMode.length > 0) syncStage()
        Component.onCompleted: DesktopEditStage.setHost(outputName, true)

        readonly property var editCard: DesktopEditStage.cardFor(outputName, width, height)
        readonly property bool editStageVisible: editCard.p > 0.001

        readonly property Item stageAbyssDockHost: DesktopEditStage.stageEnabled ? stageAbyssDockContainer : null
        readonly property Item stageDashboardDockHost: DesktopEditStage.stageEnabled ? stageDashboardDockContainer : null
        readonly property Item stageLeftDashboardDockHost: DesktopEditStage.stageEnabled ? stageLeftDashboardDockContainer : null
        readonly property Item stageRightDashboardDockHost: DesktopEditStage.stageEnabled ? stageRightDashboardDockContainer : null
        readonly property Item stageSettingsDockHost: DesktopEditStage.stageEnabled ? stageSettingsDockContainer : null

        Item {
            id: backgroundDesktopStage
            objectName: "backgroundDesktopStage"
            width: win.width
            height: win.height
            transform: [
                Scale { xScale: win.editCard.s; yScale: win.editCard.s },
                Translate { x: win.editCard.x; y: win.editCard.y }
            ]

            Item {
                id: safeBounds
                anchors.fill: parent
                readonly property real safeLeft: 16
                readonly property real safeTop: 48
                readonly property real safeRight: width - 16
                readonly property real safeBottom: height - 16
                readonly property real safeWidth: safeRight - safeLeft
                readonly property real safeHeight: safeBottom - safeTop
            }

            DesktopWidgetEditToolbar {
                id: widgetToolbar
                windowContext: widgetWindowContext
                safeBounds: safeBounds
                manager: mockManager
                fallbackParent: safeBounds
            }
        }

        AbyssSurfaceController {
            id: liquid
            outputName: win.outputName
            outputWidth: win.width
            outputHeight: win.height
            presented: true
            presentationItem: field
            edgeInsets: win.nativeInsets
        }

        Item {
            id: abyssDesktopStage
            objectName: "abyssDesktopStage"
            width: win.width
            height: win.height
            transform: [
                Scale { xScale: win.editCard.s; yScale: win.editCard.s },
                Translate { x: win.editCard.x; y: win.editCard.y }
            ]

            AbyssEdgeEditor {
                id: editor
                anchors.fill: parent
                visible: win.editorOpen
                outputName: win.outputName
                moduleLayer: bar
                controller: liquid
                edgeInsets: win.nativeInsets
                externalDockParent: DesktopEditStage.stageEnabled ? stageAbyssDockContainer : null
                externalLeftDockParent: DesktopEditStage.stageEnabled ? stageLeftAbyssDockContainer : null
                externalRightDockParent: DesktopEditStage.stageEnabled ? stageRightAbyssDockContainer : null
            }

            AbyssBar {
                id: bar
                anchors.fill: parent
                outputName: win.outputName
                edge: "top"
                liquidController: liquid
                basePaintInsets: win.nativeInsets
                editing: editor.visible || win.widgetStageEditing
                draftPlacements: editor.visible ? editor.draft : null
                draftOptions: editor.visible ? editor.draftOptions : null
            }

            AbyssBodyHost {
                id: widgetEditorBody
                identity: "widgetEditor"
                controller: liquid
                anchors.fill: parent
                outputName: win.outputName
                embeddedItem: GlobalStates.desktopWidgetEditors[win.outputName] ?? null
                open: embeddedItem !== null && GlobalStates.widgetEditMode && !DesktopEditStage.hosted(win.outputName)
            }

            AbyssBodyHost {
                id: dashboardBody
                stableContentSize: true
                identity: "dashboard"
                controller: liquid
                anchors.fill: parent
                edge: "bottom"
                outputName: win.outputName
                open: GlobalStates.dashboardOpen
                largeSurface: true
                edgeInsets: win.nativeInsets
                span: win.width * 0.72 + 40
                along: (win.width - span) / 2
                depth: win.height * 0.72 + 40
                source: "content/AbyssDashboardContent.qml"
            }

            AbyssBodyHost {
                id: settingsBody
                stableContentSize: true
                identity: "settings"
                controller: liquid
                anchors.fill: parent
                edge: "bottom"
                outputName: win.outputName
                open: GlobalStates.settingsOverlayOpen
                largeSurface: true
                edgeInsets: win.nativeInsets
                span: Math.min(1400, win.width * 0.88)
                along: (win.width - span) / 2
                depth: Math.min(820, win.height * 0.88)
                source: "content/AbyssSettingsContent.qml"
            }

            AbyssBodyHost {
                id: wallpaperBody
                stableContentSize: true
                identity: "wallpaper"
                controller: liquid
                anchors.fill: parent
                edge: "bottom"
                outputName: win.outputName
                open: GlobalStates.wallpaperLauncherOpen && !DesktopEditStage.wallpaperStageEnabled
                edgeInsets: win.nativeInsets
                span: Math.min(1080, win.width * 0.92)
                along: (win.width - span) / 2
                depth: 180
                minimumSpan: 420
                minimumDepth: 120
                source: "content/AbyssWallpaperContent.qml"
            }

            AbyssField {
                id: field
                z: -1
                anchors.fill: parent
                outputName: win.outputName
                edgeInsets: win.nativeInsets
                records: liquid.records
            }
        }

        AbyssEditStageFrame {
            id: editStageFrame
            objectName: "abyssEditStageFrame"
            z: 500
            anchors.fill: parent
            card: win.editCard
        }

        Item {
            id: stageLeftEditDock
            objectName: "abyssStageLeftEditDock"
            z: 505
            visible: win.editStageVisible && win.editCard.leftDockWidth > 0 && win.editCard.leftProgress > 0.001
            x: win.editCard.leftDockX
            y: win.editCard.leftDockY
            width: win.editCard.leftDockWidth
            height: win.editCard.leftDockHeight
            clip: true
            Item {
                id: stageLeftAbyssDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "abyss" && stageLeftEditDock.visible
            }
            Item {
                id: stageLeftDashboardDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "dashboard" && stageLeftEditDock.visible
            }
        }

        Item {
            id: stageRightEditDock
            objectName: "abyssStageRightEditDock"
            z: 505
            visible: win.editStageVisible && win.editCard.rightDockWidth > 0 && win.editCard.rightProgress > 0.001
            x: win.editCard.rightDockX
            y: win.editCard.rightDockY
            width: win.editCard.rightDockWidth
            height: win.editCard.rightDockHeight
            clip: true
            Item {
                id: stageRightAbyssDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "abyss" && stageRightEditDock.visible
            }
            Item {
                id: stageRightDashboardDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "dashboard" && stageRightEditDock.visible
            }
            Item {
                id: stageRightWidgetManagerContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "widgets" && stageRightEditDock.visible
                Binding {
                    target: win.externalWidgetEditor
                    property: "abyssRightHost"
                    value: stageRightWidgetManagerContainer
                    when: win.externalWidgetEditor !== null && DesktopEditStage.hosted(win.outputName)
                    restoreMode: Binding.RestoreBindingOrValue
                }
            }
        }

        Item {
            id: stageEditDock
            objectName: "abyssStageEditDock"
            z: 505
            visible: win.editStageVisible
            x: win.editCard.dockX
            y: win.editCard.dockY
            width: win.editCard.dockWidth
            height: win.editCard.dockHeight
            clip: true

            Item {
                id: stageAbyssDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "abyss" && win.editStageVisible
            }
            Item {
                id: stageWidgetDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "widgets" && win.editStageVisible
                QtObject {
                    id: stageWidgetDockAdapter
                    readonly property real padding: 4
                    readonly property Item contentParent: stageWidgetDockContainer
                    readonly property bool visualResident: stageWidgetDockContainer.visible
                    readonly property var editorWorkArea: ({
                        left: 0,
                        top: 0,
                        right: Math.max(1, stageWidgetDockContainer.width),
                        bottom: Math.max(1, stageWidgetDockContainer.height)
                    })
                    readonly property var targetRecord: ({
                        content: Qt.rect(0, 0, Math.max(1, stageWidgetDockContainer.width), Math.max(1, stageWidgetDockContainer.height))
                    })
                }
                Binding {
                    target: win.externalWidgetEditor
                    property: "abyssHost"
                    value: stageWidgetDockAdapter
                    when: win.externalWidgetEditor !== null && DesktopEditStage.hosted(win.outputName)
                    restoreMode: Binding.RestoreBindingOrValue
                }
            }
            Item {
                id: stageDashboardDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "dashboard" && win.editStageVisible
            }
            Item {
                id: stageSettingsDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "settings" && win.editStageVisible
            }
            Item {
                id: stageWallpaperDockContainer
                anchors.fill: parent
                visible: win.displayEditStageMode === "wallpaper" && win.editStageVisible
                Loader {
                    id: stageWallpaperLoader
                    anchors.fill: parent
                    active: DesktopEditStage.wallpaperStageEnabled
                        && (win.wallpaperStageEditing || (win.displayEditStageMode === "wallpaper" && win.editStageVisible))
                    source: "modules/abyss/content/AbyssWallpaperContent.qml"
                }
            }
        }
    }

    function assertStageAndOuterDock(modeLabel, dockItem): bool {
        const card = win.editCard;
        if (!root.check(card.active && card.p === 1, modeLabel + ": editCard active"))
            return false;
        if (!root.check(card.s > 0.55 && card.s <= 0.84, modeLabel + ": desktop shrunk proportionally (s=" + card.s + ")"))
            return false;
        if (!root.check(card.x >= 24 && card.y >= 12, modeLabel + ": shrunk desktop centered with surround margins"))
            return false;

        // Verify Abyss Screen Edges (`field` + `bar`) transform with the shrunk desktop:
        const fieldTL = field.mapToItem(null, 0, 0);
        const fieldBR = field.mapToItem(null, field.width, field.height);
        if (!root.check(Math.abs(fieldTL.x - card.x) <= 1.5 && Math.abs(fieldTL.y - card.y) <= 1.5,
                modeLabel + ": AbyssField top-left matches shrunk desktop card"))
            return false;
        if (!root.check(Math.abs((fieldBR.x - fieldTL.x) - card.width) <= 2.0
                && Math.abs((fieldBR.y - fieldTL.y) - card.height) <= 2.0,
                modeLabel + ": AbyssField size matches shrunk desktop card"))
            return false;

        const bgTL = backgroundDesktopStage.mapToItem(null, 0, 0);
        if (!root.check(Math.abs(bgTL.x - card.x) <= 1.5 && Math.abs(bgTL.y - card.y) <= 1.5,
                modeLabel + ": Background desktop stage matches Abyss desktop stage"))
            return false;

        if (!root.check(editStageFrame.visible && editStageFrame.progress === 1,
                modeLabel + ": AbyssEditStageFrame visible"))
            return false;

        if (!root.check(Boolean(dockItem) && dockItem.visible && stageEditDock.visible,
                modeLabel + ": outer customization dock visible"))
            return false;

        const dockGlobal = dockItem.mapToItem(null, 0, 0);
        const dockBottom = dockGlobal.y + dockItem.height;
        if (!root.check(dockGlobal.y >= card.bottom - 0.5,
                modeLabel + ": dock sits OUTSIDE & BELOW shrunk desktop (dockY=" + dockGlobal.y + ", stageBottom=" + card.bottom + ")"))
            return false;
        if (!root.check((dockGlobal.y - card.bottom) <= card.bezel + 1.5,
                modeLabel + ": dock is welded seamlessly to shrunk desktop bezel (gap=" + (dockGlobal.y - card.bottom) + ")"))
            return false;
        if (!root.check(dockBottom <= win.height - 4,
                modeLabel + ": dock fits inside output height (dockBottom=" + dockBottom + ", winH=" + win.height + ")"))
            return false;
        if (!root.check(dockItem.width >= 600,
                modeLabel + ": dock renders at readable 1:1 unscaled width (" + dockItem.width + ")"))
            return false;
        if (!root.check(stageEditDock.width <= Math.round(card.width * 0.80) + 1,
                modeLabel + ": bottom dock width capped at <= 80% of shrunk Desktop (dockW=" + stageEditDock.width + ", max80=" + Math.round(card.width * 0.80) + ")"))
            return false;
        if (stageLeftEditDock.visible && !root.check(stageLeftEditDock.height <= Math.round(card.height * 0.80) + 1,
                modeLabel + ": left dock height capped at <= 80% of shrunk Desktop (leftH=" + stageLeftEditDock.height + ", max80=" + Math.round(card.height * 0.80) + ")"))
            return false;
        if (stageRightEditDock.visible && !root.check(stageRightEditDock.height <= Math.round(card.height * 0.80) + 1,
                modeLabel + ": right dock height capped at <= 80% of shrunk Desktop (rightH=" + stageRightEditDock.height + ", max80=" + Math.round(card.height * 0.80) + ")"))
            return false;

        return true;
    }

    Timer {
        id: watchdog
        interval: 18000
        running: Config.ready
        onTriggered: {
            console.error("STAGE_EDIT_FAIL: timed out at step=" + root.step
                + " dashOpen=" + dashboardBody.open + " dashProg=" + dashboardBody.progress
                + " dashItem=" + Boolean(dashboardBody.contentItem.item)
                + " setOpen=" + settingsBody.open + " setProg=" + settingsBody.progress
                + " setItem=" + Boolean(settingsBody.contentItem.item));
            Qt.quit();
        }
    }

    Timer {
        interval: 160
        repeat: true
        running: Config.ready
        onTriggered: {
            if (root.step === 0) {
                GlobalStates.deferredPanelsReady = true;
                Config.setNestedValue("panelFamily", "abyss");
                Config.setNestedValue("performance.reduceAnimations", true);
                if (!root.check(editStageFrame.transitionsEnabled === false,
                        "AbyssEditStageFrame outer backdrop disables wallpaper transitions"))
                    return;
                // Pure-slide invariance check across p = 0.05..1.00 (zero scale/shrink/grow on all 3 docks + screenshot dock)
                const c05 = DesktopEditStage.cardForGeometry(1920, 1080, "abyss", 0.05, 920, 150, 312, 280, 324, 420, 0.05, 0.05);
                const c50 = DesktopEditStage.cardForGeometry(1920, 1080, "abyss", 0.50, 920, 150, 312, 280, 324, 420, 0.50, 0.50);
                const c10 = DesktopEditStage.cardForGeometry(1920, 1080, "abyss", 1.00, 920, 150, 312, 280, 324, 420, 1.00, 1.00);
                if (!root.check(
                        c05.dockWidth === c10.dockWidth && c05.dockHeight === c10.dockHeight
                        && c50.dockWidth === c10.dockWidth && c50.dockHeight === c10.dockHeight
                        && c05.leftDockWidth === c10.leftDockWidth && c05.leftDockHeight === c10.leftDockHeight
                        && c05.rightDockWidth === c10.rightDockWidth && c05.rightDockHeight === c10.rightDockHeight
                        && c05.dockY > c50.dockY && c50.dockY > c10.dockY
                        && c05.leftDockX < c50.leftDockX && c50.leftDockX < c10.leftDockX
                        && c05.rightDockX > c50.rightDockX && c50.rightDockX > c10.rightDockX,
                        "All bottom/left/right edit docks maintain 100% constant size and execute pure off-screen edge slides"))
                    return;
                const ssCard = DesktopEditStage.cardForGeometry(1920, 1080, "screenshot", 1.0, 520, 58, 0, 0, 0, 0, 0, 0);
                if (!root.check(ssCard.active && ssCard.dockY >= ssCard.bottom && ssCard.dockWidth === 520 && ssCard.dockHeight === 58,
                        "Take Screenshot external dock mounts outside & below shrunk Desktop Stage"))
                    return;
                const w1536 = DesktopEditStage.cardForGeometry(1536, 960, "widgets", 1.0, 920, 148, 0, 0, 284, 691, 0, 1.0);
                if (!root.check(w1536.active
                        && w1536.dockWidth <= Math.round(w1536.width * 0.80) + 1
                        && w1536.rightDockHeight <= Math.round(w1536.height * 0.80) + 1,
                        "1536x960 Edit Widgets caps bottom width and right height at <= 80% of shrunk Desktop"))
                    return;
                if (!root.check(!win.editCard.active && win.editCard.s === 1 && win.editCard.x === 0 && win.editCard.y === 0,
                        "idle desktop starts at full 1:1 scale"))
                    return;
                GlobalStates.setWidgetEditMode(true);
            } else if (root.step === 1) {
                if (!root.check(!widgetEditorBody.open, "in-field widgetEditorBody stays closed when stage-hosted"))
                    return;
                if (!root.assertStageAndOuterDock("widgets", widgetToolbar))
                    return;
                const gridBtn = root.findByObjectName(widgetToolbar, "widgetDockGridSizeButton");
                if (!root.check(Boolean(gridBtn) && gridBtn.leftPadding === 0 && gridBtn.rightPadding === 0,
                        "widgetDockGridSizeButton centers icon + text with zero asymmetric padding"))
                    return;
                if (!root.check(root.findByObjectName(widgetToolbar, "widgetDockManageButton") === null,
                        "widgetDockManageButton is removed because Manage Widgets Right Dock is always open"))
                    return;
                if (!root.check(Math.abs(win.editCard.x - Math.round((win.width - win.editCard.width) / 2)) <= 1,
                        "Desktop remains horizontally centered in Edit Widgets Mode (x=" + win.editCard.x + ")"))
                    return;
                if (!root.check(stageRightEditDock.visible
                        && mockManager.externalDockParent === stageRightWidgetManagerContainer
                        && stageRightEditDock.x >= win.editCard.right
                        && (win.width - (stageRightEditDock.x + stageRightEditDock.width)) >= DesktopEditStage.edgeClearanceMargin - 1
                        && (win.height - (stageEditDock.y + stageEditDock.height)) >= DesktopEditStage.edgeClearanceMargin - 1,
                        "Manage Widgets Right Dock is always visible outside Desktop with clean screen-edge clearances"))
                    return;
                root.widgetsBottomW = stageEditDock.width;
                root.widgetsBottomH = stageEditDock.height;
                root.widgetsRightW = stageRightEditDock.width;
                root.widgetsRightH = stageRightEditDock.height;
                GlobalStates.setWidgetEditMode(false);
            } else if (root.step === 2) {
                if (!root.check(!win.editCard.active && win.editCard.s === 1 && !stageEditDock.visible && !stageRightEditDock.visible,
                        "exiting widget edit mode restores 1:1 desktop"))
                    return;
                GlobalStates.startAbyssEditing(win.outputName);
            } else if (root.step === 3) {
                const abyssToolbar = root.findByObjectName(stageAbyssDockContainer, "abyssEdgeEditorToolbar");
                const leftPopupsDock = root.findByObjectName(stageLeftAbyssDockContainer, "abyssLeftPopupsDock");
                const rightEdgeDock = root.findByObjectName(stageRightAbyssDockContainer, "abyssRightEdgeDock");
                const editorBody = root.findByObjectName(editor, "abyssEdgeEditorBody");
                if (!root.check(Boolean(editorBody) && !editorBody.open,
                        "in-field AbyssEdgeEditor body stays closed when externally docked"))
                    return;
                if (!root.check(Boolean(abyssToolbar)
                        && stageLeftEditDock.height > 120 && stageRightEditDock.height > 120
                        && stageLeftEditDock.height !== stageRightEditDock.height
                        && stageLeftEditDock.width >= 200 && stageRightEditDock.width >= 200
                        && Math.abs(win.editCard.x - Math.round((win.width - win.editCard.width) / 2)) <= 1
                        && stageLeftEditDock.x >= DesktopEditStage.edgeClearanceMargin - 1
                        && (win.width - (stageRightEditDock.x + stageRightEditDock.width)) >= DesktopEditStage.edgeClearanceMargin - 1
                        && (win.height - (stageEditDock.y + stageEditDock.height)) >= DesktopEditStage.edgeClearanceMargin - 1,
                        "Abyss Layout Left/Right/Bottom docks size flexibly to content with centered Desktop & clean screen-edge clearances"))
                    return;
                if (!root.assertStageAndOuterDock("abyss", abyssToolbar))
                    return;
                if (!root.check(Boolean(leftPopupsDock) && leftPopupsDock.visible && stageLeftEditDock.visible
                        && (stageLeftEditDock.x + stageLeftEditDock.width) <= win.editCard.x + 1,
                        "Abyss Layout Popups dock mounts centered on LEFT outside shrunk Desktop Stage"))
                    return;
                const ipcOutputCombo = root.findByObjectName(leftPopupsDock, "abyssEditorIpcOutput");
                const ipcKindCombo = root.findByObjectName(leftPopupsDock, "abyssEditorIpcKind");
                const ipcEdgeCombo = root.findByObjectName(leftPopupsDock, "abyssIpcEdgeDropdown");
                const ipcAlignCombo = root.findByObjectName(leftPopupsDock, "abyssIpcAlignmentDropdown");
                if (!root.check(Boolean(ipcOutputCombo) && Boolean(ipcKindCombo) && Boolean(ipcEdgeCombo) && Boolean(ipcAlignCombo)
                        && ipcOutputCombo.width > 140 && ipcKindCombo.width > 180
                        && ipcEdgeCombo.width > 180 && ipcAlignCombo.width > 180,
                        "Popups & Panels dropdowns render full-width with readable labels"))
                    return;
                for (const combo of [ipcOutputCombo, ipcKindCombo, ipcEdgeCombo, ipcAlignCombo]) {
                    combo.popup.open();
                    if (!root.check(combo.popup.visible && combo.popup.width >= 150,
                            "Popups & Panels dropdown menu opens cleanly (" + combo.objectName + ")"))
                        return;
                    combo.popup.close();
                }
                if (!root.check(stageEditDock.width > 720 && stageEditDock.width <= Math.round(win.editCard.width * 0.80) + 1,
                        "Abyss Layout bottom dock expands flexibly past legacy 680px up to 80% desktop width (w=" + stageEditDock.width + ")"))
                    return;
                if (!root.check(Boolean(rightEdgeDock) && rightEdgeDock.visible && stageRightEditDock.visible
                        && stageRightEditDock.x >= win.editCard.right - 1,
                        "Abyss Layout Screen Edge dock mounts centered on RIGHT outside shrunk Desktop Stage"))
                    return;
                GlobalStates.abyssEditing = false;
            } else if (root.step === 4) {
                if (!root.check(!win.editCard.active && win.editCard.s === 1,
                        "exiting Abyss edit mode restores 1:1 desktop"))
                    return;
                GlobalStates.dashboardOpen = true;
            } else if (root.step === 5) {
                if (!dashboardBody.contentItem.item || !(dashboardBody.progress > 0.99))
                    return;
                const canvasCtrl = root.findByObjectName(stageDashboardDockContainer, "abyssDashboardEditPopup")?.canvasController ?? null;
                if (!canvasCtrl)
                    return;
                canvasCtrl.beginEditMode();
            } else if (root.step === 6) {
                const dashPopup = root.findByObjectName(stageDashboardDockContainer, "abyssDashboardEditPopup");
                const leftTabsDock = root.findByObjectName(stageLeftDashboardDockContainer, "abyssLeftDashboardTabsDock");
                const rightLayoutDock = root.findByObjectName(stageRightDashboardDockContainer, "abyssRightDashboardLayoutDock");
                if (!root.check(dashboardBody.contentItem.item.bottomControlReserve === 0,
                        "stage-hosted Dashboard uses 0 bottomControlReserve"))
                    return;
                if (!root.assertStageAndOuterDock("dashboard", dashPopup))
                    return;
                if (!root.check(stageEditDock.width >= 320 && stageEditDock.height >= 48
                        && stageEditDock.y >= win.editCard.bottom
                        && stageEditDock.width <= Math.round(win.editCard.width * 0.80) + 1
                        && Math.abs(win.editCard.x - Math.round((win.width - win.editCard.width) / 2)) <= 1,
                        "Edit Dashboard bottom dock sizes flexibly within 80% desktop cap & keeps Desktop centered"))
                    return;
                if (!root.check(Boolean(leftTabsDock) && leftTabsDock.visible && stageLeftEditDock.visible
                        && stageLeftEditDock.width >= 200
                        && stageLeftEditDock.height <= Math.round(win.editCard.height * 0.80) + 1
                        && (stageLeftEditDock.x + stageLeftEditDock.width) <= win.editCard.x + 1,
                        "Edit Dashboard Tabs dock mounts on LEFT outside shrunk Desktop Stage"))
                    return;
                if (!root.check(Boolean(rightLayoutDock) && rightLayoutDock.visible && stageRightEditDock.visible
                        && stageRightEditDock.width >= 200
                        && stageRightEditDock.height <= Math.round(win.editCard.height * 0.80) + 1
                        && stageRightEditDock.x >= win.editCard.right - 1,
                        "Edit Dashboard Layout & Grid dock mounts on RIGHT outside shrunk Desktop Stage"))
                    return;
                dashPopup.canvasController.cancelEditMode();
                GlobalStates.dashboardOpen = false;
            } else if (root.step === 7) {
                if (!root.check(!win.editCard.active && win.editCard.s === 1,
                        "exiting Dashboard edit mode restores 1:1 desktop"))
                    return;
                GlobalStates.settingsOverlayOpen = true;
            } else if (root.step === 8) {
                if (!settingsBody.contentItem.item || !(settingsBody.progress > 0.99))
                    return;
                SettingsLayoutManager.beginEditMode();
            } else if (root.step === 9) {
                const settingsPopup = root.findByObjectName(stageSettingsDockContainer, "abyssSettingsEditPopup");
                if (!root.check(settingsBody.contentItem.item.bottomControlReserve === 0,
                        "stage-hosted Settings uses 0 bottomControlReserve"))
                    return;
                if (!root.assertStageAndOuterDock("settings", settingsPopup))
                    return;
                if (!root.check(stageEditDock.width >= 320 && stageEditDock.height >= 48
                        && stageEditDock.y >= win.editCard.bottom,
                        "Edit Settings bottom dock sizes flexibly outside Desktop Stage"))
                    return;
                SettingsLayoutManager.cancelEditMode();
                GlobalStates.settingsOverlayOpen = false;
            } else if (root.step === 10) {
                if (!root.check(!win.editCard.active && win.editCard.s === 1 && !editStageFrame.visible && !stageEditDock.visible,
                        "exiting Settings edit mode restores 1:1 desktop"))
                    return;
                GlobalStates.wallpaperLauncherOpen = true;
            } else if (root.step === 11) {
                if (!stageWallpaperLoader.item)
                    return;
                if (!root.check(!wallpaperBody.open, "in-field wallpaperBody stays closed when stage-hosted"))
                    return;
                if (!root.assertStageAndOuterDock("wallpaper", stageWallpaperLoader.item))
                    return;
                Config.setNestedValue("abyss.editStage.scale", 0.74);
            } else if (root.step === 12) {
                if (!root.check(win.editCard.s > 0.70 && win.editCard.s <= 0.75,
                        "abyss.editStage.scale dynamically resizes shrunk desktop (s=" + win.editCard.s + ")"))
                    return;
                Config.setNestedValue("abyss.editStage.wallpaperPreview", false);
            } else if (root.step === 13) {
                if (!root.check(!win.editCard.active && win.editCard.s === 1 && !stageEditDock.visible && wallpaperBody.open,
                        "disabling wallpaperPreview falls back to bottom-edge wallpaperBody at 1:1 desktop scale"))
                    return;
                Config.setNestedValue("abyss.editStage.wallpaperPreview", true);
                Config.setNestedValue("abyss.editStage.scale", 0.83);
                GlobalStates.wallpaperLauncherOpen = false;
                Config.setNestedValue("abyss.editStage.enable", false);
            } else if (root.step === 14) {
                GlobalStates.startAbyssEditing(win.outputName);
            } else if (root.step === 15) {
                const editorBody = root.findByObjectName(editor, "abyssEdgeEditorBody");
                if (!root.check(!win.editCard.active && win.editCard.s === 1 && !stageEditDock.visible
                        && Boolean(editorBody) && editorBody.open,
                        "disabling abyss.editStage.enable falls back to bottom-edge AbyssEdgeEditor at 1:1 desktop scale"))
                    return;
                GlobalStates.abyssEditing = false;
                console.info("STAGE_EDIT_PASS");
                Qt.quit();
                return;
            }
            root.step++;
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-stage-edit-") as folder:
    root = Path(folder)
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
        (root / name).symlink_to(REPO / name)
    config = root / "config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy(REPO / "defaults/config.json", config / "config.json")
    (root / "shell.qml").write_text(QML, encoding="utf-8")

    env = dict(
        os.environ,
        QT_QPA_PLATFORM="wayland",
        XDG_CONFIG_HOME=str(root / "config"),
        XDG_STATE_HOME=str(root / "state"),
        XDG_CACHE_HOME=str(root / "cache"),
    )
    for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
        env.pop(key, None)

    result = subprocess.run(
        ["dbus-run-session", "--", "timeout", "25s", "qs", "-p", str(root), "--no-color"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    bad_tokens = (
        "STAGE_EDIT_FAIL",
        "[AbyssEditStageFrame]",
        "ReferenceError:",
        "TypeError:",
        "Unable to assign",
        "is not a type",
    )
    unexpected_loop = any(
        "Binding loop" in line and "AbyssBarModule.qml[73:9]" not in line
        for line in result.stdout.splitlines()
    )
    if result.returncode or "STAGE_EDIT_PASS" not in result.stdout or unexpected_loop or any(tok in result.stdout for tok in bad_tokens):
        print(result.stdout)
        raise SystemExit(1)

print("PASS: Abyss Desktop Edit Stage shrinks desktop + Screen Edges and welds outer customization dock below across all 4 edit modes")
