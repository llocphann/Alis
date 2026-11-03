pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import org.kde.kirigami as Kirigami
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    focus: true

    property var targetWindow: null
    signal confirm()
    signal cancel()

    readonly property string appId: String(targetWindow?.app_id ?? "")
    readonly property string appTitle: String(targetWindow?.title ?? "")
    readonly property string appDisplayName: appTitle || appId || Translation.tr("Unknown")
    readonly property bool showAppId: appId.length > 0
        && appId.toLowerCase() !== appDisplayName.toLowerCase()
    readonly property color dangerColor: Appearance.colors.colError
    readonly property color dangerForeground: Appearance.colors.colOnError
    readonly property color detailSurface: Appearance.colors.colLayer2
    readonly property color detailBorder: Appearance.colors.colOutlineVariant
    readonly property int detailRadius: Appearance.rounding.small

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            root.cancel()
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.confirm()
            event.accepted = true
        }
    }

    component ActionButton: RippleButton {
        id: actionButton
        required property string label
        required property string iconName
        property bool destructive: false

        implicitHeight: 36
        implicitWidth: actionRow.implicitWidth + Appearance.sizes.spacingLarge * 2
        horizontalPadding: Appearance.sizes.spacingLarge
        buttonRadius: Appearance.rounding.full
        cookieMorphing: false
        colBackground: destructive ? root.dangerColor : root.detailSurface
        colBackgroundHover: destructive
            ? Appearance.colors.colErrorHover : Appearance.colLayer2Hover
        colRipple: destructive
            ? Appearance.colors.colErrorActive : Appearance.colLayer1Active

        contentItem: RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: Appearance.sizes.spacingSmall

            MaterialSymbol {
                visible: actionButton.iconName.length > 0
                text: actionButton.iconName
                iconSize: Appearance.font.pixelSize.larger
                fill: actionButton.destructive ? 1 : 0
                color: actionButton.destructive
                    ? root.dangerForeground
                    : Appearance.colors.colOnLayer2
            }

            StyledText {
                text: actionButton.label
                font.family: Appearance.font.family.main
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: actionButton.destructive
                    ? root.dangerForeground
                    : Appearance.colors.colOnLayer2
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colScrim
        opacity: 0
        Component.onCompleted: opacity = 1
        Behavior on opacity {
            animation: NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancel()
        }
    }

    WindowDialog {
        id: dialog
        anchors.centerIn: parent
        backgroundWidth: 360
        show: false
        Component.onCompleted: show = true

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.sizes.spacingMedium

            Rectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                Layout.alignment: Qt.AlignTop
                radius: root.detailRadius
                color: root.detailSurface
                border.width: 1
                border.color: root.detailBorder

                Kirigami.Icon {
                    anchors.fill: parent
                    anchors.margins: Appearance.sizes.spacingSmall
                    source: root.appId
                    fallback: "application-x-executable"
                    roundToIconSize: false
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                WindowDialogTitle {
                    Layout.fillWidth: true
                    text: Translation.tr("Close this window?")
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.appDisplayName
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.showAppId
                    text: root.appId
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideMiddle
                    maximumLineCount: 1
                }
            }
        }

        WindowDialogButtonRow {
            spacing: Appearance.sizes.spacingSmall
            Layout.topMargin: -4

            Item { Layout.fillWidth: true }

            ActionButton {
                label: Translation.tr("Cancel")
                iconName: ""
                onClicked: root.cancel()
            }

            ActionButton {
                label: Translation.tr("Close")
                iconName: "close"
                destructive: true
                onClicked: root.confirm()
            }
        }
    }
}
