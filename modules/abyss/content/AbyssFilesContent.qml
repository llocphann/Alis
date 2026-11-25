import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss

Item {
    id: root
    property var participant: null
    property string outputName: ""
    property bool _everActivated: false
    property string _loadedTargetSource: ""
    readonly property bool _participantActive: Boolean(participant && (participant.open || (participant.progress ?? 0) > 0.001))
    readonly property bool _warmupRequested: Boolean(participant?.backgroundPreload)
    readonly property bool _hostOwnsLoadingSurface: Boolean(participant?.showLoadingSurface)
    readonly property bool contentReady: _hostOwnsLoadingSurface
        ? (workspaceLoader.status === Loader.Ready || (!_participantActive && !_warmupRequested))
        : (!_warmupRequested || _participantActive || workspaceLoader.status === Loader.Ready)
    readonly property string _targetSource: AlisIntergration.alisFilesEnabled ? AlisIntergration.alisFilesWorkspaceSource() : ""

    function _syncWorkspaceSource(): void {
        if ((root._participantActive || root._warmupRequested) && root._targetSource.length > 0)
            root._everActivated = true
        if (!AlisIntergration.alisFilesEnabled || root._targetSource.length === 0) {
            root._everActivated = false
            root._loadedTargetSource = ""
            if (workspaceLoader.source.toString().length > 0)
                workspaceLoader.source = ""
            return
        }
        if (!root._everActivated)
            return
        if (root._loadedTargetSource !== root._targetSource || workspaceLoader.status === Loader.Null) {
            root._loadedTargetSource = root._targetSource
            const settledNow = Boolean(root.participant ? (root.participant.open && Math.abs((root.participant.progress ?? 1) - 1) < 0.02) : true)
            workspaceLoader.setSource(root._targetSource, {
                embeddedSurface: true,
                transitionSettled: settledNow
            })
        }
    }

    Component.onCompleted: root._syncWorkspaceSource()
    onParticipantChanged: root._syncWorkspaceSource()
    on_ParticipantActiveChanged: root._syncWorkspaceSource()
    on_WarmupRequestedChanged: root._syncWorkspaceSource()
    on_TargetSourceChanged: root._syncWorkspaceSource()

    function handleEscape(): bool {
        if (workspaceLoader.item && typeof workspaceLoader.item.handleEscape === "function")
            return Boolean(workspaceLoader.item.handleEscape())
        return false
    }

    function focusPrimarySurface(): void {
        if (workspaceLoader.item) {
            if (typeof workspaceLoader.item.focusPrimarySurface === "function")
                workspaceLoader.item.focusPrimarySurface()
            else
                workspaceLoader.item.forceActiveFocus()
        }
    }

    function forwardKeyEvent(event): bool {
        if (workspaceLoader.item && typeof workspaceLoader.item.forwardKeyEvent === "function")
            return Boolean(workspaceLoader.item.forwardKeyEvent(event))
        return false
    }

    Connections {
        target: root.participant && typeof root.participant === "object" && root.participant.objectName !== undefined ? root.participant : null
        ignoreUnknownSignals: true
        function onOpenChanged() {
            if (root.participant?.open) {
                root.focusPrimarySurface()
                Qt.callLater(() => root.focusPrimarySurface())
            }
        }
    }

    Loader {
        id: workspaceLoader
        anchors.fill: parent
        visible: root._participantActive
        asynchronous: (Quickshell.env("QT_QUICK_BACKEND") !== "software") && status !== Loader.Ready
        onLoaded: {
            if (item) {
                item.files = Qt.binding(() => AlisIntergration.alisFiles)
                item.visible = Qt.binding(() => Boolean(root.participant ? (root.participant.open || (root.participant.progress ?? 0) > 0.001) : true))
                if (item.embeddedSurface !== undefined)
                    item.embeddedSurface = true
                if (item.bottomDocked !== undefined)
                    item.bottomDocked = Qt.binding(() => (root.participant?.edge ?? "bottom") === "bottom")
                if (item.transitionSettled !== undefined)
                    item.transitionSettled = Qt.binding(() => Boolean(root.participant ? (root.participant.open && Math.abs((root.participant.progress ?? 1) - 1) < 0.02) : true))
                if (root.participant?.open) {
                    root.focusPrimarySurface()
                    Qt.callLater(() => root.focusPrimarySurface())
                }
            }
        }
    }

    AlisLoadingScreen {
        objectName: "filesWorkspaceLoadingScreen"
        anchors.fill: parent
        z: 30
        loading: root._participantActive && !root._hostOwnsLoadingSurface && workspaceLoader.status !== Loader.Ready
        title: Translation.tr("Files")
        icon: "folder_open"
        fillSurface: false
    }
}
