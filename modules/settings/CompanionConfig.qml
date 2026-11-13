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
    property var categorySiblingPages: []
    readonly property int settingsPageIndex: 37
    readonly property string settingsPageName: Translation.tr("Companion")
    readonly property var settingsTaskNavigator: settingsLoader.item?.settingsTaskNavigator ?? null
    implicitHeight: embedded ? (settingsLoader.item?.implicitHeight ?? missing.implicitHeight) : 0

    signal pageNavigationRequested(int targetPageIndex)
    signal pageSectionNavigationRequested(int targetPageIndex, string targetSection)

    function refreshCompanionModels(): void {
        if (settingsLoader.item && typeof settingsLoader.item.refreshCompanionModels === "function") {
            settingsLoader.item.refreshCompanionModels()
        }
    }

    Loader {
        id: settingsLoader
        anchors.fill: parent
        active: AlisCompanion.available && AlisCompanion.settingsSource.length > 0
        function reloadSource(): void {
            if (active && AlisCompanion.settingsSource.length > 0) {
                setSource(AlisCompanion.settingsSource, {
                    embedded: root.embedded,
                    activeSection: root.activeSection,
                    categorySiblingPages: root.categorySiblingPages
                })
            } else {
                source = ""
            }
        }
        Component.onCompleted: reloadSource()
        onActiveChanged: reloadSource()
        Connections {
            target: AlisCompanion
            function onSettingsSourceChanged(): void { settingsLoader.reloadSource() }
        }
        Binding { target: settingsLoader.item; property: "embedded"; value: root.embedded; when: !!settingsLoader.item }
        Binding { target: settingsLoader.item; property: "activeSection"; value: root.activeSection; when: !!settingsLoader.item }
        Binding { target: settingsLoader.item; property: "categorySiblingPages"; value: root.categorySiblingPages; when: !!settingsLoader.item && settingsLoader.item.hasOwnProperty("categorySiblingPages") }
        Connections {
            target: settingsLoader.item
            ignoreUnknownSignals: true
            function onPageNavigationRequested(targetPageIndex: int): void {
                root.pageNavigationRequested(targetPageIndex)
            }
            function onPageSectionNavigationRequested(targetPageIndex: int, targetSection: string): void {
                root.pageSectionNavigationRequested(targetPageIndex, targetSection)
            }
        }
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
