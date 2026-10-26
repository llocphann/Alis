import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: root

    function _log(...args): void {
        if (Quickshell.env("QS_DEBUG") === "1") console.log(...args);
    }

    property var pinnedDragInfo: null
    property int pinnedDropIndex: -1
    readonly property bool pinnedDragging: pinnedDragInfo !== null

    function commitPinnedDrop(): void {
        if (!root.pinnedDragInfo || root.pinnedDropIndex < 0) {
            root.pinnedDragInfo = null
            root.pinnedDropIndex = -1
            return
        }
        const values = [...(Config.options?.dock?.pinnedApps ?? [])]
        const fromIndex = root.pinnedDragInfo.index
        const toIndex = root.pinnedDropIndex
        if (fromIndex >= 0 && fromIndex < values.length
                && toIndex >= 0 && toIndex < values.length
                && fromIndex !== toIndex) {
            const moved = values.splice(fromIndex, 1)[0]
            values.splice(toIndex, 0, moved)
            Config.setNestedValue("dock.pinnedApps", values)
        }
        root.pinnedDragInfo = null
        root.pinnedDropIndex = -1
    }

    function pinnedAppLabel(appId: string): string {
        return AppSearch.lookupDesktopEntry(appId)?.name ?? appId
    }

    function pinnedAppIcon(appId: string): string {
        const entry = AppSearch.lookupDesktopEntry(appId)
        const icon = entry?.icon || AppSearch.guessIcon(appId)
        const resolved = IconThemeService.smartIconName(icon, appId)
        if (resolved.startsWith("/") || resolved.startsWith("file://"))
            return resolved.startsWith("file://") ? resolved : `file://${resolved}`
        return Quickshell.iconPath(resolved, "application-x-executable")
    }

    function isPinnedVisible(appId: string): bool {
        const lowerId = String(appId ?? "").toLowerCase()
        const hidden = Config.options?.dock?.hiddenPinnedApps ?? []
        return !hidden.some(id => String(id ?? "").toLowerCase() === lowerId)
    }

    function togglePinnedVisibility(appId: string): void {
        const lowerId = String(appId ?? "").toLowerCase()
        if (!lowerId) return
        const hidden = [...(Config.options?.dock?.hiddenPinnedApps ?? [])]
        const index = hidden.findIndex(id => String(id ?? "").toLowerCase() === lowerId)
        if (index >= 0) hidden.splice(index, 1)
        else hidden.push(lowerId)
        Config.setNestedValue("dock.hiddenPinnedApps", hidden)
    }

    function removePinnedApp(appId: string): void {
        const lowerId = String(appId ?? "").toLowerCase()
        if (!lowerId) return
        const pinned = [...(Config.options?.dock?.pinnedApps ?? [])]
            .filter(id => String(id ?? "").toLowerCase() !== lowerId)
        const hidden = [...(Config.options?.dock?.hiddenPinnedApps ?? [])]
            .filter(id => String(id ?? "").toLowerCase() !== lowerId)
        Config.setNestedValues({
            "dock.pinnedApps": pinned,
            "dock.hiddenPinnedApps": hidden
        })
    }

    function addPinnedApp(appId: string): void {
        const id = String(appId ?? "").trim()
        if (!id) return
        const lowerId = id.toLowerCase()
        const pinned = [...(Config.options?.dock?.pinnedApps ?? [])]
        if (!pinned.some(existing => String(existing ?? "").toLowerCase() === lowerId))
            pinned.push(id)
        const hidden = [...(Config.options?.dock?.hiddenPinnedApps ?? [])]
            .filter(existing => String(existing ?? "").toLowerCase() !== lowerId)
        Config.setNestedValues({
            "dock.pinnedApps": pinned,
            "dock.hiddenPinnedApps": hidden
        })
    }

    function filteredAddApps(): var {
        const query = pinnedAppSearchField.text.toLowerCase().trim()
        const pinned = new Set((Config.options?.dock?.pinnedApps ?? [])
            .map(id => String(id ?? "").toLowerCase()))
        const result = []
        for (const app of (AppSearch.list ?? [])) {
            const id = String(app?.id ?? "").trim()
            if (!id || pinned.has(id.toLowerCase())) continue
            const haystack = [
                app?.name ?? "",
                app?.genericName ?? "",
                app?.comment ?? "",
                id
            ].join(" ").toLowerCase()
            if (query && !haystack.includes(query)) continue
            result.push(app)
        }
        result.sort((a, b) => String(a?.name ?? a?.id ?? "")
            .localeCompare(String(b?.name ?? b?.id ?? "")))
        return result
    }

    settingsPageIndex: embedded ? 2 : 22
    settingsPageName: Translation.tr("Dock")

    property bool isIiActive: Config.options?.panelFamily !== "waffle"
    property bool addApplicationsOpen: false

    SettingsCardSection {
        visible: root.isIiActive
        expanded: true
        icon: "call_to_action"
        title: Translation.tr("Dock")

        SettingsGroup {
            GridLayout {
                objectName: "dockTwoColumnGrid"
                Layout.fillWidth: true
                columns: width >= 620 ? 2 : 1
                columnSpacing: 14
                rowSpacing: 14

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 12

                    ConfigRow {
                        id: dockPrimaryToggles
                        uniform: true

                        SettingsSwitch {
                            buttonIcon: "check"
                            text: Translation.tr("Enable")
                            checked: Config.options.dock.enable
                            onCheckedChanged: Config.setNestedValue("dock.enable", checked)
                            StyledToolTip { text: Translation.tr("Show the application dock") }
                        }

                        SettingsSwitch {
                            buttonIcon: "dashboard"
                            text: Translation.tr("Show Dashboard icon")
                            checked: Config.options?.dock?.showDashboardButton ?? true
                            onCheckedChanged: Config.setNestedValue("dock.showDashboardButton", checked)
                            StyledToolTip {
                                text: Translation.tr("Show the Dashboard / Overview launcher button in the Dock")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "colors"
                            text: Translation.tr("Tint app icons")
                            checked: Config.options.dock.monochromeIcons
                            onCheckedChanged: Config.setNestedValue("dock.monochromeIcons", checked)
                            StyledToolTip {
                                text: Translation.tr("Apply accent color tint to dock app icons")
                            }
                        }
                    }

                    SettingsNote {
                        icon: "dock_to_bottom"
                        text: Config.options?.panelFamily === "abyss" ? "The Dock shares the Abyss Screen Edge surface." : Translation.tr("Dock uses the Panel surface style.")
                    }

                    ConfigRow {
                        uniform: true
                        ContentSubsection {
                            title: Translation.tr("Dock position")

                            ConfigSelectionArray {
                                currentValue: Config.options?.dock?.position ?? "bottom"
                                onSelected: newValue => {
                                    Config.setNestedValue('dock.position', newValue);
                                }
                                options: [
                                    { displayName: Translation.tr("Left"), icon: "arrow_back", value: "left" },
                                    { displayName: Translation.tr("Top"), icon: "arrow_upward", value: "top" },
                                    { displayName: Translation.tr("Bottom"), icon: "arrow_downward", value: "bottom" },
                                    { displayName: Translation.tr("Right"), icon: "arrow_forward", value: "right" }
                                ]
                            }
                        }
                        ContentSubsection {
                            title: Translation.tr("Reveal behavior")
                            tooltip: Translation.tr("Hover reveals the Dock at the edge; Empty workspace shows it on an empty desktop.")

                            ConfigSelectionArray {
                                currentValue: Config.options?.dock?.hoverToReveal ?? true
                                onSelected: newValue => {
                                    Config.setNestedValue('dock.hoverToReveal', newValue);
                                }
                                options: [
                                    { displayName: Translation.tr("Hover"), icon: "highlight_mouse_cursor", value: true },
                                    { displayName: Translation.tr("Empty workspace"), icon: "desktop_windows", value: false }
                                ]
                            }
                            ConfigRow {
                                id: revealModeToggles
                                uniform: true

                                SettingsSwitch {
                                    buttonIcon: "desktop_windows"
                                    text: Translation.tr("Show on desktop")
                                    enabled: !(Config.options?.dock?.hoverToReveal ?? true)
                                    checked: Config.options?.dock?.showOnDesktop ?? true
                                    onCheckedChanged: Config.setNestedValue("dock.showOnDesktop", checked)
                                    StyledToolTip {
                                        text: Translation.tr("Show dock when no window is focused (Empty workspace mode only)")
                                    }
                                }

                                SettingsSwitch {
                                    buttonIcon: "keep"
                                    text: Translation.tr("Pinned on startup")
                                    enabled: !(Config.options?.dock?.hoverToReveal ?? true)
                                    checked: Config.options.dock.pinnedOnStartup
                                    onCheckedChanged: Config.setNestedValue("dock.pinnedOnStartup", checked)
                                    StyledToolTip {
                                        text: Translation.tr("Keep dock visible at all times (Empty workspace mode only)")
                                    }
                                }
                            }
                        }
                    }

                    ConfigRow {
                        id: dockSecondaryToggles
                        uniform: true

                        SettingsSwitch {
                            buttonIcon: "widgets"
                            visible: Config.options?.panelFamily !== "abyss"
                            text: Translation.tr("Show dock background")
                            checked: Config.options.dock.showBackground
                            onCheckedChanged: Config.setNestedValue("dock.showBackground", checked)
                            StyledToolTip {
                                text: Translation.tr("Show a background behind the dock")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "splitscreen"
                            text: Translation.tr("Separate pinned from running")
                            checked: Config.options?.dock?.separatePinnedFromRunning ?? true
                            onCheckedChanged: Config.setNestedValue("dock.separatePinnedFromRunning", checked)
                            StyledToolTip {
                                text: Translation.tr("Show pinned-only apps on the left, running apps on the right with a separator")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "notifications"
                            text: Translation.tr("Notification badges")
                            checked: Config.options?.dock?.notificationBadge ?? true
                            onCheckedChanged: Config.setNestedValue("dock.notificationBadge", checked)
                            StyledToolTip {
                                text: Translation.tr("Show the number of pending notifications on each app icon")
                            }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Appearance")

                        ConfigSpinBox {
                            icon: "height"
                            text: Translation.tr("Dock height (px)")
                            value: Config.options.dock.height ?? 60
                            from: 40
                            to: 100
                            stepSize: 5
                            onValueChanged: {
                                Config.setNestedValue("dock.height", value);
                            }
                            StyledToolTip {
                                text: Translation.tr("Height of the dock container")
                            }
                        }

                        ConfigSpinBox {
                            icon: "aspect_ratio"
                            text: Translation.tr("Icon size (px)")
                            value: Config.options.dock.iconSize ?? 35
                            from: 20
                            to: 60
                            stepSize: 5
                            onValueChanged: {
                                Config.setNestedValue("dock.iconSize", value);
                            }
                            StyledToolTip {
                                text: Translation.tr("Size of application icons in the dock")
                            }
                        }

                        ConfigSpinBox {
                            icon: {
                                const pos = Config.options?.dock?.position ?? "bottom"
                                switch (pos) {
                                    case "top": return "vertical_align_top"
                                    case "left": return "align_horizontal_left"
                                    case "right": return "align_horizontal_right"
                                    default: return "vertical_align_bottom"
                                }
                            }
                            text: Translation.tr("Hover reveal region size (px)")
                            value: Config.options.dock.hoverRegionHeight ?? 2
                            from: 1
                            to: 20
                            stepSize: 1
                            enabled: Config.options.dock.hoverToReveal
                            onValueChanged: {
                                Config.setNestedValue("dock.hoverRegionHeight", value);
                            }
                            StyledToolTip {
                                text: Translation.tr("Size of the invisible area at screen edge that triggers dock reveal")
                            }
                        }
                    }

                    ContentSubsection {
                        title: Translation.tr("Window indicators")

                        SettingsSwitch {
                            buttonIcon: "my_location"
                            text: Translation.tr("Smart indicator (highlight focused window)")
                            checked: Config.options.dock.smartIndicator !== false
                            onCheckedChanged: {
                                Config.setNestedValue("dock.smartIndicator", checked);
                            }
                            StyledToolTip {
                                text: Translation.tr("When multiple windows of the same app are open, highlight which one is focused")
                            }
                        }

                        SettingsSwitch {
                            buttonIcon: "more_horiz"
                            text: Translation.tr("Show dots for inactive apps")
                            checked: Config.options.dock.showAllWindowDots !== false
                            onCheckedChanged: {
                                Config.setNestedValue("dock.showAllWindowDots", checked);
                            }
                            StyledToolTip {
                                text: Translation.tr("Show a dot per window even for apps that aren't currently focused")
                            }
                        }

                        ConfigSpinBox {
                            icon: "filter_5"
                            text: Translation.tr("Maximum indicator dots")
                            value: Config.options.dock.maxIndicatorDots ?? 5
                            from: 1
                            to: 10
                            stepSize: 1
                            onValueChanged: {
                                Config.setNestedValue("dock.maxIndicatorDots", value);
                            }
                            StyledToolTip {
                                text: Translation.tr("Limit the number of open window dots shown below an app icon")
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 12

                    ContentSubsection {
                        title: Translation.tr("Pinned apps")

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Drag to reorder · eye hides · minus removes.")
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.WordWrap
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: Config.options?.dock?.pinnedApps ?? []

                                delegate: Item {
                                    id: pinnedSlot
                                    required property var modelData
                                    required property int index
                                    readonly property string appId: String(modelData ?? "")
                                    Layout.fillWidth: true
                                    implicitHeight: 42
                                    clip: false

                                    DropArea {
                                        anchors.fill: parent
                                        keys: ["alis-dock-pinned-app"]
                                        enabled: root.pinnedDragging
                                        onEntered: drag => {
                                            if (drag.source && drag.source.appId !== pinnedSlot.appId)
                                                root.pinnedDropIndex = pinnedSlot.index
                                        }
                                    }

                                    Rectangle {
                                        id: pinnedRow
                                        property string appId: pinnedSlot.appId
                                        width: pinnedSlot.width
                                        height: 42
                                        x: 0
                                        y: 0
                                        z: pinnedHandle.drag.active ? 100 : 1
                                        radius: Appearance.rounding.small
                                        color: pinnedHandle.containsMouse || pinnedHandle.drag.active
                                            ? Appearance.colors.colLayer1Hover
                                            : Appearance.colors.colLayer1
                                        border.width: root.pinnedDragging
                                            && root.pinnedDropIndex === pinnedSlot.index ? 1 : 0
                                        border.color: Appearance.colors.colPrimary
                                        opacity: root.isPinnedVisible(pinnedSlot.appId) ? 1 : 0.62

                                        Drag.active: pinnedHandle.drag.active
                                        Drag.source: pinnedRow
                                        Drag.keys: ["alis-dock-pinned-app"]
                                        Drag.hotSpot.x: width / 2
                                        Drag.hotSpot.y: height / 2

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            Item {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 28

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "drag_indicator"
                                                    iconSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colSubtext
                                                }

                                                MouseArea {
                                                    id: pinnedHandle
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: drag.active
                                                        ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                                                    drag.target: pinnedRow
                                                    drag.axis: Drag.YAxis
                                                    drag.minimumY: -pinnedSlot.index * 48
                                                    drag.maximumY: ((Config.options?.dock?.pinnedApps?.length ?? 0)
                                                        - pinnedSlot.index - 1) * 48
                                                    onPressed: {
                                                        root.pinnedDragInfo = {
                                                            id: pinnedSlot.appId,
                                                            index: pinnedSlot.index
                                                        }
                                                        root.pinnedDropIndex = pinnedSlot.index
                                                    }
                                                    onReleased: {
                                                        pinnedRow.Drag.drop()
                                                        root.commitPinnedDrop()
                                                        pinnedRow.y = 0
                                                    }
                                                    onCanceled: {
                                                        root.pinnedDragInfo = null
                                                        root.pinnedDropIndex = -1
                                                        pinnedRow.y = 0
                                                    }
                                                }
                                            }

                                            IconImage {
                                                Layout.preferredWidth: 26
                                                Layout.preferredHeight: 26
                                                source: root.pinnedAppIcon(pinnedSlot.appId)
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: root.pinnedAppLabel(pinnedSlot.appId)
                                                    color: Appearance.colors.colOnLayer1
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: pinnedSlot.appId
                                                    color: Appearance.colors.colSubtext
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            RippleButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                buttonRadius: Appearance.rounding.full
                                                Accessible.name: root.isPinnedVisible(pinnedSlot.appId)
                                                    ? Translation.tr("Hide from Dock")
                                                    : Translation.tr("Show in Dock")
                                                onClicked: root.togglePinnedVisibility(pinnedSlot.appId)
                                                contentItem: MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: root.isPinnedVisible(pinnedSlot.appId)
                                                        ? "visibility" : "visibility_off"
                                                    iconSize: Appearance.font.pixelSize.normal
                                                    color: root.isPinnedVisible(pinnedSlot.appId)
                                                        ? Appearance.colors.colPrimary
                                                        : Appearance.colors.colSubtext
                                                }
                                                StyledToolTip {
                                                    text: root.isPinnedVisible(pinnedSlot.appId)
                                                        ? Translation.tr("Hide from Dock")
                                                        : Translation.tr("Show in Dock")
                                                }
                                            }

                                            RippleButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                buttonRadius: Appearance.rounding.full
                                                Accessible.name: Translation.tr("Remove from Dock")
                                                onClicked: root.removePinnedApp(pinnedSlot.appId)
                                                contentItem: MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "remove_circle"
                                                    iconSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colSubtext
                                                }
                                                StyledToolTip { text: Translation.tr("Remove from Dock") }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            Layout.leftMargin: 8
                            Layout.rightMargin: 6
                            spacing: 8

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Add applications")
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                            }

                            RippleButton {
                                id: addApplicationsToggle
                                implicitWidth: 30
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.full
                                Accessible.name: root.addApplicationsOpen
                                    ? Translation.tr("Close application picker")
                                    : Translation.tr("Add applications")
                                onClicked: {
                                    root.addApplicationsOpen = !root.addApplicationsOpen
                                    if (root.addApplicationsOpen)
                                        Qt.callLater(() => pinnedAppSearchField.forceActiveFocus())
                                    else
                                        pinnedAppSearchField.text = ""
                                }

                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: root.addApplicationsOpen ? "close" : "add"
                                    iconSize: Appearance.font.pixelSize.normal
                                    color: root.addApplicationsOpen
                                        ? Appearance.colors.colOnLayer1
                                        : Appearance.colors.colPrimary
                                }

                                StyledToolTip {
                                    text: root.addApplicationsOpen
                                        ? Translation.tr("Close application picker")
                                        : Translation.tr("Add applications")
                                }
                            }
                        }

                        Item {
                            id: addApplicationsPanel
                            Layout.fillWidth: true
                            implicitHeight: root.addApplicationsOpen
                                ? addApplicationsContent.implicitHeight : 0
                            opacity: root.addApplicationsOpen ? 1 : 0
                            clip: true
                            enabled: root.addApplicationsOpen

                            Behavior on implicitHeight {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementResize.duration
                                    easing.type: Easing.OutCubic
                                }
                            }
                            Behavior on opacity {
                                enabled: Appearance.animationsEnabled
                                NumberAnimation {
                                    duration: Appearance.animation.elementMoveFast.duration
                                    easing.type: Easing.OutCubic
                                }
                            }

                            ColumnLayout {
                                id: addApplicationsContent
                                width: parent.width
                                spacing: 4

                                MaterialTextField {
                                    id: pinnedAppSearchField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    placeholderText: Translation.tr("Search applications...")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }

                                ListView {
                                    id: pinnedAppSearchList
                                    Layout.fillWidth: true
                                    implicitHeight: Math.min(184, Math.max(44, contentHeight))
                                    clip: true
                                    model: root.addApplicationsOpen ? root.filteredAddApps() : []
                                    boundsBehavior: Flickable.StopAtBounds
                                    spacing: 2

                                    PagePlaceholder {
                                        shown: pinnedAppSearchList.count === 0
                                        icon: "search_off"
                                        title: Translation.tr("No matching apps")
                                        description: Translation.tr("Try a different search term.")
                                        anchors.fill: parent
                                    }

                                    delegate: Item {
                                        id: addAppDelegate
                                        required property var modelData
                                        required property int index
                                        width: pinnedAppSearchList.width
                                        height: 42

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: Appearance.rounding.small
                                            color: addAppHover.hovered
                                                ? Appearance.colors.colLayer1Hover : "transparent"
                                        }
                                        HoverHandler { id: addAppHover }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            Item {
                                                Layout.preferredWidth: 26
                                                Layout.preferredHeight: 26

                                                Image {
                                                    id: addAppIcon
                                                    anchors.fill: parent
                                                    source: AppSearch.getIconSource(
                                                        addAppDelegate.modelData?.icon ?? "",
                                                        addAppDelegate.modelData?.name ?? "")
                                                    sourceSize.width: 52
                                                    sourceSize.height: 52
                                                    fillMode: Image.PreserveAspectFit
                                                }
                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    visible: addAppIcon.status !== Image.Ready
                                                    text: "apps"
                                                    iconSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colOnLayer1
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                spacing: 0

                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: addAppDelegate.modelData?.name
                                                        ?? addAppDelegate.modelData?.id ?? ""
                                                    font.pixelSize: Appearance.font.pixelSize.small
                                                    color: Appearance.colors.colOnLayer1
                                                    elide: Text.ElideRight
                                                }
                                                StyledText {
                                                    Layout.fillWidth: true
                                                    text: String(addAppDelegate.modelData?.id ?? "")
                                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                                    color: Appearance.colors.colSubtext
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            RippleButton {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                buttonRadius: Appearance.rounding.full
                                                Accessible.name: Translation.tr("Add to Dock")
                                                onClicked: root.addPinnedApp(
                                                    String(addAppDelegate.modelData?.id ?? ""))
                                                contentItem: MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: "add"
                                                    iconSize: Appearance.font.pixelSize.normal
                                                    color: Appearance.colors.colPrimary
                                                }
                                                StyledToolTip {
                                                    text: Translation.tr("Add to Dock")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
