import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services

Item {
    id: root
    implicitWidth: gridLayout.implicitWidth
    implicitHeight: gridLayout.implicitHeight
    property bool vertical: false
    property bool invertSide: false
    property bool trayOverflowOpen: false
    property bool showSeparator: true
    property bool showOverflowMenu: true
    property var activeMenu: null
    onActiveMenuChanged: updateOverflowAutoClose()

    Timer {
        id: overflowAutoCloseTimer
        interval: 1500
        repeat: false
        onTriggered: root.trayOverflowOpen = false
    }

    function updateOverflowAutoClose(): void {
        if (!root.trayOverflowOpen) {
            overflowAutoCloseTimer.stop();
            return;
        }
        // Never auto-close while a context menu is open from an overflow item
        if (root.activeMenu !== null) {
            overflowAutoCloseTimer.stop();
            return;
        }
        const hovering = trayOverflowButton.hovered || overflowPopup.popupHovered
        if (hovering) overflowAutoCloseTimer.stop();
        else overflowAutoCloseTimer.restart();
    }

    // Signal to close all tray menus before opening a new one.
    signal closeAllTrayMenus()
    // Abyss consumes this and opens its connected Wi-Fi/Bluetooth body at the
    // System Tray module anchor. Other families ignore it.
    signal hoverPopupRequested(string kind)
    signal connectivityHoverChanged(string kind, bool hovered)

    property bool smartTray: Config.options.bar.tray.filterPassive
    
    // Filter out invalid items (null or missing id)
    function isValidItem(item) {
        return item && item.id;
    }
    
    property list<var> itemsInUserList: SystemTray.items.values.filter(i => {
        if (!isValidItem(i)) return false;
        const id = (i.id || "").toLowerCase();
        const title = (i.title || "").toLowerCase();
        const isSpotify = id.indexOf("spotify") !== -1 || title.indexOf("spotify") !== -1;
        return (Config.options?.bar?.tray?.pinnedItems ?? []).includes(i.id)
                && (!smartTray || i.status !== Status.Passive || isSpotify);
    })
    property list<var> itemsNotInUserList: SystemTray.items.values.filter(i => {
        if (!isValidItem(i)) return false;
        const id = (i.id || "").toLowerCase();
        const title = (i.title || "").toLowerCase();
        const isSpotify = id.indexOf("spotify") !== -1 || title.indexOf("spotify") !== -1;
        return !(Config.options?.bar?.tray?.pinnedItems ?? []).includes(i.id)
                && (!smartTray || i.status !== Status.Passive || isSpotify);
    })

    property bool invertPins: Config.options?.bar?.tray?.invertPinnedItems ?? false
    property list<var> pinnedItems: invertPins ? itemsNotInUserList : itemsInUserList
    property list<var> unpinnedItems: invertPins ? itemsInUserList : itemsNotInUserList
    onUnpinnedItemsChanged: {
        if (unpinnedItems.length == 0) root.closeOverflowMenu();
    }

    function setExtraWindowAndGrabFocus(window) {
        // Keep CompositorFocusGrab.active declarative. Imperatively assigning the
        // bound property would detach it from trayOverflowOpen/activeMenu and make
        // subsequent connected-surface opens lose focus-grab tracking.
        root.activeMenu = window;
    }

    function releaseFocus(window) {
        // Menu close animations are asynchronous. Ignore a delayed close from a
        // superseded menu so it cannot clear the focus grab of the current menu.
        if (root.activeMenu === window)
            root.activeMenu = null;
    }

    function closeOverflowMenu() {
        root.trayOverflowOpen = false;
    }

    // The overflow is now a lazy full-output connected surface rather than a
    // visual child window. Track the presentation window explicitly; QsWindow on
    // the StyledPopup loader describes the loader's own visual ancestry and is
    // not the lazily-created overlay surface.
    CompositorFocusGrab {
        id: focusGrab
        active: (root.trayOverflowOpen && overflowPopup.presentationWindow !== null)
            || root.activeMenu !== null
        windows: [overflowPopup.presentationWindow, root.activeMenu]
            .filter(window => window !== null)
        onCleared: {
            if (root.activeMenu) {
                root.activeMenu.close();
                root.activeMenu = null;
            }
            // If still hovering the overflow area, keep it open and let the timer handle it
            if (trayOverflowButton.hovered || overflowPopup.popupHovered) {
                root.updateOverflowAutoClose();
            } else {
                root.trayOverflowOpen = false;
            }
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.fill: parent
        rowSpacing: 8 * Appearance.sizes.barModuleScale
        columnSpacing: 15 * Appearance.sizes.barModuleScale

        RippleButton {
            id: trayOverflowButton
            visible: root.showOverflowMenu && root.unpinnedItems.length > 0
            toggled: root.trayOverflowOpen
            property bool containsMouse: hovered

            onHoveredChanged: root.updateOverflowAutoClose()

            downAction: () => root.trayOverflowOpen = !root.trayOverflowOpen

            Layout.fillHeight: !root.vertical
            Layout.fillWidth: root.vertical
            background.implicitWidth: 24 * Appearance.sizes.barModuleScale
            background.implicitHeight: 24 * Appearance.sizes.barModuleScale
            background.anchors.centerIn: this
            colBackgroundToggled: Appearance.colors.colSecondaryContainer
            colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
            colRippleToggled: Appearance.colors.colSecondaryContainerActive

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                iconSize: Math.round(Appearance.font.pixelSize.larger * Appearance.sizes.barModuleScale)
                text: "expand_more"
                horizontalAlignment: Text.AlignHCenter
                color: root.trayOverflowOpen
                    ? Appearance.colors.colOnSecondaryContainer
                    : Appearance.colors.colOnLayer2
                rotation: (root.trayOverflowOpen ? 180 : 0) - (90 * root.vertical) + (180 * root.invertSide)
                Behavior on rotation {
                    animation: NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }
            }

            StyledPopup {
                id: overflowPopup
                hoverTarget: trayOverflowButton
                hoverActivates: false
                alternativeVisibleCondition: root.trayOverflowOpen && root.unpinnedItems.length > 0
                popupBackgroundMargin: 0
                closeOnOutsideClick: false
                onRequestClose: root.trayOverflowOpen = false
                onPopupHoveredChanged: root.updateOverflowAutoClose()
                onActiveChanged: root.updateOverflowAutoClose()

                GridLayout {
                    id: trayOverflowLayout
                    anchors.centerIn: parent
                    columns: Math.ceil(Math.sqrt(root.unpinnedItems.length))
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.unpinnedItems

                        delegate: SysTrayItem {
                            required property SystemTrayItem modelData
                            item: modelData
                            sizeScale: 1
                            trayParent: root
                            Layout.fillHeight: !root.vertical
                            Layout.fillWidth: root.vertical
                            onMenuClosed: (qsWindow) => root.releaseFocus(qsWindow);
                            onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow);
                        }
                    }
                }
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.pinnedItems
            }

            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                trayParent: root
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                onMenuClosed: (qsWindow) => root.releaseFocus(qsWindow);
                onMenuOpened: (qsWindow) => {
                    root.setExtraWindowAndGrabFocus(qsWindow);
                }
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            font.pixelSize: Math.round(Appearance.font.pixelSize.larger * Appearance.sizes.barModuleScale)
            color: Appearance.colors.colSubtext
            text: "•"
            visible: root.showSeparator && SystemTray.items.values.length > 0
        }

        BarStatusIndicators {
            vertical: root.vertical
            Layout.alignment: Qt.AlignVCenter | Qt.AlignHCenter
            onHoverPopupRequested: kind => root.hoverPopupRequested(kind)
            onConnectivityHoverChanged: (kind, hovered) =>
                root.connectivityHoverChanged(kind, hovered)
        }
    }
}
