pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    property string text: ""
    property font font
    property bool extraVisibleCondition: true
    // Mouse clicks commonly leave Controls with activeFocus. Using activeFocus
    // here made a hover tooltip survive after the pointer left. visualFocus is
    // keyboard-origin focus only, which is the accessibility behavior wanted.
    readonly property bool parentKeyboardFocusState: {
        if (!parent)
            return false
        if (parent.visualFocus !== undefined)
            return parent.visualFocus
        if (parent.focusReason !== undefined) {
            return parent.activeFocus
                && (parent.focusReason === Qt.TabFocusReason
                    || parent.focusReason === Qt.BacktabFocusReason
                    || parent.focusReason === Qt.ShortcutFocusReason)
        }
        return false
    }
    property bool alternativeVisibleCondition: root.parentKeyboardFocusState
    property int delay: 16
    property real horizontalPadding: 10
    property real verticalPadding: 5
    property real horizontalMargin: horizontalPadding
    property real verticalMargin: verticalPadding

    function setContentShown(shown: bool): void {
        if (root.contentItem && root.contentItem.shown !== undefined)
            root.contentItem.shown = shown
    }
    
    function updateAnchor(): void {
        tooltipLoader.item?.anchor?.updateAnchor()
    }

    // Do not bind Loader.active directly to Item.visible. Effective Item
    // visibility can itself change while the presentation is materialized or
    // reparented, which lets QML form an active <-> visibility dependency
    // cycle. Lifecycle signals drive the lazy Loader imperatively instead.
    function syncPresentation(): void {
        const shouldBeActive = root.visible && root.internalVisibleCondition
        if (tooltipLoader.active !== shouldBeActive)
            tooltipLoader.active = shouldBeActive
        if (_anchorRefreshTimer.running !== shouldBeActive)
            _anchorRefreshTimer.running = shouldBeActive
    }

    // PopupAnchor item geometry is sampled only when a PopupWindow is shown.
    // Keep a tiny revision heartbeat while a tooltip is live so both the
    // PopupWindow anchor and the ApplicationWindow fallback follow moving
    // layout/animation anchors instead of leaving detached stale popups.
    property int anchorRevision: 0

    // Some tooltip parents are plain Items, not Controls or MouseAreas.
    // Never treat an unknown hover state as hovered: that made the tooltip
    // permanently visible as soon as the item had non-empty text.
    // Callers with an explicit external hover source may opt out and supply
    // extraVisibleCondition instead (e.g. a compact tile's child MouseArea).
    property bool useParentHover: true
    // Explicit MouseArea-backed anchors can supply their own hover/press truth.
    // Defaulting external hover to the existing condition preserves callers
    // that already opt out of parent-hover introspection.
    property bool externalHoverState: root.extraVisibleCondition
    property bool externalPressedState: false
    readonly property bool parentHoverState: {
        if (!root.useParentHover)
            return root.externalHoverState
        if (!parent)
            return false
        if (parent.buttonHovered !== undefined)
            return parent.buttonHovered
        if (parent.hovered !== undefined)
            return parent.hovered
        if (parent.containsMouse !== undefined)
            return parent.containsMouse
        return false
    }
    readonly property bool parentPressedState: {
        if (root.externalPressedState)
            return true
        if (!parent)
            return false
        if (parent.down !== undefined)
            return parent.down
        if (parent.pressed !== undefined)
            return parent.pressed
        return false
    }
    // A click can move/collapse the anchor while Qt still reports the old
    // hover state for a frame (or until the pointer moves). Keep that tooltip
    // closed until the pointer genuinely leaves the control.
    property bool suppressUntilHoverExit: false
    readonly property bool parentVisibleState:
        parent ? parent.visible : false
    readonly property bool hasContent: root.text.trim().length > 0
    readonly property bool internalVisibleCondition: root.enabled && root.hasContent
        && root.parentVisibleState
        && !root.suppressUntilHoverExit && !root.parentPressedState
        && ((extraVisibleCondition && parentHoverState) || alternativeVisibleCondition)

    onParentPressedStateChanged: {
        if (!root.parentPressedState)
            return
        // Keyboard activation without pointer hover must not permanently
        // suppress focus-driven tooltips.
        root.suppressUntilHoverExit = root.parentHoverState
        _showDelayTimer.stop()
        root.setContentShown(false)
    }
    onParentHoverStateChanged: {
        if (!root.parentHoverState)
            root.suppressUntilHoverExit = false
    }
    // Cancel delayed show on every hide path, not only Loader deactivation.
    // This also covers a parent becoming hidden or a component being unloaded.
    onInternalVisibleConditionChanged: {
        if (!root.internalVisibleCondition) {
            _showDelayTimer.stop()
            root.setContentShown(false)
        }
        root.syncPresentation()
    }
    onVisibleChanged: {
        if (!root.visible) {
            root.suppressUntilHoverExit = root.parentHoverState
            _showDelayTimer.stop()
            root.setContentShown(false)
        }
        root.syncPresentation()
    }
    property bool _anchorInitialized: false
    Component.onCompleted: {
        root._anchorInitialized = true
        Qt.callLater(root.syncPresentation)
    }
    onParentChanged: {
        if (!root._anchorInitialized)
            return
        root.suppressUntilHoverExit = root.parentHoverState
        root.anchorRevision += 1
        _showDelayTimer.stop()
        root.setContentShown(false)
        Qt.callLater(root.syncPresentation)
    }

    property var anchorEdges: Edges.Top
    property var anchorGravity: anchorEdges

    property Item contentItem: StyledToolTipContent {
        id: contentItem
        anchors.centerIn: parent
        text: root.text
        shown: false
        position: root.anchorEdges === Edges.Top ? "top"
                : root.anchorEdges === Edges.Left ? "left"
                : root.anchorEdges === Edges.Right ? "right"
                : "bottom"
        horizontalPadding: root.horizontalPadding
        verticalPadding: root.verticalPadding
    }

    // Whether we can use PopupWindow (requires QsWindow, i.e. PanelWindow context)
    readonly property bool _canUsePopupWindow: root.QsWindow.window !== null

    Timer {
        id: _showDelayTimer
        interval: root.delay
        onTriggered: {
            if (root.visible && root.internalVisibleCondition)
                root.setContentShown(true)
        }
    }

    Timer {
        id: _anchorRefreshTimer
        interval: 50
        repeat: true
        onTriggered: {
            root.anchorRevision += 1
            if (tooltipLoader.active)
                root.updateAnchor()
        }
    }

    // One Loader owns both presentation paths. Its active state follows only
    // tooltip lifecycle; window association selects the loaded component.
    Loader {
        id: tooltipLoader
        anchors.fill: parent
        active: false
        sourceComponent: root._canUsePopupWindow
            ? popupWindowPresentation : fallbackItemPresentation

        onLoaded: {
            root.setContentShown(false)
            _showDelayTimer.restart()
        }
        onActiveChanged: {
            if (!active) {
                _showDelayTimer.stop()
                root.setContentShown(false)
            }
        }
    }

    Component {
        id: popupWindowPresentation
        PopupWindow {
            visible: true
            readonly property real _gap: 4
            anchor {
                window: root.QsWindow.window
                item: root.parent
                rect.x: root.anchorEdges === Edges.Left ? -_gap : 0
                rect.y: root.anchorEdges === Edges.Top ? -_gap : 0
                rect.width: (root.parent?.width ?? 0)
                    + ((root.anchorEdges === Edges.Left
                        || root.anchorEdges === Edges.Right) ? _gap : 0)
                rect.height: (root.parent?.height ?? 0)
                    + ((root.anchorEdges === Edges.Top
                        || root.anchorEdges === Edges.Bottom) ? _gap : 0)
                edges: root.anchorEdges
                gravity: root.anchorGravity
            }
            mask: Region { item: null }
            color: "transparent"
            implicitWidth: root.contentItem.implicitWidth
                + root.horizontalMargin * 2
            implicitHeight: root.contentItem.implicitHeight
                + root.verticalMargin * 2
            data: [root.contentItem]
        }
    }

    Component {
        id: fallbackItemPresentation
        Item {
            id: fallbackItem
            parent: root.Window.window?.contentItem ?? root.parent ?? root
            z: 1000

            readonly property real tooltipW:
                root.contentItem.implicitWidth + root.horizontalMargin * 2
            readonly property real tooltipH:
                root.contentItem.implicitHeight + root.verticalMargin * 2
            width: tooltipW
            height: tooltipH

            readonly property Item anchorItem: root.parent
            readonly property point anchorPos: {
                const revision = root.anchorRevision
                if (!anchorItem || !fallbackItem.parent)
                    return Qt.point(0, 0)
                return anchorItem.mapToItem(fallbackItem.parent, 0, 0)
            }
            readonly property real gap: 4
            readonly property real viewportMargin: 6
            readonly property real preferredX: {
                const edges = root.anchorEdges
                if (edges === Edges.Left)
                    return anchorPos.x - tooltipW - gap
                if (edges === Edges.Right)
                    return anchorPos.x + (anchorItem?.width ?? 0) + gap
                return anchorPos.x
                    + ((anchorItem?.width ?? 0) - tooltipW) / 2
            }
            readonly property real preferredY: {
                const edges = root.anchorEdges
                if (edges === Edges.Top)
                    return anchorPos.y - tooltipH - gap
                if (edges === Edges.Bottom)
                    return anchorPos.y + (anchorItem?.height ?? 0) + gap
                return anchorPos.y
                    + ((anchorItem?.height ?? 0) - tooltipH) / 2
            }

            x: Math.max(viewportMargin, Math.min(preferredX,
                Math.max(viewportMargin,
                    (parent?.width ?? tooltipW) - tooltipW - viewportMargin)))
            y: Math.max(viewportMargin, Math.min(preferredY,
                Math.max(viewportMargin,
                    (parent?.height ?? tooltipH) - tooltipH - viewportMargin)))
            data: [root.contentItem]
        }
    }

}
