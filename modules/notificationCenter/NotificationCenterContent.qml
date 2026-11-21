pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

Item {
    id: root

    property bool showOpenCenterButton: false
    property bool popupPresentation: false
    readonly property bool dragActive: listview.dragIndex >= 0
    // The corner popup is intentionally glanceable: searching belongs to the
    // larger notification-center surfaces, not this compact two-tab panel.
    readonly property bool searchVisible:
        !root.popupPresentation && Notifications.list.length > 3

    readonly property bool compactHeight: root.height > 0 && root.height < 260
    readonly property bool narrowWidth: root.width > 0 && root.width < 320

    signal openCenterRequested()
    signal searchFocusRequested()
    signal externalNavigationRequested()

    function focusSearch(): void {
        searchField.forceActiveFocus()
    }

    function clearSearchFocus(): void {
        searchField.focus = false
    }

    Component.onCompleted: Notifications.ensureInitialized()

    ColumnLayout {
        anchors.fill: parent
        spacing: root.compactHeight ? 6 : 10

        RowLayout {
            Layout.fillWidth: true
            spacing: root.narrowWidth ? 6 : 8

            MaterialSymbol {
                text: Notifications.silent ? "notifications_paused" : "notifications"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Notifications")
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Notifications.silent
                        ? Translation.tr("Silent · %1 total").arg(Notifications.list.length)
                        : Translation.tr("%1 unread · %2 total")
                            .arg(Notifications.unread).arg(Notifications.list.length)
                    color: Appearance.colors.colOnLayer1
                    opacity: 0.78
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            RippleButton {
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                enabled: Notifications.unread > 0
                onClicked: Notifications.markAllRead()

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "done_all"
                        iconSize: 17
                        color: Notifications.unread > 0
                            ? Appearance.colors.colOnLayer1 : Appearance.colors.colSubtext
                    }
                }

                StyledToolTip { text: Translation.tr("Mark all as read") }
            }

            RippleButton {
                visible: root.showOpenCenterButton
                implicitWidth: 30
                implicitHeight: 30
                buttonRadius: Appearance.rounding.full
                colBackground: "transparent"
                colBackgroundHover: Appearance.colors.colLayer1Hover
                colRipple: Appearance.colors.colLayer1Active
                onClicked: root.openCenterRequested()

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "open_in_new"
                        iconSize: 17
                        color: Appearance.colors.colOnLayer1
                    }
                }

                StyledToolTip { text: Translation.tr("Open notification center") }
            }
        }

        ToolbarTextField {
            id: searchField
            visible: root.searchVisible
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 36
            placeholderText: Translation.tr("Search notifications")
            onVisibleChanged: {
                if (!visible) text = ""
            }

            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.searchFocusRequested()
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            NotificationListView {
                id: listview
                anchors.fill: parent
                clip: true
                dataMode: "history"
                popupPresentation: root.popupPresentation
                // History should consume the available canvas before hiding
                // information. If it grows beyond the viewport the list scrolls;
                // groups are collapsed only by an explicit user action.
                preferExpanded: true
                modernCards: true
                compactCards: root.popupPresentation
                compactActions: root.popupPresentation
                filterQuery: searchField.text
                onExternalLinkOpened: root.externalNavigationRequested()
                onNotificationActionInvoked:
                    root.externalNavigationRequested()
            }

            MaterialPlaceholderMessage {
                anchors.centerIn: parent
                maximumWidth: Math.min(
                    Math.max(220, Math.round(parent.width * 0.72)),
                    Math.max(120, parent.width - 24))
                compact: root.popupPresentation || root.compactHeight || root.narrowWidth
                shown: Notifications.list.length === 0
                    || (root.searchVisible && searchField.text.trim().length > 0
                        && listview.count === 0)
                icon: Notifications.list.length === 0
                    ? "notifications_active" : "search_off"
                text: Notifications.list.length === 0
                    ? (Notifications.silent
                        ? Translation.tr("Muted")
                        : Translation.tr("All caught up"))
                    : Translation.tr("No matching notifications")
                shape: MaterialShape.Shape.Ghostish
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Keep footer actions visually quiet: labels live in hover tooltips
            // and accessibility names while the persistent affordance is a
            // high-contrast Material icon.
            Item {
                Layout.fillWidth: true
                implicitWidth: 1
            }

            RippleButton {
                id: notificationModeButton
                implicitWidth: root.popupPresentation ? 30 : 36
                implicitHeight: root.popupPresentation ? 30 : 36
                buttonText: Notifications.silent
                    ? Translation.tr("Resume") : Translation.tr("Do Not Disturb")
                buttonRadius: Appearance.rounding.full
                colBackground: Notifications.silent
                    ? Appearance.colors.colPrimaryContainer
                    : Appearance.colors.colLayer2
                colBackgroundHover: Notifications.silent
                    ? Appearance.colors.colPrimaryContainerHover
                    : Appearance.colors.colLayer2Hover
                colRipple: Notifications.silent
                    ? Appearance.colors.colPrimaryContainerActive
                    : Appearance.colors.colLayer2Active
                onClicked: Notifications.toggleSilent()

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: Notifications.silent
                            ? "notifications_active" : "notifications_off"
                        iconSize: root.popupPresentation ? 17 : 20
                        fill: 1
                        color: Notifications.silent
                            ? Appearance.colors.colOnPrimaryContainer
                            : Appearance.colors.colOnLayer2
                    }
                }

                StyledToolTip { text: notificationModeButton.buttonText }
            }

            RippleButton {
                id: clearAllButton
                implicitWidth: root.popupPresentation ? 30 : 36
                implicitHeight: root.popupPresentation ? 30 : 36
                buttonText: Translation.tr("Clear all")
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colLayer2
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                enabled: Notifications.list.length > 0
                onClicked: Notifications.discardAllNotifications()

                contentItem: Item {
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "delete_sweep"
                        iconSize: root.popupPresentation ? 17 : 20
                        fill: 1
                        color: Appearance.colors.colOnLayer2
                    }
                }

                StyledToolTip { text: clearAllButton.buttonText }
            }
        }
    }
}
