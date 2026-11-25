import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks
import qs.modules.waffle.looks as Waffle
import "DashboardCustomTabPolicy.js" as TabPolicy

/**
 * Dashboard navigation: uptime at left, tab icon indicators at center, actions at right.
 */
Item {
    id: root
    // Page dots remain when actions are hidden. A hidden RowLayout can report
    // a new implicit size after Edit changes its children; it must not resize
    // the visible page header or the widget canvas.
    implicitHeight: Math.max(32, showActions ? actions.implicitHeight : 0)
        + (separateNavigation ? 36 : 0)
    property bool waffleMenu: false
    onWaffleMenuChanged: pageDotsRow.forceLayout()
    readonly property bool separateNavigation: waffleMenu && showActions && pageCount > 1
        && (editMode || (width - pages.width) / 2 < actions.implicitWidth + 8)

    property bool editMode: false
    property bool showActions: true
    property int currentPage: 0
    // DashboardContent supplies its existing slide progress; standalone Header
    // tests can fall back to the selected page without inventing a new timer.
    property real indicatorProgress: currentPage
    readonly property int pageDotButtonWidth: 32
    readonly property int pageIconSize: 18
    // Arrows follow the latest request while a cold target is incubating.
    // Indicators continue to show the selected, ready page.
    property int navigationPage: currentPage
    property int pageCount: 1
    property var pageIds: ["dashboard", "music"]
    property var customTabs: []
    property var tabIcons: Config.options?.dashboard?.tabIcons ?? []
    property bool navigationAllowed: true
    property bool pageSlideInFlight: false
    property bool reorderAllowed: editMode
    property string dragPageId: ""
    property string dragPageOrder: ""
    property bool draggingPage: false
    property int dragTarget: -1
    property point dragPress: Qt.point(0,0)
    property point dragPointer: Qt.point(0,0)
    property string _movedPageId: ""
    readonly property bool narrow: width < 620
    readonly property bool abyss: Config.options?.panelFamily === "abyss"
    signal pageRequested(int index)
    signal pageMoveRequested(string id, int target)
    signal editModeRequested
    signal horizontalWheel(var event)
    function pageLabel(id): string {
        if(id==="dashboard") return Translation.tr("Dashboard")
        if(id==="music") return Translation.tr("Music")
        if(id==="weeklyPlanner") return Translation.tr("Weekly Planner")
        if(id==="spacedRepetition") return Translation.tr("Spaced Repetition")
        if(id==="exercisesTracker") return Translation.tr("Exercises Tracker")
        return root.customTabs.find(tab => tab.id === id)?.name ?? String(id ?? "")
    }
    function pageIcon(id): string {
        return TabPolicy.iconFor(root.tabIcons, id)
    }
    function focusMovedPage(): void {
        const index=pageIds.indexOf(_movedPageId)
        if(reorderAllowed && index>=0)pageRepeater.itemAt(index)?.forceActiveFocus(Qt.MouseFocusReason)
    }
    function moveFocusedPage(id,target): void {
        _movedPageId=id
        pageMoveRequested(id,target)
        Qt.callLater(root.focusMovedPage)
    }
    function cancelPageDrag(): bool {
        const active=dragPageId.length>0
        dragPageId="";dragPageOrder="";draggingPage=false;dragTarget=-1
        return active
    }
    function updatePageDrag(position): void {
        if (!dragPageId.length) return
        dragPointer=position
        if (!draggingPage && Math.hypot(position.x-dragPress.x,position.y-dragPress.y)>=Qt.styleHints.startDragDistance)
            draggingPage=true
        if (!draggingPage) return
        const point=root.mapToItem(pages,position.x,position.y)
        let nearest=Infinity,index=-1
        for(let at=0;at<pageRepeater.count;at++) {
            const item=pageRepeater.itemAt(at)
            const distance=Math.abs(point.x-item.x-item.width/2)
            if(distance<nearest){nearest=distance;index=at}
        }
        dragTarget=index
    }
    function finishPageDrag(position): void {
        const id=dragPageId,target=dragTarget,wasDragging=draggingPage
        const accept=wasDragging && reorderAllowed && position.x>=0 && position.x<=width
            && position.y>=-16 && position.y<=height+16
        cancelPageDrag()
        if(accept)moveFocusedPage(id,target)
        else if(!wasDragging && target>=0)root.pageRequested(target)
    }
    onReorderAllowedChanged: if(!reorderAllowed)cancelPageDrag()
    onEditModeChanged: {
        if (!editMode) {
            for (let i = 0; i < pageRepeater.count; ++i) {
                const item = pageRepeater.itemAt(i)
                if (item?.focus || item?.activeFocus)
                    item.focus = false
            }
        }
    }
    onPageIdsChanged: {
        // Config may republish an equal list during a live pointer gesture.
        // Cancel only when its identities/order actually changed.
        if (dragPageId.length && JSON.stringify(pageIds)!==dragPageOrder)
            cancelPageDrag()
    }
    Keys.onEscapePressed: event => {event.accepted=root.cancelPageDrag()}
    WheelHandler {
        target: null
        orientation: Qt.Horizontal
        blocking: false
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.navigationAllowed && root.pageCount > 1 && !root.editMode
        onWheel: event => root.horizontalWheel(event)
    }
    Keys.onLeftPressed: event => {
        if (root.navigationAllowed && !root.editMode && root.navigationPage > 0) {
            if (event.isAutoRepeat) {
                event.accepted = true
                return
            }
            root.pageRequested(root.navigationPage - 1)
            event.accepted = true
        } else event.accepted = false
    }
    Keys.onRightPressed: event => {
        if (root.navigationAllowed && !root.editMode && root.navigationPage < root.pageCount - 1) {
            if (event.isAutoRepeat) {
                event.accepted = true
                return
            }
            root.pageRequested(root.navigationPage + 1)
            event.accepted = true
        } else event.accepted = false
    }

    readonly property bool alisEverywhere: Appearance.alisEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere
    readonly property bool showPowerButtons: true
    readonly property color colText: waffleMenu ? Waffle.Looks.colors.fg : (abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000") : Appearance.angelEverywhere ? Appearance.angel.colText : alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer0)
    readonly property color colSubtext: waffleMenu ? Waffle.Looks.colors.subfg : (abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : Qt.alpha("#000000", .66)) : Appearance.angelEverywhere ? Appearance.angel.colTextSecondary : alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colSubtext)
    readonly property color colCardBase: ColorUtils.applyAlpha(
        Qt.color(Appearance.colors.colLayer1Base).valid
            ? Appearance.colors.colLayer1Base
            : Appearance.colors.colLayer0Base,
        1.0
    )
    readonly property real tonalDir: Qt.color(root.colCardBase).hslLightness > 0.86 ? -1 : 1
    readonly property color colHoverTonal: ColorUtils.applyAlpha(
        ColorUtils.tonalStep(root.colCardBase, root.tonalDir * 0.044, 1.07),
        0.92
    )

    component HeaderButton: RippleButton {
        id: headerButton
        property alias iconName: headerSymbol.text
        property string tooltip: ""
        implicitWidth: root.waffleMenu ? (root.narrow ? 30 : 34) : (root.narrow ? 30 : 38)
        implicitHeight: root.waffleMenu ? (root.narrow ? 30 : 34) : (root.narrow ? 30 : 38)
        buttonRadius: root.waffleMenu ? Waffle.Looks.radius.medium : (toggled ? Appearance.rounding.normal : Appearance.rounding.full)
        colBackground: root.waffleMenu
            ? Waffle.Looks.colors.bg1
            : (root.abyss ? Qt.alpha(AbyssStyle.accent, .05) : Appearance.angelEverywhere ? Appearance.angel.colGlassCard : root.alisEverywhere ? Appearance.alis.colLayer1 : root.auroraEverywhere ? Appearance.aurora.colSubSurface : Appearance.colors.colLayer1)
        colBackgroundHover: root.waffleMenu
            ? Waffle.Looks.colors.bg1Hover
            : (root.abyss ? Qt.alpha(AbyssStyle.accent, .12) : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover : root.alisEverywhere ? Appearance.alis.colLayer1Hover : root.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover : Appearance.colors.colLayer1Hover)
        colBackgroundToggled: root.waffleMenu ? Waffle.Looks.colors.accent : Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: root.waffleMenu ? Waffle.Looks.colors.accentHover : Appearance.colors.colSecondaryContainerHover
        Behavior on buttonRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        Rectangle {
            anchors.fill: parent
            radius: headerButton.buttonEffectiveRadius
            color: "transparent"
            visible: root.waffleMenu
            border.width: 1
            border.color: headerButton.toggled ? Waffle.Looks.colors.accent : Waffle.Looks.colors.bg1Border
        }
        contentItem: MaterialSymbol {
            id: headerSymbol
            anchors.centerIn: parent
            iconSize: 20
            horizontalAlignment: Text.AlignHCenter
            color: headerButton.toggled
                ? (root.waffleMenu ? Waffle.Looks.colors.accentFg : Appearance.colors.colOnSecondaryContainer)
                : root.colText
        }
        StyledToolTip {
            text: headerButton.tooltip
        }
    }

    RowLayout {
        id: actions
        visible: root.showActions
        anchors.right: parent.right
        anchors.verticalCenter: root.separateNavigation ? undefined : parent.verticalCenter
        anchors.top: root.separateNavigation ? parent.top : undefined
        spacing: root.narrow ? 3 : 8

        HeaderButton {
            objectName: "dashboardEditLayoutButton"
            enabled: root.pageCount > 0
            iconName: root.editMode ? "done" : "edit"
            tooltip: root.editMode ? Translation.tr("Done editing") : Translation.tr("Edit widgets")
            toggled: root.editMode
            onClicked: root.editModeRequested()
        }
        HeaderButton {
            iconName: "notifications_paused"
            tooltip: Translation.tr("Do Not Disturb")
            toggled: Notifications.silent
            onClicked: Notifications.toggleSilent()
        }
        HeaderButton {
            iconName: "wallpaper"
            tooltip: Translation.tr("Wallpapers")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.overviewOpen = false;
                GlobalStates.wallpaperSelectorOpen = true;
            }
        }
        HeaderButton {
            iconName: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.overviewOpen = false;
                if (GlobalStates.useSettingsOverlay()) {
                    GlobalStates.settingsOverlayTargetOutput = GlobalStates.resolveOutputName("", []);
                    GlobalStates.settingsOverlayRequestedSection = "";
                    GlobalStates.settingsOverlayRequestedPage = -1;
                    GlobalStates.settingsOverlayOpen = true;
                } else {
                    Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings-window"]);
                }
            }
        }
        HeaderButton {
            visible: root.showPowerButtons
            iconName: "lock"
            tooltip: Translation.tr("Lock")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.overviewOpen = false;
                GlobalStates.screenLocked = true;
            }
        }
        HeaderButton {
            visible: root.showPowerButtons
            iconName: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.overviewOpen = false;
                GlobalStates.sessionOpen = true;
            }
        }
    }
    Flickable {
        id: menuNavigation
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 32
        visible: root.separateNavigation
        clip: true
        contentWidth: Math.max(width, pages.width + (root.editMode ? 40 : 0))
        contentHeight: height
        interactive: visible && contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick

        function revealCurrentPage() {
            if (!interactive) {
                contentX = 0
                return
            }
            const tabItem = pageRepeater.itemAt(root.currentPage)
            const left = pages.x + (tabItem ? tabItem.x : root.currentPage * (root.pageDotButtonWidth + pages.spacing))
            const tabWidth = tabItem ? tabItem.width : root.pageDotButtonWidth
            contentX = Math.min(Math.max(0, contentWidth - width),
                Math.max(0, Math.min(left, Math.max(contentX, left + tabWidth - width))))
        }
        onContentWidthChanged: Qt.callLater(revealCurrentPage)
        onWidthChanged: Qt.callLater(revealCurrentPage)
        Connections {
            target: root
            function onCurrentPageChanged() { menuNavigation.revealCurrentPage() }
        }
        Item { id: menuStrip; width: menuNavigation.contentWidth; height: menuNavigation.height }
    }
    RowLayout {
        id: pages
        parent: root.separateNavigation ? menuStrip : root
        objectName: "dashboardPageDots"
        z: 1
        anchors.centerIn: parent
        spacing: 4
        width: pageDotsRow.implicitWidth
        visible: root.pageCount > 1
        Row {
            id: pageDotsRow
            Layout.alignment: Qt.AlignVCenter
            spacing: pages.spacing
            Repeater {
                id:pageRepeater
                model: root.pageCount
                onItemAdded: pageDotsRow.forceLayout()
                onItemRemoved: pageDotsRow.forceLayout()
                onCountChanged: pageDotsRow.forceLayout()
                delegate: RippleButton {
                    id:pageButton
                    required property int index
                    readonly property string pageId: String(root.pageIds[index] ?? "")
                    readonly property real selectedBlend: Math.max(0, 1 - Math.abs(root.indicatorProgress - index))
                    objectName: "dashboardPage" + index
                    implicitWidth: root.waffleMenu ? Math.max(56, waffleTabRow.implicitWidth + 18) : root.pageDotButtonWidth
                    implicitHeight: root.waffleMenu ? 28 : 32
                    buttonRadius: root.waffleMenu ? Waffle.Looks.radius.medium : 16
                    enabled: root.reorderAllowed || (root.navigationAllowed && !root.editMode)
                    focusPolicy: Qt.TabFocus
                    Accessible.name:root.pageLabel(pageId)
                    colBackground: root.waffleMenu
                        ? (index === root.currentPage ? Waffle.Looks.colors.bg1 : "transparent")
                        : (pageDragMouse.pressed && index !== root.currentPage
                            ? Appearance.colors.colPrimaryContainer
                            : (pageDragMouse.containsMouse && index !== root.currentPage
                                ? root.colHoverTonal : "transparent"))
                    colBackgroundHover: root.waffleMenu
                        ? Waffle.Looks.colors.bg1Hover
                        : (index === root.currentPage ? Appearance.colors.colPrimaryContainerHover : root.colHoverTonal)
                    contentItem: Item {
                        MaterialSymbol {
                            id: pageIconSymbol
                            objectName: "dashboardPageIcon" + index
                            visible: !root.waffleMenu
                            anchors.centerIn: parent
                            text: root.pageIcon(pageButton.pageId)
                            iconSize: root.pageIconSize
                            fill: pageButton.selectedBlend
                            horizontalAlignment: Text.AlignHCenter
                            color: pageDragMouse.pressed && index !== root.currentPage
                                ? Appearance.colors.colOnPrimaryContainer
                                : ColorUtils.mix(
                                    Appearance.colors.colOnPrimaryContainer,
                                    (pageButton.hovered || pageDragMouse.containsMouse) ? root.colText : root.colSubtext,
                                    1 - pageButton.selectedBlend
                                )
                        }
                        Row {
                            id: waffleTabRow
                            visible: root.waffleMenu
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol {
                                visible: root.waffleMenu
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.pageIcon(pageButton.pageId)
                                iconSize: 14
                                fill: pageButton.index === root.currentPage ? 1 : 0
                                horizontalAlignment: Text.AlignHCenter
                                color: pageButton.index === root.currentPage ? root.colText : root.colSubtext
                            }
                            StyledText {
                                id: waffleTabLabel
                                visible: root.waffleMenu
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.pageLabel(pageButton.pageId)
                                font.family: Waffle.Looks.font.family.ui
                                font.pixelSize: Waffle.Looks.font.pixelSize.small
                                font.weight: pageButton.index === root.currentPage ? Font.DemiBold : Font.Normal
                                color: pageButton.index === root.currentPage ? root.colText : root.colSubtext
                            }
                        }
                    }
                    onClicked: if(!root.editMode && root.navigationAllowed)root.pageRequested(index)
                    Keys.onPressed: event => {
                        if(root.reorderAllowed && (event.modifiers & Qt.AltModifier)
                                && (event.key===Qt.Key_Left || event.key===Qt.Key_Right)) {
                            if (event.isAutoRepeat || root.pageSlideInFlight) {
                                event.accepted = true
                                return
                            }
                            root.moveFocusedPage(root.pageIds[index],index+(event.key===Qt.Key_Left?-1:1))
                            event.accepted=true
                        }else if(event.key===Qt.Key_Escape && root.cancelPageDrag())event.accepted=true
                        else event.accepted=false
                    }
                    MouseArea {
                        id: pageDragMouse
                        anchors.fill:parent
                        enabled:root.reorderAllowed
                        hoverEnabled:true
                        cursorShape:pressed?Qt.ClosedHandCursor:Qt.OpenHandCursor
                        onPressed: mouse => {
                            pageButton.forceActiveFocus(Qt.MouseFocusReason)
                            const point=mapToItem(root,mouse.x,mouse.y)
                            root.dragPageOrder=JSON.stringify(root.pageIds)
                            root.dragPageId=root.pageIds[pageButton.index]
                            root.dragPress=point;root.dragPointer=point;root.dragTarget=pageButton.index
                        }
                        onPositionChanged:mouse=>{if(pressed)root.updatePageDrag(mapToItem(root,mouse.x,mouse.y))}
                        onReleased:mouse=>root.finishPageDrag(mapToItem(root,mouse.x,mouse.y))
                        onCanceled:root.cancelPageDrag()
                    }
                    StyledToolTip {
                        text:parent.Accessible.name+(root.editMode?" · "+Translation.tr("Drag to reorder; Alt+Left/Right also moves tabs") : "")
                    }
                }
            }
        }
    }
    Rectangle {
        id: activePageIndicator
        objectName: "dashboardActivePageIndicator"
        parent: root.separateNavigation ? menuStrip : root
        z: root.waffleMenu ? 10 : 0
        readonly property Item currentTabItem: (root.currentPage >= 0 && root.currentPage < pageRepeater.count)
            ? pageRepeater.itemAt(root.currentPage) : null
        width: root.waffleMenu
            ? Math.max(16, (currentTabItem?.width ?? 36) - 18)
            : root.pageDotButtonWidth
        height: root.waffleMenu ? 3 : 30
        radius: root.waffleMenu ? 1.5 : height / 2
        color: root.waffleMenu ? Waffle.Looks.colors.accent : Appearance.colors.colPrimaryContainer
        visible: pages.visible && root.currentPage >= 0
            && root.currentPage < root.pageCount
        anchors.verticalCenter: root.waffleMenu ? undefined : pages.verticalCenter
        anchors.bottom: root.waffleMenu ? pages.bottom : undefined
        // Use the *same* position animated by Dashboard's page strip: this
        // removes the one-frame extinguish/relight effect and cannot lag,
        // overshoot separately, or trigger any additional animation work.
        x: root.waffleMenu
            ? pages.x + (currentTabItem ? currentTabItem.x + Math.round((currentTabItem.width - width) / 2) : 0)
            : pages.x + (root.pageDotButtonWidth - width) / 2
                + Math.max(0, Math.min(root.pageCount - 1, root.indicatorProgress))
                    * (root.pageDotButtonWidth + pages.spacing)
        Behavior on x {
            enabled: root.waffleMenu && Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
    }
    MaterialSymbol {
        id: tabReorderHandle
        objectName: "dashboardTabReorderHandle"
        parent: root.separateNavigation ? menuStrip : root
        visible:root.reorderAllowed
        anchors.right:pages.left;anchors.rightMargin:2
        anchors.verticalCenter:pages.verticalCenter
        text:"drag_indicator";iconSize:16;color:root.colSubtext
    }
    Rectangle {
        objectName:"dashboardTabInsertion"
        parent: root.separateNavigation ? menuStrip : root
        visible:root.draggingPage && root.dragTarget>=0
        x:pages.x+(pageRepeater.itemAt(root.dragTarget)?.x ?? 0)
            +(root.dragTarget>root.pageIds.indexOf(root.dragPageId)?(pageRepeater.itemAt(root.dragTarget)?.width ?? root.pageDotButtonWidth):0)-2
        y:pages.y+6;width:2;height:20;radius:1;color:root.colText
    }
    Rectangle {
        objectName:"dashboardTabDragGhost"
        visible:root.draggingPage
        x:Math.max(0,Math.min(root.width-width,root.dragPointer.x-width/2))
        y:root.dragPointer.y+14;width:ghostLabel.implicitWidth+24;height:28;radius:14;z:20
        color:root.abyss?AbyssStyle.contentLayer:Appearance.colors.colLayer1
        border.width:1;border.color:Qt.alpha(root.colText,.4)
        StyledText {id:ghostLabel;anchors.centerIn:parent;text:root.pageLabel(root.dragPageId);color:root.colText;font.pixelSize:Appearance.font.pixelSize.smallest}
    }
    RowLayout {
        id: uptime
        visible: root.showActions
        anchors.left: parent.left
        anchors.verticalCenter: root.separateNavigation ? undefined : parent.verticalCenter
        anchors.top: root.separateNavigation ? parent.top : undefined
        height: root.separateNavigation ? actions.height : implicitHeight
        width: Math.min(implicitWidth, Math.max(0, root.separateNavigation
            ? actions.x - 8 : Math.min(pages.x - 12, root.width / 2 - pages.width / 2 - 12)))
        spacing: 8

        MaterialSymbol {
            text: "timelapse"
            iconSize: 20
            color: root.colSubtext
        }
        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            text: Translation.tr("Uptime: %1").arg(DateTime.uptime)
            font.family: root.waffleMenu ? Waffle.Looks.font.family.ui : Appearance.font.family.main
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colSubtext
        }
    }
}
