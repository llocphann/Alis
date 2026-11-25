pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Modern segmented preset picker with optional centered +/- fine-tune stepper.
 * Ideal for discrete / sweet-spot Settings parameters (animation speed, cursor size,
 * corner radius, color temperature, stage scale) instead of imprecise long sliders.
 */
ColumnLayout {
    id: root
    objectName: "settingsPresetRow"
    readonly property string sliderLayoutId: "preset-row"

    property string icon: ""
    property string text: ""
    property string description: ""
    property real value: 0
    property bool asyncCommit: false
    property int syncRevision: 0
    property bool _hasLocalValue: false
    property real _localValue: 0
    readonly property real liveValue: root._hasLocalValue ? root._localValue : root.value
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string displayValue: ""
    property var presets: [] // [{ label: "1.0×", value: 1.0 }, ...]
    property bool showStepper: true
    property real matchTolerance: 0.005

    // Settings search integration
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1
    property string settingsSearchLabel: root.text
    property string settingsSearchDescription: root.description
    property var settingsSearchKeywords: []

    signal moved(real newValue)

    onValueChanged: root._hasLocalValue = false
    onSyncRevisionChanged: root._hasLocalValue = false
    onEnabledChanged: {
        if (!enabled) {
            presetRepeatTimer.stop()
            root._hasLocalValue = false
        }
    }
    onVisibleChanged: {
        if (!visible)
            presetRepeatTimer.stop()
    }

    function resetLiveValue(): void {
        root._hasLocalValue = false
    }

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    spacing: 8
    opacity: root.enabled ? 1.0 : 0.48

    function _decimalsForStep(step: real): int {
        if (!Number.isFinite(step) || step <= 0 || Math.abs(step - Math.round(step)) < 1e-9)
            return 0
        const s = step.toFixed(6).replace(/0+$/, "")
        const dot = s.indexOf(".")
        return dot >= 0 ? Math.max(0, s.length - dot - 1) : 0
    }

    function _commit(nextRaw: real): void {
        if (!root.enabled)
            return
        const clamped = Math.max(root.from, Math.min(root.to, nextRaw))
        const step = root.stepSize > 0 ? root.stepSize : 1
        const decs = Math.max(root._decimalsForStep(step), root._decimalsForStep(root.from))
        const precision = Math.pow(10, Math.min(6, decs))
        const rounded = Math.max(root.from, Math.min(root.to, Math.round(clamped * precision) / precision))
        root._localValue = rounded
        root._hasLocalValue = true
        root.moved(rounded)
        if (!root.asyncCommit) {
            Qt.callLater(() => {
                if (!root.asyncCommit)
                    root._hasLocalValue = false
            })
        }
    }

    function _findSettingsContext() {
        var page = null
        var sectionTitle = ""
        var groupTitle = ""
        var p = root.parent
        while (p) {
            if (!page && p.hasOwnProperty("settingsPageIndex"))
                page = p
            if (p.hasOwnProperty("title")) {
                if (!sectionTitle && p.hasOwnProperty("icon"))
                    sectionTitle = p.title
                else if (!groupTitle && !p.hasOwnProperty("icon"))
                    groupTitle = p.title
            }
            p = p.parent
        }
        return { page: page, sectionTitle: sectionTitle, groupTitle: groupTitle }
    }

    function focusFromSettingsSearch() {
        var p = root.parent
        while (p) {
            if (p.hasOwnProperty("expanded") && p.hasOwnProperty("collapsible")) {
                p.expanded = true
                break
            }
            p = p.parent
        }
        const firstBtn = presetRepeater.count > 0 ? presetRepeater.itemAt(0) : null
        if (firstBtn)
            firstBtn.forceActiveFocus()
    }

    Component.onCompleted: {
        if (!root.enableSettingsSearch || typeof SettingsSearchRegistry === "undefined")
            return
        const ctx = root._findSettingsContext()
        const page = ctx.page
        const pageIdx = page && page.settingsPageIndex !== undefined ? page.settingsPageIndex : -1
        if (pageIdx < 0)
            return
        const label = root.settingsSearchLabel || root.text || ctx.groupTitle || ctx.sectionTitle
        if (!label)
            return
        root.settingsSearchOptionId = SettingsSearchRegistry.registerOption({
            control: root,
            pageIndex: pageIdx,
            pageName: page && page.settingsPageName ? page.settingsPageName : "",
            section: ctx.sectionTitle,
            label: label,
            description: root.settingsSearchDescription || root.description || "",
            keywords: root.settingsSearchKeywords || []
        })
    }

    Component.onDestruction: {
        presetRepeatTimer.stop()
        if (typeof SettingsSearchRegistry !== "undefined")
            SettingsSearchRegistry.unregisterControl(root)
    }

    Timer {
        id: presetRepeatTimer
        property int delta: 0
        interval: 380
        repeat: true
        onTriggered: {
            if (!root.enabled || !root.visible
                    || (delta < 0 && root.liveValue <= root.from + 0.00001)
                    || (delta > 0 && root.liveValue >= root.to - 0.00001)) {
                stop()
                return
            }
            interval = 75
            if (delta < 0)
                presetDecBtn.suppressClickOnRelease = true
            else if (delta > 0)
                presetIncBtn.suppressClickOnRelease = true
            root._commit(root.liveValue + delta * root.stepSize)
        }
    }

    TextMetrics {
        id: presetMetrics
        font.family: SettingsMaterialPreset.fontFamily
        font.features: ({ "tnum": 1 })
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.DemiBold
        text: {
            let longest = ""
            const list = root.presets || []
            for (let i = 0; i < list.length; i++) {
                const lbl = String(list[i]?.label ?? "")
                if (lbl.length > longest.length)
                    longest = lbl
            }
            return longest
        }
    }

    // Header row: icon + title + current value badge (when text is provided)
    RowLayout {
        visible: root.text.length > 0 || root.description.length > 0
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 8

        OptionalMaterialSymbol {
            visible: root.icon.length > 0
            Layout.fillWidth: false
            Layout.alignment: Qt.AlignVCenter
            icon: root.icon
            iconSize: 18
            color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 1

            StyledText {
                visible: root.text.length > 0
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.text
                font.family: SettingsMaterialPreset.fontFamily
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                color: SettingsMaterialPreset.textColor
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            StyledText {
                visible: root.description.length > 0
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                text: root.description
                font.family: SettingsMaterialPreset.fontFamily
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: SettingsMaterialPreset.secondaryTextColor
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        Rectangle {
            visible: root.displayValue.length > 0
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(24 * Appearance.fontSizeScale)
            implicitWidth: valueBadgeText.implicitWidth + 16
            radius: height / 2
            color: SettingsMaterialPreset.accentTint
            border.width: 1
            border.color: SettingsMaterialPreset.accentBorder

            StyledText {
                id: valueBadgeText
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: root.displayValue
                font.family: Appearance.font.family.numbers
                font.features: ({ "tnum": 1 })
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
        }
    }

    // Controls row: Segmented preset pills + optional fine-tune stepper
    RowLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        spacing: 8

        Rectangle {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            implicitHeight: presetFlow.implicitHeight + 6
            radius: 10
            color: SettingsMaterialPreset.controlSurface
            border.width: 1
            border.color: SettingsMaterialPreset.controlBorderColor

            Flow {
                id: presetFlow
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                    margins: 3
                }
                spacing: 3

                readonly property int presetCount: Math.max(1, root.presets.length)
                readonly property int availWidth: Math.max(presetCount, Math.floor(width))
                readonly property real minReadablePillWidth: Math.max(
                    Math.round(42 * Appearance.fontSizeScale),
                    Math.ceil(presetMetrics.advanceWidth) + 18
                )
                readonly property int rowCount: {
                    const maxFit = Math.max(1, Math.floor((availWidth + spacing) / (minReadablePillWidth + spacing)))
                    return Math.max(1, Math.ceil(presetCount / maxFit))
                }

                Repeater {
                    id: presetRepeater
                    model: root.presets

                    delegate: RippleButton {
                        id: presetBtn
                        required property var modelData
                        required property int index
                        readonly property bool isSelected: Math.abs(Number(root.liveValue) - Number(modelData.value)) <= root.matchTolerance

                        width: {
                            const count = presetFlow.presetCount
                            const rows = presetFlow.rowCount
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
                            const avail = Math.max(itemsInRow, presetFlow.availWidth - presetFlow.spacing * (itemsInRow - 1))
                            const base = Math.floor(avail / itemsInRow)
                            return posInRow === itemsInRow - 1
                                ? Math.max(1, avail - base * (itemsInRow - 1))
                                : Math.max(1, base)
                        }
                        implicitHeight: Math.round(28 * Appearance.fontSizeScale)
                        buttonRadius: 7
                        toggled: isSelected
                        Accessible.name: String(modelData.label ?? "")
                        colBackground: "transparent"
                        colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                        colBackgroundToggled: SettingsMaterialPreset.pillSelectedColor
                        colBackgroundToggledHover: SettingsMaterialPreset.pillSelectedHoverColor
                        onClicked: root._commit(Number(modelData.value))

                        contentItem: StyledText {
                            id: presetLabel
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: String(presetBtn.modelData.label ?? "")
                            font.family: SettingsMaterialPreset.fontFamily
                            font.features: ({ "tnum": 1 })
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: presetBtn.isSelected ? Font.DemiBold : Font.Medium
                            color: presetBtn.isSelected
                                ? SettingsMaterialPreset.pillSelectedTextColor
                                : SettingsMaterialPreset.textColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // Fine-tune stepper capsule
        Rectangle {
            visible: root.showStepper
            Layout.alignment: Qt.AlignVCenter
            implicitHeight: Math.round(34 * Appearance.fontSizeScale)
            implicitWidth: fineRow.implicitWidth + 6
            radius: 10
            color: SettingsMaterialPreset.controlSurface
            border.width: 1
            border.color: SettingsMaterialPreset.controlBorderColor

            Row {
                id: fineRow
                anchors.centerIn: parent
                spacing: 2

                RippleButton {
                    id: presetDecBtn
                    implicitWidth: Math.round(26 * Appearance.fontSizeScale)
                    implicitHeight: Math.round(26 * Appearance.fontSizeScale)
                    buttonRadius: 7
                    enabled: root.enabled && root.liveValue > root.from + 0.00001
                    onEnabledChanged: if (!enabled && presetRepeatTimer.delta < 0) presetRepeatTimer.stop()
                    Accessible.name: Translation.tr("Decrease %1").arg(root.text)
                    colBackground: "transparent"
                    colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                    onClicked: root._commit(root.liveValue - root.stepSize)
                    downAction: () => {
                        presetRepeatTimer.delta = -1
                        presetRepeatTimer.interval = 380
                        presetRepeatTimer.restart()
                    }
                    releaseAction: () => presetRepeatTimer.stop()
                    cancelAction: () => presetRepeatTimer.stop()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "remove"
                        iconSize: 14
                        color: SettingsMaterialPreset.textColor
                    }
                }

                StyledText {
                    visible: root.text.length === 0 && root.displayValue.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.max(implicitWidth + 6, Math.round(38 * Appearance.fontSizeScale))
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.displayValue
                    font.family: Appearance.font.family.numbers
                    font.features: ({ "tnum": 1 })
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: SettingsMaterialPreset.textColor
                }

                RippleButton {
                    id: presetIncBtn
                    implicitWidth: Math.round(26 * Appearance.fontSizeScale)
                    implicitHeight: Math.round(26 * Appearance.fontSizeScale)
                    buttonRadius: 7
                    enabled: root.enabled && root.liveValue < root.to - 0.00001
                    onEnabledChanged: if (!enabled && presetRepeatTimer.delta > 0) presetRepeatTimer.stop()
                    Accessible.name: Translation.tr("Increase %1").arg(root.text)
                    colBackground: "transparent"
                    colBackgroundHover: SettingsMaterialPreset.controlSurfaceHover
                    onClicked: root._commit(root.liveValue + root.stepSize)
                    downAction: () => {
                        presetRepeatTimer.delta = 1
                        presetRepeatTimer.interval = 380
                        presetRepeatTimer.restart()
                    }
                    releaseAction: () => presetRepeatTimer.stop()
                    cancelAction: () => presetRepeatTimer.stop()

                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "add"
                        iconSize: 14
                        color: SettingsMaterialPreset.textColor
                    }
                }
            }
        }
    }
}
