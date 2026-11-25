pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle.looks as Waffle

ColumnLayout {
    id: root
    objectName: "waffleSettingsRailHeader"

    property string searchQuery: ""
    property int resultCount: 0
    property alias searchField: searchInput

    signal accountClicked()
    signal searchTextEdited(string query)
    signal focusResultsRequested()
    signal acceptCurrentResultRequested()
    signal clearSearchRequested()
    signal escapeEmptySearchRequested()

    function focusSearch(): void {
        searchInput.forceActiveFocus()
    }

    spacing: 8

    // ── Windows 11 Top User Account Header ──
    Waffle.WBorderlessButton {
        id: accountBtn
        objectName: "waffleSettingsAccountHeader"
        Layout.fillWidth: true
        implicitHeight: Waffle.Looks.dp(58)
        colBackground: "transparent"
        colBackgroundHover: SettingsMaterialPreset.navHoverColor
        colBackgroundActive: SettingsMaterialPreset.navSelectedHoverColor
        onClicked: root.accountClicked()

        background: Rectangle {
            radius: SettingsMaterialPreset.navItemRadius
            color: accountBtn.color
        }

        contentItem: RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 12

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Waffle.Looks.dp(44)
                implicitHeight: Waffle.Looks.dp(44)
                radius: width / 2
                color: SettingsMaterialPreset.cardColor
                border.width: 1
                border.color: SettingsMaterialPreset.cardBorderColor

                Waffle.WUserAvatar {
                    anchors.centerIn: parent
                    sourceSize: Qt.size(Waffle.Looks.dp(42), Waffle.Looks.dp(42))
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                Waffle.WText {
                    objectName: "waffleSettingsAccountName"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    verticalAlignment: Text.AlignVCenter
                    text: SystemInfo.displayName || SystemInfo.username || "User"
                    font.pixelSize: Waffle.Looks.dp(14)
                    font.weight: Font.DemiBold
                    color: SettingsMaterialPreset.textColor
                    elide: Text.ElideRight
                }

                Waffle.WText {
                    objectName: "waffleSettingsAccountSubtitle"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    verticalAlignment: Text.AlignVCenter
                    text: {
                        const uname = String(SystemInfo.username || "").trim()
                        const distro = String(SystemInfo.distroName || "Local Account").trim()
                        return uname.length > 0 ? `${uname} · ${distro}` : distro
                    }
                    font.pixelSize: Waffle.Looks.dp(11)
                    color: SettingsMaterialPreset.secondaryTextColor
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ── Windows 11 WinUI 3 "Find a setting" Search Box with Bottom Accent Underline ──
    Rectangle {
        id: searchBox
        objectName: "waffleSettingsSearchBox"
        Layout.fillWidth: true
        implicitHeight: Waffle.Looks.dp(36)
        radius: SettingsMaterialPreset.searchRadius
        color: searchInput.activeFocus
            ? (Waffle.Looks.dark ? "#1f1f1f" : "#ffffff")
            : SettingsMaterialPreset.searchColor
        border.width: 1
        border.color: SettingsMaterialPreset.cardBorderColor
        clip: true

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation { duration: 120 }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 11
            anchors.rightMargin: 8
            spacing: 6

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumWidth: 0

                Waffle.WText {
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    visible: searchInput.text.length === 0
                    text: "Find a setting"
                    font.pixelSize: Waffle.Looks.dp(13)
                    color: SettingsMaterialPreset.secondaryTextColor
                    elide: Text.ElideRight
                }

                TextInput {
                    id: searchInput
                    objectName: "waffleSettingsSearchInput"
                    anchors.fill: parent
                    verticalAlignment: Text.AlignVCenter
                    clip: true
                    selectByMouse: true
                    color: SettingsMaterialPreset.textColor
                    selectionColor: Waffle.Looks.colors.selection
                    selectedTextColor: Waffle.Looks.colors.selectionFg
                    font.family: SettingsMaterialPreset.fontFamily
                    font.pixelSize: Waffle.Looks.dp(13)
                    text: root.searchQuery

                    onTextChanged: {
                        if (text !== root.searchQuery)
                            root.searchTextEdited(text)
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Down && root.resultCount > 0) {
                            root.focusResultsRequested()
                            event.accepted = true
                        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                && root.resultCount > 0) {
                            root.acceptCurrentResultRequested()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Escape) {
                            if (searchInput.text.length > 0) {
                                searchInput.text = ""
                                root.clearSearchRequested()
                            } else {
                                searchInput.focus = false
                                root.escapeEmptySearchRequested()
                            }
                            event.accepted = true
                        }
                    }
                }
            }

            Waffle.WBorderlessButton {
                objectName: "waffleSettingsSearchClear"
                visible: searchInput.text.length > 0
                implicitWidth: Waffle.Looks.dp(24)
                implicitHeight: Waffle.Looks.dp(24)
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                    searchInput.text = ""
                    root.clearSearchRequested()
                    searchInput.forceActiveFocus()
                }

                contentItem: Item {
                    Waffle.FluentIcon {
                        anchors.centerIn: parent
                        monochrome: true
                        icon: "dismiss"
                        implicitSize: Waffle.Looks.dp(12)
                        color: SettingsMaterialPreset.secondaryTextColor
                    }
                }
            }

            Waffle.FluentIcon {
                Layout.alignment: Qt.AlignVCenter
                monochrome: true
                icon: "search"
                implicitSize: Waffle.Looks.dp(14)
                color: searchInput.activeFocus
                    ? SettingsMaterialPreset.accentColor
                    : SettingsMaterialPreset.secondaryTextColor
            }
        }

        Rectangle {
            id: bottomAccentLine
            objectName: "waffleSettingsSearchUnderline"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: searchInput.activeFocus ? 0 : 1
            anchors.rightMargin: searchInput.activeFocus ? 0 : 1
            height: searchInput.activeFocus ? 2 : 1
            radius: searchInput.activeFocus ? 1 : 0
            color: searchInput.activeFocus
                ? SettingsMaterialPreset.accentColor
                : SettingsMaterialPreset.searchBottomLineColor

            Behavior on color {
                enabled: Appearance.animationsEnabled
                ColorAnimation { duration: 120 }
            }
        }
    }
}
