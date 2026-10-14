pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common

ColumnLayout {
    id: root

    property string icon: "tune"
    property string title: ""
    property string description: ""
    property string summary: ""
    property bool showSummary: root.options.length === 0
    // The page header already shows name/description; the intro card is only
    // worth drawing on pages that need the extra onboarding copy.
    property bool showIntro: true
    property string currentValue: ""
    property var options: []
    property var searchAliases: ({})
    property bool highContrastSelection: false
    readonly property bool abyssTaskStyle: Config.options?.panelFamily === "abyss"

    signal selected(string value)

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

    Component.onCompleted: {
        const page = _findSettingsPage()
        if (page)
            page.settingsTaskNavigator = root
    }

    Component.onDestruction: {
        const page = _findSettingsPage()
        if (page && page.settingsTaskNavigator === root)
            page.settingsTaskNavigator = null
    }

    Layout.fillWidth: true
    spacing: 12

    Rectangle {
        visible: root.showIntro && (root.title.length > 0 || root.description.length > 0)
        Layout.fillWidth: true
        implicitHeight: visible ? introColumn.implicitHeight + (root.title.length > 0 ? 24 : 20) : 0
        radius: Appearance.rounding.normal
        // Follow upstream Alis's quiet information hierarchy: task context is
        // a neutral settings plate, while selection is carried by the tabs.
        color: root.abyssTaskStyle ? SettingsMaterialPreset.cardColor : Appearance.colors.colLayer1

        // Full variant (icon + title + description) for pages that onboard;
        // compact variant (centered description + summary) when the page header
        // already carries the name and icon.
        ColumnLayout {
            id: introColumn
            anchors.fill: parent
            anchors.margins: root.title.length > 0 ? 12 : 10
            spacing: root.title.length > 0 ? 9 : 4

            RowLayout {
                Layout.fillWidth: true
                visible: root.title.length > 0
                spacing: 10

                Item {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    Layout.alignment: Qt.AlignTop
                    visible: root.icon.length > 0

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.icon
                        iconSize: 22
                        color: Appearance.colors.colOnLayer1
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: root.title
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer1
                        wrapMode: Text.WordWrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.description.length > 0
                        text: root.description
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                        opacity: 0.82
                        wrapMode: Text.WordWrap
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.title.length === 0 && root.description.length > 0
                text: root.description
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                opacity: 0.86
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.showSummary && root.summary.length > 0
                text: root.summary
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Medium
                color: Appearance.colors.colOnLayer1
                opacity: 0.72
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.WordWrap
            }
        }
    }

    Item {
        visible: root.options.length > 0
        Layout.fillWidth: true
        implicitHeight: taskOptions.implicitHeight + padding * 2
        readonly property real padding: root.abyssTaskStyle ? SettingsMaterialPreset.taskTabPadding : 0

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
