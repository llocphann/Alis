pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks

Rectangle {
    id: root
    objectName: "abyssCustomizationDock"

    property bool embeddedSurface: false
    property var tabs: []
    property string activeTab: ""
    property bool autoSwitchTab: true
    property bool trayExpanded: true
    property real trayHeight: 116
    property bool canUndo: false
    property bool canRedo: false
    property bool showUndo: true
    property bool showRedo: false
    property bool showSearch: false
    property string searchText: ""
    property string searchPlaceholder: Translation.tr("Search...")
    property string searchObjectName: ""
    property bool showCancel: true
    property string cancelLabel: Translation.tr("Cancel")
    property string doneLabel: Translation.tr("Done")
    property string doneObjectName: ""
    property string cancelObjectName: ""
    property string undoObjectName: ""
    property string redoObjectName: ""
    property bool headerOverlayActive: false

    property alias leadingControls: leadingRow.data
    property alias trailingControls: trailingRow.data
    property alias headerOverlay: headerOverlayHost.data
    default property alias trayContent: trayContentHost.data
    readonly property TextInput searchInputItem: searchInput

    signal undoClicked()
    signal redoClicked()
    signal tabClicked(string key)
    signal searchEdited(string text)
    signal cancelClicked()
    signal doneClicked()

    readonly property bool abyssMode: (Config.options?.panelFamily ?? "abyss") === "abyss"
    property real horizontalPadding: 14
    property real verticalPadding: 7
    property real topBarHeight: 40
    property real trayGap: 6
    property real contentPreferredWidth: 0
    property bool _syncingSearch: false

    property real _animatedTrayHeight: root.trayExpanded ? Math.max(0, root.trayHeight) : 0
    Behavior on _animatedTrayHeight {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: AbyssStyle.motionFast > 0 ? AbyssStyle.motionFast : 160
            easing.type: Easing.OutCubic
        }
    }

    onSearchTextChanged: {
        if (root._syncingSearch)
            return;
        if (searchInput.text !== root.searchText) {
            root._syncingSearch = true;
            searchInput.text = root.searchText;
            root._syncingSearch = false;
        }
    }

    implicitWidth: Math.min(2400, Math.max(560, Math.ceil(
        Math.max(topRow.implicitWidth, root.trayExpanded ? root.contentPreferredWidth : 0)
        + root.horizontalPadding * 2)))
    implicitHeight: Math.ceil(
        root.verticalPadding * 2
        + root.topBarHeight
        + (root._animatedTrayHeight > 0.5 ? (root.trayGap + 1 + root._animatedTrayHeight) : 0)
    )

    readonly property real fallbackCornerRadius: root.abyssMode ? AbyssStyle.perimeterRadius : Appearance.rounding.large
    radius: root.embeddedSurface ? 0 : root.fallbackCornerRadius
    topLeftRadius: root.embeddedSurface ? 0 : root.fallbackCornerRadius
    topRightRadius: root.embeddedSurface ? 0 : root.fallbackCornerRadius
    bottomLeftRadius: 0
    bottomRightRadius: 0
    color: root.embeddedSurface
        ? "transparent"
        : (root.abyssMode
            ? Qt.alpha(AbyssStyle.surfaceDeep, AbyssStyle.contentOpacity)
            : Appearance.colors.colLayer1)
    border.width: root.embeddedSurface ? 0 : (root.abyssMode && AbyssStyle.highlightStrength <= 0.001 ? 0 : 1)
    border.color: root.embeddedSurface
        ? "transparent"
        : (root.abyssMode
            ? Qt.alpha(AbyssStyle.specular, 0.34 * AbyssStyle.highlightStrength)
            : Qt.alpha(Appearance.colors.colOutlineVariant, 0.42))
    clip: true

    // Subtle top rim highlight for non-embedded fallback surfaces
    Rectangle {
        visible: !root.embeddedSurface && root.abyssMode && AbyssStyle.highlightStrength > 0.001
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: root.topLeftRadius * 0.65
        anchors.rightMargin: root.topRightRadius * 0.65
        height: 1
        color: Qt.alpha(AbyssStyle.specular, 0.28 * AbyssStyle.highlightStrength)
    }

    component DockIconButton: Rectangle {
        id: iconBtn
        property string icon: ""
        property string tooltipText: ""
        signal clicked()

        readonly property Item contentItem: iconGlyph
        implicitWidth: 30
        implicitHeight: 30
        width: 30
        height: 30
        radius: 15
        opacity: iconBtn.enabled ? 1.0 : 0.36
        scale: iconMouse.pressed && iconBtn.enabled ? 0.94 : 1.0
        color: iconMouse.pressed && iconBtn.enabled
            ? Appearance.colors.colLayer2Active
            : (iconMouse.containsMouse && iconBtn.enabled
                ? Appearance.colors.colLayer2Hover
                : Qt.alpha(Appearance.colors.colLayer2, 0.55))
        border.width: 1
        border.color: iconMouse.containsMouse && iconBtn.enabled
            ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.45)
            : Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

        Behavior on scale {
            enabled: Appearance.animationsEnabled
            NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
        }
        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
        }

        MaterialSymbol {
            id: iconGlyph
            anchors.centerIn: parent
            text: iconBtn.icon
            iconSize: 17
            color: Appearance.colors.colOnLayer1
        }

        MouseArea {
            id: iconMouse
            anchors.fill: parent
            enabled: iconBtn.enabled
            hoverEnabled: true
            cursorShape: iconBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: iconBtn.clicked()
        }

        StyledToolTip {
            position: "top"
            extraVisibleCondition: iconMouse.containsMouse && iconBtn.tooltipText.length > 0
            text: iconBtn.tooltipText
        }
    }

    Column {
        id: dockColumn
        anchors.fill: parent
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        anchors.topMargin: root.verticalPadding
        anchors.bottomMargin: root.verticalPadding
        spacing: root.trayGap

        // Tier 1: Top Control Strip (or in-place Header Overlay with identical height)
        Item {
            id: headerBand
            width: parent.width
            height: root.topBarHeight
            implicitHeight: root.topBarHeight

            RowLayout {
                id: topRow
                anchors.fill: parent
                spacing: 8
                visible: !root.headerOverlayActive

                Row {
                    id: historyRow
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4
                    visible: root.showUndo || root.showRedo

                    DockIconButton {
                        id: undoButton
                        objectName: root.undoObjectName
                        visible: root.showUndo
                        enabled: root.canUndo
                        icon: "undo"
                        tooltipText: Translation.tr("Undo last layout change")
                        onClicked: root.undoClicked()
                    }

                    DockIconButton {
                        id: redoButton
                        objectName: root.redoObjectName
                        visible: root.showRedo
                        enabled: root.canRedo
                        icon: "redo"
                        tooltipText: Translation.tr("Redo layout change")
                        onClicked: root.redoClicked()
                    }
                }

                Row {
                    id: leadingRow
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6
                    visible: children.length > 0
                }

                // Segmented Pill Tab Bar
                Rectangle {
                    id: tabStrip
                    visible: (root.tabs?.length ?? 0) > 0
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 32
                    implicitWidth: tabButtonsRow.implicitWidth + 6
                    radius: 16
                    color: Qt.alpha(Appearance.colors.colLayer2, 0.56)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                    Row {
                        id: tabButtonsRow
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: root.tabs ?? []
                            delegate: Rectangle {
                                id: tabBtn
                                required property var modelData
                                required property int index

                                readonly property string tabKey: String(modelData?.key ?? "")
                                readonly property string tabLabel: String(modelData?.label ?? "")
                                readonly property string tabIcon: String(modelData?.icon ?? "")
                                readonly property string tabBadge: modelData?.badge !== undefined && modelData?.badge !== null
                                    ? String(modelData.badge) : ""
                                readonly property bool isCurrent: root.activeTab === tabBtn.tabKey
                                property string tooltipText: String(modelData?.tooltipText ?? "").length > 0
                                    ? String(modelData.tooltipText)
                                    : Translation.tr("Switch to %1 section").arg(tabBtn.tabLabel)
                                readonly property Item contentItem: tabContentRow
                                signal clicked()

                                objectName: String(modelData?.objectName ?? "")
                                implicitHeight: 26
                                implicitWidth: tabContentRow.implicitWidth + (tabBtn.tabLabel.length > 0 ? 20 : 14)
                                height: 26
                                radius: 13
                                color: tabBtn.isCurrent
                                    ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.72)
                                    : (tabMouse.containsMouse
                                        ? Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                        : "transparent")
                                border.width: tabBtn.isCurrent ? 1 : 0
                                border.color: tabBtn.isCurrent
                                    ? Qt.alpha(Appearance.colors.colPrimary, 0.48)
                                    : "transparent"

                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation { duration: 130; easing.type: Easing.OutCubic }
                                }

                                Row {
                                    id: tabContentRow
                                    anchors.centerIn: parent
                                    spacing: 5

                                    MaterialSymbol {
                                        visible: tabBtn.tabIcon.length > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabBtn.tabIcon
                                        iconSize: 15
                                        fill: tabBtn.isCurrent ? 1 : 0
                                        color: tabBtn.isCurrent
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : (tabMouse.containsMouse
                                                ? Appearance.colors.colOnLayer1
                                                : Appearance.colors.colSubtext)
                                    }

                                    StyledText {
                                        visible: tabBtn.tabLabel.length > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        verticalAlignment: Text.AlignVCenter
                                        text: tabBtn.tabLabel
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: tabBtn.isCurrent ? Font.DemiBold : Font.Medium
                                        color: tabBtn.isCurrent
                                            ? Appearance.colors.colOnPrimaryContainer
                                            : (tabMouse.containsMouse
                                                ? Appearance.colors.colOnLayer1
                                                : Appearance.colors.colSubtext)
                                    }

                                    Rectangle {
                                        visible: tabBtn.tabBadge.length > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        implicitHeight: 16
                                        implicitWidth: Math.max(16, badgeText.implicitWidth + 8)
                                        radius: 8
                                        color: tabBtn.isCurrent
                                            ? Qt.alpha(Appearance.colors.colPrimary, 0.34)
                                            : Qt.alpha(Appearance.colors.colLayer3, 0.85)

                                        StyledText {
                                            id: badgeText
                                            anchors.centerIn: parent
                                            text: tabBtn.tabBadge
                                            font.pixelSize: Appearance.font.pixelSize.smallest
                                            font.weight: Font.DemiBold
                                            color: tabBtn.isCurrent
                                                ? Appearance.colors.colOnPrimaryContainer
                                                : Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                MouseArea {
                                    id: tabMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.autoSwitchTab)
                                            root.activeTab = tabBtn.tabKey;
                                        tabBtn.clicked();
                                        root.tabClicked(tabBtn.tabKey);
                                    }
                                }

                                StyledToolTip {
                                    position: "top"
                                    extraVisibleCondition: tabMouse.containsMouse && tabBtn.tooltipText.length > 0
                                    text: tabBtn.tooltipText
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 4
                }

                // Rounded Search Pill
                Rectangle {
                    id: searchPill
                    visible: root.showSearch
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 176
                    Layout.minimumWidth: 92
                    Layout.maximumWidth: 248
                    implicitHeight: 30
                    height: 30
                    radius: 15
                    color: searchInput.activeFocus
                        ? Qt.alpha(Appearance.colors.colLayer2, 0.92)
                        : Qt.alpha(Appearance.colors.colLayer2, 0.62)
                    border.width: 1
                    border.color: searchInput.activeFocus
                        ? Qt.alpha(Appearance.colors.colPrimary, 0.62)
                        : Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)

                    Behavior on border.color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 6
                        spacing: 6

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "search"
                            iconSize: 15
                            color: searchInput.activeFocus
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colSubtext
                        }

                        TextInput {
                            id: searchInput
                            objectName: root.searchObjectName
                            Layout.alignment: Qt.AlignVCenter
                            Layout.fillWidth: true
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colOnLayer1
                            selectionColor: Qt.alpha(Appearance.colors.colPrimary, 0.35)
                            selectedTextColor: Appearance.colors.colOnLayer1
                            selectByMouse: true
                            clip: true

                            Component.onCompleted: {
                                if (searchInput.text !== root.searchText) {
                                    root._syncingSearch = true;
                                    searchInput.text = root.searchText;
                                    root._syncingSearch = false;
                                }
                            }

                            onTextChanged: {
                                if (root._syncingSearch)
                                    return;
                                root._syncingSearch = true;
                                if (root.searchText !== searchInput.text)
                                    root.searchText = searchInput.text;
                                root._syncingSearch = false;
                                root.searchEdited(searchInput.text);
                            }

                            Keys.onEscapePressed: event => {
                                if (searchInput.text.length > 0) {
                                    searchInput.text = "";
                                    event.accepted = true;
                                } else {
                                    searchInput.focus = false;
                                    event.accepted = false;
                                }
                            }

                            StyledText {
                                visible: searchInput.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                verticalAlignment: Text.AlignVCenter
                                text: root.searchPlaceholder
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        Rectangle {
                            visible: searchInput.text.length > 0
                            Layout.alignment: Qt.AlignVCenter
                            width: 18
                            height: 18
                            radius: 9
                            color: clearMouse.containsMouse
                                ? Appearance.colors.colLayer3Hover
                                : Qt.alpha(Appearance.colors.colLayer3, 0.72)

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 13
                                color: Appearance.colors.colSubtext
                            }

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchInput.text = "";
                                    searchInput.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                Row {
                    id: trailingRow
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 6
                    visible: children.length > 0
                }

                // Subtle Cancel Pill
                Rectangle {
                    id: cancelButton
                    objectName: root.cancelObjectName
                    visible: root.showCancel
                    Layout.alignment: Qt.AlignVCenter
                    property string tooltipText: Translation.tr("Discard changes and exit Edit Mode")
                    readonly property Item contentItem: cancelContentRow
                    signal clicked()

                    implicitHeight: 30
                    implicitWidth: Math.max(58, cancelContentRow.implicitWidth + 22)
                    height: 30
                    radius: 15
                    scale: cancelMouse.pressed ? 0.96 : 1.0
                    color: cancelMouse.pressed
                        ? Appearance.colors.colLayer2Active
                        : (cancelMouse.containsMouse
                            ? Appearance.colors.colLayer2Hover
                            : Qt.alpha(Appearance.colors.colLayer2, 0.68))
                    border.width: 1
                    border.color: cancelMouse.containsMouse
                        ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.5)
                        : Qt.alpha(Appearance.colors.colOutlineVariant, 0.32)

                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    Row {
                        id: cancelContentRow
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.cancelLabel
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            cancelButton.clicked();
                            root.cancelClicked();
                        }
                    }

                    StyledToolTip {
                        position: "top"
                        extraVisibleCondition: cancelMouse.containsMouse && cancelButton.tooltipText.length > 0
                        text: cancelButton.tooltipText
                    }
                }

                // Primary Accent Done Pill
                Rectangle {
                    id: doneButton
                    objectName: root.doneObjectName
                    Layout.alignment: Qt.AlignVCenter
                    property string tooltipText: Translation.tr("Save layout changes and exit Edit Mode")
                    readonly property Item contentItem: doneContentRow
                    signal clicked()

                    implicitHeight: 30
                    implicitWidth: Math.max(64, doneContentRow.implicitWidth + 28)
                    height: 30
                    radius: 15
                    scale: doneMouse.pressed ? 0.96 : 1.0
                    color: doneMouse.pressed
                        ? Appearance.colors.colPrimaryActive
                        : (doneMouse.containsMouse
                            ? Appearance.colors.colPrimaryHover
                            : Appearance.colors.colPrimary)

                    Behavior on scale {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 110; easing.type: Easing.OutCubic }
                    }
                    Behavior on color {
                        enabled: Appearance.animationsEnabled
                        ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                    }

                    Row {
                        id: doneContentRow
                        anchors.centerIn: parent
                        spacing: 4

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            verticalAlignment: Text.AlignVCenter
                            text: root.doneLabel
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnPrimary
                        }
                    }

                    MouseArea {
                        id: doneMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            doneButton.clicked();
                            root.doneClicked();
                        }
                    }

                    StyledToolTip {
                        position: "top"
                        extraVisibleCondition: doneMouse.containsMouse && doneButton.tooltipText.length > 0
                        text: doneButton.tooltipText
                    }
                }
            }

            Item {
                id: headerOverlayHost
                anchors.fill: parent
                visible: root.headerOverlayActive
            }
        }

        // Hairline Separator between Top Strip and Gallery/Control Tray
        Rectangle {
            id: traySeparator
            visible: root._animatedTrayHeight > 0.5
            width: parent.width
            height: 1
            opacity: Math.min(1, root._animatedTrayHeight / 24)
            color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)
        }

        // Tier 2: Expandable Horizontal Tile Gallery / Control Tray
        Item {
            id: trayContentHost
            visible: root._animatedTrayHeight > 0.5
            width: parent.width
            height: (root.embeddedSurface && root.trayExpanded && root._animatedTrayHeight >= root.trayHeight - 1 && root.height > root.implicitHeight)
                ? Math.max(0, root.height - root.verticalPadding * 2 - root.topBarHeight - root.trayGap - 1)
                : Math.max(0, root._animatedTrayHeight)
            opacity: Math.min(1, root._animatedTrayHeight / Math.max(1, root.trayHeight * 0.55))
            clip: true
        }
    }
}
