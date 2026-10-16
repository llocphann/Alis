import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.settings
ContentPage {
    id: root
    property var sections: ["surface","performance"]
    property string barSection: "modules"
    property string sidebarSection: "general"
    settingsPageIndex: 2
    settingsPageName: "Abyss"
    property alias activeSection: controls.activeSection
    function activateSettingsSearchSection(section: string): void {
        const label = String(section).toLowerCase().split(/[·›]/).pop().trim()
        const aliases = {"live editor":"editor", "audio spectrum":"spectrum",
            "appearance & layout":"surface", "sizing & surface":"surface",
            "behavior":"bar", "clock":"bar", "auto hide":"bar", "behavior & clock":"bar", "module behavior":"bar", "media":"bar",
            "system tray":"bar", "workspaces":"bar", "resources":"bar",
            "bar module layout":"editor", "shell layout":"editor",
            "left sidebar":"sidebars", "right sidebar":"sidebars", "opening":"sidebars", "sidebar":"sidebars", "general":"sidebars", "left":"sidebars",
            "right":"sidebars", "open":"sidebars", "media & content":"sidebars"}
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
    AbyssStyleSettings { id: controls;sections:root.sections;activeSection:root.sections[0] }
    Loader {
        id: moduleSettings
        Layout.fillWidth: true
        Layout.preferredHeight: item?.implicitHeight ?? 0
        visible: active
        active: controls.activeSection === "bar"
        source: "BarConfig.qml"
        onLoaded: { item.embedded = true; item.settingsPageIndex = root.settingsPageIndex; item.activeSection = root.barSection }
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
