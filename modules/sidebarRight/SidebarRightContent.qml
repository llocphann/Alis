import qs
import qs.services
import qs.modules.common
import qs.modules.common.perimeter
import qs.modules.common.models
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Qt5Compat.GraphicalEffects as GE

import qs.modules.sidebarRight.quickToggles
import qs.modules.sidebarRight.quickToggles.classicStyle

import qs.modules.sidebarRight.bluetoothDevices
import qs.modules.sidebarRight.events
import qs.modules.sidebarRight.hotspot
import qs.modules.sidebarRight.nightLight
import qs.modules.sidebarRight.volumeMixer
import qs.modules.sidebarRight.wifiNetworks

Item {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property int sidebarWidth: Appearance.sizes.sidebarWidth
    property int sidebarPadding: 10
    property string settingsQmlPath: Quickshell.shellPath("settings.qml")
    property int screenWidth: 1920
    property int screenHeight: 1080
    property var panelScreen: null
    property real panelScreenY: Appearance.sizes.hyprlandGapsOut
    property bool externalConnectedSurface: false
    readonly property color connectedSurfaceColor:
        sidebarRightBackground.cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0
    readonly property real connectedSurfaceRadius: sidebarRightBackground.radius
    property bool panelVisible: false
    property bool geometryPreviewActive: false
    property string attachedEdge: "right"
    property bool showAudioOutputDialog: false
    property bool showAudioInputDialog: false
    property bool showBluetoothDialog: false
    property bool showEventsDialog: false
    property bool showHotspotDialog: false
    property bool showNightLightDialog: false
    property bool showWifiDialog: false
    property bool editMode: false

    readonly property bool anyDialogOpen: showAudioOutputDialog || showAudioInputDialog
        || showBluetoothDialog || showEventsDialog || showHotspotDialog
        || showNightLightDialog || showWifiDialog
    readonly property real preferredContentHeight: SidebarGeometry.rightFitHeight(
        Math.max(0, root.screenHeight - Appearance.sizes.hyprlandGapsOut * 2),
        sidebarRightBackground.naturalCompactHeight,
        root.bottomGroupCollapsed)
    readonly property real minimumUsefulHeight: Math.max(320,
        root.screenHeight * (root.bottomGroupCollapsed
            ? SidebarGeometry.rightFitCollapsedMinRatio
            : SidebarGeometry.rightFitExpandedMinRatio))
    readonly property real minimumUsefulWidth: 320
    readonly property real maximumUsefulWidth: 900

    // Events dialog target: an event object to edit, a Date for a new event
    // prefilled to that day, or null for a blank new event.
    property var eventsDialogEditEvent: null

    // Debounce timers to prevent accidental double-clicks
    property bool reloadButtonEnabled: true
    property bool settingsButtonEnabled: true

    // ─── System header actions ───────────────────────────────────────
    // Owned here so both header styles (classic pills, profile card) drive
    // the same debounce state instead of each keeping its own copy.
    function requestReload(): void {
        if (!root.reloadButtonEnabled) {
            _log("[SidebarRight] Reload button still on cooldown, ignoring click");
            return;
        }

        _log("[SidebarRight] Reload button clicked");
        root.reloadButtonEnabled = false;
        reloadButtonCooldown.restart();

        if (CompositorService.isHyprland) {
            Hyprland.dispatch("reload");
        } else if (CompositorService.isNiri) {
            Quickshell.execDetached(["/usr/bin/niri", "msg", "action", "load-config-file"]);
        }
        Quickshell.execDetached(["/usr/bin/bash", Quickshell.shellPath("scripts/restart-shell.sh")]);
    }

    function openSettings(): void {
        if (!root.settingsButtonEnabled) {
            _log("[SidebarRight] Settings button still on cooldown, ignoring click");
            return;
        }

        _log("[SidebarRight] Settings button clicked");
        root.settingsButtonEnabled = false;
        settingsButtonCooldown.restart();

        if (CompositorService.isNiri) {
            const wins = NiriService.windows || []
            _log("[SidebarRight] Checking for existing settings window among", wins.length, "windows");
            for (let i = 0; i < wins.length; i++) {
                const w = wins[i]
                if (w.title === "alis Settings" && w.app_id === "org.quickshell") {
                    _log("[SidebarRight] Found existing settings window, focusing it");
                    GlobalStates.sidebarRightOpen = false;
                    Qt.callLater(() => {
                        NiriService.focusWindow(w.id)
                    })
                    return
                }
            }
            _log("[SidebarRight] No existing settings window found");
        }

        _log("[SidebarRight] Opening new settings window via IPC");
        GlobalStates.sidebarRightOpen = false;
        Qt.callLater(() => {
            Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"]);
        })
    }

    Timer {
        id: reloadButtonCooldown
        interval: 500
        onTriggered: {
            root.reloadButtonEnabled = true;
            _log("[SidebarRight] Reload button cooldown finished");
        }
    }

    Timer {
        id: settingsButtonCooldown
        interval: 500
        onTriggered: {
            root.settingsButtonEnabled = true;
            _log("[SidebarRight] Settings button cooldown finished");
        }
    }

    // ─── Modular sections (sidebar.right.sectionOrder) ───────────────
    // Sanitized: unknown ids dropped, missing ids appended in default order,
    // so a stale or hand-edited config can never blank the sidebar.
    readonly property string headerStyle: Config.options?.sidebar?.right?.headerStyle ?? "profile"
    readonly property var _sectionDefaultOrder: ["system", "sliders", "toggles", "widgets"]
    readonly property var sectionOrder: {
        const def = root._sectionDefaultOrder
        const saved = Config.options?.sidebar?.right?.sectionOrder ?? def
        const result = []
        for (let i = 0; i < saved.length; i++)
            if (def.includes(saved[i]) && !result.includes(saved[i])) result.push(saved[i])
        for (let i = 0; i < def.length; i++)
            if (!result.includes(def[i])) result.push(def[i])
        return result
    }
    // Loaded BottomWidgetGroup instance (section delegates load lazily).
    // Its collapse state participates in the parent's elastic layout instead
    // of being treated as an isolated visual detail.
    property var bottomWidgetGroupItem: null
    readonly property bool bottomGroupCollapsed: bottomWidgetGroupItem?.collapsed ?? false

    // ─── Section drag-reorder (modular sidebar phase 2) ──────────────
    // Same mechanics as DraggableWidgetContainer: cache heights, displace
    // neighbours live, write the new order once on drop.
    property bool sectionEditMode: false
    property int sectionDragIndex: -1
    property int sectionHoverIndex: -1
    property real sectionDragStartY: 0
    property real sectionDragCurrentY: 0
    property var _sectionHeights: []

    function _cacheSectionHeights(): void {
        const heights = []
        for (let i = 0; i < sectionRepeater.count; i++) {
            const item = sectionRepeater.itemAt(i)
            heights.push(item && item.visible ? item.height : 0)
        }
        _sectionHeights = heights
    }

    function getSectionDisplacementY(itemIndex: int): real {
        if (sectionDragIndex < 0 || sectionHoverIndex < 0) return 0
        if (itemIndex === sectionDragIndex) return 0
        if (sectionDragIndex < sectionHoverIndex) {
            if (itemIndex > sectionDragIndex && itemIndex <= sectionHoverIndex)
                return -((_sectionHeights[sectionDragIndex] ?? 0) + contentColumn.spacing)
        } else if (sectionDragIndex > sectionHoverIndex) {
            if (itemIndex >= sectionHoverIndex && itemIndex < sectionDragIndex)
                return (_sectionHeights[sectionDragIndex] ?? 0) + contentColumn.spacing
        }
        return 0
    }

    function getSectionDragFollowY(): real {
        if (sectionDragIndex < 0) return 0
        return sectionDragCurrentY - sectionDragStartY
    }

    function moveSection(fromIdx: int, toIdx: int): void {
        if (fromIdx === toIdx || fromIdx < 0 || toIdx < 0) return
        const newOrder = [...root.sectionOrder]
        const moved = newOrder.splice(fromIdx, 1)[0]
        newOrder.splice(toIdx, 0, moved)
        Config.setNestedValue("sidebar.right.sectionOrder", newOrder)
    }

    function startSectionDrag(index: int, mouseY: real): void {
        _cacheSectionHeights()
        sectionDragIndex = index
        sectionHoverIndex = index
        sectionDragStartY = mouseY
        sectionDragCurrentY = mouseY
    }

    function updateSectionDrag(mouseY: real): void {
        if (sectionDragIndex < 0) return
        sectionDragCurrentY = mouseY
        let lastVisibleIndex = sectionDragIndex
        for (let i = 0; i < sectionRepeater.count; i++) {
            const item = sectionRepeater.itemAt(i)
            if (!item || !item.visible) continue
            lastVisibleIndex = i
            if (mouseY < item.y + item.height / 2) {
                sectionHoverIndex = i
                return
            }
        }
        sectionHoverIndex = lastVisibleIndex
    }

    function endSectionDrag(): void {
        if (sectionDragIndex >= 0 && sectionHoverIndex >= 0 && sectionDragIndex !== sectionHoverIndex)
            moveSection(sectionDragIndex, sectionHoverIndex)
        sectionDragIndex = -1
        sectionHoverIndex = -1
        sectionDragStartY = 0
        sectionDragCurrentY = 0
        _sectionHeights = []
    }

    function cancelSectionDrag(): void {
        sectionDragIndex = -1
        sectionHoverIndex = -1
        sectionDragStartY = 0
        sectionDragCurrentY = 0
        _sectionHeights = []
    }

    function focusActiveItem() {
        if (bottomWidgetGroupItem && bottomWidgetGroupItem.focusActiveItem) {
            bottomWidgetGroupItem.focusActiveItem()
        }
    }

    Connections {
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (!GlobalStates.sidebarRightOpen) {
                root.sectionEditMode = false;
                root.cancelSectionDrag();
                root.showWifiDialog = false;
                root.showBluetoothDialog = false;
                root.showEventsDialog = false;
                root.showAudioOutputDialog = false;
                root.showAudioInputDialog = false;
                root.showNightLightDialog = false;
                root.showHotspotDialog = false;
                root.eventsDialogEditEvent = null;
            }
        }
        function onRequestWifiDialogChanged() {
            if (GlobalStates.requestWifiDialog) {
                GlobalStates.requestWifiDialog = false
                if (!GlobalStates.sidebarRightOpen)
                    GlobalStates.openSidebarRight(GlobalStates.sidebarLeftTargetOutput)
                root.showWifiDialog = true
            }
        }
        function onRequestBluetoothDialogChanged() {
            if (GlobalStates.requestBluetoothDialog) {
                GlobalStates.requestBluetoothDialog = false
                if (!GlobalStates.sidebarRightOpen)
                    GlobalStates.openSidebarRight(GlobalStates.sidebarLeftTargetOutput)
                root.showBluetoothDialog = true
            }
        }
    }

    implicitHeight: sidebarRightBackground.implicitHeight
    implicitWidth: sidebarRightBackground.implicitWidth

    // ── Staggered section entrance (first instantiation only) ──────────────────
    property int _entranceCascade: -1
    property bool _cascadeCompleted: false

    Timer {
        id: _entranceCascadeTimer
        interval: 50
        repeat: true
        onTriggered: {
            if (root._entranceCascade < 5) root._entranceCascade++
            else { stop(); root._cascadeCompleted = true }
        }
    }

    Component.onCompleted: {
        if (GlobalStates.sidebarRightOpen) {
            _entranceCascadeTimer.start()
        } else {
            // Content pre-loaded while sidebar closed — skip cascade
            root._entranceCascade = 99
            root._cascadeCompleted = true
        }
    }

    Connections {
        id: _cascadeConnections
        target: GlobalStates
        function onSidebarRightOpenChanged() {
            if (GlobalStates.sidebarRightOpen && !root._cascadeCompleted) {
                root._entranceCascade = -1
                _entranceCascadeTimer.start()
            }
        }
    }

    StyledRectangularShadow {
        target: sidebarRightBackground
        radius: sidebarRightBackground.radius
        blur: Math.max(0, Math.min(32,
            Math.round(Config.options?.appearance?.screenEdge?.shadow?.size ?? 15)))
        spread: 0
        offset: Qt.vector2d(0, 0)
        color: ColorUtils.applyAlpha(Appearance.colors.colShadow,
            Math.max(0, Math.min(1.0,
                Number(Config.options?.appearance?.screenEdge?.shadow?.opacity ?? 0.70))))
        visible: root.panelVisible && !root.externalConnectedSurface
            && (Config.options?.appearance?.screenEdge?.shadow?.enabled ?? true)
            && !Appearance.gameModeMinimal
        joinLeft: root.attachedEdge === "left"
        joinRight: root.attachedEdge === "right"
    }

    RicelinSurface {
        anchors.fill: sidebarRightBackground
        visible: sidebarRightBackground.islandStyle
        radius: sidebarRightBackground.radius
        glassEnabled: true
        screen: root.panelScreen ?? root.QsWindow?.window?.screen ?? null
        glassScreenX: root.screenWidth - sidebarRightBackground.width
            - Appearance.sizes.hyprlandGapsOut
        glassScreenY: root.panelScreenY
        glassScreenWidth: root.screenWidth
        glassScreenHeight: root.screenHeight
    }

    Rectangle {
        id: sidebarRightBackground

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        readonly property real naturalCompactHeight: contentColumn.implicitHeight
            + root.sidebarPadding * 2
        height: parent.height
        Behavior on height {
            enabled: Appearance.animationsEnabled && root.panelVisible
                && !root.geometryPreviewActive
            NumberAnimation { duration: Appearance.animation.elementResize.duration; easing.type: Appearance.animation.elementResize.type; easing.bezierCurve: Appearance.animation.elementResize.bezierCurve }
        }
        // Clamp >= 0: preload parent.height is 0 here, raw subtraction went negative and froze layout.
        implicitHeight: Math.max(0, parent.height - Appearance.sizes.hyprlandGapsOut * 2)
        implicitWidth: sidebarWidth - Appearance.sizes.hyprlandGapsOut * 2
        property bool cardStyle: Config.options?.sidebar?.cardStyle ?? false
        // Ricelin island mode remains an explicit supported sidebar skin;
        // otherwise the sidebar uses the canonical Material surface.
        readonly property string surfaceDialect: Appearance.surfaceDialectFor(
            (Config.options?.sidebar?.style ?? "panel") === "island" ? "island" : "")
        readonly property bool islandStyle: surfaceDialect === "island"
        readonly property bool gameModeMinimal: Appearance.gameModeMinimal

        color: root.externalConnectedSurface
            ? "transparent"
            : (gameModeMinimal || islandStyle) ? "transparent"
            : (cardStyle ? Appearance.colors.colLayer1 : Appearance.colors.colLayer0)
        // Screen Edge owns the outer shell boundary. Drawing a second outline
        // here makes the edge/sidebar join read as two stacked cards.
        border.width: 0 // Screen Edge seam owns the outer boundary
        border.color: "transparent"
        radius: cardStyle
            ? Appearance.rounding.normal
            : (Appearance.rounding.screenRounding - Appearance.sizes.hyprlandGapsOut + 1)
        topLeftRadius: root.attachedEdge === "left" ? 0 : radius
        bottomLeftRadius: root.attachedEdge === "left" ? 0 : radius
        topRightRadius: root.attachedEdge === "right" ? 0 : radius
        bottomRightRadius: root.attachedEdge === "right" ? 0 : radius

        Behavior on radius {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        clip: true

        layer.enabled: root.panelVisible && !gameModeMinimal
        layer.smooth: false
        layer.mipmap: false
        layer.effect: GE.OpacityMask {
            maskSource: Rectangle {
                width: sidebarRightBackground.width
                height: sidebarRightBackground.height
                radius: sidebarRightBackground.radius
                topLeftRadius: sidebarRightBackground.topLeftRadius
                topRightRadius: sidebarRightBackground.topRightRadius
                bottomLeftRadius: sidebarRightBackground.bottomLeftRadius
                bottomRightRadius: sidebarRightBackground.bottomRightRadius
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.fill: parent
            anchors.margins: sidebarPadding
            spacing: sidebarPadding

            // Sections render in the user-configured order. One delegate owns
            // Layout hints, entrance cascade and dialog-signal routing for all
            // section kinds so reordering never changes wiring.
            Repeater {
                id: sectionRepeater
                model: root.sectionOrder
                delegate: Loader {
                    id: sectionLoader
                    required property string modelData
                    required property int index
                    readonly property bool isElastic: modelData === "widgets"
                    readonly property bool contentCollapsed: modelData === "widgets"
                        && (item?.collapsed ?? false)
                    readonly property bool usesElasticPool: isElastic && !contentCollapsed
                    readonly property bool isBeingDragged: root.sectionDragIndex === index
                    readonly property bool isDropTarget: root.sectionHoverIndex === index
                        && root.sectionDragIndex !== index && root.sectionDragIndex >= 0

                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    Layout.fillHeight: usesElasticPool
                    Layout.minimumHeight: !isElastic ? -1
                        : contentCollapsed ? implicitHeight : 250
                    Layout.preferredHeight: usesElasticPool
                        ? Math.max(250, implicitHeight) : implicitHeight
                    // The profile card is a full-bleed card that nests into the
                    // panel's corner, so its gap must match the 10px side inset
                    // exactly. The classic pill row keeps its extra breathing
                    // room, which is what that 5 was for.
                    Layout.topMargin: (modelData === "system" && root.headerStyle === "classic") ? 5 : 0
                    visible: active
                    active: {
                        if (modelData !== "sliders") return true
                        const configQuickSliders = Config.options?.sidebar?.quickSliders
                        if (!configQuickSliders?.enable) return false
                        if (!configQuickSliders?.showMic && !configQuickSliders?.showVolume && !configQuickSliders?.showBrightness) return false
                        return true
                    }
                    opacity: root._entranceCascade >= index
                        ? (root.sectionEditMode && !isBeingDragged ? 0.8 : 1) : 0
                    Behavior on opacity { enabled: Appearance.animationsEnabled; NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutCubic } }
                    scale: isBeingDragged ? 1.015 : 1
                    Behavior on scale { enabled: Appearance.animationsEnabled; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    z: isBeingDragged ? 5 : 0

                    // Live displacement while a sibling section is dragged over
                    transform: Translate {
                        y: sectionLoader.isBeingDragged
                            ? root.getSectionDragFollowY()
                            : root.getSectionDisplacementY(sectionLoader.index)
                        Behavior on y {
                            enabled: Appearance.animationsEnabled && !sectionLoader.isBeingDragged
                            NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
                        }
                    }

                    // Drop indicator bars (same language as widget reorder)
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        anchors.topMargin: -contentColumn.spacing / 2 - height / 2
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        height: 3
                        radius: 1.5
                        color: Appearance.colors.colPrimary
                        opacity: sectionLoader.isDropTarget && root.sectionHoverIndex < root.sectionDragIndex ? 0.85 : 0
                        visible: opacity > 0
                        z: 10
                        Behavior on opacity { enabled: Appearance.animationsEnabled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.bottomMargin: -contentColumn.spacing / 2 - height / 2
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        height: 3
                        radius: 1.5
                        color: Appearance.colors.colPrimary
                        opacity: sectionLoader.isDropTarget && root.sectionHoverIndex > root.sectionDragIndex ? 0.85 : 0
                        visible: opacity > 0
                        z: 10
                        Behavior on opacity { enabled: Appearance.animationsEnabled; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    }

                    // Drag grip — only exists in edit mode, top-right of the section
                    Rectangle {
                        visible: root.sectionEditMode
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.topMargin: 4
                        anchors.rightMargin: 4
                        width: 30
                        height: 22
                        z: 20
                        radius: Appearance.rounding.verysmall
                        color: sectionHandleArea.containsMouse || sectionLoader.isBeingDragged
                            ? Appearance.colors.colLayer1Hover
                            : Appearance.colors.colLayer1
                        border.width: 0
                        border.color: "transparent"

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "drag_indicator"
                            iconSize: 14
                            color: Appearance.colors.colOnLayer1
                        }

                        MouseArea {
                            id: sectionHandleArea
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            cursorShape: sectionLoader.isBeingDragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                            acceptedButtons: Qt.LeftButton
                            property bool dragStarted: false
                            onPressed: (mouse) => {
                                dragStarted = true
                                root.startSectionDrag(sectionLoader.index, mapToItem(contentColumn, mouse.x, mouse.y).y)
                            }
                            onPositionChanged: (mouse) => {
                                if (dragStarted)
                                    root.updateSectionDrag(mapToItem(contentColumn, mouse.x, mouse.y).y)
                            }
                            onReleased: {
                                if (dragStarted) root.endSectionDrag()
                                dragStarted = false
                            }
                            onCanceled: {
                                root.cancelSectionDrag()
                                dragStarted = false
                            }
                        }
                    }

                    sourceComponent: {
                        switch (modelData) {
                            case "system":
                                return root.headerStyle === "classic"
                                    ? systemSectionComponent : profileHeaderComponent
                            case "sliders": return slidersSectionComponent
                            case "toggles":
                                return (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android"
                                    ? androidTogglesComponent : classicTogglesComponent
                            case "widgets": return widgetsSectionComponent
                            default: return null
                        }
                    }
                    onLoaded: {
                        if (modelData === "widgets") root.bottomWidgetGroupItem = item
                    }

                    Connections {
                        target: sectionLoader.item
                        ignoreUnknownSignals: true
                        function onOpenAudioOutputDialog() { root.showAudioOutputDialog = true }
                        function onOpenAudioInputDialog() { root.showAudioInputDialog = true }
                        function onOpenBluetoothDialog() { root.showBluetoothDialog = true }
                        function onOpenNightLightDialog() { root.showNightLightDialog = true }
                        function onOpenHotspotDialog() { root.showHotspotDialog = true }
                        function onOpenWifiDialog() { root.showWifiDialog = true }
                        function onOpenEventsDialog(editEvent) {
                            root.eventsDialogEditEvent = editEvent
                            root.showEventsDialog = true
                        }
                    }
                }
            }
        }

        Component { id: systemSectionComponent; SystemButtonRow {} }
        Component {
            id: profileHeaderComponent
            SidebarProfileHeader {
                editMode: root.editMode
                sectionEditMode: root.sectionEditMode
                androidToggles: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android"
                reloadEnabled: root.reloadButtonEnabled
                settingsEnabled: root.settingsButtonEnabled
                panelVisible: root.panelVisible
                panelCardStyle: sidebarRightBackground.cardStyle
                panelScreen: root.panelScreen
                surfaceDialect: sidebarRightBackground.surfaceDialect
                panelRadius: sidebarRightBackground.radius
                panelInset: root.sidebarPadding
                atPanelTop: root.sectionOrder[0] === "system"
                onEditModeRequested: root.editMode = !root.editMode
                onSectionEditModeRequested: {
                    root.sectionEditMode = !root.sectionEditMode
                    if (!root.sectionEditMode) {
                        root.cancelSectionDrag()
                    }
                }
                onReloadRequested: root.requestReload()
                onSettingsRequested: root.openSettings()
            }
        }
        Component { id: slidersSectionComponent; QuickSliders {} }
        Component { id: classicTogglesComponent; ClassicQuickPanel {} }
        Component { id: androidTogglesComponent; AndroidQuickPanel { editMode: root.editMode } }
        Component { id: widgetsSectionComponent; BottomWidgetGroup {} }

    }

    // With the panel collapsed the window still spans full height; clicks on
    // the vacated strip below the panel should dismiss like the backdrop does.
    MouseArea {
        anchors.top: sidebarRightBackground.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        enabled: sidebarRightBackground.height < root.height - 1
        onClicked: GlobalStates.sidebarRightOpen = false
    }

    ToggleDialog {
        shownPropertyString: "showAudioOutputDialog"
        dialog: VolumeDialog {
            isSink: true
        }
    }

    ToggleDialog {
        shownPropertyString: "showAudioInputDialog"
        dialog: VolumeDialog {
            isSink: false
        }
    }

    ToggleDialog {
        shownPropertyString: "showBluetoothDialog"
        dialog: BluetoothDialog {}
        onShownChanged: {
            if (!Bluetooth.defaultAdapter) return
            if (!shown) {
                Bluetooth.defaultAdapter.discovering = false;
            } else {
                Bluetooth.defaultAdapter.enabled = true;
                Bluetooth.defaultAdapter.discovering = true;
            }
        }
    }

    ToggleDialog {
        shownPropertyString: "showNightLightDialog"
        dialog: NightLightDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showHotspotDialog"
        dialog: HotspotDialog {}
    }

    ToggleDialog {
        shownPropertyString: "showWifiDialog"
        dialog: WifiDialog {}
        onShownChanged: {
            if (!shown) return;
            Network.enableWifi();
            Network.rescanWifi();
        }
    }

    ToggleDialog {
        id: eventsToggle
        shownPropertyString: "showEventsDialog"
        dialog: EventsDialog {}
        onShownChanged: {
            if (shown && eventsToggle.item) {
                const arg = root.eventsDialogEditEvent;
                if (arg instanceof Date) {
                    eventsToggle.item.resetForm();
                    eventsToggle.item.eventDate = arg;
                } else if (arg) {
                    eventsToggle.item.loadEvent(arg);
                } else {
                    eventsToggle.item.resetForm();
                }
            }
        }
        onActiveChanged: {
            if (!active) {
                root.eventsDialogEditEvent = null;
            }
        }
    }

    component ToggleDialog: Loader {
        id: toggleDialogLoader
        required property string shownPropertyString
        property alias dialog: toggleDialogLoader.sourceComponent
        readonly property bool shown: root[shownPropertyString]
        property bool _loaded: false
        anchors.fill: parent

        active: _loaded

        onShownChanged: {
            if (shown && !_loaded) _loaded = true
            if (item) {
                item.show = shown
                if (shown) item.forceActiveFocus()
            }
        }

        onItemChanged: {
            if (item && shown) {
                item.show = true;
                item.forceActiveFocus();
            }
        }

        Connections {
            target: toggleDialogLoader.item
            function onDismiss() {
                root[toggleDialogLoader.shownPropertyString] = false;
            }
        }
    }

    component SystemButtonRow: Item {
        implicitHeight: systemButtonsRow.implicitHeight

        ButtonGroup {
            id: systemButtonsRow
            anchors {
                top: parent.top
                bottom: parent.bottom
                right: parent.right
            }
            color: Appearance.colors.colLayer1
            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
            padding: 4
            spacing: 8

            QuickToggleButton {
                toggled: root.editMode
                visible: (Config.options?.sidebar?.quickToggles?.style ?? "classic") === "android"
                buttonIcon: "edit"
                onClicked: root.editMode = !root.editMode
                StyledToolTip {
                    position: "left"
                    text: Translation.tr("Edit quick toggles") + (root.editMode ? Translation.tr("\nLMB to enable/disable\nRMB to toggle size\nScroll to swap position") : "")
                }
            }
            QuickToggleButton {
                toggled: root.sectionEditMode
                buttonIcon: "swap_vert"
                onClicked: {
                    root.sectionEditMode = !root.sectionEditMode
                    if (!root.sectionEditMode) {
                        root.cancelSectionDrag()
                    }
                }
                StyledToolTip {
                    position: "left"
                    text: Translation.tr("Reorder sections\nDrag the grips to rearrange the sidebar")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "view_sidebar"
                onClicked: Config.setNestedValue("sidebar.layout", "compact")
                StyledToolTip {
                    position: "left"
                    text: Translation.tr("Switch to compact layout")
                }
            }
            QuickToggleButton {
                id: reloadButton
                toggled: false
                enabled: root.reloadButtonEnabled
                opacity: enabled ? 1.0 : 0.5
                buttonIcon: "restart_alt"
                onClicked: root.requestReload()
                StyledToolTip {
                    position: "left"
                    text: Translation.tr("Reload Quickshell")
                }
            }
            QuickToggleButton {
                id: settingsButton
                toggled: false
                enabled: root.settingsButtonEnabled
                opacity: enabled ? 1.0 : 0.5
                buttonIcon: "settings"
                onClicked: root.openSettings()
                StyledToolTip {
                    position: "left"
                    text: Translation.tr("Settings")
                }
            }
            QuickToggleButton {
                toggled: false
                buttonIcon: "power_settings_new"
                onClicked: {
                    GlobalStates.sessionOpen = true;
                }
                StyledToolTip {
                    position: "left"
                    text: Translation.tr("Session")
                }
            }
        }
    }
}
