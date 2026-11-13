pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.abyss.looks
import "../looks/AbyssGeometry.js" as Geometry
import "../looks/AbyssLayout.js" as Layout

// Foreground modules embedded in the reservoir; this Item never paints a bar.
Item {
    id: root
    required property string outputName
    required property string edge
    property var draftPlacements: null
    property var draftOptions: null
    property bool editing: false
    // Selection is owned by Alis Settings, not the layout editor. The editor
    // can still display and reposition dormant modules in Edgebar Hover mode.
    readonly property var launcherModes: ({
        launcherMode: Config.options?.abyss?.modules?.launcherMode,
        notesTimersMode: Config.options?.abyss?.modules?.notesTimersMode,
        notificationActivityMode: Config.options?.abyss?.modules?.notificationActivityMode,
        // Include and track old hide preferences so legacy users do not get
        // a module AND corner hover source during migration.
        iconVisibility: ({
            notesTimers: Config.options?.abyss?.modules?.iconVisibility?.notesTimers,
            notificationActivity: Config.options?.abyss?.modules?.iconVisibility?.notificationActivity
        })
    })
    property var draggedIds: []
    property var liquidController: null
    property var leftSidebarRecord: null
    property var rightSidebarRecord: null
    property var popupObstacleRects: []
    property var basePaintInsets: ({left:0,top:0,right:0,bottom:0})
    function cavaAdjustedGeometry(rec): var {
        const baseAlong = Number(rec?.along ?? 0)
        const baseSpan = Number(rec?.span ?? 0)
        if (root.editing || !rec || rec.kind !== "cava")
            return { protrudeOffset: 0, along: baseAlong, span: baseSpan }
        if ((rec.edge !== "left" && rec.edge !== "right") || baseSpan <= 0)
            return { protrudeOffset: 0, along: baseAlong, span: baseSpan }
        let matchedSb = null
        let offset = 0
        let bandLeft = 0
        let bandRight = 0
        for (const sb of [root.leftSidebarRecord, root.rightSidebarRecord]) {
            if (!sb || sb.edge !== rec.edge || !sb.surface)
                continue
            if (sb.surface.width <= 0 || sb.surface.height <= 0)
                continue
            if (sb.progress !== undefined && sb.progress <= 0.001)
                continue
            const sbTop = Number(sb.surface.y ?? 0)
            const sbBottom = sbTop + Number(sb.surface.height ?? 0)
            if (baseAlong + baseSpan <= sbTop + 8 || baseAlong >= sbBottom - 8)
                continue
            const progressClamp = (sb.progress !== undefined && sb.progress > 1.0) ? (1.0 / sb.progress) : 1.0
            if (rec.edge === "left") {
                const innerRight = Number(sb.surface.x ?? 0) + Number(sb.surface.width ?? 0)
                const cand = (innerRight - Number(root.basePaintInsets?.left ?? 0)) * progressClamp
                if (cand > offset) {
                    offset = cand
                    matchedSb = sb
                    bandLeft = innerRight - 6
                    bandRight = innerRight + 58
                }
            } else {
                const innerLeft = Number(sb.surface.x ?? root.width)
                const cand = ((root.width - Number(root.basePaintInsets?.right ?? 0)) - innerLeft) * progressClamp
                if (cand > offset) {
                    offset = cand
                    matchedSb = sb
                    bandLeft = innerLeft - 58
                    bandRight = innerLeft + 6
                }
            }
        }
        if (!(offset > 0) || !matchedSb)
            return { protrudeOffset: 0, along: baseAlong, span: baseSpan }

        const minY = Number(matchedSb.surface.y ?? 0) + 16
        const maxY = Number(matchedSb.surface.y ?? 0) + Number(matchedSb.surface.height ?? 0) - 16
        if (maxY - minY < 72)
            return { protrudeOffset: 0, along: baseAlong, span: baseSpan }

        const blockers = []
        const obsList = root.popupObstacleRects ?? []
        for (let i = 0; i < obsList.length; ++i) {
            const obs = obsList[i]
            if (!obs || !(obs.width > 0 && obs.height > 0))
                continue
            const ox1 = Number(obs.x ?? 0)
            const ox2 = ox1 + Number(obs.width ?? 0)
            if (ox2 <= bandLeft || ox1 >= bandRight)
                continue
            const oy1 = Math.max(minY, Number(obs.y ?? 0) - 14)
            const oy2 = Math.min(maxY, Number(obs.y ?? 0) + Number(obs.height ?? 0) + 14)
            if (oy2 > oy1)
                blockers.push([oy1, oy2])
        }
        if (blockers.length === 0)
            return { protrudeOffset: offset, along: baseAlong, span: baseSpan }

        blockers.sort((a, b) => a[0] - b[0])
        const freeSegs = []
        let cursor = minY
        for (let i = 0; i < blockers.length; ++i) {
            const bStart = blockers[i][0]
            const bEnd = blockers[i][1]
            if (bStart > cursor + 0.5)
                freeSegs.push([cursor, bStart])
            cursor = Math.max(cursor, bEnd)
        }
        if (maxY > cursor + 0.5)
            freeSegs.push([cursor, maxY])

        for (let i = 0; i < freeSegs.length; ++i) {
            if (baseAlong >= freeSegs[i][0] - 0.5 && baseAlong + baseSpan <= freeSegs[i][1] + 0.5)
                return { protrudeOffset: offset, along: baseAlong, span: baseSpan }
        }

        let bestFull = null
        let bestDist = Infinity
        let largestSeg = null
        let largestLen = 0
        for (let i = 0; i < freeSegs.length; ++i) {
            const s0 = freeSegs[i][0]
            const s1 = freeSegs[i][1]
            const len = s1 - s0
            if (len > largestLen) {
                largestLen = len
                largestSeg = freeSegs[i]
            }
            if (len >= baseSpan) {
                const candidateAlong = Math.max(s0, Math.min(s1 - baseSpan, baseAlong))
                const dist = Math.abs(candidateAlong - baseAlong)
                if (dist < bestDist) {
                    bestDist = dist
                    bestFull = { protrudeOffset: offset, along: candidateAlong, span: baseSpan }
                }
            }
        }
        if (bestFull)
            return bestFull
        if (largestSeg && largestLen >= 96)
            return { protrudeOffset: offset, along: largestSeg[0], span: largestLen }
        return { protrudeOffset: 0, along: baseAlong, span: baseSpan }
    }
    function cavaProtrusionForRecord(rec): real {
        if (root.editing || !rec || rec.kind !== "cava")
            return 0
        return root.cavaAdjustedGeometry(rec).protrudeOffset
    }
    property var measuredExtents: ({})
    readonly property var configuredLayoutOptions: Object.assign({},launcherModes,draftOptions ?? Layout.optionsForOutput(Config.options?.abyss?.modules,outputName),{extents:measuredExtents,editing:editing,edgeThickness:AbyssStyle.perimeterThickness,cornerRadius:AbyssStyle.perimeterRadius})
    readonly property var layoutOptions: Object.assign({},configuredLayoutOptions,
        widthMorphActive ? {_widthFrame:presentedFrame} : {})
    property var targetFrame: null
    property var fromFrame: null
    property real widthProgress: 1
    property bool frameReady: false
    property string widthModeKey: ""
    property string widthContextKey: ""
    readonly property bool widthMorphActive: fromFrame!==null && widthProgress<1
    readonly property var presentedFrame: widthMorphActive
        ? Layout.widthFrameBetween(fromFrame,targetFrame,widthProgress) : targetFrame
    readonly property var presentedLayoutRecords: presentedFrame?.records ?? layoutRecords
    function captureWidthFrame(): var {
        return Object.assign({},presentedFrame,{
            records:renderedRecords,
            deformations:deformations,
            morphDeformations:presentedFrame?.morphDeformations ?? deformations
        })
    }
    function refreshWidthFrame(): void {
        if(width<=0 || height<=0)return
        const next=Layout.widthFrame(activePlacements,width,height,configuredLayoutOptions,
            Appearance.fontSizeScale,AbyssStyle.barThickness,AbyssStyle.neckRadius,
            AbyssStyle.perimeterRadius+AbyssStyle.neckRadius+AbyssStyle.connectionDepth+32)
        const key=JSON.stringify(["top","right","bottom","left"].map(e=>configuredLayoutOptions.edgeWidthAffectsModules?.[e]!==false))
        const contextKey=JSON.stringify([outputName,edge,width,height,
            ["top","right","bottom","left"].map(e=>Layout.edgeThickness(configuredLayoutOptions,e))])
        const sameContext=contextKey===widthContextKey
        widthContextKey=contextKey
        if(widthMorphActive && sameContext && key===widthModeKey) {
            targetFrame=next
            return
        }
        const animate=frameReady && Config.ready && visible && AbyssStyle.motionEnabled
            && targetFrame!==null && sameContext && key!==widthModeKey
        const previous=animate ? captureWidthFrame() : null
        widthMotion.stop()
        widthModeKey=key
        if(animate){fromFrame=previous;widthProgress=0;targetFrame=next;widthMotion.restart()}
        else {fromFrame=null;widthProgress=1;targetFrame=next}
    }
    function finishWidthMorph(): void {
        if(widthMorphActive){widthMotion.complete();widthProgress=1;fromFrame=null}
    }
    NumberAnimation {
        id:widthMotion;target:root;property:"widthProgress";from:0;to:1
        duration:AbyssStyle.motionNormal;easing.type:Easing.OutCubic
        onFinished:root.fromFrame=null
    }
    onConfiguredLayoutOptionsChanged:refreshWidthFrame()
    onWidthChanged:refreshWidthFrame()
    onHeightChanged:refreshWidthFrame()
    onVisibleChanged:if(!visible)finishWidthMorph()
    Connections {
        target:Appearance
        function onAnimationsEnabledChanged(){if(!Appearance.animationsEnabled)root.finishWidthMorph()}
        function onFontSizeScaleChanged(){root.refreshWidthFrame()}
    }
    Connections {
        target:AbyssStyle
        function onMotionEnabledChanged(){if(!AbyssStyle.motionEnabled)root.finishWidthMorph()}
    }
    property var pendingMeasurements: ({})
    property bool measurementQueued: false
    function measure(id, span): void {
        if (!Number.isFinite(span) || Math.abs((pendingMeasurements[id] ?? measuredExtents[id] ?? -1)-span)<.05) return
        pendingMeasurements=Object.assign({},pendingMeasurements,{[id]:span})
        if(measurementQueued)return
        measurementQueued=true
        Qt.callLater(()=>{
            measurementQueued=false
            measuredExtents=Object.assign({},measuredExtents,pendingMeasurements)
            pendingMeasurements={}
        })
    }
    readonly property bool vertical: edge === "left" || edge === "right"
    signal popupRequested(string kind, string edge, real along)
    signal popupHoveredRequested(string kind, string edge, real along)
    signal popupHoverStateChanged(string kind, string edge, real along, bool hovered)
    signal interaction(string edge, real along, real span, real strength)
    signal layoutRepairRequested()
    signal notesEditorFocusChanged(string outputName, bool focused)
    readonly property var zones: Geometry.barZones(
        (root.vertical ? Config.options?.bar?.verticalLayout : Config.options?.bar?.layout) ?? {},
        root.vertical, Config.options?.bar?.modules ?? {})
    readonly property var placements: draftPlacements ?? Layout.resolve(Config.options?.abyss?.modules,outputName,
        Layout.seed(zones,edge,width,height))
    readonly property var activePlacements: Layout.livePlacements(
        placements,launcherModes,editing)
    readonly property var fallbackLayoutRecords: Layout.geometry(activePlacements,width,height,configuredLayoutOptions,Appearance.fontSizeScale)
    readonly property var layoutRecords: targetFrame?.records ?? fallbackLayoutRecords
    readonly property var baseRenderedRecords: {
        const revision=root.revision
        return presentedLayoutRecords.map(record=>{
            if(!root.editing && record.kind==="cava")return record
            const item=itemForId(record.id)
            if(!item)return record
            return Object.assign({},record,{along:record.vertical ? item.y : item.x,
                content:{x:item.x,y:item.y,width:item.width,height:item.height}})
        })
    }
    readonly property var renderedRecords: {
        const revision=root.revision
        return presentedLayoutRecords.map(record=>{
            const item=itemForId(record.id)
            if(!root.editing && record.kind==="cava") {
                const adj=root.cavaAdjustedGeometry(record)
                const along=item ? (record.vertical ? item.y : item.x) : adj.along
                const span=item ? (record.vertical ? item.height : item.width) : adj.span
                const content=item
                    ? {x:item.x,y:item.y,width:item.width,height:item.height}
                    : Object.assign({},record.content,record.vertical ? {y:adj.along,height:adj.span} : {x:adj.along,width:adj.span})
                return adj.protrudeOffset > 0
                    ? Object.assign({},record,{along:along,span:span,content:content,protrudeOffset:adj.protrudeOffset})
                    : Object.assign({},record,{along:along,span:span,content:content})
            }
            if(!item)return record
            return Object.assign({},record,{along:record.vertical ? item.y : item.x,
                content:{x:item.x,y:item.y,width:item.width,height:item.height}})
        })
    }
    property var inputRegions: []
    property int revision: 0
    // Optional local expansion shares the output field; it has no extra painter.
    readonly property var capacityNotices: editing ? [] : Layout.capacityNotices(layoutRecords,width,height,Appearance.fontSizeScale)
    readonly property var clearanceDeformations: widthMorphActive ? presentedFrame.deformations : Layout.localSurfaces(baseRenderedRecords.concat(capacityNotices),width,height,targetFrame?.options ?? configuredLayoutOptions,Appearance.fontSizeScale,AbyssStyle.barThickness)
    readonly property var deformations: widthMorphActive ? presentedFrame.deformations : Layout.localSurfaces(renderedRecords.concat(capacityNotices),width,height,targetFrame?.options ?? configuredLayoutOptions,Appearance.fontSizeScale,AbyssStyle.barThickness)

    property var moduleIds: []
    property var hoveredModuleKinds: ({})
    function setModuleKindHovered(kind, hovered): void {
        if (!kind) return
        const current = Boolean(hoveredModuleKinds[kind])
        if (current === Boolean(hovered)) return
        const next = Object.assign({}, hoveredModuleKinds)
        if (hovered) next[kind] = true
        else delete next[kind]
        hoveredModuleKinds = next
    }
    function syncModuleIds(): void {
        const next=activePlacements.filter(p=>p.enabled).map(p=>p.id)
        if (JSON.stringify(next)!==JSON.stringify(moduleIds)) moduleIds=next
        refreshWidthFrame()
    }
    function itemForId(id): var { return modules.itemAt(moduleIds.indexOf(id)) }
    onActivePlacementsChanged: syncModuleIds()
    Component.onCompleted: {syncModuleIds();frameReady=true}
    Repeater {
        id: modules
        model: root.moduleIds
        onItemAdded: (index,item) => {
            root.inputRegions = root.inputRegions.concat([item.inputRegion])
            root.revision++
        }
        onItemRemoved: (index,item) => {
            root.inputRegions = root.inputRegions.filter(region => region !== item.inputRegion)
            root.revision++
        }
        AbyssBarModule {
            id: module
            required property string modelData
            required property int index
            readonly property var placement: root.placements.find(p=>p.id===modelData)
            // The full-output PanelWindow and this bar share item coordinates.
            // Bind the compositor hit box to the *computed* module geometry,
            // not an item-backed Region whose transformed position may remain
            // stale after dynamic placement/scale changes. Round outwards so
            // fractional DPI never clips the first/last hover pixel.
            // Edit Mode uses its own dedicated handle regions instead.
            readonly property bool unifiedEdgeLauncher:
                (module.kind === "notesTimers" || module.kind === "notificationActivity")
            readonly property bool moduleIconHitOnly:
                module.unifiedEdgeLauncher && module.showIcon
            readonly property real moduleIconHitSize: Math.max(1,
                Math.min(module.width,module.height,
                    30*Appearance.fontSizeScale*module.contentScale))
            // Unified launchers always paint their icons while the module
            // owns the source. Edgebar mode removes these live instances;
            // there must never be an invisible module edge hover trigger.
            readonly property Region inputRegion: Region {
                // Module Icon mode owns only the painted glyph, never the
                // physical screen strip. A hidden module gets zero input;
                // its legacy corner is mounted separately in Edgebar mode.
                x: module.moduleIconHitOnly
                    ? Math.floor(module.x+(module.width-module.moduleIconHitSize)/2)
                    : Math.floor(module.x)
                y: module.moduleIconHitOnly
                    ? Math.floor(module.y+(module.height-module.moduleIconHitSize)/2)
                    : Math.floor(module.y)
                width: module.visible && module.enabled
                        && (!module.unifiedEdgeLauncher || module.showIcon)
                    ? Math.max(0,module.moduleIconHitOnly
                        ? Math.ceil(module.x+(module.width+module.moduleIconHitSize)/2)-x
                        : Math.ceil(module.x+module.width)-x) : 0
                height: module.visible && module.enabled
                        && (!module.unifiedEdgeLauncher || module.showIcon)
                    ? Math.max(0,module.moduleIconHitOnly
                        ? Math.ceil(module.y+(module.height+module.moduleIconHitSize)/2)-y
                        : Math.ceil(module.y+module.height)-y) : 0
            }
            // Quickshell Region documents cases where geometry does not
            // invalidate its compositor mask automatically. Explicitly
            // announce source-bound changes, including same-pixel fractional
            // moves. Do not broaden the region to the full-output host.
            function invalidateInputRegion(): void {
                if (inputRegion) inputRegion.changed()
            }
            onXChanged: invalidateInputRegion()
            onYChanged: invalidateInputRegion()
            onWidthChanged: {invalidateInputRegion();settleDimensionChange()}
            onHeightChanged: {invalidateInputRegion();settleDimensionChange()}
            onVisibleChanged: invalidateInputRegion()
            onEnabledChanged: invalidateInputRegion()
            onUnifiedEdgeLauncherChanged: invalidateInputRegion()
            onModuleIconHitOnlyChanged: invalidateInputRegion()
            onModuleIconHitSizeChanged: invalidateInputRegion()
            readonly property var geometry: root.presentedLayoutRecords.find(rec => rec.id === modelData)
            liquidController: root.liquidController
            attachedEdge: placement?.edge ?? "top"
            moduleRotation: placement?.rotation !== undefined ? Layout.normalizeRotation(placement.rotation, attachedEdge) : -1
            popupJoinedEdge: placement?.joinCorner ? Layout.adjacentEdge(geometry,root.width,root.height) : ""
            contentScale: ((geometry?.designSpan ?? geometry?.span) ?? 0)/Math.max(1,naturalSpan)
            onNaturalSpanChanged: if (root) root.measure(modelData,naturalSpan)
            Component.onCompleted: {if (root) root.measure(modelData,naturalSpan);Qt.callLater(rearmMotion)}
            kind: placement?.kind ?? "clock"
            outputName: root.outputName
            vertical: placement?.edge === "left" || placement?.edge === "right"
            compact: placement?.compact ?? false
            // No invisible module source: a unified launcher that survives
            // livePlacements is in Module Icon mode and always paints its icon.
            // Stale per-output showIcon=false remains stored for rollback only.
            showIcon: module.unifiedEdgeLauncher ? true : placement?.showIcon !== false
            onNotesEditorFocusChanged: (outputName, focused) => root.notesEditorFocusChanged(outputName, focused)
            visible: geometry !== undefined && !geometry.capacityConflict
            // enabled: !root.editing
            enabled: !(root?.editing ?? false) && visible
            property bool motionReady: false
            property string motionEdge: ""
            property real motionWidth: -1
            property real motionHeight: -1
            readonly property string layoutEdge: geometry?.edge ?? attachedEdge
            readonly property real layoutWidth: geometry?.content.width ?? width
            readonly property real layoutHeight: geometry?.content.height ?? height
            function rearmMotion(): void {
                motionEdge=layoutEdge;motionWidth=layoutWidth;motionHeight=layoutHeight;motionReady=true
            }
            function settleDimensionChange(): void {
                motionReady=false
                xMotion.complete();yMotion.complete()
                Qt.callLater(rearmMotion)
            }
            onLayoutEdgeChanged:settleDimensionChange()
            onLayoutWidthChanged:settleDimensionChange()
            onLayoutHeightChanged:settleDimensionChange()
            onAttachedEdgeChanged:settleDimensionChange()
            onModuleRotationChanged:settleDimensionChange()
            readonly property var cavaAdjusted: module.kind === "cava" ? root.cavaAdjustedGeometry(geometry) : null
            readonly property real cavaProtrusion: cavaAdjusted?.protrudeOffset ?? 0
            readonly property real cavaShiftX: module.attachedEdge === "left" ? cavaProtrusion
                : module.attachedEdge === "right" ? -cavaProtrusion : 0
            readonly property bool animatePlacement: !root.widthMorphActive && motionReady && motionEdge===attachedEdge && motionWidth===width && Appearance.animationsEnabled
                && !placement?.locked && !root.draggedIds.includes(modelData)
            Behavior on x { enabled:module.animatePlacement && module.motionHeight===module.height && module.cavaProtrusion < 0.01; NumberAnimation { id:xMotion;duration:Math.min(140,Appearance.animation.elementMove.duration);easing.type:Easing.OutCubic } }
            Behavior on y { enabled:module.animatePlacement && (module.motionHeight===module.height || module.kind==="cava"); NumberAnimation { id:yMotion;duration:Math.min(140,Appearance.animation.elementMove.duration);easing.type:Easing.OutCubic } }
            x: (geometry?.content.x ?? 0) + cavaShiftX
            y: module.kind === "cava" && module.vertical && cavaAdjusted ? cavaAdjusted.along : (geometry?.content.y ?? 0)
            width: geometry?.content.width ?? 0
            height: module.kind === "cava" && module.vertical && cavaAdjusted ? cavaAdjusted.span : (geometry?.content.height ?? 0)
            onInteraction: strength => { if (geometry) root.interaction(geometry.edge,geometry.along+geometry.span/2,geometry.span,strength*geometry.influence) }
            Loader {
                anchors.right:parent.right;anchors.top:parent.top
                active:!root.editing && !!module.geometry?.lockConflict
                sourceComponent:MaterialSymbol {text:"warning";iconSize:14;color:Appearance.colors.colError;Accessible.name:module.geometry?.lockConflict || ""}
            }
            onRequest: kind => { if (geometry) root.popupRequested(kind,geometry.edge,geometry.along+geometry.span/2) }
            onHoverRequest: kind => { if (geometry) root.popupHoveredRequested(kind,geometry.edge,geometry.along+geometry.span/2) }
            onHoverState: (kind, hovered) => {
                if (geometry)
                    root.popupHoverStateChanged(kind,geometry.edge,geometry.along+geometry.span/2,hovered)
            }
            onHoveredChanged: if (root) root.setModuleKindHovered(module.kind, module.hovered)
            Component.onDestruction: if (root) root.setModuleKindHovered(module.kind, false)
        }
    }
    Repeater {
        model: root.capacityNotices
        onItemAdded: (index,item) => {
            root.inputRegions=root.inputRegions.concat([item.inputRegion]);root.revision++
        }
        onItemRemoved: (index,item) => {
            root.inputRegions=root.inputRegions.filter(region=>region!==item.inputRegion);root.revision++
        }
        RippleButton {
            id: notice
            required property var modelData
            objectName: "abyssCapacityNotice_"+modelData.edge
            x: modelData.content.x; y: modelData.content.y
            width: modelData.content.width; height: modelData.content.height
            buttonRadius: Appearance.rounding.small
            padding: 0
            focusPolicy: Qt.StrongFocus
            Accessible.name: Translation.tr(modelData.message)+" "+Translation.tr("Edit layout")
            readonly property Region inputRegion: Region {
                x: Math.floor(notice.x); y: Math.floor(notice.y)
                width: notice.visible ? Math.ceil(notice.x+notice.width)-Math.floor(notice.x) : 0
                height: notice.visible ? Math.ceil(notice.y+notice.height)-Math.floor(notice.y) : 0
            }
            onClicked: root.layoutRepairRequested()
            contentItem: MaterialSymbol {
                text: "warning"
                color: Appearance.colors.colError
                iconSize: Math.min(20*Appearance.fontSizeScale,notice.width-4)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            StyledToolTip {text:notice.Accessible.name}
        }
    }
}
