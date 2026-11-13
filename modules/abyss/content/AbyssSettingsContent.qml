import QtQuick
import QtQuick.Window
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.modules.abyss
import qs.modules.abyss.looks

// The mature rail/card is reparented here; no second settings page tree.
Item {
    id: root
    property var participant: null
    property string outputName: ""
    readonly property bool editMode: SettingsLayoutManager.editMode
    readonly property Item stageDockParent: root.participant?.hostWindow?.stageSettingsDockHost ?? null
    readonly property bool stageHosted: stageDockParent !== null
    readonly property real topControlReserve: 0
    readonly property real bottomControlReserve: root.stageHosted ? 0 : (editor.desiredHeight + 16)
    readonly property real editDockWidth: editor.desiredWidth
    readonly property real editDockHeight: editor.desiredHeight
    readonly property Item currentPage: settings.pageHost?.currentItem ?? null
    property bool _firstPageSettled: false
    readonly property bool _rawPageReady: Boolean(settings.pageHost && !settings.pageHost.loading)
    on_RawPageReadyChanged: if (_rawPageReady) _firstPageSettled = true
    Component.onCompleted: if (_rawPageReady) _firstPageSettled = true
    readonly property bool contentReady: _firstPageSettled || _rawPageReady
    function handleEscape(): bool {
        return settings.handleEscape()
    }
    SettingsOverlay {
        id: settings
        embeddedHost: root
    }

    // Reparent only the controls into the existing output field; the Settings
    // canvas retains its full dimensions and object identity throughout editing.
    Item {
        id: editor
        parent: root.stageHosted ? root.stageDockParent : (root.participant?.parent ?? null)
        objectName: "abyssSettingsEditPopup"
        readonly property var body: root.participant
        z: 90
        readonly property real desiredWidth: Math.min(
            1040 * Appearance.fontSizeScale,
            Math.max(680, toolbar.implicitWidth))
        readonly property real desiredHeight: toolbar.implicitHeight
        readonly property bool controlsVisible: SettingsLayoutManager.editMode
        readonly property var contentRect: root.participant?.targetRecord?.content
        readonly property bool revealRequested: controlsVisible
            && (root.stageHosted ? (root.participant?.open ?? false)
                : ((root.participant?.presented ?? false) && (root.participant?.progress ?? 0) > 0.99))
        property real revealProgress: revealRequested ? 1 : 0
        readonly property real bottomEdgeThickness: Math.max(0, Number(
            root.participant?.controller?.edgeInsets?.bottom
            ?? root.participant?.edgeInsets?.bottom
            ?? AbyssStyle.perimeterThickness))
        readonly property real targetWidth: Math.min(toolbar.implicitWidth,
            (contentRect?.width ?? 0) > 0 ? Math.round(contentRect.width * 0.80) : toolbar.implicitWidth,
            (parent?.width ?? 0) > 24 ? Math.round((parent.width - 24) * 0.80) : toolbar.implicitWidth)
        readonly property rect targetRect: Qt.rect(
            Math.max(12, Math.min((parent?.width ?? 0) - targetWidth - 12,
                (contentRect?.x ?? 0) + ((contentRect?.width ?? 0) - targetWidth) / 2)),
            Math.max(8, (parent?.height ?? 0) - bottomEdgeThickness - desiredHeight),
            targetWidth, desiredHeight)
        property var retainedRect: null
        readonly property rect presentationRect: revealRequested
            ? targetRect : (retainedRect ?? targetRect)
        function rememberRequestedRect(): void {
            if (SettingsLayoutManager.editMode && editor.revealRequested)
                editor.retainedRect = editor.targetRect
        }
        onTargetRectChanged: editor.rememberRequestedRect()
        onRevealRequestedChanged: if (revealRequested) editor.rememberRequestedRect()
        x: root.stageHosted ? 0 : presentationRect.x
        y: root.stageHosted ? 0 : presentationRect.y
        width: root.stageHosted ? (root.stageDockParent?.width ?? toolbar.implicitWidth) : presentationRect.width
        height: root.stageHosted ? (root.stageDockParent?.height ?? desiredHeight) : presentationRect.height
        readonly property real slideOffset: root.stageHosted ? 0 : (height + 16) * (1 - revealProgress)
        readonly property real revealedHeight: height
        visible: root.stageHosted
            ? (revealRequested || (root.stageDockParent?.visible ?? false))
            : (revealProgress > 0)
        enabled: revealRequested && visible && (root.participant?.acceptsInput ?? false)
        readonly property rect toolbarInputBounds: (!root.stageHosted && editor.enabled)
            ? Qt.rect(editor.x, editor.y + editor.slideOffset,
                editor.width, editor.revealedHeight)
            : Qt.rect(0, 0, 0, 0)
        readonly property Region toolbarInputRegion: Region {
            x: Math.floor(editor.toolbarInputBounds.x)
            y: Math.floor(editor.toolbarInputBounds.y)
            width: editor.toolbarInputBounds.width > 0
                ? Math.ceil(editor.toolbarInputBounds.x + editor.toolbarInputBounds.width) - x : 0
            height: editor.toolbarInputBounds.height > 0
                ? Math.ceil(editor.toolbarInputBounds.y + editor.toolbarInputBounds.height) - y : 0
        }
        clip: true
        Behavior on revealProgress {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: SurfaceMotion.duration
                easing.type: SurfaceMotion.easingType
            }
        }
        AbyssParticipant {
            identity: (root.participant?.identity ?? "settings") + "Editor"
            controller: root.participant?.controller ?? null
            geometry: (!root.stageHosted && editor.visible) ? ({edge: "bottom",
                surface: {x: editor.x - 8, y: editor.y + editor.slideOffset - 8,
                    width: editor.width + 16,
                    height: editor.revealedHeight + 8 + editor.bottomEdgeThickness + 50},
                content: {x: editor.x, y: editor.y + editor.slideOffset,
                    width: editor.width, height: editor.revealedHeight},
                along: editor.x, span: editor.width, depth: editor.revealedHeight,
                progress: editor.revealProgress}) : null
            surfaceSettled: editor.revealRequested && editor.revealProgress === 1
            inputBounds: editor.toolbarInputBounds
            nativeInputRegion: editor.toolbarInputRegion
        }
        SettingsEditToolbar {
            id: toolbar
            width: editor.width
            height: editor.height
            y: editor.slideOffset
            visible: editor.visible
            embeddedSurface: true
            targetPage: root.currentPage
        }
    }
}
