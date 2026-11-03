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
    property real contentRotation: 0
    readonly property bool verticalContent: Math.abs(root.contentRotation) === 90
    readonly property string _timeFontFamily: sharedTypography ? "" : Config.options?.bar?.clock?.timeFontFamily ?? ""
    readonly property int _timePixelSize: sharedTypography ? 0 : Config.options?.bar?.clock?.timePixelSize ?? 0
    readonly property string _dateFontFamily: sharedTypography ? "" : Config.options?.bar?.clock?.dateFontFamily ?? ""
    readonly property int _datePixelSize: sharedTypography ? 0 : Config.options?.bar?.clock?.datePixelSize ?? 0
    readonly property var verticalTimeLines: String(DateTime.timeDisplay ?? "")
        .split(/[:\s]+/)
        .filter(part => part.length > 0)
    readonly property var verticalDateItems: {
        const raw = String(DateTime.date ?? "").trim()
        if (!raw) return []
        const tokens = raw.split(/[,\s]+/).filter(t => t.length > 0)
        const items = []
        for (const token of tokens) {
            if (/^[A-Za-zÀ-ỹ]+$/.test(token) && token.length > 3) {
                const shortDay = Qt.locale().toString(DateTime.clock.date, "ddd").replace(/\.$/, "")
                items.push({
                    text: shortDay.length > 0 && shortDay.length <= 4 ? shortDay : token.slice(0, 3),
                    slashBefore: false
                })
            } else if (/[\/.-]/.test(token)) {
                const parts = token.split(/[\/.-]+/).filter(p => p.length > 0)
                for (let i = 0; i < parts.length; ++i) {
                    const part = parts[i]
                    items.push({
                        text: /^\d{4}$/.test(part) ? part.slice(2) : part,
                        slashBefore: i > 0
                    })
                }
            } else {
                items.push({ text: token, slashBefore: false })
            }
        }
        return items
    }
    implicitWidth: root.verticalContent
        ? Math.max(40, verticalColumn.implicitHeight + 12 * root.typographyScale)
        : rowLayout.implicitWidth
    implicitHeight: Appearance.sizes.barHeight

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent
        opacity: root.verticalContent ? 0 : 1
        rotation: root.verticalContent ? 0 : -root.contentRotation
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

    ColumnLayout {
        id: verticalColumn
        anchors.centerIn: parent
        visible: root.verticalContent
        rotation: -root.contentRotation
        spacing: 1 * root.typographyScale

        Repeater {
            model: root.verticalTimeLines
            delegate: StyledText {
                required property string modelData
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                font.family: root._timeFontFamily.length > 0
                    ? root._timeFontFamily : Appearance.font.family.main
                font.pixelSize: modelData.match(/am|pm/i)
                    ? Math.round(Appearance.font.pixelSize.smaller * root.typographyScale)
                    : (root._timePixelSize > 0
                        ? root._timePixelSize * root.typographyScale
                        : Appearance.font.pixelSize.large * root.typographyScale)
                color: Appearance.colors.colOnLayer1
                text: modelData
            }
        }

        Rectangle {
            visible: root.showDate && root.verticalDateItems.length > 0
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 2 * root.typographyScale
            Layout.bottomMargin: 2 * root.typographyScale
            implicitWidth: 16 * root.typographyScale
            implicitHeight: 1
            color: Appearance.colors.colOnLayer1
            opacity: 0.45
        }

        Repeater {
            model: root.showDate ? root.verticalDateItems : []
            delegate: ColumnLayout {
                required property var modelData
                Layout.alignment: Qt.AlignHCenter
                spacing: 1 * root.typographyScale

                Rectangle {
                    visible: Boolean(modelData?.slashBefore)
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 8 * root.typographyScale
                    implicitHeight: 1
                    rotation: -14
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.4
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root._dateFontFamily.length > 0
                        ? root._dateFontFamily : Appearance.font.family.main
                    font.pixelSize: root._datePixelSize > 0
                        ? root._datePixelSize * root.typographyScale
                        : Appearance.font.pixelSize.small * root.typographyScale
                    color: Appearance.colors.colOnLayer1
                    text: String(modelData?.text ?? "")
                }
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
