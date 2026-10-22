pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import "DashboardLayout.js" as WorkingLayout
import "DashboardPagePolicy.js" as PagePolicy

Item {
    id: root
    // The owning Dashboard surface clips to its rounded outer boundary.
    // Clipping here would erase every card's outward shadow at canvas edges.
    clip: false

    property bool editMode: false
    property bool presentationActive: true
    property bool warmContent: false
    // One rendering/editing implementation per tab; only layout state differs.
    property string customTabId: ""
    readonly property var layoutOptions: {
        if (!root.customTabId.length)
            return Config.options?.dashboard?.canvas ?? ({})
        const layouts = Config.options?.dashboard?.customTabLayouts ?? []
        return Array.from(layouts).find(layout => layout?.id === root.customTabId) ?? ({})
    }
    readonly property bool responsiveWorkspace: (Config.options?.panelFamily ?? "abyss") === "abyss"
    readonly property var workspace: {
        if (!responsiveWorkspace) return {width:Math.max(1,width),height:Math.max(1,height),rects:({}),overflow:[]}
        const entries=root._allIds.map(id=>root._entryFor(id)), minimums=({})
        for (const id of root._allIds) minimums[id]=root._minimumSize(id)
        return WorkingLayout.project(entries,root.width,root.height,minimums,root.collisionGap,
            {width:root._workspaceReferenceWidth,
             height:root._workspaceReferenceHeight})
    }
    property string layoutMessage: ""
    property var _undoEntries: []
    readonly property bool canUndo: editMode && _undoEntries.length>0
    function undoLastEdit() {
        if (!root.canUndo) return
        root.finishInteraction(false)
        const history=root._undoEntries.slice()
        const previous=history.pop()
        root._draftEntries=previous.widgets
        root._draftPageOrder=previous.pages
        root._basePageOrder=previous.basePages
        root._draftWorkspaceWidth=previous.width
        root._draftWorkspaceHeight=previous.height
        root._undoEntries=history
        root.layoutMessage=""
    }
    signal requestEventsDialog(var event)

    readonly property int gridSize: Math.max(8, Number(
        root.editMode && root._draftGridSize !== null
            ? root._draftGridSize
            : (Config.options?.dashboard?.canvas?.gridSize ?? 24)))
    readonly property bool snapEnabled:
        root.editMode && root._draftSnap !== null
            ? root._draftSnap
            : (Config.options?.dashboard?.canvas?.snap ?? true)
    readonly property bool autoAdjustSizeEnabled:
        root.editMode && root._draftAutoAdjustSize !== null
            ? root._draftAutoAdjustSize
            : (Config.options?.dashboard?.canvas?.autoAdjustSize ?? true)
    readonly property string gridStyle:
        root.editMode && root._draftGridStyle !== null
            ? root._draftGridStyle
            : (Config.options?.dashboard?.canvas?.gridStyle ?? "dots")

    readonly property var _catalog: ({
        welcome:       { icon: "waving_hand",       label: Translation.tr("Welcome") },
        clock:         { icon: "schedule",          label: Translation.tr("Clock") },
        system:        { icon: "monitoring",        label: Translation.tr("System usage") },
        github:        { icon: "deployed_code",     label: Translation.tr("GitHub activity") },
        notifications: { icon: "notifications",     label: Translation.tr("Notifications") },
        todo:          { icon: "checklist",         label: Translation.tr("To Do") },
        media:          { icon: "music_note",        label: Translation.tr("Media player") },
        weather:        { icon: "partly_cloudy_day", label: Translation.tr("Weather") },
        calendar:       { icon: "calendar_month",    label: Translation.tr("Calendar") },
        agenda:         { icon: "event_upcoming",    label: Translation.tr("Agenda") },
        notes:          { icon: "edit_note",         label: Translation.tr("Notes") }
    })
    readonly property var _allIds: [
        "welcome", "clock", "system", "github", "notifications",
        "todo", "media", "weather", "calendar", "agenda", "notes"
    ]
    readonly property var _defaultGeometry: ({
        welcome:       { x: 0.00, y: 0.00, w: 0.30, h: 0.18, visible: true },
        clock:         { x: 0.00, y: 0.19, w: 0.30, h: 0.14, visible: true },
        system:        { x: 0.00, y: 0.34, w: 0.30, h: 0.17, visible: true },
        github:        { x: 0.00, y: 0.52, w: 0.30, h: 0.12, visible: true },
        notifications: { x: 0.31, y: 0.00, w: 0.35, h: 0.25, visible: true },
        agenda:         { x: 0.31, y: 0.26, w: 0.35, h: 0.13, visible: true },
        todo:           { x: 0.31, y: 0.40, w: 0.35, h: 0.24, visible: true },
        media:          { x: 0.67, y: 0.00, w: 0.33, h: 0.62, visible: true },
        weather:        { x: 0.67, y: 0.64, w: 0.33, h: 0.36, visible: true },
        calendar:       { x: 0.00, y: 0.65, w: 0.66, h: 0.35, visible: true },
        notes:          { x: 0.67, y: 0.77, w: 0.33, h: 0.23, visible: false }
    })

    readonly property var _widgetMap: ({
        welcome: welcomeComponent,
        clock: clockComponent,
        weather: weatherComponent,
        calendar: calendarComponent,
        media: mediaComponent,
        notifications: notificationsComponent,
        todo: todoComponent,
        system: systemComponent,
        github: githubComponent,
        agenda: agendaComponent,
        notes: notesComponent
    })

    property string selectedId: ""
    property var _preview: ({})
    property var _interaction: null
    property var _smartGuides: []
    property var _smartSnapAxes: ({ x: false, y: false })

    // Dashboard layout editing is transactional. The live editor works against
    // this in-memory draft; persistent Config is touched only by Done.
    property var _draftEntries: null
    property var _draftPageOrder: null
    property var _basePageOrder: null
    readonly property var savedPageOrder: Config.options?.dashboard?.pageOrder ?? PagePolicy.defaultOrder
    readonly property var effectivePageOrder: editMode && _draftPageOrder!==null ? _draftPageOrder : savedPageOrder
    readonly property bool pageOrderDirty: editMode && JSON.stringify(_draftPageOrder)!==JSON.stringify(_basePageOrder)
    onSavedPageOrderChanged: {
        if (editMode && !pageOrderDirty) {
            _basePageOrder=Array.from(savedPageOrder)
            _draftPageOrder=Array.from(savedPageOrder)
        }
    }
    property real _draftWorkspaceWidth: 0
    property real _draftWorkspaceHeight: 0
    property var _draftGridSize: null
    property var _draftSnap: null
    property var _draftAutoAdjustSize: null
    property var _draftGridStyle: null
    readonly property real _workspaceReferenceWidth:
        root.editMode && root._draftEntries !== null
            ? root._draftWorkspaceWidth
            : Number(root.layoutOptions?.workspaceWidth ?? 0)
    readonly property real _workspaceReferenceHeight:
        root.editMode && root._draftEntries !== null
            ? root._draftWorkspaceHeight
            : Number(root.layoutOptions?.workspaceHeight ?? 0)

    function _icon(id) {
        return root._catalog[id]?.icon ?? "widgets"
    }

    function _label(id) {
        return root._catalog[id]?.label ?? id
    }

    function _defaultEntry(id) {
        const g = root._defaultGeometry[id] ?? {
            x: 0.10, y: 0.10, w: 0.30, h: 0.24, visible: false
        }
        return {
            id: id,
            x: Number(g.x),
            y: Number(g.y),
            w: Number(g.w),
            h: Number(g.h),
            visible: root.customTabId.length === 0 && g.visible !== false
        }
    }

    function defaultEntries() {
        const result = []
        for (const id of root._allIds)
            result.push(root._defaultEntry(id))
        return result
    }

    function _storedEntries() {
        if (root.editMode && root._draftEntries !== null)
            return root._draftEntries
        // Keep the original JsonAdapter list path for the built-in page.
        // A QML list<var> need not satisfy JS Array.isArray().
        return root.customTabId.length
            ? (root.layoutOptions?.widgets ?? [])
            : (Config.options?.dashboard?.canvas?.widgets ?? [])
    }

    function _cloneEntries(entries) {
        return JSON.parse(JSON.stringify(entries ?? []))
    }

    function _captureEditDraft() {
        if (root._draftEntries !== null)
            return
        // Capture the literal saved entries, not the responsive projection.
        // Pressing Done without making an edit must be an identity operation.
        root._draftEntries = root._cloneEntries(root._storedEntries())
        root._basePageOrder=Array.from(root.savedPageOrder)
        root._draftPageOrder=Array.from(root.savedPageOrder)
        root._draftWorkspaceWidth = Number(
            root.layoutOptions?.workspaceWidth ?? 0)
        root._draftWorkspaceHeight = Number(
            root.layoutOptions?.workspaceHeight ?? 0)
        root._draftGridSize = Number(
            Config.options?.dashboard?.canvas?.gridSize ?? 24)
        root._draftSnap =
            Config.options?.dashboard?.canvas?.snap ?? true
        root._draftAutoAdjustSize =
            Config.options?.dashboard?.canvas?.autoAdjustSize ?? true
        root._draftGridStyle =
            Config.options?.dashboard?.canvas?.gridStyle ?? "dots"
    }

    function beginEditMode() {
        if (!root.editMode)
            root.editMode = true
    }

    function _rememberDraft(): void {
        root._undoEntries=root._undoEntries.slice(-15).concat([{
            widgets:root._cloneEntries(root._draftEntries ?? root._storedEntries()),
            pages:Array.from(root.effectivePageOrder),
            basePages:Array.from(root._basePageOrder ?? root.savedPageOrder),
            width:root._draftWorkspaceWidth,height:root._draftWorkspaceHeight
        }])
    }

    function movePage(id, target, available): bool {
        if (!root.editMode) return false
        const visible=PagePolicy.ordered(root.effectivePageOrder,available)
        const next=PagePolicy.move(root.effectivePageOrder,available,id,target)
        if (JSON.stringify(visible)===JSON.stringify(PagePolicy.ordered(next,available))) return false
        root.finishInteraction(true)
        root._rememberDraft()
        root._draftPageOrder=next
        root.layoutMessage=""
        return true
    }

    function _layoutUpdates(entries, workspaceWidth, workspaceHeight): var {
        const updates = ({})
        if (!root.customTabId.length) {
            updates["dashboard.canvas.widgets"] = root._cloneEntries(entries)
            if (workspaceWidth !== null)
                updates["dashboard.canvas.workspaceWidth"] = workspaceWidth
            if (workspaceHeight !== null)
                updates["dashboard.canvas.workspaceHeight"] = workspaceHeight
            return updates
        }
        // JsonAdapter persists declared list<var> properties, not arbitrary
        // nested QObject names such as customTabLayouts.custom-1.widgets.
        const stored = Array.from(Config.options?.dashboard?.customTabLayouts ?? [])
        const previous = stored.find(layout => layout?.id === root.customTabId)
        const value = Object.assign({}, previous && typeof previous === "object"
            ? previous : ({}), {id:root.customTabId, widgets:root._cloneEntries(entries)})
        if (workspaceWidth !== null) value.workspaceWidth = workspaceWidth
        if (workspaceHeight !== null) value.workspaceHeight = workspaceHeight
        updates["dashboard.customTabLayouts"] = stored.filter(layout =>
            layout?.id !== root.customTabId).concat([value])
        return updates
    }

    function commitEditMode() {
        if (!root.editMode)
            return
        if (root.pageOrderDirty && JSON.stringify(root.savedPageOrder)!==JSON.stringify(root._basePageOrder)) {
            root.layoutMessage=Translation.tr("Tab order changed elsewhere. Reset or cancel this edit before saving.")
            return
        }
        root.finishInteraction(true)
        const updates = root._layoutUpdates(
            root._draftEntries ?? root._entriesForWrite(),
            root.responsiveWorkspace ? root._draftWorkspaceWidth : null,
            root.responsiveWorkspace ? root._draftWorkspaceHeight : null)
        updates["dashboard.canvas.gridSize"] = root._draftGridSize
        updates["dashboard.canvas.snap"] = root._draftSnap
        updates["dashboard.canvas.autoAdjustSize"] =
            root._draftAutoAdjustSize
        updates["dashboard.canvas.gridStyle"] = root._draftGridStyle
        if (root.pageOrderDirty) {
            updates["dashboard.pageOrder"]=Array.from(root._draftPageOrder)
            updates["dashboard.pageOrderVersion"]=1
        }
        Config.setNestedValues(updates)
        root.editMode = false
    }

    function cancelEditMode() {
        if (root.editMode)
            root.editMode = false
    }

    function _entryFor(id) {
        const stored = root._storedEntries()
        for (let i = 0; i < stored.length; ++i) {
            const entry = stored[i]
            if (String(entry?.id ?? "") === id) {
                return {
                    id: id,
                    x: Number(entry?.x ?? root._defaultEntry(id).x),
                    y: Number(entry?.y ?? root._defaultEntry(id).y),
                    w: Number(entry?.w ?? root._defaultEntry(id).w),
                    h: Number(entry?.h ?? root._defaultEntry(id).h),
                    visible: entry?.visible !== false
                }
            }
        }
        return root._defaultEntry(id)
    }

    function geometryFor(id) {
        const preview = root._preview[id]
        return preview ?? root._entryFor(id)
    }

    // Visibility is persisted state, not interaction-preview state. Keeping
    // these lists independent from _preview prevents Repeater/model churn on
    // every pointer frame while a module is moving or resizing.
    readonly property var visibleIds: root._allIds.filter(id =>
        root._entryFor(id).visible !== false && (!root.responsiveWorkspace || root.workspace.rects[id] !== undefined))
    readonly property var hiddenIds: root._allIds.filter(id =>
        root._entryFor(id).visible === false || (root.responsiveWorkspace && root.workspace.rects[id] === undefined))

    function _entriesForWrite() {
        const stored = root._storedEntries()
        const source = root._allIds.map(id=>root._entryFor(id)).concat(
            stored.filter(entry=>!root._allIds.includes(String(entry?.id ?? ""))))
        const result = []
        for (let i = 0; i < source.length; ++i) {
            const entry = source[i]
            const projected = root.workspace.rects[String(entry?.id ?? "")]
            if (root.responsiveWorkspace && projected) {
                result.push(Object.assign({id:String(entry.id)},root._normalizedRect(projected,entry.visible)))
                continue
            }
            result.push({
                id: String(entry?.id ?? ""),
                x: Number(entry?.x ?? 0),
                y: Number(entry?.y ?? 0),
                w: Number(entry?.w ?? 0.3),
                h: Number(entry?.h ?? 0.2),
                visible: entry?.visible !== false
            })
        }
        return result
    }

    function _writeEntries(entries) {
        if (root.editMode) {
            const previous=root._cloneEntries(root._draftEntries ?? root._storedEntries())
            if (JSON.stringify(previous)!==JSON.stringify(entries))
                root._rememberDraft()
            root._draftEntries = root._cloneEntries(entries)
            if (root.responsiveWorkspace) {
                root._draftWorkspaceWidth = canvas.width
                root._draftWorkspaceHeight = canvas.height
            }
            return
        }
        Config.setNestedValues(root._layoutUpdates(entries,
            root.responsiveWorkspace ? canvas.width : null,
            root.responsiveWorkspace ? canvas.height : null))
    }

    function _persistPatch(id, patch) {
        const entries = root._entriesForWrite()
        let found = false
        for (let i = 0; i < entries.length; ++i) {
            if (entries[i].id !== id)
                continue
            entries[i] = Object.assign({}, entries[i], patch)
            found = true
            break
        }
        if (!found)
            entries.push(Object.assign({}, root._defaultEntry(id), patch))
        root._writeEntries(entries)
    }

    function setWidgetVisible(id, visible) {
        root.layoutMessage = ""
        if (!visible) {
            root._persistPatch(id, { visible: false })
            if (root.selectedId === id)
                root.selectedId = ""
            return
        }

        const readable = root._minimumSize(id)
        if (root.responsiveWorkspace && (readable.width > canvas.width || readable.height > canvas.height)) {
            root.layoutMessage = Translation.tr("Not enough space for %1. Hide another module or enlarge Dashboard.").arg(root._label(id))
            return
        }

        // A restored widget must join the same collision contract as drag/resize.
        // Find the nearest free placement before making it visible so "Add"
        // cannot reintroduce an overlap from stale saved geometry.
        const obstacles = []
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const otherId = String(root.visibleIds[i])
            if (otherId === id)
                continue
            obstacles.push(root._rectPixels(otherId))
        }
        const base = root._rectPixelsForGeometry(id, root._entryFor(id))
        // Restored modules adapt themselves to the free region. Existing
        // visible modules stay fixed; only the module being added may shrink.
        const resolved = root._resolveNeighbour(
            base, id, obstacles, true)
        let blocked = false
        for (let i = 0; i < obstacles.length; ++i) {
            if (root._rectsOverlap(resolved, obstacles[i],
                    root.collisionGap)) {
                blocked = true
                break
            }
        }
        if (blocked) {
            root.layoutMessage = Translation.tr("Not enough space for %1. Hide another module or enlarge Dashboard.").arg(root._label(id))
            return
        }

        const g = root._normalizedRect(resolved, true)
        root._persistPatch(id, {
            x: g.x, y: g.y, w: g.w, h: g.h, visible: true
        })
    }

    function resetLayout() {
        root._preview = ({})
        root._interaction = null
        root.selectedId = ""
        if (root.editMode) {
            // Reset means "back to the last Done state" during an edit
            // transaction. Once Done commits a layout, that layout becomes the
            // next edit session's baseline/default rather than jumping back to
            // the factory geometry.
            const committed = root.customTabId.length
                ? (root.layoutOptions?.widgets ?? [])
                : (Config.options?.dashboard?.canvas?.widgets ?? [])
            root._rememberDraft()
            root._basePageOrder=Array.from(root.savedPageOrder)
            root._draftPageOrder=Array.from(root.savedPageOrder)
            root._draftEntries = root._cloneEntries(
                committed.length > 0 ? committed : root.defaultEntries())
            root._draftWorkspaceWidth = Number(
                root.layoutOptions?.workspaceWidth ?? 0)
            root._draftWorkspaceHeight = Number(
                root.layoutOptions?.workspaceHeight ?? 0)
        } else {
            Config.setNestedValues(root._layoutUpdates(root.defaultEntries(),0,0))
        }
    }

    function _smartAllLayoutEntries(): var {
        const cw = Math.max(1, canvas.width)
        const ch = Math.max(1, canvas.height)
        const gap = root.collisionGap

        // Content-aware targets: compact status cards should stay compact,
        // planning widgets need reading room, and rich visual surfaces benefit
        // from substantially more area. Do not inflate every card merely to
        // consume the canvas.
        const lanes = [
            {
                ids:["welcome","clock","system","github","notes"],
                preferredWidth:360, maxWidth:420,
                preferredHeights:{
                    welcome:90,clock:100,system:185,github:150,notes:280
                },
                maxHeights:{
                    welcome:110,clock:120,system:220,github:185,notes:350
                },
                growPriority:["notes","github","system","welcome","clock"]
            },
            {
                ids:["notifications","agenda","todo","calendar"],
                preferredWidth:430, maxWidth:500,
                preferredHeights:{
                    notifications:200,agenda:150,todo:220,calendar:220
                },
                maxHeights:{
                    notifications:270,agenda:205,todo:295,calendar:270
                },
                growPriority:["notifications","todo","agenda","calendar"]
            },
            {
                ids:["media","weather"],
                preferredWidth:400, maxWidth:460,
                preferredHeights:{media:330,weather:250},
                maxHeights:{media:390,weather:300},
                growPriority:["media","weather"]
            }
        ]

        const minLaneWidths = lanes.map(lane => {
            let width = 0
            for (const id of lane.ids)
                width = Math.max(width,root._minimumSize(id).width)
            return width
        })
        const availableWidth = cw-gap*(lanes.length-1)
        const minTotalWidth = minLaneWidths.reduce((sum,value)=>sum+value,0)
        if (availableWidth < minTotalWidth)
            return null

        const widths = lanes.map((lane,index) =>
            Math.max(minLaneWidths[index],lane.preferredWidth))
        let usedWidth = widths.reduce((sum,value)=>sum+value,0)

        if (usedWidth > availableWidth) {
            let deficit = usedWidth-availableWidth
            for (let pass=0; pass<2 && deficit>0.5; ++pass) {
                for (let index=0; index<widths.length && deficit>0.5; ++index) {
                    const room = Math.max(0,widths[index]-minLaneWidths[index])
                    if (room<=0) continue
                    const take = Math.min(room,deficit/(widths.length-index))
                    widths[index]-=take
                    deficit-=take
                }
            }
            usedWidth = widths.reduce((sum,value)=>sum+value,0)
        } else {
            let extra = availableWidth-usedWidth
            // Planning/notes benefit most from extra reading room. Media and
            // Orbital Weather deliberately stay moderate instead of becoming
            // the dominant lane merely because the canvas is wide.
            const growOrder=[1,0,2]
            for (const index of growOrder) {
                const room=Math.max(0,lanes[index].maxWidth-widths[index])
                const add=Math.min(room,extra)
                widths[index]+=add
                extra-=add
                if (extra<=0) break
            }
            usedWidth = widths.reduce((sum,value)=>sum+value,0)
        }

        function laneEntries(lane,x,width): var {
            const heights = ({})
            let minimumTotal = gap*Math.max(0,lane.ids.length-1)
            let preferredTotal = minimumTotal
            for (const id of lane.ids) {
                const minH=root._minimumSize(id).height
                heights[id]=Math.max(minH,lane.preferredHeights[id] ?? minH)
                minimumTotal+=minH
                preferredTotal+=heights[id]
            }
            if (minimumTotal>ch)
                return null

            if (preferredTotal>ch) {
                let deficit=preferredTotal-ch
                for (let pass=0; pass<2 && deficit>0.5; ++pass) {
                    for (const id of lane.growPriority.slice().reverse()) {
                        const minH=root._minimumSize(id).height
                        const room=Math.max(0,heights[id]-minH)
                        const take=Math.min(room,deficit)
                        heights[id]-=take
                        deficit-=take
                        if(deficit<=0) break
                    }
                }
            } else {
                let extra=ch-preferredTotal
                for (const id of lane.growPriority) {
                    const cap=Math.max(heights[id],
                        lane.maxHeights[id] ?? heights[id])
                    const add=Math.min(Math.max(0,cap-heights[id]),extra)
                    heights[id]+=add
                    extra-=add
                    if(extra<=0) break
                }
            }

            const used = lane.ids.reduce((sum,id)=>sum+heights[id],0)
                + gap*Math.max(0,lane.ids.length-1)
            // Preserve breathing room on tall dashboards instead of enlarging
            // compact cards beyond what their content can use.
            let y=Math.max(0,Math.min(24,(ch-used)/2))
            const result=[]
            for (const id of lane.ids) {
                result.push({
                    id:id,
                    x:x/cw,y:y/ch,w:width/cw,h:heights[id]/ch,
                    visible:true
                })
                y+=heights[id]+gap
            }
            return result
        }

        const occupiedWidth=usedWidth+gap*(lanes.length-1)
        let x=Math.max(0,(cw-occupiedWidth)/2)
        const result=[]
        for (let index=0; index<lanes.length; ++index) {
            const entries=laneEntries(lanes[index],x,widths[index])
            if(!entries) return null
            for(const entry of entries) result.push(entry)
            x+=widths[index]+gap
        }
        return result
    }
    function fitAllWidgets() {
        root.layoutMessage = ""
        root.finishInteraction(false)
        root._preview = ({})

        const stored = root._entriesForWrite()
        const existingById = ({})
        for (let i = 0; i < stored.length; ++i) {
            const id = String(stored[i]?.id ?? "")
            if (id.length > 0)
                existingById[id] = stored[i]
        }

        const smartEntries = root._smartAllLayoutEntries()
        const canonical = smartEntries ?? root._allIds.map(id =>
            Object.assign({}, root._defaultEntry(id),
                existingById[id] ?? {}, { id: id, visible: true }))
        const minimums = ({})
        for (let i = 0; i < root._allIds.length; ++i) {
            const id = String(root._allIds[i])
            minimums[id] = root._minimumSize(id)
        }

        function ordered(entries) {
            return entries.slice().sort((a, b) => {
                const am = minimums[String(a.id)]
                const bm = minimums[String(b.id)]
                return (bm.width * bm.height) - (am.width * am.height)
            })
        }

        let projection = WorkingLayout.project(
            ordered(canonical), canvas.width, canvas.height,
            minimums, root.collisionGap,
            { width: root._workspaceReferenceWidth,
              height: root._workspaceReferenceHeight })

        // Hidden widgets may carry stale custom geometry. If that cannot pack,
        // retry from readable minimum sizes before declaring the finite canvas
        // too small. Existing collision/readability limits remain authoritative.
        if (projection.overflow.length > 0) {
            const compact = canonical.map(entry => {
                const id = String(entry.id)
                const min = minimums[id]
                const fallback = root._defaultEntry(id)
                return Object.assign({}, entry, {
                    x: fallback.x,
                    y: fallback.y,
                    w: Math.min(1, min.width / Math.max(1, canvas.width)),
                    h: Math.min(1, min.height / Math.max(1, canvas.height)),
                    visible: true
                })
            })
            projection = WorkingLayout.project(
                ordered(compact), canvas.width, canvas.height,
                minimums, root.collisionGap,
                { width: canvas.width, height: canvas.height })
        }

        if (projection.overflow.length > 0) {
            root.layoutMessage = Translation.tr(
                "Not enough Dashboard space for %1 modules")
                    .arg(projection.overflow.length)
            return
        }

        const fitted = canonical.map(entry => {
            const id = String(entry.id)
            const rect = projection.rects[id]
            const geometry = root._normalizedRect(rect, true)
            return Object.assign({}, entry, {
                x: geometry.x, y: geometry.y,
                w: geometry.w, h: geometry.h,
                visible: true
            })
        })
        const extras = stored.filter(entry =>
            root._allIds.indexOf(String(entry?.id ?? "")) === -1)
        root._writeEntries(fitted.concat(extras))
        root.selectedId = ""
        root.layoutMessage = Translation.tr(
            smartEntries
                ? "Added and smart-arranged all Dashboard modules"
                : "Added and fitted all Dashboard modules")
    }

    function _minimumSize(id) {
        switch (id) {
        case "media": return { width: 320, height: 390 }
        case "weather": return { width: 280, height: 180 }
        case "calendar": return { width: 300, height: 210 }
        case "todo": return { width: 260, height: 140 }
        case "notifications": return { width: 260, height: 130 }
        case "notes": return { width: 240, height: 160 }
        case "agenda": return { width: 240, height: 75 }
        case "system": return { width: 260, height: 180 }
        default: return { width: 200, height: 80 }
        }
    }

    function _rectPixelsForGeometry(id, g) {
        const min = root._minimumSize(id)
        const minW = Math.min(canvas.width, min.width)
        const minH = Math.min(canvas.height, min.height)
        const w = Math.max(minW, Math.min(canvas.width,
            Number(g.w) * canvas.width))
        const h = Math.max(minH, Math.min(canvas.height,
            Number(g.h) * canvas.height))
        const x = Math.max(0, Math.min(canvas.width - w,
            Number(g.x) * canvas.width))
        const y = Math.max(0, Math.min(canvas.height - h,
            Number(g.y) * canvas.height))
        return { x: x, y: y, width: w, height: h }
    }

    function _rectPixels(id) {
        if(root._preview[id]) return root._rectPixelsForGeometry(id,root._preview[id])
        return root.workspace.rects[id] ?? root._rectPixelsForGeometry(id,root._entryFor(id))
    }

    function _normalizedRect(px, visible) {
        const cw = Math.max(1, canvas.width)
        const ch = Math.max(1, canvas.height)
        return {
            x: Math.max(0, Math.min(1, px.x / cw)),
            y: Math.max(0, Math.min(1, px.y / ch)),
            w: Math.max(0, Math.min(1, px.width / cw)),
            h: Math.max(0, Math.min(1, px.height / ch)),
            visible: visible !== false
        }
    }

    function _setPreview(id, px) {
        const next = Object.assign({}, root._preview)
        const current = root.geometryFor(id)
        next[id] = root._normalizedRect(px, current.visible)
        root._preview = next
    }

    function _clearPreview(id) {
        if (root._preview[id] === undefined)
            return
        const next = Object.assign({}, root._preview)
        delete next[id]
        root._preview = next
    }

    function _snap(value) {
        if (!root.snapEnabled)
            return value
        return Math.round(value / root.gridSize) * root.gridSize
    }

    function _snapRectForCommit(id, rect, kind, edge, lockX, lockY) {
        if (!root.snapEnabled)
            return root._fitRectToCanvas(
                rect, root._minimumSizeForCanvas(id))

        const min = root._minimumSizeForCanvas(id)
        if (kind === "move") {
            return root._fitRectToCanvas({
                x: lockX ? rect.x : root._snap(rect.x),
                y: lockY ? rect.y : root._snap(rect.y),
                width: rect.width,
                height: rect.height
            }, min)
        }

        let left = rect.x
        let top = rect.y
        let right = rect.x + rect.width
        let bottom = rect.y + rect.height
        const resizeEdge = String(edge ?? "")

        if (resizeEdge.indexOf("w") >= 0 && !lockX)
            left = root._snap(left)
        if (resizeEdge.indexOf("e") >= 0 && !lockX)
            right = root._snap(right)
        if (resizeEdge.indexOf("n") >= 0 && !lockY)
            top = root._snap(top)
        if (resizeEdge.indexOf("s") >= 0 && !lockY)
            bottom = root._snap(bottom)

        left = Math.max(0, Math.min(left, right - min.width))
        right = Math.min(canvas.width, Math.max(right, left + min.width))
        top = Math.max(0, Math.min(top, bottom - min.height))
        bottom = Math.min(canvas.height, Math.max(bottom, top + min.height))

        return root._fitRectToCanvas({
            x: left,
            y: top,
            width: Math.max(1, right - left),
            height: Math.max(1, bottom - top)
        }, min)
    }

    // Material cards always keep a visible gutter even on fine grids.
    readonly property real collisionGap: Math.max(8,
        Math.min(16, Math.round(root.gridSize / 3)))
    readonly property real smartGuideThreshold: Math.max(5,
        Math.min(9, root.gridSize / 4))

    function _cloneRect(rect) {
        return {
            x: Number(rect?.x ?? 0),
            y: Number(rect?.y ?? 0),
            width: Number(rect?.width ?? 1),
            height: Number(rect?.height ?? 1)
        }
    }

    function _minimumSizeForCanvas(id) {
        const requested = root._minimumSize(id)
        return {
            width: Math.min(canvas.width, requested.width),
            height: Math.min(canvas.height, requested.height)
        }
    }

    function _fitRectToCanvas(rect, min) {
        const width = Math.max(min.width,
            Math.min(canvas.width, Number(rect.width)))
        const height = Math.max(min.height,
            Math.min(canvas.height, Number(rect.height)))
        return {
            x: Math.max(0, Math.min(canvas.width - width, Number(rect.x))),
            y: Math.max(0, Math.min(canvas.height - height, Number(rect.y))),
            width: width,
            height: height
        }
    }

    function _otherRects(activeId, baselineRects) {
        const result = []
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const id = String(root.visibleIds[i])
            if (id === activeId)
                continue
            const rect = baselineRects[id] ?? root._rectPixels(id)
            result.push({ id: id, rect: rect })
        }
        return result
    }

    function _smartAlignMove(activeId, sourceRect, baselineRects) {
        const rect = root._cloneRect(sourceRect)
        const threshold = root.smartGuideThreshold
        const others = root._otherRects(activeId, baselineRects)
        const guides = []

        let bestX = null
        let bestY = null
        const activeX0 = rect.x
        const activeX1 = rect.x + rect.width / 2
        const activeX2 = rect.x + rect.width
        const activeY0 = rect.y
        const activeY1 = rect.y + rect.height / 2
        const activeY2 = rect.y + rect.height

        for (let i = 0; i < others.length; ++i) {
            const other = others[i].rect
            const otherX0 = other.x
            const otherX1 = other.x + other.width / 2
            const otherX2 = other.x + other.width
            const otherY0 = other.y
            const otherY1 = other.y + other.height / 2
            const otherY2 = other.y + other.height

            for (let ai = 0; ai < 3; ++ai) {
                const activeX = ai === 0 ? activeX0 : (ai === 1 ? activeX1 : activeX2)
                for (let oi = 0; oi < 3; ++oi) {
                    const otherX = oi === 0 ? otherX0 : (oi === 1 ? otherX1 : otherX2)
                    const delta = otherX - activeX
                    const distance = Math.abs(delta)
                    if (distance <= threshold
                            && (!bestX || distance < bestX.distance)) {
                        bestX = {
                            distance: distance,
                            delta: delta,
                            pos: otherX,
                            other: other
                        }
                    }
                }
            }

            for (let ai = 0; ai < 3; ++ai) {
                const activeY = ai === 0 ? activeY0 : (ai === 1 ? activeY1 : activeY2)
                for (let oi = 0; oi < 3; ++oi) {
                    const otherY = oi === 0 ? otherY0 : (oi === 1 ? otherY1 : otherY2)
                    const delta = otherY - activeY
                    const distance = Math.abs(delta)
                    if (distance <= threshold
                            && (!bestY || distance < bestY.distance)) {
                        bestY = {
                            distance: distance,
                            delta: delta,
                            pos: otherY,
                            other: other
                        }
                    }
                }
            }
        }

        if (bestX)
            rect.x += bestX.delta
        if (bestY)
            rect.y += bestY.delta

        const fitted = root._fitRectToCanvas(
            rect, root._minimumSizeForCanvas(activeId))

        if (bestX) {
            guides.push({
                kind: "vertical",
                x: bestX.pos,
                y1: Math.min(fitted.y, bestX.other.y) - 8,
                y2: Math.max(
                    fitted.y + fitted.height,
                    bestX.other.y + bestX.other.height) + 8
            })
        }
        if (bestY) {
            guides.push({
                kind: "horizontal",
                y: bestY.pos,
                x1: Math.min(fitted.x, bestY.other.x) - 8,
                x2: Math.max(
                    fitted.x + fitted.width,
                    bestY.other.x + bestY.other.width) + 8
            })
        }

        // PowerPoint-style equal-spacing assistance. When the moving card sits
        // between two neighbours with nearly equal gaps, magnetize the final
        // few pixels and show double-ended distance arrows.
        let left = null
        let right = null
        let above = null
        let below = null
        let equalSpacingX = false
        let equalSpacingY = false
        for (let i = 0; i < others.length; ++i) {
            const other = others[i].rect
            const verticalOverlap = Math.min(
                fitted.y + fitted.height,
                other.y + other.height) - Math.max(fitted.y, other.y)
            const horizontalOverlap = Math.min(
                fitted.x + fitted.width,
                other.x + other.width) - Math.max(fitted.x, other.x)

            if (verticalOverlap > 0) {
                const otherRight = other.x + other.width
                if (otherRight <= fitted.x) {
                    const gap = fitted.x - otherRight
                    if (!left || gap < left.gap)
                        left = { rect: other, gap: gap }
                }
                if (other.x >= fitted.x + fitted.width) {
                    const gap = other.x - (fitted.x + fitted.width)
                    if (!right || gap < right.gap)
                        right = { rect: other, gap: gap }
                }
            }

            if (horizontalOverlap > 0) {
                const otherBottom = other.y + other.height
                if (otherBottom <= fitted.y) {
                    const gap = fitted.y - otherBottom
                    if (!above || gap < above.gap)
                        above = { rect: other, gap: gap }
                }
                if (other.y >= fitted.y + fitted.height) {
                    const gap = other.y - (fitted.y + fitted.height)
                    if (!below || gap < below.gap)
                        below = { rect: other, gap: gap }
                }
            }
        }

        if (left && right
                && left.gap >= root.collisionGap
                && right.gap >= root.collisionGap
                && Math.abs(left.gap - right.gap) <= threshold * 2) {
            equalSpacingX = true
            if (!bestX) {
                const delta = (right.gap - left.gap) / 2
                if (Math.abs(delta) <= threshold)
                    fitted.x = Math.max(0,
                        Math.min(canvas.width - fitted.width,
                            fitted.x + delta))
            }
            const leftGap = fitted.x
                - (left.rect.x + left.rect.width)
            const rightGap = right.rect.x
                - (fitted.x + fitted.width)
            const y = fitted.y + fitted.height / 2
            guides.push({
                kind: "spacingH",
                x1: left.rect.x + left.rect.width,
                x2: fitted.x,
                y: y,
                distance: leftGap
            })
            guides.push({
                kind: "spacingH",
                x1: fitted.x + fitted.width,
                x2: right.rect.x,
                y: y,
                distance: rightGap
            })
        }

        if (above && below
                && above.gap >= root.collisionGap
                && below.gap >= root.collisionGap
                && Math.abs(above.gap - below.gap) <= threshold * 2) {
            equalSpacingY = true
            if (!bestY) {
                const delta = (below.gap - above.gap) / 2
                if (Math.abs(delta) <= threshold)
                    fitted.y = Math.max(0,
                        Math.min(canvas.height - fitted.height,
                            fitted.y + delta))
            }
            const aboveGap = fitted.y
                - (above.rect.y + above.rect.height)
            const belowGap = below.rect.y
                - (fitted.y + fitted.height)
            const x = fitted.x + fitted.width / 2
            guides.push({
                kind: "spacingV",
                x: x,
                y1: above.rect.y + above.rect.height,
                y2: fitted.y,
                distance: aboveGap
            })
            guides.push({
                kind: "spacingV",
                x: x,
                y1: fitted.y + fitted.height,
                y2: below.rect.y,
                distance: belowGap
            })
        }

        // Diagonal center guide: visual only. It helps keep diagonal module
        // relationships obvious without constraining freeform placement.
        const cx = fitted.x + fitted.width / 2
        const cy = fitted.y + fitted.height / 2
        let diagonal = null
        for (let i = 0; i < others.length; ++i) {
            const other = others[i].rect
            const ox = other.x + other.width / 2
            const oy = other.y + other.height / 2
            const dx = ox - cx
            const dy = oy - cy
            const diagonalError = Math.abs(Math.abs(dx) - Math.abs(dy))
            const length = Math.sqrt(dx * dx + dy * dy)
            if (Math.min(Math.abs(dx), Math.abs(dy)) > 20
                    && diagonalError <= threshold
                    && (!diagonal || length < diagonal.length)) {
                diagonal = {
                    length: length,
                    x1: cx, y1: cy,
                    x2: ox, y2: oy
                }
            }
        }
        if (diagonal)
            guides.push(Object.assign({ kind: "diagonal" }, diagonal))

        root._smartGuides = guides
        root._smartSnapAxes = {
            x: bestX !== null || equalSpacingX,
            y: bestY !== null || equalSpacingY
        }
        return fitted
    }

    function _smartAlignResize(activeId, sourceRect, edge,
            baselineRects) {
        const rect = root._cloneRect(sourceRect)
        const threshold = root.smartGuideThreshold
        const others = root._otherRects(activeId, baselineRects)
        const min = root._minimumSizeForCanvas(activeId)
        const resizeEdge = String(edge ?? "")
        const guides = []
        let bestVertical = null
        let bestHorizontal = null

        const resizeX = resizeEdge.indexOf("w") >= 0
            || resizeEdge.indexOf("e") >= 0
        const resizeY = resizeEdge.indexOf("n") >= 0
            || resizeEdge.indexOf("s") >= 0
        const activeX = resizeX
            ? (resizeEdge.indexOf("w") >= 0 ? rect.x : rect.x + rect.width)
            : 0
        const activeY = resizeY
            ? (resizeEdge.indexOf("n") >= 0 ? rect.y : rect.y + rect.height)
            : 0

        for (let i = 0; i < others.length; ++i) {
            const other = others[i].rect
            if (resizeX) {
                for (let t = 0; t < 2; ++t) {
                    const target = t === 0 ? other.x : other.x + other.width
                    const delta = target - activeX
                    const distance = Math.abs(delta)
                    if (distance <= threshold
                            && (!bestVertical
                                || distance < bestVertical.distance)) {
                        bestVertical = {
                            distance: distance,
                            delta: delta,
                            pos: target,
                            other: other
                        }
                    }
                }
            }

            if (resizeY) {
                for (let t = 0; t < 2; ++t) {
                    const target = t === 0 ? other.y : other.y + other.height
                    const delta = target - activeY
                    const distance = Math.abs(delta)
                    if (distance <= threshold
                            && (!bestHorizontal
                                || distance < bestHorizontal.distance)) {
                        bestHorizontal = {
                            distance: distance,
                            delta: delta,
                            pos: target,
                            other: other
                        }
                    }
                }
            }
        }

        if (bestVertical) {
            if (resizeEdge.indexOf("w") >= 0) {
                const right = rect.x + rect.width
                const left = Math.min(
                    right - min.width, rect.x + bestVertical.delta)
                rect.x = left
                rect.width = right - left
            } else {
                rect.width = Math.max(
                    min.width, rect.width + bestVertical.delta)
            }
            guides.push({
                kind: "vertical",
                x: bestVertical.pos,
                y1: Math.min(rect.y, bestVertical.other.y) - 8,
                y2: Math.max(
                    rect.y + rect.height,
                    bestVertical.other.y + bestVertical.other.height) + 8
            })
        }

        if (bestHorizontal) {
            if (resizeEdge.indexOf("n") >= 0) {
                const bottom = rect.y + rect.height
                const top = Math.min(
                    bottom - min.height, rect.y + bestHorizontal.delta)
                rect.y = top
                rect.height = bottom - top
            } else {
                rect.height = Math.max(
                    min.height, rect.height + bestHorizontal.delta)
            }
            guides.push({
                kind: "horizontal",
                y: bestHorizontal.pos,
                x1: Math.min(rect.x, bestHorizontal.other.x) - 8,
                x2: Math.max(
                    rect.x + rect.width,
                    bestHorizontal.other.x + bestHorizontal.other.width) + 8
            })
        }

        const fitted = root._fitRectToCanvas(rect, min)
        root._smartGuides = guides
        root._smartSnapAxes = {
            x: bestVertical !== null,
            y: bestHorizontal !== null
        }
        return fitted
    }

    function _snapshotVisibleRects() {
        const result = ({})
        // Always snapshot persisted geometry. Every pointer frame resolves from
        // this immutable baseline so neighbours expand back immediately when the
        // user reverses a resize while still holding the mouse button.
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const id = String(root.visibleIds[i])
            result[id] = root._cloneRect(
                root._rectPixels(id))
        }
        return result
    }

    function _rectsOverlap(a, b, gap) {
        const g = Number(gap ?? 0)
        return a.x < b.x + b.width + g
            && a.x + a.width + g > b.x
            && a.y < b.y + b.height + g
            && a.y + a.height + g > b.y
    }

    function _candidateInRegion(base, min, x0, y0, x1, y1,
            allowResize) {
        const left = Math.max(0, Number(x0))
        const top = Math.max(0, Number(y0))
        const right = Math.min(canvas.width, Number(x1))
        const bottom = Math.min(canvas.height, Number(y1))
        const availableWidth = Math.max(0, right - left)
        const availableHeight = Math.max(0, bottom - top)
        const baseWidth = Math.min(canvas.width, Number(base.width))
        const baseHeight = Math.min(canvas.height, Number(base.height))
        const requiredWidth = allowResize ? min.width : baseWidth
        const requiredHeight = allowResize ? min.height : baseHeight
        if (availableWidth + 0.001 < requiredWidth
                || availableHeight + 0.001 < requiredHeight)
            return null

        // Drag/drop and resize-with-auto-adjust-off preserve neighbour sizes.
        // Shrinking is available only during an explicit resize interaction
        // while Auto-adjust size is enabled.
        const width = allowResize
            ? Math.max(min.width, Math.min(baseWidth, availableWidth))
            : baseWidth
        const height = allowResize
            ? Math.max(min.height, Math.min(baseHeight, availableHeight))
            : baseHeight
        return {
            x: Math.max(left,
                Math.min(right - width, Number(base.x))),
            y: Math.max(top,
                Math.min(bottom - height, Number(base.y))),
            width: width,
            height: height
        }
    }

    function _candidateScore(candidate, base, obstacles,
            knownNoOverlap) {
        if (!candidate)
            return Number.POSITIVE_INFINITY
        let overlaps = 0
        if (!knownNoOverlap) {
            for (let i = 0; i < obstacles.length; ++i) {
                if (root._rectsOverlap(candidate, obstacles[i],
                        root.collisionGap))
                    overlaps++
            }
        }
        const dx = candidate.x - base.x
        const dy = candidate.y - base.y
        const dw = Math.max(0, base.width - candidate.width)
        const dh = Math.max(0, base.height - candidate.height)
        // A local elastic shrink is cheaper than teleporting a widget across
        // the canvas, while any remaining overlap is effectively forbidden.
        return overlaps * 1000000000
            + dx * dx + dy * dy
            + (dw * dw + dh * dh) * 0.35
    }

    function _bestSideCandidate(base, min, obstacle, obstacles,
            allowResize) {
        const gap = root.collisionGap
        const right = obstacle.x + obstacle.width
        const bottom = obstacle.y + obstacle.height
        const candidates = [
            root._candidateInRegion(base, min,
                0, 0, obstacle.x - gap, canvas.height, allowResize),
            root._candidateInRegion(base, min,
                right + gap, 0, canvas.width, canvas.height, allowResize),
            root._candidateInRegion(base, min,
                0, 0, canvas.width, obstacle.y - gap, allowResize),
            root._candidateInRegion(base, min,
                0, bottom + gap, canvas.width, canvas.height, allowResize)
        ]
        let best = null
        let bestScore = Number.POSITIVE_INFINITY
        for (let i = 0; i < candidates.length; ++i) {
            const score = root._candidateScore(
                candidates[i], base, obstacles)
            if (score < bestScore) {
                bestScore = score
                best = candidates[i]
            }
        }
        return best
    }

    function _fallbackPlacement(base, min, obstacles, allowResize) {
        const gap = root.collisionGap
        const widths = allowResize ? [
            Math.min(canvas.width, base.width),
            Math.max(min.width, Math.min(base.width, base.width * 0.82)),
            Math.max(min.width, Math.min(base.width, base.width * 0.66)),
            min.width
        ] : [Math.min(canvas.width, base.width)]
        const heights = allowResize ? [
            Math.min(canvas.height, base.height),
            Math.max(min.height, Math.min(base.height, base.height * 0.82)),
            Math.max(min.height, Math.min(base.height, base.height * 0.66)),
            min.height
        ] : [Math.min(canvas.height, base.height)]
        let best = null
        let bestScore = Number.POSITIVE_INFINITY

        for (let wi = 0; wi < widths.length; ++wi) {
            for (let hi = 0; hi < heights.length; ++hi) {
                const width = Math.min(canvas.width, widths[wi])
                const height = Math.min(canvas.height, heights[hi])
                const xs = [base.x, 0, canvas.width - width]
                const ys = [base.y, 0, canvas.height - height]
                for (let oi = 0; oi < obstacles.length; ++oi) {
                    const obstacle = obstacles[oi]
                    xs.push(obstacle.x - gap - width)
                    xs.push(obstacle.x + obstacle.width + gap)
                    ys.push(obstacle.y - gap - height)
                    ys.push(obstacle.y + obstacle.height + gap)
                }

                for (let xi = 0; xi < xs.length; ++xi) {
                    for (let yi = 0; yi < ys.length; ++yi) {
                        const candidate = root._fitRectToCanvas({
                            x: xs[xi], y: ys[yi],
                            width: width, height: height
                        }, min)
                        let blocked = false
                        for (let oi = 0; oi < obstacles.length; ++oi) {
                            if (root._rectsOverlap(candidate, obstacles[oi], gap)) {
                                blocked = true
                                break
                            }
                        }
                        if (blocked)
                            continue
                        const score = root._candidateScore(
                            candidate, base, obstacles, true)
                        if (score < bestScore) {
                            bestScore = score
                            best = candidate
                        }
                    }
                }
            }
        }
        return best
    }

    function _resolveNeighbour(baseRect, id, obstacles, allowResize) {
        const min = root._minimumSizeForCanvas(id)
        const base = root._fitRectToCanvas(baseRect, min)
        let current = root._cloneRect(base)

        const maxPasses = Math.max(8, obstacles.length * 4)
        for (let pass = 0; pass < maxPasses; ++pass) {
            let blocker = null
            for (let i = 0; i < obstacles.length; ++i) {
                if (root._rectsOverlap(current, obstacles[i],
                        root.collisionGap)) {
                    blocker = obstacles[i]
                    break
                }
            }
            if (!blocker)
                return current

            const next = root._bestSideCandidate(
                base, min, blocker, obstacles, allowResize)
            if (!next)
                break

            const unchanged = Math.abs(next.x - current.x) < 0.01
                && Math.abs(next.y - current.y) < 0.01
                && Math.abs(next.width - current.width) < 0.01
                && Math.abs(next.height - current.height) < 0.01
            current = next
            if (unchanged)
                break
        }

        // Complex chains can exhaust the simple side solver. Search the finite
        // set of obstacle edges before conceding; this keeps ordinary dashboard
        // layouts overlap-free without running a full grid packer every frame.
        return root._fallbackPlacement(
            base, min, obstacles, allowResize) ?? current
    }

    function _resolveLayout(activeId, activeRect, baselineRects,
            allowResize, localResizeOnly) {
        const result = ({})
        const activeMin = root._minimumSizeForCanvas(activeId)
        const fixedActive = root._fitRectToCanvas(activeRect, activeMin)
        result[activeId] = fixedActive

        const activeBase = baselineRects[activeId] ?? fixedActive
        const activeCenterX = activeBase.x + activeBase.width / 2
        const activeCenterY = activeBase.y + activeBase.height / 2
        const others = []
        const directlyAffected = ({})
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const id = String(root.visibleIds[i])
            if (id === activeId)
                continue
            const base = baselineRects[id] ?? root._rectPixels(id)
            const affected = localResizeOnly === true
                && root._rectsOverlap(
                    fixedActive, base, root.collisionGap)
            directlyAffected[id] = affected

            // During resize, never propagate adjustment through the whole
            // dashboard. Unaffected neighbours remain bit-for-bit at their
            // immutable baseline. With auto-adjust disabled, every neighbour
            // stays fixed and the active resize is clamped instead.
            if (localResizeOnly === true
                    && (!allowResize || !affected)) {
                result[id] = root._cloneRect(base)
                continue
            }
            others.push(id)
        }
        // Resolve closest affected neighbours first. Move/drop keeps the
        // existing insertion solver; resize is deliberately local.
        others.sort((a, b) => {
            const ar = baselineRects[a]
            const br = baselineRects[b]
            const adx = (ar.x + ar.width / 2) - activeCenterX
            const ady = (ar.y + ar.height / 2) - activeCenterY
            const bdx = (br.x + br.width / 2) - activeCenterX
            const bdy = (br.y + br.height / 2) - activeCenterY
            return (adx * adx + ady * ady) - (bdx * bdx + bdy * bdy)
        })

        const obstacles = [fixedActive]
        if (localResizeOnly === true) {
            // Fixed neighbours are obstacles, not participants. This prevents
            // a resize from cascading through second- and third-order modules.
            for (let i = 0; i < root.visibleIds.length; ++i) {
                const id = String(root.visibleIds[i])
                if (id === activeId || directlyAffected[id])
                    continue
                obstacles.push(result[id]
                    ?? baselineRects[id] ?? root._rectPixels(id))
            }
        }

        for (let i = 0; i < others.length; ++i) {
            const id = others[i]
            const base = baselineRects[id] ?? root._rectPixels(id)
            const resolved = root._resolveNeighbour(
                base, id, obstacles, allowResize)
            result[id] = resolved
            obstacles.push(resolved)
        }
        return result
    }

    function _sameRect(a, b) {
        return a && b && ["x", "y", "width", "height"].every(
            key => Math.abs(a[key] - b[key]) < 0.001)
    }

    function _layoutHasOverlap(rects, baselineRects) {
        const ids = []
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const id = String(root.visibleIds[i])
            if (rects[id])
                ids.push(id)
        }
        for (let i = 0; i < ids.length; ++i) {
            for (let j = i + 1; j < ids.length; ++j) {
                if (!root._rectsOverlap(rects[ids[i]], rects[ids[j]],
                        root.collisionGap)) continue
                // Old saved layouts can overlap after minimum-size clamping.
                // An unchanged pair elsewhere must not freeze this interaction.
                // Any moved/resized pair still obeys the full collision contract.
                if (baselineRects
                        && root._sameRect(rects[ids[i]], baselineRects[ids[i]])
                        && root._sameRect(rects[ids[j]], baselineRects[ids[j]]))
                    continue
                return true
            }
        }
        return false
    }

    function _isFiniteOverlapRect(rect) {
        return !!rect
            && typeof rect.x === "number" && Number.isFinite(rect.x)
            && typeof rect.y === "number" && Number.isFinite(rect.y)
            && typeof rect.width === "number" && Number.isFinite(rect.width)
            && typeof rect.height === "number" && Number.isFinite(rect.height)
    }

    function _responsiveLayoutHasOverlap(rects, baselineRects, activeId,
            plainSnapshot) {
        // Responsive edit probes are shallow copies of the captured plain
        // baseline with only the active rectangle replaced. Guard that exact
        // provenance before skipping unchanged other-other collision pairs.
        // Any malformed or unproven state falls back to the generic routine.
        if (plainSnapshot !== true || typeof activeId !== "string"
                || !baselineRects)
            return root._layoutHasOverlap(rects, baselineRects)

        const gap = root.collisionGap
        if (typeof gap !== "number" || !Number.isFinite(gap))
            return root._layoutHasOverlap(rects, baselineRects)

        const ids = []
        const seen = Object.create(null)
        let activeIndex = -1
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const id = String(root.visibleIds[i])
            const rect = rects[id]
            if (!rect)
                continue
            if (Object.prototype.hasOwnProperty.call(seen, id))
                return root._layoutHasOverlap(rects, baselineRects)
            seen[id] = true

            const base = baselineRects[id]
            if (!root._isFiniteOverlapRect(rect)
                    || !root._isFiniteOverlapRect(base)
                    || (id !== activeId && rect !== base))
                return root._layoutHasOverlap(rects, baselineRects)
            if (id === activeId)
                activeIndex = ids.length
            ids.push(id)
        }
        if (activeIndex < 0)
            return root._layoutHasOverlap(rects, baselineRects)

        const active = ids[activeIndex]
        for (let i = 0; i < activeIndex; ++i) {
            const left = ids[i]
            if (!root._rectsOverlap(rects[left], rects[active], gap))
                continue
            if (root._sameRect(rects[left], baselineRects[left])
                    && root._sameRect(rects[active], baselineRects[active]))
                continue
            return true
        }
        for (let j = activeIndex + 1; j < ids.length; ++j) {
            const right = ids[j]
            if (!root._rectsOverlap(rects[active], rects[right], gap))
                continue
            if (root._sameRect(rects[active], baselineRects[active])
                    && root._sameRect(rects[right], baselineRects[right]))
                continue
            return true
        }
        return false
    }

    function _interpolateRect(from, to, t) {
        return {
            x: from.x + (to.x - from.x) * t,
            y: from.y + (to.y - from.y) * t,
            width: from.width + (to.width - from.width) * t,
            height: from.height + (to.height - from.height) * t
        }
    }

    function _resolveFeasibleLayout(activeId, startRect, desiredRect,
            baselineRects, allowResize, localResizeOnly) {
        if (root.responsiveWorkspace) {
            // A finite Dashboard never shuffles the other cards during/drop
            // after an edit. Clamp only the active card to a feasible point.
            const fixed = Object.assign({}, baselineRects)
            fixed[activeId] = root._fitRectToCanvas(desiredRect, root._minimumSizeForCanvas(activeId))
            if (!root._responsiveLayoutHasOverlap(
                    fixed, baselineRects, activeId, true)) return fixed
            let safe = Object.assign({}, baselineRects), low = 0, high = 1
            for (let i = 0; i < 12; ++i) {
                const mid = (low + high) / 2
                const probe = Object.assign({}, baselineRects)
                probe[activeId] = root._fitRectToCanvas(root._interpolateRect(startRect, desiredRect, mid), root._minimumSizeForCanvas(activeId))
                if (root._responsiveLayoutHasOverlap(
                        probe, baselineRects, activeId, true)) high = mid
                else { low = mid; safe = probe }
            }
            return safe
        }
        const desired = root._resolveLayout(
            activeId, desiredRect, baselineRects, allowResize,
            localResizeOnly)
        if (!root._layoutHasOverlap(desired, baselineRects))
            return desired

        // If neighbours have reached their minimums/bounds, clamp the active
        // interaction to the last feasible point rather than allowing overlap.
        // Never publish an infeasible insertion, even when the initial saved
        // layout has unrelated overlaps or every free region is exhausted.
        let best = ({})
        for (const id of root.visibleIds)
            best[id] = root._cloneRect(baselineRects[id])
        let low = 0
        let high = 1
        for (let i = 0; i < 8; ++i) {
            const mid = (low + high) / 2
            const probeRect = root._interpolateRect(
                startRect, desiredRect, mid)
            const probe = root._resolveLayout(
                activeId, probeRect, baselineRects, allowResize,
                localResizeOnly)
            if (root._layoutHasOverlap(probe, baselineRects)) {
                high = mid
            } else {
                low = mid
                best = probe
            }
        }
        return best
    }

    function _applyPreviewRects(rects) {
        const next = ({})
        for (let i = 0; i < root.visibleIds.length; ++i) {
            const id = String(root.visibleIds[i])
            const px = rects[id]
            if (!px)
                continue
            next[id] = root._normalizedRect(
                px, root._entryFor(id).visible)
        }
        root._preview = next
    }

    function _persistPreviewLayout() {
        const entries = root._entriesForWrite()
        const indexById = ({})
        for (let i = 0; i < entries.length; ++i)
            indexById[entries[i].id] = i

        for (let i = 0; i < root._allIds.length; ++i) {
            const id = String(root._allIds[i])
            const g = root._preview[id]
            if (g === undefined)
                continue
            const patch = { x: g.x, y: g.y, w: g.w, h: g.h }
            const index = indexById[id]
            if (index === undefined) {
                indexById[id] = entries.length
                entries.push(Object.assign({}, root._defaultEntry(id), patch))
            } else {
                entries[index] = Object.assign({}, entries[index], patch)
            }
        }
        root._writeEntries(entries)
    }

    function beginMove(id, point) {
        root._preview = ({})
        root._smartGuides = []
        root._smartSnapAxes = ({ x: false, y: false })
        root.selectedId = id
        root._interaction = {
            id: id,
            kind: "move",
            startPoint: point,
            startRect: root._rectPixels(id),
            baselineRects: root._snapshotVisibleRects()
        }
    }

    function beginResize(id, edge, point) {
        root._preview = ({})
        root._smartGuides = []
        root._smartSnapAxes = ({ x: false, y: false })
        root.selectedId = id
        root._interaction = {
            id: id,
            kind: "resize",
            edge: edge,
            startPoint: point,
            startRect: root._rectPixels(id),
            baselineRects: root._snapshotVisibleRects()
        }
    }

    function updateInteraction(point) {
        const state = root._interaction
        if (!state)
            return

        const dx = point.x - state.startPoint.x
        const dy = point.y - state.startPoint.y
        const start = state.startRect
        const min = root._minimumSizeForCanvas(state.id)
        let left = start.x
        let top = start.y
        let right = start.x + start.width
        let bottom = start.y + start.height

        if (state.kind === "move") {
            left = start.x + dx
            top = start.y + dy
            left = Math.max(0, Math.min(canvas.width - start.width, left))
            top = Math.max(0, Math.min(canvas.height - start.height, top))

            // A dragged module is temporarily lifted out of the packed layout.
            // Only the selected module follows the pointer; neighbours stay
            // completely stable until drop, when the insertion is resolved once.
            const guided = root._smartAlignMove(state.id, {
                x: left, y: top,
                width: start.width, height: start.height
            }, state.baselineRects)
            root._setPreview(state.id, guided)
            return
        }

        const edge = String(state.edge ?? "")
        if (edge.indexOf("w") >= 0)
            left = start.x + dx
        if (edge.indexOf("e") >= 0)
            right = start.x + start.width + dx
        if (edge.indexOf("n") >= 0)
            top = start.y + dy
        if (edge.indexOf("s") >= 0)
            bottom = start.y + start.height + dy

        left = Math.max(0, Math.min(left, right - min.width))
        right = Math.min(canvas.width, Math.max(right, left + min.width))
        top = Math.max(0, Math.min(top, bottom - min.height))
        bottom = Math.min(canvas.height, Math.max(bottom, top + min.height))

        if (right - left < min.width) {
            if (edge.indexOf("w") >= 0)
                left = right - min.width
            else
                right = left + min.width
        }
        if (bottom - top < min.height) {
            if (edge.indexOf("n") >= 0)
                top = bottom - min.height
            else
                bottom = top + min.height
        }

        left = Math.max(0, left)
        top = Math.max(0, top)
        right = Math.min(canvas.width, right)
        bottom = Math.min(canvas.height, bottom)

        const desired = root._smartAlignResize(state.id, {
            x: left, y: top,
            width: Math.max(1, right - left),
            height: Math.max(1, bottom - top)
        }, edge, state.baselineRects)
        const resolved = root._resolveFeasibleLayout(
            state.id, start, desired, state.baselineRects,
            root.autoAdjustSizeEnabled, true)
        root._applyPreviewRects(resolved)
    }

    function finishInteraction(commit) {
        const state = root._interaction
        if (!state)
            return

        if (!commit) {
            // End direct manipulation first so geometry Behaviors animate the
            // selected module smoothly back to its persisted rect.
            root._interaction = null
            root._preview = ({})
            root._smartGuides = []
            root._smartSnapAxes = ({ x: false, y: false })
            return
        }

        if (Object.keys(root._preview).length === 0) {
            root._interaction = null
            root._smartGuides = []
            root._smartSnapAxes = ({ x: false, y: false })
            return
        }

        const activeGeometry = root._preview[state.id]
        if (activeGeometry !== undefined) {
            const currentRect = root._rectPixelsForGeometry(
                state.id, activeGeometry)
            const snappedRect = root._snapRectForCommit(
                state.id, currentRect, state.kind, state.edge,
                root._smartSnapAxes.x, root._smartSnapAxes.y)
            // Drop is the insertion point: resolve neighbours exactly once
            // after continuous pointer tracking has ended.
            const allowResize = state.kind === "resize"
                && root.autoAdjustSizeEnabled
            const resolved = root._resolveFeasibleLayout(
                state.id, state.startRect, snappedRect,
                state.baselineRects, allowResize,
                state.kind === "resize")

            // Pointer tracking ends before the final target is published. The
            // selected module and any displaced neighbours therefore settle into
            // their snapped positions with the same spatial animation.
            root._interaction = null
            root._smartGuides = []
            root._smartSnapAxes = ({ x: false, y: false })
            root._applyPreviewRects(resolved)
            root._persistPreviewLayout()

            // Keep the resolved preview alive through this event-loop turn so
            // Config propagation cannot briefly expose the old persisted rect.
            // Clearing on the next turn makes the target handoff visually
            // continuous instead of flashing back for one frame.
            Qt.callLater(() => {
                if (root._interaction === null)
                    root._preview = ({})
            })
        } else {
            root._interaction = null
            root._preview = ({})
            root._smartGuides = []
            root._smartSnapAxes = ({ x: false, y: false })
        }
    }

    function toggleSnap() {
        if (root.editMode)
            root._draftSnap = !root.snapEnabled
        else
            Config.setNestedValue("dashboard.canvas.snap", !root.snapEnabled)
    }

    function toggleAutoAdjustSize() {
        if (root.editMode)
            root._draftAutoAdjustSize = !root.autoAdjustSizeEnabled
        else
            Config.setNestedValue("dashboard.canvas.autoAdjustSize",
                !root.autoAdjustSizeEnabled)
    }

    function _cycleGridSize() {
        const sizes = [16, 24, 32, 48, 64]
        const current = root.gridSize
        let index = sizes.indexOf(current)
        index = index < 0 ? 0 : (index + 1) % sizes.length
        const next = sizes[index]
        if (root.editMode)
            root._draftGridSize = next
        else
            Config.setNestedValue("dashboard.canvas.gridSize", next)
    }

    function _cycleGridStyle() {
        const styles = ["dots", "lines", "cross"]
        const current = styles.indexOf(root.gridStyle)
        const next = styles[(current < 0 ? 0 : current + 1) % styles.length]
        if (root.editMode)
            root._draftGridStyle = next
        else
            Config.setNestedValue("dashboard.canvas.gridStyle", next)
    }

    onEditModeChanged: {
        if (editMode) {
            root._captureEditDraft()
            return
        }
        root.finishInteraction(false)
        root._smartGuides = []
        root._smartSnapAxes = ({ x: false, y: false })
        root.selectedId = ""
        root._draftEntries = null
        root._draftPageOrder=null
        root._basePageOrder=null
        root._undoEntries = []
        root._draftWorkspaceWidth = 0
        root._draftWorkspaceHeight = 0
        root._draftGridSize = null
        root._draftSnap = null
        root._draftAutoAdjustSize = null
        root._draftGridStyle = null
    }
    onPresentationActiveChanged:
        if (!presentationActive) root.cancelEditMode()

    Component { id: welcomeComponent; DashWelcome {} }
    Component { id: clockComponent; DashClock {} }
    Component { id: weatherComponent; DashWeather {} }
    Component {
        id: calendarComponent
        DashCalendar {
            onRequestEventsDialog: event => root.requestEventsDialog(event)
        }
    }
    Component {
        id: mediaComponent
        DashMedia {
            presentationActive: root.presentationActive
        }
    }
    Component { id: notificationsComponent; DashNotifications {} }
    Component { id: todoComponent; DashTodo {} }
    Component { id: systemComponent; DashSystem {} }
    Component { id: githubComponent; DashGithub {} }
    Component { id: notesComponent; DashNotes {} }
    Component {
        id: agendaComponent
        DashAgenda {
            onRequestEventsDialog: event => root.requestEventsDialog(event)
        }
    }

    Item {
        id: viewport
        anchors.fill: parent
        clip: root.responsiveWorkspace
        Item {
        id: canvas
        width:root.workspace.width;height:root.workspace.height
        clip:false

        DashboardEditGrid {
            anchors.fill: parent
            visible: root.editMode
            opacity: root.editMode ? 1 : 0
            gridSize: root.gridSize
            gridStyle: root.gridStyle
            Behavior on opacity {
                enabled: Appearance.animationsEnabled
                NumberAnimation {
                    duration: Appearance.animation.elementMoveFast.duration
                }
            }
        }

        DashboardAlignmentGuides {
            anchors.fill: parent
            z: 70
            visible: root.editMode && root._smartGuides.length > 0
            guides: root._smartGuides
        }

        Repeater {
            // Keep delegate identity stable for the whole Dashboard lifetime.
            // A JS-array model derived from _preview would recreate delegates
            // during pointer updates and look like cards were blinking/chopping.
            model: root._allIds

            delegate: Item {
                id: cardWrap
                required property var modelData
                readonly property var px: root._rectPixels(String(modelData))
                visible: root.visibleIds.includes(String(modelData))
                readonly property bool selected:
                    root.editMode && root.selectedId === String(modelData)
                readonly property bool directlyManipulated:
                    selected && root._interaction !== null
                readonly property bool floating:
                    directlyManipulated && root._interaction?.kind === "move"
                readonly property bool animateGeometry:
                    root.editMode && !directlyManipulated

                x: px.x
                y: px.y
                width: px.width
                height: px.height
                z: floating ? 50 : (selected ? 30 : 1)

                Behavior on x {
                    enabled: Appearance.animationsEnabled
                        && cardWrap.animateGeometry
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve:
                            Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on y {
                    enabled: Appearance.animationsEnabled
                        && cardWrap.animateGeometry
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Appearance.animation.elementMoveFast.type
                        easing.bezierCurve:
                            Appearance.animation.elementMoveFast.bezierCurve
                    }
                }
                Behavior on width {
                    enabled: Appearance.animationsEnabled
                        && cardWrap.animateGeometry
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve:
                            Appearance.animation.elementResize.bezierCurve
                    }
                }
                Behavior on height {
                    enabled: Appearance.animationsEnabled
                        && cardWrap.animateGeometry
                    NumberAnimation {
                        duration: Appearance.animation.elementResize.duration
                        easing.type: Appearance.animation.elementResize.type
                        easing.bezierCurve:
                            Appearance.animation.elementResize.bezierCurve
                    }
                }

                scale: floating ? 1.012 : 1
                transformOrigin: Item.Center
                Behavior on scale {
                    enabled: Appearance.animationsEnabled
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                    }
                }

                // Paint one elevation layer per visible module, outside
                // cardViewport's content clip. Keep freeform geometry and hit
                // regions untouched; the outer Dashboard clips final pixels.
                StyledRectangularShadow {
                    target: cardWrap
                    z: -1
                    radius: Appearance.rounding.small
                    blur: Math.max(0, Math.min(16, Number(
                        Config.options?.appearance?.screenEdge?.shadow?.size ?? 15)))
                    spread: 0
                    offset: Qt.vector2d(0, 1)
                    color: Qt.alpha(Appearance.m3colors.m3shadow, Math.min(0.40,
                        Number(Config.options?.appearance?.screenEdge?.shadow?.opacity ?? 0.70) * 0.5))
                    visible: cardWrap.visible && Appearance.effectsEnabled
                        && !Appearance.gameModeMinimal
                        && (Config.options?.appearance?.screenEdge?.shadow?.enabled ?? true)
                }

                Item {
                    id: cardViewport
                    anchors.fill: parent
                    clip: true

                    Loader {
                        anchors.fill: parent
                        sourceComponent: root._widgetMap[String(cardWrap.modelData)] ?? null
                        active: cardWrap.visible || root.warmContent
                            && root.visibleIds.includes(String(cardWrap.modelData))
                        enabled: !root.editMode
                        opacity: root.editMode ? 0.92 : 1
                        Behavior on opacity {
                            enabled: Appearance.animationsEnabled
                            NumberAnimation {
                                duration: Appearance.animation.elementMoveFast.duration
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: root.editMode
                    color: selected
                        ? ColorUtils.applyAlpha(Appearance.colors.colPrimaryContainer, 0.10)
                        : ColorUtils.applyAlpha(Appearance.colors.colLayer1Hover, 0.06)
                    radius: Appearance.rounding.normal
                    border.width: selected ? 2 : 1
                    border.color: selected
                        ? Appearance.colors.colPrimary
                        : ColorUtils.applyAlpha(Appearance.colors.colOutlineVariant, 0.72)
                    z: 10
                }

                MouseArea {
                    id: moveArea
                    anchors.fill: parent
                    enabled: root.editMode
                    hoverEnabled: root.editMode
                    preventStealing: true
                    z: 20
                    cursorShape: root.editMode
                        ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                        : Qt.ArrowCursor
                    onPressed: mouse => {
                        const p = moveArea.mapToItem(canvas, mouse.x, mouse.y)
                        root.beginMove(String(cardWrap.modelData), p)
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return
                        const p = moveArea.mapToItem(canvas, mouse.x, mouse.y)
                        root.updateInteraction(p)
                    }
                    onReleased: root.finishInteraction(true)
                    onCanceled: root.finishInteraction(false)
                }

                RippleButton {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 8
                    visible: cardWrap.selected && root._interaction === null
                    z: 40
                    implicitWidth: 28
                    implicitHeight: 28
                    buttonRadius: Appearance.rounding.full
                    colBackground: Appearance.colors.colLayer2
                    onClicked: root.setWidgetVisible(String(cardWrap.modelData), false)
                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        text: "close"
                        iconSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                    StyledToolTip { text: Translation.tr("Hide from dashboard") }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    visible: cardWrap.selected && root._interaction !== null
                    z: 41
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer2
                    implicitWidth: sizeText.implicitWidth + 14
                    implicitHeight: 24
                    StyledText {
                        id: sizeText
                        anchors.centerIn: parent
                        text: Math.round(cardWrap.width) + " × " + Math.round(cardWrap.height)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        color: Appearance.colors.colOnLayer2
                    }
                }

                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "n"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "s"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "e"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "w"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "nw"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "ne"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "sw"; cardItem: cardWrap }
                ResizeHandle { widgetId: String(cardWrap.modelData); edge: "se"; cardItem: cardWrap }
            }
        }

    }

    }

    component ResizeHandle: Rectangle {
        id: handle
        required property string widgetId
        required property string edge
        required property Item cardItem

        readonly property bool horizontal:
            edge === "n" || edge === "s"
        readonly property bool vertical:
            edge === "e" || edge === "w"
        readonly property bool corner: edge.length === 2

        visible: root.editMode && root.selectedId === widgetId
        z: 60
        width: corner ? 8 : (horizontal ? 24 : 6)
        height: corner ? 8 : (vertical ? 24 : 6)
        radius: corner ? 2 : Appearance.rounding.full
        color: Appearance.colors.colPrimary
        border.width: 0
        border.color: "transparent"

        x: {
            if (edge.indexOf("w") >= 0)
                return -width / 2
            if (edge.indexOf("e") >= 0)
                return cardItem.width - width / 2
            return cardItem.width / 2 - width / 2
        }
        y: {
            if (edge.indexOf("n") >= 0)
                return -height / 2
            if (edge.indexOf("s") >= 0)
                return cardItem.height - height / 2
            return cardItem.height / 2 - height / 2
        }

        MouseArea {
            id: resizeMouse
            anchors.fill: parent
            anchors.margins: -4
            enabled: handle.visible
            preventStealing: true
            cursorShape: {
                if (!handle.visible)
                    return Qt.ArrowCursor
                if (handle.edge === "n" || handle.edge === "s")
                    return Qt.SizeVerCursor
                if (handle.edge === "e" || handle.edge === "w")
                    return Qt.SizeHorCursor
                if (handle.edge === "nw" || handle.edge === "se")
                    return Qt.SizeFDiagCursor
                return Qt.SizeBDiagCursor
            }
            onPressed: mouse => {
                const p = resizeMouse.mapToItem(canvas, mouse.x, mouse.y)
                root.beginResize(handle.widgetId, handle.edge, p)
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return
                const p = resizeMouse.mapToItem(canvas, mouse.x, mouse.y)
                root.updateInteraction(p)
            }
            onReleased: root.finishInteraction(true)
            onCanceled: root.finishInteraction(false)
        }
    }
}
