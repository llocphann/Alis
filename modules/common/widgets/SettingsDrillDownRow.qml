import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RippleButton {
    id: root
    objectName: "settingsDrillDownRow"

    property string iconName: "tune"
    property string title: ""
    property string description: ""
    property alias subtitle: root.description
    property string statusText: ""
    property alias badgeText: root.statusText
    property color accentColor: Appearance.colors.colPrimary
    property bool compact: false

    signal activated()

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    implicitHeight: Math.round((root.compact ? 44 : 52) * Appearance.fontSizeScale)
    buttonRadius: SettingsMaterialPreset.cardRadius
    colBackground: SettingsMaterialPreset.cardColor
    colBackgroundHover: SettingsMaterialPreset.headerHoverColor
    colRipple: Appearance.colors.colLayer2Active

    onClicked: root.activated()

    Rectangle {
        anchors.fill: parent
        radius: root.buttonRadius
        color: "transparent"
        border.width: Config.options?.panelFamily === "abyss" ? 0 : 1
        border.color: root.hovered
            ? ColorUtils.applyAlpha(root.accentColor, 0.35)
            : SettingsMaterialPreset.cardBorderColor
    }

    contentItem: RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Math.round(12 * Appearance.fontSizeScale)
        anchors.rightMargin: Math.round(12 * Appearance.fontSizeScale)
        spacing: Math.round(10 * Appearance.fontSizeScale)

        // iOS / macOS Sequoia rounded colored icon badge
        Rectangle {
            Layout.preferredWidth: Math.round((root.compact ? 28 : 32) * Appearance.fontSizeScale)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            radius: Math.round(8 * Appearance.fontSizeScale)
            color: ColorUtils.applyAlpha(root.accentColor, 0.16)

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.iconName && root.iconName.length > 0 ? root.iconName : "tune"
                iconSize: Math.round((root.compact ? 16 : 18) * Appearance.fontSizeScale)
                color: root.accentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurface
                marquee: true
                maximumLineCount: 1
            }

            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Rectangle {
            visible: root.statusText.length > 0
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(22 * Appearance.fontSizeScale)
            implicitWidth: statusLabel.implicitWidth + Math.round(14 * Appearance.fontSizeScale)
            radius: height / 2
            color: ColorUtils.applyAlpha(Appearance.colors.colLayer2, 0.7)

            StyledText {
                id: statusLabel
                anchors.centerIn: parent
                text: root.statusText
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: Appearance.colors.colSubtext
            }
        }

        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: "chevron_right"
            iconSize: Math.round(20 * Appearance.fontSizeScale)
            color: root.hovered ? root.accentColor : Appearance.colors.colSubtext
        }
    }
}
