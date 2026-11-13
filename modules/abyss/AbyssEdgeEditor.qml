pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.abyss.looks
import qs.modules.abyss.settings
import "looks/AbyssGeometry.js" as Geometry
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
        implicitWidth: 20 * Appearance.fontSizeScale
        implicitHeight: root.editorActionSize
        Accessible.role: Accessible.StaticText
        Accessible.name: description
        MaterialSymbol {
            anchors.centerIn: parent
            text: glyph
            iconSize: 16 * Appearance.fontSizeScale
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
    component DockTogglePill: Rectangle {
        id: pillRoot
        property string icon: ""
        property string tooltipText: ""
        property bool active: false
        readonly property bool checked: active
        signal clicked()

        implicitWidth: 30
        implicitHeight: 30
        width: 30
        height: 30
        radius: 15
        opacity: pillRoot.enabled ? 1.0 : 0.38
        scale: pillMouse.pressed && pillRoot.enabled ? 0.94 : 1.0
        color: pillRoot.active
            ? Qt.alpha(Appearance.colors.colPrimary, pillMouse.containsMouse ? 0.30 : 0.22)
            : (pillMouse.pressed && pillRoot.enabled
                ? Appearance.colors.colLayer2Active
                : (pillMouse.containsMouse && pillRoot.enabled
                    ? Appearance.colors.colLayer2Hover
                    : Qt.alpha(Appearance.colors.colLayer2, 0.55)))
        border.width: 1
        border.color: pillRoot.active
            ? Qt.alpha(Appearance.colors.colPrimary, 0.58)
            : (pillMouse.containsMouse && pillRoot.enabled
                ? Qt.alpha(Appearance.colors.colOutlineVariant, 0.45)
                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.22))

        MaterialSymbol {
            anchors.centerIn: parent
            text: pillRoot.icon
            iconSize: 16
            fill: pillRoot.active ? 1 : 0
            color: pillRoot.active
                ? Appearance.colors.colPrimary
                : Appearance.colors.colOnLayer1
        }

        MouseArea {
            id: pillMouse
            anchors.fill: parent
            enabled: pillRoot.enabled
            hoverEnabled: true
            cursorShape: pillRoot.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: pillRoot.clicked()
        }

        StyledToolTip {
            position: "top"
            extraVisibleCondition: pillMouse.containsMouse && pillRoot.tooltipText.length > 0
            text: pillRoot.tooltipText
        }
    }
    component ModuleTileArt: Item {
        id: artRoot
        property string kind: "widgets"
        property string glyph: "widgets"
        property string edge: "top"
        property bool inDraft: false
        property bool active: false
        property bool locked: false

        // Top-left Screen Edge tag pill
        Rectangle {
            id: edgeTag
            anchors.top: parent.top
            anchors.left: parent.left
            height: 15
            width: edgeTagRow.implicitWidth + 8
            radius: 7.5
            color: artRoot.inDraft
                ? Qt.alpha(Appearance.colors.colPrimary, artRoot.active ? 0.22 : 0.12)
                : Qt.alpha(Appearance.colors.colLayer3, 0.72)
            border.width: 1
            border.color: artRoot.inDraft
                ? Qt.alpha(Appearance.colors.colPrimary, 0.38)
                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.26)

            Row {
                id: edgeTagRow
                anchors.centerIn: parent
                spacing: 2

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: artRoot.inDraft
                        ? (artRoot.edge === "bottom" ? "BTM" : artRoot.edge.toUpperCase())
                        : "NEW"
                    font.pixelSize: 8 * Appearance.fontSizeScale
                    font.weight: Font.DemiBold
                    color: artRoot.inDraft
                        ? Appearance.colors.colPrimary
                        : Appearance.colors.colSubtext
                }

                MaterialSymbol {
                    visible: artRoot.locked
                    anchors.verticalCenter: parent.verticalCenter
                    text: "lock"
                    iconSize: 9 * Appearance.fontSizeScale
                    color: Appearance.colors.colPrimary
                }
            }
        }

        // Centered miniature module preview surface
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(22, parent.height - 19)
            radius: 7
            color: Qt.alpha(Appearance.colors.colLayer3, 0.58)
            border.width: 1
            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.20)

            // Clock mini readout
            Row {
                visible: artRoot.kind === "clock"
                anchors.centerIn: parent
                spacing: 4
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "12:45"
                    font.pixelSize: 11 * Appearance.fontSizeScale
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 5
                    height: 5
                    radius: 2.5
                    color: Appearance.colors.colPrimary
                }
            }

            // Workspaces mini pills
            Row {
                visible: artRoot.kind === "workspaces"
                anchors.centerIn: parent
                spacing: 4
                Rectangle {
                    width: 16
                    height: 6
                    radius: 3
                    color: Appearance.colors.colPrimary
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.35)
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.25)
                }
                Rectangle {
                    width: 6
                    height: 6
                    radius: 3
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.20)
                }
            }

            // Media / Cava equalizer bars
            Row {
                visible: artRoot.kind === "media" || artRoot.kind === "cava"
                anchors.centerIn: parent
                height: 16
                spacing: 3
                Repeater {
                    model: (artRoot.kind === "media" || artRoot.kind === "cava") ? [8, 14, 11, 16, 9] : []
                    delegate: Rectangle {
                        required property int modelData
                        y: (16 - modelData) / 2
                        width: 3
                        height: modelData
                        radius: 1.5
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            // System resources telemetry bars
            Column {
                id: resourceBarCol
                visible: artRoot.kind === "resources"
                anchors.centerIn: parent
                spacing: 3
                width: Math.max(28, parent.width - 20)
                Repeater {
                    model: artRoot.kind === "resources" ? [0.72, 0.48, 0.86] : []
                    delegate: Rectangle {
                        required property real modelData
                        width: resourceBarCol.width
                        height: 3
                        radius: 1.5
                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.16)
                        Rectangle {
                            width: parent.width * modelData
                            height: parent.height
                            radius: 1.5
                            color: Appearance.colors.colPrimary
                        }
                    }
                }
            }

            // Battery mini gauge
            Row {
                visible: artRoot.kind === "battery"
                anchors.centerIn: parent
                spacing: 2
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    height: 11
                    radius: 3
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colOnLayer1, 0.55)
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        width: 15
                        radius: 1.5
                        color: Appearance.colors.colPrimary
                    }
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: 5
                    radius: 1
                    color: Qt.alpha(Appearance.colors.colOnLayer1, 0.55)
                }
            }

            // Default module emblem + indicator bars
            Row {
                visible: artRoot.kind !== "clock"
                    && artRoot.kind !== "workspaces"
                    && artRoot.kind !== "media"
                    && artRoot.kind !== "cava"
                    && artRoot.kind !== "resources"
                    && artRoot.kind !== "battery"
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: artRoot.glyph
                    iconSize: 15 * Appearance.fontSizeScale
                    fill: 1
                    color: Appearance.colors.colPrimary
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Rectangle {
                        width: 26
                        height: 3.5
                        radius: 1.75
                        color: Qt.alpha(Appearance.colors.colOnLayer1, 0.55)
                    }
                    Rectangle {
                        width: 18
                        height: 3
                        radius: 1.5
                        color: Qt.alpha(Appearance.colors.colPrimary, 0.48)
                    }
                }
            }
        }
    }
    readonly property real editorActionSize: 30 * Appearance.fontSizeScale
    readonly property real rotateActionSize: editorActionSize
    // Compact actions also keep Save/Cancel reachable on narrow horizontal
    // toolbars, where four normal squares alone exceed the viewport.
    readonly property bool compactHeaderActions: !toolbarOnHorizontalEdge
        || toolbarScroll.width < 4*editorActionSize+72*Appearance.fontSizeScale
    readonly property real headerActionSize: compactHeaderActions
        ? 24 * Appearance.fontSizeScale : editorActionSize
    // On side Edges the narrower output picker shares its left edge with
    // IPC selectors, whose right edge matches the output-only toggle.
    readonly property real sideIpcDropdownWidth: Math.min(
        136 * Appearance.fontSizeScale,
        Math.max(0,
            toolbarScroll.width - (headerActionSize + Math.max(16,10 * Appearance.fontSizeScale))))
    readonly property real sideIpcSelectorWidth: sideIpcDropdownWidth
        + 6 * Appearance.fontSizeScale + headerActionSize
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
    readonly property var targetIds: selectedIds.length>1
        ? selectedIds.filter(id=>draft.some(p=>p.id===id))
        : selectedId && draft.some(p=>p.id===selectedId) ? [selectedId]
        : selectedIds.filter(id=>draft.some(p=>p.id===id))
    readonly property bool multiSelect: targetIds.length>1
    readonly property var targets: targetIds.map(id=>draft.find(p=>p.id===id)).filter(p=>p)
    readonly property bool anyTargetLocked: targets.some(p=>p.locked)
    readonly property bool allTargetsLocked: targets.length>0 && targets.every(p=>p.locked)
    readonly property bool allTargetsDisabled: targets.length>0 && targets.every(p=>!p.enabled)
    readonly property bool allTargetsCustom: targets.length>0 && targets.every(p=>p.customSize)
    readonly property bool canRotateSelection: targets.length>0
        && targets.every(p=>Placement.canRotateModule(p.kind))
    readonly property int selectedRotation: selected
        ? Placement.effectiveRotation(selected) : 0
    readonly property bool mixedSelectionRotation: multiSelect
        && targets.some(p=>Placement.effectiveRotation(p)!==selectedRotation)
    readonly property string rotateActionText: !targets.length
        ? "Rotate 90°"
        : mixedSelectionRotation
        ? "Rotate 90° (mixed)"
        : "Rotate 90° ("+selectedRotation+"°)"
    readonly property string rotateActionDescription: !targets.length
        ? "Select a module to rotate its orientation by 90°."
        : !canRotateSelection
        ? "This module type does not support manual rotation."
        : mixedSelectionRotation
        ? "Rotate selected modules clockwise by 90° (mixed orientations)."
        : "Orientation: "+selectedRotation+"°. Click to rotate clockwise to "+Placement.nextRotation(selectedRotation)+"°."
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
    property Item externalDockParent: null
    property Item externalLeftDockParent: null
    property Item externalRightDockParent: null
    readonly property bool externallyDocked: externalDockParent !== null
    readonly property bool splitSideDocks: externallyDocked
        && externalLeftDockParent !== null
        && externalRightDockParent !== null
    readonly property real desiredDockWidth: Math.min(
        2400,
        Math.max(680, Math.ceil(horizontalDock.implicitWidth + 12)))
    readonly property real desiredDockHeight: Math.round(horizontalDock.implicitHeight + 8)
    readonly property real desiredLeftDockWidth: Math.max(228, Math.round(Math.min(310, Math.max(244 * Appearance.fontSizeScale, previewPositions.compactKindWidth + 44))))
    readonly property real desiredLeftDockHeight: Math.max(168, Math.round(popupsDockCard.implicitHeight + 12))
    readonly property real desiredRightDockWidth: Math.max(244, Math.round(262 * Appearance.fontSizeScale))
    readonly property real desiredRightDockHeight: Math.max(200, Math.round(rightEdgeDockHeader.implicitHeight + rightEdgeDockScrollContent.implicitHeight + 26 * Appearance.fontSizeScale))
    // The editor stays on its current Screen Edge until a module/IPC preview
    // physically overlaps its control surface; selection alone never moves it.
    property string toolbarEdge: "bottom"
    readonly property bool toolbarOnHorizontalEdge:
        externallyDocked || toolbarEdge === "top" || toolbarEdge === "bottom"
    readonly property bool useHorizontalDock: (typeof splitSideDocks !== "undefined" && splitSideDocks) || ((typeof externallyDocked !== "undefined" && externallyDocked)
        ? ((externalDockParent?.width ?? 0) <= 0 || (externalDockParent?.width ?? 0) >= 500)
        : (toolbarOnHorizontalEdge
            && (width - 48) >= 700 * Appearance.fontSizeScale
            && height >= 420 * Appearance.fontSizeScale))
    property string editorSection: "modules"
    property string moduleSearchText: ""
    readonly property string activeDockTab: splitSideDocks
        ? "modules"
        : (editingPopups ? "popups" : (editorSection === "edge" ? "edge" : "modules"))
    readonly property real dockToolbarSpan: Math.min(
        width - 48, 980 * Appearance.fontSizeScale)
    readonly property bool toolbarWideControls: !splitSideDocks
        && toolbarOnHorizontalEdge && toolbarScroll.width >= (editingPopups
            ? ipcSelectorSpan : 520*Appearance.fontSizeScale)
    // The Module side is only as wide as its picker + action icons. The Edge
    // side keeps room for two readable sliders and their value gutters.
    // Both widths are independent of the body's resulting span, avoiding a
    // layout-size feedback loop when the toolbar relocates.
    readonly property real moduleToolbarSpan: Math.max(
        520*Appearance.fontSizeScale,
        moduleHeaderActions.implicitWidth + (270 + 2*10 + 1)*Appearance.fontSizeScale)
        + 2*editorBody.padding
    // The compact IPC labels fit side by side without the previous
    // minimum 520px content track, which only produced an empty tail.
    readonly property real ipcSelectorSpan:
        previewPositions.compactKindWidth
            + previewPositions.compactEdgeWidth
            + previewPositions.compactAlignmentWidth
            + (30 + 3*6 + 8)*Appearance.fontSizeScale
    readonly property real ipcToolbarSpan:
        Math.max(450*Appearance.fontSizeScale,ipcSelectorSpan)
            + 2*editorBody.padding
    property var guides: []
    property bool snapEnabled: true
    property bool outputOnly: true
    property bool editingPopups: false
    readonly property var galleryEntries: {
        const entries = draft.map(p => ({
            key: p.id,
            inDraft: true,
            placementId: p.id,
            kind: p.kind,
            title: Placement.label(p.kind),
            edge: p.edge,
            enabled: p.enabled !== false,
            locked: p.locked === true
        }))
        for (const kind of Placement.catalog) {
            if (!draft.some(p => p.kind === kind)) {
                entries.push({
                    key: "catalog-" + kind,
                    inDraft: false,
                    placementId: "",
                    kind: kind,
                    title: Placement.label(kind),
                    edge: root.editingEdge,
                    enabled: false,
                    locked: false
                })
            }
        }
        return entries
    }
    readonly property var filteredGalleryEntries: {
        const q = moduleSearchText.trim().toLowerCase()
        if (!q) return galleryEntries
        return galleryEntries.filter(entry =>
            entry.title.toLowerCase().includes(q)
            || entry.kind.toLowerCase().includes(q)
            || entry.edge.toLowerCase().includes(q))
    }
    property string companionDraftEdge: "bottom"
    property real companionDraftAlong: 0.72
    property string _initialCompanionEdge: "bottom"
    property real _initialCompanionAlong: 0.72
    property bool _draggingCompanion: false
    readonly property alias companionMannequinItem: companionMannequin
    readonly property bool expandedControls: true
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
    readonly property string nearbyCorner: root.visible && selectedId.length > 0
        ? Placement.cornerForModule(moduleLayer.layoutRecords,selectedId,width,height) : ""
    readonly property var selected: draft.find(p => p.id === selectedId)
    readonly property var layoutConflicts: root.visible
        ? Placement.conflicts(moduleLayer.layoutRecords) : []
    readonly property var draftOptions: Object.assign({},Config.options?.abyss?.modules,{gap:gap,edgeSizes:edgeSizes,size:moduleScale,
        singleModuleExpansion:singleModuleExpansion,edgeThicknesses:edgeThicknesses,edgeWidthAffectsModules:edgeWidthAffectsModules,edgeJoinModules:edgeJoinModules,edgeModuleRadii:edgeModuleRadii,edgeRoundZeroCorners:edgeRoundZeroCorners,edgeThickness:AbyssStyle.perimeterThickness,cornerRadius:AbyssStyle.perimeterRadius})

    // Resolve the actual footprint on the current Edge and conservatively
    // predict the same centered control surface on alternate Edges. Merely
    // editing Bottom Edge or selecting its modules cannot relocate the toolbar.
    function toolbarFootprint(edge): var {
        if (edge === toolbarEdge && editorBody.targetRecord?.content)
            return editorBody.targetRecord.content
        const horizontal = edge === "top" || edge === "bottom"
        const length = horizontal ? width : height
        if (length <= 48) return null
        const horizontalDock = horizontal
            && (width - 48) >= 700 * Appearance.fontSizeScale
            && height >= 420 * Appearance.fontSizeScale
        const pad = horizontalDock ? 8 * Appearance.fontSizeScale : AbyssStyle.contentPadding
        const span = horizontal
            ? (horizontalDock
                ? Math.min(width-48,dockToolbarSpan)
                : Math.min(width-48,editingPopups ? ipcToolbarSpan : moduleToolbarSpan))
            : Math.min(height-48,Math.max(toolbar.implicitHeight
                + pad*2,height*.72))
        const depth = horizontal
            ? Math.min(Math.max(80,height*.65),toolbar.implicitHeight
                + pad*2)
            : Math.min(width-48,260*Appearance.fontSizeScale)
        // Use the same inset/padding/clamping rules as the real BodyHost.
        return Geometry.panel(width,height,edgeInsets,edge,
            (length-span)/2,span,depth,1,pad,[],true).content
    }

    function bestToolbarEdge(): string {
        if (externallyDocked) return "bottom"
        if (width<=48 || height<=48) return toolbarEdge
        const footprints = {}
        for (const edge of ["bottom","top","right","left"])
            footprints[edge] = toolbarFootprint(edge)
        let previewRects = []
        if (root.editingPopups) {
            // IPC previews are treated like modules: only their *actual*
            // intersection with the controls can force a relocation.
            if (previewBody.targetRecord?.content)
                previewRects = [previewBody.targetRecord.content]
        } else if (companionMannequin.visible && root._draggingCompanion) {
            previewRects = [{x: companionMannequin.x, y: companionMannequin.y, width: companionMannequin.width, height: companionMannequin.height}]
        }
        return Placement.toolbarEdgeForRects(toolbarEdge,footprints,
            moduleLayer.layoutRecords,previewRects)
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
            draftPositions:draftPositions,positionEdits:positionEdits,
            companionDraftEdge:companionDraftEdge,companionDraftAlong:companionDraftAlong}))
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
    function rotateSelection(): void {
        if(!targets.length){feedback="Select a module first";return}
        if(!canRotateSelection){feedback="This module type does not support manual rotation";return}
        batch("rotation","step")
    }
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
    function _clonePlacementItems(sourceList): var {
        if (!Array.isArray(sourceList))
            return []
        const out = new Array(sourceList.length)
        for (let i = 0; i < sourceList.length; ++i) {
            const item = sourceList[i]
            out[i] = item && typeof item === "object" ? Object.assign({}, item) : item
        }
        return out
    }
    function begin(): void {
        _historyReady=false;_dragging=false;feedback=""
        draft = _clonePlacementItems(Placement.resolve(Config.options?.abyss?.modules,outputName,
            Placement.seed(moduleLayer.zones,moduleLayer.edge,width,height)))
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
        draftPositions=_clonePlacementItems(Config.options?.abyss?.positions)
        positionEdits=[];editingPopups=false
        editorSection="modules";moduleSearchText=""
        const companionCfg=Config.options?.abyss?.companion
        companionDraftEdge=["top","right","bottom","left"].includes(companionCfg?.edge)
            ? companionCfg.edge
            : (["top","right","bottom","left"].includes(moduleLayer.edge) ? moduleLayer.edge : "bottom")
        companionDraftAlong=Number.isFinite(Number(companionCfg?.along))
            ? Math.max(0.08,Math.min(0.92,Number(companionCfg.along))) : 0.72
        _initialCompanionEdge=companionDraftEdge
        _initialCompanionAlong=companionDraftAlong
        _draggingCompanion=false
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
            if(companionDraftEdge!==_initialCompanionEdge || Math.abs(companionDraftAlong-_initialCompanionAlong)>0.0005) {
                writes["abyss.companion.edge"]=companionDraftEdge
                writes["abyss.companion.along"]=Math.round(companionDraftAlong*1000)/1000
            }
            Config.setNestedValues(writes)
        }
        guides = []
        _historyReady=false
        _draggingCompanion=false
        clearDrag()
        GlobalStates.abyssEditing = false
    }
    // Reset only the current IPC kind/output override; remain in draft until Done.
    // Modules mode continues to reset the full module layout as before.
    function resetIpcPosition(): void {
        if (!editingPopups) return
        previewPositions.apply(null)
    }
    function reset(): void {
        clearDrag();rememberHistory()
        draft = Placement.withUnifiedEdgeModules(
            Placement.seed(moduleLayer.zones,moduleLayer.edge,width,height),
            Config.options?.abyss?.modules?.autoUnifiedEdgeLaunchers === true)
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
        companionDraftEdge=["top","right","bottom","left"].includes(moduleLayer.edge) ? moduleLayer.edge : "bottom"
        companionDraftAlong=0.72
        draftPositions=JSON.parse(JSON.stringify(Config.options?.abyss?.positions ?? []));positionEdits=[]
        refreshHandles()
    }
    function change(key,value): void {
        if(multiSelect || key==="rotation"){batch(key,value);return}
        if(selected?.locked && ["edge","position","alignment","size","customSize","depth"].includes(key)) {
            feedback="Unlock this module before changing its placement or size";return
        }
        feedback=""
        draft = draft.map(p => p.id === selectedId ? Object.assign({},p,
            key==="customSize" && value && !p.customSize ? {size:Placement.edgeSize(draftOptions,p.edge)} : {},
            key==="edge" && (Placement.hasExplicitRotation(p.rotation) || value!==p.edge) ? {rotation:Placement.effectiveRotation(p)} : {},
            {[key]:value}) : p)
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
        const targetSpan=(horizontal ? previewBody.contentItem.item?.desiredWidth ?? 390 : previewBody.contentItem.item?.desiredHeight ?? 120)+previewBody.padding*2
        const inset=Math.max(16,(horizontal ? root.edgeInsets?.left : root.edgeInsets?.top) ?? 0)
        const endInset=Math.max(16,(horizontal ? root.edgeInsets?.right : root.edgeInsets?.bottom) ?? 0)
        const ratio=Math.max(0,Math.min(1,(point-targetSpan/2-inset)/Math.max(1,length-inset-endInset-targetSpan)))
        const values=Object.assign({},previewPosition,{edge:location.edge,alignment:"custom",position:ratio})
        const output=outputOnly ? outputName : ""
        editPosition(Presentation.save(draftPositions,previewKind,output,values),previewKind,output,values)
    }
    function moveCompanion(x,y): void {
        const location=Placement.project(x,y,width,height), horizontal=["top","bottom"].includes(location.edge)
        const length=Math.max(1,horizontal ? width : height), point=horizontal ? x : y
        const nextAlong=Math.max(0.08,Math.min(0.92,point/length))
        companionDraftEdge=location.edge
        companionDraftAlong=nextAlong
        editingEdge=location.edge
        root.scheduleToolbarRelocation()
        const now=Date.now()
        if (now-lastImpulse>80) {
            controller.impulse(location.edge,nextAlong*length,84,.28,1,"drag")
            lastImpulse=now
        }
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
    function moduleGlyph(kind): string {
        switch (kind) {
        case "distroIcon": return "apps"
        case "activeWindow": return "web_asset"
        case "resources": return "monitoring"
        case "media": return "music_note"
        case "cava": return "equalizer"
        case "workspaces": return "workspaces"
        case "clock": return "schedule"
        case "utilButtons": return "tune"
        case "battery": return "battery_full"
        case "tray": return "dock_to_bottom"
        case "timer": return "timer"
        case "shellUpdate": return "system_update_alt"
        case "weather": return "partly_cloudy_day"
        case "taskbar": return "view_week"
        case "notesTimers": return "sticky_note_2"
        case "notificationActivity": return "notifications"
        default: return "widgets"
        }
    }
    function togglePlacementEnabled(id): void {
        if (_dragging) {
            feedback = "Finish moving the module group before editing its settings"
            return
        }
        const entry = draft.find(p => p.id === id)
        if (!entry) return
        rememberHistory()
        const nextEnabled = entry.enabled === false
        const options = Object.assign({}, draftOptions, {extents: moduleLayer.measuredExtents, editing: true})
        const result = Placement.checkedBatch(draft, [id], "enabled", nextEnabled, width, height, options, Appearance.fontSizeScale, moduleLayer.renderedRecords)
        feedback = result.rejected || ""
        if (result.rejected) return
        draft = result.placements
        if (nextEnabled)
            select(id)
    }
    function scrollGalleryToSelection(): void {
        if (!useHorizontalDock || activeDockTab !== "modules" || !selectedId)
            return
        const idx = filteredGalleryEntries.findIndex(e => e.inDraft && e.placementId === selectedId)
        if (idx < 0 || moduleGalleryFlick.width <= 0)
            return
        const stride = 118 * Appearance.fontSizeScale + 8 * Appearance.fontSizeScale
        const left = idx * stride
        const right = left + 118 * Appearance.fontSizeScale
        const maxX = Math.max(0, moduleGalleryFlick.contentWidth - moduleGalleryFlick.width)
        if (left < moduleGalleryFlick.contentX)
            moduleGalleryFlick.contentX = Math.max(0, left - 8)
        else if (right > moduleGalleryFlick.contentX + moduleGalleryFlick.width)
            moduleGalleryFlick.contentX = Math.min(maxX, right - moduleGalleryFlick.width + 8)
    }
    function syncPaletteToSelection(): void {
        const kind = root.selected?.kind ?? ""
        if (!kind) return
        const idx = Placement.catalog.indexOf(kind)
        if (idx >= 0) {
            if (palette.currentIndex !== idx)
                palette.currentIndex = idx
            if (dockPalette.currentIndex !== idx)
                dockPalette.currentIndex = idx
        }
    }
    onSelectedChanged: {
        if (selected) {
            editingEdge = selected.edge
            root.syncPaletteToSelection()
            Qt.callLater(() => root.scrollGalleryToSelection())
        }
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
    onOutputOnlyChanged: {root.scheduleToolbarRelocation();root.queueHistory()}

    Connections {
        target:root.moduleLayer
        enabled:root.visible
        function onMeasuredExtentsChanged(){root.reflowGroup()}
        // A module can grow into the controls after its first live measurement.
        function onLayoutRecordsChanged(){root.scheduleToolbarRelocation()}
    }

    Timer {
        id: toolbarRelocate
        interval: 90
        repeat: false
        onTriggered: root.relocateToolbar()
    }

    function add(kind): void {
        // A unified launcher is one module entry, never a second instance of
        // Notes/Timers or Notifications/Activities on the same output.
        if (Placement.isUnifiedKind(kind)) {
            const present=draft.find(p => p.kind === kind && p.enabled)
            if (present) {
                select(present.id)
                feedback="This unified module is already on this output"
                return
            }
        }
        if (draft.length >= 24) return
        const existing = draft.find(p => p.kind === kind && !p.enabled)
        if (existing) {
            const result=Placement.checkedBatch(draft,[existing.id],"enabled",true,width,height,
                Object.assign({},draftOptions,{extents:moduleLayer.measuredExtents,editing:true}),Appearance.fontSizeScale)
            if(result.rejected){feedback=result.rejected;return}
            draft=result.placements;select(existing.id);return
        }
        const id = kind+"-"+Date.now()
        const proposed=Placement.normalize(draft.concat([{id:id,kind:kind,edge:editingEdge,position:.5,rotation:0}]),"top")
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
        model: root.visible ? root.handles : []
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
                } else if(event.key===Qt.Key_R){
                    if(!root.targetIds.includes(handle.modelData))root.select(handle.modelData)
                    root.rotateSelection();event.accepted=true
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
        model: root.visible ? ["top","right","bottom","left"] : []
        AbyssLabel {
            required property string modelData
            // These decorative hints compete with modules/controls on a tiny
            // output. The toolbar's Edge selector remains available there.
            visible:root.width>=520 && root.height>=420
            readonly property var editorSurface: editorBody.record?.surface ?? null
            readonly property bool editorEdge: !root.externallyDocked && modelData === root.toolbarEdge
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
                    : modelData === "bottom" ? (root.externallyDocked ? root.height-height-64 : root.height-220)
                    : (root.height-height)/2
            }
        }
    }
    AbyssBodyHost {
        id: editorBody
        z: 30
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
        open: root.visible && !root.externallyDocked
        padding: root.useHorizontalDock
            ? 8 * Appearance.fontSizeScale : AbyssStyle.contentPadding
        // Horizontal Edges use the familiar wide control strip. If both are
        // busy, the same editor can move to a side Edge with a deeper body and
        // a long vertical span instead of covering the module being edited.
        span: root.toolbarOnHorizontalEdge
            ? (root.useHorizontalDock
                ? Math.min(root.width-48,root.dockToolbarSpan)
                : Math.min(root.width-48,root.editingPopups
                    ? root.ipcToolbarSpan : root.moduleToolbarSpan))
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
    Item {
        id:companionMannequin
        objectName:"abyssCompanionMannequin"
        z:2
        visible:root.visible && !root.editingPopups && root.width>=240 && root.height>=200
        property bool customModelPresent:false
        readonly property real companionScale:Math.max(0.65,Math.min(1.5,Number(Config.options?.abyss?.companion?.size) || 1))
        readonly property bool horizontalEdge:["top","bottom"].includes(root.companionDraftEdge)
        width:(horizontalEdge ? 112 : 98)*companionScale
        height:(horizontalEdge ? 98 : 112)*companionScale
        readonly property real axisExtent:Math.max(1,horizontalEdge ? root.width : root.height)
        readonly property real axisSpan:horizontalEdge ? width : height
        readonly property real startInset:Math.max(12,((horizontalEdge ? root.edgeInsets?.left : root.edgeInsets?.top) ?? 0)+12)
        readonly property real endInset:Math.max(12,((horizontalEdge ? root.edgeInsets?.right : root.edgeInsets?.bottom) ?? 0)+12)
        readonly property real alongCoordinate:Math.max(startInset,Math.min(Math.max(startInset,axisExtent-axisSpan-endInset),axisExtent*root.companionDraftAlong-axisSpan/2))
        readonly property real normalCoordinate:root.companionDraftEdge==="top"
            ? Math.max(2,root.edgeInsets?.top ?? 0)
            : root.companionDraftEdge==="bottom"
            ? Math.max(2,root.height-(root.edgeInsets?.bottom ?? 0)-height)
            : root.companionDraftEdge==="left"
            ? Math.max(2,root.edgeInsets?.left ?? 0)
            : Math.max(2,root.width-(root.edgeInsets?.right ?? 0)-width)
        x:horizontalEdge ? alongCoordinate : normalCoordinate
        y:horizontalEdge ? normalCoordinate : alongCoordinate
        function invalidateCompanionRegion(): void {if(companionMannequinRegion)companionMannequinRegion.changed()}
        onXChanged:invalidateCompanionRegion();onYChanged:invalidateCompanionRegion()
        onWidthChanged:invalidateCompanionRegion();onHeightChanged:invalidateCompanionRegion()
        onVisibleChanged:invalidateCompanionRegion()
        Accessible.role:Accessible.Button
        Accessible.name:"Companion primary position · "+root.companionDraftEdge
        Rectangle {
            anchors.fill:parent;anchors.margins:-2
            radius:14
            color:Qt.alpha(AbyssStyle.accent,companionDragArea.pressed ? .24 : companionDragArea.containsMouse ? .16 : .09)
            border.width:companionDragArea.pressed ? 2 : 1
            border.color:Qt.alpha(AbyssStyle.accent,companionDragArea.pressed ? .92 : .65)
        }
        Item {
            id:companionSilhouette
            visible:!companionMannequin.customModelPresent
            anchors.centerIn:parent
            anchors.verticalCenterOffset:root.companionDraftEdge==="top" ? -9 : 9
            width:Math.min(56*companionMannequin.companionScale,Math.max(24,companionMannequin.width-12))
            height:Math.min(64*companionMannequin.companionScale,Math.max(24,companionMannequin.height-26))
            rotation:root.companionDraftEdge==="top" ? 180 : root.companionDraftEdge==="left" ? 90 : root.companionDraftEdge==="right" ? -90 : 0
            Rectangle {
                anchors.horizontalCenter:parent.horizontalCenter
                anchors.bottom:parent.bottom
                width:parent.width*.84
                height:parent.height*.78
                radius:width*.48
                color:Qt.alpha(AbyssStyle.accent,.28)
                border.width:1.5
                border.color:Qt.alpha(AbyssStyle.accent,.82)
                Row {
                    anchors.centerIn:parent
                    spacing:8*companionMannequin.companionScale
                    Rectangle { width:5*companionMannequin.companionScale; height:8*companionMannequin.companionScale; radius:width/2; color:AbyssStyle.textColor }
                    Rectangle { width:5*companionMannequin.companionScale; height:8*companionMannequin.companionScale; radius:width/2; color:AbyssStyle.textColor }
                }
            }
        }
        Rectangle {
            z:10
            anchors.horizontalCenter:parent.horizontalCenter
            y:root.companionDraftEdge==="top" ? parent.height-height-2 : 2
            width:companionBadgeRow.implicitWidth+10
            height:18
            radius:9
            color:Qt.alpha(AbyssStyle.surfaceDeep,.88)
            border.width:1
            border.color:Qt.alpha(AbyssStyle.accent,.55)
            Row {
                id:companionBadgeRow
                anchors.centerIn:parent
                spacing:3
                MaterialSymbol {
                    anchors.verticalCenter:parent.verticalCenter
                    text:"open_with"
                    iconSize:11
                    color:AbyssStyle.accent
                }
                AbyssLabel {
                    anchors.verticalCenter:parent.verticalCenter
                    text:"Companion"
                    font.pixelSize:9*Appearance.fontSizeScale
                    font.bold:true
                    color:AbyssStyle.textColor
                }
            }
        }
        MouseArea {
            id:companionDragArea
            z:20
            objectName:"abyssCompanionMannequinDrag"
            anchors.fill:parent
            hoverEnabled:true
            cursorShape:pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onPressed: {
                root.rememberHistory()
                root._draggingCompanion=true
                root.editingEdge=root.companionDraftEdge
            }
            onPositionChanged:mouse=> {
                if(!pressed || !root._draggingCompanion) return
                const point=mapToItem(root,mouse.x,mouse.y)
                root.moveCompanion(point.x,point.y)
            }
            onReleased: {
                root._draggingCompanion=false
                root.queueHistory()
            }
            onCanceled: {
                root._draggingCompanion=false
                root.queueHistory()
            }
        }
    }
    readonly property Region companionMannequinRegion: Region {
        x:Math.floor(companionMannequin.x);y:Math.floor(companionMannequin.y)
        width:root.editingPopups || !companionMannequin.visible ? 0 : Math.ceil(companionMannequin.x+companionMannequin.width)-Math.floor(companionMannequin.x)
        height:root.editingPopups || !companionMannequin.visible ? 0 : Math.ceil(companionMannequin.y+companionMannequin.height)-Math.floor(companionMannequin.y)
    }
    readonly property Region previewRegion: Region { x:previewBody.inputBounds.x;y:previewBody.inputBounds.y;width:previewBody.inputBounds.width;height:previewBody.inputBounds.height }
    readonly property Region toolbarRegion: Region { item: toolbar }
    readonly property Region ipcKindRegion: Region { item:previewPositions.compactKindCombo.popup.contentItem; width:previewPositions.compactKindCombo.popup.visible ? previewPositions.compactKindCombo.popup.contentItem.width : 0 }
    readonly property Region ipcOutputRegion: Region { item:ipcOutputChoice.popup.contentItem; width:ipcOutputChoice.popup.visible ? ipcOutputChoice.popup.contentItem.width : 0 }
    readonly property Region paletteRegion: Region { item: palette.popup.contentItem; width: palette.popup.visible ? palette.popup.contentItem.width : 0 }
    readonly property Region edgeRegion: Region { item: edgeChoice.popup.contentItem; width: edgeChoice.popup.visible ? edgeChoice.popup.contentItem.width : 0 }
    readonly property Region alignmentRegion: Region { item: alignmentChoice.popup.contentItem; width: alignmentChoice.popup.visible ? alignmentChoice.popup.contentItem.width : 0 }
    readonly property Region dockPaletteRegion: Region { item: dockPalette.popup.contentItem; width: dockPalette.popup.visible ? dockPalette.popup.contentItem.width : 0 }
    readonly property Region dockAlignmentRegion: Region { item: dockAlignmentChoice.popup.contentItem; width: dockAlignmentChoice.popup.visible ? dockAlignmentChoice.popup.contentItem.width : 0 }
    readonly property Region dockIpcOutputRegion: Region { item: dockIpcOutputChoice.popup.contentItem; width: dockIpcOutputChoice.popup.visible ? dockIpcOutputChoice.popup.contentItem.width : 0 }
    readonly property var externalPopupRegions: [paletteRegion, ipcKindRegion, ipcOutputRegion, edgeRegion, alignmentRegion, dockPaletteRegion, dockAlignmentRegion, dockIpcOutputRegion]
    readonly property var regions: inputRegions.concat(root.externallyDocked ? [] : [toolbarRegion], externalPopupRegions, [previewRegion, companionMannequinRegion], (root.editingPopups || root.splitSideDocks) ? previewPositions.inputRegions : [])

    Item {
        id: leftPopupsDockSurface
        objectName: "abyssLeftPopupsDock"
        parent: root.splitSideDocks ? root.externalLeftDockParent : root
        visible: root.splitSideDocks && (root.visible || (root.externalLeftDockParent?.visible ?? false))
        enabled: root.visible && root.splitSideDocks
        x: 0
        y: 0
        width: root.splitSideDocks ? (root.externalLeftDockParent?.width ?? root.desiredLeftDockWidth) : 0
        height: root.splitSideDocks ? (root.externalLeftDockParent?.height ?? root.desiredLeftDockHeight) : 0
        clip: true

        Flickable {
            anchors.fill: parent
            anchors.margins: root.splitSideDocks ? 6 : 10
            clip: true
            contentWidth: width
            contentHeight: leftPopupsDockColumn.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Item {
                id: leftPopupsDockColumn
                width: parent.width
                implicitHeight: popupsDockCard.implicitHeight
            }
        }
    }

    Item {
        id: rightEdgeDockSurface
        objectName: "abyssRightEdgeDock"
        parent: root.splitSideDocks ? root.externalRightDockParent : root
        visible: root.splitSideDocks && (root.visible || (root.externalRightDockParent?.visible ?? false))
        enabled: root.visible && root.splitSideDocks
        x: 0
        y: 0
        width: root.splitSideDocks ? (root.externalRightDockParent?.width ?? root.desiredRightDockWidth) : 0
        height: root.splitSideDocks ? (root.externalRightDockParent?.height ?? root.desiredRightDockHeight) : 0
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: root.splitSideDocks ? 6 : 10
            spacing: (root.splitSideDocks ? 6 : 8) * Appearance.fontSizeScale

            RowLayout {
                id: rightEdgeDockHeader
                objectName: root.splitSideDocks ? "abyssEditorEdgeMode" : ""
                Layout.fillWidth: true
                spacing: 6

                MaterialSymbol {
                    text: "border_outer"
                    iconSize: 17 * Appearance.fontSizeScale
                    color: Appearance.colors.colPrimary
                }

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: Translation.tr("Screen Edge")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                Rectangle {
                    implicitHeight: 20
                    implicitWidth: activeEdgeBadgeLabel.implicitWidth + 10
                    radius: 10
                    color: Qt.alpha(Appearance.colors.colPrimary, 0.16)
                    border.width: 1
                    border.color: Qt.alpha(Appearance.colors.colPrimary, 0.36)

                    StyledText {
                        id: activeEdgeBadgeLabel
                        anchors.centerIn: parent
                        text: root.editingEdge.toUpperCase()
                        font.pixelSize: 9 * Appearance.fontSizeScale
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colPrimary
                    }
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: rightEdgeDockScrollContent.implicitHeight
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: rightEdgeDockScrollContent
                    width: parent.width
                    spacing: 8 * Appearance.fontSizeScale
                }
            }
        }
    }

    Item {
        id: toolbar
        objectName: "abyssEdgeEditorToolbar"
        readonly property var editorOwner: root
        visible: root.visible || (root.externallyDocked && (root.externalDockParent?.visible ?? false))
        enabled: root.visible
        parent: root.externallyDocked ? root.externalDockParent : editorBody.contentParent
        anchors.fill: parent
        implicitWidth: root.toolbarOnHorizontalEdge
            ? (root.useHorizontalDock ? horizontalDock.implicitWidth : toolbarColumn.implicitWidth)
            : 260*Appearance.fontSizeScale
        implicitHeight: root.useHorizontalDock
            ? horizontalDock.implicitHeight : toolbarColumn.implicitHeight

        Flickable {
            id: toolbarScroll
            objectName: "abyssEdgeEditorScroll"
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: root.useHorizontalDock
                ? horizontalDock.implicitHeight : toolbarColumn.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            // Very small outputs can still clamp the requested depth. Keep
            // all controls reachable on horizontal as well as side Edges.
            interactive: contentHeight > height

            AbyssCustomizationDock {
                id: horizontalDock
                objectName: root.useHorizontalDock ? "abyssEdgeEditorDock" : ""
                visible: root.useHorizontalDock
                width: toolbarScroll.width
                embeddedSurface: true
                horizontalPadding: 4
                verticalPadding: 6
                topBarHeight: 38 * Appearance.fontSizeScale
                trayGap: 6 * Appearance.fontSizeScale
                trayExpanded: true
                trayHeight: (152 + (dockFeedbackBanner.visible ? 26 : 0)) * Appearance.fontSizeScale
                contentPreferredWidth: !root.splitSideDocks && root.activeDockTab === "edge"
                    ? Math.ceil(edgeCardsGrid.implicitWidth + 16)
                    : (!root.splitSideDocks && root.activeDockTab === "popups"
                        ? Math.ceil(popupsCardColumn.implicitWidth + 24)
                        : Math.max(
                            Math.ceil(moduleGalleryRow.implicitWidth + 16),
                            dockModuleInspector.visible
                                ? Math.ceil(dockModuleInspectorLayout.implicitWidth + 24)
                                : 0))
                autoSwitchTab: false
                activeTab: root.activeDockTab
                tabs: root.splitSideDocks
                    ? [
                        {
                            key: "modules",
                            label: Translation.tr("Modules"),
                            icon: "widgets",
                            objectName: root.useHorizontalDock ? "abyssEditorModulesMode" : "",
                            tooltipText: Translation.tr("Screen Edge modules gallery and module inspector")
                        }
                    ]
                    : [
                        {
                            key: "modules",
                            label: Translation.tr("Modules"),
                            icon: toolbarScroll.width >= 880 * Appearance.fontSizeScale ? "widgets" : "",
                            objectName: root.useHorizontalDock ? "abyssEditorModulesMode" : "",
                            tooltipText: Translation.tr("Screen Edge modules gallery and module inspector")
                        },
                        {
                            key: "edge",
                            label: toolbarScroll.width >= 820 * Appearance.fontSizeScale
                                ? Translation.tr("Screen Edge") : Translation.tr("Edge"),
                            icon: toolbarScroll.width >= 880 * Appearance.fontSizeScale ? "border_outer" : "",
                            objectName: root.useHorizontalDock ? "abyssEditorEdgeMode" : "",
                            tooltipText: Translation.tr("Configure active Screen Edge thickness, spacing, scale and curvature")
                        },
                        {
                            key: "popups",
                            label: toolbarScroll.width >= 820 * Appearance.fontSizeScale
                                ? Translation.tr("Popups & Panels") : Translation.tr("Popups"),
                            icon: toolbarScroll.width >= 880 * Appearance.fontSizeScale ? "open_in_new" : "",
                            objectName: root.useHorizontalDock ? "abyssEditorIpcMode" : "",
                            tooltipText: Translation.tr("Position OSD and IPC indicator surfaces")
                        }
                    ]
                showUndo: true
                canUndo: root.undoStack.length > 0
                undoObjectName: root.useHorizontalDock ? "abyssLayoutUndo" : ""
                showSearch: root.activeDockTab === "modules"
                searchText: root.moduleSearchText
                searchPlaceholder: Translation.tr("Search modules...")
                searchObjectName: root.useHorizontalDock ? "abyssModuleSearchInput" : ""
                showCancel: true
                cancelLabel: Translation.tr("Cancel")
                cancelObjectName: root.useHorizontalDock ? "abyssLayoutCancel" : ""
                doneLabel: Translation.tr("Done")
                doneObjectName: root.useHorizontalDock ? "abyssLayoutDone" : ""

                onUndoClicked: root.undo()
                onSearchEdited: text => root.moduleSearchText = text
                onCancelClicked: root.finish(false)
                onDoneClicked: root.finish(true)
                onTabClicked: key => {
                    if (key === "popups") {
                        root.editingPopups = true
                    } else {
                        root.editingPopups = false
                        root.editorSection = key === "edge" ? "edge" : "modules"
                    }
                }

                leadingControls: [
                    DockTogglePill {
                        objectName: root.useHorizontalDock ? "abyssLayoutReset" : ""
                        icon: "restart_alt"
                        active: false
                        tooltipText: root.editingPopups
                            ? Translation.tr("Reset selected IPC position")
                            : Translation.tr("Reset layout draft")
                        onClicked: root.editingPopups ? root.resetIpcPosition() : root.reset()
                    }
                ]

                trailingControls: [
                    DockTogglePill {
                        objectName: root.useHorizontalDock ? "abyssDockSnapToggle" : ""
                        icon: "grid_4x4"
                        active: root.snapEnabled
                        tooltipText: root.snapEnabled
                            ? Translation.tr("Snap to guides · on")
                            : Translation.tr("Snap to guides · off")
                        onClicked: root.snapEnabled = !root.snapEnabled
                    },
                    DockTogglePill {
                        objectName: root.useHorizontalDock ? "abyssEditorOutputOnly" : ""
                        icon: "monitor"
                        active: root.outputOnly
                        tooltipText: root.outputOnly
                            ? Translation.tr("This output only (%1)").arg(root.outputName)
                            : Translation.tr("All outputs (global)")
                        onClicked: root.outputOnly = !root.outputOnly
                    }
                ]

                ColumnLayout {
                    id: dockTrayColumn
                    anchors.fill: parent
                    spacing: 4 * Appearance.fontSizeScale

                    Rectangle {
                        id: dockFeedbackBanner
                        visible: dockFeedbackLabel.text.length > 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 22 * Appearance.fontSizeScale
                        radius: 8
                        color: Qt.alpha(Appearance.colors.colError, 0.14)
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colError, 0.38)

                        AbyssLabel {
                            id: dockFeedbackLabel
                            objectName: root.useHorizontalDock ? "abyssLayoutFeedback" : ""
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                            text: root.layoutConflicts[0] || root.feedback
                            font.pixelSize: 11 * Appearance.fontSizeScale
                            color: Appearance.colors.colError
                        }
                    }

                    // Tier 2A: Modules Gallery + Contextual Module Inspector Strip
                    ColumnLayout {
                        visible: root.activeDockTab === "modules"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6 * Appearance.fontSizeScale

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 100 * Appearance.fontSizeScale

                            Flickable {
                                id: moduleGalleryFlick
                                objectName: root.useHorizontalDock ? "abyssModuleGallery" : ""
                                anchors.fill: parent
                                clip: true
                                contentWidth: Math.max(width, moduleGalleryRow.implicitWidth)
                                contentHeight: height
                                flickableDirection: Flickable.HorizontalFlick
                                boundsBehavior: Flickable.StopAtBounds
                                interactive: contentWidth > width

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: event => {
                                        if (toolbarScroll.interactive && Math.abs(event.angleDelta.y) > Math.abs(event.angleDelta.x)) {
                                            event.accepted = false
                                            return
                                        }
                                        const delta = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y)
                                            ? event.angleDelta.x : event.angleDelta.y
                                        const maxX = Math.max(0, moduleGalleryFlick.contentWidth - moduleGalleryFlick.width)
                                        moduleGalleryFlick.contentX = Math.max(0, Math.min(maxX, moduleGalleryFlick.contentX - delta * 0.65))
                                        event.accepted = true
                                    }
                                }

                                Row {
                                    id: moduleGalleryRow
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 8 * Appearance.fontSizeScale

                                    Repeater {
                                        model: root.filteredGalleryEntries
                                        delegate: AbyssCustomizationTile {
                                            required property var modelData
                                            objectName: "abyssModuleGalleryTile"
                                            tileId: String(modelData.key)
                                            title: String(modelData.title)
                                            subtitle: modelData.inDraft
                                                ? (String(modelData.edge).charAt(0).toUpperCase()
                                                    + String(modelData.edge).slice(1)
                                                    + (modelData.locked ? " · Locked" : ""))
                                                : Translation.tr("Available")
                                            icon: root.moduleGlyph(modelData.kind)
                                            active: Boolean(modelData.inDraft && modelData.enabled)
                                            selected: Boolean(modelData.inDraft && root.targetIds.includes(modelData.placementId))
                                            separateBadgeClick: true
                                            tileWidth: 118 * Appearance.fontSizeScale
                                            previewHeight: 58 * Appearance.fontSizeScale
                                            tooltipText: modelData.inDraft
                                                ? (modelData.enabled
                                                    ? Translation.tr("%1 on %2 Edge — click to select, click ✓ to disable").arg(modelData.title).arg(modelData.edge)
                                                    : Translation.tr("%1 (disabled) — click to select, click + to enable").arg(modelData.title))
                                                : Translation.tr("Click to add %1 to %2 Edge").arg(modelData.title).arg(root.editingEdge)

                                            onClicked: {
                                                if (root.splitSideDocks && root.editingPopups)
                                                    root.editingPopups = false
                                                if (modelData.inDraft)
                                                    root.select(modelData.placementId)
                                                else
                                                    root.add(modelData.kind)
                                            }
                                            onBadgeClicked: {
                                                if (root.splitSideDocks && root.editingPopups)
                                                    root.editingPopups = false
                                                if (modelData.inDraft)
                                                    root.togglePlacementEnabled(modelData.placementId)
                                                else
                                                    root.add(modelData.kind)
                                            }

                                            ModuleTileArt {
                                                anchors.fill: parent
                                                kind: String(modelData.kind)
                                                glyph: root.moduleGlyph(modelData.kind)
                                                edge: String(modelData.edge)
                                                inDraft: Boolean(modelData.inDraft)
                                                active: Boolean(modelData.enabled)
                                                locked: Boolean(modelData.locked)
                                            }
                                        }
                                    }
                                }
                            }

                            StyledText {
                                visible: root.filteredGalleryEntries.length === 0
                                anchors.centerIn: parent
                                text: Translation.tr("No modules match \"%1\"").arg(root.moduleSearchText)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                            }
                        }

                        // Contextual Module Inspector Strip
                        Rectangle {
                            id: dockModuleInspector
                            objectName: root.useHorizontalDock ? "abyssDockModuleInspector" : ""
                            Layout.fillWidth: true
                            Layout.preferredHeight: 36 * Appearance.fontSizeScale
                            radius: 11
                            color: Qt.alpha(Appearance.colors.colLayer2, 0.46)
                            border.width: 1
                            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                            RowLayout {
                                id: dockModuleInspectorLayout
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 4 * Appearance.fontSizeScale

                                StyledComboBox {
                                    id: dockPalette
                                    objectName: root.useHorizontalDock ? "abyssModuleDropdown" : ""
                                    baseHeight: 28 * Appearance.fontSizeScale
                                    Layout.preferredWidth: (root.multiSelect ? 92 : 112) * Appearance.fontSizeScale
                                    Layout.maximumWidth: 128 * Appearance.fontSizeScale
                                    Layout.minimumWidth: 0
                                    popupMinimumWidth: 168 * Appearance.fontSizeScale
                                    model: Placement.catalog.map(kind => ({label: Placement.label(kind), kind: kind}))
                                    textRole: "label"
                                    valueRole: "kind"
                                    onActivated: {
                                        const chosenKind = currentValue
                                        const match = root.draft.find(p => p.kind === chosenKind && p.enabled)
                                            ?? root.draft.find(p => p.kind === chosenKind)
                                        if (match && root.selected?.kind !== chosenKind)
                                            root.select(match.id)
                                    }
                                    Component.onCompleted: root.syncPaletteToSelection()
                                    StyledToolTip { text: Translation.tr("Select or add module kind") }
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssEditorConfirmAdd" : ""
                                    editorSquare: true
                                    compact: true
                                    text: "Add module"
                                    glyph: "add"
                                    description: "Add selected module"
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    enabled: root.draft.length < 24
                                    onClicked: root.add(dockPalette.currentValue)
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 18 * Appearance.fontSizeScale
                                    color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.30)
                                }

                                // 4-way Screen Edge move pill group (T / B / L / R)
                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitHeight: 28 * Appearance.fontSizeScale
                                    implicitWidth: dockMoveEdgeRow.implicitWidth + 4
                                    radius: 9
                                    opacity: root.targets.length > 0 && !root.anyTargetLocked ? 1.0 : 0.42
                                    color: Qt.alpha(Appearance.colors.colLayer3, 0.56)
                                    border.width: 1
                                    border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                                    Row {
                                        id: dockMoveEdgeRow
                                        anchors.centerIn: parent
                                        spacing: 2

                                        Repeater {
                                            model: [
                                                { key: "top", label: "T", tip: Translation.tr("Move selected module to Top Edge") },
                                                { key: "bottom", label: "B", tip: Translation.tr("Move selected module to Bottom Edge") },
                                                { key: "left", label: "L", tip: Translation.tr("Move selected module to Left Edge") },
                                                { key: "right", label: "R", tip: Translation.tr("Move selected module to Right Edge") }
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                readonly property bool isSelectedEdge: root.targets.length > 0
                                                    && root.targets.every(p => p.edge === modelData.key)
                                                objectName: root.useHorizontalDock ? ("abyssModuleMoveEdge_" + modelData.key) : ""
                                                width: 21 * Appearance.fontSizeScale
                                                height: 24 * Appearance.fontSizeScale
                                                radius: 7
                                                color: isSelectedEdge
                                                    ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.68)
                                                    : (moveEdgeMouse.containsMouse && moveEdgeMouse.enabled
                                                        ? Qt.alpha(Appearance.colors.colOnLayer1, 0.10)
                                                        : "transparent")

                                                StyledText {
                                                    anchors.centerIn: parent
                                                    text: String(modelData.label)
                                                    font.pixelSize: 10 * Appearance.fontSizeScale
                                                    font.weight: isSelectedEdge ? Font.DemiBold : Font.Medium
                                                    color: isSelectedEdge
                                                        ? Appearance.colors.colOnPrimaryContainer
                                                        : Appearance.colors.colSubtext
                                                }

                                                MouseArea {
                                                    id: moveEdgeMouse
                                                    anchors.fill: parent
                                                    enabled: root.targets.length > 0 && !root.anyTargetLocked
                                                    hoverEnabled: true
                                                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                                    onClicked: {
                                                        root.rememberHistory()
                                                        root.change("edge", modelData.key)
                                                        root.editingEdge = modelData.key
                                                    }
                                                }

                                                StyledToolTip {
                                                    position: "top"
                                                    extraVisibleCondition: moveEdgeMouse.containsMouse
                                                    text: String(modelData.tip)
                                                }
                                            }
                                        }
                                    }
                                }

                                StyledComboBox {
                                    id: dockAlignmentChoice
                                    objectName: root.useHorizontalDock ? "abyssModulePositionDropdown" : ""
                                    baseHeight: 28 * Appearance.fontSizeScale
                                    Layout.preferredWidth: (root.multiSelect ? 80 : 96) * Appearance.fontSizeScale
                                    Layout.maximumWidth: 112 * Appearance.fontSizeScale
                                    Layout.minimumWidth: 0
                                    popupMinimumWidth: 136 * Appearance.fontSizeScale
                                    model: [
                                        {label: "Free position", value: "free"},
                                        {label: "Align start", value: "start"},
                                        {label: "Align center", value: "center"},
                                        {label: "Align end", value: "end"}
                                    ]
                                    textRole: "label"
                                    valueRole: "value"
                                    currentIndex: Math.max(0, model.findIndex(p => p.value === root.selected?.alignment))
                                    displayText: root.multiSelect && root.targets.some(p => p.alignment !== root.selected?.alignment)
                                        ? "Mixed alignment" : currentText
                                    enabled: root.targets.length > 0 && !root.anyTargetLocked
                                    onActivated: root.change("alignment", currentValue)
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssModuleRotate" : ""
                                    text: root.rotateActionText
                                    glyph: "rotate_right"
                                    compact: true
                                    editorSquare: true
                                    description: root.rotateActionDescription
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.rotateActionSize
                                    Layout.maximumHeight: root.rotateActionSize
                                    enabled: root.canRotateSelection
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            root.rotateSelection()
                                            event.accepted = true
                                        }
                                    }
                                    onClicked: root.rotateSelection()
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssModulePositionLock" : ""
                                    text: root.allTargetsLocked ? "Unlock position" : "Lock position"
                                    glyph: root.allTargetsLocked ? "lock_open" : "lock"
                                    compact: true
                                    editorSquare: true
                                    description: text
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    enabled: root.targets.length > 0
                                    Keys.onPressed: event => {
                                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                            root.lockSelection()
                                            event.accepted = true
                                        }
                                    }
                                    onClicked: root.lockSelection()
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssSelectionEnabled" : ""
                                    text: root.allTargetsDisabled ? "Enable" : "Disable"
                                    glyph: root.allTargetsDisabled ? "visibility" : "visibility_off"
                                    compact: true
                                    editorSquare: true
                                    description: text
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    enabled: root.targets.length > 0
                                    onClicked: root.batch("enabled", root.allTargetsDisabled)
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssModuleJoinCorner" : ""
                                    text: root.nearbyCorner
                                        ? "Connect to " + root.nearbyCorner + " corner"
                                        : "Join nearby corner"
                                    glyph: "join_inner"
                                    compact: true
                                    editorSquare: true
                                    checkable: true
                                    description: root.nearbyCorner
                                        ? "Extend this module's local surface to the corner and attach its popup to both Screen Edges. Module size stays unchanged."
                                        : "The nearest visible module within 160 px of a corner can connect to it."
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    checked: root.targets.length > 0 && root.targets.every(p => p.joinCorner)
                                    enabled: root.targets.length > 0 && (root.targets.every(p => !!Placement.cornerForModule(
                                        root.moduleLayer.layoutRecords, p.id, root.width, root.height)) || checked)
                                    onToggled: root.change("joinCorner", checked)
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssSelectionRemove" : ""
                                    text: "Remove"
                                    glyph: "delete"
                                    compact: true
                                    editorSquare: true
                                    description: root.multiSelect ? "Remove selected modules" : "Remove selected module"
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    enabled: root.targets.length > 0
                                    onClicked: root.batch("remove", true)
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: 18 * Appearance.fontSizeScale
                                    color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.30)
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssModuleCustomSizeToggle" : ""
                                    text: "Custom size"
                                    glyph: "aspect_ratio"
                                    compact: true
                                    editorSquare: true
                                    checkable: true
                                    description: "Use a custom size for the selected module"
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    checked: root.allTargetsCustom
                                    enabled: root.targets.length > 0 && !root.anyTargetLocked
                                    onToggled: root.change("customSize", checked)
                                }

                                AbyssSlider {
                                    objectName: root.useHorizontalDock ? "abyssModuleCustomSizeSlider" : ""
                                    editorCompact: true
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 75 * Appearance.fontSizeScale
                                    Layout.maximumWidth: 136 * Appearance.fontSizeScale
                                    from: .6
                                    to: 1.8
                                    stepSize: .01
                                    value: root.selected?.customSize
                                        ? root.selected.size
                                        : Placement.edgeSize(
                                            root.draftOptions,
                                            root.selected?.edge ?? root.editingEdge)
                                    enabled: root.allTargetsCustom && !root.anyTargetLocked
                                    onMoved: root.change("size", value)
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                }

                                AbyssLabel {
                                    objectName: root.useHorizontalDock ? "abyssSelectionCount" : ""
                                    visible: root.multiSelect
                                    text: root.targets.length + " selected · " + root.targets.filter(p => p.locked).length + " locked"
                                    font.pixelSize: 11 * Appearance.fontSizeScale
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 96 * Appearance.fontSizeScale
                                }

                                AbyssButton {
                                    objectName: root.useHorizontalDock ? "abyssSelectionClear" : ""
                                    visible: root.multiSelect
                                    compact: true
                                    editorSquare: true
                                    text: "Clear selection"
                                    glyph: "deselect"
                                    Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                    Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                    Layout.maximumWidth: root.editorActionSize
                                    Layout.maximumHeight: root.editorActionSize
                                    enabled: root.targetIds.length > 0
                                    onClicked: root.clearSelection()
                                }
                            }
                        }
                    }

                    // Tier 2B: Screen Edge Geometry, Spacing, Scale & Curvature Cards
                    GridLayout {
                        id: edgeCardsGrid
                        parent: root.splitSideDocks ? rightEdgeDockScrollContent : dockTrayColumn
                        columns: root.splitSideDocks ? 1 : 3
                        visible: root.splitSideDocks || root.activeDockTab === "edge"
                        Layout.fillWidth: true
                        Layout.fillHeight: !root.splitSideDocks
                        rowSpacing: 8 * Appearance.fontSizeScale
                        columnSpacing: 8 * Appearance.fontSizeScale

                        // Card 1: Active Screen Edge & Physical Thickness
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: !root.splitSideDocks
                            Layout.preferredWidth: root.splitSideDocks ? -1 : 1
                            Layout.preferredHeight: root.splitSideDocks ? implicitHeight : -1
                            implicitHeight: edgeCard1Col.implicitHeight + 16
                            radius: 12
                            color: Qt.alpha(Appearance.colors.colLayer2, 0.46)
                            border.width: 1
                            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                            ColumnLayout {
                                id: edgeCard1Col
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: root.splitSideDocks ? undefined : parent.bottom
                                anchors.margins: 8
                                spacing: 6 * Appearance.fontSizeScale

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        visible: toolbarScroll.width >= 900 * Appearance.fontSizeScale
                                        text: Translation.tr("Edge")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colSubtext
                                    }

                                    Rectangle {
                                        objectName: root.useHorizontalDock ? "abyssEditingEdgeSelector" : ""
                                        Layout.fillWidth: true
                                        implicitHeight: 26 * Appearance.fontSizeScale
                                        radius: 13
                                        color: Qt.alpha(Appearance.colors.colLayer3, 0.56)
                                        border.width: 1
                                        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            spacing: 2

                                            Repeater {
                                                model: [
                                                    { key: "top", label: Translation.tr("Top") },
                                                    { key: "bottom", label: Translation.tr("Bottom") },
                                                    { key: "left", label: Translation.tr("Left") },
                                                    { key: "right", label: Translation.tr("Right") }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool isCurrentEdge: root.editingEdge === modelData.key
                                                    objectName: root.useHorizontalDock ? ("abyssEdgePill_" + modelData.key) : ""
                                                    Layout.fillWidth: true
                                                    Layout.fillHeight: true
                                                    radius: 11
                                                    color: isCurrentEdge
                                                        ? ColorUtils.mix(Appearance.colors.colPrimaryContainer, Appearance.colors.colPrimary, 0.70)
                                                        : (edgePillMouse.containsMouse
                                                            ? Qt.alpha(Appearance.colors.colOnLayer1, 0.08)
                                                            : "transparent")

                                                    StyledText {
                                                        anchors.centerIn: parent
                                                        text: String(modelData.label)
                                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                                        font.weight: isCurrentEdge ? Font.DemiBold : Font.Medium
                                                        color: isCurrentEdge
                                                            ? Appearance.colors.colOnPrimaryContainer
                                                            : Appearance.colors.colSubtext
                                                    }

                                                    MouseArea {
                                                        id: edgePillMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.editingEdge = modelData.key
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    AbyssButton {
                                        editorSquare: true
                                        compact: true
                                        text: "Inherit surface"
                                        glyph: "layers"
                                        description: "Inherit the physical surface thickness"
                                        Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                        Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                        Layout.maximumWidth: root.editorActionSize
                                        Layout.maximumHeight: root.editorActionSize
                                        enabled: (root.edgeThicknesses[root.editingEdge] ?? -1) >= 0
                                        onClicked: root.edgeThicknesses = Object.assign(
                                            {}, root.edgeThicknesses,
                                            {[root.editingEdge]: -1})
                                    }

                                    AbyssButton {
                                        objectName: root.useHorizontalDock ? "abyssRoundZeroCorners" : ""
                                        text: "Round inner corners at 0 px"
                                        glyph: "rounded_corner"
                                        compact: true
                                        editorSquare: true
                                        checkable: true
                                        description: enabled
                                            ? "Round the workspace-side inner corners when the physical Edge is 0 px wide."
                                            : "Set physical Edge width to 0 px to enable inner-corner rounding."
                                        Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                        Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                        Layout.maximumWidth: root.editorActionSize
                                        Layout.maximumHeight: root.editorActionSize
                                        enabled: Placement.edgeThickness(root.draftOptions, root.editingEdge) === 0
                                        checked: root.edgeRoundZeroCorners[root.editingEdge] === true
                                        onToggled: root.edgeRoundZeroCorners = Object.assign(
                                            {}, root.edgeRoundZeroCorners,
                                            {[root.editingEdge]: checked})
                                    }

                                    AbyssSlider {
                                        objectName: root.useHorizontalDock ? "abyssEdgeWidthSlider" : ""
                                        editorCompact: true
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 75 * Appearance.fontSizeScale
                                        unit: "px"
                                        from: 0
                                        to: 40
                                        stepSize: 1
                                        value: Placement.edgeThickness(root.draftOptions, root.editingEdge)
                                        onMoved: root.edgeThicknesses = Object.assign(
                                            {}, root.edgeThicknesses,
                                            {[root.editingEdge]: value})
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    AbyssButton {
                                        objectName: root.useHorizontalDock ? "abyssScaleModulesToggle" : ""
                                        editorSquare: true
                                        compact: true
                                        checkable: true
                                        text: "Width affects modules"
                                        glyph: "width"
                                        description: "Scale modules: scale inherited modules with this Edge (0px hides them), or change only the bare Edge and retain local module bulges. Custom module sizes stay independent."
                                        Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                        Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                        Layout.maximumWidth: root.editorActionSize
                                        Layout.maximumHeight: root.editorActionSize
                                        checked: root.edgeWidthAffectsModules[root.editingEdge] !== false
                                        onToggled: root.edgeWidthAffectsModules = Object.assign(
                                            {}, root.edgeWidthAffectsModules,
                                            {[root.editingEdge]: checked})
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: Translation.tr("Scale modules")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }

                                    AbyssButton {
                                        objectName: root.useHorizontalDock ? "abyssExpandWholeEdgeToggle" : ""
                                        editorSquare: true
                                        compact: true
                                        checkable: true
                                        text: "Expand whole Edge"
                                        glyph: "fit_screen"
                                        description: "Expand a single module across the whole Edge; turn off to expand only its local surface."
                                        Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                        Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                        Layout.maximumWidth: root.editorActionSize
                                        Layout.maximumHeight: root.editorActionSize
                                        enabled: root.draft.filter(
                                            p => p.enabled && p.edge === root.editingEdge && !Placement.isUnifiedKind(p.kind)).length === 1
                                        checked: root.singleModuleExpansion[root.editingEdge] !== "local"
                                        onToggled: root.singleModuleExpansion = Object.assign(
                                            {}, root.singleModuleExpansion,
                                            {[root.editingEdge]: checked ? "edge" : "local"})
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: Translation.tr("Whole edge")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }
                            }
                        }

                        // Card 2: Gap, Edge Size & Module Scale
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: !root.splitSideDocks
                            Layout.preferredWidth: root.splitSideDocks ? -1 : 1
                            Layout.preferredHeight: root.splitSideDocks ? implicitHeight : -1
                            implicitHeight: edgeCard2Col.implicitHeight + 16
                            radius: 12
                            color: Qt.alpha(Appearance.colors.colLayer2, 0.46)
                            border.width: 1
                            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                            ColumnLayout {
                                id: edgeCard2Col
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: root.splitSideDocks ? undefined : parent.bottom
                                anchors.margins: 8
                                spacing: 5 * Appearance.fontSizeScale

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "space_bar"
                                        iconSize: 15 * Appearance.fontSizeScale
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.preferredWidth: 42 * Appearance.fontSizeScale
                                        elide: Text.ElideRight
                                        text: Translation.tr("Gap")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                    AbyssSlider {
                                        objectName: root.useHorizontalDock ? "abyssEdgeGapSlider" : ""
                                        editorCompact: true
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 75 * Appearance.fontSizeScale
                                        unit: "px"
                                        from: 0
                                        to: 32
                                        stepSize: 1
                                        value: root.gap
                                        onMoved: root.gap = value
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "aspect_ratio"
                                        iconSize: 15 * Appearance.fontSizeScale
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.preferredWidth: 42 * Appearance.fontSizeScale
                                        elide: Text.ElideRight
                                        text: Translation.tr("Span")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                    AbyssSlider {
                                        objectName: root.useHorizontalDock ? "abyssEdgeSizeSlider" : ""
                                        editorCompact: true
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 75 * Appearance.fontSizeScale
                                        from: .6
                                        to: 1.8
                                        stepSize: .01
                                        value: Placement.edgeSize(root.draftOptions, root.editingEdge)
                                        onMoved: root.edgeSizes = Object.assign(
                                            {}, root.edgeSizes,
                                            {[root.editingEdge]: value})
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    MaterialSymbol {
                                        text: "zoom_out_map"
                                        iconSize: 15 * Appearance.fontSizeScale
                                        color: Appearance.colors.colSubtext
                                    }
                                    StyledText {
                                        Layout.preferredWidth: 42 * Appearance.fontSizeScale
                                        elide: Text.ElideRight
                                        text: Translation.tr("Scale")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                    AbyssSlider {
                                        objectName: root.useHorizontalDock ? "abyssScaleModulesSlider" : ""
                                        editorCompact: true
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 75 * Appearance.fontSizeScale
                                        from: .6
                                        to: 1.8
                                        stepSize: .01
                                        value: root.moduleScale
                                        onMoved: root.moduleScale = value
                                        StyledToolTip { text: "Overall module scale" }
                                    }
                                }
                            }
                        }

                        // Card 3: Module Welding & Corner Radius
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: !root.splitSideDocks
                            Layout.preferredWidth: root.splitSideDocks ? -1 : 1
                            Layout.preferredHeight: root.splitSideDocks ? implicitHeight : -1
                            implicitHeight: edgeCard3Col.implicitHeight + 16
                            radius: 12
                            color: Qt.alpha(Appearance.colors.colLayer2, 0.46)
                            border.width: 1
                            border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                            ColumnLayout {
                                id: edgeCard3Col
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.bottom: root.splitSideDocks ? undefined : parent.bottom
                                anchors.margins: 8
                                spacing: 6 * Appearance.fontSizeScale

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: Translation.tr("Welding & Radius")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    Rectangle {
                                        implicitHeight: 18
                                        implicitWidth: edgeCurveStatusText.implicitWidth + 10
                                        radius: 9
                                        color: Qt.alpha(Appearance.colors.colLayer3, 0.72)

                                        StyledText {
                                            id: edgeCurveStatusText
                                            anchors.centerIn: parent
                                            text: root.edgeWidthAffectsModules[root.editingEdge] === false
                                                ? Translation.tr("Local bulge")
                                                : Translation.tr("Edge-coupled")
                                            font.pixelSize: 9 * Appearance.fontSizeScale
                                            color: Appearance.colors.colSubtext
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    AbyssButton {
                                        objectName: root.useHorizontalDock ? "abyssJoinNearbyModules" : ""
                                        text: "Join nearby modules"
                                        glyph: "join_inner"
                                        compact: true
                                        editorSquare: true
                                        checkable: true
                                        description: "Join nearby modules: connect neighboring module surfaces on this Edge. Distant groups keep their own bulges and module sizes remain unchanged."
                                        Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                        Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                        Layout.maximumWidth: root.editorActionSize
                                        Layout.maximumHeight: root.editorActionSize
                                        checked: root.edgeJoinModules[root.editingEdge] === true
                                        enabled: root.edgeWidthAffectsModules[root.editingEdge] === false
                                        onToggled: root.edgeJoinModules = Object.assign(
                                            {}, root.edgeJoinModules,
                                            {[root.editingEdge]: checked})
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: Translation.tr("Join modules")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }

                                    AbyssButton {
                                        objectName: root.useHorizontalDock ? "abyssModuleRoundingAction" : ""
                                        text: "Inherit rounding"
                                        glyph: "rounded_corner"
                                        compact: true
                                        editorSquare: true
                                        checkable: true
                                        description: checked
                                            ? "Inherited module rounding. Toggle off to use a custom radius."
                                            : "Custom module rounding. Toggle on to inherit shared curvature."
                                        Layout.preferredWidth: 28 * Appearance.fontSizeScale
                                        Layout.preferredHeight: 28 * Appearance.fontSizeScale
                                        Layout.maximumWidth: root.editorActionSize
                                        Layout.maximumHeight: root.editorActionSize
                                        checked: (root.edgeModuleRadii[root.editingEdge] ?? -1) < 0
                                        enabled: root.edgeWidthAffectsModules[root.editingEdge] === false
                                        onToggled: {
                                            const radius = root.edgeModuleRadii[root.editingEdge] ?? -1
                                            root.edgeModuleRadii = Object.assign({}, root.edgeModuleRadii, {
                                                [root.editingEdge]: checked ? -1
                                                    : (radius >= 0 ? radius : AbyssStyle.neckRadius)
                                            })
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: Translation.tr("Auto radius")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    StyledText {
                                        Layout.preferredWidth: 44 * Appearance.fontSizeScale
                                        elide: Text.ElideRight
                                        text: Translation.tr("Radius")
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                    }

                                    AbyssSlider {
                                        objectName: root.useHorizontalDock ? "abyssModuleRounding" : ""
                                        editorCompact: true
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 75 * Appearance.fontSizeScale
                                        enabled: root.edgeWidthAffectsModules[root.editingEdge] === false
                                        unit: "px"
                                        from: 0
                                        to: 64
                                        stepSize: 1
                                        value: (root.edgeModuleRadii[root.editingEdge] ?? -1) < 0
                                            ? AbyssStyle.neckRadius : root.edgeModuleRadii[root.editingEdge]
                                        onMoved: root.edgeModuleRadii = Object.assign(
                                            {}, root.edgeModuleRadii,
                                            {[root.editingEdge]: value})
                                    }
                                }
                            }
                        }
                    }

                    // Tier 2C: Popups & Panels (IPC / OSD Placement Configurator)
                    Rectangle {
                        id: popupsDockCard
                        parent: root.splitSideDocks ? leftPopupsDockColumn : dockTrayColumn
                        visible: root.splitSideDocks || root.activeDockTab === "popups"
                        x: 0
                        y: 0
                        width: root.splitSideDocks ? leftPopupsDockColumn.width : undefined
                        Layout.fillWidth: true
                        Layout.fillHeight: !root.splitSideDocks
                        Layout.preferredHeight: root.splitSideDocks ? implicitHeight : -1
                        implicitHeight: popupsCardColumn.implicitHeight + 20
                        radius: 12
                        color: Qt.alpha(Appearance.colors.colLayer2, 0.46)
                        border.width: 1
                        border.color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.22)

                        ColumnLayout {
                            id: popupsCardColumn
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: root.splitSideDocks ? undefined : parent.bottom
                            anchors.margins: root.splitSideDocks ? 6 : 10
                            spacing: 6 * Appearance.fontSizeScale

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                MaterialSymbol {
                                    text: "open_in_new"
                                    iconSize: 16 * Appearance.fontSizeScale
                                    color: Appearance.colors.colPrimary
                                }

                                StyledText {
                                    Layout.fillWidth: root.splitSideDocks
                                    elide: Text.ElideRight
                                    text: root.splitSideDocks
                                        ? Translation.tr("Popups & Panels")
                                        : Translation.tr("OSD & Indicator Placement")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    font.weight: Font.DemiBold
                                    color: Appearance.colors.colOnLayer1
                                }

                                StyledText {
                                    visible: !root.splitSideDocks
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: Translation.tr("Drag the live preview on any Screen Edge or choose an alignment below")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                DockTogglePill {
                                    visible: root.splitSideDocks
                                    objectName: root.splitSideDocks ? "abyssEditorIpcMode" : ""
                                    icon: "open_with"
                                    active: root.editingPopups
                                    tooltipText: root.editingPopups
                                        ? Translation.tr("Live OSD drag preview active — click to return to module handles")
                                        : Translation.tr("Show live OSD preview on Desktop Stage to drag")
                                    onClicked: root.editingPopups = !root.editingPopups
                                }

                                DockTogglePill {
                                    visible: root.splitSideDocks
                                    icon: "restart_alt"
                                    active: false
                                    tooltipText: Translation.tr("Reset selected IPC position")
                                    onClicked: previewPositions.apply(null)
                                }

                                StyledText {
                                    visible: !root.splitSideDocks
                                    text: Translation.tr("Scope")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                Item {
                                    id: inlineDockScopeHost
                                    visible: !root.splitSideDocks
                                    Layout.preferredWidth: 124 * Appearance.fontSizeScale
                                    Layout.maximumWidth: 150 * Appearance.fontSizeScale
                                    implicitWidth: 124 * Appearance.fontSizeScale
                                    implicitHeight: 28 * Appearance.fontSizeScale
                                }
                            }

                            RowLayout {
                                visible: root.splitSideDocks
                                Layout.fillWidth: true
                                spacing: 6

                                StyledText {
                                    text: Translation.tr("Scope")
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                    color: Appearance.colors.colSubtext
                                }

                                Item {
                                    id: sideDockScopeHost
                                    Layout.fillWidth: true
                                    implicitHeight: 28 * Appearance.fontSizeScale

                                    StyledComboBox {
                                        id: dockIpcOutputChoice
                                        parent: root.splitSideDocks ? sideDockScopeHost : inlineDockScopeHost
                                        objectName: root.useHorizontalDock ? "abyssEditorIpcOutput" : ""
                                        x: 0
                                        y: 0
                                        width: root.splitSideDocks ? sideDockScopeHost.width : inlineDockScopeHost.width
                                        baseHeight: 28 * Appearance.fontSizeScale
                                        popupMinimumWidth: 150 * Appearance.fontSizeScale
                                        textRole: "label"
                                        valueRole: "value"
                                        model: [
                                            {label: "All outputs", value: ""},
                                            {label: root.outputName, value: root.outputName}
                                        ]
                                        currentIndex: model.findIndex(option => option.value === (root.outputOnly ? root.outputName : ""))
                                        onActivated: root.outputOnly = currentValue !== ""
                                        StyledToolTip { text: Translation.tr("Edit this output or all outputs") }
                                    }
                                }
                            }

                            Item {
                                id: dockPopupsHost
                                Layout.fillWidth: true
                                Layout.fillHeight: !root.splitSideDocks
                                Layout.preferredHeight: previewPositions.implicitHeight
                                implicitHeight: previewPositions.implicitHeight
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                id: toolbarColumn
                visible: !root.useHorizontalDock
                width: toolbarScroll.width
                spacing: 3

                RowLayout {
                    objectName: "abyssEditorHeader"
                    Layout.fillWidth: true;Layout.minimumWidth:0
                    // Never wrap the actions below the title.
                    spacing:root.compactHeaderActions ? 4 : 8
                    AbyssLabel {
                        objectName:"abyssEditorTitle"
                        text: "Edit layout · "+root.outputName
                        font.bold: true
                        font.pixelSize:root.compactHeaderActions
                            ? 10*Appearance.fontSizeScale : AbyssStyle.fontSize
                        wrapMode:Text.NoWrap
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        Layout.alignment:Qt.AlignVCenter
                        elide:Text.ElideRight
                    }
                    RowLayout {
                        objectName:"abyssEditorHeaderActions"
                        Layout.alignment:Qt.AlignRight | Qt.AlignVCenter
                        Layout.fillWidth:false
                        Layout.minimumWidth:root.headerActionSize*4
                            + (root.compactHeaderActions ? 6 : 12)*Appearance.fontSizeScale
                        spacing:root.compactHeaderActions ? 2 : 4
                        AbyssButton {
                        Layout.maximumHeight:root.editorActionSize
                        Layout.maximumWidth:root.editorActionSize
                        editorSquare:true
                            objectName:!root.useHorizontalDock ? "abyssLayoutUndo" : ""
                            text:"Undo";glyph:"undo";compact:true
                            Layout.preferredWidth:root.headerActionSize;Layout.preferredHeight:root.headerActionSize
                            enabled:root.undoStack.length>0
                            onClicked:root.undo()
                        }
                        AbyssButton {
                        Layout.maximumHeight:root.editorActionSize
                        Layout.maximumWidth:root.editorActionSize
                        editorSquare:true
                            objectName:!root.useHorizontalDock ? "abyssLayoutReset" : ""
                            text: "Reset"; glyph: "restart_alt"; compact: true
                            description: root.editingPopups ? "Reset selected IPC position" : "Reset layout draft"
                            Layout.preferredWidth:root.headerActionSize;Layout.preferredHeight:root.headerActionSize
                            onClicked: root.editingPopups ? root.resetIpcPosition() : root.reset()
                        }


                        AbyssButton {
                        Layout.maximumHeight:root.editorActionSize
                        Layout.maximumWidth:root.editorActionSize
                        editorSquare:true
                            objectName:!root.useHorizontalDock ? "abyssLayoutCancel" : ""
                            text: "Cancel"; glyph: "close"; compact: true
                            description: "Cancel editing"
                            Layout.preferredWidth:root.headerActionSize;Layout.preferredHeight:root.headerActionSize
                            onClicked: root.finish(false)
                        }
                        AbyssButton {
                        Layout.maximumHeight:root.editorActionSize
                        Layout.maximumWidth:root.editorActionSize
                        editorSquare:true
                            objectName:!root.useHorizontalDock ? "abyssLayoutDone" : ""
                            text: "Done"; glyph: "check"; compact: true
                            description: "Save layout changes"
                            Layout.preferredWidth:root.headerActionSize;Layout.preferredHeight:root.headerActionSize
                            enabled:!root.layoutConflicts.length
                            onClicked: root.finish(true)
                        }
                    }
                }

                AbyssLabel {
                    objectName:!root.useHorizontalDock ? "abyssLayoutFeedback" : ""
                    visible:text.length>0
                    text:root.layoutConflicts[0] || root.feedback
                    Layout.fillWidth:true;Layout.minimumWidth:0;wrapMode:Text.WordWrap
                    color:Appearance.colors.colError
                }

                // Wide Edges show tabs and output scope on one row.
                // Side Edges stack those two rows, but each remains compact:
                // the Join toggle stays beside IPC, and scope stays inline.
                GridLayout {
                    id: editorModeHeader
                    objectName: "abyssEditorModeHeader"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    columns: root.toolbarOnHorizontalEdge
                        && toolbarScroll.width >= 450*Appearance.fontSizeScale ? 2 : 1
                    columnSpacing: 8
                    rowSpacing: 4

                    RowLayout {
                        id: editorModeTabs
                        objectName: "abyssEditorModeTabs"
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        spacing: 4
                        SelectionGroupButton {
                            objectName:!root.useHorizontalDock ? "abyssEditorModulesMode" : ""
                            buttonIcon:"widgets";buttonText:"Modules";toggled:!root.editingPopups
                            horizontalPadding:4*Appearance.fontSizeScale
                            verticalPadding:2*Appearance.fontSizeScale
                            baseHeight:28*Appearance.fontSizeScale
                            Layout.preferredWidth:92*Appearance.fontSizeScale
                            Layout.maximumWidth:92*Appearance.fontSizeScale
                            Layout.minimumWidth:0;Layout.fillWidth:true
                            onClicked:root.editingPopups=false
                        }
                        SelectionGroupButton {
                            objectName:!root.useHorizontalDock ? "abyssEditorIpcMode" : ""
                            buttonIcon:"open_in_new";buttonText:"IPC";toggled:root.editingPopups
                            horizontalPadding:4*Appearance.fontSizeScale
                            verticalPadding:2*Appearance.fontSizeScale
                            baseHeight:28*Appearance.fontSizeScale
                            Layout.preferredWidth:58*Appearance.fontSizeScale
                            Layout.maximumWidth:58*Appearance.fontSizeScale
                            Layout.minimumWidth:0;Layout.fillWidth:true
                            onClicked:root.editingPopups=true
                        }
                    }

                    RowLayout {
                        objectName: "abyssEditorOutputScope"
                        // Fix right-aligned, fill-width scope row offset on
                        // the left/right Edges. Leave horizontal Edges alone.
                        Layout.fillWidth: root.toolbarOnHorizontalEdge
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: root.toolbarOnHorizontalEdge
                            ? -1 : root.sideIpcSelectorWidth
                        Layout.maximumWidth: root.toolbarOnHorizontalEdge
                            ? Infinity : root.sideIpcSelectorWidth
                        Layout.alignment: root.toolbarOnHorizontalEdge
                            ? (Qt.AlignRight | Qt.AlignVCenter)
                            : (Qt.AlignLeft | Qt.AlignVCenter)
                        spacing:root.toolbarOnHorizontalEdge ? 8 : 4
                        Item {
                            visible:root.toolbarOnHorizontalEdge
                            Layout.fillWidth:root.toolbarOnHorizontalEdge
                            Layout.minimumWidth:0
                        }
                        GridLayout {
                            Layout.fillWidth:false
                            Layout.alignment:root.toolbarOnHorizontalEdge
                                ? Qt.AlignRight : Qt.AlignLeft
                            columns:2
                            columnSpacing:root.toolbarOnHorizontalEdge ? 8 : 6
                            rowSpacing: 4
                            StyledComboBox {
                            id:ipcOutputChoice
                            objectName:!root.useHorizontalDock ? "abyssEditorIpcOutput" : ""
                            // Shared output scope is useful in both Modules and IPC.
                            visible:true
                            baseHeight:28*Appearance.fontSizeScale
                            // IPC selectors extend through the toggle's right edge;
                            // output selection stops just before the toggle.
                            Layout.preferredWidth:root.toolbarOnHorizontalEdge
                                ? Math.min(116*Appearance.fontSizeScale,root.sideIpcDropdownWidth) : root.sideIpcDropdownWidth
                            Layout.maximumWidth:root.toolbarOnHorizontalEdge
                                ? Math.min(116*Appearance.fontSizeScale,root.sideIpcDropdownWidth) : root.sideIpcDropdownWidth
                            popupMinimumWidth:Math.max(116*Appearance.fontSizeScale,
                                root.sideIpcDropdownWidth)
                            textRole:"label";valueRole:"value"
                            model:[{label:"All outputs",value:""},
                                {label:root.outputName,value:root.outputName}]
                            // A model rebuild (output rename/hotplug) can
                            // reset ComboBox's index while outputOnly stays
                            // unchanged. Resolve the selection from this model.
                            currentIndex:model.findIndex(option => option.value === (root.outputOnly ? root.outputName : ""))
                            onActivated:root.outputOnly=currentValue!==""
                            StyledToolTip {text:"Edit this output or all outputs"}
                        }
                        AbyssButton {
                            objectName:!root.useHorizontalDock ? "abyssEditorOutputOnly" : ""
                            text:"This output only"
                            glyph:checked ? "check_box" : "check_box_outline_blank"
                            compact:true;editorSquare:true;checkable:true
                            description:checked
                                ? "This output only · on" : "This output only · off"
                            Layout.fillWidth:false;Layout.minimumWidth:0
                            Layout.preferredWidth:root.headerActionSize
                            Layout.preferredHeight:root.headerActionSize
                            Layout.maximumWidth:root.headerActionSize
                            Layout.maximumHeight:root.headerActionSize
                            checked:root.outputOnly
                            onToggled:root.outputOnly=checked
                        }
                        }
                    }
                }

                // IPC type, source Edge and alignment share one row inside
                // AbyssPositionSettings. This editor no longer duplicates
                // position selectors in a separate, top-aligned component.
                AbyssPositionSettings {
                    id:previewPositions
                    parent:root.useHorizontalDock ? dockPopupsHost : toolbarColumn
                    x:0
                    y:0
                    width:root.useHorizontalDock ? dockPopupsHost.width : toolbarScroll.width
                    Layout.fillWidth:true
                    Layout.minimumWidth:0
                    Layout.maximumWidth:root.useHorizontalDock ? dockPopupsHost.width : toolbarScroll.width
                    objectName:"abyssEditorIpcPlacement"
                    visible:root.splitSideDocks || root.editingPopups
                    kind:"volume"
                    compactVertical:!root.toolbarWideControls
                    compactSideToolbar:!root.toolbarOnHorizontalEdge
                    compactSideSelectorWidth:root.sideIpcSelectorWidth
                    compactCornerHost:root.toolbarOnHorizontalEdge ? null : editorModeTabs
                    compactActions:root.toolbarOnHorizontalEdge
                    commitImmediately:false
                    positions:root.draftPositions
                    outputSelectionEnabled:false
                    showKindSelector:false
                    showOutputSelector:false
                    compactIpcEditor:true
                    outputName:root.outputOnly ? root.outputName : ""
                    nearbyEdge:root.previewNearbyCorner
                    // Popups ("utilities","launcher", etc.) follow their owning Screen Edge modules; only IPC/OSD
                    // indicators have independent positions in this editor.
                    allowedKinds:["osd","volume","brightness","mic","mediaOsd","keyboardLayout","voiceSearch"]
                    onKindChanged: {
                        if (root.splitSideDocks && root.visible)
                            root.editingPopups = true
                    }
                    onPositionsEdited:(positions,kind,outputName,values)=> {
                        if (root.splitSideDocks && root.visible)
                            root.editingPopups = true
                        root.editPosition(positions,kind,outputName,values)
                    }
                }

                // Adaptive field grid: each cell keeps its icon, input and
                // contextual action together at every supported orientation.
                                // Module tools on the left, physical Edge controls on the right.
                GridLayout {
                    id:editFineControls
                    objectName:"abyssEditorFineControls"
                    visible:!root.editingPopups
                    Layout.fillWidth:true;Layout.minimumWidth:0
                    // Derive column count from the fixed viewport, NOT this GridLayout's
                    // own width. Its implicit width changes with column count, so a
                    // self-referential breakpoint can latch to one column after load.
                    readonly property bool useTwoColumns: root.toolbarOnHorizontalEdge
                        && toolbarScroll.width>=520*Appearance.fontSizeScale
                    columns:useTwoColumns ? 3 : 1
                    columnSpacing:10*Appearance.fontSizeScale
                    rowSpacing:6*Appearance.fontSizeScale

                    ColumnLayout {
                        id:moduleEditorColumn
                        Layout.alignment:Qt.AlignTop
                        objectName:"abyssEditorModuleColumn"
                        // Use the trailing module action as the right alignment
                        // guide. Never stretch the lower controls into empty
                        // space beyond the Module picker/action toolbar.
                        readonly property real controlsSpan:Math.max(0,
                            Math.min(width,Math.max(moduleHeaderActions.implicitWidth,
                                107*Appearance.fontSizeScale)))
                        // On wide Edges, stop this column at the final
                        // module action instead of allocating half the toolbar.
                        Layout.fillWidth:!editFineControls.useTwoColumns
                        Layout.minimumWidth:0
                        Layout.preferredWidth:editFineControls.useTwoColumns
                            ? moduleHeaderActions.implicitWidth
                            : Math.max(0,toolbarScroll.width)
                        spacing:4*Appearance.fontSizeScale
                            GridLayout {
                            id:moduleHeaderActions
                            objectName:"abyssModuleHeaderActions"
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            // Keep the picker/Add pair and selection actions
                            // intact when a side or narrow toolbar cannot fit
                            // their combined width. Use the outer viewport so
                            // the implicit width cannot latch the breakpoint.
                            columns:editFineControls.useTwoColumns
                                || toolbarScroll.width >= 248*Appearance.fontSizeScale+10 ? 2 : 1
                            columnSpacing:2;rowSpacing:4*Appearance.fontSizeScale
                            GridLayout {
                            Layout.alignment:Qt.AlignLeft
                            Layout.minimumWidth:0
                            columns:toolbarScroll.width>=134*Appearance.fontSizeScale+2 ? 2 : 1
                            columnSpacing:2;rowSpacing:4*Appearance.fontSizeScale
                            StyledComboBox {
                            baseHeight:28*Appearance.fontSizeScale
                            Layout.preferredWidth:104*Appearance.fontSizeScale
                            Layout.maximumWidth:104*Appearance.fontSizeScale
                            Layout.fillWidth:false;Layout.minimumWidth:0;
                            
                            id: palette
                            objectName:!root.useHorizontalDock ? "abyssModuleDropdown" : ""
                            StyledToolTip {text:"Module to add"}
                            model: Placement.catalog.map(kind => ({label:Placement.label(kind),kind:kind}))
                            textRole:"label";valueRole:"kind"
                            onActivated: {
                                const chosenKind = currentValue
                                const match = root.draft.find(p => p.kind === chosenKind && p.enabled)
                                    ?? root.draft.find(p => p.kind === chosenKind)
                                if (match && root.selected?.kind !== chosenKind)
                                    root.select(match.id)
                            }
                            Component.onCompleted: root.syncPaletteToSelection()
                            }
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            editorSquare:true
                            Layout.preferredWidth:root.editorActionSize
                            
                            objectName:!root.useHorizontalDock ? "abyssEditorConfirmAdd" : ""
                            text:"Add module";glyph:"add"
                            compact:true
                            description:"Add selected module"
                            enabled:root.draft.length<24
                            
                            onClicked:root.add(palette.currentValue)
                            }
                            }
                            GridLayout {
                            objectName:"abyssModuleSelectionActions"
                            Layout.alignment:Qt.AlignLeft
                            Layout.minimumWidth:0
                            columns:toolbarScroll.width>=114*Appearance.fontSizeScale+6 ? 4 : 2
                            columnSpacing:2;rowSpacing:4*Appearance.fontSizeScale
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.preferredWidth:28*Appearance.fontSizeScale
                            editorSquare:true
                            Layout.fillWidth:false;Layout.minimumWidth:0
                            
                            objectName:!root.useHorizontalDock ? "abyssModulePositionLock" : ""
                            text:root.allTargetsLocked ? "Unlock position" : "Lock position"
                            glyph:root.allTargetsLocked ? "lock_open" : "lock"
                            compact:true
                            description:text
                            enabled:root.targets.length>0
                            Keys.onPressed:event=>{if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){root.lockSelection();event.accepted=true}}
                            onClicked:root.lockSelection()
                            }
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.preferredWidth:28*Appearance.fontSizeScale
                            editorSquare:true
                            Layout.fillWidth:false;Layout.minimumWidth:0
                            
                            objectName:!root.useHorizontalDock ? "abyssSelectionEnabled" : ""
                            text:root.allTargetsDisabled
                            ? "Enable" : "Disable"
                            glyph:root.allTargetsDisabled
                            ? "visibility" : "visibility_off"
                            compact:true
                            description:text
                            enabled:root.targets.length>0
                            
                            onClicked:root.batch("enabled",root.allTargetsDisabled)
                            }
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.preferredWidth:28*Appearance.fontSizeScale
                            editorSquare:true
                            Layout.fillWidth:false;Layout.minimumWidth:0
                            
                            text:"Remove";glyph:"delete"
                            objectName:!root.useHorizontalDock ? "abyssSelectionRemove" : ""
                            compact:true
                            description:root.multiSelect ? "Remove selected modules" : "Remove selected module"
                            enabled:root.targets.length>0
                            
                            onClicked:root.batch("remove",true)
                            }
                            AbyssButton {
                            objectName:!root.useHorizontalDock ? "abyssModuleJoinCorner" : ""
                            text:root.nearbyCorner
                            ? "Connect to "+root.nearbyCorner+" corner"
                            : "Join nearby corner"
                            glyph:"join_inner"
                            compact:true;editorSquare:true;checkable:true
                            description:root.nearbyCorner
                            ? "Extend this module's local surface to the corner and attach its popup to both Screen Edges. Module size stays unchanged."
                            : "The nearest visible module within 160 px of a corner can connect to it."
                            Layout.preferredWidth:root.editorActionSize
                            Layout.preferredHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.maximumHeight:root.editorActionSize
                            checked:root.targets.length>0 && root.targets.every(p=>p.joinCorner)
                            enabled:root.targets.length>0 && (root.targets.every(p=>!!Placement.cornerForModule(
                            root.moduleLayer.layoutRecords,p.id,root.width,root.height)) || checked)
                            onToggled:root.change("joinCorner",checked)
                            }
                            }
                            }
                            RowLayout {
                        id:moduleAlignmentRow
                        Layout.fillWidth:false;Layout.minimumWidth:0
                        Layout.preferredWidth:moduleEditorColumn.controlsSpan
                        Layout.maximumWidth:moduleEditorColumn.controlsSpan
                        spacing:4*Appearance.fontSizeScale
                        AbyssButton {
                        objectName:!root.useHorizontalDock ? "abyssModuleRotate" : ""
                        text:root.rotateActionText
                        glyph:"rotate_right"
                        compact:true;editorSquare:true
                        description:root.rotateActionDescription
                        Layout.preferredWidth:root.rotateActionSize
                        Layout.preferredHeight:root.rotateActionSize
                        Layout.maximumWidth:root.rotateActionSize
                        Layout.maximumHeight:root.rotateActionSize
                        enabled:root.canRotateSelection
                        Keys.onPressed:event=>{if(event.key===Qt.Key_Return || event.key===Qt.Key_Enter){root.rotateSelection();event.accepted=true}}
                        onClicked:root.rotateSelection()
                        }
                        StyledComboBox {
                        baseHeight:28*Appearance.fontSizeScale
                        Layout.preferredWidth:root.multiSelect
                            ? 92*Appearance.fontSizeScale
                            : Math.max(75*Appearance.fontSizeScale,
                                moduleEditorColumn.controlsSpan-root.rotateActionSize-4*Appearance.fontSizeScale)
                        Layout.maximumWidth:Math.max(75*Appearance.fontSizeScale,
                            moduleEditorColumn.controlsSpan-root.rotateActionSize-4*Appearance.fontSizeScale)
                        Layout.fillWidth:true;Layout.minimumWidth:0;
                        
                        id:alignmentChoice
                        objectName:!root.useHorizontalDock ? "abyssModulePositionDropdown" : ""
                        visible:true
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
                        
                        
                        
                        
                        }
                        AbyssLabel {
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        
                        objectName:!root.useHorizontalDock ? "abyssSelectionCount" : ""
                        visible:root.multiSelect
                        text:root.targets.length+" selected · "+root.targets.filter(p=>p.locked).length+" locked"
                        elide:Text.ElideRight
                        Layout.maximumWidth:140*Appearance.fontSizeScale
                        }
                        AbyssButton {
                        Layout.maximumHeight:root.editorActionSize
                        Layout.maximumWidth:root.editorActionSize
                        editorSquare:true
                        Layout.preferredWidth:root.editorActionSize
                        
                        objectName:!root.useHorizontalDock ? "abyssSelectionClear" : ""
                        
                        compact:true
                        visible:root.multiSelect
                        text:"Clear selection";glyph:"deselect"
                        enabled:root.targetIds.length>0
                        onClicked:root.clearSelection()
                        }
                    }
                            GridLayout {
                            id:selectedModuleControls
                            objectName:"abyssEditorSelectedFields"
                            Layout.fillWidth:false;Layout.minimumWidth:0
                            Layout.preferredWidth:moduleEditorColumn.controlsSpan
                            Layout.maximumWidth:moduleEditorColumn.controlsSpan
                            columns:1;rowSpacing:4*Appearance.fontSizeScale
                            RowLayout {
                            id:moduleRoundingRow
                            Layout.fillWidth:true;Layout.minimumWidth:0;spacing:2*Appearance.fontSizeScale
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            editorSquare:true
                            Layout.preferredWidth:root.editorActionSize
                            
                            objectName:!root.useHorizontalDock ? "abyssModuleRoundingAction" : ""
                            text:"Inherit rounding";glyph:"rounded_corner"
                            compact:true;checkable:true
                            description:checked
                                ? "Inherited module rounding. Toggle off to use a custom radius."
                                : "Custom module rounding. Toggle on to inherit shared curvature."
                            checked:(root.edgeModuleRadii[root.editingEdge] ?? -1)<0
                            enabled:root.edgeWidthAffectsModules[root.editingEdge]===false
                            onToggled: {
                                const radius=root.edgeModuleRadii[root.editingEdge] ?? -1
                                root.edgeModuleRadii=Object.assign({},root.edgeModuleRadii,{
                                    [root.editingEdge]:checked ? -1
                                        : (radius>=0 ? radius : AbyssStyle.neckRadius)
                                })
                            }
                            }
                            AbyssSlider {
                            editorCompact:true
                            Layout.fillWidth:true
                            Layout.preferredWidth:Math.max(75*Appearance.fontSizeScale,
                                moduleEditorColumn.controlsSpan-root.editorActionSize-2*Appearance.fontSizeScale)
                            Layout.maximumWidth:Math.max(75*Appearance.fontSizeScale,
                                moduleEditorColumn.controlsSpan-root.editorActionSize-2*Appearance.fontSizeScale)
                            Layout.minimumWidth:75*Appearance.fontSizeScale
                            
                            
                            objectName:!root.useHorizontalDock ? "abyssModuleRounding" : ""
                            enabled:root.edgeWidthAffectsModules[root.editingEdge]===false
                            unit:"px";from:0;to:64;stepSize:1
                            value:(root.edgeModuleRadii[root.editingEdge] ?? -1)<0
                            ? AbyssStyle.neckRadius : root.edgeModuleRadii[root.editingEdge]
                            onMoved:root.edgeModuleRadii=Object.assign({},root.edgeModuleRadii,{[root.editingEdge]:value})
                            }
                            }
                            RowLayout {
                            id:moduleCustomSizeRow
                            Layout.fillWidth:true;Layout.minimumWidth:0;spacing:2*Appearance.fontSizeScale
                            AbyssButton {
                            objectName:!root.useHorizontalDock ? "abyssModuleCustomSizeToggle" : ""
                            text:"Custom size";glyph:"aspect_ratio"
                            compact:true;editorSquare:true;checkable:true
                            description:"Use a custom size for the selected module"
                            Layout.preferredWidth:root.editorActionSize
                            Layout.preferredHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.maximumHeight:root.editorActionSize
                            checked:root.allTargetsCustom
                            enabled:root.targets.length>0 && !root.anyTargetLocked
                            onToggled:root.change("customSize",checked)
                            }
                            AbyssSlider {
                            editorCompact:true
                            Layout.fillWidth:true
                            Layout.preferredWidth:Math.max(75*Appearance.fontSizeScale,
                                moduleEditorColumn.controlsSpan-root.editorActionSize-2*Appearance.fontSizeScale)
                            Layout.maximumWidth:Math.max(75*Appearance.fontSizeScale,
                                moduleEditorColumn.controlsSpan-root.editorActionSize-2*Appearance.fontSizeScale)
                            Layout.minimumWidth:75*Appearance.fontSizeScale
                            
                            
                            objectName:!root.useHorizontalDock ? "abyssModuleCustomSizeSlider" : ""
                            visible:true
                            from:.6;to:1.8;stepSize:.01
                            value:root.selected?.customSize
                            ? root.selected.size
                            : Placement.edgeSize(
                            root.draftOptions,
                            root.selected?.edge ?? root.editingEdge)
                            enabled:root.allTargetsCustom && !root.anyTargetLocked
                            
                            onMoved:root.change("size",value)
                            }
                            }
                            }
                            
                    }

                    Rectangle {
                        objectName:"abyssEditorColumnDivider"
                        visible:editFineControls.useTwoColumns
                        Layout.alignment:Qt.AlignHCenter | Qt.AlignVCenter
                        Layout.preferredWidth:1*Appearance.fontSizeScale
                        Layout.preferredHeight:64*Appearance.fontSizeScale
                        radius:Layout.preferredWidth/2
                        color:Qt.alpha(AbyssStyle.textColorMuted,.18)
                    }

                    ColumnLayout {
                        id:edgeEditorColumn
                        Layout.alignment:Qt.AlignTop
                        objectName:"abyssEditorEdgeColumn"
                        // Edge controls take any extra track width, preserving
                        // their slider endpoints when Module width contracts.
                        Layout.fillWidth:true;Layout.minimumWidth:0
                        Layout.preferredWidth:editFineControls.useTwoColumns
                            ? 270*Appearance.fontSizeScale
                            : Math.max(0,toolbarScroll.width)
                        width:Layout.preferredWidth
                        spacing:4*Appearance.fontSizeScale
                            RowLayout {
                            objectName:"abyssEdgeHeaderActions"
                            Layout.fillWidth:true;Layout.minimumWidth:0;spacing:2
                            StyledComboBox {
                            baseHeight:28*Appearance.fontSizeScale
                            Layout.preferredWidth:104*Appearance.fontSizeScale
                            Layout.maximumWidth:104*Appearance.fontSizeScale
                            Layout.fillWidth:true;Layout.minimumWidth:0;
                            
                            id:edgeChoice
                            objectName:!root.useHorizontalDock ? "abyssEditingEdgeDropdown" : ""
                            StyledToolTip {text:"Editing Edge"}
                            model:["top","right","bottom","left"]
                            currentIndex:model.indexOf(root.editingEdge)
                            onActivated:root.editingEdge=currentText
                            
                            
                            }
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            editorSquare:true
                            Layout.preferredWidth:root.editorActionSize
                            
                            text:"Snap to guides";glyph:"grid_4x4"
                            compact:true
                            description:"Snap module movement to alignment guides"
                            checkable:true;checked:root.snapEnabled
                            
                            onToggled:root.snapEnabled=checked
                            }
                            AbyssButton {
                            objectName:!root.useHorizontalDock ? "abyssJoinNearbyModules" : ""
                            text:"Join nearby modules";glyph:"join_inner"
                            compact:true;editorSquare:true
                            description:"Join nearby modules: connect neighboring module surfaces on this Edge. Distant groups keep their own bulges and module sizes remain unchanged."
                            checkable:true
                            checked:root.edgeJoinModules[root.editingEdge]===true
                            enabled:root.edgeWidthAffectsModules[root.editingEdge]===false
                            Layout.preferredWidth:root.editorActionSize
                            Layout.preferredHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.maximumHeight:root.editorActionSize
                            onToggled:root.edgeJoinModules=Object.assign({},root.edgeJoinModules,{[root.editingEdge]:checked})
                            }
                            }
                            GridLayout {
                            id:edgeGapAndSizeRow
                            objectName:"abyssEdgeGapAndSizeRow"
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            // Both tracks receive equal column widths. On side
                            // toolbars stack them instead of clipping the labels.
                            columns:root.toolbarOnHorizontalEdge
                                && edgeEditorColumn.width>=260*Appearance.fontSizeScale ? 2 : 1
                            columnSpacing:2*Appearance.fontSizeScale
                            rowSpacing:2*Appearance.fontSizeScale
                            RowLayout {
                            
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            Layout.preferredWidth:0
                            spacing:2*Appearance.fontSizeScale
                            EditorIconHint {
                            Layout.preferredWidth:20*Appearance.fontSizeScale
                            glyph:"space_bar";description:"Gap between modules" }
                            AbyssSlider {
                            editorCompact:true
                            Layout.fillWidth:true;Layout.preferredWidth:110*Appearance.fontSizeScale
                            Layout.minimumWidth:75*Appearance.fontSizeScale
                            
                            
                            objectName:!root.useHorizontalDock ? "abyssEdgeGapSlider" : ""
                            unit:"px";from:0;to:32;stepSize:1;value:root.gap
                            onMoved:root.gap=value
                            
                            }
                            }
                            RowLayout {
                            
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            Layout.preferredWidth:0
                            spacing:2*Appearance.fontSizeScale
                            EditorIconHint {
                            Layout.preferredWidth:20*Appearance.fontSizeScale
                            glyph:"aspect_ratio";description:"Shared module size for this Edge" }
                            AbyssSlider {
                            editorCompact:true
                            Layout.fillWidth:true;Layout.preferredWidth:110*Appearance.fontSizeScale
                            Layout.minimumWidth:75*Appearance.fontSizeScale
                            
                            
                            objectName:!root.useHorizontalDock ? "abyssEdgeSizeSlider" : ""
                            from:.6;to:1.8;stepSize:.01
                            value:Placement.edgeSize(root.draftOptions,root.editingEdge)
                            
                            onMoved:root.edgeSizes=Object.assign(
                            {},root.edgeSizes,{[root.editingEdge]:value})
                            }
                            }
                            }
                            GridLayout {
                            id:edgeWidthRow
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            readonly property bool inlineControls: edgeEditorColumn.width>=155*Appearance.fontSizeScale+6
                            columns:inlineControls ? 2 : 1
                            columnSpacing:2;rowSpacing:4*Appearance.fontSizeScale
                            RowLayout {
                            Layout.alignment:Qt.AlignLeft
                            spacing:2
                            EditorIconHint {
                            Layout.preferredWidth:20*Appearance.fontSizeScale
                            glyph:"line_weight";description:"Physical Edge width" }
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            editorSquare:true
                            Layout.preferredWidth:root.editorActionSize
                            
                            text:"Inherit surface";glyph:"layers";compact:true
                            description:"Inherit the physical surface thickness"
                            
                            enabled:(root.edgeThicknesses[root.editingEdge] ?? -1)>=0
                            onClicked:root.edgeThicknesses=Object.assign(
                            {},root.edgeThicknesses,
                            {[root.editingEdge]:-1})
                            }
                            AbyssButton {
                            objectName:!root.useHorizontalDock ? "abyssRoundZeroCorners" : ""
                            text:"Round inner corners at 0 px";glyph:"rounded_corner"
                            compact:true;editorSquare:true;checkable:true
                            description:enabled
                            ? "Round the workspace-side inner corners when the physical Edge is 0 px wide."
                            : "Set physical Edge width to 0 px to enable inner-corner rounding."
                            Layout.preferredWidth:root.editorActionSize
                            Layout.preferredHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            Layout.maximumHeight:root.editorActionSize
                            enabled:Placement.edgeThickness(root.draftOptions,root.editingEdge)===0
                            checked:root.edgeRoundZeroCorners[root.editingEdge]===true
                            onToggled:root.edgeRoundZeroCorners=Object.assign({},root.edgeRoundZeroCorners,{[root.editingEdge]:checked})
                            }
                            }
                            AbyssSlider {
                            editorCompact:true
                            objectName:!root.useHorizontalDock ? "abyssEdgeWidthSlider" : ""
                            Layout.fillWidth:true;Layout.preferredWidth:190*Appearance.fontSizeScale
                            Layout.minimumWidth:75*Appearance.fontSizeScale
                            
                            
                            unit:"px";from:0;to:40;stepSize:1
                            
                            value:Placement.edgeThickness(
                            root.draftOptions,root.editingEdge)
                            onMoved:root.edgeThicknesses=Object.assign(
                            {},root.edgeThicknesses,
                            {[root.editingEdge]:value})
                            }
                            }
                            GridLayout {
                            id:scaleModulesRow
                            Layout.fillWidth:true;Layout.minimumWidth:0
                            readonly property bool inlineControls: edgeEditorColumn.width>=135*Appearance.fontSizeScale+4
                            columns:inlineControls ? 2 : 1
                            columnSpacing:2;rowSpacing:4*Appearance.fontSizeScale
                            RowLayout {
                            Layout.alignment:Qt.AlignLeft
                            spacing:2
                            AbyssButton {
                            objectName:!root.useHorizontalDock ? "abyssScaleModulesToggle" : ""
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            editorSquare:true
                            Layout.preferredWidth:root.editorActionSize
                            
                            compact:true
                            
                            text:"Width affects modules";glyph:"width"
                            description:"Scale modules: scale inherited modules with this Edge (0px hides them), or change only the bare Edge and retain local module bulges. Custom module sizes stay independent."
                            checkable:true;checked:root.edgeWidthAffectsModules[root.editingEdge]!==false
                            onToggled:root.edgeWidthAffectsModules=Object.assign({},root.edgeWidthAffectsModules,{[root.editingEdge]:checked})
                            }
                            AbyssButton {
                            Layout.maximumHeight:root.editorActionSize
                            Layout.maximumWidth:root.editorActionSize
                            editorSquare:true
                            Layout.preferredWidth:root.editorActionSize
                            
                            text:"Expand whole Edge";glyph:"fit_screen"
                            compact:true
                            description:"Expand a single module across the whole Edge; turn off to expand only its local surface."
                            checkable:true
                            
                            enabled:root.draft.filter(
                            p=>p.enabled && p.edge===root.editingEdge && !Placement.isUnifiedKind(p.kind)).length===1
                            checked:root.singleModuleExpansion[root.editingEdge]!=="local"
                            onToggled:root.singleModuleExpansion=Object.assign(
                            {},root.singleModuleExpansion,
                            {[root.editingEdge]:checked ? "edge" : "local"})
                            }
                            }
                            AbyssSlider {
                            editorCompact:true
                            objectName:!root.useHorizontalDock ? "abyssScaleModulesSlider" : ""
                            Layout.fillWidth:true;Layout.preferredWidth:190*Appearance.fontSizeScale
                            Layout.minimumWidth:75*Appearance.fontSizeScale
                            
                            
                            from:.6;to:1.8;stepSize:.01;value:root.moduleScale
                            
                            onMoved:root.moduleScale=value
                            StyledToolTip { text:"Overall module scale" }
                            }
                            }
                    }
                }

            }
        }
    }
}
