import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property bool sharedTypography: false
    readonly property real typographyScale: sharedTypography ? 1 : Appearance.sizes.barModuleScale
    property bool borderless: Config.options?.bar?.borderless ?? false
    property bool showDate: Config.options?.bar?.verbose ?? true
    readonly property string _timeFontFamily: sharedTypography ? "" : Config.options?.bar?.clock?.timeFontFamily ?? ""
    readonly property int _timePixelSize: sharedTypography ? 0 : Config.options?.bar?.clock?.timePixelSize ?? 0
    readonly property string _dateFontFamily: sharedTypography ? "" : Config.options?.bar?.clock?.dateFontFamily ?? ""
    readonly property int _datePixelSize: sharedTypography ? 0 : Config.options?.bar?.clock?.datePixelSize ?? 0
    implicitWidth: rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        spacing: 4 * root.typographyScale

        StyledText {
            objectName:"sharedClockTime"
            font.family: root._timeFontFamily.length > 0
                ? root._timeFontFamily : Appearance.font.family.main
            font.pixelSize: root._timePixelSize > 0
                ? root._timePixelSize * root.typographyScale
                : Appearance.font.pixelSize.large * root.typographyScale
            color: Appearance.colors.colOnLayer1
            text: DateTime.timeDisplay
        }

        Revealer {
            reveal: root.showDate
            StyledText {
                font.pixelSize: Math.round(Appearance.font.pixelSize.small * root.typographyScale)
                color: Appearance.colors.colOnLayer1
                text: "•"
            }
        }

        Revealer {
            reveal: root.showDate
            StyledText {
                objectName:"sharedClockDate"
                font.family: root._dateFontFamily.length > 0
                    ? root._dateFontFamily : Appearance.font.family.main
                font.pixelSize: root._datePixelSize > 0
                    ? root._datePixelSize * root.typographyScale
                    : Appearance.font.pixelSize.small * root.typographyScale
                color: Appearance.colors.colOnLayer1
                text: DateTime.date
            }
        }
    }

    MouseArea {
        id: clockHoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    ClockCalendarPopup {
        hoverTarget: clockHoverArea
    }

}
