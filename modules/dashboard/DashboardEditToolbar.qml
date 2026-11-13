import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks

Rectangle {
    id: root

    required property var canvasController
    property var tabController: null
    property bool embeddedSurface: false
    property bool compactHeight: false
    property bool splitSideDocks: false
    property Item leftDockParent: null
    property Item rightDockParent: null
    property string activeDockTab: "modules"
    property string moduleSearchQuery: ""

    readonly property real desiredLeftDockWidth: (root.splitSideDocks && root.tabController !== null)
        ? Math.ceil(leftTabsDock.implicitWidth) : 0
    readonly property real desiredLeftDockHeight: (root.splitSideDocks && root.tabController !== null)
        ? Math.ceil(leftTabsDock.implicitHeight) : 0
    readonly property real desiredRightDockWidth: (root.splitSideDocks && root.canvasController !== null)
        ? Math.ceil(rightLayoutDock.implicitWidth) : 0
    readonly property real desiredRightDockHeight: (root.splitSideDocks && root.canvasController !== null)
        ? Math.ceil(rightLayoutDock.implicitHeight) : 0

    readonly property bool editing: root.canvasController?.editMode ?? false
    readonly property bool naming: tabController?.tabNamingActive ?? false
    readonly property var visibleIds: root.canvasController?.visibleIds ?? []
    readonly property var hiddenIds: root.canvasController?.hiddenIds ?? []
    readonly property var allModuleIds: {
        const raw = root.canvasController?._allIds
        if (raw && raw.length !== undefined && raw.length > 0)
            return Array.from(raw)
        const merged = []
        for (const id of Array.from(root.visibleIds)) {
            if (merged.indexOf(String(id)) < 0)
                merged.push(String(id))
        }
        for (const id of Array.from(root.hiddenIds)) {
            if (merged.indexOf(String(id)) < 0)
                merged.push(String(id))
        }
        return merged
    }
    readonly property var filteredModuleIds: {
        const q = root.moduleSearchQuery.trim().toLowerCase()
        if (q.length === 0)
            return root.allModuleIds
        return root.allModuleIds.filter(id => {
            const key = String(id)
            const label = String(root.canvasController?._label(key) ?? key).toLowerCase()
            return key.toLowerCase().indexOf(q) >= 0 || label.indexOf(q) >= 0
        })
    }
    readonly property bool abyssMode:
        (Config.options?.panelFamily ?? "abyss") === "abyss"
    readonly property real horizontalPadding: root.abyssMode
        ? Math.max(10, AbyssStyle.contentPadding * 0.55) : 10
    readonly property string effectiveDockTab: root.splitSideDocks
        ? "modules"
        : (root.tabController === null && root.activeDockTab === "tabs"
            ? "modules" : root.activeDockTab)
    readonly property string targetCustomTabId: {
        const cur = String(root.tabController?.currentPageId ?? "")
        if (cur.startsWith("custom-")) return cur
        const tabs = root.tabController?.customTabs ?? []
        return tabs.length > 0 ? String(tabs[tabs.length - 1]?.id ?? "") : ""
    }
    readonly property string statusSubtitle: {
        const msg = String(root.canvasController?.layoutMessage ?? "")
        if (msg.length > 0)
            return msg
        const overflowCount = Number(root.canvasController?.workspace?.overflow?.length ?? 0)
        if (overflowCount > 0)
            return Translation.tr("%1 modules need more space").arg(overflowCount)
        const sel = String(root.canvasController?.selectedId ?? "")
        if (sel.length > 0)
            return Translation.tr("Editing %1").arg(root.canvasController?._label(sel) ?? sel)
        return Translation.tr("Edit widgets")
    }

    function isModuleVisible(id): bool {
        const list = root.visibleIds
        if (!list) return false
        for (let i = 0; i < list.length; ++i) {
            if (String(list[i]) === String(id))
                return true
        }
        return false
    }

    function moduleAccentColor(id): color {
        switch (String(id)) {
            case "clock":
            case "weather":
                return root.abyssMode ? AbyssStyle.accent : Appearance.colors.colPrimary
            case "media":
            case "notes":
                return Appearance.colors.colSecondary ?? Appearance.colors.colPrimary
            case "system":
            case "github":
                return Appearance.colors.colTertiary ?? Appearance.colors.colPrimary
            default:
                return root.abyssMode ? AbyssStyle.accent : Appearance.colors.colPrimary
        }
    }

    function selectGridStyle(styleKey): void {
        if (!root.canvasController)
            return
        for (let i = 0; i < 4; ++i) {
            if (String(root.canvasController.gridStyle ?? "dots") === styleKey)
                return
            root.canvasController._cycleGridStyle()
        }
    }

    function pageTitle(pageId): string {
        const key = String(pageId)
        if (key === "dashboard") return Translation.tr("Dashboard")
        if (key === "weeklyPlanner") return Translation.tr("Planner")
        if (key === "music") return Translation.tr("Music")
        if (key === "spacedRepetition") return Translation.tr("Review")
        const tabs = root.tabController?.customTabs ?? []
        for (let i = 0; i < tabs.length; ++i) {
            if (String(tabs[i]?.id ?? "") === key)
                return String(tabs[i]?.name ?? key)
        }
        return key
    }

    function pageIcon(pageId): string {
        const key = String(pageId)
        if (key === "dashboard") return "dashboard"
        if (key === "weeklyPlanner") return "calendar_view_week"
        if (key === "music") return "library_music"
        if (key === "spacedRepetition") return "psychology"
        return "tab"
    }

    function switchDashboardTab(pageId): void {
        if (!root.tabController || pageId === root.tabController.currentPageId)
            return
        const editor = root.canvasController
        if (editor?.editMode) {
            editor.commitEditMode()
            if (editor.editMode)
                return
        }
        const editableTarget = pageId === "dashboard" || String(pageId).startsWith("custom-")
        if (editableTarget)
            root.tabController._pendingNewEditId = pageId
        root.tabController.selectPage(pageId)
        if (pageId === "dashboard") {
            Qt.callLater(() => {
                if (root.tabController?.currentPageId === "dashboard"
                        && root.tabController?.canvasController
                        && !root.tabController.canvasController.editMode) {
                    root.tabController._pendingNewEditId = ""
                    root.tabController.canvasController.beginEditMode()
                }
            })
        }
    }

    function focusTabNameInput(): void {
        if (!root.naming || !root.visible) return
        const expected = root.tabController?._customDialogName ?? ""
        if (tabNameInput.text !== expected)
            tabNameInput.text = expected
        tabNameInput.forceActiveFocus()
        tabNameInput.cursorPosition = tabNameInput.text.length
    }

    onNamingChanged: if (naming) Qt.callLater(() => {
        if (root.naming) tabNameInput.forceActiveFocus()
        root.focusTabNameInput()
    })
    onVisibleChanged: {
        if (!root.visible && root.moduleSearchQuery.length > 0)
            root.moduleSearchQuery = ""
        if (root.visible && root.naming)
            Qt.callLater(root.focusTabNameInput)
    }
    onEnabledChanged: if (root.enabled && root.naming) Qt.callLater(root.focusTabNameInput)

    Timer {
        id: tabNameFocusTimer
        interval: 35
        repeat: true
        running: root.naming && root.visible && !tabNameInput.activeFocus
        property int attempts: 0
        onRunningChanged: if (running) attempts = 0
        onTriggered: {
            attempts++
            root.focusTabNameInput()
            if (tabNameInput.activeFocus || attempts >= 8)
                stop()
        }
    }

    Connections {
        target: root.tabController
        function on_CustomDialogNameChanged(): void {
            const expected = root.tabController?._customDialogName ?? ""
            if (tabNameInput.text !== expected)
                tabNameInput.text = expected
        }
        function on_CustomDialogShownChanged(): void {
            if (root.naming)
                Qt.callLater(root.focusTabNameInput)
        }
    }

    // Preserve the canonical 2-tier Edit Dashboard Layout footprint while
    // Create/Rename temporarily overlays the top header bar. Never size the
    // dock from the naming row or validation message.
    implicitWidth: 1020
    readonly property real desiredBottomDockWidth: root.splitSideDocks ? dock.implicitWidth : root.implicitWidth
    readonly property bool stageSideHosted: root.splitSideDocks && root.embeddedSurface
    readonly property real editToolbarHeight: dock.implicitHeight
    implicitHeight: root.editToolbarHeight
    visible: root.editing || root.naming
    radius: Appearance.rounding.large
    topLeftRadius: radius
    topRightRadius: radius
    bottomLeftRadius: root.abyssMode ? radius : 0
    bottomRightRadius: root.abyssMode ? radius : 0
    color: root.embeddedSurface ? "transparent" : root.abyssMode
        ? Qt.alpha(AbyssStyle.surfaceDeep,
            Math.max(0.84, AbyssStyle.contentOpacity))
        : Appearance.colors.colLayer0
    border.width: root.abyssMode && !root.embeddedSurface ? 1 : 0
    border.color: root.abyssMode
        ? Qt.alpha(AbyssStyle.accent, 0.24) : "transparent"
    clip: true

    // Flexible content width for Bottom Edit Dashboard Stage (capped <= 80% by stage).
    AbyssCustomizationDock {
        id: dock
        anchors.fill: parent
        embeddedSurface: true
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.compactHeight ? 5 : 7
        topBarHeight: root.compactHeight ? 38 : 40
        trayGap: root.compactHeight ? 5 : 6
        trayHeight: root.compactHeight ? 88 : 114
        contentPreferredWidth: root.splitSideDocks ? Math.ceil(modulesGalleryRow.implicitWidth + 16) : 0
        canUndo: root.canvasController?.canUndo ?? false
        undoObjectName: "dashboardEditUndo"
        cancelObjectName: "dashboardEditCancel"
        doneObjectName: "dashboardEditDone"
        headerOverlayActive: root.naming
        activeTab: root.effectiveDockTab
        showSearch: root.splitSideDocks || (root.effectiveDockTab === "modules" && root.width >= 820)
        searchPlaceholder: Translation.tr("Search modules...")
        searchObjectName: "dashboardModuleSearch"
        searchText: root.moduleSearchQuery
        tabs: {
            const compactLabels = !root.splitSideDocks && root.width < 680
            const list = [
                {
                    key: "modules",
                    label: Translation.tr("Modules"),
                    icon: compactLabels ? "" : "widgets",
                    badge: root.hiddenIds.length > 0 ? String(root.hiddenIds.length) : "",
                    objectName: "dashboardDockTabModules"
                }
            ]
            if (!root.splitSideDocks) {
                list.push({
                    key: "layout",
                    label: compactLabels ? Translation.tr("Layout") : Translation.tr("Layout & Grid"),
                    icon: compactLabels ? "" : "grid_view",
                    objectName: "dashboardDockTabLayout"
                })
                if (root.tabController !== null) {
                    list.push({
                        key: "tabs",
                        label: Translation.tr("Tabs"),
                        icon: compactLabels ? "" : "tab",
                        badge: (root.tabController?.customTabs?.length ?? 0) > 0
                            ? String(root.tabController.customTabs.length) : "",
                        objectName: "dashboardDockTabTabs"
                    })
                }
            }
            return list
        }

        onUndoClicked: root.canvasController?.undoLastEdit()
        onCancelClicked: root.canvasController?.cancelEditMode()
        onDoneClicked: root.canvasController?.commitEditMode()
        onTabClicked: key => root.activeDockTab = key
        onSearchEdited: text => root.moduleSearchQuery = text

        trailingControls: [
            RowLayout {
                id: quickActionsRow
                visible: !root.naming && !root.splitSideDocks
                Layout.alignment: Qt.AlignHCenter
                spacing: 5

                EditToolButton {
                    visible: root.width >= 720
                    iconName: root.canvasController?.snapEnabled
                        ? "grid_on" : "grid_off"
                    tooltipText: root.canvasController?.snapEnabled
                        ? Translation.tr("Snap to grid: on")
                        : Translation.tr("Snap to grid: off")
                    toggled: root.canvasController?.snapEnabled ?? false
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.toggleSnap()
                    }
                }

                EditToolButton {
                    visible: root.width >= 760
                    iconName: root.canvasController?.gridStyle === "lines"
                        ? "grid_4x4"
                        : (root.canvasController?.gridStyle === "cross"
                            ? "add" : "drag_indicator")
                    tooltipText: Translation.tr("Grid style: %1 — click to cycle")
                        .arg(root.canvasController?.gridStyle ?? "dots")
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController._cycleGridStyle()
                    }
                }

                EditToolButton {
                    visible: root.width >= 820 && !(root.canvasController?.responsiveWorkspace ?? false)
                    iconName: "fit_screen"
                    tooltipText: root.canvasController?.autoAdjustSizeEnabled
                        ? Translation.tr("Auto-adjust affected module sizes: on")
                        : Translation.tr("Auto-adjust affected module sizes: off")
                    toggled: root.canvasController?.autoAdjustSizeEnabled ?? true
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.toggleAutoAdjustSize()
                    }
                }

                EditToolButton {
                    visible: root.width >= 760 && root.hiddenIds.length > 0
                    iconName: "auto_awesome_motion"
                    tooltipText: Translation.tr("Add all modules and fit them automatically")
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.fitAllWidgets()
                    }
                }

                EditToolButton {
                    visible: root.width >= 880
                    iconName: "restart_alt"
                    tooltipText: Translation.tr("Reset dashboard layout")
                    onClicked: {
                        if (root.canvasController)
                            root.canvasController.resetLayout()
                    }
                }

                EditToolButton {
                    objectName: root.splitSideDocks ? "" : "dashboardToolbarActionCreateTab"
                    visible: root.tabController !== null
                    iconName: "add"
                    tooltipText: Translation.tr("Create custom tab")
                    onClicked: root.tabController?.openCustomTabDialog("create", "")
                }
            }
        ]

        headerOverlay: [
            RowLayout {
                id: tabNamingRow
                objectName: "dashboardTabNamingToolbar"
                anchors.fill: parent
                visible: root.naming
                spacing: 8

                StyledText {
                    visible: root.width >= 640
                    Layout.alignment: Qt.AlignVCenter
                    text: root.tabController?._customDialogMode === "rename"
                        ? Translation.tr("Rename custom tab")
                        : Translation.tr("Create custom tab")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: root.abyssMode
                        ? AbyssStyle.textColor : Appearance.colors.colOnLayer0
                }

                TextField {
                    id: tabNameInput
                    objectName: "dashboardToolbarTabName"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 160
                    Layout.preferredHeight: Math.min(40, dock.topBarHeight)
                    Layout.minimumHeight: 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 40
                    maximumLength: 41
                    hoverEnabled: true
                    focusPolicy: Qt.StrongFocus
                    selectByMouse: true
                    cursorVisible: activeFocus
                    font.pixelSize: Appearance.font.pixelSize.normal
                    verticalAlignment: TextInput.AlignVCenter
                    leftPadding: 14
                    rightPadding: 14
                    topPadding: 6
                    bottomPadding: 6
                    color: root.abyssMode
                        ? AbyssStyle.textColor : Appearance.colors.colOnLayer1
                    placeholderTextColor: root.abyssMode
                        ? AbyssStyle.textColorMuted : Appearance.colors.colSubtext
                    selectionColor: Appearance.colors.colPrimaryContainer
                    selectedTextColor: Appearance.colors.colOnPrimaryContainer
                    placeholderText: Translation.tr("Custom tab name")
                    text: root.tabController?._customDialogName ?? ""
                    onTextEdited: root.tabController?.setCustomTabName(text)
                    onAccepted: root.tabController?.acceptCustomTabDialog()
                    onPressed: tabNameInput.forceActiveFocus()

                    cursorDelegate: Rectangle {
                        id: tabNameCursor
                        width: 2
                        color: root.abyssMode ? AbyssStyle.accent : Appearance.colors.colPrimary
                        visible: tabNameInput.activeFocus
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            running: tabNameInput.activeFocus
                            PropertyAction { value: 1.0 }
                            PauseAnimation { duration: 530 }
                            PropertyAction { value: 0.15 }
                            PauseAnimation { duration: 420 }
                        }
                    }

                    readonly property bool invalidName:
                        (root.tabController?._customDialogError?.length ?? 0) > 0

                    background: Rectangle {
                        id: tabNameBackground
                        objectName: "dashboardTabNameBackground"
                        radius: 12
                        color: root.abyssMode
                            ? AbyssStyle.contentLayer : Appearance.colors.colLayer1
                        border.width: tabNameInput.activeFocus ? 1.5 : 1
                        border.color: tabNameInput.invalidName
                            ? Appearance.colors.colError
                            : tabNameInput.activeFocus
                                ? (root.abyssMode
                                    ? Qt.alpha(AbyssStyle.accent, 0.85)
                                    : Appearance.colors.colPrimary)
                                : Qt.alpha(root.abyssMode
                                    ? AbyssStyle.accent : Appearance.colors.colOutline,
                                    tabNameInput.hovered ? 0.52 : 0.30)
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: AbyssStyle.motionFast }
                        }
                        Behavior on border.color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: AbyssStyle.motionFast }
                        }
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 3
                            radius: Math.max(0, tabNameBackground.radius - 3)
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.alpha(tabNameInput.invalidName
                                ? Appearance.colors.colError
                                : (root.abyssMode
                                    ? AbyssStyle.accent : Appearance.colors.colPrimary), 0.16)
                            visible: tabNameInput.activeFocus
                        }
                    }

                    StyledToolTip {
                        text: root.tabController?._customDialogError ?? ""
                        position: "top"
                        useParentHover: false
                        extraVisibleCondition: tabNameInput.invalidName
                        alternativeVisibleCondition: tabNameInput.invalidName
                    }
                }

                RippleButton {
                    objectName: "dashboardToolbarCreate"
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colPrimaryContainer
                    onClicked: root.tabController?.acceptCustomTabDialog()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "check"
                        color: Appearance.colors.colOnPrimaryContainer
                        iconSize: Appearance.font.pixelSize.normal
                    }
                    StyledToolTip {
                        text: root.tabController?._customDialogMode === "rename"
                            ? Translation.tr("Save name") : Translation.tr("Create tab")
                    }
                }

                RippleButton {
                    objectName: "dashboardToolbarCancelCreate"
                    implicitWidth: 34
                    implicitHeight: 34
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer1
                    onClicked: root.tabController?.cancelCustomTabDialog()
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        color: Appearance.colors.colOnLayer1
                        iconSize: Appearance.font.pixelSize.normal
                    }
                    StyledToolTip { text: Translation.tr("Cancel") }
                }
            }
        ]

        // ── Tier 2A: Modules Gallery ─────────────────────────────────────
        Item {
            id: modulesTray
            anchors.fill: parent
            visible: root.effectiveDockTab === "modules"

            Flickable {
                id: modulesGalleryViewport
                anchors.fill: parent
                contentWidth: modulesGalleryRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const maxScroll = Math.max(0, modulesGalleryViewport.contentWidth - modulesGalleryViewport.width)
                        if (maxScroll <= 0)
                            return
                        const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        modulesGalleryViewport.contentX = Math.max(0,
                            Math.min(maxScroll, modulesGalleryViewport.contentX - delta * 0.65))
                        event.accepted = true
                    }
                }

                Row {
                    id: modulesGalleryRow
                    y: Math.max(2, Math.round((modulesGalleryViewport.height - implicitHeight) / 2))
                    spacing: 10

                    Repeater {
                        model: root.filteredModuleIds
                        delegate: AbyssCustomizationTile {
                            id: moduleTile
                            required property var modelData
                            readonly property string moduleId: String(modelData)
                            readonly property bool moduleVisible: root.isModuleVisible(moduleId)
                            readonly property bool moduleSelected: moduleVisible
                                && String(root.canvasController?.selectedId ?? "") === moduleId

                            objectName: "dashboardModuleTile_" + moduleId
                            tileId: moduleId
                            title: root.canvasController?._label(moduleId) ?? moduleId
                            subtitle: root.compactHeight ? ""
                                : (moduleSelected ? Translation.tr("Selected")
                                    : (moduleVisible ? Translation.tr("Active") : Translation.tr("Hidden")))
                            icon: root.canvasController?._icon(moduleId) ?? "widgets"
                            accentColor: root.moduleAccentColor(moduleId)
                            active: moduleVisible
                            selected: moduleSelected
                            separateBadgeClick: true
                            tileWidth: root.compactHeight ? 116 : 126
                            previewHeight: root.compactHeight ? 54 : 66
                            tooltipText: moduleVisible
                                ? Translation.tr("%1 — click to select on canvas, click check badge to hide").arg(title)
                                : Translation.tr("Add %1 to active tab").arg(title)

                            onClicked: {
                                if (!root.canvasController)
                                    return
                                if (moduleTile.moduleVisible) {
                                    root.canvasController.selectedId = moduleTile.moduleId
                                } else {
                                    root.canvasController.setWidgetVisible(moduleTile.moduleId, true)
                                    if (root.isModuleVisible(moduleTile.moduleId))
                                        root.canvasController.selectedId = moduleTile.moduleId
                                }
                            }

                            onBadgeClicked: {
                                if (!root.canvasController)
                                    return
                                const nextVisible = !moduleTile.moduleVisible
                                root.canvasController.setWidgetVisible(moduleTile.moduleId, nextVisible)
                                if (nextVisible && root.isModuleVisible(moduleTile.moduleId))
                                    root.canvasController.selectedId = moduleTile.moduleId
                            }

                            ModuleMiniPreview {
                                anchors.fill: parent
                                moduleId: moduleTile.moduleId
                                accentColor: moduleTile.accentColor
                                moduleIcon: moduleTile.icon
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.filteredModuleIds.length === 0
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: Translation.tr("No matching Dashboard modules")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }

        // ── Tier 2B: Layout & Grid Controls ──────────────────────────────
        Item {
            id: layoutTray
            anchors.fill: parent
            visible: root.effectiveDockTab === "layout"

            Flickable {
                id: layoutControlsViewport
                anchors.fill: parent
                contentWidth: layoutControlsRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const maxScroll = Math.max(0, layoutControlsViewport.contentWidth - layoutControlsViewport.width)
                        if (maxScroll <= 0)
                            return
                        const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        layoutControlsViewport.contentX = Math.max(0,
                            Math.min(maxScroll, layoutControlsViewport.contentX - delta * 0.65))
                        event.accepted = true
                    }
                }

                Row {
                    id: layoutControlsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    DockControlCard {
                        objectName: root.splitSideDocks ? "" : "dashboardLayoutSnapCard"
                        cardHeight: root.compactHeight ? 72 : 90
                        iconName: root.canvasController?.snapEnabled ? "grid_on" : "grid_off"
                        titleText: Translation.tr("Snap to Grid")
                        subtitleText: root.canvasController?.snapEnabled
                            ? Translation.tr("Enabled") : Translation.tr("Freeform")
                        toggled: root.canvasController?.snapEnabled ?? false
                        tooltipText: root.canvasController?.snapEnabled
                            ? Translation.tr("Snap to grid: on")
                            : Translation.tr("Snap to grid: off")
                        onClicked: {
                            if (root.canvasController)
                                root.canvasController.toggleSnap()
                        }
                    }

                    // Segmented Grid Style Card (Dots / Lines / Cross)
                    Rectangle {
                        implicitWidth: styleCardColumn.implicitWidth + 24
                        implicitHeight: root.compactHeight ? 72 : 90
                        width: implicitWidth
                        height: implicitHeight
                        radius: Math.min(14, Appearance.rounding.normal)
                        color: Qt.alpha(root.abyssMode
                            ? AbyssStyle.surfaceRaised : Appearance.colors.colLayer2, 0.72)
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)

                        Column {
                            id: styleCardColumn
                            anchors.centerIn: parent
                            spacing: root.compactHeight ? 5 : 8

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("Grid Style")
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }

                            Row {
                                spacing: 4
                                Repeater {
                                    model: [
                                        { key: "dots", label: Translation.tr("Dots"), icon: "drag_indicator" },
                                        { key: "lines", label: Translation.tr("Lines"), icon: "grid_4x4" },
                                        { key: "cross", label: Translation.tr("Cross"), icon: "add" }
                                    ]
                                    delegate: RippleButton {
                                        required property var modelData
                                        readonly property bool selectedStyle:
                                            String(root.canvasController?.gridStyle ?? "dots") === modelData.key
                                        implicitHeight: root.compactHeight ? 26 : 30
                                        implicitWidth: styleChipRow.implicitWidth + 16
                                        padding: 0
                                        leftPadding: 0
                                        rightPadding: 0
                                        topPadding: 0
                                        bottomPadding: 0
                                        buttonRadius: Appearance.rounding.full
                                        focusPolicy: Qt.StrongFocus
                                        toggled: selectedStyle
                                        colBackground: Qt.alpha(Appearance.colors.colLayer3, 0.55)
                                        colBackgroundHover: Appearance.colors.colLayer3Hover
                                        colBackgroundToggled: root.abyssMode
                                            ? Qt.alpha(AbyssStyle.accent, 0.26)
                                            : Appearance.colors.colPrimaryContainer
                                        onClicked: root.selectGridStyle(modelData.key)

                                        contentItem: Item {
                                            implicitWidth: styleChipRow.implicitWidth
                                            implicitHeight: styleChipRow.implicitHeight
                                            Row {
                                                id: styleChipRow
                                                anchors.centerIn: parent
                                                spacing: 4
                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.icon
                                                    iconSize: 14
                                                    color: selectedStyle
                                                        ? (root.abyssMode ? AbyssStyle.accent : Appearance.colors.colOnPrimaryContainer)
                                                        : Appearance.colors.colSubtext
                                                }
                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: modelData.label
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: selectedStyle ? Font.DemiBold : Font.Medium
                                                    color: selectedStyle
                                                        ? (root.abyssMode ? AbyssStyle.textColor : Appearance.colors.colOnPrimaryContainer)
                                                        : Appearance.colors.colOnLayer1
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    DockControlCard {
                        objectName: root.splitSideDocks ? "" : "dashboardLayoutGridSizeCard"
                        cardHeight: root.compactHeight ? 72 : 90
                        iconName: "grid_view"
                        titleText: Translation.tr("Grid Spacing")
                        subtitleText: Translation.tr("%1 px — click to cycle")
                            .arg(root.canvasController?.gridSize ?? 24)
                        tooltipText: Translation.tr("Grid size: %1px — click to cycle")
                            .arg(root.canvasController?.gridSize ?? 24)
                        onClicked: {
                            if (root.canvasController)
                                root.canvasController._cycleGridSize()
                        }
                    }

                    DockControlCard {
                        visible: !(root.canvasController?.responsiveWorkspace ?? false)
                        objectName: root.splitSideDocks ? "" : "dashboardLayoutAutoFitCard"
                        cardHeight: root.compactHeight ? 72 : 90
                        iconName: "fit_screen"
                        titleText: Translation.tr("Auto-Adjust Size")
                        subtitleText: (root.canvasController?.autoAdjustSizeEnabled ?? true)
                            ? Translation.tr("Responsive") : Translation.tr("Manual")
                        toggled: root.canvasController?.autoAdjustSizeEnabled ?? true
                        tooltipText: root.canvasController?.autoAdjustSizeEnabled
                            ? Translation.tr("Auto-adjust affected module sizes: on")
                            : Translation.tr("Auto-adjust affected module sizes: off")
                        onClicked: {
                            if (root.canvasController)
                                root.canvasController.toggleAutoAdjustSize()
                        }
                    }

                    DockControlCard {
                        objectName: root.splitSideDocks ? "" : "dashboardLayoutFitAllCard"
                        cardHeight: root.compactHeight ? 72 : 90
                        iconName: "auto_awesome_motion"
                        titleText: Translation.tr("Smart Fit All")
                        subtitleText: root.hiddenIds.length > 0
                            ? Translation.tr("Pack %1 hidden").arg(root.hiddenIds.length)
                            : Translation.tr("All visible")
                        enabled: root.hiddenIds.length > 0
                        tooltipText: Translation.tr("Add all modules and fit them automatically")
                        onClicked: {
                            if (root.canvasController)
                                root.canvasController.fitAllWidgets()
                        }
                    }

                    DockControlCard {
                        objectName: root.splitSideDocks ? "" : "dashboardLayoutResetCard"
                        cardHeight: root.compactHeight ? 72 : 90
                        iconName: "restart_alt"
                        titleText: Translation.tr("Reset Layout")
                        subtitleText: Translation.tr("Restore tab defaults")
                        tooltipText: Translation.tr("Reset dashboard layout")
                        onClicked: {
                            if (root.canvasController)
                                root.canvasController.resetLayout()
                        }
                    }
                }
            }
        }

        // ── Tier 2C: Custom Tabs & Quick Switcher ────────────────────────
        Item {
            id: tabsTray
            anchors.fill: parent
            visible: root.tabController !== null && root.effectiveDockTab === "tabs"

            Flickable {
                id: tabsControlsViewport
                anchors.fill: parent
                contentWidth: tabsControlsRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width

                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const maxScroll = Math.max(0, tabsControlsViewport.contentWidth - tabsControlsViewport.width)
                        if (maxScroll <= 0)
                            return
                        const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        tabsControlsViewport.contentX = Math.max(0,
                            Math.min(maxScroll, tabsControlsViewport.contentX - delta * 0.65))
                        event.accepted = true
                    }
                }

                Row {
                    id: tabsControlsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    DockControlCard {
                        cardHeight: root.compactHeight ? 72 : 90
                        iconName: "add"
                        titleText: Translation.tr("Create Custom Tab")
                        subtitleText: Translation.tr("New blank canvas")
                        toggled: true
                        tooltipText: Translation.tr("Create custom tab")
                        onClicked: root.tabController?.openCustomTabDialog("create", "")
                    }

                    DockControlCard {
                        objectName: root.splitSideDocks ? "" : "dashboardToolbarActionRenameTab"
                        cardHeight: root.compactHeight ? 72 : 90
                        enabled: root.targetCustomTabId.length > 0
                        iconName: "drive_file_rename_outline"
                        titleText: Translation.tr("Rename Active Tab")
                        subtitleText: root.targetCustomTabId.length > 0
                            ? root.pageTitle(root.targetCustomTabId)
                            : Translation.tr("Select custom tab")
                        tooltipText: Translation.tr("Rename custom tab")
                        onClicked: {
                            if (root.targetCustomTabId.length > 0)
                                root.tabController?.openCustomTabDialog("rename", root.targetCustomTabId)
                        }
                    }

                    DockControlCard {
                        objectName: root.splitSideDocks ? "" : "dashboardToolbarActionDeleteTab"
                        cardHeight: root.compactHeight ? 72 : 90
                        enabled: root.targetCustomTabId.length > 0
                        iconName: "delete_outline"
                        titleText: Translation.tr("Delete Active Tab")
                        subtitleText: root.targetCustomTabId.length > 0
                            ? root.pageTitle(root.targetCustomTabId)
                            : Translation.tr("Select custom tab")
                        tooltipText: Translation.tr("Delete custom tab")
                        onClicked: {
                            if (root.targetCustomTabId.length > 0)
                                root.tabController?.openCustomTabDialog("delete", root.targetCustomTabId)
                        }
                    }

                    DockControlCard {
                        cardHeight: root.compactHeight ? 72 : 90
                        readonly property bool isDefaultPage:
                            String(Config.options?.dashboard?.defaultTabId ?? "")
                            === String(root.tabController?.currentPageId ?? "")
                        iconName: "push_pin"
                        titleText: Translation.tr("Default Tab")
                        subtitleText: isDefaultPage
                            ? Translation.tr("Pinned startup tab")
                            : Translation.tr("Set active as default")
                        toggled: isDefaultPage
                        tooltipText: Translation.tr("Open this tab after inactivity")
                        onClicked: {
                            const cur = String(root.tabController?.currentPageId ?? "")
                            if (cur.length > 0)
                                root.tabController?.setDefaultTab(cur)
                        }
                    }

                    Rectangle {
                        visible: (root.tabController?.pageIds?.length ?? 0) > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: root.compactHeight ? 48 : 60
                        color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)
                    }

                    Repeater {
                        model: root.tabController?.pageIds ?? []
                        delegate: DockControlCard {
                            required property var modelData
                            readonly property string pageKey: String(modelData)
                            readonly property bool current:
                                String(root.tabController?.currentPageId ?? "") === pageKey
                            cardHeight: root.compactHeight ? 72 : 90
                            iconName: root.pageIcon(pageKey)
                            titleText: root.pageTitle(pageKey)
                            subtitleText: current
                                ? Translation.tr("Current tab")
                                : (pageKey.startsWith("custom-")
                                    ? Translation.tr("Custom canvas")
                                    : Translation.tr("Switch tab"))
                            toggled: current
                            tooltipText: Translation.tr("Switch to %1").arg(titleText)
                            onClicked: root.switchDashboardTab(pageKey)
                        }
                    }
                }
            }
        }
    }

    // ── Abyss Panel Style Side Dock Primitives ──────────────────────────
    component AbyssSideCard: Rectangle {
        Layout.fillWidth: true
        radius: 12
        color: Qt.alpha(Appearance.colors.colLayer2, 0.46)
        border.width: 1
        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)
    }

    component AbyssSidePillButton: Rectangle {
        id: pillRoot
        property string iconName: ""
        property string labelText: ""
        property bool active: false
        property bool accentIdle: false
        property bool destructive: false
        property string tooltipText: ""
        signal clicked()

        activeFocusOnTab: true
        implicitHeight: Math.round(30 * Appearance.fontSizeScale)
        implicitWidth: Math.max(44, pillContentRow.implicitWidth + 16)
        height: implicitHeight
        radius: Math.round(implicitHeight / 2)
        opacity: pillRoot.enabled ? 1.0 : 0.42
        scale: pillMouse.pressed && pillRoot.enabled ? 0.96 : 1.0

        color: pillRoot.active
            ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.68)
            : (pillRoot.accentIdle
                ? Qt.alpha(Appearance.colors.colPrimary, pillMouse.containsMouse && pillRoot.enabled ? 0.26 : 0.16)
                : (pillMouse.containsMouse && pillRoot.enabled
                    ? (pillRoot.destructive
                        ? Qt.alpha(Appearance.colors.colError, 0.18)
                        : Qt.alpha(Appearance.colors.colOnLayer1, 0.10))
                    : Qt.alpha(Appearance.colors.colLayer3, 0.56)))
        border.width: 1
        border.color: pillRoot.activeFocus
            ? Appearance.colors.colPrimary
            : (pillRoot.active
                ? Qt.alpha(Appearance.colors.colPrimary, 0.44)
                : (pillRoot.accentIdle
                    ? Qt.alpha(Appearance.colors.colPrimary, 0.36)
                    : (pillRoot.destructive && pillMouse.containsMouse && pillRoot.enabled
                        ? Qt.alpha(Appearance.colors.colError, 0.40)
                        : Qt.alpha(Appearance.colors.colOutlineVariant, 0.22))))

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 100; easing.type: Easing.OutCubic }
        }

        Keys.onReturnPressed: event => {
            if (pillRoot.enabled) {
                pillRoot.clicked()
                event.accepted = true
            }
        }
        Keys.onEnterPressed: event => {
            if (pillRoot.enabled) {
                pillRoot.clicked()
                event.accepted = true
            }
        }
        Keys.onSpacePressed: event => {
            if (pillRoot.enabled) {
                pillRoot.clicked()
                event.accepted = true
            }
        }

        Row {
            id: pillContentRow
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                visible: pillRoot.iconName.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: pillRoot.iconName
                iconSize: 14 * Appearance.fontSizeScale
                fill: pillRoot.active ? 1 : 0
                color: pillRoot.active
                    ? Appearance.colors.colOnPrimaryContainer
                    : (pillRoot.accentIdle
                        ? Appearance.colors.colPrimary
                        : (pillRoot.destructive && pillMouse.containsMouse && pillRoot.enabled
                            ? Appearance.colors.colError
                            : Appearance.colors.colSubtext))
            }

            StyledText {
                visible: pillRoot.labelText.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: pillRoot.labelText
                width: Math.min(implicitWidth, Math.max(0, pillRoot.width - (pillRoot.iconName.length > 0 ? 26 : 12)))
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: (pillRoot.active || pillRoot.accentIdle) ? Font.DemiBold : Font.Medium
                color: pillRoot.active
                    ? Appearance.colors.colOnPrimaryContainer
                    : (pillRoot.destructive && pillMouse.containsMouse && pillRoot.enabled
                        ? Appearance.colors.colError
                        : Appearance.colors.colOnLayer1)
            }
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            enabled: pillRoot.enabled
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: pillRoot.clicked()
        }

        StyledToolTip {
            position: "top"
            extraVisibleCondition: pillMouse.containsMouse && pillRoot.tooltipText.length > 0
            text: pillRoot.tooltipText
        }
    }

    // ── Left Centered Edge Dock: Custom Tabs & Quick Switcher ────────────
    Rectangle {
        id: leftTabsDock
        objectName: "abyssLeftDashboardTabsDock"
        parent: (root.splitSideDocks && root.leftDockParent !== null && root.tabController !== null)
            ? root.leftDockParent : root
        x: 0
        y: 0
        width: parent ? parent.width : implicitWidth
        height: parent ? parent.height : implicitHeight
        z: 10
        visible: root.splitSideDocks && root.leftDockParent !== null && root.tabController !== null && root.visible
        enabled: root.enabled
        implicitWidth: Math.round(268 * Appearance.fontSizeScale)
        implicitHeight: Math.min(560, Math.ceil(leftTabsHeader.implicitHeight + 6 * Appearance.fontSizeScale + leftTabsScrollContent.implicitHeight + 16))
        radius: root.stageSideHosted ? 0 : (root.abyssMode ? AbyssStyle.perimeterRadius : Appearance.rounding.large)
        color: root.stageSideHosted
            ? "transparent"
            : (root.abyssMode
                ? Qt.alpha(AbyssStyle.surfaceDeep, Math.max(0.84, AbyssStyle.contentOpacity))
                : Appearance.colors.colLayer1)
        border.width: root.stageSideHosted ? 0 : 1
        border.color: root.stageSideHosted
            ? "transparent"
            : (root.abyssMode
                ? Qt.alpha(AbyssStyle.specular, 0.34 * AbyssStyle.highlightStrength)
                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.28))
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6 * Appearance.fontSizeScale

            RowLayout {
                id: leftTabsHeader
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "tab"
                    iconSize: 17 * Appearance.fontSizeScale
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: Translation.tr("Tabs")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: tabCountText.implicitWidth + 12
                    radius: 10
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.36)

                    StyledText {
                        id: tabCountText
                        anchors.centerIn: parent
                        text: String(root.tabController?.pageIds?.length ?? 0)
                        font.pixelSize: 9 * Appearance.fontSizeScale
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: leftTabsScrollContent.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: leftTabsScrollContent
                    width: parent.width
                    spacing: 8 * Appearance.fontSizeScale

                    AbyssSideCard {
                        implicitHeight: leftActionsCol.implicitHeight + 16

                        ColumnLayout {
                            id: leftActionsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 6 * Appearance.fontSizeScale

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                AbyssSidePillButton {
                                    objectName: root.splitSideDocks ? "dashboardToolbarActionCreateTab" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: "add"
                                    labelText: Translation.tr("New")
                                    accentIdle: true
                                    tooltipText: Translation.tr("Create custom tab")
                                    onClicked: root.tabController?.openCustomTabDialog("create", "")
                                }

                                AbyssSidePillButton {
                                    objectName: root.splitSideDocks ? "dashboardToolbarActionRenameTab" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: "drive_file_rename_outline"
                                    labelText: Translation.tr("Rename")
                                    enabled: root.targetCustomTabId.length > 0
                                    tooltipText: Translation.tr("Rename custom tab")
                                    onClicked: {
                                        if (root.targetCustomTabId.length > 0)
                                            root.tabController?.openCustomTabDialog("rename", root.targetCustomTabId)
                                    }
                                }

                                AbyssSidePillButton {
                                    objectName: root.splitSideDocks ? "dashboardToolbarActionDeleteTab" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: "delete_outline"
                                    labelText: Translation.tr("Delete")
                                    destructive: true
                                    enabled: root.targetCustomTabId.length > 0
                                    tooltipText: Translation.tr("Delete custom tab")
                                    onClicked: {
                                        if (root.targetCustomTabId.length > 0)
                                            root.tabController?.openCustomTabDialog("delete", root.targetCustomTabId)
                                    }
                                }
                            }

                            AbyssSidePillButton {
                                id: defaultTabButton
                                readonly property bool isDefaultPage:
                                    String(Config.options?.dashboard?.defaultTabId ?? "")
                                    === String(root.tabController?.currentPageId ?? "")
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                active: isDefaultPage
                                iconName: "push_pin"
                                labelText: isDefaultPage
                                    ? Translation.tr("Default tab")
                                    : Translation.tr("Pin default")
                                tooltipText: Translation.tr("Open this tab after inactivity")
                                onClicked: {
                                    const cur = String(root.tabController?.currentPageId ?? "")
                                    if (cur.length > 0)
                                        root.tabController?.setDefaultTab(cur)
                                }
                            }
                        }
                    }

                    AbyssSideCard {
                        implicitHeight: leftPagesCol.implicitHeight + 16

                        ColumnLayout {
                            id: leftPagesCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 5 * Appearance.fontSizeScale

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: Translation.tr("Pages")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }

                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: pageScopeLabel.implicitWidth + 10
                                    radius: 9
                                    color: Qt.alpha(Appearance.colors.colLayer3, 0.72)

                                    StyledText {
                                        id: pageScopeLabel
                                        anchors.centerIn: parent
                                        text: String(root.tabController?.currentPageId ?? "").startsWith("custom-")
                                            ? Translation.tr("Custom")
                                            : Translation.tr("Built-in")
                                        font.pixelSize: 9 * Appearance.fontSizeScale
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            Repeater {
                                model: root.tabController?.pageIds ?? []
                                delegate: Rectangle {
                                    id: pagePill
                                    required property var modelData
                                    readonly property string pageKey: String(modelData)
                                    readonly property bool current:
                                        String(root.tabController?.currentPageId ?? "") === pageKey
                                    readonly property bool isDefault:
                                        String(Config.options?.dashboard?.defaultTabId ?? "") === pageKey

                                    Layout.fillWidth: true
                                    implicitHeight: Math.round(30 * Appearance.fontSizeScale)
                                    radius: 10
                                    activeFocusOnTab: true
                                    color: current
                                        ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.68)
                                        : (pagePillMouse.containsMouse
                                            ? Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                            : Qt.alpha(Appearance.colors.colLayer3, 0.46))
                                    border.width: 1
                                    border.color: pagePill.activeFocus
                                        ? Appearance.colors.colPrimary
                                        : (current
                                            ? Qt.alpha(Appearance.colors.colPrimary, 0.44)
                                            : Qt.alpha(Appearance.colors.colOutlineVariant, 0.20))

                                    Behavior on color {
                                        enabled: Appearance.animationsEnabled
                                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                                    }

                                    Keys.onReturnPressed: event => {
                                        root.switchDashboardTab(pagePill.pageKey)
                                        event.accepted = true
                                    }
                                    Keys.onEnterPressed: event => {
                                        root.switchDashboardTab(pagePill.pageKey)
                                        event.accepted = true
                                    }
                                    Keys.onSpacePressed: event => {
                                        root.switchDashboardTab(pagePill.pageKey)
                                        event.accepted = true
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 9
                                        anchors.rightMargin: 9
                                        spacing: 6

                                        MaterialSymbol {
                                            text: root.pageIcon(pagePill.pageKey)
                                            iconSize: 15 * Appearance.fontSizeScale
                                            fill: pagePill.current ? 1 : 0
                                            color: pagePill.current
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colSubtext
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: root.pageTitle(pagePill.pageKey)
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            font.weight: pagePill.current ? Font.DemiBold : Font.Medium
                                            color: pagePill.current
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                        }

                                        MaterialSymbol {
                                            visible: pagePill.isDefault
                                            text: "push_pin"
                                            iconSize: 13 * Appearance.fontSizeScale
                                            color: pagePill.current
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colPrimary
                                        }
                                    }

                                    MouseArea {
                                        id: pagePillMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.switchDashboardTab(pagePill.pageKey)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Right Centered Edge Dock: Layout & Grid Inspector ────────────────
    Rectangle {
        id: rightLayoutDock
        objectName: "abyssRightDashboardLayoutDock"
        parent: (root.splitSideDocks && root.rightDockParent !== null && root.canvasController !== null)
            ? root.rightDockParent : root
        x: 0
        y: 0
        width: parent ? parent.width : implicitWidth
        height: parent ? parent.height : implicitHeight
        z: 10
        visible: root.splitSideDocks && root.rightDockParent !== null && root.canvasController !== null && root.visible
        enabled: root.enabled
        implicitWidth: Math.round(284 * Appearance.fontSizeScale)
        implicitHeight: Math.min(560, Math.ceil(rightLayoutHeader.implicitHeight + 6 * Appearance.fontSizeScale + rightLayoutScrollContent.implicitHeight + 16))
        radius: root.stageSideHosted ? 0 : (root.abyssMode ? AbyssStyle.perimeterRadius : Appearance.rounding.large)
        color: root.stageSideHosted
            ? "transparent"
            : (root.abyssMode
                ? Qt.alpha(AbyssStyle.surfaceDeep, Math.max(0.84, AbyssStyle.contentOpacity))
                : Appearance.colors.colLayer1)
        border.width: root.stageSideHosted ? 0 : 1
        border.color: root.stageSideHosted
            ? "transparent"
            : (root.abyssMode
                ? Qt.alpha(AbyssStyle.specular, 0.34 * AbyssStyle.highlightStrength)
                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.28))
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6 * Appearance.fontSizeScale

            RowLayout {
                id: rightLayoutHeader
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "grid_view"
                    iconSize: 17 * Appearance.fontSizeScale
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    elide: Text.ElideRight
                    text: Translation.tr("Layout & Grid")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: snapBadgeLabel.implicitWidth + 10
                    radius: 10
                    color: Qt.alpha(Appearance.colors.colPrimary, (root.canvasController?.snapEnabled ?? false) ? 0.16 : 0.08)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, (root.canvasController?.snapEnabled ?? false) ? 0.36 : 0.20)

                    StyledText {
                        id: snapBadgeLabel
                        anchors.centerIn: parent
                        text: (root.canvasController?.snapEnabled ?? false)
                            ? Translation.tr("SNAP")
                            : Translation.tr("FREE")
                        font.pixelSize: 9 * Appearance.fontSizeScale
                        font.weight: Font.DemiBold
                        color: (root.canvasController?.snapEnabled ?? false)
                            ? Appearance.colors.colPrimary
                            : Appearance.colors.colSubtext
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: rightLayoutScrollContent.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: rightLayoutScrollContent
                    width: parent.width
                    spacing: 8 * Appearance.fontSizeScale

                    AbyssSideCard {
                        implicitHeight: gridCardCol.implicitHeight + 16

                        ColumnLayout {
                            id: gridCardCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 6 * Appearance.fontSizeScale

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: Math.round(28 * Appearance.fontSizeScale)
                                radius: Math.round(implicitHeight / 2)
                                color: Qt.alpha(Appearance.colors.colLayer3, 0.56)
                                border.width: 1
                                border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    spacing: 2

                                    Repeater {
                                        model: [
                                            { key: "dots", label: Translation.tr("Dots"), icon: "drag_indicator" },
                                            { key: "lines", label: Translation.tr("Lines"), icon: "grid_4x4" },
                                            { key: "cross", label: Translation.tr("Cross"), icon: "add" }
                                        ]
                                        delegate: Rectangle {
                                            id: stylePill
                                            required property var modelData
                                            readonly property bool selectedStyle:
                                                String(root.canvasController?.gridStyle ?? "dots") === modelData.key

                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: 12
                                            color: selectedStyle
                                                ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.70)
                                                : (styleMouse.containsMouse
                                                    ? Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                                    : "transparent")

                                            Row {
                                                anchors.centerIn: parent
                                                spacing: 4

                                                MaterialSymbol {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: stylePill.modelData.icon
                                                    iconSize: 13 * Appearance.fontSizeScale
                                                    color: stylePill.selectedStyle
                                                        ? Appearance.colors.colOnPrimaryContainer
                                                        : Appearance.colors.colSubtext
                                                }

                                                StyledText {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: stylePill.modelData.label
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    font.weight: stylePill.selectedStyle ? Font.DemiBold : Font.Medium
                                                    color: stylePill.selectedStyle
                                                        ? Appearance.colors.colOnPrimaryContainer
                                                        : Appearance.colors.colSubtext
                                                }
                                            }

                                            MouseArea {
                                                id: styleMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectGridStyle(stylePill.modelData.key)
                                            }
                                        }
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                MaterialSymbol {
                                    text: "space_bar"
                                    iconSize: 15 * Appearance.fontSizeScale
                                    color: Appearance.colors.colSubtext
                                }

                                StyledText {
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: Translation.tr("Spacing")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                StyledSlider {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 72 * Appearance.fontSizeScale
                                    from: 8
                                    to: 64
                                    stepSize: 4
                                    value: root.canvasController?.gridSize ?? 24
                                    configuration: StyledSlider.Configuration.S
                                    onMoved: {
                                        if (root.canvasController?.setGridSize)
                                            root.canvasController.setGridSize(value)
                                        else if (root.canvasController)
                                            root.canvasController._cycleGridSize()
                                    }
                                }

                                Rectangle {
                                    objectName: root.splitSideDocks ? "dashboardLayoutGridSizeCard" : ""
                                    implicitHeight: 22
                                    implicitWidth: gridPxText.implicitWidth + 12
                                    radius: 11
                                    activeFocusOnTab: true
                                    color: gridPxMouse.containsMouse
                                        ? Qt.alpha(Appearance.colors.colPrimary, 0.22)
                                        : Qt.alpha(Appearance.colors.colLayer3, 0.72)
                                    border.width: 1
                                    border.color: gridPxMouse.containsMouse
                                        ? Qt.alpha(Appearance.colors.colPrimary, 0.40)
                                        : Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                                    StyledText {
                                        id: gridPxText
                                        anchors.centerIn: parent
                                        text: Translation.tr("%1 px").arg(root.canvasController?.gridSize ?? 24)
                                        font.pixelSize: 9 * Appearance.fontSizeScale
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colPrimary
                                    }

                                    MouseArea {
                                        id: gridPxMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.canvasController?._cycleGridSize()
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                AbyssSidePillButton {
                                    objectName: root.splitSideDocks ? "dashboardLayoutSnapCard" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: (root.canvasController?.snapEnabled ?? false) ? "grid_on" : "grid_off"
                                    labelText: Translation.tr("Snap")
                                    active: root.canvasController?.snapEnabled ?? false
                                    tooltipText: active
                                        ? Translation.tr("Snap to grid: on")
                                        : Translation.tr("Snap to grid: off")
                                    onClicked: root.canvasController?.toggleSnap()
                                }

                                AbyssSidePillButton {
                                    visible: !(root.canvasController?.responsiveWorkspace ?? false)
                                    objectName: root.splitSideDocks ? "dashboardLayoutAutoFitCard" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: "fit_screen"
                                    labelText: Translation.tr("Auto-fit")
                                    active: root.canvasController?.autoAdjustSizeEnabled ?? true
                                    tooltipText: active
                                        ? Translation.tr("Auto-adjust affected module sizes: on")
                                        : Translation.tr("Auto-adjust affected module sizes: off")
                                    onClicked: {
                                        if (root.canvasController)
                                            root.canvasController.toggleAutoAdjustSize()
                                    }
                                }
                            }
                        }
                    }

                    AbyssSideCard {
                        implicitHeight: canvasActionsCol.implicitHeight + 16

                        ColumnLayout {
                            id: canvasActionsCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 8
                            spacing: 6 * Appearance.fontSizeScale

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    elide: Text.ElideRight
                                    text: Translation.tr("Canvas")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }

                                Rectangle {
                                    implicitHeight: 18
                                    implicitWidth: hiddenCountLabel.implicitWidth + 10
                                    radius: 9
                                    color: Qt.alpha(Appearance.colors.colLayer3, 0.72)

                                    StyledText {
                                        id: hiddenCountLabel
                                        anchors.centerIn: parent
                                        text: root.hiddenIds.length > 0
                                            ? Translation.tr("%1 hidden").arg(root.hiddenIds.length)
                                            : Translation.tr("All placed")
                                        font.pixelSize: 9 * Appearance.fontSizeScale
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                AbyssSidePillButton {
                                    objectName: root.splitSideDocks ? "dashboardLayoutFitAllCard" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: "auto_awesome_motion"
                                    labelText: Translation.tr("Smart Fit")
                                    enabled: root.hiddenIds.length > 0
                                    tooltipText: Translation.tr("Add all modules and fit them automatically")
                                    onClicked: root.canvasController?.fitAllWidgets()
                                }

                                AbyssSidePillButton {
                                    objectName: root.splitSideDocks ? "dashboardLayoutResetCard" : ""
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    iconName: "restart_alt"
                                    labelText: Translation.tr("Reset")
                                    destructive: true
                                    tooltipText: Translation.tr("Reset dashboard layout")
                                    onClicked: root.canvasController?.resetLayout()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Reusable Miniature Preview Artwork for Dashboard Modules ─────────
    component ModuleMiniPreview: Rectangle {
        id: previewRoot
        property string moduleId: ""
        property color accentColor: Appearance.colors.colPrimary
        property string moduleIcon: "widgets"

        radius: 8
        color: Qt.alpha(previewRoot.accentColor, 0.08)
        border.width: 1
        border.color: Qt.alpha(previewRoot.accentColor, 0.20)
        clip: true

        // Clock miniature
        Column {
            visible: previewRoot.moduleId === "clock"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 9
            spacing: 2

            StyledText {
                text: "12:45"
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.Bold
                color: Appearance.colors.colOnLayer1
            }
            Rectangle {
                width: 42
                height: 4
                radius: 2
                color: Qt.alpha(previewRoot.accentColor, 0.65)
            }
        }

        // Weather miniature
        Row {
            visible: previewRoot.moduleId === "weather"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 9
            spacing: 6

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                text: "partly_cloudy_day"
                iconSize: 20
                fill: 1
                color: previewRoot.accentColor
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                StyledText {
                    text: "22°"
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer1
                }
                Rectangle {
                    width: 34
                    height: 4
                    radius: 2
                    color: Qt.alpha(previewRoot.accentColor, 0.50)
                }
            }
        }

        // System telemetry miniature
        Row {
            visible: previewRoot.moduleId === "system"
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 6

            Repeater {
                model: [0.72, 0.48, 0.86, 0.60]
                delegate: Rectangle {
                    required property var modelData
                    width: 12
                    height: Math.max(8, Math.round((previewRoot.height - 18) * Number(modelData)))
                    anchors.bottom: parent.bottom
                    radius: 3
                    color: Qt.alpha(previewRoot.accentColor, 0.35 + Number(modelData) * 0.45)
                }
            }
        }

        // Media player miniature
        Row {
            visible: previewRoot.moduleId === "media"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 7

            Rectangle {
                width: 28
                height: 28
                radius: 7
                color: Qt.alpha(previewRoot.accentColor, 0.26)
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "music_note"
                    iconSize: 15
                    color: previewRoot.accentColor
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Rectangle {
                    width: 40
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.62)
                }
                Row {
                    spacing: 3
                    Repeater {
                        model: [8, 13, 6, 11, 7]
                        delegate: Rectangle {
                            required property var modelData
                            width: 4
                            height: Number(modelData)
                            anchors.bottom: parent.bottom
                            radius: 2
                            color: Qt.alpha(previewRoot.accentColor, 0.72)
                        }
                    }
                }
            }
        }

        // Calendar miniature
        Grid {
            visible: previewRoot.moduleId === "calendar"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            columns: 5
            spacing: 4

            Repeater {
                model: 15
                delegate: Rectangle {
                    required property int index
                    width: 8
                    height: 6
                    radius: 2
                    color: index === 6
                        ? previewRoot.accentColor
                        : Qt.alpha(Appearance.colors.colOnLayer1, index < 5 ? 0.38 : 0.18)
                }
            }
        }

        // GitHub contribution heatmap miniature
        Grid {
            visible: previewRoot.moduleId === "github"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            columns: 6
            spacing: 3

            Repeater {
                model: [0.2, 0.75, 0.4, 0.9, 0.2, 0.55, 0.65, 0.2, 0.85, 0.35, 0.7, 0.25, 0.3, 0.9, 0.5, 0.2, 0.8, 0.6]
                delegate: Rectangle {
                    required property var modelData
                    width: 8
                    height: 8
                    radius: 2
                    color: Qt.alpha(previewRoot.accentColor, Number(modelData))
                }
            }
        }

        // Todo / Agenda / Notes / Notifications / Welcome clean structured miniature
        Row {
            visible: previewRoot.moduleId !== "clock"
                && previewRoot.moduleId !== "weather"
                && previewRoot.moduleId !== "system"
                && previewRoot.moduleId !== "media"
                && previewRoot.moduleId !== "calendar"
                && previewRoot.moduleId !== "github"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 24
            spacing: 7

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 26
                radius: previewRoot.moduleId === "welcome" ? 13 : 7
                color: Qt.alpha(previewRoot.accentColor, 0.22)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: previewRoot.moduleIcon
                    iconSize: 15
                    fill: 1
                    color: previewRoot.accentColor
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                width: Math.max(16, parent.width - 34)

                Rectangle {
                    width: Math.min(parent.width, 46)
                    height: 5
                    radius: 2.5
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.58)
                }
                Rectangle {
                    width: Math.min(parent.width, 34)
                    height: 4
                    radius: 2
                    color: Qt.alpha(previewRoot.accentColor, 0.52)
                }
                Rectangle {
                    width: Math.min(parent.width, 40)
                    height: 4
                    radius: 2
                    color: Qt.alpha(Appearance.colors.colSubtext, 0.34)
                }
            }
        }
    }

    // ── Reusable Abyss Control Card for Layout & Tabs Trays ──────────────
    component DockControlCard: RippleButton {
        id: card
        property string iconName: "tune"
        property string titleText: ""
        property string subtitleText: ""
        property string tooltipText: ""
        property real cardHeight: 90

        implicitWidth: Math.max(134, cardRow.implicitWidth + 26)
        implicitHeight: card.cardHeight
        focusPolicy: Qt.StrongFocus
        buttonRadius: Math.min(14, Appearance.rounding.normal)
        opacity: card.enabled ? 1.0 : 0.42
        colBackground: root.abyssMode
            ? Qt.alpha(AbyssStyle.surfaceRaised, 0.72)
            : Qt.alpha(Appearance.colors.colLayer2, 0.76)
        colBackgroundHover: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.16)
            : Appearance.colors.colLayer2Hover
        colBackgroundToggled: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.24)
            : Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.32)
            : Appearance.colors.colPrimaryContainer
        colRippleToggled: root.abyssMode
            ? AbyssStyle.accent : Appearance.colors.colPrimary

        contentItem: Item {
            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight

            Rectangle {
                anchors.fill: parent
                radius: card.buttonRadius
                color: "transparent"
                border.width: card.visualFocus ? 2 : 1
                border.color: card.visualFocus
                    ? (root.abyssMode ? AbyssStyle.accent : Appearance.colors.colPrimary)
                    : (card.toggled
                        ? Qt.alpha(root.abyssMode ? AbyssStyle.accent : Appearance.colors.colPrimary, 0.56)
                        : Qt.alpha(Appearance.colors.colOutlineVariant, 0.28))
            }

            Row {
                id: cardRow
                anchors.centerIn: parent
                spacing: 10

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 10
                    color: card.toggled
                        ? Qt.alpha(root.abyssMode ? AbyssStyle.accent : Appearance.colors.colPrimary, 0.24)
                        : Qt.alpha(Appearance.colors.colLayer3, 0.72)

                    MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: card.iconName
                        iconSize: 17
                        fill: card.toggled ? 1 : 0
                        color: card.toggled
                            ? (root.abyssMode ? AbyssStyle.accent : Appearance.colors.colOnPrimaryContainer)
                            : Appearance.colors.colOnLayer1
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        text: card.titleText
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledText {
                        visible: card.subtitleText.length > 0
                        text: card.subtitleText
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: card.toggled
                            ? (root.abyssMode ? AbyssStyle.accent : Appearance.colors.colOnPrimaryContainer)
                            : Appearance.colors.colSubtext
                    }
                }
            }
        }

        StyledToolTip {
            position: "top"
            text: card.tooltipText
        }
    }

    // ── Compact Circular Quick-Action Icon Button ────────────────────────
    component EditToolButton: RippleButton {
        id: tool
        property alias iconName: toolIcon.text
        property string tooltipText: ""

        implicitWidth: 32
        implicitHeight: 32
        Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
        focusPolicy: Qt.StrongFocus
        buttonText: tool.tooltipText
        buttonRadius: Appearance.rounding.full
        colBackground: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.10)
            : Appearance.colors.colLayer1
        colBackgroundHover: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.18)
            : Appearance.colors.colLayer2
        colBackgroundToggled: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.28)
            : Appearance.colors.colPrimaryContainer
        colBackgroundToggledHover: root.abyssMode
            ? Qt.alpha(AbyssStyle.accent, 0.34)
            : Appearance.colors.colPrimaryContainer
        colRippleToggled: root.abyssMode
            ? AbyssStyle.accent : Appearance.colors.colPrimary

        contentItem: Item {
            implicitWidth: tool.implicitWidth
            implicitHeight: tool.implicitHeight
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Appearance.rounding.full
                color: "transparent"
                border.width: tool.visualFocus ? 2 : (tool.toggled ? 1 : 0)
                border.color: tool.visualFocus
                    ? (root.abyssMode
                        ? AbyssStyle.accent : Appearance.colors.colPrimary)
                    : ColorUtils.applyAlpha(
                        root.abyssMode
                            ? AbyssStyle.accent
                            : Appearance.colors.colPrimary, 0.72)
            }

            MaterialSymbol {
                id: toolIcon
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                iconSize: Appearance.font.pixelSize.normal
                color: root.abyssMode
                    ? (tool.toggled
                        ? AbyssStyle.accent : AbyssStyle.textColor)
                    : (tool.toggled
                        ? Appearance.colors.colOnPrimaryContainer
                        : Appearance.colors.colOnLayer1)
            }
        }

        StyledToolTip {
            position: "top"
            text: tool.tooltipText
        }
    }
}
