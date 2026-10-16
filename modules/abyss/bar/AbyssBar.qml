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
    property var draggedIds: []
    property var liquidController: null
    property var measuredExtents: ({})
    readonly property var layoutOptions: Object.assign({},draftOptions ?? Layout.optionsForOutput(Config.options?.abyss?.modules,outputName),{extents:measuredExtents,editing:editing,edgeThickness:AbyssStyle.perimeterThickness,cornerRadius:AbyssStyle.perimeterRadius})
    property var pendingMeasurements: ({})
    property bool measurementQueued: false
    function measure(id, span): void {
        if (!Number.isFinite(span) || Math.abs((pendingMeasurements[id] ?? measuredExtents[id] ?? -1)-span)<.5) return
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
    readonly property var layoutRecords: Layout.geometry(placements,width,height,layoutOptions,Appearance.fontSizeScale)
    readonly property var renderedRecords: {
        const revision=root.revision
        return layoutRecords.map(record=>{
            const item=itemForId(record.id)
            if(!item)return record
            return Object.assign({},record,{along:record.vertical ? item.y : item.x,
                content:{x:item.x,y:item.y,width:item.width,height:item.height}})
        })
    }
    property var inputRegions: []
    property int revision: 0
    // Optional local expansion shares the output field; it has no extra painter.
    readonly property var capacityNotices: editing ? [] : Layout.capacityNotices(layoutRecords,width,height,Appearance.fontSizeScale)
    readonly property var deformations: Layout.localSurfaces(renderedRecords.concat(capacityNotices),width,height,layoutOptions,Appearance.fontSizeScale,AbyssStyle.barThickness)

    property var moduleIds: []
    function syncModuleIds(): void {
        const next=placements.filter(p=>p.enabled).map(p=>p.id)
        if (JSON.stringify(next)!==JSON.stringify(moduleIds)) moduleIds=next
    }
    function itemForId(id): var { return modules.itemAt(moduleIds.indexOf(id)) }
    onPlacementsChanged: syncModuleIds()
    Component.onCompleted: syncModuleIds()
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
            readonly property bool hiddenEdgeLauncher:
                module.unifiedEdgeLauncher && module.placement?.showIcon === false
            // Iconless mode still has one strictly bounded source hitbox at the
            // literal physical edge, rather than an invisible full-width layer.
            readonly property Region inputRegion: Region {
                x: module.unifiedEdgeLauncher && module.attachedEdge === "left"
                    ? 0 : Math.floor(module.x)
                y: module.unifiedEdgeLauncher && module.attachedEdge === "top"
                    ? 0 : Math.floor(module.y)
                width: module.visible && module.enabled
                    ? Math.max(0, (module.unifiedEdgeLauncher && module.attachedEdge === "right"
                        ? root.width : Math.ceil(module.x + module.width)) - x) : 0
                height: module.visible && module.enabled
                    ? Math.max(0, (module.unifiedEdgeLauncher && module.attachedEdge === "bottom"
                        ? root.height : Math.ceil(module.y + module.height)) - y) : 0
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
            onHiddenEdgeLauncherChanged: invalidateInputRegion()
            onUnifiedEdgeLauncherChanged: invalidateInputRegion()
            readonly property var geometry: root.layoutRecords.find(rec => rec.id === modelData)
            liquidController: root.liquidController
            attachedEdge: placement?.edge ?? "top"
            popupJoinedEdge: placement?.joinCorner ? Layout.adjacentEdge(geometry,root.width,root.height) : ""
            contentScale: (geometry?.span ?? 0)/Math.max(1,naturalSpan)
            onNaturalSpanChanged: root.measure(modelData,naturalSpan)
            Component.onCompleted: {root.measure(modelData,naturalSpan);Qt.callLater(rearmMotion)}
            kind: placement?.kind ?? "clock"
            outputName: root.outputName
            vertical: placement?.edge === "left" || placement?.edge === "right"
            compact: placement?.compact ?? false
            showIcon: placement?.showIcon !== false
            onNotesEditorFocusChanged: (outputName, focused) => root.notesEditorFocusChanged(outputName, focused)
            visible: geometry !== undefined && !geometry.capacityConflict
            enabled: !root.editing && visible
            property bool motionReady: false
            property string motionEdge: ""
            property real motionWidth: -1
            property real motionHeight: -1
            function rearmMotion(): void {
                motionEdge=attachedEdge;motionWidth=width;motionHeight=height;motionReady=true
            }
            function settleDimensionChange(): void {
                motionReady=false
                xMotion.complete();yMotion.complete()
                Qt.callLater(rearmMotion)
            }
            onAttachedEdgeChanged:settleDimensionChange()
            readonly property bool animatePlacement: motionReady && motionEdge===attachedEdge && motionWidth===width && motionHeight===height && Appearance.animationsEnabled
                && !placement?.locked && !root.draggedIds.includes(modelData)
            Behavior on x { enabled:module.animatePlacement; NumberAnimation { id:xMotion;duration:Math.min(140,Appearance.animation.elementMove.duration);easing.type:Easing.OutCubic } }
            Behavior on y { enabled:module.animatePlacement; NumberAnimation { id:yMotion;duration:Math.min(140,Appearance.animation.elementMove.duration);easing.type:Easing.OutCubic } }
            x: geometry?.content.x ?? 0; y: geometry?.content.y ?? 0
            width: geometry?.content.width ?? 0; height: geometry?.content.height ?? 0
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
