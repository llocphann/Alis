pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Options toolbar — unified snip controls: pick the action and the region shape
// inline, plus instant fullscreen capture and color picker.
Toolbar {
    id: root

    // Ordinals mirror RegionSelection.SnipAction & RegionSelection.SelectionMode.
    // Using explicit integer constants avoids QML enum resolution order races
    // when RegionSelection instantiates OptionsToolbar.
    readonly property int actionCopy: 0
    readonly property int actionEdit: 1
    readonly property int actionSearch: 2
    readonly property int actionCharRecognition: 3
    readonly property int actionRecord: 4
    readonly property int actionRecordWithSound: 5
    readonly property int modeRectCorners: 0
    readonly property int modeCircle: 1

    // Use a synchronizer on these
    property int action: root.actionCopy
    property int selectionMode: root.modeRectCorners
    property bool _syncingBars: false
    // Signals
    signal dismiss()
    signal fullscreenRequested()
    signal colorPickerRequested()

    // Region actions selectable in-overlay (order = tab index)
    readonly property var actionList: [
        { "action": root.actionCopy,            "icon": "content_cut",      "name": Translation.tr("Shot") },
        { "action": root.actionEdit,            "icon": "draw",             "name": Translation.tr("Edit") },
        { "action": root.actionCharRecognition, "icon": "document_scanner", "name": Translation.tr("OCR") },
        { "action": root.actionSearch,          "icon": "image_search",     "name": Translation.tr("Search") },
        { "action": root.actionRecord,          "icon": "videocam",         "name": Translation.tr("Record") }
    ]
    function indexForAction(a) {
        const list = root.actionList ?? []
        for (let i = 0; i < list.length; i++)
            if (list[i].action === a) return i;
        return 0;
    }

    function syncBarsFromProperties(): void {
        root._syncingBars = true
        actionBar.setCurrentIndex(root.indexForAction(root.action))
        modeBar.setCurrentIndex(root.selectionMode === root.modeRectCorners ? 0 : 1)
        root._syncingBars = false
    }

    function persistSnipChoice(): void {
        if (!(Config.options?.regionSelector?.rememberSnipChoice ?? true)) return
        const isRecord = root.action === root.actionRecord
            || root.action === root.actionRecordWithSound
        const updates = { "regionSelector.lastMode": root.selectionMode }
        if (!isRecord) updates["regionSelector.lastAction"] = root.action
        Config.setNestedValues(updates)
    }

    // Action selector
    ToolbarTabBar {
        id: actionBar
        objectName: "regionActionTabBar"
        Layout.alignment: Qt.AlignVCenter
        compactThreshold: 6
        tabButtonList: (root.actionList ?? []).map(a => ({"icon": a.icon, "name": a.name}))
        onCurrentIndexChanged: {
            if (root._syncingBars) return;
            const a = root.actionList?.[currentIndex]?.action;
            if (a !== undefined && a !== root.action) root.action = a;
        }
        onUserSelected: root.persistSnipChoice()
    }

    // Region shape (applies when drawing a region)
    ToolbarTabBar {
        id: modeBar
        objectName: "regionModeTabBar"
        Layout.alignment: Qt.AlignVCenter
        compactThreshold: 4
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        onCurrentIndexChanged: {
            if (root._syncingBars) return;
            const nextMode = currentIndex === 0 ? root.modeRectCorners : root.modeCircle;
            if (root.selectionMode !== nextMode) root.selectionMode = nextMode;
        }
        onUserSelected: root.persistSnipChoice()
    }

    // Instant tools (no region selection needed)
    FloatingActionButton {
        Layout.alignment: Qt.AlignVCenter
        baseSize: 40
        iconText: "fullscreen"
        onClicked: root.fullscreenRequested()
        StyledToolTip { text: Translation.tr("Capture fullscreen") }
        colBackground: Appearance.zzzEverywhere ? Appearance.zzz.sticker : Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        colOnBackground: Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnSecondaryContainer
    }
    FloatingActionButton {
        Layout.alignment: Qt.AlignVCenter
        baseSize: 40
        iconText: "colorize"
        onClicked: root.colorPickerRequested()
        StyledToolTip { text: Translation.tr("Color picker") }
        colBackground: Appearance.zzzEverywhere ? Appearance.zzz.sticker : Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryHover : Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.zzzEverywhere ? Appearance.colors.colPrimaryActive : Appearance.colors.colSecondaryContainerActive
        colOnBackground: Appearance.zzzEverywhere ? Appearance.zzz.onSticker : Appearance.colors.colOnSecondaryContainer
    }

    onActionChanged: root.syncBarsFromProperties()
    onSelectionModeChanged: root.syncBarsFromProperties()

    Component.onCompleted: {
        root.syncBarsFromProperties()
    }
}
