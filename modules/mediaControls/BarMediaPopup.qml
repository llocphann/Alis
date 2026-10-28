pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.common.models
import qs.services
import "root:"

Item {
    id: root
    signal closeRequested()

    Keys.onPressed: event => {
        if (event.key !== Qt.Key_Escape) return
        root.closeRequested()
        event.accepted = true
    }

    readonly property MprisPlayer activePlayer: MprisController.activePlayer
    // Use MprisController.displayPlayers - centralized filtering
    readonly property var meaningfulPlayers: MprisController.displayPlayers
    readonly property real widgetWidth: Appearance.sizes.mediaControlsWidth
    readonly property real widgetHeight: Appearance.sizes.mediaControlsHeight
    // The connected Bar popup has a tighter horizontal budget than the global
    // MediaControls surface. Keep compaction local to this owner so Sidebar,
    // Dashboard and standalone media surfaces retain their existing density.
    readonly property bool compactLayout: true
    property real popupRounding: Appearance.rounding.normal
    property real screenX: 0
    property real screenY: 0
    // Media sources are compact tabs: one PlayerControl is presented at a time,
    // with the same right-rail dot language used by Weather Popup.
    property int currentTab: 0
    readonly property int tabCount: root._visiblePlayers.length
    readonly property int tabSlideDuration: Appearance.animation.elementMove.duration
    
    // MprisController already owns membership debouncing/grace. Do not keep a
    // second cache of MprisPlayer QObject references here: an MPRIS service can
    // disappear/reappear while the popup stays open, leaving the local cache
    // pointing at destroyed QObjects. That kept the viewport height reserved
    // while Repeater had no valid PlayerControl delegate (the blank-media bug).
    // Use only live controller objects, and keep the live active player visible
    // through a transient display-filter update.
    readonly property var _visiblePlayers: {
        const result = []
        const players = root.meaningfulPlayers ?? []
        for (let i = 0; i < players.length; ++i) {
            const player = players[i]
            if (player && !result.includes(player))
                result.push(player)
        }
        if (root.activePlayer && !result.includes(root.activePlayer))
            result.unshift(root.activePlayer)
        return result
    }
    // Item.visible alone is insufficient for popout lifecycle: an item's local
    // visible flag can remain true while its presentation window is closed.
    // The popup no longer owns a decorative CAVA consumer; this state now gates
    // only the EqualizerPanel, whose integrated analyzer is the single live
    // spectrum shown on this surface.
    property bool presentationActive: root.QsWindow.window?.visible ?? false

    function _samePlayerOrder(a, b): bool {
        if ((a?.length ?? 0) !== (b?.length ?? 0)) return false
        for (let i = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false
        }
        return true
    }

    function playerLabel(player): string {
        const title = StringUtils.cleanMusicTitle(player?.trackTitle) || ""
        const artist = player?.trackArtist ?? ""
        if (title.length > 0 && artist.length > 0)
            return `${title} — ${artist}`
        return title || artist || player?.dbusName
            || Translation.tr("Unknown player")
    }

    function syncCurrentTabToActivePlayer(): void {
        const count = root.tabCount
        if (count <= 0) {
            root.currentTab = 0
            return
        }
        const activeIndex = root._visiblePlayers.indexOf(root.activePlayer)
        if (activeIndex >= 0) {
            root.currentTab = activeIndex
            return
        }
        root.currentTab = Math.max(0, Math.min(root.currentTab, count - 1))
    }

    function selectTab(index): void {
        const count = root.tabCount
        if (count <= 0)
            return
        const nextIndex = Math.max(0, Math.min(count - 1, index))
        root.currentTab = nextIndex
        const player = root._visiblePlayers[nextIndex] ?? null
        if (player && player !== root.activePlayer)
            MprisController.setActivePlayer(player)
    }

    function focusInitialControl(): bool {
        const current = playerRepeater.itemAt(root.currentTab)
        if (current) {
            current.focusPrimaryControl()
            return true
        }
        const fallback = playerRepeater.itemAt(0)
        if (fallback) {
            fallback.focusPrimaryControl()
            return true
        }
        return false
    }

    // An owned timer is cancelled with the popup. A queued closure could outlive
    // the content during a family switch or an output/body unload.
    Timer {
        id: tabSyncTimer
        interval: 0
        onTriggered: root.syncCurrentTabToActivePlayer()
    }
    onMeaningfulPlayersChanged: tabSyncTimer.restart()
    onActivePlayerChanged: tabSyncTimer.restart()
    Component.onCompleted: tabSyncTimer.restart()

    implicitWidth: widgetWidth
    implicitHeight: playerColumn.implicitHeight

    ColumnLayout {
        id: playerColumn
        anchors.fill: parent
        spacing: root.compactLayout ? 6 : 8

        Item {
            id: playerViewport
            Layout.fillWidth: true
            Layout.preferredHeight: root.tabCount > 0 ? root.widgetHeight : 0
            implicitWidth: root.widgetWidth
            implicitHeight: Layout.preferredHeight
            visible: root.tabCount > 0
            clip: true

            Repeater {
                id: playerRepeater
                model: ScriptModel {
                    values: root._visiblePlayers
                }

                delegate: Item {
                    id: playerDelegate
                    required property MprisPlayer modelData
                    required property int index

                    width: playerViewport.width
                    height: playerViewport.height
                    x: 0
                    y: (playerDelegate.index - root.currentTab)
                        * playerViewport.height
                    enabled: playerDelegate.index === root.currentTab
                    visible: enabled || tabSlideAnim.running
                    z: enabled ? 2 : 1

                    function focusPrimaryControl(): void {
                        playerControl.focusPrimaryControl()
                    }

                    Behavior on y {
                        enabled: Appearance.animationsEnabled
                        NumberAnimation {
                            id: tabSlideAnim
                            duration: root.tabSlideDuration
                            easing.type: Appearance.animation.elementMove.type
                            easing.bezierCurve:
                                Appearance.animation.elementMove.bezierCurve
                        }
                    }

                    PlayerControl {
                        id: playerControl
                        anchors {
                            top: parent.top
                            bottom: parent.bottom
                            left: parent.left
                            right: parent.right
                            rightMargin: root.tabCount > 1 ? 16 : 0
                        }
                        player: modelData
                        visualizerPoints: []
                        showVisualizer: false
                        compactLayout: root.compactLayout
                        radius: root.popupRounding
                        screenX: root.screenX + playerDelegate.x + playerControl.x
                        screenY: root.screenY + playerViewport.y
                            + playerDelegate.y + playerControl.y
                    }
                }
            }

            // Same compact vertical indicator language as Weather Popup:
            // each media source is a tab, while the active source is the
            // primary dot. The rail stays on the right rather than adding a
            // second row of source labels above the player.
            Item {
                id: tabIndicator
                width: 14
                height: indicatorDots.implicitHeight
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: root.tabCount > 1
                z: 20

                Column {
                    id: indicatorDots
                    anchors.centerIn: parent
                    spacing: 7

                    Repeater {
                        model: root.tabCount

                        delegate: Rectangle {
                            id: indicatorDot
                            required property int index
                            readonly property var tabPlayer:
                                root._visiblePlayers[indicatorDot.index] ?? null
                            width: 7
                            height: 7
                            radius: width / 2
                            color: indicatorDot.index === root.currentTab
                                ? Appearance.colors.colPrimary
                                : Appearance.colors.colLayer2
                            opacity:
                                indicatorDot.index === root.currentTab ? 1 : 0.55

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -5
                                hoverEnabled: true
                                activeFocusOnTab: true
                                cursorShape: Qt.PointingHandCursor
                                Accessible.role: Accessible.Button
                                Accessible.name:
                                    Translation.tr("Switch media source")
                                    + ": " + root.playerLabel(indicatorDot.tabPlayer)
                                Accessible.focusable: true

                                Keys.onPressed: event => {
                                    if (event.isAutoRepeat
                                            || (event.key !== Qt.Key_Return
                                                && event.key !== Qt.Key_Enter
                                                && event.key !== Qt.Key_Space))
                                        return
                                    event.accepted = true
                                    root.selectTab(indicatorDot.index)
                                }

                                onClicked:
                                    root.selectTab(indicatorDot.index)
                            }
                        }
                    }
                }
            }

            WheelHandler {
                target: playerViewport
                orientation: Qt.Vertical
                acceptedDevices:
                    PointerDevice.Mouse | PointerDevice.TouchPad
                enabled: root.tabCount > 1

                onWheel: event => {
                    // Match Weather Popup semantics: selectTab() clamps at the
                    // first/last source. Touchpads emit several wheel packets for
                    // one gesture, so modulo wrapping here could advance to the
                    // next source and immediately wrap back to the previous one.
                    if (event.angleDelta.y < 0)
                        root.selectTab(root.currentTab + 1)
                    else if (event.angleDelta.y > 0)
                        root.selectTab(root.currentTab - 1)
                    event.accepted = true
                }
            }
        }

        EqualizerPanel {
            Layout.fillWidth: true
            implicitWidth: root.widgetWidth
            compactLayout: root.compactLayout
            active: root.presentationActive && root.visible
        }

    }
}
