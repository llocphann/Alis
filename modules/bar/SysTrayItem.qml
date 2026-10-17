import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

MouseArea {
    id: root
    required property SystemTrayItem item
    property var trayParent: null  // Reference to SysTray for closing other menus
    // The overflow popup shares this component, but keeps its own native size.
    property real sizeScale: Appearance.sizes.barModuleScale
    readonly property bool useMonochromeIcon: Config.options?.bar?.tray?.monochromeIcons ?? false
    property bool targetMenuOpen: false
    property bool keyboardMenuMode: false

    signal menuOpened(qsWindow: var)
    signal menuClosed(qsWindow: var)

    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    activeFocusOnTab: true
    implicitWidth: 18 * root.sizeScale
    implicitHeight: 18 * root.sizeScale

    Accessible.role: Accessible.Button
    Accessible.name: root.item?.tooltipTitle || root.item?.title || Translation.tr("System tray item")
    Accessible.focusable: true

    function activatePrimary(): void {
        if (!TrayService.smartToggle(root.item))
            root.item.activate()
    }

    function openContextMenu(fromKeyboard: bool): void {
        if (!root.item.hasMenu)
            return
        if (root.trayParent)
            root.trayParent.closeAllTrayMenus()
        root.keyboardMenuMode = fromKeyboard
        menu.open()
    }

    Keys.onPressed: event => {
        if (event.isAutoRepeat)
            return
        if (event.key === Qt.Key_Return
                || event.key === Qt.Key_Enter
                || event.key === Qt.Key_Space) {
            root.activatePrimary()
            event.accepted = true
            return
        }
        if (event.key === Qt.Key_Menu
                || (event.key === Qt.Key_F10
                    && (event.modifiers & Qt.ShiftModifier))) {
            root.openContextMenu(true)
            event.accepted = true
        }
    }

    onPressed: (event) => {
        switch (event.button) {
        case Qt.LeftButton: {
            // Smart toggle: click to show, click again to minimize
            // Falls back to normal activate() if not handled
            root.activatePrimary();
            break;
        }
        case Qt.MiddleButton:
            // Middle click: try secondary activate (useful for some apps)
            item.secondaryActivate();
            break;
        case Qt.RightButton:
            root.openContextMenu(false);
            break;
        }
        event.accepted = true;
    }
    onEntered: {
        if (Config.options?.panelFamily === "abyss") { hoverMenu.restart();return }
        if (!item) return;
        const tooltipTitle = item.tooltipTitle ?? "";
        const title = item.title ?? "";
        const tooltipDescription = item.tooltipDescription ?? "";
        
        tooltip.text = tooltipTitle.length > 0 ? tooltipTitle
                : (title.length > 0 ? title : "");
        if (tooltip.text.length === 0) return;
        if (tooltipDescription.length > 0) tooltip.text += " • " + tooltipDescription;
    }

    onExited: hoverMenu.stop()
    Timer {
        id: hoverMenu
        interval: 350
        onTriggered: if(root.containsMouse && !root.pressed
                && Config.options?.panelFamily === "abyss")
            root.openContextMenu(false)
    }

    // Listen for close signal from parent tray
    Connections {
        target: root.trayParent
        enabled: root.trayParent !== null
        function onCloseAllTrayMenus() {
            if (menu.active && menu.item) {
                menu.item.close();
            }
        }
    }

    Loader {
        id: menu
        function open() {
            menu.active = true;
        }
        active: false
        sourceComponent: SysTrayMenu {
            Component.onCompleted: this.open();
            trayItemMenuHandle: root.item.menu
            anchorItem: root
            anchorHovered: root.containsMouse
            keyboardMode: root.keyboardMenuMode
            onMenuOpened: (window) => root.menuOpened(window);
            onMenuClosed: {
                root.keyboardMenuMode = false;
                // Preserve the closing window identity until after the parent has
                // reconciled focus state. A delayed close from an older menu must
                // never release the focus grab held by a newer menu.
                const window = menu.item;
                root.menuClosed(window);
                menu.active = false;
            }
        }
    }

    KeyboardFocusRing {
        anchors.fill: parent
        focusVisible: root.activeFocus
    }

    IconImage {
        id: trayIcon
        visible: !root.useMonochromeIcon
        source: root.item?.icon ?? ""
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
    }

    Loader {
        active: root.useMonochromeIcon
        anchors.centerIn: parent
        width: root.width
        height: root.height
        sourceComponent: Item {
            IconImage {
                id: tintedIcon
                visible: false
                anchors.fill: parent
                source: root.item?.icon ?? ""
            }
            Desaturate {
                id: desaturatedIcon
                visible: false
                anchors.fill: parent
                source: tintedIcon
                desaturation: 0.8
            }
            ColorOverlay {
                anchors.fill: desaturatedIcon
                source: desaturatedIcon
                color: ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.9)
            }
        }
    }

    PopupToolTip {
        id: tooltip
        extraVisibleCondition: root.containsMouse && Config.options?.panelFamily !== "abyss"
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: (Config.options?.bar?.vertical ?? false)
            ? ((Config.options?.bar?.bottom ?? false) ? Edges.Left : Edges.Right)
            : ((Config.options?.bar?.bottom ?? false) ? Edges.Top : Edges.Bottom)
    }

}
