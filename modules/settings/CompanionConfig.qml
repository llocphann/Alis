import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property bool embedded: false
    property string activeSection: "overview"
    readonly property int settingsPageIndex: 37
    readonly property string settingsPageName: Translation.tr("Companion")
    readonly property var settingsTaskNavigator: settingsLoader.item?.settingsTaskNavigator ?? null
    implicitHeight: embedded ? (settingsLoader.item?.implicitHeight ?? missing.implicitHeight) : 0

    Loader {
        id: settingsLoader
        anchors.fill: parent
        active: AlisCompanion.available
        source: AlisCompanion.settingsSource
        Binding { target: settingsLoader.item; property: "embedded"; value: root.embedded; when: !!settingsLoader.item }
        Binding { target: settingsLoader.item; property: "activeSection"; value: root.activeSection; when: !!settingsLoader.item }
    }

    ColumnLayout {
        id: missing
        visible: !AlisCompanion.available
        anchors { top: parent.top; left: parent.left; right: parent.right; margins: 24 }
        spacing: 16
        StyledText {
            text: Translation.tr("Companion unavailable. Run ./setup update, then Recheck Companion.")
            wrapMode: Text.Wrap
            Layout.fillWidth: true
        }
        DialogButton {
            buttonText: Translation.tr("Recheck Companion")
            onClicked: AlisCompanion.refresh()
        }
    }
}
