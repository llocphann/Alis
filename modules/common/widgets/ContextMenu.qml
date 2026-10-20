pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Loader {
    id: root

    property var model: []
    property Item anchorItem: parent
    property real padding: 4
    property bool noSmoothClosing: false
    property bool closeOnFocusLost: true
    property bool keyboardGrab: true
    property bool closeOnHoverLost: true
    property bool closeOnHoverLostAfterEntered: false
    property int closeOnHoverLostDelay: 500  // ms before closing when hover lost (waffle uses 500)
    property bool anchorHovered: false
    property bool closeOnOutsideClick: false
    property var anchorRect: null
    property var popupAdjustment: null
    property bool scaleContent: Config.options?.panelFamily === "abyss" ? false : Appearance.motion.popupReveal.enableScale
    // Cursor-positioned desktop menus use a quick slide-only reveal. Other
    // ContextMenu consumers retain the regular fade/scale profile.
    property bool cursorSlide: false
    // A cursor menu belongs to the desktop PanelWindow, never to a moving
    // one-pixel Item. Coordinates are local to that window's content.
    property var cursorAnchorWindow: null
    property real cursorAnchorX: 0
    property real cursorAnchorY: 0

    // Mapped xdg-popups are not reliably reanchorable on Niri. Queue the
    // latest click, slide the old menu away, then remap a single new popup.
    property bool relocationQueued: false
    property bool relocationCommitting: false
    property real relocationX: 0
    property real relocationY: 0
    property var relocationModel: null
    property bool relocationModelProvided: false
    signal focusCleared()

    property real visualMargin: 8
    property bool popupAbove: true  // true = popup appears above anchor, false = below
    property int popupSide: 0  // For horizontal popup: Edges.Left or Edges.Right, 0 = vertical
    property real ambientShadowWidth: 1
    property color panelFallbackColor: Config.options?.panelFamily === "abyss"
        ? Qt.alpha(Appearance.colors.colLayer2Base,.92)
        : Appearance.colors.colSurfaceContainer
    property real panelRadius: Appearance.rounding.normal
    property real panelBorderWidth: Config.options?.panelFamily === "abyss" ? 0 : 1
    property color panelBorderColor: Appearance.colors.colSurfaceContainerHighest
    readonly property bool hasIcons: model.some(item => item.iconName !== undefined && item.iconName !== "")

    onFocusCleared: {
        if (!root.closeOnFocusLost) return;
        root.close()
    }

    function grabFocus(): void {
        if (item) item.grabFocus();
    }

    function close(): void {
        root.relocationQueued = false
        root.relocationModelProvided = false
        if (item) item.close();
        else root.active = false;
    }

    function requestOpen(): void {
        if (GlobalStates.activeContextMenu && GlobalStates.activeContextMenu !== root)
            GlobalStates.activeContextMenu.active = false
        root.active = true
    }

    // Coordinates belong to anchorItem.parent, not the pointer handler.
    // Relocation unmaps the old xdg-popup, then maps a single new surface.
    function requestOpenAt(x: real, y: real, newModel: var): void {
        const nextX = Number(x)
        const nextY = Number(y)
        if (!Number.isFinite(nextX) || !Number.isFinite(nextY) || !root.anchorItem)
            return
        if (root.relocationQueued) {
            root.relocationX = nextX
            root.relocationY = nextY
            if (newModel !== undefined) {
                root.relocationModel = newModel
                root.relocationModelProvided = true
            }
            return
        }
        if (root.active && root.item && root.cursorSlide) {
            root.relocationQueued = true
            root.relocationX = nextX
            root.relocationY = nextY
            root.relocationModel = newModel
            root.relocationModelProvided = newModel !== undefined
            if (Appearance.animationsEnabled)
                root.item.slideForRelocation()
            else
                root.commitRelocation()
            return
        }
        if (newModel !== undefined)
            root.model = newModel
        root.anchorItem.x = nextX
        root.anchorItem.y = nextY
        if (root.cursorSlide) {
            root.cursorAnchorX = nextX
            root.cursorAnchorY = nextY
        }
        if (root.active && root.item)
            root.item.anchor.updateAnchor()
        root.requestOpen()
    }

    function commitRelocation(): void {
        if (!root.relocationQueued) return
        // Loader.active=false releases the native PopupWindow before we set
        // the new position. Defer remapping into the following event loop.
        root.relocationCommitting = true
        root.active = false
        root.relocationCommitting = false
        Qt.callLater(() => {
            if (!root.relocationQueued || root.active || !root.anchorItem)
                return
            if (GlobalStates.activeContextMenu && GlobalStates.activeContextMenu !== root) {
                root.relocationQueued = false
                root.relocationModelProvided = false
                return
            }
            root.anchorItem.x = root.relocationX
            root.anchorItem.y = root.relocationY
            root.cursorAnchorX = root.relocationX
            root.cursorAnchorY = root.relocationY
            if (root.relocationModelProvided)
                root.model = root.relocationModel
            root.relocationQueued = false
            root.relocationModelProvided = false
            root.requestOpen()
        })
    }

    function updateAnchor(): void {
        item?.anchor.updateAnchor();
    }

    active: false
    visible: active

    onActiveChanged: {
        if (active) {
            GlobalStates.activeContextMenu = root
            GlobalStates.activeContextMenuCount++
        } else {
            if (!root.relocationCommitting) {
                root.relocationQueued = false
                root.relocationModelProvided = false
            }
            if (GlobalStates.activeContextMenu === root)
                GlobalStates.activeContextMenu = null
            GlobalStates.activeContextMenuCount--
        }
    }

    sourceComponent: PopupWindow {
        id: popupWindow
        // Do not map a cursor popup until anchor.window is explicitly valid.
        // Otherwise Niri can put remapped popups at the output origin (0,0).
        property bool cursorAnchorReady: false
        visible: !root.cursorSlide || popupWindow.cursorAnchorReady
        // Qt's grabbed xdg-popup forwards outside pointer events to the
        // desktop with popup-local coordinates on Niri. A second right-click
        // then subtracts the previous popup origin from the desktop point.
        // Cursor menus use their desktop owner's on-demand keyboard focus;
        // avoid the pointer grab rather than compensating with an offset.
        grabFocus: root.keyboardGrab && CompositorService.isNiri && !root.cursorSlide
        property bool closing: false
        // Popup animations can sweep the content under a stationary pointer,
        // especially when the desktop menu opens near a retracted Abyss Edge.
        // A transient hover during this entrance is not a user visit: only
        // arm hover-loss dismissal after the content has settled.
        property bool entranceSettled: false
        property bool popupWasHovered: false

        // Keep the Niri click surface below the popup content, matching the
        // SysTrayMenu stacking order so outside clicks close without blocking buttons.
        PanelWindow {
            id: clickOutsideBackdrop
            screen: popupWindow.screen
            visible: CompositorService.isNiri && popupWindow.visible
                && (root.closeOnFocusLost || root.closeOnOutsideClick)
            color: Qt.rgba(0, 0, 0, 1/255)
            exclusiveZone: 0
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "quickshell:contextMenuBackdrop"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()
            }
        }

        Component.onCompleted: {
            if (root.cursorSlide) {
                // A reliable window-relative anchor per Quickshell PopupAnchor:
                // bypass item-to-window geometry cached on the previous popup.
                // The point is already in this PanelWindow's coordinate space.
                popupWindow.anchor.window = root.cursorAnchorWindow;
                popupWindow.cursorAnchorReady = popupWindow.anchor.window !== null;
                if (!popupWindow.cursorAnchorReady)
                    console.warn("[DesktopContextMenu] Missing desktop parent window");
            }
            realContent.shown = true;
            Qt.callLater(() => keyHandler.forceActiveFocus());
            if (Appearance.animationsEnabled)
                openAnim.start();
            else {
                popupWindow.sourceEdgeMargin = popupWindow.settledMargin;
                popupWindow.entranceSettled = true;
            }
        }

        Item {
            id: keyHandler
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                }
            }
        }

        anchor {
            adjustment: root.popupAdjustment ?? ((root.popupSide !== 0)
                ? (PopupAdjustment.ResizeX | PopupAdjustment.SlideY)
                : (PopupAdjustment.ResizeY | PopupAdjustment.SlideX))
            // Non-desktop menus retain item anchoring unchanged. Cursor menus
            // use an explicit anchor.window, set before mapping above.
            item: root.cursorSlide ? null : root.anchorItem
            rect.x: root.cursorSlide ? Math.round(root.cursorAnchorX)
                : Number(root.anchorRect?.x ?? 0)
            rect.y: root.cursorSlide ? Math.round(root.cursorAnchorY)
                : Number(root.anchorRect?.y ?? 0)
            rect.width: root.cursorSlide ? 1
                : Number(root.anchorRect?.width ?? (root.anchorItem?.width ?? 0))
            rect.height: root.cursorSlide ? 1
                : Number(root.anchorRect?.height ?? (root.anchorItem?.height ?? 0))
            onAnchoring: {
                if (root.cursorSlide && Quickshell.env("ALIS_CONTEXT_MENU_DEBUG") === "1")
                    console.info("[DesktopContextMenu] anchoring",
                        "output", popupWindow.screen?.name ?? "?",
                        "at", root.cursorAnchorX, root.cursorAnchorY,
                        "rect", popupWindow.anchor.rect.x, popupWindow.anchor.rect.y)
            }
            // A single vertical Edge flag centers the popup on the X axis.
            // Cursor menus need an explicit LEFT anchor / RIGHT expansion so
            // their top-left corner lands next to the pointer, not centered.
            gravity: root.cursorSlide
                ? ((root.popupAbove ? Edges.Top : Edges.Bottom) | Edges.Right)
                : (root.popupSide !== 0 ? root.popupSide
                    : (root.popupAbove ? Edges.Top : Edges.Bottom))
            edges: root.cursorSlide
                ? ((root.popupAbove ? Edges.Top : Edges.Bottom) | Edges.Left)
                : (root.popupSide !== 0 ? root.popupSide
                    : (root.popupAbove ? Edges.Top : Edges.Bottom))
        }

        CompositorFocusGrab {
            id: focusGrab
            active: root.closeOnFocusLost && CompositorService.isHyprland
            windows: [popupWindow]
            onCleared: root.focusCleared();
        }

        Timer {
            id: closeTimer
            interval: root.closeOnHoverLostDelay
            running: root.closeOnHoverLost
                && popupWindow.visible
                && !popupWindow.popupContainsMouse
                && !root.anchorHovered
                && (!root.closeOnHoverLostAfterEntered || popupWindow.popupWasHovered)
            onTriggered: root.close()
        }

        function close(): void {
            if (root.noSmoothClosing || !Appearance.animationsEnabled) {
                root.active = false;
            } else if (root.cursorSlide) {
                openAnim.stop();
                relocationAnim.stop();
                popupWindow.closing = true;
                realContent.shown = false;
                closeAnim.restart();
            } else {
                popupWindow.closing = true;
                realContent.shown = false;
                closeAnim.start();
            }
        }

        function slideForRelocation(): void {
            openAnim.stop();
            closeAnim.stop();
            relocationAnim.stop();
            popupWindow.closing = true;
            relocationAnim.start();
        }

        function grabFocus(): void {
            focusGrab.active = true;
        }

        implicitWidth: realContent.implicitWidth + (root.ambientShadowWidth * 2) + (root.visualMargin * 2)
        implicitHeight: realContent.implicitHeight + (root.ambientShadowWidth * 2) + (root.visualMargin * 2)
        mask: Region {
            item: realContent
        }

        readonly property real settledMargin: root.ambientShadowWidth + root.visualMargin
        // Material keeps the established slide-in geometry; contextual motion
        // is handled independently by the shared popupReveal opacity/scale profile.
        property real sourceEdgeMargin: -implicitHeight
        readonly property bool isHorizontalPopup: root.popupSide !== 0
        readonly property bool isLeftSide: root.popupSide === Edges.Left

        PropertyAnimation {
            id: openAnim
            target: popupWindow
            property: "sourceEdgeMargin"
            to: popupWindow.settledMargin
            duration: root.cursorSlide ? Math.min(165, Appearance.animation.elementMoveEnter.duration)
                : Appearance.animation.elementMoveEnter.duration
            easing.type: Appearance.animation.elementMoveEnter.type
            easing.bezierCurve: Appearance.motion.popupReveal.enterBezierCurve
            onStopped: {
                if (popupWindow.closing) return
                popupWindow.entranceSettled = true
                if (popupWindow.popupContainsMouse)
                    popupWindow.popupWasHovered = true
            }
        }
        SequentialAnimation {
            id: closeAnim
            PropertyAnimation {
                target: popupWindow
                property: "sourceEdgeMargin"
                to: popupWindow.isHorizontalPopup ? -popupWindow.implicitWidth : -popupWindow.implicitHeight
                duration: root.cursorSlide ? Math.min(115, Appearance.animation.elementMoveExit.duration)
                    : Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            ScriptAction {
                script: root.active = false
            }
        }

        SequentialAnimation {
            id: relocationAnim
            PropertyAnimation {
                target: popupWindow
                property: "sourceEdgeMargin"
                to: popupWindow.isHorizontalPopup
                    ? -popupWindow.implicitWidth : -popupWindow.implicitHeight
                duration: Math.min(115, Appearance.animation.elementMoveExit.duration)
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            ScriptAction { script: root.commitRelocation() }
        }

        color: "transparent"

        StyledRectangularShadow {
            target: realContent
        }

        GlassBackground {
            id: realContent
            z: 1
            property bool shown: false
            anchors {
                // Vertical popup (above/below)
                left: !popupWindow.isHorizontalPopup ? parent.left : (popupWindow.isLeftSide ? undefined : parent.left)
                right: !popupWindow.isHorizontalPopup ? parent.right : (popupWindow.isLeftSide ? parent.right : undefined)
                top: !popupWindow.isHorizontalPopup ? (root.popupAbove ? undefined : parent.top) : parent.top
                bottom: !popupWindow.isHorizontalPopup ? (root.popupAbove ? parent.bottom : undefined) : parent.bottom

                margins: root.ambientShadowWidth + root.visualMargin
                bottomMargin: !popupWindow.isHorizontalPopup && root.popupAbove ? popupWindow.sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                topMargin: !popupWindow.isHorizontalPopup && !root.popupAbove ? popupWindow.sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                leftMargin: popupWindow.isHorizontalPopup && !popupWindow.isLeftSide ? popupWindow.sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
                rightMargin: popupWindow.isHorizontalPopup && popupWindow.isLeftSide ? popupWindow.sourceEdgeMargin : (root.ambientShadowWidth + root.visualMargin)
            }
            fallbackColor: root.panelFallbackColor
            alisColor: Appearance.alis.colLayer2
            auroraTransparency: Appearance.aurora.popupTransparentize
            radius: root.panelRadius
            border.width: root.panelBorderWidth
            border.color: root.panelBorderColor
            opacity: root.cursorSlide ? 1
                : (Appearance.motion.popupReveal.enableFade ? (shown ? 1 : 0) : 1)
            scale: shown ? 1
                : (root.scaleContent
                    ? Appearance.motion.popupReveal.closedScale
                    : 1)
            transformOrigin: popupWindow.isHorizontalPopup
                ? (popupWindow.isLeftSide ? Item.Left : Item.Right)
                : (root.popupAbove ? Item.Bottom : Item.Top)

            implicitWidth: menuColumn.implicitWidth + (root.padding * 2)
            implicitHeight: menuColumn.implicitHeight + (root.padding * 2)

            Behavior on opacity {
                enabled: Appearance.animationsEnabled && !root.cursorSlide
                animation: NumberAnimation {
                    duration: popupWindow.closing
                        ? Appearance.animation.elementMoveExit.duration
                        : Appearance.animation.elementMoveEnter.duration
                    easing.type: popupWindow.closing
                        ? Appearance.animation.elementMoveExit.type
                        : Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: popupWindow.closing
                        ? Appearance.animation.elementMoveExit.bezierCurve
                        : Appearance.motion.popupReveal.enterBezierCurve
                }
            }

            Behavior on scale {
                enabled: Appearance.animationsEnabled && root.scaleContent
                animation: NumberAnimation {
                    duration: popupWindow.closing
                        ? Appearance.animation.elementMoveExit.duration
                        : Appearance.animation.elementMoveEnter.duration
                    easing.type: popupWindow.closing
                        ? Appearance.animation.elementMoveExit.type
                        : Appearance.animation.elementMoveEnter.type
                    easing.bezierCurve: popupWindow.closing
                        ? Appearance.animation.elementMoveExit.bezierCurve
                        : Appearance.motion.popupReveal.enterBezierCurve
                }
            }

            ColumnLayout {
                id: menuColumn
                anchors.centerIn: parent
                spacing: 0

                Repeater {
                    model: root.model
                    delegate: DelegateChooser {
                        role: "type"
                        DelegateChoice {
                            roleValue: "separator"
                            Rectangle {
                                Layout.topMargin: 2
                                Layout.bottomMargin: 2
                                Layout.fillWidth: true
                                implicitHeight: 1
                                color: Appearance.colors.colOutlineVariant
                            }
                        }
                        DelegateChoice {
                            roleValue: undefined
                            RippleButton {
                                id: menuBtn
                                Layout.fillWidth: true

                                required property var modelData
                                enabled: modelData.enabled !== false
                                opacity: enabled ? 1 : 0.45
                                buttonHovered: enabled && menuHover.hovered

                                implicitWidth: Math.max(140, menuRow.implicitWidth + 20)
                                implicitHeight: 32
                                buttonRadius: Appearance.rounding.small
                                colBackground: "transparent"
                                colBackgroundHover: ColorUtils.transparentize(
                                    Appearance.colors.colPrimary, 0.85)
                                colRipple: ColorUtils.transparentize(
                                    Appearance.colors.colPrimary, 0.7)

                                onClicked: {
                                    if (!enabled) return;
                                    // Some actions remove the delegate that owns this menu.
                                    // Close first so the follow-up does not dereference a
                                    // context-menu loader destroyed by its own action.
                                    const action = modelData.action;
                                    root.close();
                                    if (action) action();
                                }

                                HoverHandler {
                                    id: menuHover
                                }

                                contentItem: RowLayout {
                                    id: menuRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: anchors.leftMargin
                                    spacing: 8

                                    Loader {
                                        active: root.hasIcons
                                        visible: active
                                        Layout.alignment: Qt.AlignVCenter

                                        sourceComponent: menuBtn.modelData.monochromeIcon === true ? materialIconComp : iconImageComp

                                        Component {
                                            id: materialIconComp
                                            MaterialSymbol {
                                                text: menuBtn.modelData.iconName ?? ""
                                                iconSize: Appearance.font.pixelSize.normal
                                                color: Appearance.colors.colOnSurface
                                            }
                                        }

                                        Component {
                                            id: iconImageComp
                                            IconImage {
                                                source: Quickshell.iconPath(menuBtn.modelData.iconName ?? "", "application-x-executable")
                                                implicitSize: Appearance.font.pixelSize.normal
                                            }
                                        }
                                    }

                                    StyledText {
                                        text: menuBtn.modelData.text ?? ""
                                        color: Appearance.colors.colOnSurface
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }


        HoverHandler {
            id: popupHoverHandler
            onHoveredChanged: {
                if (hovered && popupWindow.entranceSettled)
                    popupWindow.popupWasHovered = true
            }
        }
        readonly property bool popupContainsMouse: popupHoverHandler.hovered

    }
}
