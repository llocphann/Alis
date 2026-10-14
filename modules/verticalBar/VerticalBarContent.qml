import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs
import qs.services
import qs.modules.common
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.bar as Bar
import qs.modules.bar.weather as BarWeather

Item { // Bar content region
    id: root

    property var screen: root.QsWindow.window?.screen
    property var brightnessMonitor: Brightness.getMonitorForScreen(screen)
    property alias backgroundItem: barBackground
    property bool nativeBlurAllowed: true
    readonly property string nativeBlurTopology: Appearance.blurTopology.unsupported
    readonly property bool nativeBlurActive: Appearance.useCompositorBlur("bar", root.nativeBlurTopology)
        && root.nativeBlurAllowed
        && !root.gameModeMinimal

    property Item barContextMenuSource: null
    property rect barContextMenuRect: Qt.rect(0, 0, 1, 1)

    function openBarContextMenu(clickX, clickY, mouseArea) {
        root.barContextMenuSource = mouseArea
        root.barContextMenuRect = Qt.rect(clickX, clickY, 1, 1)
        barContextMenu.requestOpen()
    }

    Bar.BarContextMenu {
        id: barContextMenu
        anchorItem: root.barContextMenuSource ?? root
        anchorRect: root.barContextMenuRect
        anchorHovered: root.barContextMenuSource?.hovered ?? false
        closeOnHoverLost: true

        model: [
            {
                iconName: "browse_activity",
                monochromeIcon: true,
                text: Translation.tr("Mission Center"),
                action: () => {
                    Session.launchTaskManager()
                },
            },
            { type: "separator" },
            {
                iconName: "settings",
                monochromeIcon: true,
                text: Translation.tr("Settings"),
                action: () => {
                    Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"])
                },
            },
        ]
    }
    readonly property color separatorColor: Appearance.colors.colOutlineVariant
    readonly property bool gameModeMinimal: Appearance.gameModeMinimal

    // Bar Settings owns one canonical module-visibility object for every edge.
    // Keep vertical presentation compact, but never fork visibility state by
    // orientation again (the old Alis vertical bar only listened to taskbar).
    function moduleEnabled(name: string, fallback: bool): bool {
        const value = Config.options?.bar?.modules?.[name]
        return value === undefined || value === null ? fallback : Boolean(value)
    }

    readonly property bool leftSidebarButtonEnabled: root.moduleEnabled("leftSidebarButton", true)
    readonly property bool distroIconEnabled: root.moduleEnabled("distroIcon", true)
    readonly property bool activeWindowEnabled: root.moduleEnabled("activeWindow", true)
        && !root.taskbarEnabled
    readonly property bool taskbarEnabled: root.moduleEnabled("taskbar", false)
    readonly property bool resourcesEnabled: root.moduleEnabled("resources", false)
    readonly property bool mediaEnabled: root.moduleEnabled("media", true)
    readonly property bool workspacesEnabled: root.moduleEnabled("workspaces", true)
    readonly property bool clockEnabled: root.moduleEnabled("clock", true)
    readonly property bool utilButtonsEnabled: root.moduleEnabled("utilButtons", false)
    readonly property bool batteryEnabled: root.moduleEnabled("battery", true)
    readonly property bool weatherEnabled: root.moduleEnabled("weather", true)
        && (Config.options?.bar?.weather?.enable ?? false)
    readonly property bool sysTrayEnabled: root.moduleEnabled("sysTray", true)
    readonly property bool rightSidebarButtonEnabled: root.moduleEnabled("rightSidebarButton", true)

    readonly property real edgeInset: Math.max(4, Appearance.rounding.screenRounding)
    readonly property real moduleGap: Math.max(2, Math.round(4 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real zoneGapNominal: Math.max(root.moduleGap + 2, Math.round(8 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real zoneGapMinimum: Math.max(2, Math.round(4 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real pivotGapNominal: Math.max(root.moduleGap + 1, Math.round(6 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))
    readonly property real pivotGapMinimum: Math.max(2, Math.round(3 * Appearance.fontSizeScale * Appearance.sizes.barModuleScale))

    readonly property real _spacerMinimumHeight: Math.max(0,
        Config.options?.bar?.verticalLayout?.spacerHeight ?? 0) * Appearance.fontSizeScale * Appearance.sizes.barModuleScale
    readonly property string _spacerMode: Config.options?.bar?.verticalLayout?.spacerMode ?? "auto"

    function _verticalZone(name, fallback) {
        const a = Config.options?.bar?.verticalLayout?.[name]
        return (a && a.length >= 0) ? a : fallback
    }
    readonly property var _topIds: root._verticalZone("top", ["leftSidebarButton", "distroIcon", "activeWindow", "spacer"])
    readonly property var _centerTopIds: root._verticalZone("centerTop", ["resources", "media"])
    readonly property var _centerIds: root._verticalZone("center", ["workspaces"]).filter(id => id === "workspaces")
    readonly property var _centerBottomIds: root._verticalZone("centerBottom", ["clock", "utilButtons", "battery"])
    readonly property var _bottomIds: root._verticalZone("bottom", ["weather", "tray", "timer", "shellUpdate", "spacer", "rightSidebarButton"])

    function _zoneContains(ids, id) { return Array.isArray(ids) && ids.indexOf(id) >= 0 }
    function _edgeZone(zone) { return zone === "top" || zone === "bottom" }
    function _fillHeight(id, zone) {
        if (id !== "spacer") return false
        if (root._spacerMode === "fixed") return false
        if (root._spacerMode === "fill") return true
        return root._edgeZone(zone)
    }
    function _moduleShown(id, zone) {
        if (id === "spacer") return root._fillHeight(id, zone) || root._spacerMinimumHeight > 0
        if (id === "leftSidebarButton") return root.leftSidebarButtonEnabled
        if (id === "distroIcon") return root.distroIconEnabled
        if (id === "activeWindow") return root.activeWindowEnabled
        if (id === "taskbar") return root.taskbarEnabled
        if (id === "resources") return root.resourcesEnabled
        if (id === "media") return root.mediaEnabled
        if (id === "workspaces") return root.workspacesEnabled
        if (id === "clock") return root.clockEnabled
        if (id === "utilButtons") return root.utilButtonsEnabled
        if (id === "battery") return root.batteryEnabled && Battery.available
        if (id === "rightSidebarButton") return root.rightSidebarButtonEnabled
        if (id === "tray") return root.sysTrayEnabled
        if (id === "weather") return root.weatherEnabled
        return id === "timer" || id === "shellUpdate"
    }

    readonly property bool _topZoneGapNeeded: topZone.implicitHeight > 0 && centerTopZone.implicitHeight > 0
    readonly property bool _bottomZoneGapNeeded: centerBottomZone.implicitHeight > 0 && bottomZone.implicitHeight > 0
    readonly property bool _topPivotGapNeeded: centerTopZone.implicitHeight > 0 && pivotZone.implicitHeight > 0
    readonly property bool _bottomPivotGapNeeded: centerBottomZone.implicitHeight > 0 && pivotZone.implicitHeight > 0
    readonly property real topAvailableHeight: Math.max(0, root.height / 2 - pivotZone.implicitHeight / 2)
    readonly property real bottomAvailableHeight: root.topAvailableHeight
    readonly property real topNaturalNeed: topZone.implicitHeight + centerTopZone.implicitHeight
        + (root._topZoneGapNeeded ? root.zoneGapNominal : 0)
        + (root._topPivotGapNeeded ? root.pivotGapNominal : 0)
    readonly property real bottomNaturalNeed: centerBottomZone.implicitHeight + bottomZone.implicitHeight
        + (root._bottomZoneGapNeeded ? root.zoneGapNominal : 0)
        + (root._bottomPivotGapNeeded ? root.pivotGapNominal : 0)
    readonly property real topPressure: Math.max(0, root.topNaturalNeed - root.topAvailableHeight)
    readonly property real bottomPressure: Math.max(0, root.bottomNaturalNeed - root.bottomAvailableHeight)
    readonly property real topGapCompressionCapacity:
        (root._topZoneGapNeeded ? root.zoneGapNominal - root.zoneGapMinimum : 0)
        + (root._topPivotGapNeeded ? root.pivotGapNominal - root.pivotGapMinimum : 0)
    readonly property real bottomGapCompressionCapacity:
        (root._bottomZoneGapNeeded ? root.zoneGapNominal - root.zoneGapMinimum : 0)
        + (root._bottomPivotGapNeeded ? root.pivotGapNominal - root.pivotGapMinimum : 0)
    readonly property real topGapCompression: root.topGapCompressionCapacity > 0
        ? Math.min(1, root.topPressure / root.topGapCompressionCapacity) : 0
    readonly property real bottomGapCompression: root.bottomGapCompressionCapacity > 0
        ? Math.min(1, root.bottomPressure / root.bottomGapCompressionCapacity) : 0
    readonly property real topZoneGap: root._topZoneGapNeeded
        ? root.zoneGapNominal - (root.zoneGapNominal - root.zoneGapMinimum) * root.topGapCompression : 0
    readonly property real bottomZoneGap: root._bottomZoneGapNeeded
        ? root.zoneGapNominal - (root.zoneGapNominal - root.zoneGapMinimum) * root.bottomGapCompression : 0
    readonly property real topPivotGap: root._topPivotGapNeeded
        ? root.pivotGapNominal - (root.pivotGapNominal - root.pivotGapMinimum) * root.topGapCompression : 0
    readonly property real bottomPivotGap: root._bottomPivotGapNeeded
        ? root.pivotGapNominal - (root.pivotGapNominal - root.pivotGapMinimum) * root.bottomGapCompression : 0

    readonly property real _utilityWeightTop:
        root._zoneContains(root._topIds, "utilButtons") || root._zoneContains(root._centerTopIds, "utilButtons") ? 1 : 0
    readonly property real _utilityWeightBottom:
        root._zoneContains(root._centerBottomIds, "utilButtons") || root._zoneContains(root._bottomIds, "utilButtons") ? 1 : 0
    readonly property bool _utilityPackingEnabled: root.utilButtonsEnabled
        && (root._utilityWeightTop > 0 || root._utilityWeightBottom > 0)
    property bool verticalUtilitiesCompact: false
    readonly property real utilityExpansionDelta: Math.max(0,
        verticalUtilMeasure.expandedMainAxisLength - verticalUtilMeasure.compactMainAxisLength)
    readonly property real topExpandedPressure: root.topPressure
        + (root.verticalUtilitiesCompact ? root.utilityExpansionDelta * root._utilityWeightTop : 0)
    readonly property real bottomExpandedPressure: root.bottomPressure
        + (root.verticalUtilitiesCompact ? root.utilityExpansionDelta * root._utilityWeightBottom : 0)

    function _scheduleUtilityPacking(): void { utilityPackingTimer.restart() }
    function _reconcileUtilityPacking(): void {
        if (!root._utilityPackingEnabled) {
            if (root.verticalUtilitiesCompact) root.verticalUtilitiesCompact = false
            return
        }
        const topNeeds = root._utilityWeightTop > 0
            && root.topExpandedPressure > root.topGapCompressionCapacity + 0.5
        const bottomNeeds = root._utilityWeightBottom > 0
            && root.bottomExpandedPressure > root.bottomGapCompressionCapacity + 0.5
        const needs = topNeeds || bottomNeeds
        if (!root.verticalUtilitiesCompact) {
            if (needs) root.verticalUtilitiesCompact = true
            return
        }
        const topRelaxed = root._utilityWeightTop <= 0
            || root.topExpandedPressure <= Math.max(0, root.topGapCompressionCapacity - 3)
        const bottomRelaxed = root._utilityWeightBottom <= 0
            || root.bottomExpandedPressure <= Math.max(0, root.bottomGapCompressionCapacity - 3)
        if (!needs && topRelaxed && bottomRelaxed) root.verticalUtilitiesCompact = false
    }
    onHeightChanged: root._scheduleUtilityPacking()
    onTopPressureChanged: root._scheduleUtilityPacking()
    onBottomPressureChanged: root._scheduleUtilityPacking()
    onUtilityExpansionDeltaChanged: root._scheduleUtilityPacking()

    Timer { id: utilityPackingTimer; interval: 16; repeat: false; onTriggered: root._reconcileUtilityPacking() }
    Bar.UtilButtons { id: verticalUtilMeasure; visible: false; enabled: false; vertical: true; compactRequested: false }

    component HorizontalBarSeparator: Rectangle {
        Layout.leftMargin: Appearance.sizes.baseBarHeight / 3
        Layout.rightMargin: Appearance.sizes.baseBarHeight / 3
        Layout.fillWidth: true
        implicitHeight: 1
        color: root.separatorColor
    }

    component VerticalClockModule: Item {
        id: clockModule
        implicitWidth: Appearance.sizes.verticalBarWidth
        implicitHeight: clockStack.implicitHeight

        ColumnLayout {
            id: clockStack
            width: parent.width
            spacing: 12 * Appearance.sizes.barModuleScale

            VerticalClockWidget {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }

            Rectangle {
                Layout.leftMargin: Appearance.sizes.baseBarHeight / 3
                Layout.rightMargin: Appearance.sizes.baseBarHeight / 3
                Layout.fillWidth: true
                implicitHeight: 1
                color: Appearance.colors.colOutlineVariant
            }

            VerticalDateWidget {
                Layout.fillWidth: true
                Layout.fillHeight: false
            }
        }

        MouseArea {
            id: clockHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        Bar.ClockCalendarPopup {
            hoverTarget: clockHoverArea
        }
    }

    component VerticalModuleCell: Item {
        id: moduleCell
        required property string modelData
        property string zoneName: ""
        readonly property bool moduleEnabled:
            root._moduleShown(moduleCell.modelData, moduleCell.zoneName)

        Layout.fillWidth: true
        Layout.fillHeight: moduleCell.visible
            && root._fillHeight(moduleCell.modelData, moduleCell.zoneName)
        implicitWidth: Appearance.sizes.baseVerticalBarWidth
        implicitHeight: moduleCell.moduleEnabled ? moduleLoader.implicitHeight : 0
        visible: moduleCell.moduleEnabled
            && (root._fillHeight(moduleCell.modelData, moduleCell.zoneName)
                || moduleCell.implicitHeight > 0)

        Loader {
            id: moduleLoader
            width: parent.width
            anchors.horizontalCenter: parent.horizontalCenter
            active: moduleCell.moduleEnabled
            sourceComponent: root._allComponents[moduleCell.modelData] ?? null
        }
    }

    component VerticalZone: Item {
        id: zoneRoot
        required property string zoneName
        required property var ids
        readonly property bool edgeZone: zoneName === "top" || zoneName === "bottom"
        readonly property real edgePadding: edgeZone ? root.edgeInset : 0
        implicitWidth: Appearance.sizes.verticalBarWidth
        implicitHeight: zoneGroup.empty ? 0 : zoneGroup.implicitHeight + edgePadding
        Bar.BarGroup {
            id: zoneGroup
            anchors {
                left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom
                topMargin: zoneRoot.zoneName === "top" ? zoneRoot.edgePadding : 0
                bottomMargin: zoneRoot.zoneName === "bottom" ? zoneRoot.edgePadding : 0
            }
            vertical: true
            bare: zoneRoot.edgeZone
            padding: zoneRoot.edgeZone ? 0 : 6 * Appearance.sizes.barModuleScale
            moduleSpacing: root.moduleGap
            Repeater {
                model: zoneRoot.ids
                delegate: VerticalModuleCell {
                    zoneName: zoneRoot.zoneName
                }
            }
        }
    }

    readonly property var _allComponents: ({
        "leftSidebarButton": leftSidebarButtonComponent,
        "distroIcon": distroIconComponent,
        "activeWindow": activeWindowComponent,
        "taskbar": taskbarComponent,
        "resources": resourcesComponent,
        "media": mediaComponent,
        "workspaces": workspacesComponent,
        "clock": clockComponent,
        "utilButtons": utilButtonsComponent,
        "battery": batteryComponent,
        "rightSidebarButton": rightSidebarButtonComponent,
        "tray": trayComponent,
        "timer": timerComponent,
        "shellUpdate": shellUpdateComponent,
        "weather": weatherComponent,
        "spacer": spacerComponent,
    })

    Component {
        id: leftSidebarButtonComponent
        Bar.LeftSidebarButton {
            implicitWidth: 34 * Appearance.sizes.barModuleScale
            colBackground: buttonHovered ? Appearance.colors.colLayer1Hover
                : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
        }
    }
    Component {
        id: distroIconComponent
        Bar.DistroIcon {}
    }
    Component {
        id: activeWindowComponent
        Item {
            id: activeWindowCompact
            implicitWidth: 34 * Appearance.sizes.barModuleScale; implicitHeight: 34 * Appearance.sizes.barModuleScale
            readonly property var activeWindow: ToplevelManager.activeToplevel
            SmartAppIcon {
                anchors.centerIn: parent
                icon: String(activeWindowCompact.activeWindow?.appId ?? "")
                fallback: "window"; iconSize: Math.round(20 * Appearance.sizes.barModuleScale)
            }
            HoverHandler {}
            StyledToolTip {
                text: {
                    const appName = String(activeWindowCompact.activeWindow?.appId ?? Translation.tr("Desktop"))
                    const title = String(activeWindowCompact.activeWindow?.title ?? "")
                    return title.length > 0 && title !== appName ? appName + "\n" + title : appName
                }
            }
        }
    }
    Component {
        id: taskbarComponent
        Bar.BarTaskbar { vertical: true; parentWindow: root.QsWindow.window; maximumHeight: Math.max(80, root.height * 0.3) }
    }
    Component { id: resourcesComponent; Resources {} }
    Component { id: mediaComponent; VerticalMedia {} }
    Component {
        id: workspacesComponent
        Bar.Workspaces {
            vertical: true
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onPressed: event => { if (event.button === Qt.RightButton) GlobalStates.toggleOverview(root.screen?.name ?? "") }
            }
        }
    }
    Component { id: clockComponent; VerticalClockModule {} }
    Component { id: utilButtonsComponent; Bar.UtilButtons { vertical: true; compactRequested: root.verticalUtilitiesCompact } }
    Component { id: batteryComponent; Bar.BatteryIndicator {} }
    Component { id: trayComponent; Bar.SysTray { vertical: true; invertSide: Config.options?.bar?.bottom ?? false } }
    Component { id: timerComponent; Bar.TimerIndicator { vertical: true } }
    Component { id: shellUpdateComponent; Bar.ShellUpdateIndicator { vertical: true } }
    Component {
        id: weatherComponent
        BarWeather.WeatherBar {
            vertical: true
        }
    }
    Component {
        id: spacerComponent
        Item { implicitWidth: Appearance.sizes.baseVerticalBarWidth; implicitHeight: root._spacerMinimumHeight }
    }
    Component {
        id: rightSidebarButtonComponent
        RippleButton {
            id: rightSidebarButton
            Accessible.name: Translation.tr("Toggle right sidebar")
            implicitWidth: 34 * Appearance.sizes.barModuleScale
            implicitHeight: 34 * Appearance.sizes.barModuleScale
            buttonRadius: Appearance.rounding.full
            colBackground: buttonHovered ? Appearance.colors.colLayer1Hover
                : ColorUtils.transparentize(Appearance.colors.colLayer1Hover, 1)
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive
            toggled: GlobalStates.sidebarRightOpen
                && GlobalStates.sidebarRightPresentationOutput === (root.screen?.name ?? "")
            onPressed: GlobalStates.toggleSidebarRight(root.screen?.name ?? "")

            MaterialSymbol {
                anchors.centerIn: parent
                text: "right_panel_open"
                iconSize: Math.round(20 * Appearance.sizes.barModuleScale)
                color: rightSidebarButton.toggled
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer0
            }
        }
    }

    // The physical Screen Edge's single inverted frame owns the inward
    // shadow, including this Bar's corners. No local duplicate renderer.

    // Background
    Rectangle {
        id: barBackground
        anchors {
            fill: parent
            margins: 0
        }
        // Hug background is structural connected chrome. Fullscreen/GameMode
        // may disable effects, but the native Bar surface stays mapped. Niri
        // covers the Top-layer surface during fullscreen and reveals it on exit.
        visible: true
        color: Appearance.colors.colLayer0
        radius: 0
        // No Behavior on the base radius — the per-corner radii below own the
        // corners, and a second interceptor on radius is unsupported (Qt warn).

        topLeftRadius: radius
        bottomLeftRadius: radius
        topRightRadius: radius
        bottomRightRadius: radius
        Behavior on topRightRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on topLeftRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        border.width: 0
        Behavior on border.width {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        border.color: Appearance.colors.colLayer0Border
        Behavior on border.color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        clip: true

    }

    VerticalZone {
        id: pivotZone
        anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter }
        zoneName: "center"
        ids: root._centerIds
        z: 3
    }

    Flickable {
        id: upperHalf
        anchors {
            left: parent.left; right: parent.right; top: parent.top
            bottom: pivotZone.top; bottomMargin: root.topPivotGap
        }
        contentWidth: width
        contentHeight: Math.max(height, upperLayout.implicitHeight)
        clip: true
        interactive: contentHeight > height + 0.5
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: upperLayout
            width: upperHalf.width
            height: upperHalf.contentHeight
            spacing: root.topZoneGap
            FocusedScrollMouseArea {
                id: barTopSectionMouseArea
                Layout.fillWidth: true; Layout.fillHeight: true
                implicitHeight: topZone.implicitHeight
                implicitWidth: Appearance.sizes.baseVerticalBarWidth
                onScrollDown: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness - 0.05)
                onScrollUp: root.brightnessMonitor.setBrightness(root.brightnessMonitor.brightness + 0.05)
                onMovedAway: GlobalStates.osdBrightnessOpen = false
                onPressed: event => {
                    if (event.button === Qt.LeftButton) GlobalStates.toggleSidebarLeft(root.screen?.name ?? "")
                    else if (event.button === Qt.RightButton) root.openBarContextMenu(event.x, event.y, barTopSectionMouseArea)
                }
                VerticalZone { id: topZone; anchors.fill: parent; zoneName: "top"; ids: root._topIds }
            }
            VerticalZone { id: centerTopZone; Layout.fillWidth: true; zoneName: "centerTop"; ids: root._centerTopIds }
        }
    }

    Flickable {
        id: lowerHalf
        anchors {
            left: parent.left; right: parent.right
            top: pivotZone.bottom; topMargin: root.bottomPivotGap; bottom: parent.bottom
        }
        contentWidth: width
        contentHeight: Math.max(height, lowerLayout.implicitHeight)
        clip: true
        interactive: contentHeight > height + 0.5
        boundsBehavior: Flickable.StopAtBounds
        ColumnLayout {
            id: lowerLayout
            width: lowerHalf.width
            height: lowerHalf.contentHeight
            spacing: root.bottomZoneGap
            VerticalZone { id: centerBottomZone; Layout.fillWidth: true; zoneName: "centerBottom"; ids: root._centerBottomIds }
            FocusedScrollMouseArea {
                id: barBottomSectionMouseArea
                Layout.fillWidth: true; Layout.fillHeight: true
                implicitHeight: bottomZone.implicitHeight
                implicitWidth: Appearance.sizes.baseVerticalBarWidth
                onScrollDown: Audio.decrementVolume()
                onScrollUp: Audio.incrementVolume()
                onMovedAway: GlobalStates.osdVolumeOpen = false
                onPressed: event => {
                    if (event.button === Qt.LeftButton) GlobalStates.toggleSidebarRight(root.screen?.name ?? "")
                    else if (event.button === Qt.RightButton) root.openBarContextMenu(event.x, event.y, barBottomSectionMouseArea)
                }
                VerticalZone { id: bottomZone; anchors.fill: parent; zoneName: "bottom"; ids: root._bottomIds }
            }
        }
    }

}
