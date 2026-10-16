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
    // Desktop click menus can use fade-only presentation and animated re-anchoring.
    property bool fadeOnly: false
    property int fadeInDuration: 130
    property int fadeOutDuration: 90

    // A mapped xdg-popup cannot always be re-anchored on Niri. Queue the
    // latest click and recreate exactly one native popup after fading out.
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
        if (root.active && root.item && root.fadeOnly) {
            root.relocationQueued = true
            root.relocationX = nextX
            root.relocationY = nextY
            root.relocationModel = newModel
            root.relocationModelProvided = newModel !== undefined
            if (Appearance.animationsEnabled)
                root.item.fadeForRelocation()
            else
                root.commitRelocation()
            return
        }
        if (newModel !== undefined)
            root.model = newModel
        root.anchorItem.x = nextX
        root.anchorItem.y = nextY
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
        visible: true
        grabFocus: root.keyboardGrab && CompositorService.isNiri
        property bool closing: false
        property real relocationOpacity: 1
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
            realContent.shown = true;
            Qt.callLater(() => keyHandler.forceActiveFocus());
            if (root.fadeOnly) {
                // Skip the shared slide/scale presentation for desktop menus.
                popupWindow.sourceEdgeMargin = popupWindow.settledMargin;
                popupWindow.entranceSettled = true;
                popupWindow.relocationOpacity = Appearance.animationsEnabled ? 0 : 1;
                if (Appearance.animationsEnabled)
                    fadeOnlyOpenAnim.start();
            } else {
                openAnim.start();
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
            item: root.anchorItem
            rect.x: Number(root.anchorRect?.x ?? 0)
            rect.y: Number(root.anchorRect?.y ?? 0)
            rect.width: Number(root.anchorRect?.width ?? (root.anchorItem?.width ?? 0))
            rect.height: Number(root.anchorRect?.height ?? (root.anchorItem?.height ?? 0))
            gravity: root.popupSide !== 0
                ? root.popupSide
                : (root.popupAbove ? Edges.Top : Edges.Bottom)
            edges: root.popupSide !== 0
                ? root.popupSide
                : (root.popupAbove ? Edges.Top : Edges.Bottom)
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
            } else if (root.fadeOnly) {
                fadeOnlyOpenAnim.stop();
                relocationAnim.stop();
                popupWindow.closing = true;
                fadeOnlyCloseAnim.restart();
            } else {
                popupWindow.closing = true;
                realContent.shown = false;
                closeAnim.start();
            }
        }

        function fadeForRelocation(): void {
            fadeOnlyOpenAnim.stop();
            fadeOnlyCloseAnim.stop();
            relocationAnim.stop();
            popupWindow.closing = false;
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
            duration: Appearance.animation.elementMoveEnter.duration
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
                duration: Appearance.animation.elementMoveExit.duration
                easing.type: Appearance.animation.elementMoveExit.type
                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
            }
            ScriptAction {
                script: root.active = false
            }
        }

        NumberAnimation {
            id: fadeOnlyOpenAnim
            target: popupWindow
            property: "relocationOpacity"
            to: 1
            duration: root.fadeInDuration
            easing.type: Easing.OutCubic
        }
        SequentialAnimation {
            id: fadeOnlyCloseAnim
            NumberAnimation {
                target: popupWindow
                property: "relocationOpacity"
                to: 0
                duration: root.fadeOutDuration
                easing.type: Easing.OutQuad
            }
            ScriptAction { script: root.active = false }
        }
        SequentialAnimation {
            id: relocationAnim
            NumberAnimation {
                target: popupWindow
                property: "relocationOpacity"
                to: 0
                duration: root.fadeOutDuration
                easing.type: Easing.OutQuad
            }
            ScriptAction { script: root.commitRelocation() }
        }

        color: "transparent"

        // Fade the menu and its shadow together, without altering shared
        // PopupWindow input, anchoring or the normal menu presentation.
        Item {
            id: fadeLayer
            anchors.fill: parent
            opacity: popupWindow.relocationOpacity

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
                opacity: root.fadeOnly ? 1 : (Appearance.motion.popupReveal.enableFade ? (shown ? 1 : 0) : 1)
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
                    enabled: Appearance.animationsEnabled
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
