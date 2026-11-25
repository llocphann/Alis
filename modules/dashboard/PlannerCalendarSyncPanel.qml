import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

DashCard {
    id: root
    objectName: "plannerCalendarSyncPanel"
    title: ""
    icon: ""
    Layout.fillHeight: true
    focus: true

    signal dismiss()

    function handleEscape(): bool {
        if (addSourceForm.expanded) {
            addSourceForm.expanded = false
            return true
        }
        root.dismiss()
        return true
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: CalendarSync.fetching ? "sync" : "calendar_month"
                iconSize: 18
                color: CalendarSync.enabled ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Calendar Sync")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
                elide: Text.ElideRight
            }

            RippleButton {
                objectName: "calendarSyncCloseButton"
                implicitWidth: 28
                implicitHeight: 28
                buttonRadius: 14
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: root.dismiss()

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.colors.colOnSurfaceVariant
                }

                StyledToolTip { text: Translation.tr("Close Calendar Sync") }
            }
        }

        ScrollView {
            id: syncScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            ColumnLayout {
                width: syncScrollView.availableWidth
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colLayer2
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 8

                        MaterialSymbol {
                            text: CalendarSync.fetching ? "sync" : "event_available"
                            iconSize: 16
                            color: CalendarSync.enabled ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            text: CalendarSync.fetching
                                ? Translation.tr("Syncing feeds…")
                                : (CalendarSync.sources.length + " " + Translation.tr("sources") + " · " + CalendarSync.events.length + " " + Translation.tr("events"))
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: Appearance.colors.colOnLayer1
                            elide: Text.ElideRight
                        }

                        RippleButton {
                            objectName: "calendarSyncNowButton"
                            enabled: CalendarSync.enabled && CalendarSync.sources.length > 0 && !CalendarSync.fetching
                            implicitWidth: syncNowRow.implicitWidth + 14
                            implicitHeight: 24
                            buttonRadius: 12
                            opacity: enabled ? 1 : 0.55
                            colBackground: Appearance.colors.colLayer1
                            colBackgroundHover: Appearance.colors.colLayer1Hover
                            onClicked: CalendarSync.fetchAll()

                            contentItem: Item {
                                Row {
                                    id: syncNowRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "refresh"
                                        iconSize: 12
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Translation.tr("Sync now")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "sync"
                    text: Translation.tr("Enable external calendar sync")
                    checked: Config.options?.calendar?.externalSync?.enable ?? false
                    onCheckedChanged: Config.setNestedValue("calendar.externalSync.enable", checked)
                }

                SettingsSwitch {
                    Layout.fillWidth: true
                    buttonIcon: "event"
                    text: Translation.tr("Show upcoming events")
                    checked: Config.options?.calendar?.showUpcoming ?? true
                    onCheckedChanged: Config.setNestedValue("calendar.showUpcoming", checked)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "date_range"
                    text: Translation.tr("Upcoming days to show")
                    value: Config.options?.calendar?.upcomingDays ?? 3
                    from: 1
                    to: 14
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("calendar.upcomingDays", value)
                    enabled: Config.options?.calendar?.showUpcoming ?? true
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "more_horiz"
                    text: Translation.tr("Maximum indicators per edge")
                    value: Config.options?.calendar?.maxEventDots ?? 3
                    from: 0
                    to: 3
                    stepSize: 1
                    onValueChanged: Config.setNestedValue("calendar.maxEventDots", value)
                }

                ConfigSpinBox {
                    Layout.fillWidth: true
                    icon: "update"
                    text: Translation.tr("Refresh interval (minutes)")
                    value: Config.options?.calendar?.externalSync?.refreshMinutes ?? 15
                    from: 5
                    to: 120
                    stepSize: 5
                    onValueChanged: Config.setNestedValue("calendar.externalSync.refreshMinutes", value)
                    enabled: Config.options?.calendar?.externalSync?.enable ?? false
                }

                SettingsDivider {}

                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    MaterialSymbol {
                        text: "celebration"
                        iconSize: 15
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Translation.tr("Holiday Presets (1-Click)")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }
                }

                Flow {
                    id: holidayPresetsFlow
                    objectName: "calendarHolidayPresetsFlow"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 6

                    Repeater {
                        model: CalendarSync.holidayPresets
                        delegate: RippleButton {
                            id: holidayChip
                            required property var modelData
                            readonly property bool added: CalendarSync.hasHolidayPreset(modelData.id)
                            objectName: "calendarHolidayPreset_" + modelData.id
                            implicitWidth: holidayChipRow.implicitWidth + 16
                            implicitHeight: 28
                            buttonRadius: 14
                            toggled: holidayChip.added
                            colBackground: Appearance.colors.colLayer2
                            colBackgroundHover: Appearance.colors.colLayer2Hover
                            colBackgroundToggled: Appearance.colors.colPrimary
                            colBackgroundToggledHover: Appearance.colors.colPrimaryHover
                            onClicked: CalendarSync.toggleHolidayPreset(holidayChip.modelData.id)

                            contentItem: Item {
                                Row {
                                    id: holidayChipRow
                                    anchors.centerIn: parent
                                    spacing: 4

                                    MaterialSymbol {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: holidayChip.added ? "check" : "add"
                                        iconSize: 13
                                        color: holidayChip.added
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colPrimary
                                    }

                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: holidayChip.modelData.shortLabel
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Medium
                                        color: holidayChip.added
                                            ? Appearance.colors.colOnPrimary
                                            : Appearance.colors.colOnLayer1
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsDivider {}

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        text: Translation.tr("Calendar Sources")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnLayer1
                        elide: Text.ElideRight
                    }

                    RippleButton {
                        objectName: "calendarAddSourceButton"
                        implicitWidth: addRow.implicitWidth + 16
                        implicitHeight: 28
                        buttonRadius: Appearance.rounding.small
                        colBackground: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.88)
                        colBackgroundHover: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.80)
                        onClicked: addSourceForm.expanded = !addSourceForm.expanded

                        contentItem: Item {
                            Row {
                                id: addRow
                                anchors.centerIn: parent
                                spacing: 4

                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "add"
                                    iconSize: 15
                                    color: Appearance.colors.colPrimary
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Add")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colPrimary
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: Config.options?.calendar?.externalSync?.sources ?? []

                    delegate: Item {
                        id: sourceItem
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        implicitHeight: sourceRow.implicitHeight + 10

                        Rectangle {
                            anchors.fill: parent
                            clip: true
                            radius: Appearance.rounding.small
                            color: sourceMA.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer2
                            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }

                            RowLayout {
                                id: sourceRow
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 10
                                    Layout.preferredHeight: 10
                                    radius: 5
                                    color: sourceItem.modelData?.color ?? Appearance.colors.colPrimary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    Layout.preferredWidth: 1
                                    clip: true
                                    spacing: 1

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 6

                                        StyledText {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            text: sourceItem.modelData?.name ?? Translation.tr("Unnamed")
                                            font.pixelSize: Appearance.font.pixelSize.small
                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        Rectangle {
                                            visible: CalendarSync.isHolidaySource(sourceItem.modelData)
                                            implicitWidth: holBadgeText.implicitWidth + 8
                                            implicitHeight: 16
                                            radius: 8
                                            color: ColorUtils.transparentize(sourceItem.modelData?.color ?? Appearance.colors.colPrimary, 0.80)
                                            StyledText {
                                                id: holBadgeText
                                                anchors.centerIn: parent
                                                text: Translation.tr("Holiday")
                                                font.pixelSize: 10
                                                font.weight: Font.DemiBold
                                                color: sourceItem.modelData?.color ?? Appearance.colors.colPrimary
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        text: sourceItem.modelData?.url ?? ""
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideMiddle
                                        maximumLineCount: 1
                                    }
                                }

                                MaterialSymbol {
                                    visible: {
                                        const st = CalendarSync.sourceStatuses?.[sourceItem.modelData?.id]
                                        return Boolean(st?.error && st.error !== "")
                                    }
                                    text: "error"
                                    iconSize: 16
                                    color: Appearance.colors.colError

                                    StyledToolTip {
                                        text: {
                                            const st = CalendarSync.sourceStatuses?.[sourceItem.modelData?.id]
                                            if (!st?.error) return ""
                                            return st.stale
                                                ? `${st.error} · ${Translation.tr("Showing cached events")}`
                                                : st.error
                                        }
                                    }
                                }

                                Switch {
                                    checked: sourceItem.modelData?.enabled ?? true
                                    onCheckedChanged: {
                                        if (checked !== (sourceItem.modelData?.enabled ?? true))
                                            CalendarSync.toggleSource(sourceItem.modelData.id, checked)
                                    }
                                }

                                RippleButton {
                                    implicitWidth: 26
                                    implicitHeight: 26
                                    buttonRadius: 13
                                    colBackground: "transparent"
                                    colBackgroundHover: Appearance.colors.colLayer1Hover
                                    onClicked: CalendarSync.removeSource(sourceItem.modelData.id)

                                    contentItem: MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: "close"
                                        iconSize: 14
                                        color: Appearance.colors.colSubtext
                                    }

                                    StyledToolTip { text: Translation.tr("Remove") }
                                }
                            }

                            MouseArea {
                                id: sourceMA
                                anchors.fill: parent
                                z: -1
                                hoverEnabled: true
                            }
                        }
                    }
                }

                StyledText {
                    visible: (Config.options?.calendar?.externalSync?.sources ?? []).length === 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 2
                    Layout.bottomMargin: 2
                    text: Translation.tr("No calendar sources added yet")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    font.italic: true
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: Translation.tr("Paste a compatible ICS/iCal feed URL; no account sign-in within Alis.")
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                }

                Rectangle {
                    id: addSourceForm
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    property bool expanded: false
                    implicitHeight: expanded ? addFormCol.implicitHeight + 20 : 0
                    visible: expanded
                    clip: true
                    radius: Appearance.rounding.small
                    color: Appearance.colors.colSurfaceContainerLow
                    border.width: 1
                    border.color: Appearance.colors.colLayer0Border

                    Behavior on implicitHeight {
                        NumberAnimation {
                            duration: Appearance.animation.elementMoveFast.duration
                            easing.type: Appearance.animation.elementMoveFast.type
                            easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
                        }
                    }

                    ColumnLayout {
                        id: addFormCol
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        StyledText {
                            text: Translation.tr("Add Calendar Source")
                            font.pixelSize: Appearance.font.pixelSize.normal
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer1
                        }

                        ColumnLayout {
                            spacing: 4
                            Layout.fillWidth: true

                            StyledText {
                                text: Translation.tr("Name")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            MaterialTextField {
                                id: sourceNameInput
                                Layout.fillWidth: true
                                placeholderText: Translation.tr("Work Calendar")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface
                                placeholderTextColor: Appearance.colors.colSubtext
                                background: Rectangle {
                                    color: Appearance.colors.colLayer1
                                    radius: Appearance.rounding.small
                                    border.width: sourceNameInput.activeFocus ? 2 : 1
                                    border.color: sourceNameInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 4
                            Layout.fillWidth: true

                            StyledText {
                                text: Translation.tr("ICS URL")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            MaterialTextField {
                                id: sourceUrlInput
                                Layout.fillWidth: true
                                placeholderText: "https:// or webcal:// (Google, Apple, Outlook .ics)"
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface
                                placeholderTextColor: Appearance.colors.colSubtext
                                background: Rectangle {
                                    color: Appearance.colors.colLayer1
                                    radius: Appearance.rounding.small
                                    border.width: sourceUrlInput.activeFocus ? 2 : 1
                                    border.color: sourceUrlInput.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 4

                            StyledText {
                                text: Translation.tr("Color")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colSubtext
                            }

                            Row {
                                id: colorPickerRow
                                spacing: 6
                                property string selectedColor: CalendarSync.presetColors[0]

                                Repeater {
                                    model: CalendarSync.presetColors

                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: modelData
                                        border.width: colorPickerRow.selectedColor === modelData ? 2 : 0
                                        border.color: Appearance.colors.colOnLayer1
                                        opacity: colorPickMA.containsMouse ? 0.8 : 1

                                        MouseArea {
                                            id: colorPickMA
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: colorPickerRow.selectedColor = modelData
                                        }
                                    }
                                }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            StyledSwitch {
                                id: sourceHolidaySwitch
                                checked: false
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                text: Translation.tr("Holiday calendar (highlight on Planner)")
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnLayer1
                                elide: Text.ElideRight
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Item { Layout.fillWidth: true }

                            RippleButton {
                                implicitWidth: cancelLabel.implicitWidth + 20
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.small
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer1Hover
                                onClicked: {
                                    addSourceForm.expanded = false
                                    sourceNameInput.text = ""
                                    sourceUrlInput.text = ""
                                    sourceHolidaySwitch.checked = false
                                }

                                contentItem: StyledText {
                                    id: cancelLabel
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Cancel")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            RippleButton {
                                implicitWidth: addLabel.implicitWidth + 20
                                implicitHeight: 30
                                buttonRadius: Appearance.rounding.small
                                colBackground: Appearance.colors.colPrimary
                                colBackgroundHover: Appearance.colors.colPrimaryHover
                                enabled: sourceNameInput.text.trim() !== "" && sourceUrlInput.text.trim() !== ""
                                opacity: enabled ? 1 : 0.5
                                onClicked: {
                                    CalendarSync.addSource(
                                        sourceNameInput.text.trim(),
                                        sourceUrlInput.text.trim(),
                                        colorPickerRow.selectedColor,
                                        sourceHolidaySwitch.checked
                                    )
                                    sourceNameInput.text = ""
                                    sourceUrlInput.text = ""
                                    sourceHolidaySwitch.checked = false
                                    addSourceForm.expanded = false
                                }

                                contentItem: StyledText {
                                    id: addLabel
                                    anchors.centerIn: parent
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    text: Translation.tr("Add")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnPrimary
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
