pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

Rectangle {
    id: root
    objectName: "irisPrismSidebar"

    property bool showingHome: false
    property int activePageIndex: 2
    property Item currentPageItem: null
    property string searchQuery: ""
    property bool windowed: false
    property bool abyssLockOverlay: false

    signal homeClicked()
    signal areaClicked(int pageIndex)
    signal sectionGroupClicked(string sectionKey)
    signal searchEdited(string text)
    signal searchMoveSelection(int delta)
    signal searchAccepted()
    signal searchCleared()
    signal switchWindowModeRequested()
    signal closeRequested()

    readonly property bool searching: root.searchQuery.trim().length > 0
    property alias searchField: searchInput

    function focusSearch(): void {
        searchInput.forceActiveFocus()
        searchInput.selectAll()
    }

    color: IrisTheme.sidebarBg
    border.width: 0

    // Right vertical divider hairline separating sidebar from middle pane
    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: 1
        color: IrisTheme.hairline
    }

    // Build clustered area list
    readonly property var clusteredAreas: {
        void(SettingsPageRegistry.pages)
        const seen = new Set()
        const out = []

        const clusters = SettingsPageRegistryData.irisClusters ?? []
        for (let i = 0; i < clusters.length; i++) {
            const cl = clusters[i]
            const items = []
            for (const idx of (cl?.pages ?? [])) {
                if (seen.has(idx) || !SettingsPageRegistry.isPageApplicable(idx))
                    continue
                const p = SettingsPageRegistry.pages[idx]
                if (!p)
                    continue
                seen.add(idx)
                items.push({
                    pageIndex: idx,
                    key: String(p.key ?? ""),
                    name: String(p.name ?? ""),
                    icon: String(p.icon ?? "settings"),
                    iconRotation: Number(p.iconRotation ?? 0)
                })
            }
            if (items.length > 0) {
                out.push({
                    id: String(cl?.id ?? ("cl-" + i)),
                    label: String(cl?.label ?? ""),
                    pages: items
                })
            }
        }
        return out
    }

    readonly property var pinnedEntries: {
        void(IrisState.pinnedAreaKeys)
        void(SettingsPageRegistry.pages)
        const keys = IrisState.pinnedAreaKeys ?? []
        const list = []
        const seen = new Set()
        for (let i = 0; i < keys.length; i++) {
            const k = String(keys[i] ?? "")
            const idx = SettingsPageRegistry.pageIndexForKey(k)
            if (idx < 0 || seen.has(idx) || !SettingsPageRegistry.isPageApplicable(idx))
                continue
            const p = SettingsPageRegistry.pages[idx]
            if (!p)
                continue
            seen.add(idx)
            list.push({
                pageIndex: idx,
                key: String(p.key ?? k),
                name: String(p.name ?? k),
                icon: String(p.icon ?? "bookmark"),
                iconRotation: Number(p.iconRotation ?? 0)
            })
        }
        return list
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        anchors.topMargin: 10
        anchors.bottomMargin: 10
        spacing: 8

        // ── Top Bar: Brand mark + title + compact action pills ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 26
                height: 26
                radius: 8
                color: IrisTheme.accentTint
                border.width: 1
                border.color: IrisTheme.accentBorder

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "tune"
                    iconSize: Appearance.font.pixelSize.normal
                    color: IrisTheme.accent
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.alignment: Qt.AlignVCenter
                text: Translation.tr("Settings")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: IrisTheme.text
            }

            // Edit Abyss Layout compact icon button (Abyss family)
            RippleButton {
                id: editAbyssHeaderBtn
                visible: !root.windowed && Config.options?.panelFamily === "abyss"
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 26
                implicitHeight: 26
                buttonRadius: 8
                colBackground: "transparent"
                colBackgroundHover: IrisTheme.plateHover
                onClicked: GlobalStates.startAbyssEditing()
                contentItem: Item {
                    implicitWidth: 16
                    implicitHeight: 16
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "edit"
                        iconSize: 16
                        color: IrisTheme.textMuted
                    }
                }
                StyledToolTip {
                    text: Translation.tr("Edit Abyss layout")
                }
            }

            // Window / Overlay mode switch
            Rectangle {
                visible: !root.abyssLockOverlay
                Layout.alignment: Qt.AlignVCenter
                width: 26
                height: 26
                radius: 8
                color: modeMouse.containsMouse ? IrisTheme.plateHover : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.windowed ? "picture_in_picture_alt" : "open_in_new"
                    iconSize: 16
                    color: IrisTheme.textMuted
                }

                MouseArea {
                    id: modeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.switchWindowModeRequested()
                }

                StyledToolTip {
                    extraVisibleCondition: modeMouse.containsMouse
                    text: root.windowed ? Translation.tr("Dock as overlay") : Translation.tr("Open in window")
                }
            }

            // Close button
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 26
                height: 26
                radius: 8
                color: closeMouse.containsMouse ? Qt.alpha(Appearance.colors.colError, 0.16) : "transparent"

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: closeMouse.containsMouse ? Appearance.colors.colError : IrisTheme.textMuted
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }

                StyledToolTip {
                    extraVisibleCondition: closeMouse.containsMouse
                    text: Translation.tr("Close (Esc)")
                }
            }
        }

        // ── Search Capsule (Ctrl+F) ──
        Rectangle {
            id: searchPlate
            objectName: "irisSearchInput"
            Layout.fillWidth: true
            implicitHeight: Math.round(34 * IrisTheme.scale)
            radius: Math.round(implicitHeight / 2)
            color: searchInput.activeFocus ? IrisTheme.plateRaised : IrisTheme.plate
            border.width: 1
            border.color: searchInput.activeFocus ? IrisTheme.accentBorder : IrisTheme.hairline

            Behavior on border.color {
                enabled: IrisTheme.fastMs > 0
                ColorAnimation { duration: IrisTheme.fastMs }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 8
                spacing: 6

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: "search"
                    iconSize: 16
                    color: searchInput.activeFocus ? IrisTheme.accent : IrisTheme.textMuted
                }

                TextField {
                    id: searchInput
                    objectName: "irisSearchTextField"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.alignment: Qt.AlignVCenter
                    background: null
                    padding: 0
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    text: root.searchQuery
                    placeholderText: Translation.tr("Search settings...")
                    placeholderTextColor: IrisTheme.textDim
                    color: IrisTheme.text
                    selectedTextColor: IrisTheme.onAccent
                    selectionColor: IrisTheme.accent
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    verticalAlignment: TextInput.AlignVCenter
                    onTextChanged: {
                        if (text !== root.searchQuery)
                            root.searchEdited(text)
                    }
                    onTextEdited: root.searchEdited(text)
                    Keys.onDownPressed: event => {
                        root.searchMoveSelection(1)
                        event.accepted = true
                    }
                    Keys.onUpPressed: event => {
                        root.searchMoveSelection(-1)
                        event.accepted = true
                    }
                    Keys.onReturnPressed: event => {
                        root.searchAccepted()
                        event.accepted = true
                    }
                    Keys.onEnterPressed: event => {
                        root.searchAccepted()
                        event.accepted = true
                    }
                    Keys.onEscapePressed: event => {
                        if (searchInput.text.length > 0) {
                            root.searchCleared()
                            searchInput.focus = false
                            event.accepted = true
                        } else {
                            searchInput.focus = false
                            event.accepted = false
                        }
                    }
                }

                // Clear button when query non-empty, else Ctrl+F hint badge
                Rectangle {
                    visible: root.searching
                    Layout.alignment: Qt.AlignVCenter
                    width: 18
                    height: 18
                    radius: 9
                    color: clearSearchMouse.containsMouse ? IrisTheme.plateHover : IrisTheme.accentTint

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: 12
                        color: IrisTheme.text
                    }

                    MouseArea {
                        id: clearSearchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.searchCleared()
                            searchInput.forceActiveFocus()
                        }
                    }
                }

                Rectangle {
                    visible: !root.searching && !searchInput.activeFocus
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: shortcutHint.implicitWidth + 8
                    implicitHeight: 18
                    radius: 5
                    color: Qt.alpha(Appearance.colors.colLayer2Base, 0.45)
                    border.width: 1
                    border.color: IrisTheme.hairline

                    StyledText {
                        id: shortcutHint
                        anchors.centerIn: parent
                        text: "Ctrl+F"
                        font.pixelSize: Appearance.font.pixelSize.smallest - 1
                        color: IrisTheme.textDim
                    }
                }
            }
        }

        // ── Scrollable Navigation Tree ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: navFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: navCol.implicitHeight + 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

                ColumnLayout {
                    id: navCol
                    width: navFlick.width
                    spacing: 2

                    // 1) Home Entry
                    Rectangle {
                        id: homeRow
                        objectName: "irisHomeNavRow"
                        Layout.fillWidth: true
                        implicitHeight: Math.round(34 * IrisTheme.scale)
                        radius: IrisTheme.radiusSmall
                        readonly property bool selected: root.showingHome && !root.searching
                        color: selected
                            ? IrisTheme.accentTint
                            : (homeMouse.containsMouse ? IrisTheme.plateHover : "transparent")
                        border.width: selected ? 1 : 0
                        border.color: IrisTheme.accentBorder

                        Rectangle {
                            visible: homeRow.selected
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: 3
                            height: 16
                            radius: 1.5
                            color: IrisTheme.accent
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "home"
                                fill: homeRow.selected ? 1 : 0
                                iconSize: 18
                                color: homeRow.selected ? IrisTheme.accent : IrisTheme.textMuted
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                Layout.alignment: Qt.AlignVCenter
                                text: Translation.tr("Home")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: homeRow.selected ? Font.DemiBold : Font.Normal
                                color: homeRow.selected ? IrisTheme.text : IrisTheme.textSecondary
                            }
                        }

                        MouseArea {
                            id: homeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.homeClicked()
                        }
                    }

                    // 2) Pinned Quick Links
                    ColumnLayout {
                        visible: root.pinnedEntries.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            Layout.bottomMargin: 2
                            text: Translation.tr("PINNED")
                            font.pixelSize: Appearance.font.pixelSize.smallest - 1
                            font.weight: Font.DemiBold
                            font.letterSpacing: 0.9
                            color: IrisTheme.textDim
                        }

                        Repeater {
                            model: root.pinnedEntries

                            delegate: Rectangle {
                                id: pinRow
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: Math.round(30 * IrisTheme.scale)
                                radius: IrisTheme.radiusSmall
                                readonly property bool selected: !root.showingHome && !root.searching
                                    && root.activePageIndex === Number(modelData.pageIndex)
                                color: selected
                                    ? Qt.alpha(IrisTheme.accent, 0.10)
                                    : (pinRowMouse.containsMouse ? IrisTheme.plateHover : "transparent")

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 6
                                    spacing: 8

                                    MaterialSymbol {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: String(pinRow.modelData.icon || "bookmark")
                                        rotation: Number(pinRow.modelData.iconRotation || 0)
                                        iconSize: 16
                                        color: pinRow.selected ? IrisTheme.accent : IrisTheme.textMuted
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignVCenter
                                        text: String(pinRow.modelData.name || "")
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: pinRow.selected ? IrisTheme.text : IrisTheme.textSecondary
                                    }

                                    Rectangle {
                                        visible: pinRowMouse.containsMouse || unpinMouse.containsMouse
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 20
                                        height: 20
                                        radius: 6
                                        color: unpinMouse.containsMouse ? IrisTheme.accentTint : "transparent"

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "keep_off"
                                            iconSize: 13
                                            color: IrisTheme.textMuted
                                        }

                                        MouseArea {
                                            id: unpinMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: IrisState.togglePinArea(String(pinRow.modelData.key || ""))
                                        }
                                    }
                                }

                                MouseArea {
                                    id: pinRowMouse
                                    anchors.fill: parent
                                    anchors.rightMargin: 24
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.areaClicked(Number(pinRow.modelData.pageIndex))
                                }
                            }
                        }
                    }

                    // 3) Clustered Areas + Unfolding Active Sub-Groups
                    Repeater {
                        model: root.clusteredAreas

                        delegate: ColumnLayout {
                            id: clusterBlock
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            spacing: 2

                            StyledText {
                                visible: String(clusterBlock.modelData.label || "").length > 0
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.bottomMargin: 2
                                text: String(clusterBlock.modelData.label || "")
                                font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.9
                                color: IrisTheme.textDim
                            }

                            Repeater {
                                model: clusterBlock.modelData.pages ?? []

                                delegate: ColumnLayout {
                                    id: areaItemCol
                                    required property var modelData
                                    readonly property int pageIdx: Number(modelData.pageIndex)
                                    readonly property bool isCurrentArea: !root.showingHome
                                        && !root.searching
                                        && root.activePageIndex === pageIdx
                                    readonly property var areaSubTabs: {
                                        if (!isCurrentArea || !root.currentPageItem)
                                            return []
                                        const specs = root.currentPageItem.effectiveSubTabSpecs ?? []
                                        return specs.length > 1 ? specs : []
                                    }
                                    readonly property var areaSectionGroups: {
                                        if (!isCurrentArea || !root.currentPageItem)
                                            return []
                                        return root.currentPageItem.irisSectionGroups ?? []
                                    }
                                    readonly property bool hasUnfold: isCurrentArea
                                        && (areaSubTabs.length > 0 || areaSectionGroups.length > 1)

                                    Layout.fillWidth: true
                                    spacing: 2

                                    Rectangle {
                                        id: areaRowRect
                                        objectName: "settingsNav_" + String(areaItemCol.modelData.key || "")
                                        Layout.fillWidth: true
                                        implicitHeight: Math.round(34 * IrisTheme.scale)
                                        radius: IrisTheme.radiusSmall
                                        color: areaItemCol.isCurrentArea
                                            ? IrisTheme.accentTint
                                            : (areaMouse.containsMouse ? IrisTheme.plateHover : "transparent")
                                        border.width: areaItemCol.isCurrentArea ? 1 : 0
                                        border.color: IrisTheme.accentBorder

                                        Rectangle {
                                            visible: areaItemCol.isCurrentArea
                                            anchors.left: parent.left
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 3
                                            height: 16
                                            radius: 1.5
                                            color: IrisTheme.accent
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            MaterialSymbol {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: String(areaItemCol.modelData.icon || "settings")
                                                rotation: Number(areaItemCol.modelData.iconRotation || 0)
                                                fill: areaItemCol.isCurrentArea ? 1 : 0
                                                iconSize: 17
                                                color: areaItemCol.isCurrentArea ? IrisTheme.accent : IrisTheme.textMuted
                                            }

                                            StyledText {
                                                Layout.fillWidth: true
                                                Layout.minimumWidth: 0
                                                Layout.alignment: Qt.AlignVCenter
                                                text: String(areaItemCol.modelData.name || "")
                                                font.pixelSize: Appearance.font.pixelSize.small
                                                font.weight: areaItemCol.isCurrentArea ? Font.DemiBold : Font.Normal
                                                color: areaItemCol.isCurrentArea ? IrisTheme.text : IrisTheme.textSecondary
                                            }

                                            // Pin/Unpin quick-link button on hover
                                            Rectangle {
                                                readonly property bool pinned: IrisState.isAreaPinned(String(areaItemCol.modelData.key || ""))
                                                visible: areaMouse.containsMouse || pinAreaBtnMouse.containsMouse
                                                Layout.alignment: Qt.AlignVCenter
                                                width: 20
                                                height: 20
                                                radius: 6
                                                color: pinAreaBtnMouse.containsMouse ? IrisTheme.accentTint : "transparent"

                                                MaterialSymbol {
                                                    anchors.centerIn: parent
                                                    text: parent.pinned ? "keep_off" : "keep"
                                                    fill: parent.pinned ? 1 : 0
                                                    iconSize: 13
                                                    color: parent.pinned ? IrisTheme.accent : IrisTheme.textMuted
                                                }

                                                MouseArea {
                                                    id: pinAreaBtnMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: IrisState.togglePinArea(String(areaItemCol.modelData.key || ""))
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: areaMouse
                                            anchors.fill: parent
                                            anchors.rightMargin: 24
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.areaClicked(areaItemCol.pageIdx)
                                        }
                                    }

                                    // Unfolding sub-groups directly under active area (iRiS PrismSidebar pattern)
                                    Item {
                                        id: unfoldContainer
                                        visible: areaItemCol.hasUnfold || subUnfoldAnim.running
                                        Layout.fillWidth: true
                                        implicitHeight: areaItemCol.hasUnfold ? subUnfoldInner.implicitHeight + 4 : 0
                                        clip: true

                                        Behavior on implicitHeight {
                                            enabled: IrisTheme.glideMs > 0
                                            NumberAnimation {
                                                id: subUnfoldAnim
                                                duration: IrisTheme.glideMs
                                                easing.type: Easing.OutCubic
                                            }
                                        }

                                        // Vertical 1px guide line
                                        Rectangle {
                                            x: 18
                                            anchors.top: subUnfoldInner.top
                                            anchors.bottom: subUnfoldInner.bottom
                                            anchors.topMargin: 4
                                            anchors.bottomMargin: 4
                                            width: 1
                                            color: IrisTheme.hairlineStrong
                                        }

                                        ColumnLayout {
                                            id: subUnfoldInner
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.leftMargin: 26
                                            anchors.rightMargin: 4
                                            y: 2
                                            spacing: 1

                                            // Sub-tab mode switches when page has multiple subTabs
                                            Repeater {
                                                model: areaItemCol.areaSubTabs

                                                delegate: Rectangle {
                                                    id: subTabEntry
                                                    required property var modelData
                                                    readonly property bool activeTab: root.currentPageItem
                                                        && String(root.currentPageItem.activeSubTabKey ?? "") === String(modelData.key ?? "")
                                                    Layout.fillWidth: true
                                                    implicitHeight: Math.round(26 * IrisTheme.scale)
                                                    radius: 6
                                                    color: activeTab
                                                        ? Qt.alpha(IrisTheme.accent, 0.12)
                                                        : (subTabEntryMouse.containsMouse ? IrisTheme.plateHover : "transparent")

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 6
                                                        spacing: 6

                                                        MaterialSymbol {
                                                            visible: String(subTabEntry.modelData.icon || "").length > 0
                                                            Layout.alignment: Qt.AlignVCenter
                                                            text: String(subTabEntry.modelData.icon || "tab")
                                                            iconSize: 13
                                                            color: subTabEntry.activeTab ? IrisTheme.accent : IrisTheme.textDim
                                                        }

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            Layout.alignment: Qt.AlignVCenter
                                                            text: String(subTabEntry.modelData.label || "")
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: subTabEntry.activeTab ? Font.DemiBold : Font.Normal
                                                            color: subTabEntry.activeTab ? IrisTheme.accent : IrisTheme.textMuted
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: subTabEntryMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (root.currentPageItem && typeof root.currentPageItem.selectSubTabItem === "function")
                                                                root.currentPageItem.selectSubTabItem(subTabEntry.modelData)
                                                        }
                                                    }
                                                }
                                            }

                                            // Numbered section plates on active page (scroll-spy + OutCubic glide)
                                            Repeater {
                                                model: areaItemCol.areaSectionGroups

                                                delegate: Rectangle {
                                                    id: secGroupRow
                                                    required property var modelData
                                                    readonly property bool inView: root.currentPageItem
                                                        && String(root.currentPageItem.currentIrisSectionTitle ?? "") === String(modelData.title ?? "")
                                                    Layout.fillWidth: true
                                                    implicitHeight: Math.round(26 * IrisTheme.scale)
                                                    radius: 6
                                                    color: secGroupMouse.containsMouse ? IrisTheme.plateHover : "transparent"

                                                    // Active indicator tick aligned with left hairline
                                                    Rectangle {
                                                        visible: secGroupRow.inView
                                                        x: -8.5
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        width: 2.5
                                                        height: 14
                                                        radius: 1.25
                                                        color: IrisTheme.accent
                                                    }

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 6
                                                        spacing: 6

                                                        StyledText {
                                                            Layout.alignment: Qt.AlignVCenter
                                                            text: {
                                                                const idx = Number(secGroupRow.modelData.index ?? 0)
                                                                return (idx < 10 ? "0" : "") + String(idx)
                                                            }
                                                            font.pixelSize: Appearance.font.pixelSize.smallest - 1
                                                            font.features: ({ "tnum": 1 })
                                                            color: secGroupRow.inView ? IrisTheme.accent : IrisTheme.textDim
                                                        }

                                                        StyledText {
                                                            Layout.fillWidth: true
                                                            Layout.minimumWidth: 0
                                                            Layout.alignment: Qt.AlignVCenter
                                                            text: String(secGroupRow.modelData.title || "")
                                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                                            font.weight: secGroupRow.inView ? Font.DemiBold : Font.Normal
                                                            color: secGroupRow.inView ? IrisTheme.text : IrisTheme.textMuted
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: secGroupMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.sectionGroupClicked(String(secGroupRow.modelData.key || secGroupRow.modelData.title || ""))
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

            IrisScrollEdge {
                flickable: navFlick
                edge: "top"
                fadeColor: IrisTheme.sidebarBg
                fadeExtent: 18
            }

            IrisScrollEdge {
                flickable: navFlick
                edge: "bottom"
                fadeColor: IrisTheme.sidebarBg
                fadeExtent: 18
            }
        }
    }
}
