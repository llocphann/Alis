pragma ComponentBehavior: Bound
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "EventsWindow.js" as UpcomingWindow

Item {
    id: root
    
    required property var event
    property bool isExternal: false
    property bool compactPresentation: false
    signal removeClicked()
    signal editClicked(var event)
    
    implicitHeight: cardContent.implicitHeight
        + cardContent.anchors.topMargin + cardContent.anchors.bottomMargin
    activeFocusOnTab: !root.isExternal
    Accessible.role: root.isExternal ? Accessible.StaticText : Accessible.Button
    Accessible.name: root.event?.title ?? Translation.tr("Event")
    Accessible.focusable: !root.isExternal
    Accessible.onPressAction: {
        if (!root.isExternal)
            root.editClicked(root.event)
    }

    Keys.onPressed: event => {
        if (root.isExternal || event.isAutoRepeat
                || (event.key !== Qt.Key_Return
                    && event.key !== Qt.Key_Enter
                    && event.key !== Qt.Key_Space))
            return
        root.editClicked(root.event)
        event.accepted = true
    }
    
    // Style tokens
    readonly property color colPrimary: Appearance.colors.colPrimary
    readonly property color colText: Appearance.colors.colOnLayer1
    readonly property color colSubtext: Appearance.colors.colSubtext
    readonly property color colError: Appearance.colors.colError
    readonly property color colBadge: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.90)

    // Source color for external events, priority color for local
    readonly property color indicatorColor: {
        if (root.isExternal) return root.event?.sourceColor ?? root.colPrimary
        switch (root.event?.priority ?? "normal") {
            case "high": return root.colError
            case "low": return root.colSubtext
            default: return root.colPrimary
        }
    }
    readonly property date eventDate: new Date(event.startDate || event.dateTime || "")
    readonly property date eventEndDate: event?.endDate
        ? new Date(event.endDate) : new Date("")
    readonly property bool isToday: {
        const now = new Date()
        return now.toDateString() === root.eventDate.toDateString()
    }
    readonly property bool isAllDay: root.event?.allDay ?? false
    readonly property bool isPast: UpcomingWindow.eventIsPast(
        root.eventDate, root.eventEndDate, DateTime.clock.date)
    // Passive hover tracking is shared by metadata, but the close action
    // independently tracks just its own small hit area.
    HoverHandler { id: cardHover }

    StyledRectangularShadow {
        target: cardBg
        // Default card mode has shadow visible: true
        visible: !root.compactPresentation
    }
    
    Rectangle {
        id: cardBg
        anchors.fill: parent
        radius: Appearance.rounding.small
        // The Calendar's denser card uses the darker theme layer; other
        // EventCard owners preserve their current Material treatment.
        color: root.compactPresentation
            ? (cardHover.hovered && !root.isExternal
                ? ColorUtils.mix(Appearance.colors.colLayer1,
                    Appearance.colors.colLayer2, 0.35)
                : Appearance.colors.colLayer1)
            : (editMA.containsMouse && !root.isExternal
                ? Appearance.colors.colLayer2Hover
                : (Appearance.m3colors?.m3surfaceContainerHigh ?? Appearance.colors.colLayer2))
        border.width: root.activeFocus && !root.isExternal ? 2 : 1
        border.color: root.activeFocus && !root.isExternal
            ? root.colPrimary
            : ColorUtils.transparentize(Appearance.colors.colOutlineVariant,
                root.compactPresentation ? 0.84 : 0.72)
        Behavior on color {
            enabled: Appearance.animationsEnabled
            animation: ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        
        // Indicator bar (source color for external, priority for local)
        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 4
            radius: parent.radius
            color: root.indicatorColor
        }
        
        RowLayout {
            id: cardContent
            anchors.fill: parent
            anchors.margins: root.compactPresentation ? 6 : 12
            anchors.leftMargin: root.compactPresentation ? 10 : 16
            spacing: root.compactPresentation ? 6 : 12
            
            // Category / source icon
            Rectangle {
                Layout.preferredWidth: root.compactPresentation ? 24 : 40
                Layout.preferredHeight: root.compactPresentation ? 24 : 40
                radius: width / 2
                color: ColorUtils.transparentize(root.indicatorColor, 0.85)
                
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isExternal ? "cloud_sync" : Events.getCategoryIcon(root.event.category)
                    iconSize: root.compactPresentation ? 14 : 20
                    color: root.indicatorColor
                }
            }
            
            // Event info
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: root.compactPresentation ? 2 : 4
                
                StyledText {
                    Layout.fillWidth: true
                    text: root.event?.title ?? ""
                    font.pixelSize: root.compactPresentation
                        ? Appearance.font.pixelSize.small
                        : Appearance.font.pixelSize.normal
                    font.weight: Font.Medium
                    color: root.colText
                    elide: Text.ElideRight
                }
                
                // Description or location (Agenda and Todo are independent).
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: {
                        if (root.isExternal) return root.event?.location ?? root.event?.description ?? ""
                        return root.event?.description ?? ""
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: root.colSubtext
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                }
                
                RowLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: root.compactPresentation ? 4 : 8
                    
                    // Date/time badge
                    Rectangle {
                        Layout.fillWidth: !root.compactPresentation
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: root.compactPresentation
                            ? dateTimeRow.implicitWidth + 10 : -1
                        implicitHeight: dateTimeRow.implicitHeight + 6
                        implicitWidth: dateTimeRow.implicitWidth + 10
                        radius: height / 2
                        color: root.isToday 
                            ? ColorUtils.transparentize(root.colPrimary, 0.85)
                            : root.colBadge
                        
                        RowLayout {
                            id: dateTimeRow
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 5
                            spacing: root.compactPresentation ? 3 : 4
                            
                            MaterialSymbol {
                                text: "schedule"
                                iconSize: root.compactPresentation ? 11 : 12
                                color: root.isToday ? root.colPrimary : root.colSubtext
                            }
                            
                            StyledText {
                                Layout.fillWidth: !root.compactPresentation
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                text: {
                                    if (root.isAllDay) return Translation.tr("All day")
                                    const start = Qt.formatTime(root.eventDate, "HH:mm")
                                    const range = !isNaN(root.eventEndDate.getTime())
                                        ? start + "–" + Qt.formatTime(root.eventEndDate, "HH:mm")
                                        : start
                                    // Calendar headings already identify the day.
                                    if (root.compactPresentation) return range
                                    if (root.isToday) return Translation.tr("Today") + " " + range
                                    const now = new Date()
                                    const tomorrow = new Date(now)
                                    tomorrow.setDate(tomorrow.getDate() + 1)
                                    if (root.eventDate.toDateString() === tomorrow.toDateString()) {
                                        return Translation.tr("Tomorrow") + " " + range
                                    }
                                    return Qt.formatDate(root.eventDate, "dd/MM") + " " + range
                                }
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.Medium
                                color: root.isToday ? root.colPrimary : root.colSubtext
                            }
                        }
                    }
                    
                    // Source / category badge: only reveal on card hover/focus
                    // inside the compact Calendar Popup (no blank chip at rest).
                    Rectangle {
                        visible: !root.compactPresentation
                            || cardHover.hovered || root.activeFocus
                        Layout.fillWidth: !root.compactPresentation
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: root.compactPresentation
                            ? categoryText.implicitWidth + 12 : -1
                        implicitHeight: categoryText.implicitHeight + 6
                        implicitWidth: categoryText.implicitWidth + 12
                        radius: height / 2
                        color: root.isExternal
                            ? ColorUtils.transparentize(root.indicatorColor, 0.85)
                            : root.colBadge
                        
                        StyledText {
                            id: categoryText
                            anchors.centerIn: parent
                            width: Math.max(0, parent.width - 12)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            text: {
                                if (root.isExternal) return root.event?.sourceName ?? Translation.tr("External")
                                switch (root.event?.category ?? "general") {
                                    case "birthday": return Translation.tr("Birthday")
                                    case "meeting": return Translation.tr("Meeting")
                                    case "deadline": return Translation.tr("Deadline")
                                    case "reminder": return Translation.tr("Reminder")
                                    default: return Translation.tr("General")
                                }
                            }
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            color: root.isExternal ? root.indicatorColor : root.colSubtext
                        }
                    }
                }
            }
            
            // A small reserved action area avoids card reflow. Its close icon
            // appears only when the pointer reaches this particular corner,
            // not when hovering the title/time or the rest of the card.
            RippleButton {
                Layout.preferredWidth: root.compactPresentation ? 26 : 32
                Layout.preferredHeight: root.compactPresentation ? 26 : 32
                buttonText: Translation.tr("Remove")
                buttonRadius: root.compactPresentation ? 13 : 16
                visible: !root.isExternal
                opacity: !root.compactPresentation || removeHover.hovered
                    || activeFocus ? 1 : 0
                HoverHandler { id: removeHover }
                Behavior on opacity {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation { duration: 100 }
                }
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                onClicked: root.removeClicked()
                
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: root.compactPresentation ? 14 : 16
                    color: root.colSubtext
                }
                
                StyledToolTip {
                    text: Translation.tr("Remove")
                }
            }
        }
        
         // Click to edit (local only)
        MouseArea {
            id: editMA
            anchors.fill: parent
            z: -1
            hoverEnabled: !root.isExternal
            cursorShape: root.isExternal ? Qt.ArrowCursor : Qt.PointingHandCursor
            onClicked: {
                if (!root.isExternal) root.editClicked(root.event)
            }
        }
    }
}
