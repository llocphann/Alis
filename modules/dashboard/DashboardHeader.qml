import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks

/**
 * Dashboard navigation: uptime at left, page dots at center, actions at right.
 */
Item {
    id: root
    // Page dots remain when actions are hidden. A hidden RowLayout can report
    // a new implicit size after Edit changes its children; it must not resize
    // the visible page header or the widget canvas.
    implicitHeight: Math.max(32, showActions ? actions.implicitHeight : 0)

    property bool editMode: false
    property bool showActions: true
    property int currentPage: 0
    property int pageCount: 1
    property var pageIds: ["dashboard", "music"]
    property var customTabs: []
    property string defaultTabId: "dashboard"
    property bool navigationAllowed: true
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
    signal createTabRequested()
    signal setDefaultTabRequested(string id)
    signal renameTabRequested(string id)
    signal deleteTabRequested(string id)
    signal editModeRequested
    signal horizontalWheel(var event)
    function pageLabel(id): string {
        if(id==="dashboard") return Translation.tr("Dashboard")
        if(id==="music") return Translation.tr("Music")
        if(id==="weeklyPlanner") return Translation.tr("Weekly Planner")
        return root.customTabs.find(tab => tab.id === id)?.name ?? String(id ?? "")
    }
    function focusMovedPage(): void {
        const index=pageIds.indexOf(_movedPageId)
        if(reorderAllowed && index>=0)pageRepeater.itemAt(index)?.forceActiveFocus()
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
        const id=dragPageId,target=dragTarget
        const accept=draggingPage && reorderAllowed && position.x>=0 && position.x<=width
            && position.y>=-16 && position.y<=height+16
        cancelPageDrag()
        if(accept)moveFocusedPage(id,target)
    }
    onReorderAllowedChanged: if(!reorderAllowed)cancelPageDrag()
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
        if (root.navigationAllowed && !root.editMode && root.currentPage > 0) {
            root.pageRequested(root.currentPage - 1)
            event.accepted = true
        } else event.accepted = false
    }
    Keys.onRightPressed: event => {
        if (root.navigationAllowed && !root.editMode && root.currentPage < root.pageCount - 1) {
            root.pageRequested(root.currentPage + 1)
            event.accepted = true
        } else event.accepted = false
    }

    readonly property bool alisEverywhere: Appearance.alisEverywhere
    readonly property bool auroraEverywhere: Appearance.auroraEverywhere
    readonly property bool showPowerButtons: Config.options?.dashboard?.showPowerButtons ?? true
    readonly property color colText: abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000") : Appearance.angelEverywhere ? Appearance.angel.colText : alisEverywhere ? Appearance.alis.colText : Appearance.colors.colOnLayer0
    readonly property color colSubtext: abyss ? (Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : Qt.alpha("#000000", .66)) : Appearance.angelEverywhere ? Appearance.angel.colTextSecondary : alisEverywhere ? Appearance.alis.colTextSecondary : Appearance.colors.colSubtext

    component HeaderButton: RippleButton {
        id: headerButton
        property alias iconName: headerSymbol.text
        property string tooltip: ""
        implicitWidth: root.narrow ? 30 : 38
        implicitHeight: root.narrow ? 30 : 38
        buttonRadius: toggled ? Appearance.rounding.normal : Appearance.rounding.full
        colBackground: root.abyss ? Qt.alpha(AbyssStyle.accent, .05) : Appearance.angelEverywhere ? Appearance.angel.colGlassCard : root.alisEverywhere ? Appearance.alis.colLayer1 : root.auroraEverywhere ? Appearance.aurora.colSubSurface : Appearance.colors.colLayer1
        colBackgroundHover: root.abyss ? Qt.alpha(AbyssStyle.accent, .12) : Appearance.angelEverywhere ? Appearance.angel.colGlassCardHover : root.alisEverywhere ? Appearance.alis.colLayer1Hover : root.auroraEverywhere ? Appearance.aurora.colSubSurfaceHover : Appearance.colors.colLayer1Hover
        colBackgroundToggled: Appearance.colors.colSecondaryContainer
        colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
        Behavior on buttonRadius {
            enabled: Appearance.animationsEnabled
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        contentItem: MaterialSymbol {
            id: headerSymbol
            anchors.centerIn: parent
            iconSize: 20
            horizontalAlignment: Text.AlignHCenter
            color: headerButton.toggled ? Appearance.colors.colOnSecondaryContainer : root.colText
        }
        StyledToolTip {
            text: headerButton.tooltip
        }
    }

    RowLayout {
        id: actions
        visible: root.showActions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.narrow ? 3 : 8

        HeaderButton {
            enabled: root.pageIds[root.currentPage] === "dashboard"
                || root.pageIds[root.currentPage]?.startsWith("custom-")
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
                GlobalStates.wallpaperSelectorOpen = true;
            }
        }
        HeaderButton {
            iconName: "settings"
            tooltip: Translation.tr("Settings")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                Quickshell.execDetached([Quickshell.shellPath("scripts/alis"), "settings"]);
            }
        }
        HeaderButton {
            visible: root.showPowerButtons
            iconName: "lock"
            tooltip: Translation.tr("Lock")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.screenLocked = true;
            }
        }
        HeaderButton {
            visible: root.showPowerButtons
            iconName: "power_settings_new"
            tooltip: Translation.tr("Session")
            onClicked: {
                GlobalStates.dashboardOpen = false;
                GlobalStates.sessionOpen = true;
            }
        }
    }
    RowLayout {
        id: pages
        objectName: "dashboardPageDots"
        anchors.centerIn: parent
        spacing: 4
        visible: root.pageCount > 1
        Repeater {
            id:pageRepeater
            model: root.pageCount
            delegate: RippleButton {
                id:pageButton
                required property int index
                objectName: "dashboardPage" + index
                implicitWidth: 24
                implicitHeight: 32
                buttonRadius: 16
                enabled: root.reorderAllowed || (root.navigationAllowed && !root.editMode)
                focusPolicy:Qt.StrongFocus
                Accessible.name:root.pageLabel(root.pageIds[index])
                colBackground: "transparent"
                colBackgroundHover: Qt.alpha(root.colText, .08)
                contentItem: Item {
                    Rectangle {
                        objectName: "dashboardPageDot" + index
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        color: index === root.currentPage ? root.colText : Qt.alpha(root.colText, .35)
                    }
                }
                onClicked: if(!root.editMode && root.navigationAllowed)root.pageRequested(index)
                Keys.onPressed: event => {
                    if(root.reorderAllowed && (event.modifiers & Qt.AltModifier)
                            && (event.key===Qt.Key_Left || event.key===Qt.Key_Right)) {
                        root.moveFocusedPage(root.pageIds[index],index+(event.key===Qt.Key_Left?-1:1))
                        event.accepted=true
                    }else if(event.key===Qt.Key_Escape && root.cancelPageDrag())event.accepted=true
                    else event.accepted=false
                }
                Rectangle {
                    anchors.fill:parent;anchors.margins:2;radius:12;color:"transparent"
                    border.width:pageButton.activeFocus?1:0;border.color:root.colText
                }
                MouseArea {
                    anchors.fill:parent
                    enabled:root.reorderAllowed
                    cursorShape:pressed?Qt.ClosedHandCursor:Qt.OpenHandCursor
                    onPressed: mouse => {
                        pageButton.forceActiveFocus()
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
        // All controls are inside the centered page group, so the combined
        // indicator/actions block stays centered in every display mode.
        Row {
        id: customTabActions
        objectName: "dashboardCustomTabActions"
        Layout.alignment: Qt.AlignVCenter
        spacing: 2
        z: 10
        visible: root.pageCount > 0
        RippleButton {
            id: defaultTabButton
            objectName: "dashboardSetDefaultTab"
            implicitWidth: 29
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            readonly property bool isDefault:
                root.pageIds[root.currentPage] === root.defaultTabId
            toggled: isDefault
            enabled: root.pageIds[root.currentPage] !== undefined
            focusPolicy: Qt.StrongFocus
            colBackground: "transparent"
            colBackgroundHover: Qt.alpha(root.colText, .08)
            onClicked: root.setDefaultTabRequested(root.pageIds[root.currentPage])
            contentItem: MaterialSymbol {
                text: "home"
                iconSize: 19
                color: defaultTabButton.isDefault ? Appearance.colors.colPrimary : root.colText
            }
            StyledToolTip {
                text: defaultTabButton.isDefault
                    ? Translation.tr("Default tab after inactivity")
                    : Translation.tr("Set this as default tab after inactivity")
            }
        }
        RippleButton {
            objectName: "dashboardCreateCustomTab"
            visible: root.editMode
            implicitWidth: 28
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            enabled: root.editMode
            focusPolicy: Qt.StrongFocus
            colBackground: "transparent"
            colBackgroundHover: Qt.alpha(root.colText, .08)
            onClicked: root.createTabRequested()
            contentItem: MaterialSymbol {
                text: "add"
                iconSize: 20
                color: root.colText
            }
            StyledToolTip { text: Translation.tr("Create custom tab") }
        }
        RippleButton {
            objectName: "dashboardRenameCustomTab"
            visible: root.pageIds[root.currentPage]?.startsWith("custom-") && root.editMode
            implicitWidth: 27
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Qt.alpha(root.colText, .08)
            onClicked: root.renameTabRequested(root.pageIds[root.currentPage])
            contentItem: MaterialSymbol {
                text: "drive_file_rename_outline"
                iconSize: 17
                color: root.colText
            }
            StyledToolTip { text: Translation.tr("Rename custom tab") }
        }
        RippleButton {
            objectName: "dashboardDeleteCustomTab"
            visible: root.pageIds[root.currentPage]?.startsWith("custom-") && root.editMode
            implicitWidth: 27
            implicitHeight: 30
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Qt.alpha(root.colText, .08)
            onClicked: root.deleteTabRequested(root.pageIds[root.currentPage])
            contentItem: MaterialSymbol {
                text: "delete_outline"
                iconSize: 17
                color: root.colText
            }
            StyledToolTip { text: Translation.tr("Delete custom tab") }
        }
    }
    }
    MaterialSymbol {
        visible:root.reorderAllowed
        anchors.right:pages.left;anchors.rightMargin:2;anchors.verticalCenter:pages.verticalCenter
        text:"drag_indicator";iconSize:16;color:root.colSubtext
    }
    Rectangle {
        objectName:"dashboardTabInsertion"
        visible:root.draggingPage && root.dragTarget>=0
        x:pages.x+(pageRepeater.itemAt(root.dragTarget)?.x ?? 0)
            +(root.dragTarget>root.pageIds.indexOf(root.dragPageId)?24:0)-2
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
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0, root.width / 2 - pages.width / 2 - 12))
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
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.colSubtext
        }
    }
}
