pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks
import "../looks/AbyssPresentation.js" as Presentation

ColumnLayout {
    id: root
    Layout.fillWidth: true
    spacing:root.compactIpcEditor ? 5 : 8
    property string kind: "popup"
    property string outputName: ""
    property var positions: Config.options?.abyss?.positions ?? []
    property bool commitImmediately: true
    property bool outputSelectionEnabled: true
    // The embedded IPC editor places kind and output scope in its toolbar.
    property bool showKindSelector: true
    property bool showOutputSelector: true
    property bool compactIpcEditor: false
    // Compact IPC presents type, Edge, alignment and corner toggle together.
    property alias compactKindCombo: compactKindChoice
    property bool compactSideToolbar: false
    // Move the same Join toggle into the side toolbar's Modules/IPC row,
    // without duplicating its checked state or activation handler.
    property Item compactCornerHost: null
    // Size each trigger for its own longest choice. Do not derive the
    // widths from this ColumnLayout's width: that depends on the children's
    // implicit widths and can collapse the three IPC fields to ~72 px.
    FontMetrics {
        id: compactSelectorMetrics
        font.pixelSize: Appearance.font.pixelSize.small
    }
    function compactContentWidth(options): real {
        let widest = 0
        for (const option of options ?? [])
            widest = Math.max(widest, compactSelectorMetrics.advanceWidth(option.label))
        // StyledComboBox: 12px text inset, 6px gap, arrow and 8px right inset.
        return Math.ceil(widest + 32*Appearance.fontSizeScale
            + Appearance.font.pixelSize.normal)
    }
    readonly property real compactKindWidth: compactContentWidth(compactKindChoice.model)
    readonly property real compactEdgeWidth: compactContentWidth(edgeChoice.model)
    readonly property real compactAlignmentWidth: compactContentWidth(alignmentChoice.model)
    function compactTriggerWidth(label, fullWidth): real {
        if (!compactSideToolbar) return fullWidth
        // Side triggers fit the selected text; their opened menus retain
        // the full option width via StyledComboBox.popupMinimumWidth.
        return Math.min(fullWidth,Math.max(86*Appearance.fontSizeScale,
            compactSelectorMetrics.advanceWidth(label || "")
                + 32*Appearance.fontSizeScale + Appearance.font.pixelSize.normal))
    }
    readonly property real compactKindTriggerWidth:
        compactTriggerWidth(compactKindChoice.displayText,compactKindWidth)
    readonly property real compactEdgeTriggerWidth:
        compactTriggerWidth(edgeChoice.displayText,compactEdgeWidth)
    readonly property real compactAlignmentTriggerWidth:
        compactTriggerWidth(alignmentChoice.displayText,compactAlignmentWidth)
    property bool compactVertical: false
    property bool compactActions: false
    property var allowedKinds: []
    readonly property bool ipcOnly: allowedKinds.length > 0 && allowedKinds.every(
        kind => ["osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"].includes(kind))
    property string nearbyEdge: ""
    signal positionsEdited(var positions,string kind,string outputName,var values)
    property var _pendingImmediatePositions: null
    property int _pendingImmediateGeneration: 0
    function _positionsForRead(): var {
        return commitImmediately && _pendingImmediatePositions !== null
            ? _pendingImmediatePositions
            : positions
    }
    function _currentPosition(): var {
        return Presentation.resolve(_positionsForRead(),kind,outputName)
    }
    readonly property var position: _currentPosition()
    function _releaseImmediateShadow(generation): void {
        if (generation === _pendingImmediateGeneration)
            _pendingImmediatePositions = null
    }
    function apply(values): void {
        const next=Presentation.save(_positionsForRead(),kind,outputName,values)
        if(commitImmediately) {
            // JsonAdapter-backed arrays are not guaranteed to round-trip through
            // Config.options within the same JavaScript turn. Keep a one-turn
            // shadow so sequential field edits merge instead of overwriting
            // each other, while still committing each edit synchronously.
            _pendingImmediatePositions = next
            _pendingImmediateGeneration++
            const generation = _pendingImmediateGeneration
            Config.setNestedValue("abyss.positions",next)
            Qt.callLater(() => root._releaseImmediateShadow(generation))
        } else positionsEdited(next,kind,outputName,values)
    }
    function change(key,value): void {
        const values=Object.assign({edge:"source",alignment:"source",position:.5},_currentPosition(),{[key]:value})
        apply(values)
    }
    readonly property var inputRegions: [kindRegion,outputRegion,edgeRegion,alignmentRegion]
    readonly property Region kindRegion: Region { item:kindChoice.popup.contentItem;width:kindChoice.popup.visible ? kindChoice.popup.contentItem.width : 0 }
    readonly property Region outputRegion: Region { item:outputChoice.popup.contentItem;width:outputChoice.popup.visible ? outputChoice.popup.contentItem.width : 0 }
    readonly property Region edgeRegion: Region { item:edgeChoice.popup.contentItem;width:edgeChoice.popup.visible ? edgeChoice.popup.contentItem.width : 0 }
    readonly property Region alignmentRegion: Region { item:alignmentChoice.popup.contentItem;width:alignmentChoice.popup.visible ? alignmentChoice.popup.contentItem.width : 0 }
    GridLayout {
        visible:root.showKindSelector || root.showOutputSelector
        Layout.fillWidth:true
        columns:root.compactVertical ? 1 : 2
        rowSpacing:6
        columnSpacing:6
        StyledComboBox {
            id:kindChoice
            visible:root.showKindSelector
            Layout.fillWidth:true
            textRole:"label";valueRole:"value"
            model:[{label:"All Edge Bar popups",value:"popup"},{label:"Calendar",value:"clock"},
                {label:"System resources",value:"resources"},{label:"Battery",value:"battery"},
                {label:"Media popup",value:"media"},{label:"Weather",value:"weather"},
                {label:"Wi-Fi / Bluetooth",value:"wifi"},
                {label:"Utilities",value:"utilities"},
                {label:"Launcher presets",value:"launcher"},
                {label:"Workspaces",value:"workspaces"},{label:"System tray",value:"tray"},
                {label:"All OSDs / IPC indicators",value:"osd"},{label:"Volume OSD",value:"volume"},
                {label:"Brightness OSD",value:"brightness"},{label:"Microphone OSD",value:"mic"},
                {label:"Media OSD",value:"mediaOsd"},{label:"Keyboard OSD",value:"keyboardLayout"},
                {label:"Voice Search OSD",value:"voiceSearch"},{label:"Settings",value:"settings"},
                {label:"Dashboard",value:"dashboard"},{label:"Overview",value:"overview"},
                {label:"Clipboard",value:"clipboard"},{label:"Controls",value:"controls"},
                {label:"Left sidebar",value:"leftPanel"},{label:"Right sidebar",value:"rightPanel"},
                {label:"Quick Notes / Timers Edge Bar",value:"quickNotes"},{label:"Notifications / Activity Edge Bar",value:"notificationCenter"},{label:"Notification popups",value:"notifications"},
                {label:"Session menu",value:"session"},{label:"Cheatsheet",value:"cheatsheet"},
                {label:"Shell update",value:"update"},{label:"Dialogs",value:"dialog"}].filter(option=>!root.allowedKinds.length || root.allowedKinds.includes(option.value))
            currentIndex:model.findIndex(p => p.value===root.kind)
            onActivated:root.kind=currentValue
        }
        StyledComboBox {
            id:outputChoice
            enabled:root.outputSelectionEnabled
            visible:root.showOutputSelector
                && (root.outputSelectionEnabled || !root.compactVertical)
            Layout.fillWidth:true
            textRole:"label";valueRole:"value"
            model:[{label:"All outputs",value:""}].concat(Quickshell.screens.map(s => ({label:s.name,value:s.name})))
            currentIndex:Math.max(0,model.findIndex(p => p.value===root.outputName))
            onActivated:root.outputName=currentValue
        }
    }
    GridLayout {
        id: ipcPositionSelectorRow
        objectName: "abyssIpcSelectorsRow"
        Layout.fillWidth:true
        columns:root.compactIpcEditor
            ? (root.compactVertical ? 1 : 4)
            : (root.compactVertical ? 1 : 3)
        rowSpacing:root.compactIpcEditor ? 4 : 6
        columnSpacing:root.compactIpcEditor ? 6 : 6
        StyledComboBox {
            id:compactKindChoice
            objectName:"abyssEditorIpcKind"
            visible:root.compactIpcEditor
            Layout.fillWidth:root.compactVertical && !root.compactSideToolbar
            Layout.minimumWidth:0
            Layout.preferredWidth:root.compactIpcEditor ? root.compactKindTriggerWidth : -1
            Layout.maximumWidth:root.compactIpcEditor
                && (!root.compactVertical || root.compactSideToolbar)
                ? root.compactKindTriggerWidth : Infinity
            popupMinimumWidth:root.compactSideToolbar ? root.compactKindWidth : 0
            textRole:"label";valueRole:"value"
            model:[{label:"All OSDs",value:"osd"},{label:"Volume",value:"volume"},
                {label:"Brightness",value:"brightness"},{label:"Microphone",value:"mic"},
                {label:"Media",value:"mediaOsd"},{label:"Keyboard",value:"keyboardLayout"},
                {label:"Voice search",value:"voiceSearch"}]
            currentIndex:model.findIndex(option=>option.value===root.kind)
            onActivated:root.kind=currentValue
        }
        StyledComboBox {
            id:edgeChoice
            objectName:"abyssIpcEdgeDropdown"
            Layout.fillWidth:!root.compactIpcEditor
                || (root.compactVertical && !root.compactSideToolbar)
            Layout.minimumWidth:0
            Layout.preferredWidth:root.compactIpcEditor
                ? root.compactEdgeTriggerWidth : -1
            Layout.maximumWidth:root.compactIpcEditor
                && (!root.compactVertical || root.compactSideToolbar)
                ? root.compactEdgeTriggerWidth : Infinity
            popupMinimumWidth:root.compactSideToolbar ? root.compactEdgeWidth : 0
            textRole:"label";valueRole:"value"
            model:[{label:root.compactIpcEditor ? "Source edge" : "Follow source edge",value:"source"},{label:"Top Edge",value:"top"},
                {label:"Right Edge",value:"right"},{label:"Bottom Edge",value:"bottom"},{label:"Left Edge",value:"left"}]
            currentIndex:Math.max(0,model.findIndex(p => p.value===(root.position.edge ?? "source")))
            onActivated:root.change("edge",currentValue)
        }
        StyledComboBox {
            id:alignmentChoice
            objectName:"abyssIpcAlignmentDropdown"
            Layout.fillWidth:!root.compactIpcEditor
                || (root.compactVertical && !root.compactSideToolbar)
            Layout.minimumWidth:0
            Layout.preferredWidth:root.compactIpcEditor
                ? root.compactAlignmentTriggerWidth : -1
            Layout.maximumWidth:root.compactIpcEditor
                && (!root.compactVertical || root.compactSideToolbar)
                ? root.compactAlignmentTriggerWidth : Infinity
            popupMinimumWidth:root.compactSideToolbar ? root.compactAlignmentWidth : 0
            textRole:"label";valueRole:"value"
            model:[{label:root.compactIpcEditor ? "Source position" : "Follow source position",value:"source"},{label:"Align start",value:"start"},
                {label:"Align center",value:"center"},{label:"Align end",value:"end"},{label:"Custom position",value:"custom"}]
            currentIndex:Math.max(0,model.findIndex(p => p.value===(root.position.alignment ?? "source")))
            onActivated:root.change("alignment",currentValue)
        }
        AbyssButton {
            visible:!root.compactIpcEditor
            text:"Reset position";glyph:"restart_alt"
            compact:root.compactActions || root.compactIpcEditor
            editorSquare:root.compactIpcEditor
            description:root.ipcOnly ? "Reset IPC position" : "Reset popup or IPC position"
            Layout.fillWidth:root.compactVertical && !root.compactIpcEditor
            Layout.preferredWidth:root.compactIpcEditor
                ? 30*Appearance.fontSizeScale : -1
            Layout.maximumWidth:root.compactIpcEditor
                ? 30*Appearance.fontSizeScale : Infinity
            onClicked:root.apply(null)
        }
        AbyssButton {
            objectName:"abyssIpcJoinCornerToggle"
            parent:root.compactSideToolbar && root.compactCornerHost
                ? root.compactCornerHost : ipcPositionSelectorRow
            visible:root.visible && root.compactIpcEditor && Presentation.canJoin(root.kind)
            text:"Join nearby corner";glyph:"join_inner"
            compact:true;editorSquare:true;checkable:true
            description:root.nearbyEdge
                ? "Join this IPC indicator to the nearby "+root.nearbyEdge+" Edge"
                : "Connect this IPC indicator to the nearest visible corner"
            Layout.fillWidth:false
            Layout.preferredWidth:30*Appearance.fontSizeScale
            Layout.preferredHeight:30*Appearance.fontSizeScale
            Layout.maximumWidth:30*Appearance.fontSizeScale
            Layout.maximumHeight:30*Appearance.fontSizeScale
            enabled:root.commitImmediately || root.nearbyEdge.length>0 || checked
            checked:root.position.joinCorner===true
            onToggled:root.change("joinCorner",checked)
        }
    }
    WindowDialogSlider {
        text:"Position along Edge";Layout.fillWidth:true
        visible:root.position.alignment==="custom"
        from:0;to:100;stepSize:1;value:(root.position.position ?? .5)*100
        valueText:Math.round(value)+" %"
        onMoved:root.change("position",value/100)
    }
    AbyssCheckBox {
        Layout.fillWidth:true
        visible:!root.compactIpcEditor && Presentation.canJoin(root.kind)
        text:"Join nearby corner"+(root.nearbyEdge ? " · "+root.nearbyEdge+" Edge" : "")
        enabled:root.commitImmediately || root.nearbyEdge.length>0 || checked
        checked:root.position.joinCorner===true
        onToggled:root.change("joinCorner",checked)
    }
    SettingsNote {
        objectName: "abyssIpcPlacementHelpNote"
        // Embedded IPC editor intentionally has no explanatory paragraph.
        // Full settings pages retain their help text.
        visible: !root.compactIpcEditor
        text: root.compactVertical
            ? "Override Edge and position for this output."
            : root.ipcOnly
                ? "IPC indicators follow their source until overridden. Popups stay attached to Screen Edge modules."
                : "Positions follow the source unless overridden. Each popup or IPC indicator can use any Edge, globally or per output; content and input are clamped inside that output."
    }
}
