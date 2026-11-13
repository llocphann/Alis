pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

Item {
    id: root

    property string icon: "tune"
    property string title: ""
    property string description: ""
    property string summary: ""
    property bool showTabBar: true
    property bool showSummary: false
    property bool showIntro: false
    property string currentValue: ""
    property var options: []
    property var searchAliases: ({})
    property bool highContrastSelection: false
    property bool activeNavigator: true
    readonly property bool abyssTaskStyle: Config.options?.panelFamily === "abyss"
    readonly property bool _hasVisibleContent: false

    signal selected(string value)

    implicitWidth: 0
    implicitHeight: 0
    Layout.fillWidth: true
    Layout.preferredHeight: 0
    Layout.maximumHeight: 0
    opacity: 0
    clip: true

    function _normalizeSearchLabel(value): string {
        return String(value || "")
            .toLowerCase()
            .split(/[·›]/)
            .map(part => part.trim())
            .filter(part => part.length > 0)
            .pop() || ""
    }

    function resolveSearchSection(section): string {
        const label = _normalizeSearchLabel(section)
        if (!label.length)
            return ""
        const aliased = searchAliases?.[label]
        if (aliased !== undefined)
            return String(aliased)
        for (let i = 0; i < options.length; ++i) {
            const option = options[i] ?? ({})
            if (_normalizeSearchLabel(option.displayName) === label
                    || _normalizeSearchLabel(option.value) === label)
                return String(option.value ?? "")
        }
        return ""
    }

    function activateSearchSection(section): bool {
        const value = resolveSearchSection(section)
        if (!value.length)
            return false
        root.selected(value)
        const page = _findSettingsPage()
        if (page && typeof page.syncTaskNavigatorSelection === "function") {
            page.syncTaskNavigatorSelection(value)
        }
        return true
    }

    function _findSettingsPage(): var {
        let item = root.parent
        while (item) {
            if (item.hasOwnProperty("settingsPageIndex")
                    && item.hasOwnProperty("settingsTaskNavigator"))
                return item
            item = item.parent
        }
        return null
    }

    function _notifyPage(): void {
        const page = _findSettingsPage()
        if (!page)
            return
        if (typeof page.syncTaskNavigatorSelection === "function") {
            page.syncTaskNavigatorSelection(root.currentValue)
        }
        if (typeof page.notifyCardEligibilityChanged === "function") {
            page.notifyCardEligibilityChanged()
        }
    }

    onCurrentValueChanged: root._notifyPage()
    onOptionsChanged: root._notifyPage()
    onVisibleChanged: root._notifyPage()
    onShowTabBarChanged: root._notifyPage()

    Component.onCompleted: {
        const page = _findSettingsPage()
        if (!page)
            return
        const isTopLevel = root.parent === page.pageBodyColumn || root.parent === page.navigatorHeaderHost
        const current = page.settingsTaskNavigator
        const currentActive = current && current.visible && current.showTabBar && (current.options?.length ?? 0) > 1
        const rootActive = root.showTabBar && (root.options?.length ?? 0) > 1
        if (!current || (isTopLevel && (rootActive || !currentActive))) {
            page.settingsTaskNavigator = root
        }
        root._notifyPage()
    }

    Component.onDestruction: {
        const page = _findSettingsPage()
        if (page && page.settingsTaskNavigator === root)
            page.settingsTaskNavigator = null
    }

    Item {
        visible: root.options.length > 0
        implicitWidth: root.width
        width: root.width
        implicitHeight: taskOptions.implicitHeight + padding * 2
        readonly property real padding: root.abyssTaskStyle ? SettingsMaterialPreset.taskTabPadding : 0
        readonly property color introCardColor: root.abyssTaskStyle ? SettingsMaterialPreset.cardColor : Appearance.colors.colLayer1

        Rectangle {
            objectName: "settingsTaskRail"
            anchors.fill: parent
            visible: root.abyssTaskStyle
            color: SettingsMaterialPreset.taskRailColor
            radius: SettingsMaterialPreset.taskRailRadius
        }

        ConfigSelectionArray {
            id: taskOptions
            objectName: "settingsTaskOptions"
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: parent.padding
            y: parent.padding
            currentValue: root.currentValue
            options: root.options
            taskNavigation: true
            useAbyssPillShape: false
            highContrastSelection: root.highContrastSelection
            onSelected: value => root.selected(value)
        }
    }
}
