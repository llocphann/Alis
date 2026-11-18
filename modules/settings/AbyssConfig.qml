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
        ? Math.max(controls.popupsCardImplicitHeight, rightPopupsColumn.implicitHeight)
        : 0
    property alias activeSection: controls.activeSection

    function activateSection(section: string): void {
        const raw = String(section ?? "").trim()
        const lower = raw.toLowerCase()
        if (lower === "editmode" || lower === "edit mode" || lower === "editor" || lower === "live editor") {
            const target = root.twoColumnModulesBar
                ? "bar"
                : (root.sections.includes("surface") ? "surface" : (root.sections[0] ?? "surface"))
            activeSection = target
            if (target === "bar" && moduleSettings.item)
                moduleSettings.item.activeSection = root.barSection
            return
        }
        activateSettingsSearchSection(raw)
    }

    function activateSettingsSearchSection(section: string): void {
        const label = String(section).toLowerCase().split(/[·›]/).pop().trim()
        const fallbackEditor = root.twoColumnModulesBar ? "bar" : "surface"
        const aliases = {"live editor": fallbackEditor, "editor": fallbackEditor, "editmode": fallbackEditor, "audio spectrum":"spectrum",
            "customization stage (edit mode)": fallbackEditor, "customization stage": fallbackEditor, "edit mode": fallbackEditor,
            "appearance & layout":"surface", "sizing & surface":"surface",
            "behavior":"bar", "clock":"bar", "auto hide":"bar", "behavior & clock":"bar", "module behavior":"bar", "media":"bar",
            "system tray":"bar", "workspaces":"bar", "resources":"bar",
            "bar module layout": fallbackEditor, "shell layout": fallbackEditor,
            "left sidebar":"sidebars", "right sidebar":"sidebars", "opening":"sidebars", "sidebar":"sidebars", "general":"sidebars", "left":"sidebars",
            "right":"sidebars", "open":"sidebars", "media & content":"sidebars",
            "notifications":"popups", "notification center":"popups"}
        const value = aliases[label] ?? label
        if (["surface","waves","spectrum","modules","bar","dock","sidebars","popups","interaction","performance"].includes(value)) {
            root.barSection = ["behavior","module behavior","behavior & clock","clock","auto hide"].includes(label) ? "behavior" : "modules"
            root.sidebarSection = ({"left sidebar":"left","right sidebar":"right","media & content":"media","opening":"open"}[label] ?? (["general","left","right","media","open"].includes(label) ? label : "general"))
            activeSection = value
            if (value === "bar" && moduleSettings.item)
                moduleSettings.item.activeSection = root.barSection
            if (value === "sidebars" && sidebarSettings.item)
                sidebarSettings.item.activeSection = root.sidebarSection
        }
    }
    Timer {
        id: barEqualizeTimer
        interval: 0
        repeat: false
        onTriggered: root._syncBarColumnHeights()
    }

    function _collectVisibleCards(rootItem) {
        var cards = []
        if (!rootItem)
            return cards
        function walk(node) {
            if (!node)
                return
            if (node._bentoExtraHeight !== undefined && node.naturalCardImplicitHeight !== undefined && node.visible) {
                cards.push(node)
                return
            }
            var ch = node.children || []
            for (var i = 0; i < ch.length; i++)
                walk(ch[i])
        }
        walk(rootItem)
        return cards
    }

    function _syncBarColumnHeights(): void {
        if (!root.twoColumnModulesBar)
            return
        var leftCards = root._collectVisibleCards(behaviorSettings.item)
        var rightCards = root._collectVisibleCards(moduleSettings.item)
        var allCards = leftCards.concat(rightCards)
        for (var k = 0; k < allCards.length; k++) {
            if (allCards[k]._bentoExtraHeight !== 0)
                allCards[k]._bentoExtraHeight = 0
        }
    }

    onTargetBentoHeightChanged: if (root.twoColumnModulesBar) barEqualizeTimer.restart()

    GridLayout {
        id: twoColumnGrid
        Layout.fillWidth: true
        columns: (root.twoColumnModulesBar || root.twoColumnPopups) && width >= 620 ? 2 : 1
        uniformCellWidths: columns === 2
        columnSpacing: 14
        rowSpacing: 14
        onColumnsChanged: if (root.twoColumnModulesBar) barEqualizeTimer.restart()

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
                hostTargetBentoHeight: root.targetBentoHeight
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
                    barEqualizeTimer.restart()
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
                barEqualizeTimer.restart()
            }
        }
        ColumnLayout {
            id: rightPopupsColumn
            visible: controls.activeSection === "popups"
            Layout.preferredWidth: 1
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: SettingsMaterialPreset.pageSpacing

            Loader {
                id: popupNotificationSettings
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
                    item.notificationsCardMinHeight = 0
                }
            }

            SettingsCardSection {
                id: edgebarPopupsCard
                _preventBentoReparent: true
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignTop
                settingsTaskSection: "popups"
                visible: controls.activeSection === "popups"
                expanded: true
                icon: "south_east"
                title: "Corner Hover Triggers"

                SettingsGroup {
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        columns: width >= 360 ? 2 : 1
                        uniformCellWidths: columns === 2
                        columnSpacing: 10
                        rowSpacing: 8

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            icon: "hourglass"
                            text: "Notifications delay (ms)"
                            value: Config.options?.notificationCenter?.hoverDelayMs ?? 220
                            from: 0
                            to: 1200
                            stepSize: 20
                            onValueChanged: Config.setNestedValue("notificationCenter.hoverDelayMs", value)
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            icon: "select"
                            text: "Notifications hit (px)"
                            value: Config.options?.notificationCenter?.cornerSize ?? 14
                            from: 8
                            to: 48
                            stepSize: 1
                            onValueChanged: Config.setNestedValue("notificationCenter.cornerSize", value)
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            icon: "schedule"
                            text: "Quick Notes delay (ms)"
                            value: Config.options?.quickNotes?.hoverDelayMs ?? 220
                            from: 0
                            to: 1200
                            stepSize: 20
                            onValueChanged: Config.setNestedValue("quickNotes.hoverDelayMs", value)
                        }

                        ConfigSpinBox {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.minimumWidth: 0
                            icon: "crop_free"
                            text: "Quick Notes hit (px)"
                            value: Config.options?.quickNotes?.cornerSize ?? 14
                            from: 8
                            to: 48
                            stepSize: 1
                            onValueChanged: Config.setNestedValue("quickNotes.cornerSize", value)
                        }
                    }
                }
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
