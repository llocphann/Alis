pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flow {
    id: root
    Layout.fillWidth: true
    spacing: 2
    // Integración con buscador global de Settings
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1

    property list<var> options: [
        {
            "displayName": "Option 1",
            "icon": "check",
            "value": 1
        },
        {
            "displayName": "Option 2",
            "icon": "close",
            "value": 2
        },
    ]
    property var currentValue: null
    property bool highContrastSelection: false
    property bool useAbyssPillShape: true
    property bool taskNavigation: false
    // Planner-only: inactive choices remain icon-only; selected choice expands.
    property bool activeLabelOnly: false
    readonly property bool hovered: _hoverHandler.hovered

    signal selected(var newValue)

    HoverHandler {
        id: _hoverHandler
    }

    function _findSettingsContext() {
        var page = null;
        var sectionTitle = "";
        var groupTitle = "";
        var p = root.parent;
        while (p) {
            if (!page && p.hasOwnProperty("settingsPageIndex")) {
                page = p;
            }
            if (p.hasOwnProperty("title")) {
                if (!sectionTitle && p.hasOwnProperty("icon")) {
                    sectionTitle = p.title;
                } else if (!groupTitle && !p.hasOwnProperty("icon")) {
                    groupTitle = p.title;
                }
            }
            p = p.parent;
        }
        return { page: page, sectionTitle: sectionTitle, groupTitle: groupTitle };
    }

    function moveTaskFocus(index, direction): bool {
        if (!root.taskNavigation || root.options.length === 0)
            return false
        for (let step = 1; step <= root.options.length; ++step) {
            const next = (index + direction * step + root.options.length) % root.options.length
            const button = optionRepeater.itemAt(next)
            if (!button || !button.enabled || !button.visible)
                continue
            button.forceActiveFocus(Qt.TabFocusReason)
            root.selected(root.options[next].value)
            return true
        }
        return false
    }

    function focusFromSettingsSearch() {
        // Expand parent CollapsibleSection if collapsed
        var p = root.parent;
        while (p) {
            if (p.hasOwnProperty("expanded") && p.hasOwnProperty("collapsible")) {
                p.expanded = true;
                break;
            }
            p = p.parent;
        }

        // Focus a real option rather than the non-interactive Flow so the
        // search result lands on a visible, keyboard-operable control.
        Qt.callLater(() => {
            let targetIndex = 0
            for (let i = 0; i < root.options.length; ++i) {
                if (root.currentValue != null && root.currentValue == root.options[i]?.value) {
                    targetIndex = i
                    break
                }
            }
            optionRepeater.itemAt(targetIndex)?.forceActiveFocus()
        })
    }

    Component.onCompleted: {
        if (!enableSettingsSearch)
            return;
        if (typeof SettingsSearchRegistry === "undefined")
            return;

        var ctx = _findSettingsContext();
        var page = ctx.page;
        var sectionTitle = ctx.sectionTitle;
        var label = ctx.groupTitle || sectionTitle;
        var optionNames = [];
        for (var i = 0; i < root.options.length; ++i) {
            var opt = root.options[i];
            if (opt && opt.displayName)
                optionNames.push(String(opt.displayName).toLowerCase());
        }
        
        // Include option names in description for better search
        var optionsList = optionNames.join(", ");

        settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: sectionTitle,
            label: label,
            description: optionsList,
            keywords: optionNames
        });
    }

    Component.onDestruction: {
        if (typeof SettingsSearchRegistry !== "undefined") {
            SettingsSearchRegistry.unregisterControl(root);
        }
    }

    Repeater {
        id: optionRepeater
        model: root.options
        delegate: SelectionGroupButton {
            id: paletteButton
            required property var modelData
            required property int index

            function syncRowEdges(): void {
                const previous = index > 0 ? optionRepeater.itemAt(index - 1) : null
                const startsRow = index === 0
                    || (previous !== null && previous.y !== paletteButton.y)
                paletteButton.leftmost = startsRow
                paletteButton.rightmost = index === root.options.length - 1
                if (previous !== null)
                    previous.rightmost = startsRow
            }

            Component.onCompleted: Qt.callLater(syncRowEdges)
            onYChanged: Qt.callLater(syncRowEdges)
            leftmost: index === 0
            rightmost: index === root.options.length - 1
            buttonIcon: modelData.icon || ""
            buttonPreviewKind: modelData.previewKind || ""
            buttonText: root.activeLabelOnly && !paletteButton.toggled
                ? "" : modelData.displayName
            Accessible.name: modelData.displayName
            ToolTip.visible: root.activeLabelOnly && paletteButton.hovered
                && !paletteButton.toggled
            ToolTip.text: modelData.displayName
            highContrastSelection: root.highContrastSelection
            useAbyssPillShape: root.useAbyssPillShape
            abyssTaskNavigation: root.taskNavigation && Config.options?.panelFamily === "abyss"
            enabled: !root.taskNavigation || modelData?.enabled !== false
            maxTextWidth: root.taskNavigation
                ? Math.max(0, root.width - horizontalPadding * 2
                    - (buttonIcon.length > 0 ? Appearance.font.pixelSize.normal + 4 : 0)) : 180
            enableImplicitWidthAnimation: !root.taskNavigation
            enableImplicitHeightAnimation: !root.taskNavigation
            Keys.onLeftPressed: event => { event.accepted = root.moveTaskFocus(index, -1) }
            Keys.onRightPressed: event => { event.accepted = root.moveTaskFocus(index, 1) }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Home)
                    event.accepted = root.moveTaskFocus(-1, 1)
                else if (event.key === Qt.Key_End)
                    event.accepted = root.moveTaskFocus(0, -1)
                else event.accepted = false
            }
            Keys.onReturnPressed: event => {
                event.accepted = root.taskNavigation
                if (event.accepted) paletteButton.clicked()
            }
            Keys.onEnterPressed: event => {
                event.accepted = root.taskNavigation
                if (event.accepted) paletteButton.clicked()
            }
            opacity: modelData?.dimmed === true ? 0.45 : 1
            toggled: (root.currentValue != null && root.currentValue == modelData.value) ?? false
            onClicked: {
                root.selected(modelData.value);
            }
        }
    }
}
