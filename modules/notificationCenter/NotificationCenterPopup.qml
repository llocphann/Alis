pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.modules.bar as Bar
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.notificationCenter
import qs.services

Bar.StyledPopup {
    id: root

    required property Item anchorItem
    required property string outputName
    property bool hoverAllowed: true
    // The popup may coexist with Quick Notes while its editor owns the output
    // keyboard. Only search/focus acquisition is deferred; pointer content
    // remains visible and interactive.
    property bool keyboardAllowed: true
    property bool entryBridgeHeld: false
    property bool exitGraceHeld: false
    property bool keyboardInteraction: false
    property bool hoverSessionArmed: true
    property int selectedTab: 0
    property int _screenTimeRevision: 0
    // Legacy corner popup uses a tiny 0,0-local anchor. A proper Abyss module
    // has real output-relative geometry and must not snap to the far corner.
    property bool moduleAnchorMode: false
    property string cornerAttachmentEdge: "bottom"
    property real cornerAttachmentThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))

    readonly property bool explicitForThisOutput:
        GlobalStates.notificationCenterExplicitOpen
        && GlobalStates.notificationCenterPresentationOutput === root.outputName
    readonly property real requestedPopupWidth: Math.max(320, Math.min(760,
        Config.options?.notificationCenter?.popupWidth ?? 420))
    readonly property real requestedPopupHeight: Math.max(260, Math.min(900,
        Config.options?.notificationCenter?.popupHeight ?? 560))
    readonly property var todayUsage: {
        const revision = root._screenTimeRevision
        return ScreenTime.getToday()
    }
    readonly property var todayApps: {
        const revision = root._screenTimeRevision
        return ScreenTime.getAppList(1)
    }
    // Keep rows readable in the shared footprint, including a custom short
    // popup. Extra apps are summarized as +N without another scroller.
    readonly property int visibleAppLimit: Math.max(0, Math.min(4,
        Math.floor((root.requestedPopupHeight - root._contentPadding * 2 - 123) / 39)))
    readonly property var visibleApps: root.todayApps.slice(0, root.visibleAppLimit)
    readonly property int hiddenAppCount:
        Math.max(0, root.todayApps.length - root.visibleApps.length)
    readonly property real maxAppSeconds: {
        let maximum = 1
        const apps = root.todayApps
        for (let i = 0; i < apps.length; ++i)
            maximum = Math.max(maximum, Number(apps[i]?.seconds ?? 0))
        return maximum
    }
    // MouseArea.containsMouse can clear while StyledPopup's real source
    // HoverHandler still reports hovered (owner native trace: #68–71 and
    // #80–82). Both are legitimate views of the same corner anchor.
    // Keep the notification's lifetime lease aligned with the already-active
    // source hover rather than expiring its bridge grace beneath the pointer.
    readonly property bool _anchorHovered: Boolean(root.anchorItem
        && ((root.anchorItem.containsMouse ?? false)
            || (root._anchorHover?.hovered ?? false)))
    readonly property bool hoverLeaseRequested:
        root.hoverAllowed
        && !root.explicitForThisOutput
        && root.presentationActive
        && (root._anchorHovered
            || root.popupHovered
            || root.entryBridgeHeld
            || (contentLoader.item?.dragActive ?? false))

    hoverTarget: root.anchorItem
    barAutoHideHoldEnabled: false
    // ScreenCorners owns this anchor in a tiny bottom-right layer surface.
    // Its local x/y are therefore near zero; pin the popup to the trailing
    // tangent edge of the full output instead of interpreting those locals as
    // output coordinates (which incorrectly placed the body bottom-left).
    tangentEdgeOverride: root.moduleAnchorMode ? "" : "end"
    attachmentEdgeOverride: root.cornerAttachmentEdge
    attachmentThicknessOverride: root.cornerAttachmentThickness
    hoverActivates: root.hoverAllowed && root.hoverSessionArmed
    alternativeVisibleCondition: root.explicitForThisOutput
        || root.entryBridgeHeld
        || root.exitGraceHeld
        || root.keyboardInteraction
        || (contentLoader.item?.dragActive ?? false)
    keyboardFocus: root.keyboardInteraction
    closeOnOutsideClick: root.explicitForThisOutput || root.keyboardInteraction
    popupBackgroundMargin: 0

    function enterKeyboardMode(): void {
        if (!root.presentationActive || !root.keyboardAllowed)
            return
        if (!GlobalStates.openNotificationCenter(root.outputName))
            return
        root.keyboardInteraction = true
        Qt.callLater(() => {
            if (contentLoader.item)
                contentLoader.item.focusSearch()
        })
    }

    onSelectedTabChanged: {
        if (root.selectedTab === 1 && root.keyboardInteraction)
            root.keyboardInteraction = false
    }
    onKeyboardAllowedChanged: {
        if (root.keyboardAllowed || !root.keyboardInteraction)
            return
        root.keyboardInteraction = false
        if (contentLoader.item)
            contentLoader.item.clearSearchFocus()
    }

    // StyledPopup's default property accepts only QQuickItem. Keep the
    // non-visual ScreenTime observer on an explicit QObject property so type
    // construction never tries to route Connections into popup content.
    property QtObject _screenTimeConnections: Connections {
        target: ScreenTime

        function onDataChanged(): void {
            root._screenTimeRevision++
        }

        function onReadyChanged(): void {
            root._screenTimeRevision++
        }

        function onEnabledChanged(): void {
            root._screenTimeRevision++
        }
    }

    function isCurrentApp(app): bool {
        const current = String(ScreenTime.currentAppId ?? "").toLowerCase()
        const original = String(app?.originalId ?? "").toLowerCase()
        const id = String(app?.id ?? "").toLowerCase()
        return current.length > 0
            && (current === original || current === id)
    }

    function dismissAndDisarm(): void {
        entryBridgeTimer.stop()
        exitGraceTimer.stop()
        root.entryBridgeHeld = false
        root.exitGraceHeld = false
        root.keyboardInteraction = false
        root.hoverSessionArmed = false
        if (contentLoader.item)
            contentLoader.item.clearSearchFocus()
        GlobalStates.setNotificationCenterHoverOutput(root.outputName, false)
        GlobalStates.closeNotificationCenter()
    }

    function rearmHoverIfIdle(): void {
        if (!root.presentationActive && !root._anchorHovered)
            root.hoverSessionArmed = true
    }

    onRequestClose: root.dismissAndDisarm()

    onHoverAllowedChanged: {
        if (!hoverAllowed && !explicitForThisOutput) {
            entryBridgeTimer.stop()
            entryBridgeHeld = false
        }
    }

    onHoverLeaseRequestedChanged: {
        if (root.hoverLeaseRequested) {
            exitGraceTimer.stop()
            root.exitGraceHeld = false
            GlobalStates.setNotificationCenterHoverOutput(root.outputName, true)
            return
        }

        if (root.presentationActive && !root.explicitForThisOutput) {
            root.exitGraceHeld = true
            exitGraceTimer.restart()
            return
        }

        GlobalStates.setNotificationCenterHoverOutput(root.outputName, false)
    }

    onPresentationActiveChanged: {
        if (presentationActive) {
            Qt.callLater(() => {
                if (root.presentationActive && !root.explicitForThisOutput) {
                    root.entryBridgeHeld = true
                    entryBridgeTimer.restart()
                }
            })
            return
        }

        entryBridgeTimer.stop()
        exitGraceTimer.stop()
        root.entryBridgeHeld = false
        root.exitGraceHeld = false
        root.keyboardInteraction = false
        if (contentLoader.item)
            contentLoader.item.clearSearchFocus()
        GlobalStates.setNotificationCenterHoverOutput(root.outputName, false)
        if (!root._anchorHovered)
            root.hoverSessionArmed = true
    }

    Component.onDestruction:
        GlobalStates.setNotificationCenterHoverOutput(root.outputName, false)

    property QtObject _entryBridgeTimer: Timer {
        id: entryBridgeTimer
        // Use the public transfer-grace setting for both directions. A separate
        // hard-coded entry delay made Settings only partially authoritative.
        interval: Math.max(0,
            Config.options?.notificationCenter?.closeGraceMs ?? 280)
        repeat: false
        onTriggered: root.entryBridgeHeld = false
    }

    property QtObject _exitGraceTimer: Timer {
        id: exitGraceTimer
        interval: Math.max(0,
            Config.options?.notificationCenter?.closeGraceMs ?? 280)
        repeat: false
        onTriggered: {
            if (root.hoverLeaseRequested)
                return
            root.exitGraceHeld = false
            GlobalStates.setNotificationCenterHoverOutput(root.outputName, false)
        }
    }

    Item {
        id: contentRoot

        Shortcut {
            sequences: [StandardKey.Cancel]
            context: Qt.WindowShortcut
            enabled: root.presentationActive
                && (root.explicitForThisOutput || root.keyboardInteraction)
            onActivated: root.dismissAndDisarm()
        }

        implicitWidth: Math.max(1,
            root.requestedPopupWidth - root._contentPadding * 2)
        implicitHeight: Math.max(1,
            root.requestedPopupHeight - root._contentPadding * 2)
        width: parent ? parent.width : implicitWidth
        height: parent ? parent.height : implicitHeight

        ColumnLayout {
            anchors.fill: parent
            spacing: 10

            PillTabBar {
                Layout.fillWidth: true
                currentIndex: root.selectedTab
                pillHeight: 36
                tabs: [
                    {
                        icon: "notifications",
                        label: Translation.tr("Notifications"),
                        count: Notifications.list.length
                    },
                    {
                        icon: "monitoring",
                        label: Translation.tr("Activity")
                    }
                ]
                onTabSelected: index => root.selectedTab = index
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Loader {
                    id: contentLoader
                    anchors.fill: parent
                    active: root.presentationActive && root.selectedTab === 0
                    sourceComponent: NotificationCenterContent {
                        popupPresentation: true
                        onSearchFocusRequested: root.enterKeyboardMode()
                        onExternalNavigationRequested: root.dismissAndDisarm()
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    visible: root.selectedTab === 1
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        Layout.maximumHeight: 52
                        spacing: 7

                        Repeater {
                            model: [
                                {
                                    icon: "avg_pace",
                                    label: Translation.tr("System uptime"),
                                    value: DateTime.uptime || "--"
                                },
                                {
                                    icon: "schedule",
                                    label: Translation.tr("Today"),
                                    value: ScreenTime.formatDuration(
                                        Number(root.todayUsage?.totalSeconds ?? 0))
                                }
                            ]

                            delegate: Rectangle {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 14
                                color: Appearance.colors.colLayer1
                                border.width: 1
                                border.color: Appearance.colors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 9
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 30
                                        Layout.preferredHeight: 30
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: width / 2
                                        color: Appearance.colors.colLayer2

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            iconSize: 16
                                            color: Appearance.colors.colPrimary
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: -1

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.pixelSize:
                                                Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.value
                                            font.pixelSize:
                                                Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            font.family:
                                                Appearance.font.family.numbers
                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 18
                        Layout.maximumHeight: 18
                        spacing: 6

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("App usage")
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.weight: Font.Medium
                            color: Appearance.colors.colSubtext
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: root.hiddenAppCount > 0
                            text: "+" + root.hiddenAppCount
                            font.pixelSize: Appearance.font.pixelSize.smallest
                            font.family: Appearance.font.family.numbers
                            color: Appearance.colors.colSubtext
                        }
                    }

                    ColumnLayout {
                        visible: root.visibleApps.length > 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 5

                        Repeater {
                            model: root.visibleApps

                            delegate: Rectangle {
                                id: usageRow
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: 34
                                Layout.maximumHeight: 34
                                radius: 12
                                clip: true

                                readonly property bool active:
                                    root.isCurrentApp(modelData)
                                readonly property real usageFraction:
                                    Math.max(0, Math.min(1,
                                        Number(modelData?.seconds ?? 0)
                                            / root.maxAppSeconds))

                                color: active
                                    ? Appearance.colors.colPrimaryContainer
                                    : Appearance.colors.colLayer1
                                border.width: 1
                                border.color: active
                                    ? Appearance.colors.colPrimary
                                    : Appearance.colors.colLayer2

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 7

                                    SmartAppIcon {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        iconSize: 20
                                        icon: AppSearch.guessIcon(
                                            String(usageRow.modelData?.name ?? "")
                                                .toLowerCase()
                                            || String(
                                                usageRow.modelData?.originalId
                                                    ?? usageRow.modelData?.id
                                                    ?? ""))
                                    }

                                    StyledText {
                                        Layout.preferredWidth: 78
                                        Layout.minimumWidth: 52
                                        Layout.maximumWidth: 92
                                        Layout.alignment: Qt.AlignVCenter
                                        text: usageRow.modelData?.name
                                            || usageRow.modelData?.id || ""
                                        font.pixelSize:
                                            Appearance.font.pixelSize.smallest
                                        font.weight: usageRow.active
                                            ? Font.DemiBold : Font.Medium
                                        color: usageRow.active
                                            ? Appearance.colors
                                                .colOnPrimaryContainer
                                            : Appearance.colors.colOnLayer1
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 4
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: usageRow.active
                                                ? ColorUtils.transparentize(
                                                    Appearance.colors
                                                        .colOnPrimaryContainer,
                                                    0.78)
                                                : Appearance.colors.colLayer2

                                            Rectangle {
                                                anchors {
                                                    left: parent.left
                                                    top: parent.top
                                                    bottom: parent.bottom
                                                }
                                                width: parent.width
                                                    * usageRow.usageFraction
                                                radius: height / 2
                                                color: usageRow.active
                                                    ? Appearance.colors
                                                        .colOnPrimaryContainer
                                                    : Appearance.colors.colPrimary
                                                opacity: usageRow.active
                                                    ? 0.82 : 0.62
                                            }
                                        }
                                    }

                                    StyledText {
                                        Layout.preferredWidth: 52
                                        Layout.alignment: Qt.AlignVCenter
                                        text: ScreenTime.formatDuration(
                                            Number(usageRow
                                                .modelData?.seconds ?? 0))
                                        horizontalAlignment: Text.AlignRight
                                        font.pixelSize:
                                            Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        font.family:
                                            Appearance.font.family.numbers
                                        color: usageRow.active
                                            ? Appearance.colors
                                                .colOnPrimaryContainer
                                            : Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                            Layout.minimumHeight: 0
                        }
                    }

                    Item {
                        visible: root.visibleApps.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RowLayout {
                            anchors.centerIn: parent
                            width: Math.min(parent.width - 16, 250)
                            spacing: 8

                            MaterialSymbol {
                                text: "monitoring"
                                iconSize: 20
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: ScreenTime.enabled
                                    ? Translation.tr("No activity recorded yet")
                                    : Translation.tr(
                                        "Activity tracking is starting…")
                                font.pixelSize:
                                    Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }
}
