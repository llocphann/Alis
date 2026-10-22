import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property bool _presentedOpen: false
    property bool _contentPresented: GlobalStates.dashboardOpen
    property bool _renderUpdatesNeeded: GlobalStates.dashboardOpen

    function beginPresentation(): void {
        _hideContentTimer.stop()
        _renderSuspendTimer.stop()
        root._renderUpdatesNeeded = true
        root._contentPresented = true
        root._presentedOpen = false

        if (!Appearance.animationsEnabled) {
            root._presentedOpen = true
            return
        }

        // The Dashboard window itself stays mapped after first use. Paint one
        // real closed frame at dashboardOffset before entering the open state,
        // so the only visible entrance is the immutable slide transition.
        _presentationTimer.restart()
    }

    function beginDismissal(): void {
        _presentationTimer.stop()
        root._presentedOpen = false

        if (!Appearance.animationsEnabled) {
            root._contentPresented = false
            root._renderUpdatesNeeded = false
            return
        }

        _hideContentTimer.restart()
        _renderSuspendTimer.restart()
    }

    readonly property real screenWidth: panelRoot.screen?.width ?? 1920
    readonly property real screenHeight: panelRoot.screen?.height ?? 1080
    readonly property real safePadding: Math.max(
        Appearance.sizes.hyprlandGapsOut * 2,
        Math.round(Math.min(screenWidth, screenHeight) * 0.02)
    )
    readonly property real barReservedSpace: Appearance.sizes.baseBarHeight + Appearance.sizes.hyprlandGapsOut * 2
    readonly property real topReservedSpace: safePadding
        + (!(Config.options?.bar?.bottom ?? false) ? barReservedSpace : 0)
    readonly property real bottomReservedSpace: safePadding
        + ((Config.options?.bar?.bottom ?? false) ? barReservedSpace : 0)
    readonly property real availablePanelHeight: Math.max(360, screenHeight - topReservedSpace - bottomReservedSpace)
    readonly property real availablePanelWidth: Math.max(480, screenWidth - safePadding * 2)
    readonly property real widthRatio: Math.min(0.9, Math.max(0.4, Config.options?.dashboard?.widthRatio ?? 0.72))
    readonly property real heightRatio: Math.min(0.9, Math.max(0.45, Config.options?.dashboard?.heightRatio ?? 0.72))
    readonly property real panelWidth: Math.round(Math.min(availablePanelWidth, screenWidth * widthRatio))
    readonly property real panelHeight: Math.round(Math.min(availablePanelHeight, screenHeight * heightRatio))

    PanelWindow {
        id: panelRoot

        Component.onCompleted: {
            if (GlobalStates.dashboardOpen)
                root.beginPresentation()
        }

        Connections {
            target: GlobalStates
            function onDashboardOpenChanged() {
                if (GlobalStates.dashboardOpen)
                    root.beginPresentation()
                else
                    root.beginDismissal()
            }
        }

        Timer {
            id: _presentationTimer
            interval: 16
            repeat: false
            onTriggered: {
                if (GlobalStates.dashboardOpen)
                    root._presentedOpen = true
            }
        }

        Timer {
            id: _hideContentTimer
            interval: SurfaceMotion.dashboardExitDuration + 16
            repeat: false
            onTriggered: {
                if (!GlobalStates.dashboardOpen)
                    root._contentPresented = false
            }
        }

        Timer {
            id: _renderSuspendTimer
            interval: SurfaceMotion.dashboardExitDuration + 16
            repeat: false
            onTriggered: {
                if (!GlobalStates.dashboardOpen)
                    root._renderUpdatesNeeded = false
            }
        }

        function hide() {
            GlobalStates.dashboardOpen = false
        }

        exclusiveZone: 0
        implicitWidth: screen?.width ?? 1920
        implicitHeight: screen?.height ?? 1080
        WlrLayershell.namespace: "quickshell:dashboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.dashboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"
        // Keep the native layer-shell surface mapped after first use. Mapping
        // and unmapping a fullscreen Overlay lets the compositor substitute its
        // own map effect, which visually masked the Dashboard slide.
        visible: true
        updatesEnabled: root._renderUpdatesNeeded

        anchors {
            top: true
            right: true
            bottom: true
            left: true
        }

        CompositorFocusGrab {
            id: grab
            windows: [ panelRoot ]
            active: CompositorService.isHyprland
                && GlobalStates.dashboardOpen && panelRoot.visible
            onCleared: () => {
                if (!active) panelRoot.hide()
            }
        }

        Item {
            id: dashboardInputArea
            anchors.fill: parent
        }

        Item {
            id: emptyDashboardInputArea
            width: 0
            height: 0
        }

        Region {
            id: dashboardInputRegion
            item: GlobalStates.dashboardOpen
                ? dashboardInputArea : emptyDashboardInputArea
        }

        mask: dashboardInputRegion

        // The window itself owns one Edit-mode Escape shortcut. Controls and
        // cards may steal QQuickItem activeFocus from the content Loader.
        Shortcut {
            sequences: ["Escape"]
            context: Qt.WindowShortcut
            autoRepeat: false
            enabled: GlobalStates.dashboardOpen
                && (contentLoader.item?.editMode ?? false)
            onActivated: {
                if (contentLoader.item?.handleEscape()) {
                    contentLoader.forceActiveFocus()
                    console.info("[DashboardEscape] edit canceled; surface=standalone")
                }
            }
            onActivatedAmbiguously: console.warn(
                "[DashboardEscape] ambiguous Escape shortcut in standalone window")
        }

        // Backdrop click to close
        MouseArea {
            anchors.fill: parent
            enabled: GlobalStates.dashboardOpen
            onClicked: mouse => {
                const localPos = mapToItem(contentLoader, mouse.x, mouse.y)
                if (localPos.x < 0 || localPos.x > contentLoader.width
                        || localPos.y < 0 || localPos.y > contentLoader.height) {
                    panelRoot.hide()
                }
            }
        }

        Loader {
            id: contentLoader
            // The outer iiDashboard loader is retained after first use. Keep
            // the widget tree mounted and hide only its paint after the exit
            // slide so long-idle reopens reuse the same live component state.
            active: true
            visible: root._contentPresented

            // Keep the top-level Dashboard out of an extra FBO during motion.
            // Media artwork already owns nested mask/effect layers; wrapping the
            // whole Dashboard in another transient layer can snapshot partially
            // resolved artwork and produce a cyan/blank flash during the slide.
            layer.enabled: Appearance.shouldDesaturate("overlays")
                && contentLoader.visible
            layer.effect: ShellDesaturationEffect {}

            property real panelTranslateY: SurfaceMotion.dashboardOffset
            states: [
                State {
                    name: "open"
                    when: root._presentedOpen
                    PropertyChanges {
                        target: contentLoader
                        panelTranslateY: 0
                    }
                },
                State {
                    name: "closed"
                    when: !root._presentedOpen
                    PropertyChanges {
                        target: contentLoader
                        panelTranslateY: SurfaceMotion.dashboardOffset
                    }
                }
            ]
            transitions: [
                Transition {
                    to: "open"
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        target: contentLoader
                        property: "panelTranslateY"
                        duration: SurfaceMotion.dashboardEnterDuration
                        easing.type: SurfaceMotion.dashboardEnterEasingType
                    }
                },
                Transition {
                    to: "closed"
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        target: contentLoader
                        property: "panelTranslateY"
                        duration: SurfaceMotion.dashboardExitDuration
                        easing.type: SurfaceMotion.dashboardExitEasingType
                    }
                }
            ]

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round((root.topReservedSpace - root.bottomReservedSpace) / 2)

            width: root.panelWidth
            readonly property real editToolbarReserve:
                ((item?.editMode ?? false) || (item?.tabNamingActive ?? false))
                    ? Math.max(0, Number(item?.editToolbarHeight ?? 0) - 1)
                    : 0
            height: Math.min(root.availablePanelHeight,
                root.panelHeight + contentLoader.editToolbarReserve)

            opacity: 1
            scale: 1
            transform: Translate { y: contentLoader.panelTranslateY }

            focus: GlobalStates.dashboardOpen
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    if (!contentLoader.item?.handleEscape())
                        panelRoot.hide()
                    event.accepted = true
                }
            }

            sourceComponent: Item {
                id: standaloneDashboardHost

                property alias editMode: standaloneContent.editMode
                readonly property bool tabNamingActive: standaloneContent.tabNamingActive
                function handleEscape(): bool {
                    return standaloneContent.handleEscape()
                }
                readonly property real editToolbarHeight:
                    standaloneEditToolbar.implicitHeight

                DashboardContent {
                    id: standaloneContent
                    // Keep media/equalizer presentation alive through the full
                    // exit slide; _contentPresented drops only after the card is
                    // no longer visible.
                    presentationActive: root._contentPresented
                    x: 0
                    y: standaloneEditToolbar.visible
                        ? Math.max(0, standaloneEditToolbar.height - 1)
                        : 0
                    width: parent.width
                    height: Math.max(0, parent.height - y)
                    screenWidth: panelRoot.screen?.width ?? 1920
                    screenHeight: panelRoot.screen?.height ?? 1080
                }

                DashboardEditToolbar {
                    id: standaloneEditToolbar
                    z: 8
                    canvasController: standaloneContent.canvasController
                    tabController: standaloneContent
                    width: Math.min(
                        standaloneEditToolbar.implicitWidth,
                        Math.max(1, standaloneContent.width - 32))
                    x: Math.round((parent.width - width) / 2)
                    y: 0
                }
            }
        }
    }

}
