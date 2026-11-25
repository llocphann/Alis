pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Modern scrubbable numeric control with centered +/- steppers, live tonal fill bar,
 * optional centered status/link toggle pill, and SettingsSearchRegistry integration.
 * Replaces long horizontal walls-of-sliders for discrete and precision parameters.
 */
Rectangle {
    id: root
    objectName: "settingsMetricControl"
    readonly property string sliderLayoutId: "metric-control"

    property string icon: ""
    property string text: ""
    property string description: ""
    property real from: 0
    property real to: 1
    property real stepSize: 0.01
    property real currentValue: NaN
    property real value: Number.isNaN(currentValue) ? 0 : currentValue
    readonly property real _sourceValue: Number.isNaN(currentValue) ? value : currentValue
    property bool asyncCommit: false
    property int syncRevision: 0
    property bool _hasLocalValue: false
    property real _localValue: 0
    readonly property bool dragging: scrubberDrag.pressed
    readonly property real liveValue: scrubber.value
    property string unit: ""
    property int decimals: root._decimalsForStep(root.stepSize)
    property string displayValue: ""
    property string valueText: root.displayValue.length > 0
        ? root.displayValue
        : (Number(scrubber.value).toFixed(root.decimals) + root.unit)

    // Optional inline toggle pill (e.g., "Follow", "Blur", "Refraction", "Transparent")
    property string toggleIcon: ""
    property string toggleLabel: ""
    property string toggleDescription: ""
    property string toggleObjectName: ""
    property bool toggleChecked: false
    property bool compactTile: true
    property bool centerOrigin: false

    // Settings search integration
    property bool enableSettingsSearch: true
    property int settingsSearchOptionId: -1
    property string settingsSearchLabel: root.text
    property string settingsSearchDescription: root.description
    property var searchKeywords: []
    property var settingsSearchKeywords: root.searchKeywords

    signal moved(real value)
    signal committed(real value)
    signal toggledByUser(bool checked)

    readonly property bool hasToggle: root.toggleIcon.length > 0 || root.toggleLabel.length > 0
    readonly property real _span: Math.max(0.000001, root.to - root.from)
    readonly property real _ratio: Math.max(0, Math.min(1, (scrubber.value - root.from) / root._span))
    readonly property bool _controlDimmed: !root.enabled

    on_SourceValueChanged: {
        if (!scrubberDrag.pressed)
            root._hasLocalValue = false
    }
    onSyncRevisionChanged: {
        if (!scrubberDrag.pressed)
            root._hasLocalValue = false
    }
    onEnabledChanged: {
        if (!enabled) {
            repeatTimer.stop()
            root._hasLocalValue = false
        }
    }
    onVisibleChanged: {
        if (!visible)
            repeatTimer.stop()
    }

    function resetLiveValue(): void {
        root._hasLocalValue = false
    }

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    implicitHeight: tileColumn.implicitHeight + (root.compactTile ? 18 : 12)
    radius: root.compactTile ? 10 : 0
    color: root.compactTile ? SettingsMaterialPreset.controlSurface : "transparent"
    border.width: root.compactTile ? 1 : 0
    border.color: root.compactTile
        ? (scrubberDrag.pressed || scrubber.activeFocus
            ? SettingsMaterialPreset.accentBorder
            : SettingsMaterialPreset.controlBorderColor)
        : "transparent"
    opacity: root._controlDimmed ? 0.48 : 1.0

    Behavior on border.color {
        enabled: Appearance.animationsEnabled
        ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
    }

    function _decimalsForStep(step: real): int {
        if (!Number.isFinite(step) || step <= 0 || Math.abs(step - Math.round(step)) < 1e-9)
            return 0
        const s = step.toFixed(6).replace(/0+$/, "")
        const dot = s.indexOf(".")
        return dot >= 0 ? Math.max(0, s.length - dot - 1) : 0
    }

    function _snap(raw: real): real {
        const clamped = Math.max(root.from, Math.min(root.to, raw))
        const step = root.stepSize > 0 ? root.stepSize : 0.01
        const steps = Math.round((clamped - root.from) / step)
        const snapped = root.from + steps * step
        const decs = Math.max(root._decimalsForStep(step), root._decimalsForStep(root.from))
        const precision = Math.pow(10, Math.min(6, decs))
        return Math.max(root.from, Math.min(root.to, Math.round(snapped * precision) / precision))
    }

    function _applyValue(nextRaw: real, isFinalCommit: bool): void {
        const snapped = root._snap(nextRaw)
        const changed = Math.abs(scrubber.value - snapped) > 1e-9 || !root._hasLocalValue
        root._localValue = snapped
        root._hasLocalValue = true
        if (changed)
            root.moved(snapped)
        if (isFinalCommit) {
            root.committed(snapped)
            if (!root.asyncCommit) {
                Qt.callLater(() => {
                    if (!scrubberDrag.pressed && !root.asyncCommit)
                        root._hasLocalValue = false
                })
            }
        }
    }

    function _commitValue(nextRaw: real): void {
        root._applyValue(nextRaw, true)
    }

    function _stepBy(deltaSteps: int): void {
        if (!root.enabled)
            return
        const step = root.stepSize > 0 ? root.stepSize : ((root.to - root.from) / 20)
        root._applyValue(scrubber.value + deltaSteps * step, true)
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
        scrubber.forceActiveFocus()
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
            description: root.settingsSearchDescription || root.toggleDescription || "",
            keywords: root.settingsSearchKeywords || []
        })
    }

    Component.onDestruction: {
        repeatTimer.stop()
        if (typeof SettingsSearchRegistry !== "undefined")
            SettingsSearchRegistry.unregisterControl(root)
    }

    // Hold-to-repeat timer for +/- stepper buttons (cancels cleanly on disable/boundary/release,
    // and suppresses the trailing release click so holding never overshoots by an extra step).
    Timer {
        id: repeatTimer
        property int delta: 0
        interval: 380
        repeat: true
        onTriggered: {
            if (!root.enabled || !root.visible
                    || (delta < 0 && scrubber.value <= root.from + 0.00001)
                    || (delta > 0 && scrubber.value >= root.to - 0.00001)) {
                stop()
                return
            }
            interval = 65
            if (delta < 0)
                decButton.suppressClickOnRelease = true
            else if (delta > 0)
                incButton.suppressClickOnRelease = true
            root._stepBy(delta)
        }
    }

    ColumnLayout {
        id: tileColumn
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.compactTile ? 11 : 0
            rightMargin: root.compactTile ? 11 : 0
        }
        spacing: 7

        // Top header row: icon + label on left, optional centered toggle pill on right
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 8

            OptionalMaterialSymbol {
                visible: root.icon.length > 0
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignVCenter
                icon: root.icon
                iconSize: 16
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
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

            // Optional centered status/link toggle pill
            RippleButton {
                id: togglePill
                visible: root.hasToggle
                objectName: root.toggleObjectName
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: false
                implicitHeight: Math.round(24 * Appearance.fontSizeScale)
                implicitWidth: togglePillRow.implicitWidth + (root.toggleLabel.length > 0 ? 16 : 12)
                buttonRadius: height / 2
                toggled: root.toggleChecked
                checked: root.toggleChecked
                Accessible.name: root.toggleDescription.length > 0 ? root.toggleDescription : (root.toggleLabel || root.text)
                Accessible.checkable: true
                Accessible.checked: root.toggleChecked
                colBackground: Qt.alpha(Appearance.colors.colOutlineVariant, 0.18)
                colBackgroundHover: Qt.alpha(Appearance.colors.colOutlineVariant, 0.28)
                colBackgroundToggled: SettingsMaterialPreset.pillSelectedColor
                colBackgroundToggledHover: SettingsMaterialPreset.pillSelectedHoverColor
                onClicked: root.toggledByUser(!root.toggleChecked)

                contentItem: Item {
                    implicitWidth: togglePillRow.implicitWidth
                    implicitHeight: togglePillRow.implicitHeight

                    Row {
                        id: togglePillRow
                        anchors.centerIn: parent
                        spacing: root.toggleIcon.length > 0 && root.toggleLabel.length > 0 ? 4 : 0

                        MaterialSymbol {
                            visible: root.toggleIcon.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.toggleIcon
                            iconSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            color: root.toggleChecked
                                ? SettingsMaterialPreset.pillSelectedTextColor
                                : SettingsMaterialPreset.secondaryTextColor
                        }

                        StyledText {
                            visible: root.toggleLabel.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.toggleLabel
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.family: SettingsMaterialPreset.fontFamily
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: root.toggleChecked ? Font.DemiBold : Font.Medium
                            color: root.toggleChecked
                                ? SettingsMaterialPreset.pillSelectedTextColor
                                : SettingsMaterialPreset.secondaryTextColor
                        }
                    }
                }

                StyledToolTip {
                    visible: root.toggleDescription.length > 0 && togglePill.hovered
                    text: root.toggleDescription + (root.toggleChecked ? " · On" : " · Off")
                }
            }
        }

        // Bottom interactive stepper + scrubbable meter bar
        RowLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 6

            RippleButton {
                id: decButton
                Layout.preferredWidth: Math.round(28 * Appearance.fontSizeScale)
                Layout.preferredHeight: Math.round(28 * Appearance.fontSizeScale)
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: 8
                enabled: root.enabled && scrubber.value > root.from + 0.00001
                onEnabledChanged: if (!enabled && repeatTimer.delta < 0) repeatTimer.stop()
                Accessible.name: Translation.tr("Decrease %1").arg(root.text)
                colBackground: SettingsMaterialPreset.controlSurfaceHover
                colBackgroundHover: SettingsMaterialPreset.controlSurfaceActive
                onClicked: root._stepBy(-1)
                downAction: () => {
                    repeatTimer.delta = -1
                    repeatTimer.interval = 380
                    repeatTimer.restart()
                }
                releaseAction: () => repeatTimer.stop()
                cancelAction: () => repeatTimer.stop()

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "remove"
                    iconSize: 15
                    color: SettingsMaterialPreset.textColor
                }
            }

            // Scrubbable tonal value bar
            Rectangle {
                id: scrubber
                Layout.fillWidth: true
                Layout.minimumWidth: Math.round(72 * Appearance.fontSizeScale)
                Layout.preferredHeight: Math.round(28 * Appearance.fontSizeScale)
                Layout.alignment: Qt.AlignVCenter
                radius: 8
                clip: true
                activeFocusOnTab: true
                color: SettingsMaterialPreset.cardColor
                border.width: activeFocus || scrubberDrag.pressed ? 1.5 : 1
                border.color: activeFocus || scrubberDrag.pressed
                    ? Appearance.colors.colPrimary
                    : SettingsMaterialPreset.controlBorderColor

                property real from: root.from
                property real to: root.to
                property real value: root._sourceValue
                signal moved()

                onMoved: {
                    root.moved(scrubber.value)
                    root.committed(scrubber.value)
                }

                Binding {
                    target: scrubber
                    property: "value"
                    value: (scrubberDrag.pressed || root._hasLocalValue) ? root._localValue : root._sourceValue
                    when: true
                    restoreMode: Binding.RestoreBindingOrValue
                }

                // Tonal progress meter inside the pill
                Rectangle {
                    visible: !root.centerOrigin
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.margins: 1
                    width: Math.max(0, Math.round((parent.width - 2) * root._ratio))
                    radius: Math.max(0, parent.radius - 1)
                    color: Qt.alpha(Appearance.colors.colPrimary, scrubberDrag.pressed ? 0.30 : 0.20)

                    Behavior on width {
                        enabled: Appearance.animationsEnabled && !scrubberDrag.pressed
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                        }
                    }
                }

                // Center-origin bipolar fill (for -1..+1 controls like pointer speed)
                Rectangle {
                    visible: root.centerOrigin
                    readonly property real zeroRatio: Math.max(0, Math.min(1, (0 - root.from) / root._span))
                    readonly property real innerW: Math.max(0, parent.width - 2)
                    readonly property real startX: Math.min(zeroRatio, root._ratio) * innerW
                    readonly property real endX: Math.max(zeroRatio, root._ratio) * innerW
                    x: 1 + Math.round(startX)
                    y: 1
                    width: Math.max(0, Math.round(endX - startX))
                    height: Math.max(0, parent.height - 2)
                    radius: 4
                    color: Qt.alpha(Appearance.colors.colPrimary, scrubberDrag.pressed ? 0.32 : 0.22)
                }

                // Subtle top & bottom center notch ticks for bipolar controls (never crossing the readout text)
                Rectangle {
                    visible: root.centerOrigin
                    anchors.top: parent.top
                    anchors.topMargin: 2
                    x: Math.round(1 + (parent.width - 2) * Math.max(0, Math.min(1, (0 - root.from) / root._span)))
                    width: 1
                    height: 4
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.75
                }
                Rectangle {
                    visible: root.centerOrigin
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 2
                    x: Math.round(1 + (parent.width - 2) * Math.max(0, Math.min(1, (0 - root.from) / root._span)))
                    width: 1
                    height: 4
                    color: Appearance.colors.colOutlineVariant
                    opacity: 0.75
                }

                // Centered tabular readout
                StyledText {
                    id: readoutText
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: root.valueText
                    font.family: Appearance.font.family.numbers
                    font.variableAxes: Appearance.font.variableAxes.numbers
                    font.features: ({ "tnum": 1 })
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: SettingsMaterialPreset.textColor
                }

                Keys.onLeftPressed: event => { root._stepBy(-1); event.accepted = true }
                Keys.onRightPressed: event => { root._stepBy(1); event.accepted = true }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) {
                        root._commitValue(root.from)
                        event.accepted = true
                    } else if (event.key === Qt.Key_End) {
                        root._commitValue(root.to)
                        event.accepted = true
                    }
                }

                MouseArea {
                    id: scrubberDrag
                    anchors.fill: parent
                    enabled: root.enabled
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.SizeHorCursor

                    function updateFromX(mx: real): void {
                        const usable = Math.max(1, width - 8)
                        const t = Math.max(0, Math.min(1, (mx - 4) / usable))
                        root._applyValue(root.from + t * (root.to - root.from), false)
                    }

                    onPressed: mouse => {
                        scrubber.forceActiveFocus()
                        updateFromX(mouse.x)
                    }
                    onPositionChanged: mouse => {
                        if (pressed)
                            updateFromX(mouse.x)
                    }
                    onReleased: mouse => {
                        const usable = Math.max(1, width - 8)
                        const t = Math.max(0, Math.min(1, (mouse.x - 4) / usable))
                        root._applyValue(root.from + t * (root.to - root.from), true)
                    }
                    onCanceled: {
                        root._hasLocalValue = false
                    }
                }
            }

            RippleButton {
                id: incButton
                Layout.preferredWidth: Math.round(28 * Appearance.fontSizeScale)
                Layout.preferredHeight: Math.round(28 * Appearance.fontSizeScale)
                Layout.alignment: Qt.AlignVCenter
                buttonRadius: 8
                enabled: root.enabled && scrubber.value < root.to - 0.00001
                onEnabledChanged: if (!enabled && repeatTimer.delta > 0) repeatTimer.stop()
                Accessible.name: Translation.tr("Increase %1").arg(root.text)
                colBackground: SettingsMaterialPreset.controlSurfaceHover
                colBackgroundHover: SettingsMaterialPreset.controlSurfaceActive
                onClicked: root._stepBy(1)
                downAction: () => {
                    repeatTimer.delta = 1
                    repeatTimer.interval = 380
                    repeatTimer.restart()
                }
                releaseAction: () => repeatTimer.stop()
                cancelAction: () => repeatTimer.stop()

                contentItem: MaterialSymbol {
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "add"
                    iconSize: 15
                    color: SettingsMaterialPreset.textColor
                }
            }
        }
    }
}
