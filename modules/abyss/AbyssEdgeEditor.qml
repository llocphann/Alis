pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks
import qs.modules.abyss.settings
import "looks/AbyssLayout.js" as Placement
import "looks/AbyssSelection.js" as ModuleSelection
import "looks/AbyssPresentation.js" as Presentation

// Drafts never write Config. Only Done merges this output into the latest profile.
Item {
    id: root
    // Compact, non-clickable captions keep slider semantics in tooltips.
    component EditorIconHint: Item {
        property string glyph: ""
        property string description: ""
        implicitWidth: 30 * Appearance.fontSizeScale
        implicitHeight: 32 * Appearance.fontSizeScale
        Accessible.role: Accessible.StaticText
        Accessible.name: description
        MaterialSymbol {
            anchors.centerIn: parent
            text: glyph
            iconSize: 20
            color: Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : "#1a1a1a"
        }
        HoverHandler { id: hintHover }
        StyledToolTip {
            text: description
            useParentHover: false
            externalHoverState: hintHover.hovered
            delay: 500
        }
    }
    required property string outputName
    required property var moduleLayer
    required property var controller
    property var edgeInsets: Placement.edgeInsetsForModules(moduleLayer.placements,moduleLayer.layoutOptions,
        Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
    property var draft: []
    property var handles: []
    property string selectedId: ""
    // A multi-selection is inferred from Ctrl/Shift-click, never a toolbar mode.
    property var selectedIds: []
    property string selectionAnchor: ""
    readonly property var targetIds: selectedIds.length
        ? selectedIds.filter(id=>draft.some(p=>p.id===id))
        : selectedId && draft.some(p=>p.id===selectedId) ? [selectedId] : []
    readonly property bool multiSelect: targetIds.length>1
    readonly property var targets: targetIds.map(id=>draft.find(p=>p.id===id)).filter(p=>p)
    readonly property bool anyTargetLocked: targets.some(p=>p.locked)
    readonly property bool allTargetsLocked: targets.length>0 && targets.every(p=>p.locked)
    readonly property bool allTargetsDisabled: targets.length>0 && targets.every(p=>!p.enabled)
    readonly property bool allTargetsCustom: targets.length>0 && targets.every(p=>p.customSize)
    property var _lastSelection: null
    property var _dragOrigin: null
    property var _dragRecords: null
    property var _dragContext: null
    property var _dragRequest: null
    property int _dragToken: 0
    property bool _groupReflowQueued: false
    property int _groupReflowBudget: 0
    property string feedback: ""
    property var undoStack: []
    property var _lastSnapshot: null
    property string _sourceSignature: ""
    property bool _historyReady: false
    property bool _historyQueued: false
    property bool _dragging: false
    property real gap: 8
    property var edgeSizes: ({top:1,right:1,bottom:1,left:1})
    property var edgeThicknesses: ({top:-1,right:-1,bottom:-1,left:-1})
    property var edgeWidthAffectsModules: ({top:true,right:true,bottom:true,left:true})
    property var edgeJoinModules: ({top:false,right:false,bottom:false,left:false})
    property var edgeRoundZeroCorners: ({top:false,right:false,bottom:false,left:false})
    property var edgeModuleRadii: ({top:-1,right:-1,bottom:-1,left:-1})
    property real moduleScale: 1
    property var singleModuleExpansion: ({top:"edge",right:"edge",bottom:"edge",left:"edge"})
    property string editingEdge: "top"
    // Keep the editor controls on the least-contended Screen Edge. The selected
    // module's Edge receives a large penalty, while a small hysteresis bonus
    // keeps the toolbar from oscillating between equal candidates mid-drag.
    property string toolbarEdge: "bottom"
    readonly property bool toolbarOnHorizontalEdge:
        toolbarEdge === "top" || toolbarEdge === "bottom"
    readonly property bool toolbarWideControls:
        toolbarOnHorizontalEdge && toolbarScroll.width>=640*Appearance.fontSizeScale
    property var guides: []
    property bool snapEnabled: true
    property bool outputOnly: true
    property bool editingPopups: false
    property bool expandedControls: false
    property var draftPositions: []
    property var positionEdits: []
    property alias previewKind:previewPositions.kind
    readonly property var previewPosition: Presentation.resolve(draftPositions,previewKind,outputOnly ? outputName : "")
    property alias previewHost:previewBody
    readonly property string previewNearbyCorner:
        Presentation.nearbyEdge(previewBody.edge,previewBody.along,
            previewBody.span,width,height)
    property real lastImpulse: 0
    property var inputRegions: []
    readonly property string nearbyCorner: Placement.cornerForModule(moduleLayer.layoutRecords,selectedId,width,height)
    readonly property var selected: draft.find(p => p.id === selectedId)
    readonly property var layoutConflicts: Placement.conflicts(moduleLayer.layoutRecords)
    readonly property var draftOptions: Object.assign({},Config.options?.abyss?.modules,{gap:gap,edgeSizes:edgeSizes,size:moduleScale,
        singleModuleExpansion:singleModuleExpansion,edgeThicknesses:edgeThicknesses,edgeWidthAffectsModules:edgeWidthAffectsModules,edgeJoinModules:edgeJoinModules,edgeModuleRadii:edgeModuleRadii,edgeRoundZeroCorners:edgeRoundZeroCorners,edgeThickness:AbyssStyle.perimeterThickness,cornerRadius:AbyssStyle.perimeterRadius})

    function toolbarEdgeScore(edge): real {
        let score = (edge === toolbarEdge ? -4 : 0)
        // Side placement remains available, but top/bottom wins close ties
        // because the existing control rows are naturally horizontal.
        if (edge === "left" || edge === "right")
            score += 6
        if (edge === editingEdge)
            score += selected ? 54 : 12

        if (root.editingPopups) {
            // Popup/IPC previews are first-class edit targets too. Keep the
            // controls off the preview's physical Edge (and its joined Edge)
            // so dragging a persistent example never happens under the toolbar.
            if (edge === previewBody.edge) {
                const edgeLength = ["top","bottom"].includes(edge)
                    ? root.width : root.height
                const occupancy = Math.min(1,
                    previewBody.span / Math.max(1, edgeLength))
                score += 260 + occupancy * 120
            }
            if (previewBody.joinedEdge.length > 0
                    && edge === previewBody.joinedEdge)
                score += 180
        }

        for (let i = 0; i < draft.length; ++i) {
            const placement = draft[i]
            if (placement?.enabled === false || placement?.edge !== edge)
                continue
            const scale = placement?.customSize
                ? Number(placement?.size ?? 1)
                : Placement.edgeSize(draftOptions,edge)
            score += 18 + Math.max(.5,scale) * 8
            if (targetIds.includes(placement?.id))
                score += 220
        }
        return score
    }

    function bestToolbarEdge(): string {
        const candidates = ["bottom","top","right","left"]
        let best = candidates[0]
        let bestScore = toolbarEdgeScore(best)
        for (let i = 1; i < candidates.length; ++i) {
            const score = toolbarEdgeScore(candidates[i])
            if (score < bestScore) {
                best = candidates[i]
                bestScore = score
            }
        }
        return best
    }

    function scheduleToolbarRelocation(): void {
        if (visible)
            toolbarRelocate.restart()
    }

    function relocateToolbar(): void {
        const next = bestToolbarEdge()
        if (next !== toolbarEdge)
            toolbarEdge = next
    }

    function refreshHandles(): void { handles = draft.map(p => p.id) }
    function selectionState(): var {
        return {selectedId:selectedId,selectedIds:Array.from(selectedIds),anchor:selectionAnchor}
    }
    function pruneSelection(): void {
        selectedIds=selectedIds.filter(id=>draft.some(p=>p.id===id))
        if(!draft.some(p=>p.id===selectedId))selectedId=selectedIds[selectedIds.length-1] || ""
        if(!draft.some(p=>p.id===selectionAnchor))selectionAnchor=selectedId
    }
    function select(id,ctrl=false,shift=false): void {
        if(!draft.some(p=>p.id===id))return
        rememberHistory()
        const next=ModuleSelection.select(targetIds,selectedId,selectionAnchor,
            id,ModuleSelection.orderedIds(draft),ctrl,shift)
        selectedIds=next.ids
        selectedId=next.primary
        selectionAnchor=next.anchor
        feedback=""
        rememberHistory()
    }
    function clearSelection(): void {
        clearDrag()
        rememberHistory();selectedIds=[];selectedId="";selectionAnchor="";guides=[];rememberHistory()
    }
    function snapshot(): var {
        return JSON.parse(JSON.stringify({draft:draft,gap:gap,edgeSizes:edgeSizes,
            edgeThicknesses:edgeThicknesses,edgeWidthAffectsModules:edgeWidthAffectsModules,
            edgeJoinModules:edgeJoinModules,edgeModuleRadii:edgeModuleRadii,edgeRoundZeroCorners:edgeRoundZeroCorners,moduleScale:moduleScale,
            singleModuleExpansion:singleModuleExpansion,outputOnly:outputOnly,
            draftPositions:draftPositions,positionEdits:positionEdits}))
    }
    function queueHistory(): void {
        if(!_historyReady || _historyQueued || _dragging)return
        _historyQueued=true
        Qt.callLater(()=>{
            _historyQueued=false
            if(!_historyReady || _dragging)return
            root.rememberHistory()
        })
    }
    function rememberHistory(): void {
        if(!_historyReady || _dragging)return
        const next=snapshot()
        if(JSON.stringify(next)===JSON.stringify(_lastSnapshot)){_lastSelection=selectionState();return}
        undoStack=undoStack.concat([{state:_lastSnapshot,selection:_lastSelection}]).slice(-64)
        _lastSnapshot=next;_lastSelection=selectionState()
    }
    function sourceSignature(): string {
        const options=Config.options?.abyss?.modules
        const values={configured:options?.configured,placements:Array.from(options?.placements || []),gap:options?.gap,size:options?.size}
        for(const key of ["edgeSizes","edgeThicknesses","edgeWidthAffectsModules","edgeJoinModules","edgeModuleRadii","edgeRoundZeroCorners","singleModuleExpansion"])values[key]=Placement.edgeMap(options?.[key])
        return JSON.stringify({global:values,profile:Array.from(options?.outputLayouts || []).find(p=>p.outputName===outputName) || null})
    }
    function undo(): void {
        _dragging=false;rememberHistory()
        if(!undoStack.length)return
        const previous=undoStack[undoStack.length-1]
        _historyReady=false;_dragging=false
        undoStack=undoStack.slice(0,-1)
        Object.keys(previous.state).forEach(key=>root[key]=JSON.parse(JSON.stringify(previous.state[key])))
        selectedIds=previous.selection?.selectedIds ?? []
        selectedId=previous.selection?.selectedId ?? "";selectionAnchor=previous.selection?.anchor ?? selectedId;pruneSelection()
        refreshHandles();guides=[];feedback="";clearDrag()
        _lastSnapshot=snapshot();_lastSelection=selectionState();_historyReady=true
    }
    function toggleLock(id): void {
        const p=draft.find(p=>p.id===id)
        if(!p)return
        const options=Object.assign({},draftOptions,{extents:moduleLayer.measuredExtents,editing:true})
        draft=Placement.setLocked(draft,id,!p.locked,width,height,options,Appearance.fontSizeScale,moduleLayer.renderedRecords)
        feedback=""
    }
    function batch(action,value): void {
        if(_dragging){feedback="Finish moving the module group before editing its settings";return}
        rememberHistory()
        const options=Object.assign({},draftOptions,{extents:moduleLayer.measuredExtents,editing:true})
        const result=Placement.checkedBatch(draft,targetIds,action,value,width,height,options,Appearance.fontSizeScale,moduleLayer.renderedRecords)
        feedback=result.rejected || ""
        if(result.rejected)return
        draft=result.placements
        if(action==="remove")refreshHandles()
    }
    function lockSelection(): void {batch("locked",!allTargetsLocked)}
    function startDrag(id,x=NaN,y=NaN): void {
        rememberHistory();_dragToken++;_dragRequest=null
        _dragOrigin=JSON.parse(JSON.stringify(draft))
        _dragRecords=JSON.parse(JSON.stringify(moduleLayer.renderedRecords ?? moduleLayer.layoutRecords));_dragging=true
        const own=_dragRecords.find(record=>record.id===id)
        _dragContext=own && Number.isFinite(x) && Number.isFinite(y) ? Placement.dragContext(own,x,y) : null
        feedback=""
    }
    function clearDrag(): void {
        _dragContext=null;_dragToken++;_dragOrigin=null;_dragRecords=null;_dragRequest=null;_dragging=false}
    function reflowGroup(): void {
        if(_groupReflowQueued || !_dragging || !multiSelect || !_dragRequest || _groupReflowBudget<=0)return
        _groupReflowQueued=true
        const token=_dragToken
        Qt.callLater(()=>{
            if(!root)return
            _groupReflowQueued=false
            if(root._dragToken!==token || !root._dragging || !root._dragRequest)return
            const request=root._dragRequest
            root._groupReflowBudget--
            root.move(request.id,request.x,request.y,request.snap,true)
        })
    }
    function endDrag(): void {
        const request=_dragRequest,token=_dragToken
        if(multiSelect && _dragging && request) {
            // The destination's mature module reports a new natural span when
            // rotating. Coalesce three finite layout turns before releasing the
            // gesture's Undo snapshot. There is no idle timer or new renderer.
            const settle=remaining=>{
                if(!root || root._dragToken!==token || !root._dragging)return
                root.move(request.id,request.x,request.y,request.snap,true)
                if(remaining>0)Qt.callLater(()=>settle(remaining-1))
                else {root.clearDrag();root.guides=[];root.queueHistory()}
            }
            Qt.callLater(()=>settle(2))
        } else {clearDrag();guides=[];queueHistory()}
    }
    function begin(): void {
        _historyReady=false;_dragging=false;feedback=""
        draft = JSON.parse(JSON.stringify(Placement.resolve(Config.options?.abyss?.modules,outputName,
            Placement.seed(moduleLayer.zones,moduleLayer.edge,width,height))))
        const options = Placement.optionsForOutput(Config.options?.abyss?.modules,outputName)
        gap = options.gap
        edgeSizes = Object.assign({top:1,right:1,bottom:1,left:1},options.edgeSizes)
        edgeThicknesses = Object.assign({top:-1,right:-1,bottom:-1,left:-1},options.edgeThicknesses)
        edgeWidthAffectsModules = Object.assign({top:true,right:true,bottom:true,left:true},options.edgeWidthAffectsModules)
        edgeJoinModules = Object.assign({top:false,right:false,bottom:false,left:false},options.edgeJoinModules)
        edgeRoundZeroCorners=Object.assign({top:false,right:false,bottom:false,left:false},options.edgeRoundZeroCorners)
        edgeModuleRadii = Object.assign({top:-1,right:-1,bottom:-1,left:-1},options.edgeModuleRadii)
        moduleScale = options.size
        singleModuleExpansion = Object.assign({top:"edge",right:"edge",bottom:"edge",left:"edge"},options.singleModuleExpansion)
        editingEdge = moduleLayer.edge
        guides = []
        draftPositions=JSON.parse(JSON.stringify(Config.options?.abyss?.positions ?? []))
        positionEdits=[];editingPopups=false;expandedControls=false
        selectedId = ""
        selectedIds=[];selectionAnchor="";clearDrag()
        refreshHandles()
        undoStack=[];_lastSnapshot=snapshot();_lastSelection=selectionState();_historyReady=true
        _sourceSignature=sourceSignature()
        Qt.callLater(() => root.relocateToolbar())
        forceActiveFocus()
    }
    function finish(save): void {
        if (save) {
            if(_dragging){feedback="Finish moving the module group before saving";return}
            if(layoutConflicts.length){feedback=layoutConflicts[0];return}
            if(_sourceSignature!==sourceSignature()){feedback="This layout changed outside the editor. Cancel and reopen before saving.";return}
            const writes=Placement.saveProfile(Config.options?.abyss?.modules,outputName,draft,gap,outputOnly,edgeSizes,singleModuleExpansion,moduleScale,edgeThicknesses,edgeWidthAffectsModules,edgeJoinModules,edgeModuleRadii,edgeRoundZeroCorners)
            let positions=Config.options?.abyss?.positions ?? []
            positionEdits.forEach(edit=>positions=Presentation.save(positions,edit.kind,edit.outputName,edit.values))
            if(positionEdits.length) writes["abyss.positions"]=positions
            Config.setNestedValues(writes)
        }
        guides = []
        _historyReady=false
        clearDrag()
        GlobalStates.abyssEditing = false
    }
    function reset(): void {
        clearDrag();rememberHistory()
        draft = Placement.seed(moduleLayer.zones,moduleLayer.edge,width,height)
        gap = 8
        edgeSizes = {top:1,right:1,bottom:1,left:1}
        moduleScale = 1
        edgeThicknesses = {top:-1,right:-1,bottom:-1,left:-1}
        edgeWidthAffectsModules = {top:true,right:true,bottom:true,left:true}
        edgeJoinModules = {top:false,right:false,bottom:false,left:false}
        edgeModuleRadii = {top:-1,right:-1,bottom:-1,left:-1}
        edgeRoundZeroCorners = {top:false,right:false,bottom:false,left:false}
        singleModuleExpansion = {top:"edge",right:"edge",bottom:"edge",left:"edge"}
        guides = []
        selectedId = ""
        selectedIds=[];selectionAnchor=""
        draftPositions=JSON.parse(JSON.stringify(Config.options?.abyss?.positions ?? []));positionEdits=[]
        refreshHandles()
    }
    function change(key,value): void {
        if(multiSelect){batch(key,value);return}
        if(selected?.locked && ["edge","position","alignment","size","customSize","depth"].includes(key)) {
            feedback="Unlock this module before changing its placement or size";return
        }
        feedback=""
        draft = draft.map(p => p.id === selectedId ? Object.assign({},p,
            key==="customSize" && value && !p.customSize ? {size:Placement.edgeSize(draftOptions,p.edge)} : {},{[key]:value}) : p)
    }
    function editPosition(positions,kind,output,values): void {
        draftPositions=positions
        positionEdits=positionEdits.filter(edit=>edit.kind!==kind || edit.outputName!==output)
            .concat([{kind:kind,outputName:output,values:values}])
        root.scheduleToolbarRelocation()
    }
    function movePreview(x,y): void {
        const location=Placement.project(x,y,width,height), horizontal=["top","bottom"].includes(location.edge)
        const length=horizontal ? width : height, point=horizontal ? x : y
        const inset=horizontal ? previewBody.edgeInsets.left : previewBody.edgeInsets.top
        const endInset=horizontal ? previewBody.edgeInsets.right : previewBody.edgeInsets.bottom
        const ratio=Math.max(0,Math.min(1,(point-previewBody.span/2-inset)/Math.max(1,length-inset-endInset-previewBody.span)))
        const values=Object.assign({},previewPosition,{edge:location.edge,alignment:"custom",position:ratio})
        const output=outputOnly ? outputName : ""
        editPosition(Presentation.save(draftPositions,previewKind,output,values),previewKind,output,values)
    }
    function move(id,x,y,snap = true,reflow=false): void {
        if(!multiSelect)selectedId = id
        if(!reflow)_groupReflowBudget=3
        if(multiSelect && _dragging)_dragRequest={id:id,x:x,y:y,snap:snap}
        const point=_dragging && _dragContext ? Placement.dragPoint(_dragContext,x,y,width,height,Appearance.fontSizeScale) : null
        if(point){x=point.x;y=point.y}
        const options = Object.assign({},draftOptions,{extents:moduleLayer.measuredExtents,editing:true,dragEdge:point?.edge})
        const result=multiSelect
            ? Placement.checkedGroupMove(_dragOrigin || draft,targetIds,id,x,y,width,height,options,Appearance.fontSizeScale,snap && snapEnabled,_dragRecords)
            : Placement.checkedMove(draft,id,x,y,width,height,options,Appearance.fontSizeScale,snap && snapEnabled)
        feedback=result.rejected || ""
        if(result.rejected){guides=[];if(multiSelect && _dragOrigin)draft=_dragOrigin;return}
        if(point)_dragContext=Object.assign({},_dragContext,{edge:point.edge})
        draft=result.placements;guides=result.guides
        editingEdge = draft.find(p => p.id===id)?.edge ?? editingEdge
        root.scheduleToolbarRelocation()
        const now = Date.now()
        if (now-lastImpulse > 80) {
            const p = draft.find(p => p.id === id)
            controller.impulse(p.edge,p.position*(p.edge === "top" || p.edge === "bottom" ? width : height),90,.35,1,"drag")
            lastImpulse = now
        }
    }
    onSelectedChanged: {
        if (selected)
            editingEdge = selected.edge
        root.scheduleToolbarRelocation()
    }
    onEditingEdgeChanged: root.scheduleToolbarRelocation()
    onDraftChanged: {root.pruneSelection();root.scheduleToolbarRelocation();root.queueHistory()}
    onGapChanged: root.queueHistory()
    onEdgeSizesChanged: root.queueHistory()
    onEdgeThicknessesChanged: root.queueHistory()
    onEdgeWidthAffectsModulesChanged: root.queueHistory()
    onEdgeJoinModulesChanged: root.queueHistory()
    onEdgeModuleRadiiChanged: root.queueHistory()
    onEdgeRoundZeroCornersChanged: root.queueHistory()
    onModuleScaleChanged: root.queueHistory()
    onSingleModuleExpansionChanged: root.queueHistory()
    onDraftPositionsChanged: root.queueHistory()
    onPositionEditsChanged: root.queueHistory()
    onEditingPopupsChanged: root.scheduleToolbarRelocation()
    onPreviewPositionChanged: root.scheduleToolbarRelocation()
    onPreviewKindChanged: root.scheduleToolbarRelocation()
    onExpandedControlsChanged: {
        toolbarScroll.contentY=0
        root.scheduleToolbarRelocation()
    }
    onOutputOnlyChanged: {root.scheduleToolbarRelocation();root.queueHistory()}

    Connections {
        target:root.moduleLayer
        function onMeasuredExtentsChanged(){root.reflowGroup()}
    }

    Timer {
        id: toolbarRelocate
        interval: 90
        repeat: false
        onTriggered: root.relocateToolbar()
    }

    function add(kind): void {
        if (draft.length >= 24) return
        const existing = draft.find(p => p.kind === kind && !p.enabled)
        if (existing) {
            const result=Placement.checkedBatch(draft,[existing.id],"enabled",true,width,height,
                Object.assign({},draftOptions,{extents:moduleLayer.measuredExtents,editing:true}),Appearance.fontSizeScale)
            if(result.rejected){feedback=result.rejected;return}
            draft=result.placements;select(existing.id);return
        }
        const id = kind+"-"+Date.now()
        const proposed=Placement.normalize(draft.concat([{id:id,kind:kind,edge:editingEdge,position:.5}]),"top")
        const failures=Placement.conflicts(Placement.geometry(proposed,width,height,Object.assign({},draftOptions,{extents:moduleLayer.measuredExtents,editing:true}),Appearance.fontSizeScale))
        if(failures.length){feedback=failures[0];return}
        draft=proposed;feedback=""
        select(id)
        refreshHandles()
    }
    onVisibleChanged: if (visible) begin()
    Component.onCompleted: if (visible) begin()
    Component.onDestruction: {
        _historyReady=false;clearDrag()
        if (GlobalStates.abyssEditorTargetOutput === outputName) GlobalStates.abyssEditing = false
    }
    Keys.onEscapePressed: finish(false)
    Keys.onReturnPressed: finish(true)
    Keys.onPressed:event=>{
        if(event.key===Qt.Key_Z && (event.modifiers & Qt.ControlModifier)){undo();event.accepted=true}
        else if(event.key===Qt.Key_A && (event.modifiers & Qt.ControlModifier) && !editingPopups){
            rememberHistory();selectedIds=ModuleSelection.orderedIds(draft);
            selectedId=selectedIds[0] || "";selectionAnchor=selectedId;rememberHistory();event.accepted=true
        }
    }
    Repeater {
        model: root.handles
        onItemAdded: (index,item) => root.inputRegions = root.inputRegions.concat([item.inputRegion])
        onItemRemoved: (index,item) => root.inputRegions = root.inputRegions.filter(region => region !== item.inputRegion)
        Item {
            id: handle
            objectName:"abyssModuleHandle"
            required property string modelData
            readonly property var record: (root.moduleLayer.renderedRecords ?? root.moduleLayer.layoutRecords).find(p => p.id === modelData)
            readonly property Region inputRegion: Region {
                x:Math.floor(handle.x);y:Math.floor(handle.y)
                width:root.editingPopups || !handle.visible ? 0 : Math.ceil(handle.x+handle.width)-Math.floor(handle.x)
                height:root.editingPopups || !handle.visible ? 0 : Math.ceil(handle.y+handle.height)-Math.floor(handle.y)
            }
            function invalidateRegion(): void {if(inputRegion)inputRegion.changed()}
            onXChanged:invalidateRegion();onYChanged:invalidateRegion()
            onWidthChanged:invalidateRegion();onHeightChanged:invalidateRegion()
            onVisibleChanged:invalidateRegion()
            x: record?.content.x ?? 0; y: record?.content.y ?? 0
            width: record?.content.width ?? 0; height: record?.content.height ?? 0
            visible: record !== undefined && !record.capacityConflict && !root.editingPopups
            activeFocusOnTab:true
            Accessible.role:Accessible.Button
            Accessible.name:Placement.label(record?.kind)+(record?.locked ? " · Locked" : "")
                +(root.targetIds.includes(handle.modelData) ? " · Selected" : "")
            Accessible.onPressAction:root.select(handle.modelData)
            Keys.onPressed:event=>{
                if(event.key===Qt.Key_Space){
                    root.select(handle.modelData,!!(event.modifiers & Qt.ControlModifier),
                        !!(event.modifiers & Qt.ShiftModifier));event.accepted=true
                } else if(event.key===Qt.Key_L){
                    if(!root.targetIds.includes(handle.modelData))root.select(handle.modelData)
                    root.lockSelection();event.accepted=true
                }
            }
            Rectangle {
                anchors.fill: parent; anchors.margins: -3
                color: Qt.alpha(AbyssStyle.accent,drag.pressed ? .22 : root.targetIds.includes(handle.modelData) ? .18 : .08)
                radius: 8
                border.width: root.targetIds.includes(handle.modelData) ? 2 : 1
                border.color: Qt.alpha(AbyssStyle.accent,.6)
            }
            MaterialSymbol {
                anchors.right:parent.right;anchors.top:parent.top
                visible:handle.record?.locked ?? false
                text:handle.record?.lockConflict ? "warning" : "lock"
                iconSize:14;color:handle.record?.lockConflict ? Appearance.colors.colError : AbyssStyle.accent
            }
            MaterialSymbol {
                anchors.left:parent.left;anchors.top:parent.top
                visible:root.multiSelect && root.targetIds.includes(handle.modelData)
                text:"check_circle";iconSize:14;color:AbyssStyle.accent
            }
            MouseArea {
                id: drag
                anchors.fill: parent
                cursorShape:handle.record?.locked ? Qt.ArrowCursor : pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property bool deferCollapse: false
                property bool movedBeyondThreshold: false
                property real pressRootX: 0
                property real pressRootY: 0
                onPressed:mouse=>{
                    const ctrl=!!(mouse.modifiers & Qt.ControlModifier)
                    const shift=!!(mouse.modifiers & Qt.ShiftModifier)
                    // Do not collapse an existing multi-selection on mouse-down:
                    // that destroys the group before checkedGroupMove can drag it.
                    deferCollapse=ModuleSelection.deferCollapseOnPress(root.targetIds,
                        handle.modelData,ctrl,shift)
                    movedBeyondThreshold=false
                    const point=mapToItem(root,mouse.x,mouse.y)
                    pressRootX=point.x
                    pressRootY=point.y
                    if(!deferCollapse)root.select(handle.modelData,ctrl,shift)
                    handle.forceActiveFocus()
                    if(!ctrl && !shift)
                        root.startDrag(handle.modelData,point.x,point.y)
                    if(handle.record?.locked)root.feedback="Unlock this module before moving it"
                }
                onReleased:mouse=>{
                    root.endDrag()
                    if(deferCollapse && !movedBeyondThreshold)
                        root.select(handle.modelData)
                    deferCollapse=false
                    movedBeyondThreshold=false
                }
                onCanceled:{
                    root.endDrag()
                    deferCollapse=false
                    movedBeyondThreshold=false
                }
                onPositionChanged: mouse => {
                    if (!pressed || !root._dragging) return
                    const point = mapToItem(root,mouse.x,mouse.y)
                    if(!movedBeyondThreshold) {
                        const delta=Math.hypot(point.x-pressRootX,point.y-pressRootY)
                        if(delta<Math.max(6,8*Appearance.fontSizeScale))return
                        movedBeyondThreshold=true
                    }
                    root.move(handle.modelData,point.x,point.y,!(mouse.modifiers & Qt.ShiftModifier))
                }
            }
        }
    }
    Repeater {
        model: root.guides
        Item {
            required property var modelData
            anchors.fill: parent
            Rectangle {
                x: modelData.horizontal ? modelData.along : 0
                y: modelData.horizontal ? 0 : modelData.along
                width: modelData.horizontal ? 1 : root.width
                height: modelData.horizontal ? root.height : 1
                color: AbyssStyle.accent; opacity: .6
            }
            AbyssLabel {
                text: modelData.label
                x: modelData.horizontal ? modelData.along+8 : root.width/2
                y: modelData.horizontal ? 76 : modelData.along+8
                color: AbyssStyle.accent
            }
        }
    }
    // Anchor hints paint only; the work area remains click-through in edit mode.
    // The hint for the Edge that owns the editor must stay outside its body,
    // otherwise it reads like part of the control surface.
    Repeater {
        model: ["top","right","bottom","left"]
        AbyssLabel {
            required property string modelData
            // These decorative hints compete with modules/controls on a tiny
            // output. The toolbar's Edge selector remains available there.
            visible:root.width>=520 && root.height>=420
            readonly property var editorSurface: editorBody.record?.surface ?? null
            readonly property bool editorEdge: modelData === root.toolbarEdge
            text: modelData.toUpperCase()
            opacity: .55
            x: {
                if (editorEdge && editorSurface) {
                    if (modelData === "left")
                        return Math.min(root.width-width-10,
                            editorSurface.x+editorSurface.width+12)
                    if (modelData === "right")
                        return Math.max(10,editorSurface.x-width-12)
                }
                return modelData === "left" ? 50
                    : modelData === "right" ? root.width-width-50
                    : (root.width-width)/2
            }
            y: {
                if (editorEdge && editorSurface) {
                    if (modelData === "top")
                        return Math.min(root.height-height-10,
                            editorSurface.y+editorSurface.height+12)
                    if (modelData === "bottom")
                        return Math.max(10,editorSurface.y-height-12)
                }
                return modelData === "top" ? 64
                    : modelData === "bottom" ? root.height-220
                    : (root.height-height)/2
            }
        }
    }
    AbyssBodyHost {
        id: editorBody
        anchors.fill: parent
        edge: root.toolbarEdge
        identity: "edgeEditor"
        objectName: "abyssEdgeEditorBody"
        // Fit the actual control rows instead of applying the compact popup's
        // 42% depth cap, which can clip the final controls on narrow outputs.
        largeSurface: true
        outputName: root.outputName
        controller: root.controller
        edgeInsets: root.edgeInsets
        open: root.visible
        // Horizontal Edges use the familiar wide control strip. If both are
        // busy, the same editor can move to a side Edge with a deeper body and
        // a long vertical span instead of covering the module being edited.
        span: root.toolbarOnHorizontalEdge
            ? Math.min(root.width-48,root.expandedControls ? 1000 : 760)
            : Math.min(root.height-48,toolbar.implicitHeight+padding*2)
        along: ((root.toolbarOnHorizontalEdge ? root.width : root.height)-span)/2
        depth: root.toolbarOnHorizontalEdge
            ? Math.min(Math.max(80,root.height*.65),toolbar.implicitHeight+padding*2)
            : Math.min(root.width-48,260*Appearance.fontSizeScale)
        embeddedItem: toolbar
    }
    AbyssBodyHost {
        id:previewBody;anchors.fill:parent;identity:"editorPreview";outputName:root.outputName
        controller:root.controller;placementPriority:-2;largeSurface:true
        open:root.visible && root.editingPopups
        contentKind:root.previewKind;source:"content/AbyssLayoutPreview.qml"
        edge:Presentation.edge(root.previewPosition,root.moduleLayer.edge)
        joinedEdge:Presentation.joinedEdge(root.previewKind,
            root.previewPosition,edge,along,span,root.width,root.height)
        edgeInsets:Placement.clearanceInsets(root.edgeInsets,root.moduleLayer.deformations,edge,along,span)
        span:(["top","bottom"].includes(edge) ? contentItem.item?.desiredWidth ?? 390 : contentItem.item?.desiredHeight ?? 120)+padding*2
        depth:(["top","bottom"].includes(edge) ? contentItem.item?.desiredHeight ?? 120 : contentItem.item?.desiredWidth ?? 390)+padding*2
        along:Presentation.along(root.previewPosition,edge,span,root.width,root.height,
            ((["top","bottom"].includes(edge) ? root.width : root.height)-span)/2,root.edgeInsets)
        MouseArea {
            parent:previewBody.contentParent;anchors.fill:parent
            cursorShape:pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPositionChanged:mouse=> { if(pressed) { const point=mapToItem(root,mouse.x,mouse.y);root.movePreview(point.x,point.y) } }
        }
    }
    readonly property Region previewRegion: Region { x:previewBody.inputBounds.x;y:previewBody.inputBounds.y;width:previewBody.inputBounds.width;height:previewBody.inputBounds.height }
    readonly property Region toolbarRegion: Region { item: toolbar }
    readonly property Region ipcKindRegion: Region { item:ipcKindChoice.popup.contentItem; width:ipcKindChoice.popup.visible ? ipcKindChoice.popup.contentItem.width : 0 }
    readonly property Region paletteRegion: Region { item: palette.popup.contentItem; width: palette.popup.visible ? palette.popup.contentItem.width : 0 }
    readonly property Region selectionRegion: Region { item: selection.popup.contentItem; width: selection.popup.visible ? selection.popup.contentItem.width : 0 }
    readonly property Region edgeRegion: Region { item: edgeChoice.popup.contentItem; width: edgeChoice.popup.visible ? edgeChoice.popup.contentItem.width : 0 }
    readonly property Region alignmentRegion: Region { item: alignmentChoice.popup.contentItem; width: alignmentChoice.popup.visible ? alignmentChoice.popup.contentItem.width : 0 }
    readonly property var regions: inputRegions.concat([toolbarRegion,paletteRegion,ipcKindRegion,selectionRegion,edgeRegion,alignmentRegion,previewRegion],root.editingPopups ? previewPositions.inputRegions : [])
    Item {
        id: toolbar
        parent: editorBody.contentParent
        anchors.fill: parent
        implicitWidth: root.toolbarOnHorizontalEdge
            ? toolbarColumn.implicitWidth : 288*Appearance.fontSizeScale
        implicitHeight: toolbarColumn.implicitHeight

        Flickable {
            id: toolbarScroll
            objectName: "abyssEdgeEditorScroll"
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: toolbarColumn.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            // Very small outputs can still clamp the requested depth. Keep
            // all controls reachable on horizontal as well as side Edges.
            interactive: contentHeight > height

            ColumnLayout {
                id: toolbarColumn
                width: toolbarScroll.width
                spacing: 4

                GridLayout {
                    Layout.fillWidth: true;Layout.minimumWidth:0
                    columns: width>=480*Appearance.fontSizeScale ? 2 : 1
                    rowSpacing: 6
                    AbyssLabel {
                        text: "Edit layout · "+root.outputName
                        font.bold: true
                        Layout.fillWidth: true;Layout.minimumWidth:0

                        elide: Text.ElideRight
                    }
                    GridLayout {
                        Layout.fillWidth: true;Layout.minimumWidth:0
                        columns: Math.max(1,Math.min(root.editingPopups ? 5 : 6,Math.floor((width+6)/42)))
                        columnSpacing: 6
                        rowSpacing: 6
                        AbyssButton {
                            objectName:"abyssLayoutUndo"
                            text:"Undo";glyph:"undo";compact:true
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            enabled:root.undoStack.length>0
                            onClicked:root.undo()
                        }
                        AbyssButton {
                            text: "Reset"; glyph: "restart_alt"; compact: true
                            description: "Reset layout draft"
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            onClicked: root.reset()
                        }
                        AbyssButton {
                            objectName:"abyssEditorOptions"
                            text:"Options";glyph:"tune";compact:true
                            description:root.expandedControls ? "Hide layout options" : "Show layout options"
                            checkable:true;checked:root.expandedControls
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            onToggled:root.expandedControls=checked
                        }
                        AbyssButton {
                            objectName:"abyssEditorAdd"
                            visible:!root.editingPopups
                            text:"Add module";glyph:"add";compact:true
                            description:"Choose a module to add"
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            onClicked:{root.expandedControls=true;palette.forceActiveFocus()}
                        }
                        AbyssButton {
                            objectName:"abyssLayoutCancel"
                            text: "Cancel"; glyph: "close"; compact: true
                            description: "Cancel editing"
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            onClicked: root.finish(false)
                        }
                        AbyssButton {
                            objectName:"abyssLayoutDone"
                            text: "Done"; glyph: "check"; compact: true
                            description: "Save layout changes"
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            enabled:!root.layoutConflicts.length
                            onClicked: root.finish(true)
                        }
                    }
                }

                AbyssLabel {
                    objectName:"abyssLayoutFeedback"
                    visible:text.length>0
                    text:root.layoutConflicts[0] || root.feedback
                    Layout.fillWidth:true;Layout.minimumWidth:0;wrapMode:Text.WordWrap
                    color:Appearance.colors.colError
                }

                GridLayout {
                    Layout.fillWidth: true;Layout.minimumWidth:0
                    columns: root.editingPopups && width>=480*Appearance.fontSizeScale ? 3 : 2
                    columnSpacing:6;rowSpacing:6
                    SelectionGroupButton {
                        objectName:"abyssEditorModulesMode"
                        buttonIcon:"widgets";buttonText:"Modules";toggled:!root.editingPopups
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onClicked:root.editingPopups=false
                    }
                    SelectionGroupButton {
                        objectName:"abyssEditorIpcMode"
                        buttonIcon:"open_in_new";buttonText:"IPC";toggled:root.editingPopups
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onClicked:root.editingPopups=true
                    }
                    StyledComboBox {
                        id:ipcKindChoice
                        Layout.columnSpan:parent.columns===2 ? 2 : 1
                        objectName:"abyssEditorIpcKind"
                        visible:root.editingPopups
                        model:[{label:"All OSDs",value:"osd"},{label:"Volume",value:"volume"},
                            {label:"Brightness",value:"brightness"},{label:"Microphone",value:"mic"},
                            {label:"Media",value:"mediaOsd"},{label:"Keyboard",value:"keyboardLayout"},
                            {label:"Voice search",value:"voiceSearch"}]
                        textRole:"label";valueRole:"value"
                        currentIndex:model.findIndex(p=>p.value===previewPositions.kind)
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onActivated:previewPositions.kind=currentValue
                    }
                }

                AbyssCheckBox {
                    visible:root.expandedControls
                    text:"This output only"
                    checked:root.outputOnly
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    onToggled:root.outputOnly=checked
                }

                Rectangle {
                    Layout.fillWidth: true;Layout.minimumWidth:0
                    height: 1
                    visible: root.expandedControls && !root.toolbarOnHorizontalEdge
                    color: Qt.alpha(AbyssStyle.accent,.18)
                }

                AbyssLabel {
                    visible: root.expandedControls && !root.toolbarOnHorizontalEdge
                    text: root.editingPopups
                        ? "IPC placement" : "Module placement"
                    font.bold: true
                    color: Appearance.m3colors.darkmode ? AbyssStyle.textColorMuted : "#1a1a1a"
                    Layout.fillWidth: true;Layout.minimumWidth:0
                }

                AbyssPositionSettings {
                    id:previewPositions
                    visible:root.expandedControls && root.editingPopups
                    kind:"volume"
                    compactVertical:!root.toolbarWideControls
                    compactActions:root.toolbarOnHorizontalEdge
                    commitImmediately:false
                    positions:root.draftPositions
                    outputSelectionEnabled:false
                    outputName:root.outputOnly ? root.outputName : ""
                    nearbyEdge:root.previewNearbyCorner
                    // Popups follow their owning Screen Edge modules; only IPC/OSD
                    // indicators have independent positions in this editor.
                    allowedKinds:["osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"]
                    onPositionsEdited:(positions,kind,outputName,values)=>
                        root.editPosition(positions,kind,outputName,values)
                }

                GridLayout {
                    visible:root.expandedControls && !root.editingPopups
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:root.toolbarWideControls ? 4 : 1
                    rowSpacing:6
                    columnSpacing:6

                    StyledComboBox {
                        id: palette
                        model: Placement.catalog.map(kind => ({label:Placement.label(kind),kind:kind}))
                        textRole:"label";valueRole:"kind"
                        Layout.preferredWidth: root.toolbarOnHorizontalEdge ? 190 : -1
                        Layout.fillWidth: !root.toolbarOnHorizontalEdge;Layout.minimumWidth:0
                    }
                    AbyssButton {
                        objectName:"abyssEditorConfirmAdd"
                        text:"Add module";glyph:"add"
                        compact:root.toolbarOnHorizontalEdge
                        description:"Add selected module"
                        enabled:root.draft.length<24
                        Layout.fillWidth: !root.toolbarOnHorizontalEdge;Layout.minimumWidth:0
                        onClicked:root.add(palette.currentValue)
                    }
                    EditorIconHint { glyph:"space_bar";description:"Gap between modules" }
                    AbyssSlider {
                        Layout.maximumWidth: 210 * Appearance.fontSizeScale
                        unit:"px";from:0;to:32;value:root.gap
                        onMoved:root.gap=value
                        Layout.fillWidth:true;Layout.minimumWidth:0
                    }
                }

                Rectangle {
                    Layout.fillWidth:true;Layout.minimumWidth:0;height:1
                    visible:root.expandedControls && !root.toolbarOnHorizontalEdge && !root.editingPopups
                    color:Qt.alpha(AbyssStyle.accent,.12)
                }

                GridLayout {
                    visible:root.expandedControls && !root.editingPopups
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:root.toolbarWideControls ? 5 : 1
                    rowSpacing:6
                    columnSpacing:6

                    EditorIconHint { glyph:"border_outer";description:"Editing Edge" }
                    StyledComboBox {
                        id:edgeChoice
                        model:["top","right","bottom","left"]
                        currentIndex:model.indexOf(root.editingEdge)
                        onActivated:root.editingEdge=currentText
                        Layout.preferredWidth:root.toolbarOnHorizontalEdge ? 110 : -1
                        Layout.fillWidth:!root.toolbarOnHorizontalEdge;Layout.minimumWidth:0
                    }
                    EditorIconHint { glyph:"aspect_ratio";description:"Shared module size for this Edge" }
                    AbyssSlider {
                        Layout.maximumWidth: 210 * Appearance.fontSizeScale
                        from:.6;to:1.8
                        value:Placement.edgeSize(root.draftOptions,root.editingEdge)
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onMoved:root.edgeSizes=Object.assign(
                            {},root.edgeSizes,{[root.editingEdge]:value})
                    }
                    AbyssButton {
                        text:"Snap to guides";glyph:"grid_4x4"
                        compact:true
                        description:"Snap module movement to alignment guides"
                        checkable:true;checked:root.snapEnabled
                        Layout.fillWidth:!root.toolbarOnHorizontalEdge;Layout.minimumWidth:0
                        onToggled:root.snapEnabled=checked
                    }
                }

                GridLayout {
                    visible:root.expandedControls && !root.editingPopups
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:root.toolbarWideControls ? 3 : 1
                    rowSpacing:6
                    columnSpacing:6

                    EditorIconHint { glyph:"line_weight";description:"Physical Edge width" }
                    AbyssSlider {
                        Layout.maximumWidth: 210 * Appearance.fontSizeScale
                        unit:"px";from:0;to:40;stepSize:1
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        value:Placement.edgeThickness(
                            root.draftOptions,root.editingEdge)
                        onMoved:root.edgeThicknesses=Object.assign(
                            {},root.edgeThicknesses,
                            {[root.editingEdge]:value})
                    }
                    AbyssButton {
                        text:"Inherit surface";glyph:"layers";compact:true
                        description:"Inherit the physical surface thickness"
                        Layout.fillWidth:!root.toolbarOnHorizontalEdge;Layout.minimumWidth:0
                        enabled:(root.edgeThicknesses[root.editingEdge] ?? -1)>=0
                        onClicked:root.edgeThicknesses=Object.assign(
                            {},root.edgeThicknesses,
                            {[root.editingEdge]:-1})
                    }
                }

                AbyssCheckBox {
                    objectName:"abyssRoundZeroCorners"
                    visible:root.expandedControls && !root.editingPopups
                    enabled:Placement.edgeThickness(root.draftOptions,root.editingEdge)===0
                    text:"Round inner corners at 0px"
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    checked:root.edgeRoundZeroCorners[root.editingEdge]===true
                    onToggled:root.edgeRoundZeroCorners=Object.assign({},root.edgeRoundZeroCorners,{[root.editingEdge]:checked})
                    StyledToolTip {text:parent.enabled ? "Uses shared Curvature" : "Set Edge width to 0px"}
                }

                AbyssButton {
                    visible:root.expandedControls && !root.editingPopups;Layout.fillWidth:true;Layout.minimumWidth:0
                    text:"Width affects modules";glyph:"width"
                    description:"Scale inherited modules with this Edge (0px hides them), or change only the bare Edge and retain local module bulges. Custom module sizes stay independent."
                    checkable:true;checked:root.edgeWidthAffectsModules[root.editingEdge]!==false
                    onToggled:root.edgeWidthAffectsModules=Object.assign({},root.edgeWidthAffectsModules,{[root.editingEdge]:checked})
                }

                AbyssCheckBox {
                    objectName:"abyssJoinNearbyModules"
                    visible:root.expandedControls && !root.editingPopups && root.edgeWidthAffectsModules[root.editingEdge]===false
                    text:"Join nearby modules"
                    checked:root.edgeJoinModules[root.editingEdge]===true
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    onToggled:root.edgeJoinModules=Object.assign({},root.edgeJoinModules,{[root.editingEdge]:checked})
                    StyledToolTip {text:"Connect neighboring module surfaces on this Edge. Distant groups keep their own bulges; module sizes stay unchanged."}
                }

                GridLayout {
                    visible:root.expandedControls && !root.editingPopups && root.edgeWidthAffectsModules[root.editingEdge]===false
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:root.toolbarWideControls ? 3 : 1
                    EditorIconHint { glyph:"rounded_corner";description:"Module rounding radius" }
                    AbyssSlider {
                        Layout.maximumWidth: 210 * Appearance.fontSizeScale
                        objectName:"abyssModuleRounding"
                        Layout.fillWidth:true;Layout.minimumWidth:0;unit:"px";from:0;to:64;stepSize:1
                        value:(root.edgeModuleRadii[root.editingEdge] ?? -1)<0
                            ? AbyssStyle.neckRadius : root.edgeModuleRadii[root.editingEdge]
                        onMoved:root.edgeModuleRadii=Object.assign({},root.edgeModuleRadii,{[root.editingEdge]:value})
                    }
                    AbyssButton {
                        text:"Inherit rounding";glyph:"rounded_corner"
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        compact:true
                        description:"Inherit shared module rounding"
                        enabled:(root.edgeModuleRadii[root.editingEdge] ?? -1)>=0
                        onClicked:root.edgeModuleRadii=Object.assign({},root.edgeModuleRadii,{[root.editingEdge]:-1})
                    }
                }

                GridLayout {
                    visible:root.expandedControls && !root.editingPopups
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:root.toolbarWideControls ? 3 : 1
                    rowSpacing:6
                    columnSpacing:6

                    EditorIconHint { glyph:"zoom_out_map";description:"Overall module scale" }
                    AbyssSlider {
                        Layout.maximumWidth: 210 * Appearance.fontSizeScale
                        from:.6;to:1.8;value:root.moduleScale
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onMoved:root.moduleScale=value
                    }
                    AbyssButton {
                        text:"Expand whole Edge";glyph:"fit_screen"
                        compact:true
                        description:"Expand a single module across the whole Edge; turn off to expand only its local surface."
                        checkable:true
                        Layout.fillWidth:!root.toolbarOnHorizontalEdge;Layout.minimumWidth:0
                        enabled:root.draft.filter(
                            p=>p.enabled && p.edge===root.editingEdge).length===1
                        checked:root.singleModuleExpansion[root.editingEdge]!=="local"
                        onToggled:root.singleModuleExpansion=Object.assign(
                            {},root.singleModuleExpansion,
                            {[root.editingEdge]:checked ? "edge" : "local"})
                    }
                }

                Rectangle {
                    Layout.fillWidth:true;Layout.minimumWidth:0;height:1
                    visible:root.expandedControls && !root.toolbarOnHorizontalEdge && !root.editingPopups
                    color:Qt.alpha(AbyssStyle.accent,.12)
                }

                GridLayout {
                    visible:!root.editingPopups && (root.multiSelect || root.expandedControls)
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:width>300*Appearance.fontSizeScale ? 2 : 1
                    AbyssLabel {
                        objectName:"abyssSelectionCount"
                        visible:root.multiSelect
                        text:root.targets.length+" selected · "+root.targets.filter(p=>p.locked).length+" locked"
                        Layout.fillWidth:true;Layout.minimumWidth:0;wrapMode:Text.WordWrap
                    }
                    AbyssButton {
                        objectName:"abyssSelectionClear"
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        compact:true
                        visible:root.targetIds.length>0
                        text:"Clear selection";glyph:"deselect"
                        enabled:root.targetIds.length>0
                        onClicked:root.clearSelection()
                    }
                }

                GridLayout {
                    id:selectedModuleControls
                    visible:!root.editingPopups
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    columns:!root.expandedControls ? (width>=460*Appearance.fontSizeScale ? 4 : 3)
                        : !root.toolbarOnHorizontalEdge || width<420*Appearance.fontSizeScale ? 1 : width<740*Appearance.fontSizeScale ? 2 : width<1100*Appearance.fontSizeScale ? 4 : 8
                    rowSpacing:6
                    columnSpacing:6

                    StyledComboBox {
                        id:selection
                        objectName:"abyssEditorSelection"
                        Layout.columnSpan:!root.expandedControls && selectedModuleControls.columns===3 ? 3 : 1
                        model:root.draft.map(p => ({
                            label:Placement.label(p.kind)
                                +(root.multiSelect && root.targetIds.includes(p.id) ? " · Selected" : "")
                                +(p.locked ? " · Locked" : "")
                                +(p.enabled ? "" : " (disabled)"),
                            id:p.id}))
                        textRole:"label";valueRole:"id"
                        currentIndex:root.draft.findIndex(
                            p => p.id===root.selectedId)
                        displayText:root.selected
                            ? Placement.label(root.selected.kind)
                            : "Select a module"
                        onActivated:root.select(currentValue)
                        Layout.preferredWidth:root.toolbarOnHorizontalEdge ? 190 : -1

                        Layout.maximumWidth:selectedModuleControls.width
                        Layout.fillWidth:true;Layout.minimumWidth:0
                    }
                    AbyssButton {
                        objectName:"abyssModulePositionLock"
                        text:root.allTargetsLocked ? "Unlock position" : "Lock position"
                        glyph:root.allTargetsLocked ? "lock_open" : "lock"
                        compact:true
                        description:text
                        enabled:root.targets.length>0
                        Keys.onPressed:event=>{if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){root.lockSelection();event.accepted=true}}
                        onClicked:root.lockSelection()
                    }
                    AbyssButton {
                        objectName:"abyssSelectionEnabled"
                        text:root.allTargetsDisabled
                            ? "Enable" : "Disable"
                        glyph:root.allTargetsDisabled
                            ? "visibility" : "visibility_off"
                        compact:true
                        description:text
                        enabled:root.targets.length>0
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onClicked:root.batch("enabled",root.allTargetsDisabled)
                    }
                    AbyssButton {
                        text:"Remove";glyph:"delete"
                        objectName:"abyssSelectionRemove"
                        compact:true
                        description:root.multiSelect ? "Remove selected modules" : "Remove selected module"
                        enabled:root.targets.length>0
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onClicked:root.batch("remove",true)
                    }
                    StyledComboBox {
                        id:alignmentChoice
                        visible:root.expandedControls
                        model:[
                            {label:"Free position",value:"free"},
                            {label:"Align start",value:"start"},
                            {label:"Align center",value:"center"},
                            {label:"Align end",value:"end"}]
                        textRole:"label";valueRole:"value"
                        currentIndex:Math.max(0,model.findIndex(
                            p => p.value===root.selected?.alignment))
                        displayText:root.multiSelect && root.targets.some(p=>p.alignment!==root.selected?.alignment)
                            ? "Mixed alignment" : currentText
                        enabled:root.targets.length>0 && !root.anyTargetLocked
                        onActivated:root.change("alignment",currentValue)
                        Layout.preferredWidth:root.toolbarOnHorizontalEdge ? 146 : -1

                        Layout.maximumWidth:selectedModuleControls.width
                        Layout.fillWidth:true;Layout.minimumWidth:0
                    }
                    AbyssCheckBox {
                        visible:root.expandedControls
                        text:"Custom size"
                        checked:root.allTargetsCustom
                        enabled:root.targets.length>0 && !root.anyTargetLocked
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onToggled:root.change("customSize",checked)
                    }
                    AbyssCheckBox {
                        objectName:"abyssModuleJoinCorner"
                        visible:root.expandedControls
                        text:root.nearbyCorner
                            ? "Connect to "+root.nearbyCorner+" corner"
                            : "Join nearby corner"
                        checked:root.targets.length>0 && root.targets.every(p=>p.joinCorner)
                        enabled:root.targets.length>0 && (root.targets.every(p=>!!Placement.cornerForModule(
                            root.moduleLayer.layoutRecords,p.id,root.width,root.height)) || checked)
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onToggled:root.change("joinCorner",checked)
                        StyledToolTip {
                            text:root.nearbyCorner
                                ? "Extend this module's local surface to the corner and attach its popup to both Screen Edges. Module size stays unchanged."
                                : "The nearest visible module within 160 px of a corner can connect to it."
                        }
                    }
                    AbyssSlider {
                        Layout.maximumWidth: 210 * Appearance.fontSizeScale
                        visible:root.expandedControls
                        from:.6;to:1.8
                        value:root.selected?.customSize
                            ? root.selected.size
                            : Placement.edgeSize(
                                root.draftOptions,
                                root.selected?.edge ?? root.editingEdge)
                        enabled:root.allTargetsCustom && !root.anyTargetLocked
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        onMoved:root.change("size",value)
                    }
                }

            }
        }
    }
}
