import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.settings
ContentPage {
    id: root
    property var sections: ["surface","interaction","performance","spectrum","waves"]
    property string barSection: "modules"
    property string sidebarSection: "general"
    settingsPageIndex: 2
    settingsPageName: "Surface & Waves"
    readonly property bool twoColumnModulesBar: root.sections.length === 2
        && root.sections.includes("modules") && root.sections.includes("bar")
    readonly property bool twoColumnPopups: root.sections.length === 1
        && root.sections[0] === "popups"
    readonly property real sharedModulesHeight: twoColumnGrid.columns === 2
        ? Math.max(controls.modulesCardImplicitHeight, moduleSettings.item?.modulesCardImplicitHeight ?? 0)
        : 0
    readonly property real sharedPopupsHeight: twoColumnGrid.columns === 2 && root.twoColumnPopups
        ? Math.max(controls.popupsCardImplicitHeight, popupNotificationSettings.item?.notificationsCardImplicitHeight ?? 0)
        : 0
    property alias activeSection: controls.activeSection
    function activateSettingsSearchSection(section: string): void {
        const label = String(section).toLowerCase().split(/[·›]/).pop().trim()
        const aliases = {"live editor":"editor", "audio spectrum":"spectrum",
            "customization stage (edit mode)":"surface", "customization stage":"surface", "edit mode":"surface",
            "appearance & layout":"surface", "sizing & surface":"surface",
            "behavior":"bar", "clock":"bar", "auto hide":"bar", "behavior & clock":"bar", "module behavior":"bar", "media":"bar",
            "system tray":"bar", "workspaces":"bar", "resources":"bar",
            "bar module layout":"editor", "shell layout":"editor",
            "left sidebar":"sidebars", "right sidebar":"sidebars", "opening":"sidebars", "sidebar":"sidebars", "general":"sidebars", "left":"sidebars",
            "right":"sidebars", "open":"sidebars", "media & content":"sidebars",
            "notifications":"popups", "notification center":"popups"}
        const value = aliases[label] ?? label
        if (["surface","waves","spectrum","modules","bar","dock","sidebars","popups","editor","interaction","performance"].includes(value)) {
            root.barSection = ["behavior","module behavior","behavior & clock","clock","auto hide"].includes(label) ? "behavior" : "modules"
            root.sidebarSection = ({"left sidebar":"left","right sidebar":"right","media & content":"media","opening":"open"}[label] ?? (["general","left","right","media","open"].includes(label) ? label : "general"))
            activeSection = value
            if (value === "bar" && moduleSettings.item)
                moduleSettings.item.activeSection = root.barSection
            if (value === "sidebars" && sidebarSettings.item)
                sidebarSettings.item.activeSection = root.sidebarSection
        }
    }
    GridLayout {
        id: twoColumnGrid
        Layout.fillWidth: true
        columns: (root.twoColumnModulesBar || root.twoColumnPopups) && width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14

        ColumnLayout {
            id: leftModulesColumn
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 0

            AbyssStyleSettings {
                id: controls
                visible: !root.twoColumnModulesBar
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                modulesCardMinHeight: 0
                popupsCardMinHeight: root.sharedPopupsHeight
                hostPageHeight: root.height
                hostSubTabCount: root._subTabItems.length
                sections: root.sections
                activeSection: root.sections[0]
            }
            Loader {
                id: behaviorSettings
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.preferredHeight: item?.implicitHeight ?? 0
                visible: active
                active: root.twoColumnModulesBar
                source: "BarConfig.qml"
                onLoaded: {
                    item.embedded = true
                    item.settingsPageIndex = root.settingsPageIndex
                    item.activeSection = "behavior"
                    item.abyssCardFilter = "behavior_and_quick_actions"
                }
            }
        }
        Loader {
            id: moduleSettings
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: item?.implicitHeight ?? 0
            visible: active
            active: controls.activeSection === "bar" || root.twoColumnModulesBar
            source: "BarConfig.qml"
            onLoaded: {
                item.embedded = true
                item.settingsPageIndex = root.settingsPageIndex
                item.activeSection = root.twoColumnModulesBar ? "modules" : root.barSection
                item.abyssCardFilter = root.twoColumnModulesBar ? "workspaces_and_tray" : ""
                item.modulesCardMinHeight = 0
            }
        }
        Loader {
            id: popupNotificationSettings
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            Layout.preferredHeight: item?.implicitHeight ?? 0
            visible: active
            active: controls.activeSection === "popups"
            source: "InterfaceConfig.qml"
            onLoaded: {
                item.embedded = true
                item.settingsPageIndex = root.settingsPageIndex
                item.activeSection = "notifications"
                item.notificationsCardMinHeight = Qt.binding(() => root.sharedPopupsHeight)
            }
        }
    }
    Loader {
        Layout.fillWidth: true
        Layout.preferredHeight: item?.implicitHeight ?? 0
        visible: active
        active: controls.activeSection === "dock"
        source: "DockConfig.qml"
        onLoaded: item.embedded = true
    }
    Loader {
        id: sidebarSettings
        Layout.fillWidth: true
        Layout.preferredHeight: item?.implicitHeight ?? 0
        visible: active
        active: controls.activeSection === "sidebars"
        source: "SidebarsConfig.qml"
        onLoaded: { item.embedded = true; item.activeSection = root.sidebarSection }
    }
}
