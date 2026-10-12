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
    spacing: 8
    property string kind: "popup"
    property string outputName: ""
    property var positions: Config.options?.abyss?.positions ?? []
    property bool commitImmediately: true
    property bool outputSelectionEnabled: true
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
        Layout.fillWidth:true
        columns:root.compactVertical ? 1 : 2
        rowSpacing:6
        columnSpacing:6
        StyledComboBox {
            id:kindChoice
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
            visible: root.outputSelectionEnabled || !root.compactVertical
            Layout.fillWidth:true
            textRole:"label";valueRole:"value"
            model:[{label:"All outputs",value:""}].concat(Quickshell.screens.map(s => ({label:s.name,value:s.name})))
            currentIndex:Math.max(0,model.findIndex(p => p.value===root.outputName))
            onActivated:root.outputName=currentValue
        }
    }
    GridLayout {
        Layout.fillWidth:true
        columns:root.compactVertical ? 1 : 3
        rowSpacing:6
        columnSpacing:6
        StyledComboBox {
            id:edgeChoice
            Layout.fillWidth:true
            textRole:"label";valueRole:"value"
            model:[{label:"Follow source edge",value:"source"},{label:"Top Edge",value:"top"},
                {label:"Right Edge",value:"right"},{label:"Bottom Edge",value:"bottom"},{label:"Left Edge",value:"left"}]
            currentIndex:Math.max(0,model.findIndex(p => p.value===(root.position.edge ?? "source")))
            onActivated:root.change("edge",currentValue)
        }
        StyledComboBox {
            id:alignmentChoice
            Layout.fillWidth:true
            textRole:"label";valueRole:"value"
            model:[{label:"Follow source position",value:"source"},{label:"Align start",value:"start"},
                {label:"Align center",value:"center"},{label:"Align end",value:"end"},{label:"Custom position",value:"custom"}]
            currentIndex:Math.max(0,model.findIndex(p => p.value===(root.position.alignment ?? "source")))
            onActivated:root.change("alignment",currentValue)
        }
        AbyssButton {
            text:"Reset position";glyph:"restart_alt"
            compact:root.compactActions
            description:root.ipcOnly ? "Reset IPC position" : "Reset popup or IPC position"
            Layout.fillWidth:root.compactVertical
            onClicked:root.apply(null)
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
        visible:Presentation.canJoin(root.kind)
        text:"Join nearby corner"+(root.nearbyEdge ? " · "+root.nearbyEdge+" Edge" : "")
        enabled:root.commitImmediately || root.nearbyEdge.length>0 || checked
        checked:root.position.joinCorner===true
        onToggled:root.change("joinCorner",checked)
    }
    SettingsNote {
        text: root.compactVertical
            ? "Override Edge and position for this output."
            : root.ipcOnly
                ? "IPC indicators follow their source until overridden. Popups stay attached to Screen Edge modules."
                : "Positions follow the source unless overridden. Each popup or IPC indicator can use any Edge, globally or per output; content and input are clamped inside that output."
    }
}
