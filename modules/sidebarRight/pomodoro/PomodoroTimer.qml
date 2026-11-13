import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property bool compactMode: false
    property bool centerMode: true

    // Style helpers
    readonly property color _colLayer: Appearance.angelEverywhere ? Appearance.angel.colGlassCard
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2
        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface
        : Appearance.colors.colLayer2
    readonly property color _colLayerHover: Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurfaceHover
        : Appearance.colors.colLayer2Hover
    readonly property color _colLayerActive: Appearance.angelEverywhere ? Appearance.angel.colGlassCardActive
        : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive
        : Appearance.colors.colLayer2Active
    readonly property color _colText: Appearance.angelEverywhere ? Appearance.angel.colText
        : Appearance.alisEverywhere ? Appearance.alis.colText
        : Appearance.colors.colOnLayer2
    readonly property color _colTextSecondary: Appearance.angelEverywhere ? Appearance.angel.colTextSecondary
        : Appearance.alisEverywhere ? Appearance.alis.colTextSecondary
        : Appearance.colors.colSubtext
    readonly property color _colAccent: Appearance.angelEverywhere ? Appearance.angel.colPrimary
        : Appearance.alisEverywhere ? Appearance.alis.colPrimary
        : Appearance.colors.colPrimary
    readonly property color _colTrack: ColorUtils.transparentize(root._colTextSecondary, 0.82)

    property bool settingsOpen: false
    property bool tagMenuOpen: false
    property string tagSearchText: ""
    property string colorPickerTag: ""
    property string newTagColor: ""

    readonly property var filteredTags: {
        const q = root.tagSearchText.trim().toLowerCase()
        const all = TimerService.tags ?? []
        if (!q) return all
        let out = []
        for (let i = 0; i < all.length; i++) {
            if (String(all[i]).toLowerCase().indexOf(q) !== -1)
                out.push(all[i])
        }
        return out
    }

    readonly property var matchingArchivedTags: {
        const q = root.tagSearchText.trim().toLowerCase()
        if (!q) return []
        const arch = TimerService.archivedTags ?? []
        let out = []
        for (let i = 0; i < arch.length; i++) {
            if (String(arch[i]).toLowerCase().indexOf(q) !== -1)
                out.push(arch[i])
        }
        return out
    }

    readonly property bool canCreateTag: {
        const q = root.tagSearchText.trim().toLowerCase()
        if (!q) return false
        const all = TimerService.tags ?? []
        for (let i = 0; i < all.length; i++) {
            if (String(all[i]).toLowerCase() === q) return false
        }
        return true
    }

    // Reusable row for adjusting a single timer duration value
    component AdjustRow: RowLayout {
        id: adjustRow
        property string icon
        property string label
        property int currentValue
        property int minValue
        property int maxValue
        property int step
        property string configPath
        property bool isMinutes: true
        property bool _editing: false

        Layout.fillWidth: true
        spacing: 0

        MaterialSymbol {
            text: adjustRow.icon
            iconSize: 16
            color: root._colTextSecondary
            Layout.rightMargin: 6
        }
        StyledText {
            text: adjustRow.label
            font.pixelSize: Appearance.font.pixelSize.small
            color: root._colTextSecondary
            Layout.fillWidth: true
        }
        RippleButton {
            implicitWidth: root.compactMode ? 24 : 28
            implicitHeight: root.compactMode ? 24 : 28
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: root._colLayerHover
            colRipple: root._colLayerActive
            enabled: adjustRow.currentValue > adjustRow.minValue
            onClicked: Config.setNestedValue(adjustRow.configPath, Math.max(adjustRow.minValue, adjustRow.currentValue - adjustRow.step))
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "remove"
                iconSize: 16
                color: enabled ? root._colText : root._colTextSecondary
            }
        }
        Rectangle {
            implicitWidth: 56
            implicitHeight: root.compactMode ? 24 : 28
            radius: Appearance.angelEverywhere ? Appearance.angel.roundingSmall
                : Appearance.alisEverywhere ? Appearance.alis.roundingSmall
                : Appearance.rounding.small
            color: adjustRow._editing
                ? (Appearance.angelEverywhere ? ColorUtils.transparentize(Appearance.angel.colPrimary, 0.8)
                 : Appearance.alisEverywhere ? Appearance.alis.colSecondaryContainer
                 : Appearance.colors.colPrimaryContainer)
                : Appearance.angelEverywhere ? Appearance.angel.colGlassCard
                : Appearance.alisEverywhere ? Appearance.alis.colLayer1
                : Appearance.colors.colLayer1
            border.width: adjustRow._editing ? 1 : 0
            border.color: Appearance.angelEverywhere ? Appearance.angel.colPrimary
                : Appearance.alisEverywhere ? Appearance.alis.colPrimary
                : Appearance.colors.colPrimary
            TextInput {
                id: valueInput
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: adjustRow.isMinutes
                    ? -Math.round((unitLabel.implicitWidth + 2) / 2)
                    : 0
                width: parent.width - (adjustRow.isMinutes ? 16 : 8)
                text: adjustRow.isMinutes ? Math.floor(adjustRow.currentValue / 60).toString() : adjustRow.currentValue.toString()
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
                font.family: Appearance.font.family.main
                color: root._colText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                validator: IntValidator { bottom: 1; top: 999 }
                selectByMouse: true
                onActiveFocusChanged: {
                    adjustRow._editing = activeFocus
                    if (activeFocus) selectAll()
                }
                onEditingFinished: {
                    const val = parseInt(text) || 1
                    const newValue = adjustRow.isMinutes ? val * 60 : val
                    Config.setNestedValue(adjustRow.configPath, Math.max(adjustRow.minValue, Math.min(adjustRow.maxValue, newValue)))
                }
            }
            StyledText {
                id: unitLabel
                x: Math.min(parent.width - width - 3,
                    Math.round(valueInput.x + (valueInput.width + valueInput.contentWidth) / 2 + 2))
                anchors.baseline: valueInput.baseline
                visible: adjustRow.isMinutes
                text: "m"
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: root._colTextSecondary
                opacity: 0.7
            }
        }
        RippleButton {
            implicitWidth: root.compactMode ? 24 : 28
            implicitHeight: root.compactMode ? 24 : 28
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: root._colLayerHover
            colRipple: root._colLayerActive
            enabled: adjustRow.currentValue < adjustRow.maxValue
            onClicked: Config.setNestedValue(adjustRow.configPath, Math.min(adjustRow.maxValue, adjustRow.currentValue + adjustRow.step))
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                text: "add"
                iconSize: 16
                color: enabled ? root._colText : root._colTextSecondary
            }
        }
    }

    StyledFlickable {
        id: flickable
        anchors.fill: parent
        // The settings face replaces the dial, keeping all duration controls
        // within the compact popup's normal height.
        contentHeight: (root.centerMode && contentColumn.implicitHeight <= flickable.height)
            ? flickable.height
            : contentColumn.implicitHeight
        clip: true
        interactive: contentColumn.implicitHeight > flickable.height

        ColumnLayout {
            id: contentColumn
            width: flickable.width
            spacing: 0
            // Center vertically via y offset — safe from polish loops because
            // implicitHeight here is the column's own intrinsic size (no spacers),
            // and flickable.height is an external reference that doesn't depend on us.
            y: (root.centerMode && implicitHeight < flickable.height)
                ? Math.max(0, (flickable.height - implicitHeight) / 2)
                : 0

            // Study-Tracker Focus Timer Header: Title + Subject/Tag Pill + Today Sessions Badge
            RowLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, flickable.width - 20)
                Layout.leftMargin: 10
                Layout.rightMargin: 10
                Layout.topMargin: root.compactMode ? 0 : 2
                Layout.bottomMargin: root.compactMode ? 2 : 4
                spacing: 6

                StyledText {
                    id: focusHeaderLabel
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("FOCUS")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.Bold
                    font.letterSpacing: 1.0
                    verticalAlignment: Text.AlignVCenter
                    color: root._colTextSecondary
                }

                // Active Subject / Tag Pill (Study-Tracker style)
                Rectangle {
                    id: activeTagPill
                    objectName: "pomodoroActiveTagPill"
                    Layout.alignment: Qt.AlignVCenter
                    readonly property real maxAllowedWidth: Math.max(56, Math.min(160,
                        flickable.width - 20 - focusHeaderLabel.implicitWidth
                            - presetChip.implicitWidth
                            - (todayBadge.visible ? todayBadge.implicitWidth + 6 : 0) - 18))
                    implicitWidth: Math.min(maxAllowedWidth, Math.ceil(tagPillRow.implicitWidth) + 16)
                    implicitHeight: 22
                    radius: 11
                    color: tagPillMouse.containsMouse || root.tagMenuOpen
                        ? root._colLayerHover
                        : root._colLayer
                    border.width: 1
                    border.color: root.tagMenuOpen
                        ? root._colAccent
                        : ColorUtils.transparentize(root._colTextSecondary, 0.78)

                    RowLayout {
                        id: tagPillRow
                        anchors.centerIn: parent
                        // MaterialSymbol chevron has internal right glyph padding;
                        // a +1.5px offset balances visual left/right margins.
                        anchors.horizontalCenterOffset: 1.5
                        spacing: 5

                        Rectangle {
                            Layout.preferredWidth: 7
                            Layout.preferredHeight: 7
                            Layout.alignment: Qt.AlignVCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: TimerService.getTagColor(TimerService.activeTag)
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: TimerService.activeTag
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.DemiBold
                            verticalAlignment: Text.AlignVCenter
                            color: root._colText
                            Layout.maximumWidth: Math.max(24, activeTagPill.maxAllowedWidth - 41)
                            elide: Text.ElideRight
                        }

                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: root.tagMenuOpen ? "expand_less" : "expand_more"
                            iconSize: 13
                            verticalAlignment: Text.AlignVCenter
                            color: root._colTextSecondary
                        }
                    }

                    MouseArea {
                        id: tagPillMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.tagMenuOpen = !root.tagMenuOpen
                            if (root.tagMenuOpen) {
                                root.settingsOpen = false
                                root.tagSearchText = ""
                                root.colorPickerTag = ""
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Preset badge + Today's focus summary
                Rectangle {
                    id: todayBadge
                    Layout.alignment: Qt.AlignVCenter
                    visible: TimerService.todaySessions > 0
                    implicitWidth: Math.ceil(todayBadgeRow.implicitWidth) + 14
                    implicitHeight: 22
                    radius: 11
                    color: ColorUtils.transparentize(root._colAccent, 0.86)

                    RowLayout {
                        id: todayBadgeRow
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -0.5
                        spacing: 4
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignVCenter
                            text: "local_fire_department"
                            iconSize: 12
                            verticalAlignment: Text.AlignVCenter
                            color: root._colAccent
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: `${TimerService.todaySessions} · ${Math.max(1, Math.round(TimerService.todayFocusSeconds / 60))}m`
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            verticalAlignment: Text.AlignVCenter
                            color: root._colAccent
                        }
                    }
                }

                Rectangle {
                    id: presetChip
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Math.ceil(presetChipText.implicitWidth) + 14
                    implicitHeight: 22
                    radius: 11
                    color: presetChipMouse.containsMouse || root.settingsOpen
                        ? root._colLayerHover
                        : root._colLayer
                    border.width: 1
                    border.color: root.settingsOpen
                        ? root._colAccent
                        : ColorUtils.transparentize(root._colTextSecondary, 0.82)

                    StyledText {
                        id: presetChipText
                        anchors.fill: parent
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: TimerService.activePreset === "standard" ? "25/5"
                            : TimerService.activePreset === "deep" ? "50/10"
                            : TimerService.activePreset === "ultradian" ? "90/20"
                            : `${Math.round(TimerService.focusTime / 60)}/${Math.round(TimerService.breakTime / 60)}`
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Medium
                        color: root._colTextSecondary
                    }

                    MouseArea {
                        id: presetChipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !TimerService.pomodoroRunning
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            root.settingsOpen = !root.settingsOpen
                            if (root.settingsOpen) root.tagMenuOpen = false
                        }
                    }
                }
            }

            // Collapsible Study-Tracker Subject / Tag Manager Drawer
            Item {
                id: tagMenuContainer
                readonly property int maxDrawerHeight: Math.max(96, flickable.height - 28)
                readonly property int desiredDrawerHeight: Math.min(tagMenuColumn.implicitHeight + 12, maxDrawerHeight)
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, flickable.width - 16)
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.bottomMargin: root.tagMenuOpen ? 4 : 0
                Layout.preferredHeight: root.tagMenuOpen ? desiredDrawerHeight : 0
                Layout.maximumHeight: root.tagMenuOpen ? desiredDrawerHeight : 0
                visible: root.tagMenuOpen
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.normal
                    color: root._colLayer
                    border.width: 1
                    border.color: ColorUtils.transparentize(root._colTextSecondary, 0.78)
                }

                Flickable {
                    id: tagMenuFlick
                    anchors { fill: parent; margins: 6 }
                    contentWidth: width
                    contentHeight: tagMenuColumn.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    ColumnLayout {
                        id: tagMenuColumn
                        width: tagMenuFlick.width
                        spacing: 4

                        // Search / Create Subject Input
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 26
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer1
                        border.width: tagSearchInput.activeFocus ? 1 : 0
                        border.color: root._colAccent

                        RowLayout {
                            anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                            spacing: 6

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "label"
                                iconSize: 14
                                color: root._colTextSecondary
                            }

                            TextInput {
                                id: tagSearchInput
                                Layout.fillWidth: true
                                Layout.preferredHeight: 26
                                Layout.alignment: Qt.AlignVCenter
                                text: root.tagSearchText
                                color: root._colText
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.family: Appearance.font.family.main
                                verticalAlignment: TextInput.AlignVCenter
                                selectByMouse: true
                                clip: true
                                onTextChanged: root.tagSearchText = text
                                Keys.onReturnPressed: {
                                    if (root.canCreateTag) {
                                        TimerService.addTag(root.tagSearchText.trim(), root.newTagColor)
                                        root.tagSearchText = ""
                                        tagSearchInput.text = ""
                                    } else if (root.filteredTags.length > 0) {
                                        TimerService.setActiveTag(root.filteredTags[0])
                                        root.tagMenuOpen = false
                                    }
                                }

                                StyledText {
                                    anchors.fill: parent
                                    visible: tagSearchInput.text.length === 0
                                    text: Translation.tr("Search or add subject...")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    verticalAlignment: Text.AlignVCenter
                                    color: root._colTextSecondary
                                    opacity: 0.7
                                }
                            }

                            RippleButton {
                                Layout.alignment: Qt.AlignVCenter
                                visible: root.canCreateTag
                                implicitWidth: 20
                                implicitHeight: 20
                                buttonRadius: 10
                                colBackground: root._colAccent
                                onClicked: {
                                    TimerService.addTag(root.tagSearchText.trim(), root.newTagColor)
                                    root.tagSearchText = ""
                                    tagSearchInput.text = ""
                                }
                                contentItem: MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "add"
                                    iconSize: 14
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }

                    // Tag Rows
                    Repeater {
                        model: root.filteredTags

                        ColumnLayout {
                            required property var modelData
                            required property int index
                            readonly property string tagName: String(modelData)
                            readonly property bool isCurrent: tagName === TimerService.activeTag
                            Layout.fillWidth: true
                            spacing: 2

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 24
                                radius: Appearance.rounding.small
                                color: isCurrent
                                    ? ColorUtils.transparentize(root._colAccent, 0.85)
                                    : tagRowMouse.containsMouse ? root._colLayerHover : "transparent"

                                RowLayout {
                                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                    spacing: 6

                                    // Color dot (click to toggle inline color palette)
                                    Rectangle {
                                        Layout.preferredWidth: 12
                                        Layout.preferredHeight: 12
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 12
                                        height: 12
                                        radius: 6
                                        color: TimerService.getTagColor(tagName)
                                        border.width: root.colorPickerTag === tagName ? 1.5 : 0
                                        border.color: root._colText

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.colorPickerTag = (root.colorPickerTag === tagName ? "" : tagName)
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: tagName
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: isCurrent ? Font.DemiBold : Font.Normal
                                        verticalAlignment: Text.AlignVCenter
                                        color: isCurrent ? root._colAccent : root._colText
                                        elide: Text.ElideRight

                                        MouseArea {
                                            id: tagRowMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                TimerService.setActiveTag(tagName)
                                                root.tagMenuOpen = false
                                            }
                                        }
                                    }

                                    // Archive / delete tag button
                                    RippleButton {
                                        Layout.alignment: Qt.AlignVCenter
                                        visible: (TimerService.tags?.length ?? 0) > 1
                                        implicitWidth: 20
                                        implicitHeight: 20
                                        buttonRadius: 10
                                        colBackground: "transparent"
                                        colBackgroundHover: root._colLayerHover
                                        onClicked: TimerService.removeTag(tagName)
                                        contentItem: MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: "close"
                                            iconSize: 13
                                            color: root._colTextSecondary
                                        }
                                    }
                                }
                            }

                            // Inline 12-color palette row when color dot is clicked
                            Flow {
                                visible: root.colorPickerTag === tagName
                                Layout.fillWidth: true
                                Layout.leftMargin: 6
                                spacing: 4

                                Repeater {
                                    model: TimerService.tagColorPalette

                                    Rectangle {
                                        required property var modelData
                                        width: 14
                                        height: 14
                                        radius: 7
                                        color: String(modelData)
                                        border.width: TimerService.getTagColor(tagName) === String(modelData) ? 2 : 0
                                        border.color: root._colText

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                TimerService.setTagColor(tagName, String(modelData))
                                                root.colorPickerTag = ""
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Archived tags recovery (if search matches archived tag)
                    Repeater {
                        model: root.matchingArchivedTags

                        Rectangle {
                            required property var modelData
                            readonly property string archName: String(modelData)
                            Layout.fillWidth: true
                            implicitHeight: 24
                            radius: Appearance.rounding.small
                            color: ColorUtils.transparentize(root._colAccent, 0.9)

                            RowLayout {
                                anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                spacing: 6
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "restore"
                                    iconSize: 13
                                    color: root._colAccent
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: Translation.tr("Restore \"%1\"").arg(archName)
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    verticalAlignment: Text.AlignVCenter
                                    color: root._colAccent
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    TimerService.recoverTag(archName)
                                    root.tagSearchText = ""
                                    tagSearchInput.text = ""
                                    root.tagMenuOpen = false
                                }
                            }
                        }
                    }
                    }
                }
            }

            // Open orbital focus arc: intentionally not a generic 360° timer
            // ring. The bottom gap carries the session rhythm and keeps the time
            // readout visually lighter in compact Dashboard layouts.
            Item {
                id: focusDial
                visible: !root.settingsOpen && !root.tagMenuOpen
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: root.compactMode
                    ? Math.min(184, Math.max(148,
                        Math.min(flickable.width * 0.52, (flickable.height - 66) * 1.22)))
                    : 190
                Layout.preferredHeight: root.compactMode
                    ? Math.max(128, Math.min(Layout.preferredWidth, flickable.height - 68))
                    : Layout.preferredWidth
                Layout.bottomMargin: root.compactMode ? 0 : 2

                readonly property real rawProgress:
                    TimerService.pomodoroLapDuration > 0
                        ? Math.max(0, Math.min(1,
                            TimerService.pomodoroSecondsLeft
                                / TimerService.pomodoroLapDuration))
                        : 0
                property real displayProgress: rawProgress
                readonly property real orbitStrokeWidth: 5
                // Preserve sub-pixel geometry for the curve renderer instead
                // of quantizing the ellipse to whole pixels at compact sizes.
                readonly property real arcCenterX: width / 2
                readonly property real arcCenterY: height / 2 - 4
                readonly property real arcRadiusY:
                    Math.max(46, Math.min(height / 2 - 8, (width / 2 - 8) * 0.80, 86 * 0.80))
                readonly property real arcRadiusX:
                    Math.max(58, Math.min(width / 2 - 8, arcRadiusY / 0.80, 86))
                readonly property real startAngle: 155
                readonly property real sweepAngle: 230

                Behavior on displayProgress {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }

                Shape {
                    anchors.fill: parent
                    antialiasing: true
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root._colTrack
                        strokeWidth: focusDial.orbitStrokeWidth
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: focusDial.arcCenterX
                            centerY: focusDial.arcCenterY
                            radiusX: focusDial.arcRadiusX
                            radiusY: focusDial.arcRadiusY
                            startAngle: focusDial.startAngle
                            sweepAngle: focusDial.sweepAngle
                        }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: root._colAccent
                        strokeWidth: focusDial.orbitStrokeWidth
                        capStyle: ShapePath.RoundCap

                        PathAngleArc {
                            centerX: focusDial.arcCenterX
                            centerY: focusDial.arcCenterY
                            radiusX: focusDial.arcRadiusX
                            radiusY: focusDial.arcRadiusY
                            startAngle: focusDial.startAngle
                            sweepAngle: focusDial.sweepAngle
                                * focusDial.displayProgress
                        }
                    }
                }

                Rectangle {
                    readonly property real angle:
                        (focusDial.startAngle
                            + focusDial.sweepAngle * focusDial.displayProgress)
                            * Math.PI / 180
                    width: 8
                    height: 8
                    radius: width / 2
                    color: root._colAccent
                    border.width: 1
                    border.color: root._colLayer
                    visible: focusDial.displayProgress > 0.002
                    x: focusDial.arcCenterX
                        + focusDial.arcRadiusX * Math.cos(angle) - width / 2
                    y: focusDial.arcCenterY
                        + focusDial.arcRadiusY * Math.sin(angle) - height / 2
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: root.compactMode ? 9 : 8
                    spacing: 2

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            const minutes = Math.floor(
                                TimerService.pomodoroSecondsLeft / 60)
                                .toString().padStart(2, '0')
                            const seconds = Math.floor(
                                TimerService.pomodoroSecondsLeft % 60)
                                .toString().padStart(2, '0')
                            return `${minutes}:${seconds}`
                        }
                        font.pixelSize: Math.round(
                            (root.compactMode ? 31 : 34)
                                * Appearance.fontSizeScale)
                        font.weight: Font.Medium
                        font.family: Appearance.font.family.numbers
                        color: root._colText
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: focusDial.arcRadiusX * 1.75
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                        text: {
                            const phaseLabel = TimerService.pomodoroLongBreak
                                ? Translation.tr("Long break")
                                : TimerService.pomodoroBreak
                                    ? Translation.tr("Break")
                                    : Translation.tr("Focus")
                            const phaseMins = Math.max(1, Math.round(TimerService.pomodoroLapDuration / 60))
                            const stateLabel = TimerService.pomodoroRunning
                                ? (TimerService.pomodoroPaused ? Translation.tr("paused") : Translation.tr("running"))
                                : Translation.tr("ready")
                            return `${phaseLabel} (${phaseMins}m) · ${stateLabel}`
                        }
                        font.pixelSize: root.compactMode
                            ? Appearance.font.pixelSize.smallest
                            : Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                        color: root._colTextSecondary
                    }

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 5
                        Layout.bottomMargin: Math.round(focusDial.arcRadiusY * 0.56)
                        spacing: 5

                        Repeater {
                            model: Math.max(1,
                                TimerService.cyclesBeforeLongBreak)

                            Rectangle {
                                required property int index
                                readonly property bool current:
                                    index === TimerService.pomodoroCycle
                                readonly property bool complete:
                                    index < TimerService.pomodoroCycle
                                width: current ? 15 : 5
                                height: 5
                                radius: height / 2
                                color: current || complete
                                    ? root._colAccent : root._colTrack

                                Behavior on width {
                                    enabled: Appearance.animationsEnabled
                                    NumberAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                    }
                                }
                                Behavior on color {
                                    enabled: Appearance.animationsEnabled
                                    ColorAnimation {
                                        duration: Appearance.animation.elementMoveFast.duration
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Study-Tracker Linear Progress Bar
            Rectangle {
                id: progressTrack
                visible: !root.settingsOpen && !root.tagMenuOpen
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, flickable.width - 32)
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                Layout.bottomMargin: root.compactMode ? 4 : 8
                implicitHeight: 5
                radius: 2.5
                color: root._colTrack

                Rectangle {
                    id: progressFill
                    height: parent.height
                    radius: parent.radius
                    width: Math.max(0, Math.min(parent.width,
                        parent.width * (1.0 - focusDial.displayProgress)))
                    color: TimerService.pomodoroBreak
                        ? Appearance.colors.colSecondary
                        : root._colAccent

                    Behavior on width {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                }
            }

            // The compact settings face uses the dial's space in this viewport.
            Item {
                id: settingsCard
                readonly property bool active: root.settingsOpen && !TimerService.pomodoroRunning && !root.tagMenuOpen
                readonly property real fullCardHeight: settingsInner.implicitHeight + (root.compactMode ? 12 : 16)
                readonly property real targetHeight: active
                    ? (root.compactMode
                        ? Math.min(fullCardHeight, Math.max(128, flickable.height - 64))
                        : fullCardHeight)
                    : 0
                visible: active || Layout.maximumHeight > 0
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, flickable.width - 16)
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.topMargin: active ? 2 : 0
                Layout.bottomMargin: active ? (root.compactMode ? 4 : 6) : 0
                Layout.preferredHeight: targetHeight
                Layout.maximumHeight: targetHeight
                clip: true

                Behavior on Layout.maximumHeight {
                    enabled: Appearance.animationsEnabled && !root.compactMode
                    animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.angelEverywhere ? Appearance.angel.roundingNormal
                        : Appearance.alisEverywhere ? Appearance.alis.roundingNormal
                        : Appearance.rounding.normal
                    color: root._colLayer
                    border.width: 1
                    border.color: Appearance.angelEverywhere ? Appearance.angel.colBorder
                        : Appearance.alisEverywhere ? Appearance.alis.colBorder
                        : Appearance.colors.colLayer0Border
                }

                Flickable {
                    id: settingsFlickable
                    anchors {
                        fill: parent
                        margins: root.compactMode ? 6 : 8
                    }
                    contentWidth: width
                    contentHeight: settingsInner.implicitHeight
                    clip: true
                    interactive: contentHeight > height

                    ColumnLayout {
                        id: settingsInner
                        width: settingsFlickable.width
                        spacing: root.compactMode ? 4 : 6

                        // Study-Tracker Presets Row (Standard 25/5/15, Deep Work 50/10/30, Ultradian 90/20)
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Repeater {
                                model: [
                                    { key: "standard", label: Translation.tr("Standard"), sub: "25/5" },
                                    { key: "deep", label: Translation.tr("Deep Work"), sub: "50/10" },
                                    { key: "ultradian", label: Translation.tr("Ultradian"), sub: "90/20" }
                                ]

                                RippleButton {
                                    id: presetBtn
                                    required property var modelData
                                    readonly property bool isPresetActive: TimerService.activePreset === modelData.key
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    implicitHeight: root.compactMode ? 25 : 28
                                    buttonRadius: Appearance.rounding.small
                                    colBackground: isPresetActive
                                        ? root._colAccent
                                        : Appearance.colors.colLayer1
                                    colBackgroundHover: isPresetActive
                                        ? root._colAccent
                                        : root._colLayerHover
                                    onClicked: TimerService.applyPomodoroPreset(modelData.key)

                                    contentItem: Item {
                                        clip: true
                                        Row {
                                            anchors.centerIn: parent
                                            spacing: presetBtn.width < 88 ? 2 : 4
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: Math.min(implicitWidth, Math.max(0, presetBtn.width - (presetBtn.width < 88 ? 4 : 32)))
                                                elide: Text.ElideRight
                                                text: modelData.label
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: isPresetActive ? Font.Bold : Font.Medium
                                                verticalAlignment: Text.AlignVCenter
                                                color: isPresetActive ? Appearance.colors.colOnPrimary : root._colText
                                            }
                                            StyledText {
                                                visible: presetBtn.width >= 88
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: modelData.sub
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                verticalAlignment: Text.AlignVCenter
                                                color: isPresetActive
                                                    ? ColorUtils.transparentize(Appearance.colors.colOnPrimary, 0.2)
                                                    : root._colTextSecondary
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        AdjustRow {
                            icon: "target"
                            label: Translation.tr("Focus")
                            currentValue: TimerService.focusTime
                            minValue: 60; maxValue: 7200; step: 300
                            configPath: "time.pomodoro.focus"
                            isMinutes: true
                        }
                        AdjustRow {
                            icon: "coffee"
                            label: Translation.tr("Break")
                            currentValue: TimerService.breakTime
                            minValue: 60; maxValue: 1800; step: 60
                            configPath: "time.pomodoro.breakTime"
                            isMinutes: true
                        }
                        AdjustRow {
                            icon: "weekend"
                            label: Translation.tr("Long break")
                            currentValue: TimerService.longBreakTime
                            minValue: 60; maxValue: 3600; step: 300
                            configPath: "time.pomodoro.longBreak"
                            isMinutes: true
                        }
                        AdjustRow {
                            icon: "replay"
                            label: Translation.tr("Cycles")
                            currentValue: TimerService.cyclesBeforeLongBreak
                            minValue: 1; maxValue: 10; step: 1
                            configPath: "time.pomodoro.cyclesBeforeLongBreak"
                            isMinutes: false
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 1
                            color: Appearance.angelEverywhere ? Appearance.angel.colBorder
                                : Appearance.alisEverywhere ? Appearance.alis.colBorder
                                : Appearance.colors.colOutlineVariant
                            opacity: 0.5
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: (Config.options?.sounds?.pomodoro ?? false) ? "volume_up" : "volume_off"
                                iconSize: 16
                                color: root._colTextSecondary
                                Layout.rightMargin: 6
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: Translation.tr("Sound")
                                font.pixelSize: Appearance.font.pixelSize.small
                                verticalAlignment: Text.AlignVCenter
                                color: root._colTextSecondary
                            }
                            StyledSwitch {
                                Layout.alignment: Qt.AlignVCenter
                                scale: 0.55
                                checked: Config.options?.sounds?.pomodoro ?? false
                                onCheckedChanged: Config.setNestedValue("sounds.pomodoro", checked)
                            }
                        }
                    }
                }
            }

            // Start/Pause + Reset + Skip + Customize buttons
            RowLayout {
                id: controlsRow
                readonly property bool tightControls: flickable.width > 0 && flickable.width < 320
                visible: !root.tagMenuOpen
                Layout.fillWidth: true
                Layout.maximumWidth: Math.max(0, flickable.width - 12)
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                spacing: tightControls ? 6 : 8

                // Mirror the trailing Customize button when width permits so
                // Start / Reset / Skip stay centered under the focus dial without
                // overflowing narrow (280px) popups.
                Item {
                    Layout.preferredWidth: Math.max(0, Math.min(
                        customizeButton.implicitWidth,
                        flickable.width - (startButton.implicitWidth + resetButton.implicitWidth + skipButton.implicitWidth + customizeButton.implicitWidth + (controlsRow.tightControls ? 48 : 60))))
                    Layout.preferredHeight: 1
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: startButton
                    Layout.alignment: Qt.AlignVCenter
                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        text: TimerService.pomodoroRunning ? (TimerService.pomodoroPaused ? Translation.tr("Resume") : Translation.tr("Pause")) : (TimerService.pomodoroSecondsLeft === TimerService.focusTime) ? Translation.tr("Start") : Translation.tr("Resume")
                        color: TimerService.pomodoroRunning && !TimerService.pomodoroPaused
                            ? (Appearance.zzzEverywhere ? Appearance.zzz.onSticker
                                : Appearance.alisEverywhere ? Appearance.alis.colText
                                : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer2 : Appearance.colors.colOnSecondaryContainer)
                            : Appearance.colors.colOnPrimary
                        Behavior on color {
                            enabled: Appearance.animationsEnabled
                            ColorAnimation { duration: Appearance.animation.elementMoveFast.duration }
                        }
                    }
                    implicitHeight: root.compactMode ? 34 : 35
                    implicitWidth: controlsRow.tightControls ? 74 : 88
                    buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full
                    font.pixelSize: Appearance.font.pixelSize.larger
                    onClicked: TimerService.togglePomodoro()
                    colBackground: TimerService.pomodoroRunning && !TimerService.pomodoroPaused
                        ? (Appearance.zzzEverywhere ? Appearance.zzz.sticker
                            : Appearance.alisEverywhere ? Appearance.alis.colLayer2
                            : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface : Appearance.colors.colSecondaryContainer)
                        : Appearance.colors.colPrimary
                    colBackgroundHover: TimerService.pomodoroRunning && !TimerService.pomodoroPaused
                        ? (Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover
                            : Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                            : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurfaceHover : Appearance.colors.colSecondaryContainerHover)
                        : Appearance.colors.colPrimaryHover
                    colRipple: TimerService.pomodoroRunning && !TimerService.pomodoroPaused
                        ? (Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive
                            : Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
                            : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive : Appearance.colors.colSecondaryContainerActive)
                        : Appearance.colors.colPrimaryActive
                }

                RippleButton {
                    id: resetButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitHeight: root.compactMode ? 34 : 35
                    implicitWidth: controlsRow.tightControls ? 66 : 78
                    buttonRadius: Appearance.zzzEverywhere ? Appearance.zzz.controlRadius : Appearance.rounding.full

                    onClicked: TimerService.resetPomodoro()
                    enabled: (TimerService.pomodoroSecondsLeft < TimerService.pomodoroLapDuration) || TimerService.pomodoroCycle > 0 || TimerService.pomodoroBreak

                    font.pixelSize: Appearance.font.pixelSize.larger
                    colBackground: Appearance.alisEverywhere ? Appearance.alis.colLayer2
                        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurface
                        : Appearance.colors.colErrorContainer
                    colBackgroundHover: Appearance.alisEverywhere ? Appearance.alis.colLayer2Hover
                        : Appearance.auroraEverywhere ? Appearance.aurora.colElevatedSurfaceHover
                        : Appearance.colors.colErrorContainerHover
                    colRipple: Appearance.alisEverywhere ? Appearance.alis.colLayer2Active
                        : Appearance.auroraEverywhere ? Appearance.aurora.colSubSurfaceActive
                        : Appearance.colors.colErrorContainerActive

                    contentItem: Item {
                        Rectangle {
                            anchors.fill: parent
                            radius: resetButton.buttonRadius
                            visible: !resetButton.enabled
                            color: root._colLayer
                        }
                        StyledText {
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.Medium
                            text: Translation.tr("Reset")
                            color: !resetButton.enabled
                                ? root._colText
                                : Appearance.alisEverywhere ? Appearance.alis.colText
                                    : Appearance.auroraEverywhere ? Appearance.colors.colOnLayer2
                                    : Appearance.colors.colOnErrorContainer
                        }
                    }
                }

                RippleButton {
                    id: skipButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.compactMode ? 34 : 35
                    implicitHeight: root.compactMode ? 34 : 35
                    buttonRadius: height / 2
                    colBackground: root._colLayer
                    colBackgroundHover: root._colLayerHover
                    onClicked: TimerService.skipPomodoroPhase()

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "skip_next"
                        iconSize: 19
                        color: root._colText
                    }

                    StyledToolTip {
                        text: Translation.tr("Skip to next phase")
                    }
                }

                Item { Layout.fillWidth: true }

                RippleButton {
                    id: customizeButton
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: root.compactMode ? 34 : 36
                    implicitHeight: root.compactMode ? 34 : 36
                    buttonRadius: height / 2
                    enabled: !TimerService.pomodoroRunning
                    colBackground: root.settingsOpen
                        ? Appearance.colors.colPrimaryContainer
                        : root._colLayer
                    colBackgroundHover: Appearance.colors.colPrimaryContainerHover
                    onClicked: {
                        root.settingsOpen = !root.settingsOpen
                        if (root.settingsOpen) root.tagMenuOpen = false
                    }

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.settingsOpen ? "close" : "tune"
                        iconSize: 20
                        color: root.settingsOpen
                            ? Appearance.colors.colOnPrimaryContainer
                            : root._colText
                    }

                    StyledToolTip {
                        text: Translation.tr("Customize timer")
                    }
                }
            }
        }
    }
}
