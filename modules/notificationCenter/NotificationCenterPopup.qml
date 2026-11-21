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
        if (!root.presentationActive || root.selectedTab !== 1)
            return ({ totalSeconds: 0 })
        const revision = root._screenTimeRevision
        return ScreenTime.getToday()
    }
    readonly property var todayApps: {
        if (!root.presentationActive || root.selectedTab !== 1)
            return []
        const revision = root._screenTimeRevision
        return ScreenTime.getAppList(1)
    }
    // Keep rows readable in the shared footprint across custom short and tall
    // Edgebar heights. Extra apps are summarized as +N without another scroller.
    readonly property real _effectiveContentHeight: {
        const requestedInner = Math.max(0, root.requestedPopupHeight - root._contentPadding * 2)
        return contentRoot.height > 0
            ? Math.min(contentRoot.height, requestedInner)
            : requestedInner
    }
    readonly property bool _activityNarrow: contentRoot.width > 0 && contentRoot.width < 340
    readonly property bool _activityWide: contentRoot.width >= 500
    readonly property bool _activityTall: root._effectiveContentHeight >= 480
    readonly property int _statCardHeight: Math.max(
        root._activityTall ? 56 : 52,
        Math.round(48 * Appearance.fontSizeScale))
    readonly property int _appRowHeight: Math.max(
        root._activityTall ? 36 : 34,
        Math.round(30 * Appearance.fontSizeScale))
    readonly property int _appRowSpacing: root._activityTall ? 6 : 5
    readonly property int _activityChromeHeight:
        30 + (root._activityTall ? 8 : 6) + root._statCardHeight + 6 + 18 + 6
    readonly property int visibleAppLimit: Math.max(0, Math.min(16,
        Math.floor((root._effectiveContentHeight - root._activityChromeHeight)
            / (root._appRowHeight + root._appRowSpacing))))
    readonly property real _appNameWidth: Math.max(62, Math.min(200,
        Math.round(contentRoot.width * 0.28)))
    readonly property real _appDurationWidth: Math.max(
        Math.round(52 * Appearance.fontSizeScale),
        Math.min(88, Math.round(contentRoot.width * 0.14 * Math.max(1, Appearance.fontSizeScale))))
    readonly property color _activitySubLayer: ColorUtils.tonalStep(
        Appearance.colors.colLayer1Base,
        Appearance.colors.colLayer1Base.hslLightness > 0.86 ? -0.022 : 0.022)
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
    // Default corner mode uses tangentEdgeOverride: "end"
    tangentEdgeOverride: root.moduleAnchorMode ? "" : "end"
    attachmentEdgeOverride: root.cornerAttachmentEdge
    attachmentThicknessOverride: root.cornerAttachmentThickness
    hoverActivates: root.hoverAllowed && root.hoverSessionArmed
    alternativeVisibleCondition: root.explicitForThisOutput
        || root.entryBridgeHeld
        || root.exitGraceHeld
        || root.keyboardInteraction
        || (contentLoader.item?.dragActive ?? false)
    fifoAutoClosable: root.hoverAllowed && !root.explicitForThisOutput
        && !root.keyboardInteraction && !(contentLoader.item?.dragActive ?? false)
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
        enabled: root.presentationActive && root.selectedTab === 1

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

    onPopupHoveredChanged: {
        if (root.popupHovered && root.entryBridgeHeld) {
            entryBridgeTimer.stop()
            root.entryBridgeHeld = false
        }
    }

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
            spacing: root._activityTall ? 8 : 6

            PillTabBar {
                id: notificationTabs
                objectName: "notificationCenterMainTabs"
                Layout.fillWidth: false
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(360,
                    Math.min(Math.max(180, contentRoot.width - 8),
                        Math.max(284, Math.round(contentRoot.width * 0.76))))
                width: Layout.preferredWidth
                currentIndex: root.selectedTab
                pillHeight: 30
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
                    id: activityPane
                    objectName: "notificationCenterActivityPane"
                    anchors.fill: parent
                    visible: root.selectedTab === 1
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root._statCardHeight
                        Layout.maximumHeight: root._statCardHeight
                        spacing: root._activityNarrow ? 6 : 8

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
                                Layout.minimumWidth: 0
                                radius: 14
                                color: Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: root._activitySubLayer

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root._activityNarrow ? 7 : (root._activityWide ? 12 : 9)
                                    anchors.rightMargin: root._activityNarrow ? 7 : (root._activityWide ? 12 : 9)
                                    spacing: root._activityNarrow ? 6 : (root._activityWide ? 10 : 8)

                                    Rectangle {
                                        Layout.preferredWidth: root._activityNarrow ? 26 : (root._activityTall ? 32 : 30)
                                        Layout.preferredHeight: Layout.preferredWidth
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: width / 2
                                        color: root._activitySubLayer

                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: modelData.icon
                                            iconSize: root._activityNarrow ? 15 : (root._activityTall ? 17 : 16)
                                            color: Appearance.colors.colPrimary
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: -1

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.pixelSize:
                                                Appearance.font.pixelSize.smallest
                                            color: Appearance.colors.colSubtext
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: modelData.value
                                            font.pixelSize: root._activityWide
                                                ? Appearance.font.pixelSize.normal
                                                : Appearance.font.pixelSize.small
                                            font.weight: Font.DemiBold
                                            font.family:
                                                Appearance.font.family.numbers
                                            color: Appearance.colors.colOnLayer1
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
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
                        spacing: root._appRowSpacing

                        Repeater {
                            model: root.visibleApps

                            delegate: Rectangle {
                                id: usageRow
                                required property var modelData

                                Layout.fillWidth: true
                                Layout.preferredHeight: root._appRowHeight
                                Layout.maximumHeight: root._appRowHeight
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
                                    : Appearance.colors.colLayer1Base
                                border.width: 1
                                border.color: active
                                    ? Appearance.colors.colPrimary
                                    : root._activitySubLayer

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: root._activityNarrow ? 7 : 10
                                    anchors.rightMargin: root._activityNarrow ? 7 : 10
                                    spacing: root._activityNarrow ? 6 : 8

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
                                        Layout.preferredWidth: root._appNameWidth
                                        Layout.minimumWidth: 52
                                        Layout.maximumWidth: root._appNameWidth
                                        Layout.alignment: Qt.AlignVCenter
                                        text: usageRow.modelData?.name
                                            || usageRow.modelData?.id || ""
                                        font.pixelSize: root._activityWide
                                            ? Appearance.font.pixelSize.smaller
                                            : Appearance.font.pixelSize.smallest
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
                                        Layout.preferredHeight: root._activityWide ? 5 : 4
                                        Layout.alignment: Qt.AlignVCenter

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: height / 2
                                            color: usageRow.active
                                                ? ColorUtils.transparentize(
                                                    Appearance.colors
                                                        .colOnPrimaryContainer,
                                                    0.78)
                                                : root._activitySubLayer

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
                                        Layout.preferredWidth: root._appDurationWidth
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
                        visible: root.todayApps.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Row {
                            id: activityEmptyState
                            objectName: "notificationCenterActivityEmpty"
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "monitoring"
                                iconSize: 20
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Math.max(80, activityEmptyState.parent.width - 48))
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
