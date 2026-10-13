pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import "looks/AbyssGeometry.js" as Geometry
import "looks/AbyssLayout.js" as ModuleLayout
import "looks/AbyssPresentation.js" as Presentation

Scope {
    id: root
    readonly property var outputHosts:outputWindows.instances
    // First native output frame, not merely Loader completion. The critical
    // host uses this to perform its one-time cold input recovery *after* Wayland
    // has had a real Perimeter frame to configure.
    readonly property bool nativeInputFramesReady: {
        let presented = 0
        for (const output of (root.outputHosts ?? [])) {
            if (!output?.presented) continue
            presented++
            if (!output.nativeFieldReady) return false
        }
        return presented > 0
    }
    property string largeTargetOutput: GlobalStates.resolveOutputName("",[])
    // Match the mature ScreenCorners keyboard lease: hover previews may exist on
    // several outputs, but only one Quick Notes editor may own keyboard focus.
    property string quickNotesEditorOutput: ""
    function setQuickNotesEditorOutput(outputName, focused): void {
        const name = String(outputName ?? "")
        if (focused) {
            if (name && (!root.quickNotesEditorOutput
                    || root.quickNotesEditorOutput === name))
                root.quickNotesEditorOutput = name
            return
        }
        if (root.quickNotesEditorOutput === name)
            root.quickNotesEditorOutput = ""
    }
    readonly property string utilityKind: GlobalStates.sessionOpen ? "session" : GlobalStates.cheatsheetOpen ? "cheatsheet" : ShellUpdates.overlayOpen ? "update" : ""
    readonly property string utilityIdentifier: utilityKind === "session" ? "abyssSessionScreen" : utilityKind === "cheatsheet" ? "iiCheatsheet" : "iiShellUpdate"
    function closeUtility(): void {
        if (utilityKind === "session") GlobalStates.sessionOpen = false
        else if (utilityKind === "cheatsheet") GlobalStates.cheatsheetOpen = false
        else ShellUpdates.closeOverlay()
    }
    onUtilityKindChanged: if (utilityKind) largeTargetOutput = GlobalStates.resolveOutputName("",[])
    property var revealedBars: ({})
    function setBarRevealed(name, value): void {
        const next = Object.assign({},revealedBars)
        if (value) next[name] = true
        else delete next[name]
        revealedBars = next
    }
    readonly property string barEdge: Geometry.edge(Config.options?.bar?.vertical ?? false, Config.options?.bar?.bottom ?? false)
    function barOnOutput(name): bool {
        return (Config.options?.enabledPanels ?? []).includes("abyssBar")
            && GlobalStates.barOpen
            && (!(Config.options?.bar?.autoHide?.enable ?? false)
                || root.revealedBars[name]
                || GlobalStates.barPopupHoverHeld(name)
                || (GlobalStates.superDown && (Config.options?.bar?.autoHide?.showWhenPressingSuper ?? true))
                || (GlobalStates.abyssPopupKind.length > 0
                    && GlobalStates.resolveOutputName(GlobalStates.abyssPopupTargetOutput,[]) === name))
            && Geometry.targets(name, Config.options?.bar?.screenList ?? [], Quickshell.screens.map(s => s.name))
    }
    function outputInsets(name, reservation = false) {
        const options=Object.assign({},ModuleLayout.optionsForOutput(Config.options?.abyss?.modules,name),{edgeThickness:AbyssStyle.perimeterThickness})
        const result = ModuleLayout.edgeInsetsForModules([],options,Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
        if (!root.barOnOutput(name) || (reservation && (Config.options?.bar?.autoHide?.enable ?? false))) return result
        const screen = Quickshell.screens.find(s => s.name === name)
        const vertical = !Geometry.horizontal(root.barEdge)
        const zones = Geometry.barZones((vertical ? Config.options?.bar?.verticalLayout : Config.options?.bar?.layout) ?? {},vertical,Config.options?.bar?.modules ?? {})
        const placements = ModuleLayout.resolve(Config.options?.abyss?.modules,name,ModuleLayout.seed(zones,root.barEdge,screen?.width ?? 1920,screen?.height ?? 1080))
        return ModuleLayout.edgeInsetsForModules(placements,options,Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,reservation)
    }
    Connections {
        target: Quickshell
        function onScreensChanged(): void {
            const owner = root.quickNotesEditorOutput
            if (!owner) return
            if (!Quickshell.screens.some(screen =>
                    String(screen?.name ?? "") === owner))
                root.quickNotesEditorOutput = ""
        }
    }
    Connections {
        target: GlobalStates
        function onDashboardOpenChanged(): void { if (GlobalStates.dashboardOpen) root.largeTargetOutput = GlobalStates.resolveOutputName("",[]) }
        function onControlPanelOpenChanged(): void { if (GlobalStates.controlPanelOpen) root.largeTargetOutput = GlobalStates.resolveOutputName("",[]) }
        function onOverviewOpenChanged(): void { if (GlobalStates.overviewOpen) GlobalStates.clipboardOpen = false }
        function onClipboardOpenChanged(): void {
            if (GlobalStates.clipboardOpen) {
                GlobalStates.abyssClipboardTargetOutput = GlobalStates.resolveOutputName("",[])
                GlobalStates.overviewOpen = false
            }
        }
    }
    AbyssOsdController {}
    // Diagnostic only: no input mutations, popup leases, or timers. The
    // single read-only IPC snapshot is deliberately tied to the production
    // PanelWindow, not an isolated hover fixture.
    function hoverProbeSnapshot(): string {
        const outputs = []
        for (const host of (root.outputHosts ?? [])) {
            try {
                outputs.push(host?.hoverProbeOutput ? host.hoverProbeOutput()
                    : { unavailable: true })
            } catch (error) {
                outputs.push({ probeError: String(error) })
            }
        }
        return JSON.stringify({
            timestamp: Date.now(),
            family: String(Config.options?.panelFamily ?? ""),
            shellEntryReady: GlobalStates.shellEntryReady,
            deferredPanelsReady: GlobalStates.deferredPanelsReady,
            compositorNiri: CompositorService.isNiri,
            outputCount: outputs.length,
            outputs: outputs
        })
    }
    // Read-only, on-demand diagnostic for Dashboard Escape ownership.
    // It never changes focus, edits data, or installs a background timer.
    IpcHandler {
        target: "dashboardEscProbe"
        function snapshot(): string {
            return JSON.stringify({
                timestamp: Date.now(),
                family: String(Config.options?.panelFamily ?? ""),
                outputs: (root.outputHosts ?? []).map(host =>
                    host?.dashboardEscapeProbe ? host.dashboardEscapeProbe()
                        : {unavailable: true})
            })
        }
    }
    IpcHandler {
        target: "abyssHoverProbe"
        function snapshot(): string { return root.hoverProbeSnapshot() }
        // Opt-in bounded present-interval capture. No sampling timer or
        // telemetry workload exists until explicitly requested over IPC.
        function startFrames(): string {
            return JSON.stringify((root.outputHosts ?? []).map(host =>
                host?.startFrameProbe ? host.startFrameProbe()
                    : {unavailable:true}))
        }
        function stopFrames(): string {
            return JSON.stringify((root.outputHosts ?? []).map(host =>
                host?.stopFrameProbe ? host.stopFrameProbe()
                    : {unavailable:true}))
        }
        // One-shot diagnostic experiment: request a compositor input-mask
        // rebuild without remounting Abyss or changing any configuration.
        // Do not use as an automatic startup workaround: first determine
        // whether this alone restores native pointer delivery.
        function swapMask(): string {
            const results = []
            for (const host of (root.outputHosts ?? [])) {
                try {
                    results.push(host?.hoverProbeSwapMask
                        ? host.hoverProbeSwapMask()
                        : { unavailable: true })
                } catch (e) { results.push({ error: String(e) }) }
            }
            return JSON.stringify({ diagnostic: "identity-swap", outputs: results })
        }
        function remapWindow(): string {
            const results = []
            for (const host of (root.outputHosts ?? [])) {
                try {
                    results.push(host?.hoverProbeRemapWindow
                        ? host.hoverProbeRemapWindow()
                        : { unavailable: true })
                } catch (e) { results.push({ error: String(e) }) }
            }
            return JSON.stringify({ diagnostic: "one-shot-remap", outputs: results })
        }
        function refreshMask(): string {
            const results = []
            for (const host of (root.outputHosts ?? [])) {
                try {
                    results.push(host?.hoverProbeRefreshMask
                        ? host.hoverProbeRefreshMask()
                        : { unavailable: true })
                } catch (error) {
                    results.push({ error: String(error) })
                }
            }
            return JSON.stringify({ timestamp: Date.now(),
                experimentalOneShot: true, outputs: results })
        }
    }
    Component.onCompleted: {
        Notifications.ensureInitialized()
    }
    Variants {
        id: outputWindows
        model: Quickshell.screens
        PanelWindow {
            id: window
            objectName:"abyssOutputHost_"+modelData.name
            required property var modelData
            readonly property string outputName: modelData?.name ?? ""
            readonly property bool nativeFieldReady: field.ready
            property bool _probeMaskProxy: false
            property bool _probeUnmapped: false
            // Quiescent by default: these fields are only touched by the
            // abyssHoverProbe.startFrames/stopFrames diagnostic IPC.
            property bool _frameProbeEnabled: false
            // Date.now() is epoch milliseconds (~1.8e12), far beyond QML
            // int's 32-bit range. A wrapped previous timestamp produces
            // fictitious trillion-millisecond frame intervals.
            property real _frameProbePreviousMs: 0
            property var _frameProbeIntervals: []
            // Bounded, opt-in traces of slow intervals. The per-frame hot path
            // reads existing clock/array state only; surface-state snapshots
            // are taken ONLY if an interval actually exceeds 33.3ms.
            property var _frameProbeSlowEvents: []
            // Cheap, opt-in presence/motion counters: if every Panel is zero
            // through the entire six-second window, slow frames cannot be
            // attributed to an observed Panel animation. Never run at idle.
            property var _frameProbePreviousPanelProgress: null
            property int _frameProbePanelNonzeroFrames: 0
            property int _frameProbePanelChangedFrames: 0
            property int _frameProbePopupOpenFrames: 0
            // Timer and frameSwapped use the same Qt event loop. Large timer
            // gaps overlapping large swap gaps suggest scheduling stalls;
            // normal timer cadence with sparse swaps suggests no render/present.
            // They are correlations, not a profiler or compositor timestamps.
            property real _frameProbeHeartbeatPrevMs: 0
            property int _frameProbeHeartbeatCount: 0
            property int _frameProbeHeartbeatOver100Ms: 0
            property real _frameProbeHeartbeatMaxMs: 0
            property var _frameProbeHeartbeatLateEvents: []
            // At most 160 ticks (~8s at 50ms). Retain the FULL opt-in
            // heartbeat chronology so a sparse frame-swapped gap can be
            // compared to actual event-loop deliveries within that gap.
            property var _frameProbeHeartbeatHistory: []
            property real _frameProbeBarPrevProgress: -1
            property int _frameProbeBarChangedFrames: 0
            function recordProbeHeartbeat(now): void {
                const previous=window._frameProbeHeartbeatPrevMs
                const intervalMs=previous > 0 ? Math.max(0,now-previous) : null
                if (window._frameProbeHeartbeatHistory.length < 160)
                    window._frameProbeHeartbeatHistory.push({
                        timestampMs:now,intervalMs:intervalMs})
                if (previous > 0) {
                    window._frameProbeHeartbeatCount++
                    window._frameProbeHeartbeatMaxMs=Math.max(
                        window._frameProbeHeartbeatMaxMs,intervalMs)
                    if (intervalMs > 100) {
                        window._frameProbeHeartbeatOver100Ms++
                        if (window._frameProbeHeartbeatLateEvents.length < 30)
                            window._frameProbeHeartbeatLateEvents.push({
                                timestampMs:now,intervalMs:intervalMs})
                    }
                }
                window._frameProbeHeartbeatPrevMs=now
            }
            function startFrameProbe(): var {
                window._frameProbeIntervals = []
                window._frameProbeSlowEvents = []
                window._frameProbePreviousPanelProgress = null
                window._frameProbePanelNonzeroFrames = 0
                window._frameProbePanelChangedFrames = 0
                window._frameProbePopupOpenFrames = 0
                window._frameProbeHeartbeatPrevMs = 0
                window._frameProbeHeartbeatCount = 0
                window._frameProbeHeartbeatOver100Ms = 0
                window._frameProbeHeartbeatMaxMs = 0
                window._frameProbeHeartbeatLateEvents = []
                window._frameProbeHeartbeatHistory = []
                window._frameProbeBarPrevProgress = -1
                window._frameProbeBarChangedFrames = 0
                window._frameProbePreviousMs = 0
                window._frameProbeEnabled = true
                return {output:window.outputName,started:true,maxIntervals:600}
            }
            function stopFrameProbe(): var {
                window._frameProbeEnabled = false
                const intervals=window._frameProbeIntervals.slice()
                intervals.sort((a,b)=>a-b)
                const n=intervals.length
                const percentile=p=>n ? intervals[Math.min(n-1,
                    Math.max(0,Math.ceil(n*p)-1))] : null
                const sum=intervals.reduce((a,b)=>a+b,0)
                return {
                    output:window.outputName,
                    sample:"QQuickWindow frameSwapped wall-clock intervals (ms)",
                    count:n,exhausted:n>=600,
                    min:n?intervals[0]:null,
                    p50:percentile(.5),p95:percentile(.95),
                    p99:percentile(.99),max:n?intervals[n-1]:null,
                    mean:n?sum/n:null,
                    over16ms:intervals.filter(ms=>ms>16.7).length,
                    over33ms:intervals.filter(ms=>ms>33.3).length,
                    idleGapsOver100ms:intervals.filter(ms=>ms>100).length,
                    slowEvents:window._frameProbeSlowEvents.slice(),
                    panelNonzeroFrames:window._frameProbePanelNonzeroFrames,
                    panelProgressChangedFrames:window._frameProbePanelChangedFrames,
                    popupOpenFrames:window._frameProbePopupOpenFrames,
                    barProgressChangedFrames:window._frameProbeBarChangedFrames,
                    heartbeatSampleCount:window._frameProbeHeartbeatCount,
                    heartbeatOver100Ms:window._frameProbeHeartbeatOver100Ms,
                    heartbeatMaxIntervalMs:window._frameProbeHeartbeatMaxMs,
                    heartbeatLateEvents:window._frameProbeHeartbeatLateEvents.slice(),
                    heartbeatHistory:window._frameProbeHeartbeatHistory.slice(),
                    heartbeatHistoryExhausted:window._frameProbeHeartbeatHistory.length>=160,
                    caveat:"swap wall-clock gaps include idle gaps; 50ms Qt timer lateness is only event-loop correlation, not GPU/compositor proof"
                }
            }
            Timer {
                id: frameHeartbeat
                interval: 50
                repeat: true
                running: window._frameProbeEnabled
                onTriggered: window.recordProbeHeartbeat(Date.now())
            }
            Connections {
                target: field.Window.window
                enabled: window._frameProbeEnabled
                function onFrameSwapped(): void {
                    const now=Date.now()
                    // Five reused numeric state reads per sampled frame;
                    // this instrumentation is off unless startFrames ran.
                    const panels=[
                        Number(leftPanel.progress ?? 0),
                        Number(rightPanel.progress ?? 0),
                        Number(dashboardBody.progress ?? 0),
                        Number(controls.progress ?? 0),
                        Number(settings.progress ?? 0)
                    ]
                    if (panels.some(value=>value>0.001))
                        window._frameProbePanelNonzeroFrames++
                    const previous=window._frameProbePreviousPanelProgress
                    if (previous && panels.some((value,i)=>Math.abs(value-previous[i])>0.001))
                        window._frameProbePanelChangedFrames++
                    window._frameProbePreviousPanelProgress=panels
                    if (liquid.popupsOpen) window._frameProbePopupOpenFrames++
                    const currentBarProgress=Number(window.barProgress ?? 0)
                    if (window._frameProbeBarPrevProgress >= 0
                            && Math.abs(currentBarProgress
                                - window._frameProbeBarPrevProgress) > 0.001)
                        window._frameProbeBarChangedFrames++
                    window._frameProbeBarPrevProgress=currentBarProgress
                    if (window._frameProbePreviousMs > 0
                            && window._frameProbeIntervals.length < 600) {
                        const intervalMs = Math.max(0,now-window._frameProbePreviousMs)
                        window._frameProbeIntervals.push(intervalMs)
                        if (intervalMs > 33.3
                                && window._frameProbeSlowEvents.length < 40) {
                            // Occurs only for slow intervals, not every frame.
                            // Correlation hints, not compositor present proof.
                            window._frameProbeSlowEvents.push({
                                timestampMs:now, intervalMs:intervalMs,
                                barVisible:Boolean(bar.visible),
                                barProgress:Number(window.barProgress ?? 0),
                                liquidPopupsOpen:Boolean(liquid.popupsOpen),
                                popupMotion:liquid.popupSlots.filter(slot=>slot?.popup)
                                    .map(slot=>({
                                        kind:String(slot.popup?._liquidAnchor?.kind ?? ""),
                                        revealProgress:Number(slot.popup?.revealProgress ?? 0),
                                        requestedVisible:Boolean(slot.popup?.requestedVisible)
                                    })),
                                leftPanelProgress:leftPanel.progress,
                                rightPanelProgress:rightPanel.progress,
                                dashboardProgress:dashboardBody.progress,
                                controlPanelProgress:controls.progress,
                                settingsProgress:settings.progress
                            })
                        }
                    }
                    window._frameProbePreviousMs=now
                    if (window._frameProbeIntervals.length >= 600)
                        window._frameProbeEnabled=false
                }
            }
            Timer {
                id: probeRemapTimer
                interval: 260
                repeat: false
                onTriggered: window._probeUnmapped = false
            }
            function _probeNormalIdle(): bool {
                return window.presented && !window.editorOpen && field.ready
                    && !liquid.activeDialog && !utility.open
                    && !window.overviewDragging
            }
            function hoverProbeSwapMask(): var {
                if (!window._probeNormalIdle())
                    return { output: window.outputName, skipped: true,
                        reason: "not normal idle" }
                window._probeMaskProxy = !window._probeMaskProxy
                return { output: window.outputName, skipped: false,
                    maskProxy: window._probeMaskProxy }
            }
            function hoverProbeRemapWindow(): var {
                if (!window._probeNormalIdle() || window._probeUnmapped)
                    return { output: window.outputName, skipped: true,
                        reason: "not safe to remap" }
                window._probeUnmapped = true
                probeRemapTimer.restart()
                return { output: window.outputName, skipped: false,
                    remapDurationMs: 260 }
            }
            // Diagnostic only: force a one-shot Region.changed notification
            // while preserving the same mapped PanelWindow, layer and family.
            // This is not an automatically scheduled fix.
            function hoverProbeRefreshMask(): var {
                if (!window.presented || window.editorOpen || !field.ready
                        || liquid.activeDialog || utility.open
                        || window.overviewDragging)
                    return { output: window.outputName,
                        skipped: true, reason: "mask mode not normal idle" }
                let count = 0
                for (const region of (bar.inputRegions ?? [])) {
                    if (region) {
                        region.changed()
                        count++
                    }
                }
                nativeInputMask.changed()
                return { output: window.outputName, skipped: false,
                    regionSignals: count, barVisible: bar.visible,
                    fieldReady: field.ready,
                    popupOpen: liquid.popupsOpen }
            }
            // This function is evaluated only by abyssHoverProbe.snapshot.
            // Read-only hit test of the current Perimeter pointer coordinates.
            // Source anchor QQuickWindow scene coordinates are NOT passed here.
            // Only valid when the existing hosted HoverHandler has a point;
            // null after leave is intentionally not treated as (0,0).
            function hoverProbeGeometry(host, scenePoint): var {
                if (!host) return null
                const bounds=host.inputBounds
                const raw=host.rawPresentationRecord?.surface ?? null
                const joined=host.record?.surface ?? null
                const strips=host.connectionRects ?? []
                const rect=r=>r ? {x:r.x,y:r.y,w:r.width,h:r.height} : null
                return {
                    edge:String(host.edge ?? ""),
                    joinedEdge:String(host.joinedEdge ?? ""),
                    outputWidth:window.width,
                    outputHeight:window.height,
                    connectionInsets:host.connectionInsets ?? null,
                    rawSurface:rect(raw),
                    joinedSurface:rect(joined),
                    pointHit:scenePoint ? {
                        inInputBounds:Geometry.rectContains(bounds,
                            scenePoint.x,scenePoint.y),
                        inShoulderStrip:strips.some(r=>Geometry.rectContains(r,
                            scenePoint.x,scenePoint.y)),
                        inSourceRegion:(host.controller?.sourceInputRegions ?? [])
                            .some(r=>Geometry.rectContains(r,scenePoint.x,scenePoint.y)),
                        inRawSurfaceBounds:Geometry.rectContains(raw,
                            scenePoint.x,scenePoint.y)
                    } : null
                }
            }
            // No perpetual logging, pointer handlers or geometry changes.
            function hoverProbeOutput(): var {
                const modules = []
                for (const id of (bar.moduleIds ?? [])) {
                    const item = bar.itemForId(id)
                    if (!item) {
                        modules.push({ id: String(id), constructed: false })
                        continue
                    }
                    const region = item.inputRegion
                    const popup = item.companionPopup
                    modules.push({
                        id: String(id),
                        kind: String(item.kind ?? ""),
                        constructed: true,
                        visible: Boolean(item.visible),
                        enabled: Boolean(item.enabled),
                        hovered: Boolean(item.hovered),
                        featureHovered: item.feature?.hovered ?? null,
                        featureContainsMouse: item.feature?.containsMouse ?? null,
                        rect: { x: item.x, y: item.y, w: item.width, h: item.height },
                        input: region ? { x: region.x, y: region.y,
                            w: region.width, h: region.height } : null,
                        popup: popup ? {
                            anchorReady: Boolean(popup._anchorReady),
                            liquidOwner: Boolean(popup._liquidAnchor),
                            liquidControllerMatches: popup._liquidController === liquid,
                            windowBound: Boolean(popup._anchorWindow),
                            screenBound: Boolean(popup._anchorScreen),
                            moduleHoverActive: Boolean(popup.moduleHoverActive),
                            anchorHover: Boolean(popup._anchorHover?.hovered),
                            requestedVisible: Boolean(popup.requestedVisible),
                            presentationActive: Boolean(popup.presentationActive),
                            hosted: popup._hostedController === liquid
                        } : null
                    })
                }
                return {
                    output: window.outputName,
                    windowVisible: Boolean(window.visible),
                    presented: Boolean(window.presented),
                    editorOpen: Boolean(window.editorOpen),
                    fullscreenCovered: Boolean(window.fullscreenCovered),
                    fieldReady: Boolean(field.ready),
                    framePresented: Boolean(field.framePresented),
                    barVisible: Boolean(bar.visible),
                    barEnabled: Boolean(bar.enabled),
                    barOnOutput: root.barOnOutput(window.outputName),
                    barEditing: Boolean(bar.editing),
                    barHover: Boolean(barHover.hovered),
                    probeMaskProxy: window._probeMaskProxy,
                    probeUnmapped: window._probeUnmapped,
                    barInputRegionCount: bar.inputRegions.length,
                    editorRegionCount: editor.regions.length,
                    liquidPresented: Boolean(liquid.presented),
                    liquidPopupsOpen: Boolean(liquid.popupsOpen),
                    // Read only on explicit IPC snapshot: distinguish lost
                    // source hover, lost body hover, a visible compositor
                    // mask, and a timed semantic retract. Never log each
                    // frame or force a repaint while diagnosing.
                    barPopupHoverLease: GlobalStates.barPopupHoverHeld(window.outputName),
                    popupSlots: liquid.popupSlots.map((slot,index) => {
                        if (!slot) return null
                        const p=slot.popup
                        const host=liquid._popupHost(index)
                        const bounds=host?.inputBounds ?? null
                        const content=host?.record?.content ?? null
                        return {
                            kind:String(p?._liquidAnchor?.kind ?? ""),
                            order:slot.order,
                            active:Boolean(p?.presentationActive),
                            requestedVisible:Boolean(p?.requestedVisible),
                            semanticHold:Boolean(p?._liquidSemanticHold),
                            lingerVisible:Boolean(p?._lingerVisible),
                            // Read-only ownership inputs help distinguish
                            // actual hover loss from configured grace holds.
                            humanVisibleRequest:Boolean(p?.humanVisibleRequest),
                            rawVisibleRequest:Boolean(p?._rawVisibleRequest),
                            hoverActivates:Boolean(p?.hoverActivates),
                            notificationHover: String(p?._liquidAnchor?.kind ?? "") === "notificationCenter"
                                ? {
                                    anchorHovered:Boolean(p?._anchorHovered),
                                    entryBridgeHeld:Boolean(p?.entryBridgeHeld),
                                    exitGraceHeld:Boolean(p?.exitGraceHeld),
                                    hoverLeaseRequested:Boolean(p?.hoverLeaseRequested),
                                    hoverSessionArmed:Boolean(p?.hoverSessionArmed),
                                    hoverAllowed:Boolean(p?.hoverAllowed),
                                    explicitForThisOutput:Boolean(p?.explicitForThisOutput)
                                  } : null,
                            moduleHover:Boolean(p?.moduleHoverActive),
                            anchorHover:Boolean(p?._anchorHover?.hovered),
                            // These points are each local to THEIR OWN
                            // QQuickWindow. Never compare corner-source
                            // coordinates directly to Perimeter coordinates.
                            anchorScenePoint:p?._anchorHover?.hoverProbeScenePoint ?? null,
                            bodyHover:Boolean(p?._bodyHovered),
                            contentHover:Boolean(p?._contentHovered),
                            contentScenePoint:host?.hoverProbeContentScenePoint ?? null,
                            hoverGeometry:window.hoverProbeGeometry(host,
                                host?.hoverProbeContentScenePoint ?? null),
                            hosted:p?._hostedController === liquid,
                            bodyAcceptsInput:Boolean(host?.acceptsInput),
                            bodyReady:Boolean(host?.ready),
                            hoverParentEnabled:Boolean(host?.hoverParent?.enabled),
                            nativeRegionRegistered:Boolean(host?.nativeInputRegion
                                && liquid.nativeInputRegions.includes(host.nativeInputRegion)),
                            stripCount:host?.connectionRects?.length ?? 0,
                            bounds:bounds ? {x:bounds.x,y:bounds.y,
                                w:bounds.width,h:bounds.height} : null,
                            content:content ? {x:content.x,y:content.y,
                                w:content.width,h:content.height} : null
                        }
                    }),
                    // NOTIF-I01/I02: sampled only on explicit opt-in IPC.
                    // No notification text, filename, image, process command,
                    // screenshot pixels or other user contents are exposed.
                    notificationPresentation:{
                        toastCount:Notifications.popupList.length,
                        inhibited:Boolean(Notifications.popupInhibited),
                        recording:Boolean(RecorderStatus.isRecording),
                        centerOpen:Boolean(GlobalStates.notificationCenterOpen),
                        toastOpen:Boolean(notification.open),
                        toastResident:Boolean(notification.visualResident),
                        toastRevealProgress:Number(notification.progress ?? 0),
                        toastEdge:String(notification.edge ?? ""),
                        toastSpan:Number(notification.span ?? 0),
                        toastDepth:Number(notification.depth ?? 0),
                        toastPaintDepth:Number(notification.record?.depth ?? 0),
                        toastTargetDepth:Number(notification.targetRecord?.depth ?? 0),
                        toastAlong:Number(notification.along ?? 0),
                        toastDesiredHeight:Number(notification.contentItem.item?.desiredHeight ?? 0),
                        toastMeasuredHeight:Number(notification.contentItem.item?.measuredPopupHeight ?? 0),
                        toastLayoutReady:Boolean(notification.contentItem.item?.popupLayoutReady)
                    },
                    genericPopup:{
                        activeKind:String(popup.activeKind ?? ""),
                        desiredKind:String(popup.desiredKind ?? ""),
                        resident:Boolean(popup.resident),
                        requestedOpen:Boolean(popup.requestedOpen),
                        progress:Number(popup.progress ?? 0),
                        inputBounds:{x:popup.inputBounds.x,y:popup.inputBounds.y,
                            w:popup.inputBounds.width,h:popup.inputBounds.height},
                        triggerHover:Boolean(popup.contentItem.item?.triggerHovered),
                        focusHeld:Boolean(popup.contentItem.item?.editorFocusHeld)
                    },
                    modules: modules
                }
            }
            function presentation(kind) { return Presentation.resolve(Config.options?.abyss?.positions,kind,outputName) }
            function positionEdge(kind,fallback) { return Presentation.edge(presentation(kind),fallback) }
            function positionAlong(kind,edge,span,fallback) { return Presentation.along(presentation(kind),edge,span,width,height,fallback,nativeInsets) }
            function bodyInsets(edge,along,span) { return ModuleLayout.clearanceInsets(nativeInsets,bar.visible ? bar.deformations : [],edge,along,span) }
            readonly property bool fullscreenCovered: GameMode.hasFullscreenOnOutput(outputName)
            readonly property bool presented: !GlobalStates.screenLocked
                && (!fullscreenCovered || (Config.options?.abyss?.perimeter?.visibleInFullscreen ?? false))
            // Fullscreen feedback owns only this transient body, never the
            // suppressed Screen Edges, popup leases or keyboard focus.
            readonly property bool physicalOsdKind: osd.presentationKind === "volume" || osd.presentationKind === "brightness"
            readonly property bool physicalOsdRequested: !presented && fullscreenCovered && physicalOsdKind
                && !GlobalStates.screenLocked
                && (Config.options?.enabledPanels ?? []).includes("abyssOnScreenDisplay")
                && (GlobalStates.osdVolumeOpen || GlobalStates.osdBrightnessOpen)
                && Geometry.targets(outputName,Config.options?.osd?.screenList ?? [],Quickshell.screens.map(s => s.name))
            readonly property bool physicalOsdResident: !presented && fullscreenCovered && physicalOsdKind
                && !GlobalStates.screenLocked && (physicalOsdRequested || osd.visualResident)
            readonly property var physicalInsets: ({left:0,top:0,right:0,bottom:0})
            readonly property var paintInsets: physicalOsdResident ? physicalInsets : nativeInsets
            readonly property bool editorOpen: GlobalStates.abyssEditing && GlobalStates.abyssEditorTargetOutput === outputName
            onPresentedChanged: if (!presented && editorOpen) GlobalStates.abyssEditing = false
            screen: modelData
            // Keep the Top surface mapped across fullscreen, preserving stack order.
            visible: Config.ready && !GlobalStates.screenLocked && !window._probeUnmapped
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "hadalis:abyss-perimeter"
            // Niri needs a stable overlay for hit-tested Screen Edge modules
            // when the output is presented, even before the first hover popup.
            // Hidden/covered outputs retain the old Top fallback. Otherwise liquid.popupsOpen
            // switches Top -> Overlay at pointer entry, which can invalidate
            // hover just as the popup begins opening. Keep native-dialog/
            // Polkit overrides and the existing shaped input mask.
            WlrLayershell.layer: GlobalStates.settingsNativeDialogOpen ? WlrLayer.Bottom : PolkitService.active ? WlrLayer.Top : (window.physicalOsdResident || (CompositorService.isNiri && window.presented) || window.editorOpen || wallpaperBody.open || (keyboardBody.open && (Config.options?.osk?.keepOnTop ?? false)) || utility.open || liquid.popupsOpen || toastBody.open || dialogBody.open || companionExtension.editing || settings.open || dashboardBody.open || controls.open || (window.fullscreenCovered && window.presented)) ? WlrLayer.Overlay : WlrLayer.Top
            WlrLayershell.keyboardFocus: !window.presented || !field.ready || GlobalStates.regionSelectorOpen || GlobalStates.settingsNativeDialogOpen || PolkitService.active || window.overviewDragging || companionExtension.curiosityOwned
                ? WlrKeyboardFocus.None
                : (companionExtension.editing || window.editorOpen || (utility.presented && utility.ready) || liquid.popupExclusiveFocus || (popup.presented && (popup.contentItem.item?.keyboardFocus ?? false)) || (dialogBody.presented && dialogBody.ready) || (aux.presented && aux.ready) || (wallpaperBody.presented && wallpaperBody.ready) || (clipboardBody.presented && clipboardBody.ready) || (settings.presented && settings.ready) || (dashboardBody.presented && dashboardBody.ready) || (controls.presented && controls.ready)) ? WlrKeyboardFocus.Exclusive
                : (companionExtension.editing || liquid.popupOnDemandFocus || (leftPanel.presented && leftPanel.ready) || (rightPanel.presented && rightPanel.ready) || (popup.presented && popup.ready) || (notification.presented && notification.ready && notification.contentKind === "center"))
                    ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            anchors { top: true; bottom: true; left: true; right: true }
            Item { id: emptyInput; width: 0; height: 0 }
            readonly property bool overviewDragging: aux.open && (aux.contentItem.item?.applicationDragActive ?? false)
            readonly property Region dragPassThrough: Region {}
            mask: window.overviewDragging ? dragPassThrough : liquid.activeDialog ? dialogInputMask : utility.open ? utilityInputMask : (window._probeMaskProxy ? probeProxyInputMask : nativeInputMask)
            // Equally shaped alternative Region identity. An explicit IPC
            // toggle tests re-binding QWindow.mask instead of only sending
            // Region.changed. No full-output/unmasked pointer interception.
            readonly property Region probeProxyInputMask: Region {
                regions: [nativeInputMask]
            }
            readonly property Region dialogInputMask: Region {
                x: dialogBody.inputBounds.x; y: dialogBody.inputBounds.y
                width: window.presented && field.ready ? dialogBody.inputBounds.width : 0
                height: dialogBody.inputBounds.height
            }
            readonly property Region utilityInputMask: Region {
                Region {
                    x: utility.inputBounds.x; y: utility.inputBounds.y
                    width: window.presented && field.ready ? utility.inputBounds.width : 0
                    height: utility.inputBounds.height
                }
                Region { regions: companionExtension.inputRegions }
            }
            readonly property Region nativeInputMask: Region {
                Region { regions: window.presented && field.ready && bar.visible ? bar.inputRegions : [] }
                Region { regions: companionExtension.inputRegions }
                Region { regions: window.presented && field.ready && editor.visible ? editor.regions : [] }
                Region { item: window.presented && revealTrigger.visible ? revealTrigger : emptyInput }
                Region { item: window.presented && dockTrigger.visible ? dockTrigger : emptyInput }
                Region { x: widgetEditorBody.inputBounds.x; y: widgetEditorBody.inputBounds.y; width: window.presented && field.ready ? widgetEditorBody.inputBounds.width : 0; height: widgetEditorBody.inputBounds.height }
                Region { x: leftReveal.x; y: leftReveal.y; width: leftReveal.available ? leftReveal.width : 0; height: leftReveal.height }
                Region { x: rightReveal.x; y: rightReveal.y; width: rightReveal.available ? rightReveal.width : 0; height: rightReveal.height }
                Region { x: leftPanel.inputBounds.x; y: leftPanel.inputBounds.y; width: window.presented && field.ready ? leftPanel.inputBounds.width : 0; height: leftPanel.inputBounds.height }
                Region { x: rightPanel.inputBounds.x; y: rightPanel.inputBounds.y; width: window.presented && field.ready ? rightPanel.inputBounds.width : 0; height: rightPanel.inputBounds.height }
                Region { regions: window.presented && field.ready ? liquid.nativeInputRegions : [] }
                Region { x: dock.inputBounds.x; y: dock.inputBounds.y; width: window.presented && field.ready ? dock.inputBounds.width : 0; height: dock.inputBounds.height }
                Region { item:corners.notesAvailable ? corners.notesAnchor : emptyInput }
                Region { item:corners.centerAvailable ? corners.centerAnchor : emptyInput }
                Region { regions:corners.sidebarRegions }
                Region { x: notification.inputBounds.x; y: notification.inputBounds.y; width: window.presented && field.ready ? notification.inputBounds.width : 0; height: notification.inputBounds.height }
                Region { x: toastBody.inputBounds.x; y: toastBody.inputBounds.y; width: window.presented && field.ready ? toastBody.inputBounds.width : 0; height: toastBody.inputBounds.height }
                Region { x: osd.inputBounds.x; y: osd.inputBounds.y; width: (window.presented || window.physicalOsdResident) && field.ready ? osd.inputBounds.width : 0; height: osd.inputBounds.height }
                Region { x: dashboardBody.inputBounds.x; y: dashboardBody.inputBounds.y; width: window.presented && field.ready ? dashboardBody.inputBounds.width : 0; height: dashboardBody.inputBounds.height }
                Region { x: controls.inputBounds.x; y: controls.inputBounds.y; width: window.presented && field.ready ? controls.inputBounds.width : 0; height: controls.inputBounds.height }
                Region { x: settings.inputBounds.x; y: settings.inputBounds.y; width: window.presented && field.ready && !GlobalStates.settingsNativeDialogOpen ? settings.inputBounds.width : 0; height: settings.inputBounds.height }
                Region { x: aux.inputBounds.x; y: aux.inputBounds.y; width: window.presented && field.ready ? aux.inputBounds.width : 0; height: aux.inputBounds.height }
                Region {x:keyboardBody.inputBounds.x;y:keyboardBody.inputBounds.y;width:window.presented && field.ready ? keyboardBody.inputBounds.width : 0;height:keyboardBody.inputBounds.height}
                Region { x:wallpaperBody.inputBounds.x;y:wallpaperBody.inputBounds.y;width:window.presented && field.ready ? wallpaperBody.inputBounds.width : 0;height:wallpaperBody.inputBounds.height }
                Region { x: clipboardBody.inputBounds.x; y: clipboardBody.inputBounds.y; width: window.presented && field.ready ? clipboardBody.inputBounds.width : 0; height: clipboardBody.inputBounds.height }
            }
            function closeGenericPopup(expectedKind = ""): void {
                const expected = String(expectedKind ?? "")

                // Hover-owned generic surfaces (Wi-Fi/Bluetooth/Utilities/etc.)
                // must never dismiss a newer mature StyledPopup. A stale idle
                // timer may only close the generic popup it originally owned.
                const current = String(GlobalStates.abyssPopupKind ?? "")
                if (expected && current !== expected)
                    return
                if (current === "dockAppMenu") {
                    GlobalStates.abyssDockMenuModel = []
                    GlobalStates.abyssDockMenuOwnerId = ""
                    GlobalStates.abyssDockMenuTriggerHovered = false
                }
                GlobalStates.abyssPopupKind = ""
            }
            function closePopup(): void {
                // Semantic "close all" remains reserved for Escape/backdrop
                // and explicit global transitions.
                liquid.dismissPopups()
                window.closeGenericPopup()
            }
            // An edit Escape must be handled by the active Window, not by an
            // editor sub-item: Quick Notes, drag handles and toolbar buttons
            // can all own QQuickItem focus. Keep only ONE shortcut per output.
            property bool dashboardEscapeCancelPending: false
            property int dashboardEscapeCancelCount: 0
            property int dashboardEscapeFallbackCount: 0
            property real dashboardEscapeLastCancelMs: 0
            function dashboardEscapeProbe(): var {
                return {
                    output: window.outputName,
                    presented: Boolean(window.presented),
                    active: Boolean(window.active),
                    focusItem: String(window.activeFocusItem?.objectName ?? ""),
                    fallbackActiveFocus: Boolean(perimeterEscapeFallback.activeFocus),
                    requestedKeyboardFocus: Number(window.WlrLayershell.keyboardFocus),
                    dashboardOpen: Boolean(dashboardBody.open),
                    dashboardReady: Boolean(dashboardBody.ready),
                    dashboardEditMode: Boolean(dashboardBody.contentItem?.item?.editMode),
                    bodyEscapeCount: dashboardBody.escapeKeyCount,
                    fallbackEscapeCount: window.dashboardEscapeFallbackCount,
                    ownerShortcutEnabled: dashboardEditEscapeShortcut.enabled,
                    cancelCount: window.dashboardEscapeCancelCount,
                    lastCancelMs: window.dashboardEscapeLastCancelMs
                }
            }
            function cancelDashboardEditFromEscape(): bool {
                if (window.dashboardEscapeCancelPending)
                    return true
                const dashboard = dashboardBody.presented ? dashboardBody.contentItem?.item : null
                const overview = aux.presented ? aux.contentItem?.item : null
                const target = dashboard?.editMode ? dashboard
                    : overview?.editMode ? overview : null
                if (!target || typeof target.handleEscape !== "function")
                    return false
                window.dashboardEscapeCancelPending = true
                try {
                    target.handleEscape()
                    window.dashboardEscapeCancelCount++
                    window.dashboardEscapeLastCancelMs = Date.now()
                    // Preserve keyboard ownership for the next physical press.
                    perimeterEscapeFallback.forceActiveFocus()
                    console.info("[DashboardEscape] edit canceled; surface="
                        + (target === dashboard ? "dashboard" : "overview"))
                } finally {
                    Qt.callLater(() => window.dashboardEscapeCancelPending = false)
                }
                return true
            }
            Shortcut {
                id: dashboardEditEscapeShortcut
                sequences: ["Escape"]
                context: Qt.WindowShortcut
                autoRepeat: false
                enabled: window.presented && field.ready
                    && ((dashboardBody.presented
                        && (dashboardBody.contentItem?.item?.editMode ?? false))
                        || (aux.presented
                            && (aux.contentItem?.item?.editMode ?? false)))
                onActivated: window.cancelDashboardEditFromEscape()
                onActivatedAmbiguously: console.warn(
                    "[DashboardEscape] ambiguous Escape shortcut in Abyss output")
            }
            Item {
                id: perimeterEscapeFallback
                anchors.fill: parent
                focus: aux.presented || clipboardBody.presented || leftPanel.presented
                    || rightPanel.presented || popup.presented || dashboardBody.presented
                Keys.onEscapePressed: event => {
                    window.dashboardEscapeFallbackCount++
                    if (window.cancelDashboardEditFromEscape()) {
                        event.accepted = true
                        return
                    }
                    window.closePopup()
                    if (root.utilityKind) root.closeUtility()
                    GlobalStates.closeSidebarLeft()
                    GlobalStates.closeSidebarRight()
                    GlobalStates.dashboardOpen = false
                    GlobalStates.controlPanelOpen = false
                    GlobalStates.settingsOverlayOpen = false
                    GlobalStates.clipboardOpen = false
                    GlobalStates.overviewOpen = false
                    GlobalStates.closeNotificationCenter()
                }
            }
            AbyssEdgeEditor {
                id: editor
                z: 30
                anchors.fill: parent
                visible: window.editorOpen && window.presented && field.ready
                outputName: window.outputName
                moduleLayer: bar
                controller: liquid
                edgeInsets: window.nativeInsets
            }
            property string transientPopupHoverKind: ""
            AbyssBar {
                id: bar
                outputName: window.outputName
                liquidController: liquid
                edge: root.barEdge
                editing: editor.visible
                draggedIds: editor._dragging ? editor.targetIds : []
                draftPlacements: editor.visible ? editor.draft : null
                draftOptions: editor.visible ? editor.draftOptions : null
                visible: window.presented && field.ready && (window.editorOpen || root.barOnOutput(window.outputName))
                anchors.fill: parent
                HoverHandler { id: barHover; onHoveredChanged: { if (hovered) { barClose.stop(); root.setBarRevealed(window.outputName,true) } else barClose.restart() } }
                onInteraction: (edge,along,span,strength) => liquid.impulse(edge,along,span,strength)
                onLayoutRepairRequested: GlobalStates.startAbyssEditing(window.outputName)
                onPopupRequested: (kind,edge,along) => {
                    companionExtension.yieldToUser()
                    const same = GlobalStates.abyssPopupKind === kind
                        && GlobalStates.abyssPopupTargetOutput === window.outputName
                    // Utilities is hover-owned. A click while it is already open
                    // is an idempotent keep-open action, not a surprising toggle-close.
                    if (kind === "utilities" && same)
                        return
                    window.closeGenericPopup()
                    if (!same) {
                        GlobalStates.abyssPopupTargetOutput = window.outputName
                        GlobalStates.abyssPopupAlong = along
                        GlobalStates.abyssPopupEdge = edge
                        GlobalStates.abyssPopupKind = kind
                    }
                }
                onPopupHoveredRequested: (kind,edge,along) => {
                    companionExtension.yieldToUser()
                    const same = GlobalStates.abyssPopupKind === kind
                        && GlobalStates.abyssPopupTargetOutput === window.outputName
                    if (same)
                        return
                    window.closeGenericPopup()
                    GlobalStates.abyssPopupTargetOutput = window.outputName
                    GlobalStates.abyssPopupAlong = along
                    GlobalStates.abyssPopupEdge = edge
                    GlobalStates.abyssPopupKind = kind
                }
                onPopupHoverStateChanged: (kind,edge,along,hovered) => {
                    if (!["wifi","bluetooth","utilities"].includes(kind))
                        return
                    if (hovered) {
                        window.transientPopupHoverKind = kind
                        return
                    }
                    if (window.transientPopupHoverKind === kind)
                        window.transientPopupHoverKind = ""
                }
            }
            HadanionSurface {
                id: companionExtension
                anchors.fill: parent
                host: window
                hostLiquid: liquid
                hostField: field
                hostBar: bar
                hostLeftPanel: leftPanel
                hostRightPanel: rightPanel
                hostCorners: corners
                hostUtility: utility
                hostBarHover: barHover
                hostRevealHover: revealHover
            }
            Item {
                id: revealTrigger
                visible: window.presented && field.ready && (Config.options?.bar?.autoHide?.enable ?? false)
                    && GlobalStates.barOpen && (Config.options?.enabledPanels ?? []).includes("abyssBar")
                    && Geometry.targets(window.outputName,Config.options?.bar?.screenList ?? [],Quickshell.screens.map(s => s.name))
                x: root.barEdge === "right" ? window.width-width : 0
                y: root.barEdge === "bottom" ? window.height-height : 0
                width: Geometry.horizontal(root.barEdge) ? window.width : AbyssStyle.perimeterThickness
                height: Geometry.horizontal(root.barEdge) ? AbyssStyle.perimeterThickness : window.height
                HoverHandler { id: revealHover; onHoveredChanged: { if (hovered) root.setBarRevealed(window.outputName,true); else barClose.restart() } }
            }
            Timer {
                id: barClose; interval: 220; repeat: false
                // Hover state is transient; popup ownership has its own leases.
                // Clearing revealedBars while a popup is open lets the lease
                // release hide the Bar immediately after the popup retracts,
                // instead of leaving the Bar stuck open until another hover.
                onTriggered: if (!barHover.hovered && !revealHover.hovered)
                    root.setBarRevealed(window.outputName,false)
            }
            property real barProgress: root.barOnOutput(window.outputName) ? 1 : 0
            Behavior on barProgress {
                enabled: AbyssStyle.motionEnabled
                NumberAnimation { duration: AbyssStyle.motionNormal; easing.type: Easing.OutCubic }
            }
            // Module strips can expand the painted inset without changing the
            // user's physical Edge width. R02 corner ownership reads the latter.
            readonly property var configuredInsets: ModuleLayout.edgeInsetsForModules(
                [],bar.layoutOptions,Appearance.fontSizeScale,
                AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
            readonly property var nativeInsets: bar.visible
                ? ModuleLayout.edgeInsetsForModules(bar.placements,bar.layoutOptions,
                    Appearance.fontSizeScale,AbyssStyle.perimeterThickness,
                    AbyssStyle.barThickness,false)
                : configuredInsets
            AbyssSurfaceController {
                id: liquid
                outputName: window.outputName
                outputWidth: window.width
                outputHeight: window.height
                presented: window.presented
                presentationItem: field
                dialogHost: dialogBody
                edgeInsets: window.paintInsets
                moduleRecords: bar.visible ? bar.deformations : []
                cornerWidthInsets: window.configuredInsets
                roundZeroCorners: bar.layoutOptions.edgeRoundZeroCorners ?? {}
                // Editing disables the mature module's input, but its handle
                // still owns the same source pixels. Do not let a popup behind
                // that handle acquire body hover and keep itself alive during
                // the gesture. Pin/keyboard requests remain independent.
                sourceInputRegions: (bar.visible ? bar.inputRegions : []).concat(
                    editor.visible ? editor.inputRegions : [])
            }
            readonly property var sideObstacles: {
                // Keep the filter phase before either selected record read.
                const leftVisible = leftPanel.progress > 0.001
                const rightVisible = rightPanel.progress > 0.001
                const result = []
                if (leftVisible) result.push(leftPanel.record)
                if (rightVisible) result.push(rightPanel.record)
                return result
            }
            AbyssSpectrumController {
                waves:liquid.waves
                outputName:window.outputName
                barEdge:root.barEdge
                presented:window.presented && field.ready && !window.editorOpen
            }
            readonly property bool sidebarRevealAvailable: window.presented && field.ready && !window.editorOpen
                && (Config.options?.abyss?.sidebars?.hoverEnabled ?? true)
                && Geometry.targets(window.outputName,Config.options?.sidebar?.screenList ?? [],Quickshell.screens.map(s=>s.name))
            readonly property bool sidebarOpeningAllowed: !utility.open && !settings.open && !dashboardBody.open
                && !controls.open && !aux.open && !clipboardBody.open && !dialogBody.open && !GlobalStates.settingsNativeDialogOpen
                && !PolkitService.active && !GlobalStates.regionSelectorOpen
            component SidebarReveal: AbyssSidebarReveal {
                y: (window.height-height)/2
                width: Math.max(AbyssStyle.perimeterThickness,Config.options?.sidebar?.edgeOpen?.regionWidth ?? 2)
                height: Math.min(180,window.height*.25)
                openingAllowed: window.sidebarOpeningAllowed
                closeBlocked: GlobalStates.activeContextMenuCount>0 || dialogBody.open || GlobalStates.settingsNativeDialogOpen
                z: 220
            }
            SidebarReveal {
                id: leftReveal
                x: 0
                available: window.sidebarRevealAvailable && (Config.options?.enabledPanels ?? []).includes("abyssSidebarLeft")
                open: leftPanel.open
                transientOpen: GlobalStates.sidebarLeftTransient
                bodyItem: leftPanel.contentParent
                onRevealRequested: GlobalStates.openSidebarLeft(window.outputName, true)
                onHideRequested: if (GlobalStates.sidebarLeftPresentationOutput===window.outputName) GlobalStates.closeSidebarLeft()
            }
            SidebarReveal {
                id: rightReveal
                x: window.width-width
                available: window.sidebarRevealAvailable && (Config.options?.enabledPanels ?? []).includes("abyssSidebarRight")
                open: rightPanel.open
                transientOpen: GlobalStates.sidebarRightTransient
                bodyItem: rightPanel.contentParent
                onRevealRequested: GlobalStates.openSidebarRight(window.outputName, true)
                onHideRequested: if (GlobalStates.sidebarRightPresentationOutput===window.outputName) GlobalStates.closeSidebarRight()
            }
            AbyssCorners {
                id:corners;anchors.fill:parent;controller:liquid;outputName:window.outputName
                attachmentThickness:window.nativeInsets.bottom
                quickNotesEditorOutput: root.quickNotesEditorOutput
                presentationEnabled:window.presented && field.ready && !window.editorOpen
                blocked:settings.open || dashboardBody.open || utility.open || controls.open || aux.open || clipboardBody.open
                    || GlobalStates.settingsNativeDialogOpen || PolkitService.active || GlobalStates.regionSelectorOpen
                onQuickNotesEditorLeaseChanged:(outputName,focused)=>
                    root.setQuickNotesEditorOutput(outputName,focused)
            }
            AbyssBodyHost {
                id: widgetEditorBody
                identity: "widgetEditor"
                controller: liquid
                anchors.fill: parent
                outputName: window.outputName
                embeddedItem: GlobalStates.desktopWidgetEditors[window.outputName] ?? null
                readonly property var editorWorkArea: ({
                    left:window.nativeInsets.left, top:window.nativeInsets.top,
                    right:window.width-window.nativeInsets.right,
                    bottom:window.height-window.nativeInsets.bottom})
                readonly property var editorPlacement: embeddedItem?.placement ?? {edge:"bottom",along:0,span:900,depth:64}
                edge: editorPlacement.edge
                along: editorPlacement.along
                span: editorPlacement.span
                depth: editorPlacement.depth
                padding: 6
                edgeInsets: window.bodyInsets(edge,along,span)
                placementPriority: 1
                placementCanResize: false
                placementCanStackInward: false
                animatePlacementChanges: false
                stableContentSize: true
                open: window.presented && field.ready && embeddedItem !== null && GlobalStates.widgetEditMode
                Binding {
                    target: widgetEditorBody.embeddedItem
                    property: "abyssHost"
                    value: widgetEditorBody
                    when: widgetEditorBody.embeddedItem !== null
                    restoreMode: Binding.RestoreBindingOrValue
                }
            }
            AbyssBodyHost {
                id: leftPanel
                // Reveal clips a final-size Sidebar; controls never reflow per frame.
                stableContentSize: true
                identity: "leftPanel"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,ShellLayoutController.sidebarAssignments().featureSidebar)
                outputName: window.outputName
                vacancyRole: "featureSidebar"
                open: window.presented && field.ready && (Config.options?.enabledPanels ?? []).includes("abyssSidebarLeft")
                    && GlobalStates.sidebarLeftOpen && GlobalStates.sidebarLeftPresentationOutput === window.outputName

                edgeInsets: window.bodyInsets(edge,along,span)
                along: window.positionAlong(identity,edge,span,Geometry.horizontal(edge) ? (window.width-span)/2 : (window.height-span)/2)
                readonly property var sizeState:ShellLayoutController.currentState("featureSidebar",window.outputName)
                readonly property real bodyWidth:Math.min(window.width*.8,(sizeState.width ?? 460)+(GlobalStates.sidebarLeftExpanded ? 190 : 0))
                readonly property real bodyHeight:Math.min(window.height-window.nativeInsets.top-window.nativeInsets.bottom-72,
                    sizeState.sizeMode === "custom" ? sizeState.customHeight : Math.max(320,contentItem.item?.preferredContentHeight ?? window.height*.7))
                span:Geometry.horizontal(edge) ? bodyWidth : bodyHeight
                depth:Geometry.horizontal(edge) ? bodyHeight : bodyWidth
                source: "content/AbyssLeftContent.qml"
                onCloseRequested: GlobalStates.closeSidebarLeft()
            }
            AbyssBodyHost {
                id: rightPanel
                // Reveal clips a final-size Sidebar; controls never reflow per frame.
                stableContentSize: true
                identity: "rightPanel"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,ShellLayoutController.sidebarAssignments().systemSidebar)
                outputName: window.outputName
                vacancyRole: "systemSidebar"
                open: window.presented && field.ready && (Config.options?.enabledPanels ?? []).includes("abyssSidebarRight")
                    && GlobalStates.sidebarRightOpen && GlobalStates.sidebarRightPresentationOutput === window.outputName

                edgeInsets: window.bodyInsets(edge,along,span)
                along: window.positionAlong(identity,edge,span,Geometry.horizontal(edge) ? (window.width-span)/2 : (window.height-span)/2)
                readonly property var sizeState:ShellLayoutController.currentState("systemSidebar",window.outputName)
                readonly property real bodyWidth:Math.min(window.width*.8,sizeState.width ?? 460)
                readonly property real bodyHeight:Math.min(window.height-window.nativeInsets.top-window.nativeInsets.bottom-72,
                    sizeState.sizeMode === "custom" ? sizeState.customHeight : Math.max(420,contentItem.item?.preferredContentHeight ?? window.height*.7))
                span:Geometry.horizontal(edge) ? bodyWidth : bodyHeight
                depth:Geometry.horizontal(edge) ? bodyHeight : bodyWidth
                source: "content/AbyssRightContent.qml"
                onCloseRequested: GlobalStates.closeSidebarRight()
            }
            AbyssGenericPopupPresenter {
                id: popup
                anchors.fill: parent
                controller: liquid
                outputName: window.outputName
                outputWidth: window.width
                outputHeight: window.height
                positions: Config.options?.abyss?.positions ?? []
                presentationInsets: window.nativeInsets
                obstacles: window.sideObstacles

                requestedKind: GlobalStates.abyssPopupKind
                requestedOpen: window.presented && field.ready
                    && (Config.options?.enabledPanels ?? []).includes("abyssPopup")
                    && requestedKind.length > 0
                    && GlobalStates.resolveOutputName(
                        GlobalStates.abyssPopupTargetOutput,[]) === window.outputName
                requestedFallbackEdge:
                    GlobalStates.abyssPopupEdge || root.barEdge
                requestedAlongCenter: GlobalStates.abyssPopupAlong
                hoverKind: window.transientPopupHoverKind
                companionVisitActive: companionExtension.utilitiesVisitActive
                bodyInsetsResolver: (edge,along,span) =>
                    window.bodyInsets(edge,along,span)

                onCloseRequested: kind => window.closeGenericPopup(kind)
            }
            // Stable slots avoid destroying/recreating a mature popup's visual
            // content when another popup opens. The controller owns slot
            // assignment; every host remains an ordinary Abyss participant so
            // anchor-preserving composition, input masks and focus arbitration
            // apply to all simultaneous popups.
            Repeater {
                id: styledPopupHosts
                model: liquid.popupCapacity

                delegate: AbyssBodyHost {
                    id: styledPopupHost
                    required property int index
                    readonly property var popupEntry: liquid.popupSlots[index] ?? null
                    readonly property var hostedPopup: popupEntry?.popup ?? null
                    // Existing content HoverHandler exposes scene position only
                    // while hovered. No additional handlers or input regions.
                    readonly property var hoverProbeContentScenePoint:
                        popupContentHover.hovered
                            ? ({ x: popupContentHover.point.scenePosition.x,
                                 y: popupContentHover.point.scenePosition.y })
                            : null
                    readonly property string presentationKind: {
                        const explicitKind = String(
                            hostedPopup?.liquidPresentationKind ?? "")
                        return explicitKind.length > 0
                            ? explicitKind
                            : (hostedPopup?._liquidAnchor?.kind ?? "popup")
                    }

                    identity: "styledPopup" + index
                    includeEdgeConnection: true
                    stackPolicy: "pyramid"
                    semanticOpenOverride:
                        hostedPopup?.liquidSemanticVisible ?? false
                    readonly property var configuredPresentation:
                        window.presentation(presentationKind)
                    readonly property string configuredJoinedEdge:
                        Presentation.joinedEdge(presentationKind,
                            configuredPresentation,edge,along,span,
                            window.width,window.height)
                    joinedEdge: configuredJoinedEdge.length > 0
                        ? configuredJoinedEdge
                        : (hostedPopup?._liquidAnchor?.popupJoinedEdge ?? "")
                    controller: liquid
                    anchors.fill: parent
                    edge: window.positionEdge(presentationKind,
                        hostedPopup?._attachmentEdge ?? root.barEdge)
                    outputName: window.outputName
                    vacancyRole: presentationKind === "quickNotes"
                        ? "quickNotes"
                        : (presentationKind === "notificationCenter"
                            ? "notificationCenter" : "")
                    open: window.presented && field.ready
                        && (hostedPopup?.presentationActive ?? false)
                        && ((hostedPopup?.requestedVisible ?? false)
                            || ((hostedPopup?.hoverActivates ?? false)
                                && (hostedPopup?._lingerVisible ?? false)))
                    animatePresentation: true
                    externalProgress: hostedPopup?.revealProgress ?? 0
                    embeddedItem: hostedPopup?.contentItem ?? null
                    edgeInsets: window.bodyInsets(edge,along,span)
                    padding: 14
                    span: (Geometry.horizontal(edge)
                        ? (embeddedItem?.implicitWidth ?? 1)
                        : (embeddedItem?.implicitHeight ?? 1))+padding*2
                    depth: (Geometry.horizontal(edge)
                        ? (embeddedItem?.implicitHeight ?? 1)
                        : (embeddedItem?.implicitWidth ?? 1))+padding*2
                    largeSurface: depth
                        > (Geometry.horizontal(edge) ? window.height : window.width)*.42
                    readonly property rect anchorBounds:
                        hostedPopup?._anchorRect(window.width,window.height)
                            ?? Qt.rect(0,0,0,0)
                    along: window.positionAlong(presentationKind,edge,span,
                        (Geometry.horizontal(edge)
                            ? anchorBounds.x+anchorBounds.width/2
                            : anchorBounds.y+anchorBounds.height/2)-span/2)
                    obstacles: window.sideObstacles

                    onPopupEntryChanged: {
                        retainedPlacement = null
                        resetPyramidMotion()
                    }
                    onCloseRequested: hostedPopup?.dismissPresentation()
                    Component.onCompleted:
                        liquid.registerPopupHost(index,styledPopupHost)
                    Component.onDestruction:
                        liquid.unregisterPopupHost(index,styledPopupHost)

                    HoverHandler {
                        id: popupContentHover
                        parent: styledPopupHost.hoverParent
                        enabled: styledPopupHost.open
                        onHoveredChanged: {
                            if (styledPopupHost.hostedPopup)
                                styledPopupHost.hostedPopup._contentHovered = hovered
                        }
                    }
                }
            }
            property bool dockHovered: false
            // Retain the source/arrival water during a visit and its final dive.
            // This reads semantic placement and the actor's presentation, not
            // the derived scene/permission, so Dock geometry cannot bind back
            // into its own open decision. Policy reset removes the hold at once.

            readonly property string dockEdge: ["top","bottom","left","right"].includes(Config.options?.dock?.position) ? Config.options.dock.position : "bottom"
            AbyssBodyHost {
                id: dock
                stableContentSize: true
                residentContent: true
                property real cachedSpan: 220
                readonly property real measuredSpan: contentItem.item?.desiredSpan ?? cachedSpan
                readonly property bool attachedPopupHold:
                    liquid.hasPopupAnchoredTo(dock)
                onMeasuredSpanChanged: if(contentItem.item && measuredSpan>0) cachedSpan=measuredSpan
                identity: "dock"
                controller: liquid
                anchors.fill: parent
                edge: window.dockEdge
                outputName: window.outputName
                open: window.presented && field.ready && GlobalStates.shellEntryReady && !GlobalStates.widgetEditMode
                    && (Config.options?.enabledPanels ?? []).includes("abyssDock") && (Config.options?.dock?.enable ?? true)
                    && Geometry.targets(window.outputName,Config.options?.dock?.screenList ?? [],Quickshell.screens.map(s => s.name))
                    && !window.editorOpen && !settings.open && !dashboardBody.open && !controls.open
                    && !aux.open && !clipboardBody.open && !utility.open
                    && (GlobalStates.abyssPopupKind === "dockAppMenu"
                        || attachedPopupHold
                        || !liquid.participantOverlapsRect("popup", requestedRecord.surface, 10))
                    && (GlobalStates.abyssPopupKind === "dockAppMenu"
                        || attachedPopupHold
                        || !liquid.hasPopupOverlapRect(requestedRecord.surface, 10))
                    && (((Config.options?.dock?.pinnedOnStartup ?? false) && !(Config.options?.dock?.hoverToReveal ?? false)) || window.dockHovered
                        || companionExtension.dockHeld
                        || attachedPopupHold
                        || (contentItem.item?.requestDockShow ?? false)
                        || ((Config.options?.dock?.showOnDesktop ?? true) && !ToplevelManager.activeToplevel?.activated))
                edgeInsets: window.bodyInsets(edge,along,span)
                span: Math.min((Geometry.horizontal(edge) ? window.width : window.height)-80,
                    Math.max(140,measuredSpan))
                along: (Geometry.horizontal(edge) ? window.width : window.height)/2-span/2
                depth: AbyssStyle.dockThickness
                padding: 12
                obstacles: {
                    // Keep the first concat's evaluation/copy phase intact.
                    const result = window.sideObstacles.concat(notification.progress > 0.001 ? [notification.record] : [])
                    if (popup.progress > 0.001) result.push(popup.record)
                    return result
                }
                source: "content/AbyssDockContent.qml"
                HoverHandler { id: dockHover; parent: dock.contentItem; onHoveredChanged: { if (hovered) { dockClose.stop(); window.dockHovered = true } else dockClose.restart() } }
            }
            Item {
                id: dockTrigger
                visible: window.presented && field.ready && (Config.options?.dock?.hoverToReveal ?? false)
                    && (Config.options?.dock?.enable ?? true) && (Config.options?.enabledPanels ?? []).includes("abyssDock")
                    && Geometry.targets(window.outputName,Config.options?.dock?.screenList ?? [],Quickshell.screens.map(s => s.name))
                width: Geometry.horizontal(window.dockEdge) ? dock.span : AbyssStyle.perimeterThickness
                height: Geometry.horizontal(window.dockEdge) ? AbyssStyle.perimeterThickness : dock.span
                x: Geometry.horizontal(window.dockEdge) ? (window.width-width)/2 : window.dockEdge === "left" ? 0 : window.width-width
                y: Geometry.horizontal(window.dockEdge) ? window.dockEdge === "top" ? 0 : window.height-height : (window.height-height)/2
                HoverHandler { id: dockRevealHover; onHoveredChanged: { if (hovered) { dockClose.stop(); window.dockHovered = true } else dockClose.restart() } }
            }
            Timer { id: dockClose; interval: 260; repeat: false; onTriggered: if (!dockRevealHover.hovered && !dockHover.hovered) window.dockHovered = false }
            AbyssBodyHost {
                id:keyboardBody;identity:"keyboard"
                controller:liquid;anchors.fill:parent;outputName:window.outputName
                z:(Config.options?.osk?.keepOnTop ?? false) ? 10000 : 0
                property string draftEdge:""
                property real draftAlong:NaN
                property real dragOriginX:0
                property real dragOriginY:0
                property bool dragActive:false
                edge:draftEdge || (["top","bottom"].includes(window.positionEdge(identity,"bottom")) ? window.positionEdge(identity,"bottom") : "bottom")
                open:window.presented && field.ready && GlobalStates.oskOpen
                    && (Config.options?.enabledPanels ?? []).includes("iiOnScreenKeyboard")
                    && GlobalStates.resolveOutputName(GlobalStates.oskTargetMonitor,[])===window.outputName
                edgeInsets:window.bodyInsets(edge,along,span)
                readonly property real naturalWidth:Math.max(1,contentItem.item?.implicitWidth ?? 970)
                readonly property real naturalHeight:Math.max(1,contentItem.item?.implicitHeight ?? 300)
                readonly property real fitScale:Math.max(.01,Math.min(1,
                    (Math.min(1010,window.width*.94)-2*padding)/naturalWidth,
                    (window.height*.72-2*padding)/naturalHeight))
                span:naturalWidth*fitScale+2*padding
                depth:naturalHeight*fitScale+2*padding
                placementCanResize:false
                along:Number.isFinite(draftAlong) ? draftAlong : window.positionAlong(identity,edge,span,window.width/2-span/2)
                source:"../onScreenKeyboard/AbyssKeyboardContent.qml"
                function beginKeyboardDrag():void {
                    dragActive=true;animatePlacementChanges=false
                    dragOriginX=inputBounds.x+inputBounds.width/2
                    dragOriginY=inputBounds.y+inputBounds.height/2
                }
                function moveKeyboardDrag(dx,dy):void {
                    if(!dragActive)return
                    draftEdge=dragOriginY+dy<window.height/2 ? "top" : "bottom"
                    draftAlong=Math.max(window.nativeInsets.left,Math.min(window.width-window.nativeInsets.right-span,dragOriginX+dx-span/2))
                }
                function finishKeyboardDrag():void {
                    if(!dragActive)return
                    dragActive=false;animatePlacementChanges=true
                    const start=window.nativeInsets.left,end=Math.max(start,window.width-window.nativeInsets.right-span)
                    Config.setNestedValue("abyss.positions",Presentation.save(Config.options?.abyss?.positions,identity,outputName,
                        {edge:edge,alignment:"custom",position:end>start ? Math.max(0,Math.min(1,(along-start)/(end-start))) : .5}))
                    draftEdge="";draftAlong=NaN
                }
                onOpenChanged:if(!open){dragActive=false;draftEdge="";draftAlong=NaN;animatePlacementChanges=true}
                onCloseRequested:GlobalStates.oskOpen=false
            }
            AbyssBodyHost {
                id:wallpaperBody;identity:"wallpaper"
                controller:liquid;anchors.fill:parent;outputName:window.outputName
                edge:window.positionEdge(identity,"bottom")
                open:window.presented && field.ready && GlobalStates.wallpaperLauncherOpen
                    && (Config.options?.enabledPanels ?? []).includes("iiWallpaperSelector")
                    && GlobalStates.resolveOutputName(GlobalStates.wallpaperSelectorTargetMonitor,[])===window.outputName
                edgeInsets:window.bodyInsets(edge,along,span)
                readonly property real contentWidth:Math.min(1080,window.width*.9)
                readonly property real contentHeight:Math.min(320,window.height*.65)
                span:Geometry.horizontal(edge) ? contentWidth : contentHeight
                depth:Geometry.horizontal(edge) ? contentHeight : contentWidth
                along:window.positionAlong(identity,edge,span,(Geometry.horizontal(edge) ? window.width : window.height)/2-span/2)
                minimumSpan:Math.min(span,420);minimumDepth:Math.min(depth,280)
                source:"../wallpaperLauncher/WallpaperLauncherContent.qml"
                onReadyChanged:if(ready && contentItem.item)contentItem.item.embedded=true
                onCloseRequested:GlobalStates.wallpaperLauncherOpen=false
            }
            // Distinct hosts retain their own content until retraction ends.
            // Switching the aux Loader to Overview on clipboard close briefly
            // rendered Dashboard inside the still-visible Clipboard silhouette.
            AbyssBodyHost {
                id: clipboardBody
                stableContentSize: true
                identity: "clipboard"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,"bottom")
                outputName: window.outputName
                open: window.presented && field.ready && GlobalStates.clipboardOpen
                    && (Config.options?.enabledPanels ?? []).includes("abyssClipboard")
                    && GlobalStates.resolveOutputName(GlobalStates.abyssClipboardTargetOutput,[]) === window.outputName
                edgeInsets: window.bodyInsets(edge,along,span)
                readonly property real contentWidth: 640
                readonly property real contentHeight: window.height*.42
                span: Geometry.horizontal(edge) ? contentWidth : contentHeight
                along: window.positionAlong(identity,edge,span,(Geometry.horizontal(edge) ? window.width : window.height)/2-span/2)
                depth: Geometry.horizontal(edge) ? contentHeight : contentWidth
                obstacles: window.sideObstacles
                source: "content/AbyssClipboardContent.qml"
                onCloseRequested: GlobalStates.clipboardOpen = false
            }
            AbyssBodyHost {
                id: aux
                stableContentSize: true
                warmContent: true
                identity: "aux"
                controller: liquid
                anchors.fill: parent
                readonly property string presentationKind: "overview"
                edge: window.positionEdge(presentationKind,"bottom")
                outputName: window.outputName
                open: window.presented && field.ready && GlobalStates.overviewOpen
                    && (Config.options?.enabledPanels ?? []).includes("abyssOverview")
                    && GlobalStates.overviewPresentationOutput === window.outputName
                edgeInsets: window.bodyInsets(edge,along,span)
                largeSurface: true
                readonly property real contentWidth: GlobalStates.overviewMode === "taskview" ? window.width*.9 : window.width*(Config.options?.dashboard?.widthRatio ?? .72)+40
                readonly property real contentHeight: (contentItem.item?.desiredHeight ?? window.height*.72)+padding*2
                span: Geometry.horizontal(edge) ? contentWidth : contentHeight
                along: window.positionAlong(presentationKind,edge,span,(Geometry.horizontal(edge) ? window.width : window.height)/2-span/2)
                depth: Geometry.horizontal(edge) ? contentHeight : contentWidth
                source: "content/AbyssOverviewContent.qml"
                onCloseRequested: GlobalStates.overviewOpen = false
            }
            AbyssBodyHost {
                id: settings
                stableContentSize: true
                identity: "settings"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,"bottom")
                outputName: window.outputName
                open: window.presented && field.ready && GlobalStates.settingsOverlayOpen
                    && GlobalStates.settingsOverlayPresentationOutput === window.outputName
                largeSurface: true
                edgeInsets: window.bodyInsets(edge,along,span)
                span: Geometry.horizontal(edge) ? Math.min(1600,Math.max(900,window.width*.9)) : Math.min(1080,Math.max(720,window.height*.92))
                along: window.positionAlong(identity,edge,span,((Geometry.horizontal(edge) ? window.width : window.height)-span)/2)
                depth: Geometry.horizontal(edge) ? Math.min(1080,Math.max(720,window.height*.92)) : Math.min(1600,Math.max(900,window.width*.9))
                source: "content/AbyssSettingsContent.qml"
                onCloseRequested: GlobalStates.settingsOverlayOpen = false
            }
            AbyssBodyHost {
                id: dashboardBody
                stableContentSize: true
                warmContent: true
                identity: "dashboard"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,"bottom")
                outputName: window.outputName
                open: window.presented && field.ready && GlobalStates.dashboardOpen
                    && root.largeTargetOutput === window.outputName && (Config.options?.enabledPanels ?? []).includes("iiDashboard")
                largeSurface: true
                edgeInsets: window.bodyInsets(edge,along,span)
                span: Geometry.horizontal(edge) ? window.width*(Config.options?.dashboard?.widthRatio ?? .72)+40 : window.height*(Config.options?.dashboard?.heightRatio ?? .72)+40
                along: window.positionAlong(identity,edge,span,((Geometry.horizontal(edge) ? window.width : window.height)-span)/2)
                depth: Geometry.horizontal(edge) ? window.height*(Config.options?.dashboard?.heightRatio ?? .72)+40 : window.width*(Config.options?.dashboard?.widthRatio ?? .72)+40
                source: "content/AbyssDashboardContent.qml"
                onCloseRequested: GlobalStates.dashboardOpen = false
            }
            AbyssBodyHost {
                id: controls
                stableContentSize: true
                identity: "controls"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,"right")
                outputName: window.outputName
                open: window.presented && field.ready && GlobalStates.controlPanelOpen
                    && root.largeTargetOutput === window.outputName && (Config.options?.enabledPanels ?? []).includes("iiControlPanel")
                edgeInsets: window.bodyInsets(edge,along,span)
                span: Geometry.horizontal(edge) ? Math.max(380,window.width*.23) : Math.min(950,window.height-100)
                along: window.positionAlong(identity,edge,span,((Geometry.horizontal(edge) ? window.width : window.height)-span)/2)
                depth: Geometry.horizontal(edge) ? Math.min(950,window.height-100) : Math.max(380,window.width*.23)
                source: "content/AbyssControlContent.qml"
                onCloseRequested: GlobalStates.controlPanelOpen = false
            }
            AbyssBodyHost {
                id: notification
                identity: "notification"
                controller: liquid
                anchors.fill: parent
                // Keep toast labels/cards at their full resting dimensions
                // behind the shrinking reveal clip. Its closing surface must
                // not relayout content as the Notification Center opens.
                stableContentSize: true
                // Keep the banner's ListView loaded at target size while its
                // delegates settle, before the visible reveal and allocator
                // begin. On recording stop the saved-file-path card can require
                // multiple layout passes; opening at a provisional height
                // caused repeated field/placement work during animation.
                residentContent: Notifications.popupList.length > 0
                    && !Notifications.popupInhibited
                // This host ONLY owns transient notification banners. An open
                // Notification Center has its own mature StyledPopup slot.
                // Do not repurpose a closing banner into "center" content:
                // the prior branch changed its requested height/edge while
                // its animated surface was still visually resident.
                readonly property string position: Config.options?.notifications?.position ?? "topRight"
                readonly property string presentationKind: "notifications"
                edge: window.positionEdge(presentationKind,
                    position.startsWith("bottom") ? "bottom" : "top")
                joinedEdge: window.presentation(presentationKind).joinCorner===true
                    ? ModuleLayout.adjacentEdge({edge:edge,along:along,span:span},window.width,window.height) : ""
                outputName: window.outputName
                open: window.presented && field.ready && (!GlobalStates.notificationCenterOpen
                        && !Notifications.popupInhibited && Notifications.popupList.length > 0
                        && (contentItem.item?.popupLayoutReady ?? false)
                        && (Config.options?.enabledPanels ?? []).includes("abyssNotificationPopup")
                        && Geometry.targets(window.outputName,Config.options?.notifications?.screenList ?? [],Quickshell.screens.map(s => s.name)))
                edgeInsets: window.bodyInsets(edge,along,span)
                readonly property real contentWidth:
                    (contentItem.item?.desiredWidth
                        ?? Appearance.sizes.notificationPopupWidth)+padding*2
                readonly property real contentHeight: Math.min(window.height*.42,
                    Math.max(100,(contentItem.item?.desiredHeight ?? 130)+padding*2))
                span: Geometry.horizontal(edge) ? contentWidth : contentHeight
                along: window.positionAlong(presentationKind,edge,span,
                    position.endsWith("Left") ? 40
                        : (Geometry.horizontal(edge) ? window.width : window.height)-span-40)
                depth: Geometry.horizontal(edge) ? contentHeight : contentWidth
                obstacles: window.sideObstacles.concat(popup.open ? [popup.record] : [])
                contentKind: "popup"
                source: "content/AbyssNotificationsContent.qml"
                onCloseRequested: GlobalStates.closeNotificationCenter()
            }
            // Reload/system toasts reuse the same output-owned Abyss field.
            // ToastManager remains the single queue/timer owner; the legacy
            // independent PanelWindow is never loaded while Abyss is active.
            AbyssBodyHost {
                id: toastBody
                identity: "toast"
                controller: liquid
                anchors.fill: parent
                edge: "top"
                joinedEdge: "right"
                outputName: window.outputName
                open: window.presented && field.ready
                    && (GlobalStates.toastManager?.useAbyssPresentation ?? false)
                    && !(GlobalStates.toastManager?.suppressOnScreenToasts ?? false)
                    && (GlobalStates.toastManager?.toasts?.length ?? 0) > 0
                    && GlobalStates.toastManager?.presentationOutputName === window.outputName
                animatePresentation: false
                externalProgress: GlobalStates.toastManager?.surfaceRevealProgress ?? 0
                placementPriority: 1
                edgeInsets: window.bodyInsets(edge,along,span)
                padding: 8
                span: (contentItem.item?.desiredWidth ?? 180)+padding*2
                depth: (contentItem.item?.desiredHeight ?? 54)+padding*2
                along: Math.max(window.nativeInsets.left,
                    window.width-window.nativeInsets.right-span)
                source: "content/AbyssToastContent.qml"
            }
            AbyssBodyHost {
                id: osd
                identity: "osd"
                controller: liquid
                anchors.fill: parent
                readonly property string presentationKind: GlobalStates.abyssOsdKind === "media" ? "mediaOsd" : GlobalStates.abyssOsdKind
                edge: window.positionEdge(presentationKind,root.barEdge)
                joinedEdge: window.presentation(presentationKind).joinCorner===true
                    ? ModuleLayout.adjacentEdge({edge:edge,along:along,span:span},window.width,window.height) : ""
                outputName: window.outputName
                open: (window.presented || window.physicalOsdRequested) && field.ready && (Config.options?.enabledPanels ?? []).includes("abyssOnScreenDisplay")
                    && (GlobalStates.osdVolumeOpen || GlobalStates.osdBrightnessOpen || GlobalStates.osdMicOpen || GlobalStates.osdMediaOpen || GlobalStates.osdKeyboardLayoutOpen)
                    && Geometry.targets(window.outputName,Config.options?.osd?.screenList ?? [],Quickshell.screens.map(s => s.name))
                edgeInsets: window.physicalOsdResident ? window.physicalInsets : window.bodyInsets(edge,along,span)
                padding: 12
                span: (Geometry.horizontal(edge) ? (contentItem.item?.desiredWidth ?? Appearance.sizes.osdWidth) : (contentItem.item?.desiredHeight ?? 48))+padding*2
                along: Presentation.along(window.presentation(presentationKind),edge,span,window.width,window.height,
                    (Geometry.horizontal(edge) ? window.width : window.height)/2-span/2,
                    window.physicalOsdResident ? window.physicalInsets : window.nativeInsets)
                depth: (Geometry.horizontal(edge) ? (contentItem.item?.desiredHeight ?? 48) : (contentItem.item?.desiredWidth ?? Appearance.sizes.osdWidth))+padding*2
                source: "content/AbyssOsdContent.qml"
                HoverHandler {
                    parent: osd.contentItem
                    enabled: osd.open
                    onHoveredChanged: {
                        if (GlobalStates.abyssOsdKind === "media") {
                            if (hovered) GlobalStates.abyssOsdHoverOutput = window.outputName
                            else if (GlobalStates.abyssOsdHoverOutput === window.outputName) GlobalStates.abyssOsdHoverOutput = ""
                        } else if (hovered && GlobalStates.abyssOsdKind !== "voiceSearch") GlobalStates.osdDismissed()
                    }
                }
            }
            AbyssRecordingBody {
                anchors.fill: parent
                controller: liquid
                outputName: window.outputName
                targetOutput: GlobalStates.primaryScreen?.name === window.outputName
                available: window.presented && field.ready && GlobalStates.deferredPanelsReady
                enabledPanel: (Config.options?.enabledPanels ?? []).includes("iiRecordingOsd")
                edgeInsets: window.bodyInsets(edge,along,span)
            }
            AbyssBodyHost {
                id: utility
                property string retainedKind: "session"
                z: 15
                identity: "utility"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(contentKind,"bottom")
                outputName: window.outputName
                open: window.presented && field.ready && root.utilityKind.length > 0
                    && root.largeTargetOutput === window.outputName
                    && (Config.options?.enabledPanels ?? []).includes(root.utilityIdentifier)
                largeSurface: true
                edgeInsets: window.bodyInsets(edge,along,span)
                span: (Geometry.horizontal(edge) ? (contentItem.item?.desiredWidth ?? 640) : (contentItem.item?.desiredHeight ?? 700))+padding*2
                along: window.positionAlong(contentKind,edge,span,((Geometry.horizontal(edge) ? window.width : window.height)-span)/2)
                depth: (Geometry.horizontal(edge) ? (contentItem.item?.desiredHeight ?? 700) : (contentItem.item?.desiredWidth ?? 640))+padding*2
                // A closing host still paints its previous feature. Empty
                // utilityKind must not select the Update fallback mid-slide.
                contentKind: root.utilityKind || retainedKind
                onContentKindChanged: if(contentKind) retainedKind=contentKind
                source: "content/AbyssUtilityContent.qml"
                onCloseRequested: root.closeUtility()
            }
            AbyssBodyHost {
                id: dialogBody
                z: 20
                identity: "dialog"
                controller: liquid
                anchors.fill: parent
                edge: window.positionEdge(identity,"right")
                outputName: window.outputName
                vacancyRole: String(
                    liquid.activeDialog?.liquidVacancyRole ?? "")
                open: window.presented && field.ready && liquid.activeDialog !== null
                embeddedItem: liquid.activeDialog
                span: (Geometry.horizontal(edge) ? (liquid.activeDialog?.liquidWidth ?? 350) : (liquid.activeDialog?.liquidHeight ?? 450))+padding*2
                depth: (Geometry.horizontal(edge) ? (liquid.activeDialog?.liquidHeight ?? 450) : (liquid.activeDialog?.liquidWidth ?? 350))+padding*2
                along: window.positionAlong(identity,edge,span,((Geometry.horizontal(edge) ? window.width : window.height)-span)/2)
                edgeInsets: window.bodyInsets(edge,along,span)
                onCloseRequested: if (liquid.activeDialog) liquid.activeDialog.dismiss()
            }
            AbyssField {
                id: field
                outputName: window.outputName
                renderScale: window.modelData?.devicePixelRatio ?? 1
                z: -1
                anchors.fill: parent
                visible: window.presented || window.physicalOsdResident
                edgeInsets: window.paintInsets
                roundZeroCorners: window.presented ? bar.layoutOptions.edgeRoundZeroCorners ?? {} : {}
                cornerWidthInsets: window.configuredInsets
                records: window.presented ? liquid.records : window.physicalOsdResident ? [osd.record] : []
                waveTexture: liquid.waves.texture
                waterLink: companionExtension.waterLink
            }
        }
    }
    component Reservation: PanelWindow {
        id: reservation
        required property var modelData
        required property string edge
        readonly property bool horizontal: Geometry.horizontal(edge)
        readonly property bool mapped: Config.ready && !GlobalStates.screenLocked
            && !GameMode.hasFullscreenOnOutput(modelData?.name ?? "")
        readonly property bool persistentDock: (Config.options?.enabledPanels ?? []).includes("abyssDock")
            && (Config.options?.dock?.enable ?? true) && (Config.options?.dock?.pinnedOnStartup ?? false)
            && !(Config.options?.dock?.hoverToReveal ?? false) && !GlobalStates.widgetEditMode
            && Geometry.targets(modelData?.name ?? "",Config.options?.dock?.screenList ?? [],Quickshell.screens.map(s => s.name))
        readonly property string dockEdge: ["top","bottom","left","right"].includes(Config.options?.dock?.position) ? Config.options.dock.position : "bottom"
        readonly property real thickness: root.outputInsets(modelData?.name ?? "",true)[edge]
            + (persistentDock && edge === dockEdge ? AbyssStyle.dockThickness : 0)
        screen: modelData
        visible: mapped
        color: "transparent"
        exclusiveZone: mapped ? thickness : 0
        implicitWidth: horizontal ? 1 : thickness
        implicitHeight: horizontal ? thickness : 1
        WlrLayershell.namespace: "hadalis:abyss-reservation-" + edge
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        anchors {
            top: edge !== "bottom"
            bottom: edge !== "top"
            left: edge !== "right"
            right: edge !== "left"
        }
        mask: Region {}
    }
    Variants { model: Quickshell.screens; Reservation { edge: "top" } }
    Variants { model: Quickshell.screens; Reservation { edge: "bottom" } }
    Variants { model: Quickshell.screens; Reservation { edge: "left" } }
    Variants { model: Quickshell.screens; Reservation { edge: "right" } }
}
