pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.perimeter
import qs.modules.dashboard
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    property bool panelVisible: true
    property bool embeddedSurface: false
    property bool externalEditToolbar: false
    property bool warmContent: false
    readonly property var canvasController: dashboardContent.canvasController
    property bool directBottomAttachment: false
    property bool popupPresented: true
    property string searchingText: ""
    property real revealProgress: 0
    property real dashboardProgress: 1
    property bool _hasPresentedOnce: false
    // Once the first debounced result set is ready, keep the Dashboard in
    // Applications mode for the rest of that search session. Subsequent query
    // debounces update the model in place instead of retriggering the outer
    // Dashboard <-> Search fade/height transition on every keystroke.
    property bool _searchSessionPresented: false
    property real availableWidth: root.QsWindow?.window?.screen?.width ?? 1920
    property real availableHeight: root.QsWindow?.window?.screen?.height ?? 1080
    property real attachmentThickness: Math.max(1, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.width ?? 10)))

    readonly property bool applicationDragActive: searchWidget.applicationDragActive
    readonly property bool searching: root.searchingText.length > 0
    readonly property bool presentingSearch:
        root.searching && root._searchSessionPresented
    readonly property real searchTransitionProgress:
        1 - root.dashboardProgress
    readonly property int modeTransitionDuration:
        Math.max(220, Math.round(SurfaceMotion.duration * 0.9))
    readonly property real dashboardOpacity:
        1 - root._smooth01(root.searchTransitionProgress / 0.44)
    readonly property real searchResultsOpacity:
        root._smooth01((root.searchTransitionProgress - 0.22) / 0.78)
    readonly property real widthRatio: Math.min(0.9, Math.max(0.4, Config.options?.dashboard?.widthRatio ?? 0.72))
    readonly property real heightRatio: Math.min(0.9, Math.max(0.45, Config.options?.dashboard?.heightRatio ?? 0.72))
    readonly property real dashboardWidth: Math.round(Math.max(0,
        Math.min(root.availableWidth - 24, root.availableWidth * root.widthRatio)))
    readonly property bool editing: dashboardContent.editMode
    readonly property real editToolbarReserve: root.editing && !root.externalEditToolbar
        ? Math.max(0, dashboardEditToolbar.implicitHeight - 1) : 0
    readonly property real baseConfiguredHeight: Math.round(Math.min(
        Math.max(320, root.availableHeight - 24),
        Math.max(420, root.availableHeight * root.heightRatio)))
    readonly property real configuredHeight: Math.round(Math.max(320,
        Math.min(root.baseConfiguredHeight,
            root.availableHeight - 24 - root.editToolbarReserve)))
    readonly property real searchOnlyHeight: Math.min(root.configuredHeight, Math.max(searchWidget.collapsedHeight + 24, searchWidget.implicitHeight + 24))
    readonly property real dashboardContentHeight: Math.max(240, root.configuredHeight - searchWidget.collapsedHeight - 36)

    readonly property bool screenEdgeShadowEnabled:
        Config.options?.appearance?.screenEdge?.physicalShadow?.enabled ?? true
    readonly property real screenEdgeShadowSize: Math.max(0, Math.min(32,
        Math.round(Config.options?.appearance?.screenEdge?.physicalShadow?.size ?? 15)))
    readonly property real screenEdgeShadowOpacity: Math.max(0, Math.min(1.0,
        Number(Config.options?.appearance?.screenEdge?.physicalShadow?.opacity ?? 0.70)))
    readonly property real connectedDecorationMargin: root.embeddedSurface ? 0 : root.directBottomAttachment
        ? Math.max(Appearance.sizes.elevationMargin,
            PerimeterTokens.irisFuseDepth, root.screenEdgeShadowSize + 2)
        : Appearance.sizes.elevationMargin

    implicitWidth: dashContainer.width + root.connectedDecorationMargin * 2
    implicitHeight: dashContainer.height + root.editToolbarReserve
        + (root.directBottomAttachment
            ? root.connectedDecorationMargin
            : root.connectedDecorationMargin * 2)
    clip: root.directBottomAttachment
    readonly property rect connectedSurfaceRect: Qt.rect(dashContainer.x, dashContainer.y, dashContainer.width, dashContainer.height)
    readonly property color connectedSurfaceColor: Appearance.colors.colLayer0

    function handleEscape(): bool {
        return dashboardContent.handleEscape()
    }
    // The Overview window owns key focus, but the edit bar can take it when
    // clicked. Catch the first Escape across either focus target.
    Shortcut {
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        // The embedded Abyss path uses the owning Perimeter WindowShortcut.
        // Retain this for independently hosted Overview only.
        enabled: root.editing && root.popupPresented && !root.externalEditToolbar
        onActivated: root.handleEscape()
    }
    function focusSearchInput(): void { searchWidget.focusSearchInput() }
    function disableExpandAnimation(): void { searchWidget.disableExpandAnimation() }
    function cancelSearch(): void { searchWidget.cancelSearch() }
    function focusFirstItem(): void { searchWidget.focusFirstItem() }
    function setSearchingText(text): void { searchWidget.setSearchingText(text) }
    function _clamp01(value): real {
        return Math.max(0, Math.min(1, value))
    }
    function _smooth01(value): real {
        const t = root._clamp01(value)
        return t * t * (3 - 2 * t)
    }
    function syncReveal(): void {
        if (!root.popupPresented) {
            firstRevealFrameTimer.stop()
            root.revealProgress = 0
            return
        }

        // The first mapped frame used to race the PanelWindow mapping: the
        // reveal animation was already progressing while the compositor had
        // not presented the surface yet, so the first open looked like a fade/
        // pop instead of a slide. Keep one closed frame resident, then start
        // the immutable SurfaceMotion slide. Later opens reverse normally.
        if (!root._hasPresentedOnce) {
            root._hasPresentedOnce = true
            root.revealProgress = 0
            firstRevealFrameTimer.restart()
            return
        }
        root.revealProgress = 1
    }
    function syncDashboard(): void {
        root.dashboardProgress = root.presentingSearch ? 0 : 1
    }
    function syncSearchSession(): void {
        if (!root.searching)
            root._searchSessionPresented = false
        root.syncDashboard()
    }
    function acceptReadySearchResults(): void {
        if (root.searching && searchWidget.resultsReady)
            root._searchSessionPresented = true
        root.syncDashboard()
    }
    onPopupPresentedChanged: root.syncReveal()
    onSearchingChanged: root.syncSearchSession()

    Connections {
        target: searchWidget
        function onResultsReadyChanged(): void {
            root.acceptReadySearchResults()
        }
    }

    Timer {
        id: firstRevealFrameTimer
        interval: 16
        repeat: false
        onTriggered: {
            if (root.popupPresented)
                root.revealProgress = 1
        }
    }

    Component.onCompleted: {
        root.revealProgress = 0
        root._searchSessionPresented = root.searching && searchWidget.resultsReady
        root.dashboardProgress = root.presentingSearch ? 0 : 1
        root.syncReveal()
    }

    Behavior on revealProgress {
        enabled: Appearance.animationsEnabled
        NumberAnimation { duration: SurfaceMotion.duration; easing.type: SurfaceMotion.easingType }
    }
    Behavior on dashboardProgress {
        enabled: Appearance.animationsEnabled
        NumberAnimation {
            duration: root.modeTransitionDuration
            easing.type: Easing.InOutCubic
        }
    }

    Item {
        id: dashboardSurfaceLayer
        z: 2
        anchors.fill: parent
        transform: Translate { y: root.embeddedSurface ? 0 : (1 - root.revealProgress) * dashContainer.height }
    }

    StyledRectangularShadow {
        parent: dashboardSurfaceLayer
        z: 0
        target: dashContainer
        visible: !root.embeddedSurface && root.panelVisible && !root.directBottomAttachment
            && root.screenEdgeShadowEnabled && root.screenEdgeShadowSize > 0
            && root.screenEdgeShadowOpacity > 0
        blur: root.screenEdgeShadowSize
        spread: 0
        offset: Qt.vector2d(0, 0)
        color: Qt.alpha(Appearance.m3colors.m3shadow, root.screenEdgeShadowOpacity)
        joinBottom: root.directBottomAttachment
    }

    // The iRiS field supplies only the connected plate/shadow. Dashboard
    // content must remain above it; otherwise the opaque field covers every
    // widget and the launcher appears as one blank background rectangle.
    ConnectedSurfaceIrisEdgeSurface {
        id: dashboardIrisSurface
        z: 1
        anchors.fill: parent
        visible: !root.embeddedSurface && root.directBottomAttachment
        edge: "bottom"
        ownerThickness: root.attachmentThickness
        outputRect: Qt.rect(0, 0, root.width,
            root.height + root.attachmentThickness)
        bodyRect: Qt.rect(
            dashContainer.x,
            dashContainer.y + (1 - root.revealProgress) * dashContainer.height,
            dashContainer.width,
            dashContainer.height)
        bodyRadius: dashContainer.radius
        fillColor: Appearance.colors.colLayer0
        progress: root.revealProgress
        shadowEnabled: root.screenEdgeShadowEnabled
            && root.screenEdgeShadowSize > 0
            && root.screenEdgeShadowOpacity > 0
        shadowExtent: root.screenEdgeShadowSize
        shadowColor: Qt.alpha(
            Appearance.m3colors.m3shadow, root.screenEdgeShadowOpacity)
    }

    DashboardEditToolbar {
        id: dashboardEditToolbar
        parent: dashboardSurfaceLayer
        z: 8
        canvasController: dashboardContent.canvasController
        visible: root.editing && !root.externalEditToolbar
        width: Math.min(
            dashboardEditToolbar.implicitWidth,
            Math.max(1, dashContainer.width - 32))
        x: Math.round(dashContainer.x
            + (dashContainer.width - width) / 2)
        y: root.embeddedSurface ? 0 : Math.round(dashContainer.y - height + 1)
    }

    Rectangle {
        id: dashContainer
        parent: dashboardSurfaceLayer
        z: 1
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: root.directBottomAttachment ? parent.bottom : undefined
            verticalCenter: root.directBottomAttachment ? undefined : parent.verticalCenter
            verticalCenterOffset: root.embeddedSurface ? root.editToolbarReserve / 2 : 0
        }
        width: root.embeddedSurface ? root.width : root.dashboardWidth
        height: root.embeddedSurface ? Math.max(0, root.height - root.editToolbarReserve) : root.presentingSearch
            ? root.searchOnlyHeight : root.configuredHeight
        radius: Appearance.rounding.large
        topLeftRadius: radius
        topRightRadius: radius
        bottomLeftRadius: root.directBottomAttachment ? 0 : radius
        bottomRightRadius: root.directBottomAttachment ? 0 : radius
        color: root.embeddedSurface || root.directBottomAttachment
            ? "transparent" : Appearance.colors.colLayer0
        clip: true

        Behavior on height {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: root.modeTransitionDuration
                easing.type: Easing.InOutCubic
            }
        }

        Item {
            id: dashboardViewport
            x: 12
            y: 12
            width: Math.max(0, dashContainer.width - 24)
            height: root.embeddedSurface ? Math.max(0,dashContainer.height-searchWidget.collapsedHeight-36) : root.dashboardContentHeight
            clip: true
            visible: root.dashboardOpacity > 0.001
            opacity: root.dashboardOpacity

            DashboardContent {
                id: dashboardContent
                anchors.fill: parent
                embeddedSurface: true
                warmContent: root.warmContent
                presentationActive: root.panelVisible && root.popupPresented
                    && root.dashboardOpacity > 0.001
                screenWidth: root.availableWidth
                screenHeight: root.availableHeight
            }
        }

        SearchWidget {
            id: searchWidget
            x: 12
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12
            width: Math.max(0, dashContainer.width - 24)
            height: implicitHeight
            embeddedSurface: true
            panelVisible: root.panelVisible
            directBottomAttachment: false
            searchingText: root.searchingText
            resultsOpacity: root.searchResultsOpacity
            availableHeight: Math.max(220, root.configuredHeight - 24)
            onSearchingTextChanged: if (searchingText !== root.searchingText) root.searchingText = searchingText
        }
    }
}
