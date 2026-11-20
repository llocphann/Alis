pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.abyss.looks
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Compact options toolbar matching RecordingControls proportions (30px controls / 38px Abyss host).
Toolbar {
    id: root

    // Ordinals mirror RegionSelection.SnipAction & RegionSelection.SelectionMode.
    readonly property int actionCopy: 0
    readonly property int actionEdit: 1
    readonly property int actionSearch: 2
    readonly property int actionCharRecognition: 3
    readonly property int actionRecord: 4
    readonly property int actionRecordWithSound: 5
    readonly property int modeRectCorners: 0
    readonly property int modeCircle: 1

    property int action: root.actionCopy
    property int selectionMode: root.modeRectCorners
    property string annotationTool: ""
    property color annotationColor: Appearance.colors.colPrimary
    property real annotationStrokeWidth: 4
    property bool hasAnnotations: false
    property bool canUndo: false
    property bool canRedo: false
    property bool stylePopoverOpen: false
    property bool _syncingBars: false

    signal dismiss()
    signal fullscreenRequested()
    signal colorPickerRequested()
    signal undoRequested()
    signal redoRequested()
    signal clearAnnotationsRequested()
    signal saveAnnotatedRequested()

    padding: transparent ? 0 : 4
    spacing: 2
    minBackgroundHeight: transparent ? 30 : 38
    radius: Config.options?.panelFamily === "abyss" ? 16 : height / 2

    readonly property var actionList: [
        { "action": root.actionCopy,            "icon": "content_cut",      "name": Translation.tr("Shot") },
        { "action": root.actionEdit,            "icon": "draw",             "name": Translation.tr("Edit") },
        { "action": root.actionCharRecognition, "icon": "document_scanner", "name": Translation.tr("OCR") },
        { "action": root.actionSearch,          "icon": "image_search",     "name": Translation.tr("Search") },
        { "action": root.actionRecord,          "icon": "videocam",         "name": Translation.tr("Record") }
    ]

    readonly property var annotationTools: [
        { "tool": "pen",       "icon": "edit",                   "tip": Translation.tr("Pen (1)") },
        { "tool": "arrow",     "icon": "north_east",             "tip": Translation.tr("Arrow (2)") },
        { "tool": "rect",      "icon": "rectangle",              "tip": Translation.tr("Rectangle (3)") },
        { "tool": "ellipse",   "icon": "radio_button_unchecked", "tip": Translation.tr("Ellipse (4)") },
        { "tool": "highlight", "icon": "ink_highlighter",        "tip": Translation.tr("Highlighter (5)") },
        { "tool": "text",      "icon": "title",                  "tip": Translation.tr("Text (6)") },
        { "tool": "pixelate",  "icon": "blur_on",                "tip": Translation.tr("Pixelate (7)") },
        { "tool": "step",      "icon": "looks_one",              "tip": Translation.tr("Step badge (8)") }
    ]

    function indexForAction(a) {
        const list = root.actionList ?? [];
        for (let i = 0; i < list.length; i++)
            if (list[i].action === a) return i;
        return 0;
    }

    function syncBarsFromProperties(): void {
        root._syncingBars = true;
        actionBar.setCurrentIndex(root.indexForAction(root.action));
        modeBar.setCurrentIndex(root.selectionMode === root.modeRectCorners ? 0 : 1);
        root._syncingBars = false;
    }

    function persistSnipChoice(): void {
        if (!(Config.options?.regionSelector?.rememberSnipChoice ?? true)) return;
        const isRecord = root.action === root.actionRecord
            || root.action === root.actionRecordWithSound;
        const updates = { "regionSelector.lastMode": root.selectionMode };
        if (!isRecord) updates["regionSelector.lastAction"] = root.action;
        Config.setNestedValues(updates);
    }

    component CompactBarDivider: Rectangle {
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: 2
        Layout.rightMargin: 2
        implicitWidth: 1
        implicitHeight: 20
        color: Appearance.colors.colOutlineVariant
        opacity: 0.35
    }

    component CompactToolButton: RippleButton {
        id: btn
        required property string iconName
        property string tooltipText: ""
        property bool filledIcon: false
        property bool emphasized: false
        property color customIconColor: Appearance.colors.colOnLayer2
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: (Config.options?.panelFamily === "abyss") ? 12 : Appearance.rounding.full
        colBackground: emphasized
            ? Appearance.colors.colPrimary
            : (toggled ? Qt.alpha(AbyssStyle.accent, 0.24) : "transparent")
        colBackgroundHover: emphasized
            ? Appearance.colors.colPrimaryHover
            : Qt.alpha(AbyssStyle.accent, 0.16)
        colBackgroundToggled: Qt.alpha(AbyssStyle.accent, 0.24)
        colBackgroundToggledHover: Qt.alpha(AbyssStyle.accent, 0.32)
        colRipple: Qt.alpha(AbyssStyle.accent, 0.24)
        colRippleToggled: Qt.alpha(AbyssStyle.accent, 0.36)
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: btn.iconName
            iconSize: 17
            fill: (btn.filledIcon || btn.toggled || btn.emphasized) ? 1 : 0
            animateFill: true
            color: btn.emphasized
                ? Appearance.colors.colOnPrimary
                : (btn.toggled ? Appearance.colors.colPrimary : btn.customIconColor)
        }
        StyledToolTip {
            text: btn.tooltipText
            visible: btn.tooltipText.length > 0 && btn.buttonHovered
        }
    }

    ToolbarTabBar {
        id: actionBar
        objectName: "regionActionTabBar"
        Layout.alignment: Qt.AlignVCenter
        barHeight: 30
        tabIconSize: 16
        tabHorizontalPadding: 7
        tabLabelPixelSize: Appearance.font.pixelSize.smaller
        compactButtonSpacing: 2
        tabRadius: (Config.options?.panelFamily === "abyss") ? 12 : -1
        compactThreshold: 6
        tabButtonList: (root.actionList ?? []).map(a => ({ "icon": a.icon, "name": a.name }))
        onCurrentIndexChanged: {
            if (root._syncingBars) return;
            const a = root.actionList?.[currentIndex]?.action;
            if (a !== undefined && a !== root.action) root.action = a;
            if (root.annotationTool.length > 0) root.annotationTool = "";
        }
        onUserSelected: {
            if (root.annotationTool.length > 0) root.annotationTool = "";
            root.persistSnipChoice();
        }
    }

    ToolbarTabBar {
        id: modeBar
        objectName: "regionModeTabBar"
        Layout.alignment: Qt.AlignVCenter
        barHeight: 30
        tabIconSize: 16
        tabHorizontalPadding: 7
        tabLabelPixelSize: Appearance.font.pixelSize.smaller
        compactButtonSpacing: 2
        tabRadius: (Config.options?.panelFamily === "abyss") ? 12 : -1
        compactThreshold: 2
        tabButtonList: [
            { "icon": "activity_zone", "name": Translation.tr("Rect") },
            { "icon": "gesture", "name": Translation.tr("Circle") }
        ]
        onCurrentIndexChanged: {
            if (root._syncingBars) return;
            const nextMode = currentIndex === 0 ? root.modeRectCorners : root.modeCircle;
            if (root.selectionMode !== nextMode) root.selectionMode = nextMode;
        }
        onUserSelected: root.persistSnipChoice()
    }

    CompactBarDivider {}

    Repeater {
        model: root.annotationTools
        delegate: CompactToolButton {
            required property var modelData
            iconName: modelData.icon
            tooltipText: modelData.tip
            toggled: root.annotationTool === modelData.tool
            onClicked: {
                root.annotationTool = (root.annotationTool === modelData.tool) ? "" : modelData.tool;
                if (root.annotationTool.length === 0)
                    root.stylePopoverOpen = false;
            }
        }
    }

    // Compact color + stroke toggle pill
    RippleButton {
        id: styleButton
        objectName: "screenshotStyleButton"
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: 30
        implicitHeight: 30
        buttonRadius: (Config.options?.panelFamily === "abyss") ? 12 : Appearance.rounding.full
        toggled: root.stylePopoverOpen
        colBackground: toggled ? Qt.alpha(AbyssStyle.accent, 0.22) : "transparent"
        colBackgroundHover: Qt.alpha(AbyssStyle.accent, 0.16)
        colBackgroundToggled: Qt.alpha(AbyssStyle.accent, 0.22)
        colRipple: Qt.alpha(AbyssStyle.accent, 0.24)
        onClicked: root.stylePopoverOpen = !root.stylePopoverOpen
        contentItem: Item {
            Rectangle {
                anchors.centerIn: parent
                width: Math.max(10, Math.min(18, Math.round(9 + root.annotationStrokeWidth)))
                height: width
                radius: width / 2
                color: root.annotationColor
                border.width: 1.5
                border.color: Appearance.colors.colOnLayer0
            }
        }
        StyledToolTip {
            text: Translation.tr("Color & stroke width")
            visible: styleButton.buttonHovered
        }
    }

    CompactToolButton {
        iconName: "undo"
        tooltipText: Translation.tr("Undo (Ctrl+Z)")
        enabled: root.canUndo
        onClicked: root.undoRequested()
    }

    CompactToolButton {
        iconName: "redo"
        tooltipText: Translation.tr("Redo (Ctrl+Shift+Z)")
        enabled: root.canRedo
        onClicked: root.redoRequested()
    }

    CompactToolButton {
        visible: root.hasAnnotations
        iconName: "delete_sweep"
        tooltipText: Translation.tr("Clear annotations")
        onClicked: root.clearAnnotationsRequested()
    }

    CompactBarDivider {}

    CompactToolButton {
        iconName: "fullscreen"
        tooltipText: Translation.tr("Capture fullscreen")
        onClicked: root.fullscreenRequested()
    }

    CompactToolButton {
        iconName: "colorize"
        tooltipText: Translation.tr("Color picker")
        onClicked: root.colorPickerRequested()
    }

    CompactToolButton {
        visible: root.hasAnnotations
        objectName: "screenshotSaveAnnotatedBtn"
        iconName: "check"
        emphasized: true
        tooltipText: Translation.tr("Save & copy annotated screenshot (Enter)")
        onClicked: root.saveAnnotatedRequested()
    }

    onActionChanged: root.syncBarsFromProperties()
    onSelectionModeChanged: root.syncBarsFromProperties()

    Component.onCompleted: {
        root.syncBarsFromProperties();
    }
}
