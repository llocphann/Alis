import QtQuick
import Quickshell
import "looks/AbyssBodyPlacement.js" as BodyPlacement
import "looks/AbyssVacancyBorrowing.js" as VacancyBorrowing

// One controller per output. Content and input are not inferred from pixels.
QtObject {
    id: root
    property string outputName: ""
    property var participants: ({})
    readonly property AbyssPyramidCoordinator pyramidCoordinator:
        AbyssPyramidCoordinator { controller: root }
    property var moduleRecords: []
    // Source modules retain pointer priority over the popup bridge they own.
    property var sourceInputRegions: []
    property int presentationOrder: 0
    function nextPresentationOrder(): int { return ++presentationOrder }
    property int vacancyInteractionOrder: 0
    function nextVacancyInteractionOrder(): int {
        return ++vacancyInteractionOrder
    }
    readonly property var placementRequests: {
        const mapped = Object.keys(participants)
            .map(key => participants[key]?.placementRequest)
        // Finish all participant reads before the original filter predicates.
        // Only this fresh, unpublished map result is compacted.
        let kept = 0
        for (let i = 0; i < mapped.length; ++i) {
            const request = mapped[i]
            if (request !== null && request !== undefined)
                mapped[kept++] = request
        }
        mapped.length = kept
        return mapped
    }
    // Hover is intentionally absent: vacancy geometry is automatic and must
    // not churn when the pointer crosses a body that is itself moving.
    readonly property var vacancyParticipants: Object.keys(participants)
        .map(key => ({
            id:key,
            role:String(participants[key]?.vacancyRole ?? "")
        }))
    readonly property var baseBodyPlacements: BodyPlacement.arrange(
        placementRequests,outputWidth,outputHeight,edgeInsets)
    readonly property var bodyPlacements: VacancyBorrowing.resolve(
        placementRequests,vacancyParticipants,baseBodyPlacements,
        outputWidth,outputHeight,edgeInsets,24)
    property real outputWidth: 1920
    property real outputHeight: 1080
    property bool presented: true
    property Item presentationItem: null
    property var edgeInsets: ({left:16,top:48,right:16,bottom:16})
    property var cornerWidthInsets: edgeInsets
    property var roundZeroCorners: ({})
    // Backward-compatible single host used by isolated tests/legacy callers.
    // Production Abyss registers stable popup slots instead, allowing several
    // mature StyledPopup instances to coexist without dismissing each other.
    property var popupHost: null
    readonly property int popupCapacity: 4
    property var popupSlots: [null, null, null, null]
    property var popupHosts: ({})
    property int popupOrder: 0
    readonly property var popupEntries: popupSlots.filter(entry => entry !== null)
        .sort((a,b) => a.order-b.order)
    readonly property var activePopups: popupEntries.map(entry => entry.popup)
    readonly property var activePopup: popupEntries.length > 0
        ? popupEntries[popupEntries.length-1].popup : null
    readonly property Item popupHome: popupEntries.length > 0
        ? popupEntries[popupEntries.length-1].home : null
    readonly property bool popupsOpen: popupEntries.some(entry =>
        entry.popup?.presentationActive ?? false)
    readonly property var popupInputBounds: popupSlots.map((entry,index) => {
        if (!entry) return null
        return participants["styledPopup" + index]?.inputBounds ?? null
    }).filter(rect => rect && rect.width > 0 && rect.height > 0)
    // Match StyledPopup's native focus contract while several mature popups
    // share one layer-shell window. The newest *focus-requesting* visible popup
    // owns the mode; a newer passive popup does not steal an older editor lease.
    // keyboardFocus alone is OnDemand, exactly like StyledPopup. Exclusive is an
    // explicit opt-in through exclusiveKeyboardFocus.
    readonly property var popupFocusOwner: {
        const entries = popupEntries.slice().reverse()
        for (const entry of entries) {
            const popup = entry?.popup ?? null
            if (!popup || (!(popup.keyboardFocus ?? false)
                    && !(popup.keyboardFocusOnDemand ?? false)))
                continue
            const slot = root._popupSlot(popup)
            if (slot < 0) continue
            const rect = participants["styledPopup" + slot]?.inputBounds
            if (rect && rect.width > 0 && rect.height > 0)
                return popup
        }
        return null
    }
    readonly property bool popupExclusiveFocus: popupFocusOwner !== null
        && (popupFocusOwner.keyboardFocus ?? false)
        && (popupFocusOwner.exclusiveKeyboardFocus ?? false)
    readonly property bool popupOnDemandFocus: popupFocusOwner !== null
        && !popupExclusiveFocus

    function _popupSlot(popup): int {
        for (let i=0; i<popupSlots.length; ++i)
            if (popupSlots[i]?.popup === popup) return i
        return -1
    }
    function _popupHost(index): var {
        return popupHosts[String(index)] ?? (index === 0 ? popupHost : null)
    }
    function _rehostPopup(index): void {
        const entry = popupSlots[index]
        const host = _popupHost(index)
        if (!entry || !host || !entry.popup?.contentItem) return
        const popup = entry.popup
        const item = popup.contentItem
        item.parent = host.contentParent
        item.x = 0
        item.y = 0
        item.width = Qt.binding(() => host.contentParent.width)
        item.height = Qt.binding(() => host.contentParent.height)
        item.visible = Qt.binding(() => popup.presentationActive)
        popup.presentationWindow = presentationItem?.QsWindow?.window ?? null
    }
    function registerPopupHost(index, host): void {
        if (index < 0 || index >= popupCapacity || !host) return
        const next = Object.assign({}, popupHosts)
        next[String(index)] = host
        popupHosts = next
        _rehostPopup(index)
    }
    function unregisterPopupHost(index, host): void {
        if (popupHosts[String(index)] !== host) return
        const entry = popupSlots[index]
        if (entry?.popup?.contentItem && entry.home
                && entry.popup.contentItem.parent === host.contentParent) {
            entry.popup.contentItem.parent = entry.home
            entry.popup.contentItem.visible = Qt.binding(() => entry.popup.presentationActive)
        }
        const next = Object.assign({}, popupHosts)
        delete next[String(index)]
        popupHosts = next
    }
    function presentPopup(popup): void {
        if (!popup || !popup.contentItem) return
        const existing = _popupSlot(popup)
        if (existing >= 0) {
            _rehostPopup(existing)
            return
        }

        let slot = -1
        for (let i=0; i<popupCapacity; ++i) {
            if (popupSlots[i] === null || popupSlots[i] === undefined) {
                slot = i
                break
            }
        }
        if (slot < 0) {
            // Four simultaneous mature popups is already beyond ordinary shell
            // use. If it happens, retract the oldest and retry without ever
            // stealing/destroying its content synchronously.
            const oldest = popupEntries[0]?.popup
            if (oldest && oldest !== popup) oldest.dismissPresentation()
            Qt.callLater(() => {
                if (popup.presentationActive && root._popupSlot(popup) < 0)
                    root.presentPopup(popup)
            })
            return
        }

        const next = popupSlots.slice()
        next[slot] = {
            popup: popup,
            home: popup.contentItem.parent,
            order: ++popupOrder
        }
        popupSlots = next
        popup.presentationWindow = presentationItem?.QsWindow?.window ?? null
        Qt.callLater(() => root._rehostPopup(slot))
    }
    function releasePopup(popup, restore = true): void {
        const slot = _popupSlot(popup)
        if (slot < 0) return
        const entry = popupSlots[slot]
        popup.presentationWindow = null
        popup._bodyHovered = false
        popup._contentHovered = false
        if (restore && popup.contentItem && entry?.home) {
            popup.contentItem.parent = entry.home
            popup.contentItem.visible = Qt.binding(() => popup.presentationActive)
        }
        const next = popupSlots.slice()
        next[slot] = null
        popupSlots = next
    }
    function dismissPopups(): void {
        activePopups.slice().reverse().forEach(popup => popup?.dismissPresentation())
    }
    function _rectsOverlap(a, b, gap = 0): bool {
        if (!a || !b) return false
        return a.x < b.x + b.width + gap
            && a.x + a.width + gap > b.x
            && a.y < b.y + b.height + gap
            && a.y + a.height + gap > b.y
    }
    function participantOverlapsRect(identity, rect, gap = 0): bool {
        const request = participants[identity]?.placementRequest
        if (!(request?.open ?? false)) return false
        return root._rectsOverlap(request?.record?.surface, rect, gap)
    }
    function hasPopupOverlapRect(rect, gap = 0): bool {
        for (let i = 0; i < popupSlots.length; ++i) {
            const entry = popupSlots[i]
            if (!entry || !(entry.popup?.presentationActive ?? false))
                continue
            if (root.participantOverlapsRect("styledPopup" + i, rect, gap))
                return true
        }
        return false
    }
    function hasPopupAnchoredTo(anchor): bool {
        if (!anchor)
            return false
        return popupEntries.some(entry =>
            (entry.popup?.presentationActive ?? false)
            && entry.popup?._liquidAnchor === anchor)
    }
    function hasPopupOnEdge(edge): bool {
        return popupEntries.some(entry => (entry.popup?.presentationActive ?? false)
            && entry.popup?._attachmentEdge === edge)
    }
    onPresentedChanged: if (!presented) dismissPopups()
    property var activeDialog: null
    property Item dialogHome: null
    property var dialogHost: null
    function presentDialog(item): void {
        if (!item || !dialogHost || activeDialog === item) return
        if (activeDialog) activeDialog.dismiss()
        dialogHome = item.parent
        activeDialog = item
        item.parent = dialogHost.contentParent
        item.x = 0; item.y = 0
        item.width = Qt.binding(() => dialogHost.contentParent.width)
        item.height = Qt.binding(() => dialogHost.contentParent.height)
        item.forceActiveFocus()
    }
    function releaseDialog(item, restore = true): void {
        if (activeDialog !== item) return
        const home = dialogHome
        activeDialog = null
        dialogHome = null
        if (restore && home) {
            item.parent = home
            item.width = Qt.binding(() => home.width)
            item.height = Qt.binding(() => home.height)
        }
    }
    readonly property AbyssWaveController waves: AbyssWaveController {
        parent: root.presentationItem
        outputWidth: root.outputWidth
        outputHeight: root.outputHeight
        presented: root.presented
        records: root.records
    }
    readonly property int capacity: 40
    readonly property var records: moduleRecords.concat((() => {
        const mapped = Object.keys(participants)
            .map(key => participants[key]?.geometry ? Object.assign({},participants[key].geometry,{mass:participants[key].mass}) : null)
        // Finish all participant reads before the original filter predicates.
        // Only this fresh, unpublished map result is compacted.
        let kept = 0
        for (let i = 0; i < mapped.length; ++i) {
            const rec = mapped[i]
            if (rec && rec.surface.width > 0 && rec.surface.height > 0)
                mapped[kept++] = rec
        }
        mapped.length = kept
        return mapped
    })())
    readonly property var inputBounds: {
        const mapped = Object.keys(participants)
            .map(key => participants[key]?.inputBounds)
        // Finish all participant reads before the original filter predicates.
        // Only this fresh, unpublished map result is compacted.
        let kept = 0
        for (let i = 0; i < mapped.length; ++i) {
            const rect = mapped[i]
            if (rect && rect.width > 0 && rect.height > 0)
                mapped[kept++] = rect
        }
        mapped.length = kept
        return mapped
    }
    readonly property var nativeInputRegions: Object.keys(participants)
        .map(key=>participants[key]?.nativeInputRegion ?? null)
        .filter(region=>region !== null)

    function impulse(edge, along, span, strength, mass = 1, channel = "module"): void {
        waves.impulse(edge,along,span,strength,mass,channel)
    }

    function registerParticipant(key, participant): void {
        if (!key || !participant) return
        if (participants[key] && participants[key] !== participant) {
            console.error("[Abyss] duplicate participant", outputName, key)
            return
        }
        const next = Object.assign({}, participants)
        next[key] = participant
        participants = next
    }
    function unregisterParticipant(key, participant): void {
        if (participants[key] !== participant) return
        const next = Object.assign({}, participants)
        delete next[key]
        participants = next
    }
}
