pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

// Spotlight / command-palette live search results canvas for Settings.
// Replaces the active page cleanly while keeping pages cached underneath.
Item {
    id: root

    property string query: ""
    property var results: []
    property Item searchField: null
    property var iconForPage: (index) => "search"
    signal activated(var entry)
    signal closeRequested()

    readonly property bool searching: query.trim().length > 0
    visible: searching
    enabled: searching

    function focusResults(): void {
        if (resultsList.count <= 0) return
        if (resultsList.currentIndex < 0
                || resultsList.currentIndex >= resultsList.count)
            resultsList.currentIndex = 0
        resultsList.forceActiveFocus()
    }

    function activateCurrent(): void {
        if (resultsList.count <= 0) return
        const index = resultsList.currentIndex >= 0
            && resultsList.currentIndex < resultsList.count
                ? resultsList.currentIndex : 0
        root.activated(root.results[index])
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 12
        radius: SettingsMaterialPreset.cardRadius
        color: SettingsMaterialPreset.cardColor
        border.width: 1
        border.color: SettingsMaterialPreset.cardBorderColor
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredWidth: 30
                    Layout.preferredHeight: 30
                    radius: 9
                    color: SettingsMaterialPreset.accentTint
                    border.width: 1
                    border.color: SettingsMaterialPreset.accentBorder

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "manage_search"
                        iconSize: 17
                        color: Appearance.colors.colPrimary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Search results")
                    font.family: SettingsMaterialPreset.fontFamily
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: SettingsMaterialPreset.textColor
                }

                // Subtle keyboard shortcut hint strip
                Row {
                    visible: root.results.length > 0 && root.width >= 520
                    spacing: 6
                    Layout.alignment: Qt.AlignVCenter

                    Repeater {
                        model: [
                            { key: "↑↓", label: Translation.tr("Move") },
                            { key: "↵", label: Translation.tr("Open") },
                            { key: "Esc", label: Translation.tr("Clear") }
                        ]

                        delegate: Row {
                            required property var modelData
                            spacing: 4

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitWidth: hintKeyTxt.implicitWidth + 10
                                implicitHeight: 20
                                radius: 5
                                color: SettingsMaterialPreset.controlSurface
                                border.width: 1
                                border.color: SettingsMaterialPreset.controlBorderColor

                                StyledText {
                                    id: hintKeyTxt
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: modelData.key
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    font.weight: Font.DemiBold
                                    color: SettingsMaterialPreset.secondaryTextColor
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: SettingsMaterialPreset.secondaryTextColor
                                opacity: 0.85
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: 24
                    implicitWidth: Math.max(28, resultBadgeText.implicitWidth + 14)
                    radius: height / 2
                    color: SettingsMaterialPreset.accentTint
                    border.width: 1
                    border.color: SettingsMaterialPreset.accentBorder

                    StyledText {
                        id: resultBadgeText
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.results.length.toString()
                        font.family: Appearance.font.family.numbers
                        font.features: ({ "tnum": 1 })
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: SettingsMaterialPreset.plateDividerColor
            }

            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.results.length > 0
                model: root.results
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                currentIndex: -1
                onCountChanged: currentIndex = count > 0 ? 0 : -1

                ScrollBar.vertical: StyledScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up) {
                        if (currentIndex > 0) currentIndex--
                        else if (root.searchField) root.searchField.forceActiveFocus()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        if (currentIndex < count - 1) currentIndex++
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return
                            || event.key === Qt.Key_Enter) {
                        root.activateCurrent()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Escape) {
                        root.closeRequested()
                        if (root.searchField) root.searchField.forceActiveFocus()
                        event.accepted = true
                    }
                }

                delegate: RippleButton {
                    id: resultRow
                    required property var modelData
                    required property int index

                    width: resultsList.width
                    implicitHeight: Math.round(54 * Appearance.fontSizeScale)
                    buttonRadius: 10
                    colBackground: resultRow.ListView.isCurrentItem
                        ? SettingsMaterialPreset.controlSurfaceHover : "transparent"
                    colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                    Keys.forwardTo: [resultsList]
                    onClicked: root.activated(modelData)

                    Rectangle {
                        visible: resultRow.ListView.isCurrentItem
                        anchors.left: parent.left
                        anchors.leftMargin: 3
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        height: 22
                        radius: 1.5
                        color: Appearance.colors.colPrimary
                    }

                    contentItem: RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 11

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            Layout.alignment: Qt.AlignVCenter
                            radius: 9
                            color: resultRow.ListView.isCurrentItem
                                ? SettingsMaterialPreset.accentTint
                                : SettingsMaterialPreset.controlSurface
                            border.width: 1
                            border.color: resultRow.ListView.isCurrentItem
                                ? SettingsMaterialPreset.accentBorder
                                : SettingsMaterialPreset.controlBorderColor

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: root.iconForPage(resultRow.modelData.pageIndex)
                                iconSize: 17
                                color: resultRow.ListView.isCurrentItem
                                    ? Appearance.colors.colPrimary
                                    : SettingsMaterialPreset.secondaryTextColor
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 2

                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: resultRow.modelData.labelHighlighted
                                    || resultRow.modelData.label
                                    || resultRow.modelData.pageName || ""
                                textFormat: Text.StyledText
                                font.family: SettingsMaterialPreset.fontFamily
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: SettingsMaterialPreset.textColor
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                readonly property string pageName:
                                    resultRow.modelData.pageName || ""
                                readonly property string sectionName: {
                                    const section = String(resultRow.modelData.section || "")
                                    const pieces = section.split(/\s*[·›]\s*/).filter(part => part.length > 0)
                                    if (pieces.length > 1 && pieces[0] === pageName) pieces.shift()
                                    return pieces.join(" › ")
                                }
                                text: sectionName && sectionName !== pageName
                                    ? pageName + " › " + sectionName : pageName
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: SettingsMaterialPreset.secondaryTextColor
                                elide: Text.ElideRight
                                wrapMode: Text.NoWrap
                            }
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "chevron_right"
                            iconSize: 18
                            color: resultRow.ListView.isCurrentItem
                                ? Appearance.colors.colPrimary
                                : SettingsMaterialPreset.secondaryTextColor
                            opacity: resultRow.hovered || resultRow.ListView.isCurrentItem ? 1 : 0.45
                        }
                    }
                }
            }

            // Empty state
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.results.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 44
                        height: 44
                        radius: 13
                        color: SettingsMaterialPreset.controlSurface
                        border.width: 1
                        border.color: SettingsMaterialPreset.controlBorderColor

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "search_off"
                            iconSize: 22
                            color: SettingsMaterialPreset.secondaryTextColor
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("No results found")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: SettingsMaterialPreset.textColor
                    }

                    RippleButton {
                        objectName: "settingsLiveSearchClearButton"
                        Layout.alignment: Qt.AlignHCenter
                        Accessible.name: Translation.tr("Clear search")
                        implicitHeight: 32
                        implicitWidth: clearEmptyRow.implicitWidth + 24
                        buttonRadius: height / 2
                        colBackground: SettingsMaterialPreset.controlSurface
                        colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                        onClicked: {
                            root.closeRequested()
                            if (root.searchField)
                                root.searchField.forceActiveFocus()
                        }

                        contentItem: Item {
                            implicitWidth: clearEmptyRow.implicitWidth
                            implicitHeight: clearEmptyRow.implicitHeight
                            Row {
                                id: clearEmptyRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "close"
                                    iconSize: 15
                                    color: SettingsMaterialPreset.textColor
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Clear search")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.Medium
                                    color: SettingsMaterialPreset.textColor
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
