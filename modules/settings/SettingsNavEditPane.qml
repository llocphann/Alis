pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.common
import qs.services
import qs.modules.common.widgets

Item {
    id: root
    property int currentPage: -1
    signal pageActivated(int pageIndex)
    signal pageHidden(int pageIndex)
    signal doneRequested()

    readonly property int rowHeight: 38
    readonly property var visiblePages: SettingsPageRegistry.navigationPageIndexes(false)
    readonly property var navGroups: SettingsPageRegistry.categories
    readonly property var hiddenPages: SettingsPageRegistry.hiddenPages.filter(index =>
        SettingsPageRegistry.pages[index] && SettingsPageRegistry.isPageApplicable(index))

    property var _activeCancelRename: null

    function handleEscape(): bool {
        if (typeof root._activeCancelRename === "function") {
            const cancelFn = root._activeCancelRename
            root._activeCancelRename = null
            cancelFn()
            root.forceActiveFocus()
            return true
        }
        return false
    }

    component NavRow: Rectangle {
        id: row
        required property int pageIdx
        required property int flatIndex
        property bool hiddenSource: false
        property bool editingName: false
        readonly property var page: SettingsPageRegistry.pages[row.pageIdx] ?? null
        readonly property bool active: row.pageIdx === root.currentPage
        readonly property color iconTint: SettingsMaterialPreset.navigationIconColor(
            Math.max(0, row.flatIndex), Math.max(1, root.visiblePages.length), row.active)

        width: parent ? parent.width : 0
        height: root.rowHeight
        radius: Appearance.rounding.small
        readonly property string dropTargetId: "navrow:" + row.pageIdx
        readonly property bool isDropHovered: SettingsLayoutManager.dragActive
            && SettingsLayoutManager.hoveredDropTargetId === row.dropTargetId
        color: row.isDropHovered ? Appearance.colors.colSecondaryContainer
            : row.active ? Appearance.colors.colPrimaryContainer
            : hover.hovered ? Appearance.colors.colLayer1Hover : "transparent"
        border.width: row.isDropHovered ? 1.5 : 0
        border.color: row.isDropHovered ? Appearance.colors.colPrimary : "transparent"
        HoverHandler { id: hover }

        Component.onCompleted: {
            if (!row.hiddenSource && row.pageIdx >= 0) {
                SettingsLayoutManager.registerDropTarget(row.dropTargetId, {
                    item: row,
                    kind: "sidebar-page",
                    pageIndex: row.pageIdx,
                    customTabId: "",
                    subTabId: "",
                    label: row.page?.name ?? ""
                })
            }
        }
        Component.onDestruction: {
            SettingsLayoutManager.unregisterDropTarget(row.dropTargetId)
        }

        onEditingNameChanged: {
            if (row.editingName)
                root._activeCancelRename = row.cancelTabRename
            else if (root._activeCancelRename === row.cancelTabRename)
                root._activeCancelRename = null
        }

        function cancelTabRename(): void {
            if (!row.editingName)
                return
            row.editingName = false
            tabNameInput.text = row.page?.name ?? ""
            if (root._activeCancelRename === row.cancelTabRename)
                root._activeCancelRename = null
        }

        function commitTabRename(): void {
            if (!row.editingName)
                return
            row.editingName = false
            SettingsArrangement.renamePage(row.pageIdx, tabNameInput.text)
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 5
            anchors.rightMargin: 3
            spacing: 4

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: row.page?.icon ?? "settings"
                rotation: row.page?.iconRotation ?? 0
                iconSize: 17
                color: row.iconTint
            }

            Rectangle {
                visible: row.editingName
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer2
                border.width: 1
                border.color: Appearance.colors.colPrimary

                TextInput {
                    id: tabNameInput
                    anchors.fill: parent
                    anchors.leftMargin: 6
                    anchors.rightMargin: 6
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true
                    text: row.page?.name ?? ""
                    color: Appearance.colors.colOnLayer1
                    font.family: Appearance.font.family.main
                    font.pixelSize: Appearance.font.pixelSize.small
                    onAccepted: row.commitTabRename()
                    onActiveFocusChanged: {
                        if (!activeFocus && row.editingName)
                            row.commitTabRename()
                    }
                    Keys.onEscapePressed: {
                        row.cancelTabRename()
                    }
                }
            }

            StyledText {
                visible: !row.editingName
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                verticalAlignment: Text.AlignVCenter
                text: row.page?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: row.active ? Font.Medium : Font.Normal
                color: row.active ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                elide: Text.ElideRight
                TapHandler {
                    enabled: !row.hiddenSource
                    onTapped: {
                        SettingsLayoutManager.activeCustomTabId = ""
                        root.pageActivated(row.pageIdx)
                    }
                    onDoubleTapped: {
                        tabNameInput.text = row.page?.name ?? ""
                        row.editingName = true
                        tabNameInput.forceActiveFocus()
                        tabNameInput.selectAll()
                    }
                }
            }

            RippleButton {
                visible: !row.hiddenSource
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 25
                Layout.preferredHeight: 25
                buttonRadius: Appearance.rounding.full
                onClicked: {
                    if (row.editingName) {
                        row.commitTabRename()
                    } else {
                        tabNameInput.text = row.page?.name ?? ""
                        row.editingName = true
                        tabNameInput.forceActiveFocus()
                        tabNameInput.selectAll()
                    }
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: row.editingName ? "check" : "edit"
                    iconSize: 14
                    color: Appearance.colors.colSubtext
                }
                StyledToolTip { text: Translation.tr("Rename tab") }
            }

            RippleButton {
                visible: !row.hiddenSource && !row.editingName
                enabled: row.flatIndex > 0
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 25
                Layout.preferredHeight: 25
                buttonRadius: Appearance.rounding.full
                opacity: enabled ? 1 : 0.32
                onClicked: SettingsArrangement.movePageFlat(row.pageIdx, -1)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "keyboard_arrow_up"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                visible: !row.hiddenSource && !row.editingName
                enabled: row.flatIndex >= 0 && row.flatIndex < root.visiblePages.length - 1
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 25
                Layout.preferredHeight: 25
                buttonRadius: Appearance.rounding.full
                opacity: enabled ? 1 : 0.32
                onClicked: SettingsArrangement.movePageFlat(row.pageIdx, 1)
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "keyboard_arrow_down"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
            }

            RippleButton {
                visible: !row.editingName
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: 25
                Layout.preferredHeight: 25
                buttonRadius: Appearance.rounding.full
                onClicked: {
                    if (row.hiddenSource) {
                        SettingsArrangement.restorePage(row.pageIdx)
                    } else if (SettingsArrangement.hidePageById(row.pageIdx)) {
                        root.pageHidden(row.pageIdx)
                    }
                }
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: row.hiddenSource ? "visibility" : "visibility_off"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: editorColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: StyledScrollBar { policy: ScrollBar.AsNeeded }

        Column {
            id: editorColumn
            width: parent.width
            spacing: 4

            Rectangle {
                width: parent.width
                height: 40
                radius: Appearance.rounding.small
                color: Appearance.colors.colPrimaryContainer
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 5
                    spacing: 6
                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "reorder"
                        iconSize: 17
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Navigation tabs")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnPrimaryContainer
                    }
                    RippleButton {
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        buttonRadius: Appearance.rounding.full
                        onClicked: root.doneRequested()
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: "done"
                            iconSize: 17
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                        StyledToolTip { text: Translation.tr("Done editing") }
                    }
                }
            }

            // ── Quick Create Tab / Group Bar ──
            RowLayout {
                width: parent.width
                spacing: 4

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: {
                        const createdId = SettingsLayoutManager.createCustomTab(Translation.tr("Custom Tab"), "dashboard_customize")
                        if (createdId.length > 0) {
                            SettingsLayoutManager.activeCustomTabId = createdId
                        }
                    }
                    contentItem: Item {
                        implicitWidth: createTabButtonRow.implicitWidth
                        implicitHeight: createTabButtonRow.implicitHeight
                        Row {
                            id: createTabButtonRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "add_box"
                                iconSize: 14
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("+ Tab")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                    StyledToolTip { text: Translation.tr("Create a new custom Settings tab") }
                }

                RippleButton {
                    Layout.fillWidth: true
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: Appearance.colors.colLayer1
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: SettingsArrangement.createCategory(Translation.tr("New Group"))
                    contentItem: Item {
                        implicitWidth: createGroupButtonRow.implicitWidth
                        implicitHeight: createGroupButtonRow.implicitHeight
                        Row {
                            id: createGroupButtonRow
                            anchors.centerIn: parent
                            spacing: 4
                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "create_new_folder"
                                iconSize: 14
                                color: Appearance.colors.colPrimary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: Translation.tr("+ Group")
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnLayer1
                            }
                        }
                    }
                    StyledToolTip { text: Translation.tr("Create a new navigation group") }
                }
            }

            // ── Custom Sidebar Tabs Section ──
            Column {
                visible: SettingsLayoutManager.customTabs.length > 0
                width: editorColumn.width
                spacing: 2

                Rectangle {
                    width: parent.width
                    height: 28
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 7
                        anchors.rightMargin: 6
                        spacing: 4
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "dashboard_customize"
                            iconSize: 14
                            color: Appearance.colors.colPrimary
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Custom Tabs")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colSubtext
                        }
                    }
                }

                Repeater {
                    model: SettingsLayoutManager.customTabs
                    delegate: Rectangle {
                        id: customTabRow
                        required property var modelData
                        required property int index
                        property bool editingCustomName: false
                        readonly property string tabId: String(modelData?.id ?? "")
                        readonly property string tabLabel: String(modelData?.label ?? "")
                        readonly property bool isActiveTab: SettingsLayoutManager.activeCustomTabId === tabId
                        readonly property string dropTargetId: "navcustom:" + tabId
                        readonly property bool isDropHovered: SettingsLayoutManager.dragActive
                            && SettingsLayoutManager.hoveredDropTargetId === dropTargetId

                        width: editorColumn.width
                        height: root.rowHeight
                        radius: Appearance.rounding.small
                        color: isDropHovered ? Appearance.colors.colSecondaryContainer
                            : isActiveTab ? Appearance.colors.colPrimaryContainer
                            : customTabHover.hovered ? Appearance.colors.colLayer1Hover : "transparent"
                        border.width: isDropHovered ? 1.5 : 0
                        border.color: isDropHovered ? Appearance.colors.colPrimary : "transparent"
                        HoverHandler { id: customTabHover }

                        Component.onCompleted: {
                            if (tabId.length > 0) {
                                SettingsLayoutManager.registerDropTarget(dropTargetId, {
                                    item: customTabRow,
                                    kind: "sidebar-custom-tab",
                                    pageIndex: -1,
                                    customTabId: tabId,
                                    subTabId: "",
                                    label: tabLabel
                                })
                            }
                        }
                        Component.onDestruction: {
                            SettingsLayoutManager.unregisterDropTarget(dropTargetId)
                        }

                        function commitCustomRename(): void {
                            if (!customTabRow.editingCustomName)
                                return
                            customTabRow.editingCustomName = false
                            SettingsLayoutManager.renameCustomTab(customTabRow.tabId, customTabNameInput.text)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 5
                            anchors.rightMargin: 3
                            spacing: 4

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: String(customTabRow.modelData?.icon || "dashboard_customize")
                                iconSize: 17
                                color: customTabRow.isActiveTab
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colPrimary
                            }

                            Rectangle {
                                visible: customTabRow.editingCustomName
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Appearance.colors.colPrimary

                                TextInput {
                                    id: customTabNameInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    text: customTabRow.tabLabel
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    onAccepted: customTabRow.commitCustomRename()
                                    onActiveFocusChanged: {
                                        if (!activeFocus && customTabRow.editingCustomName)
                                            customTabRow.commitCustomRename()
                                    }
                                    Keys.onEscapePressed: {
                                        customTabRow.editingCustomName = false
                                        customTabNameInput.text = customTabRow.tabLabel
                                    }
                                }
                            }

                            StyledText {
                                visible: !customTabRow.editingCustomName
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                verticalAlignment: Text.AlignVCenter
                                text: customTabRow.tabLabel
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: customTabRow.isActiveTab ? Font.Medium : Font.Normal
                                color: customTabRow.isActiveTab
                                    ? Appearance.colors.colOnPrimaryContainer
                                    : Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                                TapHandler {
                                    onTapped: SettingsLayoutManager.activeCustomTabId = customTabRow.tabId
                                    onDoubleTapped: {
                                        customTabNameInput.text = customTabRow.tabLabel
                                        customTabRow.editingCustomName = true
                                        customTabNameInput.forceActiveFocus()
                                        customTabNameInput.selectAll()
                                    }
                                }
                            }

                            RippleButton {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                onClicked: {
                                    if (customTabRow.editingCustomName) {
                                        customTabRow.commitCustomRename()
                                    } else {
                                        customTabNameInput.text = customTabRow.tabLabel
                                        customTabRow.editingCustomName = true
                                        customTabNameInput.forceActiveFocus()
                                        customTabNameInput.selectAll()
                                    }
                                }
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: customTabRow.editingCustomName ? "check" : "edit"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                                StyledToolTip { text: Translation.tr("Rename custom tab") }
                            }

                            RippleButton {
                                visible: !customTabRow.editingCustomName
                                enabled: customTabRow.index > 0
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                opacity: enabled ? 1 : 0.32
                                onClicked: SettingsLayoutManager.moveCustomTab(customTabRow.tabId, -1)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "keyboard_arrow_up"
                                    iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            RippleButton {
                                visible: !customTabRow.editingCustomName
                                enabled: customTabRow.index < SettingsLayoutManager.customTabs.length - 1
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                opacity: enabled ? 1 : 0.32
                                onClicked: SettingsLayoutManager.moveCustomTab(customTabRow.tabId, 1)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "keyboard_arrow_down"
                                    iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            RippleButton {
                                visible: !customTabRow.editingCustomName
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                onClicked: SettingsLayoutManager.deleteCustomTab(customTabRow.tabId)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "delete"
                                    iconSize: 14
                                    color: Appearance.colors.colError
                                }
                                StyledToolTip { text: Translation.tr("Delete custom tab") }
                            }
                        }
                    }
                }
            }

            Repeater {
                model: root.navGroups
                delegate: Column {
                    id: headingSection
                    required property var modelData
                    required property int index
                    property bool editingHeading: false
                    readonly property string headingTitle: String(headingSection.modelData?.label ?? "")
                    readonly property var groupPages: headingSection.modelData?.pages ?? []
                    width: editorColumn.width
                    spacing: 2

                    onEditingHeadingChanged: {
                        if (headingSection.editingHeading)
                            root._activeCancelRename = headingSection.cancelHeadingRename
                        else if (root._activeCancelRename === headingSection.cancelHeadingRename)
                            root._activeCancelRename = null
                    }

                    function cancelHeadingRename(): void {
                        if (!headingSection.editingHeading)
                            return
                        headingSection.editingHeading = false
                        headingInput.text = headingSection.headingTitle
                        if (root._activeCancelRename === headingSection.cancelHeadingRename)
                            root._activeCancelRename = null
                    }

                    function commitHeadingRename(): void {
                        if (!headingSection.editingHeading)
                            return
                        headingSection.editingHeading = false
                        SettingsArrangement.renameCategory(headingSection.index, headingInput.text)
                    }

                    Rectangle {
                        width: parent.width
                        height: 32
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 7
                            anchors.rightMargin: 4
                            spacing: 4

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "folder"
                                iconSize: 15
                                color: Appearance.colors.colPrimary
                            }

                            Rectangle {
                                visible: headingSection.editingHeading
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.preferredHeight: 24
                                radius: Appearance.rounding.verysmall
                                color: Appearance.colors.colLayer2
                                border.width: 1
                                border.color: Appearance.colors.colPrimary

                                TextInput {
                                    id: headingInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    verticalAlignment: TextInput.AlignVCenter
                                    clip: true
                                    selectByMouse: true
                                    text: headingSection.headingTitle
                                    color: Appearance.colors.colOnLayer1
                                    font.family: Appearance.font.family.main
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    onAccepted: headingSection.commitHeadingRename()
                                    onActiveFocusChanged: {
                                        if (!activeFocus && headingSection.editingHeading)
                                            headingSection.commitHeadingRename()
                                    }
                                    Keys.onEscapePressed: {
                                        headingSection.cancelHeadingRename()
                                    }
                                }
                            }

                            StyledText {
                                visible: !headingSection.editingHeading
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                verticalAlignment: Text.AlignVCenter
                                text: headingSection.headingTitle
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colSubtext
                                elide: Text.ElideRight
                                TapHandler {
                                    onDoubleTapped: {
                                        headingInput.text = headingSection.headingTitle
                                        headingSection.editingHeading = true
                                        headingInput.forceActiveFocus()
                                        headingInput.selectAll()
                                    }
                                }
                            }

                            RippleButton {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                onClicked: {
                                    if (headingSection.editingHeading) {
                                        headingSection.commitHeadingRename()
                                    } else {
                                        headingInput.text = headingSection.headingTitle
                                        headingSection.editingHeading = true
                                        headingInput.forceActiveFocus()
                                        headingInput.selectAll()
                                    }
                                }
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: headingSection.editingHeading ? "check" : "edit"
                                    iconSize: 14
                                    color: Appearance.colors.colSubtext
                                }
                                StyledToolTip { text: Translation.tr("Rename heading") }
                            }

                            RippleButton {
                                visible: !headingSection.editingHeading
                                enabled: headingSection.index > 0
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                opacity: enabled ? 1 : 0.32
                                onClicked: SettingsArrangement.moveCategory(headingSection.index, -1)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "keyboard_arrow_up"
                                    iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            RippleButton {
                                visible: !headingSection.editingHeading
                                enabled: headingSection.index < root.navGroups.length - 1
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                opacity: enabled ? 1 : 0.32
                                onClicked: SettingsArrangement.moveCategory(headingSection.index, 1)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "keyboard_arrow_down"
                                    iconSize: 15
                                    color: Appearance.colors.colSubtext
                                }
                            }

                            RippleButton {
                                visible: !headingSection.editingHeading && root.navGroups.length > 1
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                buttonRadius: Appearance.rounding.full
                                onClicked: SettingsArrangement.deleteCategory(headingSection.index)
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: "delete"
                                    iconSize: 14
                                    color: Appearance.colors.colError
                                }
                                StyledToolTip { text: Translation.tr("Delete group") }
                            }
                        }
                    }

                    Repeater {
                        model: headingSection.groupPages
                        delegate: NavRow {
                            required property int modelData
                            required property int index
                            pageIdx: modelData
                            flatIndex: root.visiblePages.indexOf(modelData)
                        }
                    }
                }
            }

            Rectangle {
                visible: root.hiddenPages.length > 0
                width: parent.width
                height: visible ? hiddenColumn.implicitHeight + 10 : 0
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer0
                Column {
                    id: hiddenColumn
                    x: 5
                    y: 5
                    width: parent.width - 10
                    spacing: 3
                    RowLayout {
                        width: parent.width
                        height: 28
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "visibility_off"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Hidden tabs")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                        }
                    }
                    Repeater {
                        model: root.hiddenPages
                        delegate: NavRow {
                            required property int modelData
                            required property int index
                            pageIdx: modelData
                            flatIndex: -1
                            hiddenSource: true
                        }
                    }
                }
            }

            RippleButtonWithIcon {
                width: parent.width
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset navigation order")
                onClicked: SettingsArrangement.reset()
            }
        }
    }
}
