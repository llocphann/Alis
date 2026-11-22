pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.abyss.looks
import "../looks/AbyssPresentation.js" as Presentation

// Reuse actual popup/indicator layouts when doing so is side-effect free. Corner
// surfaces get a representative shell so editing their position/join never marks
// notifications read or acquires an editor lease.
Item {
    id:root
    property string kind:"volume"
    property string outputName:""
    property var participant:null
    enabled:false

    readonly property bool cornerSurface:
        ["quickNotes","notificationCenter","notifications"].includes(root.kind)
    readonly property real desiredWidth: feature.item?.implicitWidth ?? 390
    readonly property real desiredHeight: feature.item?.implicitHeight ?? 120

    Loader {
        id:feature
        anchors.fill:parent
        sourceComponent:Presentation.osds.includes(root.kind) ? indicator
            : root.kind === "polkit" ? polkitPreview
            : root.cornerSurface ? cornerPreview : popup
    }

    Component {
        id:indicator
        AbyssOsdContent { kind:root.kind;outputName:root.outputName }
    }
    Component {
        id:polkitPreview
        AbyssPolkitContent {
            previewMode:true
            outputName:root.outputName
            implicitWidth:desiredWidth
            implicitHeight:desiredHeight
        }
    }
    Component {
        id:popup
        AbyssPopupContent {
            kind:root.kind
            outputName:root.outputName
            participant:root.participant
        }
    }
    Component {
        id:cornerPreview
        Item {
            implicitWidth: root.kind === "quickNotes" ? 392
                : root.kind === "notificationCenter" ? 392 : 360
            implicitHeight: root.kind === "quickNotes" ? 272
                : root.kind === "notificationCenter" ? 500 : 220

            ColumnLayout {
                anchors.fill: parent
                spacing: 8

                AbyssLabel {
                    Layout.fillWidth: true
                    text: root.kind === "quickNotes" ? "Quick Notes · Timers"
                        : root.kind === "notificationCenter" ? "Notifications · Activity"
                        : "Notifications"
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: Qt.alpha(AbyssStyle.accent,.06)
                    border.width: 1
                    border.color: Qt.alpha(AbyssStyle.accent,.14)
                    AbyssLabel {
                        anchors.centerIn: parent
                        text: root.kind === "quickNotes" ? "Notes / To-do / Timers"
                            : root.kind === "notificationCenter" ? "Notification history / Activity"
                            : "Notification popup"
                        color: Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : "#1a1a1a"
                    }
                }
            }
        }
    }
}
