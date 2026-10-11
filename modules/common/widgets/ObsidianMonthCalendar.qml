pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property date viewingDate
    required property date today
    property var locale: Qt.locale()
    property var calendarCells: []
    property var selectedDate: null
    property bool interactiveDays: false
    property bool showEventDots: false
    // Opt in only for the Popup: existing Sidebar/Dashboard source-color
    // dots retain their original distinct-color presentation by default.
    property bool countedEventDots: false
    property int maxEventDots: 3
    readonly property int effectiveMaxEventDots: Math.max(0, Math.min(5, root.maxEventDots))
    // Popup consumers keep the compact 30px cells. Sidebar/Dashboard opt into
    // responsive sizing so the same visual language can use available width
    // without turning into a second Calendar style.
    property bool responsive: false
    property real responsiveMinCellSize: 30
    property real responsiveMaxCellSize: 42
    property real responsiveAvailableHeight: 0
    property bool showWeekNumbers: false
    property bool autoWeekNumbers: false

    signal previousMonthRequested()
    signal nextMonthRequested()
    signal todayRequested()
    signal dayActivated(var date)

    readonly property real compactCellSize: 30
    readonly property real compactCellSpacing: 4
    readonly property real responsiveCellSpacing: 6
    readonly property real cellSpacing: root.responsive
        ? root.responsiveCellSpacing : root.compactCellSpacing
    readonly property real weekNumberWidth: 32
    readonly property bool effectiveWeekNumbers: root.showWeekNumbers
        || (root.autoWeekNumbers && root.responsive && root.width > 0
            && root.width >= (7 * root.responsiveMaxCellSize
                + 6 * root.cellSpacing + root.weekNumberWidth
                + root.cellSpacing + 18))
    readonly property real cellSize: {
        if (!root.responsive || !(root.width > 0))
            return root.compactCellSize
        const weekReserve = root.effectiveWeekNumbers
            ? root.weekNumberWidth + root.cellSpacing : 0
        const widthAvailable = Math.max(0,
            root.width - weekReserve - 6 * root.cellSpacing)
        let target = widthAvailable / 7
        if (root.responsiveAvailableHeight > 0) {
            const fixedHeight = 30 + 10 + 20 + 6 * 3
            const heightAvailable = Math.max(0,
                root.responsiveAvailableHeight - fixedHeight) / 6
            target = Math.min(target, heightAvailable)
        }
        return Math.max(root.responsiveMinCellSize,
            Math.min(root.responsiveMaxCellSize, target))
    }
    readonly property color colText: Appearance.colors.colOnSurface
    readonly property color colMuted: Appearance.colors.colOnSurfaceVariant
    readonly property color colAccent: Appearance.colors.colPrimary
    readonly property color colHover: Appearance.colors.colLayer1Hover

    readonly property var weekDaysModel: {
        const monday = new Date(2024, 0, 1)
        const labels = []
        for (let i = 0; i < 7; ++i) {
            const d = new Date(monday)
            d.setDate(monday.getDate() + i)
            labels.push(root.locale.toString(d, "ddd").toUpperCase())
        }
        return labels
    }

    function sameDay(a, b): bool {
        if (!(a instanceof Date) || !(b instanceof Date)
                || isNaN(a.getTime()) || isNaN(b.getTime()))
            return false
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function isoWeekNumber(value): int {
        if (!(value instanceof Date) || isNaN(value.getTime()))
            return 0
        const date = new Date(Date.UTC(
            value.getFullYear(), value.getMonth(), value.getDate()))
        const day = date.getUTCDay() || 7
        date.setUTCDate(date.getUTCDate() + 4 - day)
        const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1))
        return Math.ceil((((date - yearStart) / 86400000) + 1) / 7)
    }

    readonly property var weekNumbers: {
        const result = []
        for (let row = 0; row < 6; ++row) {
            const cell = root.calendarCells[row * 7]
            result.push(root.isoWeekNumber(cell?.date))
        }
        return result
    }

    implicitWidth: calendarBody.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    ColumnLayout {
        id: contentColumn
        width: root.responsive && root.width > 0
            ? Math.max(root.implicitWidth, root.width)
            : root.implicitWidth
        spacing: 10

        Item {
            id: calendarHeader
            Layout.preferredWidth: calendarBody.implicitWidth
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 30

            // Align the month title with the visible MON label rather than the
            // left edge of MON's cell. This remains exact as responsive cells grow.
            StyledText {
                id: mondayMeasure
                visible: false
                text: String(root.weekDaysModel[0] ?? "MON")
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                font.letterSpacing: 1
            }

            Row {
                id: monthTitle
                x: (root.effectiveWeekNumbers
                    ? root.weekNumberWidth + root.cellSpacing : 0)
                    + Math.max(0,
                        (root.cellSize - mondayMeasure.implicitWidth) / 2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                StyledText {
                    text: root.locale.toString(root.viewingDate, "MMM")
                    color: root.colText
                    font.pixelSize: Math.round(Appearance.font.pixelSize.normal * 1.35)
                    font.weight: Font.Medium
                }

                StyledText {
                    text: root.locale.toString(root.viewingDate, "yyyy")
                    color: root.colAccent
                    font.pixelSize: Math.round(Appearance.font.pixelSize.normal * 1.35)
                    font.weight: Font.Medium
                }
            }

            Row {
                id: navRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                NavButton {
                    iconName: "chevron_left"
                    accessibleName: Translation.tr("Previous month")
                    onClicked: root.previousMonthRequested()
                }

                Item {
                    id: todayButton
                    readonly property bool currentMonth:
                        root.viewingDate.getMonth() === root.today.getMonth()
                        && root.viewingDate.getFullYear() === root.today.getFullYear()
                    implicitWidth: 50
                    implicitHeight: 28
                    opacity: 1
                    activeFocusOnTab: true

                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("Today")
                    Accessible.focusable: true
                    Accessible.onPressAction: root.todayRequested()

                    Rectangle {
                        anchors.fill: parent
                        radius: Appearance.rounding.small
                        color: todayMouse.containsMouse ? root.colHover : "transparent"
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: Translation.tr("Today").toUpperCase()
                        color: todayButton.currentMonth ? root.colMuted : root.colAccent
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                    }

                    MouseArea {
                        id: todayMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.todayRequested()
                    }

                    Keys.onPressed: event => {
                        if (event.isAutoRepeat
                                || (event.key !== Qt.Key_Return
                                    && event.key !== Qt.Key_Enter
                                    && event.key !== Qt.Key_Space))
                            return
                        root.todayRequested()
                        event.accepted = true
                    }
                }

                NavButton {
                    iconName: "chevron_right"
                    accessibleName: Translation.tr("Next month")
                    onClicked: root.nextMonthRequested()
                }
            }
        }

        RowLayout {
            id: calendarBody
            Layout.alignment: Qt.AlignHCenter
            spacing: root.effectiveWeekNumbers ? root.cellSpacing : 0

            ColumnLayout {
                visible: root.effectiveWeekNumbers
                spacing: 3

                StyledText {
                    Layout.preferredWidth: root.weekNumberWidth
                    Layout.preferredHeight: 20
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: Translation.tr("WK")
                    color: root.colMuted
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                    opacity: 0.7
                }

                Repeater {
                    model: root.weekNumbers

                    delegate: StyledText {
                        required property var modelData
                        Layout.preferredWidth: root.weekNumberWidth
                        Layout.preferredHeight: root.cellSize
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: String(modelData ?? "")
                        color: root.colMuted
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.family: Appearance.font.family.numbers
                        opacity: 0.62
                    }
                }
            }

            GridLayout {
                id: calendarGrid
                columns: 7
                columnSpacing: root.cellSpacing
                rowSpacing: 3

                Repeater {
                    model: root.weekDaysModel

                    delegate: StyledText {
                        required property var modelData
                        Layout.preferredWidth: root.cellSize
                        Layout.preferredHeight: 20
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: String(modelData)
                        color: root.colMuted
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                    }
                }

                Repeater {
                    model: root.calendarCells

                    delegate: Rectangle {
                        id: dayCell
                        objectName: "calendarEventDayCell"
                        required property int index
                        required property var modelData

                        readonly property int eventCount:
                            Number(dayCell.modelData?.eventCount ?? 0)
                        readonly property var eventColors:
                            dayCell.modelData?.eventColors ?? []
                        readonly property bool selected: root.sameDay(
                            dayCell.modelData?.date, root.selectedDate)

                        Layout.preferredWidth: root.cellSize
                        Layout.preferredHeight: root.cellSize
                        radius: Appearance.rounding.small
                        color: dayCell.selected
                            ? Appearance.colors.colPrimaryContainer
                            : dayHover.containsMouse
                                ? root.colHover : "transparent"
                        opacity: dayCell.modelData?.currentMonth === false ? 0.25 : 1

                        StyledText {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset:
                                root.showEventDots && dayCell.eventCount > 0
                                    && (!root.countedEventDots || root.effectiveMaxEventDots > 0)
                                    ? -2 : 0
                            text: String(dayCell.modelData?.day ?? "")
                            color: dayCell.selected
                                ? Appearance.colors.colOnPrimaryContainer
                                : dayCell.modelData?.today
                                    ? root.colAccent : root.colText
                            font.pixelSize:
                                root.responsive && root.cellSize >= 38
                                    ? Appearance.font.pixelSize.normal
                                    : Appearance.font.pixelSize.small
                            font.weight: dayCell.selected
                                || dayCell.modelData?.today
                                    ? Font.DemiBold : Font.Normal
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 2
                            spacing: 1
                            visible: root.showEventDots && dayCell.eventCount > 0
                                && (!root.countedEventDots || root.effectiveMaxEventDots > 0)

                            Repeater {
                                model: {
                                    if (!root.countedEventDots) {
                                        // Preserve current Sidebar/Dashboard behavior.
                                        if (dayCell.eventColors?.length > 0)
                                            return dayCell.eventColors.slice(0, 3)
                                        return [root.colAccent]
                                    }
                                    const count = Math.min(Math.max(0, dayCell.eventCount),
                                        root.effectiveMaxEventDots)
                                    const colors = []
                                    for (let i = 0; i < count; ++i)
                                        colors.push(dayCell.eventColors[i] ?? root.colAccent)
                                    return colors
                                }

                                delegate: Rectangle {
                                    objectName: "calendarEventDot"
                                    required property var modelData
                                    width: 3
                                    height: 3
                                    radius: 1.5
                                    color: modelData
                                }
                            }

                            // Extra events are still visible as a compact + cue;
                            // the complete count remains in the day model.
                            StyledText {
                                objectName: "calendarEventOverflow"
                                visible: root.countedEventDots
                                    && dayCell.eventCount > root.effectiveMaxEventDots
                                text: "+"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                color: root.colAccent
                            }
                        }

                        MouseArea {
                            id: dayHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: root.interactiveDays
                                ? Qt.LeftButton : Qt.NoButton
                            cursorShape: root.interactiveDays
                                ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (root.interactiveDays
                                        && dayCell.modelData?.date)
                                    root.dayActivated(dayCell.modelData.date)
                            }
                        }
                    }
                }
            }
        }
    }

    component NavButton: Item {
        id: navButton
        required property string iconName
        required property string accessibleName
        signal clicked()

        implicitWidth: 24
        implicitHeight: 28
        activeFocusOnTab: true

        Accessible.role: Accessible.Button
        Accessible.name: navButton.accessibleName
        Accessible.focusable: true
        Accessible.onPressAction: navButton.clicked()

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.small
            color: navMouse.containsMouse ? root.colHover : "transparent"
        }

        MaterialSymbol {
            anchors.centerIn: parent
            text: navButton.iconName
            iconSize: 16
            color: root.colMuted
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: navButton.clicked()
        }

        Keys.onPressed: event => {
            if (event.isAutoRepeat
                    || (event.key !== Qt.Key_Return
                        && event.key !== Qt.Key_Enter
                        && event.key !== Qt.Key_Space))
                return
            navButton.clicked()
            event.accepted = true
        }
    }
}
