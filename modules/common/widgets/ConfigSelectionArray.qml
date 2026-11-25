pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Flow {
    id: root
    Layout.fillWidth: true
    Layout.preferredWidth: root.fillWidthSegments ? 0 : -1
    Layout.minimumWidth: root.fillWidthSegments ? 0 : -1
    // Default spacing: 2; Planner full-label chips wrap across rows when the option card is narrow.
    spacing: root.wrapFullLabels ? 5 : (root.fillWidthSegments && root.useAbyssPillShape ? 4 : 2)
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
    // Opt-in full-width equal-segment distribution so Settings selectors end flush on the right edge.
    property bool fillWidthSegments: false
    readonly property int _fillAvailWidth: Math.max(0, Math.floor(root.width))
    readonly property bool _fillWidthActive: root.fillWidthSegments
        && root.visible
        && !root.activeLabelOnly && !root.wrapFullLabels && !root.taskNavigation
        && root._fillAvailWidth > 0
        && (!root.parent || (root.parent.width > 0 && root._fillAvailWidth <= Math.ceil(root.parent.width)))
    readonly property bool _hasAnyOptionIcon: {
        const opts = root.options ?? []
        for (let i = 0; i < opts.length; ++i) {
            if (String(opts[i]?.icon ?? "").length > 0)
                return true
        }
        return false
    }
    TextMetrics {
        id: fillSegmentMetrics
        font.family: Appearance.font.family.main
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: Font.Medium
        text: {
            let longest = ""
            const opts = root.options ?? []
            for (let i = 0; i < opts.length; ++i) {
                const lbl = String(opts[i]?.displayName ?? "")
                if (lbl.length > longest.length)
                    longest = lbl
            }
            return longest
        }
    }
    readonly property real _minFillSegWidth: Math.max(
        Math.round(56 * Appearance.fontSizeScale),
        Math.ceil(fillSegmentMetrics.advanceWidth)
            + (root._hasAnyOptionIcon ? (Appearance.font.pixelSize.normal + 6) : 0)
            + 24
    )
    readonly property int _fillRowCount: {
        const count = Math.max(1, root.options.length)
        if (!root._fillWidthActive)
            return 1
        const maxFit = Math.max(1, Math.floor((root._fillAvailWidth + root.spacing) / (root._minFillSegWidth + root.spacing)))
        return Math.max(1, Math.ceil(count / maxFit))
    }
    // Legacy optional selected-only labels. Planner Event options use complete
    // icon + text for every choice, with stable widths and multi-row Flow.
    property bool activeLabelOnly: false
    property bool wrapFullLabels: false
    property real optionHorizontalPadding: -1
    property real optionIconSize: -1
    property real optionIconSpacing: -1
    // Center each naturally wrapped row without changing any non-Planner
    // selector or adding duplicate option widgets.
    property bool centerWrappedRows: false
    function centerWrappedOptionRows(): void {
        if (!root.centerWrappedRows || root.width<=0) return
        const rows=[]
        for(let i=0;i<optionRepeater.count;i++){
            const button=optionRepeater.itemAt(i)
            if (!button || !button.visible) continue
            let group=rows.find(row=>Math.abs(row.y-button.y)<1)
            if (!group) {
                group={y:button.y,items:[]}
                rows.push(group)
            }
            group.items.push(button)
        }
        for(const row of rows){
            const minX=Math.min(...row.items.map(button=>button.x))
            const maxX=Math.max(...row.items.map(button=>button.x+button.width))
            const delta=(root.width-(maxX-minX))/2-minX
            if(Math.abs(delta)>.1)
                for(const button of row.items) button.x+=delta
        }
    }
    onPositioningComplete: if (root.centerWrappedRows)
        Qt.callLater(root.centerWrappedOptionRows)
    Timer {
        id: flowLayoutTimer
        interval: 0
        repeat: false
        onTriggered: root.forceLayout()
    }
    onWidthChanged: if (root.taskNavigation) flowLayoutTimer.restart()
    onOptionsChanged: if (root.taskNavigation) flowLayoutTimer.restart()
    Connections {
        target: Appearance
        function onFontSizeScaleChanged() {
            if (root.taskNavigation) flowLayoutTimer.restart()
        }
    }
    // Shrink previous label first, then reveal the new one; avoids Flow
    // competing width animations when choosing buttons left-to-right.
    property var revealedSelection: null
    clip: root.activeLabelOnly
    Timer {
        id: revealNextSelection
        interval: 190
        repeat: false
        onTriggered: root.revealedSelection=root.currentValue
    }
    onCurrentValueChanged: {
        if (!root.activeLabelOnly) return
        root.revealedSelection=null
        revealNextSelection.restart()
    }
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
        root.revealedSelection=root.currentValue
        revealNextSelection.stop()
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
            customIconSize: root.optionIconSize
            customIconSpacing: root.optionIconSpacing
            buttonPreviewKind: modelData.previewKind || ""
            // Stable source text: SelectionGroupButton owns the clipping
            // animation, so quick selection changes cannot lose the label.
            buttonText: modelData.displayName
            revealActiveLabelOnly: root.activeLabelOnly
            selectedLabelExpanded: root.activeLabelOnly
                ? root.revealedSelection != null
                    && root.revealedSelection == modelData.value : paletteButton.toggled
            Accessible.name: modelData.displayName
            ToolTip.visible: root.activeLabelOnly && paletteButton.hovered
                && !paletteButton.toggled
            ToolTip.text: modelData.displayName
            highContrastSelection: root.highContrastSelection
            useAbyssPillShape: root.useAbyssPillShape
            abyssTaskNavigation: root.taskNavigation && Config.options?.panelFamily === "abyss"
            // This opt-in flag also applies to ordinary (non-task) selectors.
            // Disabled delegates reject pointer and keyboard interaction.
            enabled: modelData?.enabled !== false
            // Five buttons fit one row even at narrow Planner panel widths.
            // Reserve fixed icon-only slots before allocating selected text.
            horizontalPadding: root.optionHorizontalPadding >= 0
                ? root.optionHorizontalPadding
                : (root.wrapFullLabels
                    ? Math.max(4,5 * Appearance.fontSizeScale)
                    : root.activeLabelOnly
                        ? Math.max(5,6 * Appearance.fontSizeScale)
                        : (root.taskNavigation ? 14 * Appearance.fontSizeScale : 11))
            baseWidth: {
                if (root._fillWidthActive) {
                    const count = Math.max(1, root.options.length)
                    const rows = Math.max(1, root._fillRowCount)
                    const basePerRow = Math.floor(count / rows)
                    const extraRows = count % rows
                    const cutoff = extraRows * (basePerRow + 1)
                    let itemsInRow = basePerRow
                    let posInRow = 0
                    if (index < cutoff) {
                        itemsInRow = basePerRow + 1
                        posInRow = index % itemsInRow
                    } else {
                        itemsInRow = Math.max(1, basePerRow)
                        posInRow = (index - cutoff) % itemsInRow
                    }
                    const avail = Math.max(itemsInRow, root._fillAvailWidth - root.spacing * (itemsInRow - 1))
                    const base = Math.floor(avail / itemsInRow)
                    return posInRow === itemsInRow - 1
                        ? Math.max(1, avail - base * (itemsInRow - 1))
                        : Math.max(1, base)
                }
                return contentItem.implicitWidth + horizontalPadding * 2
            }
            maxTextWidth: root._fillWidthActive
                ? Math.max(24, baseWidth - horizontalPadding * 2
                    - (buttonIcon.length > 0 ? Appearance.font.pixelSize.normal + 6 : 0))
                : root.taskNavigation
                ? (root.width > 0
                    ? Math.max(0, root.width - horizontalPadding * 2
                        - (buttonIcon.length > 0 ? Appearance.font.pixelSize.normal + 8 : 0))
                    : 320)
                : root.activeLabelOnly
                    ? Math.max(0,root.width - root.options.length
                        * (Appearance.font.pixelSize.normal + 2 * horizontalPadding
                            + root.spacing) - 10)
                    : root.wrapFullLabels
                        ? Math.max(0,root.width - 2 * horizontalPadding
                            - (buttonIcon.length > 0
                                ? Appearance.font.pixelSize.normal + 4 : 0) - 4)
                        : Math.round(180 * Appearance.fontSizeScale)
            // Only animate implicit size changes for activeLabelOnly (Planner) chips;
            // static segmented pills resize immediately on fontScale changes with zero overflow lag.
            enableImplicitWidthAnimation: root.activeLabelOnly
            enableImplicitHeightAnimation: root.activeLabelOnly
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
            opacity: modelData?.dimmed === true || !paletteButton.enabled
                ? 0.42 : 1
            toggled: (root.currentValue != null && root.currentValue == modelData.value) ?? false
            onClicked: {
                if (paletteButton.enabled) root.selected(modelData.value)
            }
        }
    }
}
