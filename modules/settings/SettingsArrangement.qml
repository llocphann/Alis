pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.services

QtObject {
    id: root

    readonly property int layoutSchemaVersion: 11
    readonly property int retiredTlpPageIndex: 28
    readonly property int overviewPageIndex: 29

    function snapshot(): var {
        return ({
            groups: SettingsPageRegistry.categories.map(c => ({
                label: c.label,
                pages: c.pages.slice()
            })),
            hidden: SettingsPageRegistry.hiddenPages.slice(),
            names: Object.assign({}, SettingsPageRegistry.customPageNames ?? ({}))
        })
    }

    function save(snapshot): void {
        // Persist all retired slots as implementation-only hidden indices so
        // old numeric routes cannot be re-added under a generated "More" group.
        const retired = SettingsPageRegistryData.legacyHiddenIndexes
        const hidden = (Array.isArray(snapshot.hidden) ? snapshot.hidden : [])
            .filter(index => !retired.includes(index))
        for (const index of retired)
            hidden.push(index)

        Config.setNestedValue("settingsUi.categories", JSON.stringify({
            version: root.layoutSchemaVersion,
            groups: snapshot.groups,
            hidden: hidden,
            names: snapshot.names ?? ({})
        }))
    }

    function migrateLegacyPageIndices(): void {
        // SettingsPageHost also calls this during Component.onCompleted, before
        // Config can be ready. Never turn that early empty state into a write.
        if (!Config.ready)
            return

        const raw = Config.options?.settingsUi?.categories ?? ""
        if (typeof raw !== "string" || raw.length === 0)
            return

        let saved
        try {
            saved = JSON.parse(raw)
        } catch (e) {
            return
        }

        const sourceVersion = Array.isArray(saved) ? 1 : Number(saved?.version ?? 2)
        if (!Array.isArray(saved) && sourceVersion >= root.layoutSchemaVersion)
            return

        const groups = Array.isArray(saved)
            ? saved
            : (Array.isArray(saved?.groups) ? saved.groups : null)
        if (!groups)
            return

        const hidden = Array.isArray(saved?.hidden) ? saved.hidden : []
        let hasLegacyTlpIndex = false
        let hasCurrentTlpIndex = false
        const inspectIndex = index => {
            if (index === 27)
                hasLegacyTlpIndex = true
            else if (index === root.retiredTlpPageIndex)
                hasCurrentTlpIndex = true
        }

        for (const group of groups) {
            if (!group || !Array.isArray(group.pages))
                continue
            group.pages.forEach(inspectIndex)
        }
        hidden.forEach(inspectIndex)

        // Before Orbit existed, fork layouts could use 27 for the standalone
        // Battery/TLP page. In those pre-v3 layouts, 27 with no 28 is the old
        // TLP page. Drop it; SettingsPageRegistryData will then surface the new
        // Orbit page as a missing page, while the public registry filters only
        // the retired TLP page 28.
        const dropPreOrbitTlp = sourceVersion < 3
            && hasLegacyTlpIndex && !hasCurrentTlpIndex
        const keepPage = index => index !== root.retiredTlpPageIndex
            && !(dropPreOrbitTlp && index === 27)

        const migratedGroups = groups.map(group => {
            if (!group || typeof group.label !== "string")
                return group
            return ({
                label: group.label,
                pages: (Array.isArray(group.pages) ? group.pages : []).filter(keepPage)
            })
        })
        const migratedHidden = hidden.filter(keepPage)

        // v5 gives Overview a first-class Shell home. v4 could only discover
        // the newly appended page as “More”, so remove that generated placement
        // and insert it into whichever saved group best matches the default Shell
        // peers. This also survives renamed/custom Shell group labels.
        if (sourceVersion < 5
                && !migratedHidden.includes(root.overviewPageIndex)) {
            for (const group of migratedGroups) {
                if (!group || !Array.isArray(group.pages))
                    continue
                group.pages = group.pages.filter(
                    index => index !== root.overviewPageIndex)
            }

            const defaultShell = SettingsPageRegistry.defaultCategories.find(
                category => category.pages.includes(root.overviewPageIndex))
            const shellPeers = defaultShell?.pages?.filter(
                index => index !== root.overviewPageIndex) ?? [2, 26, 5, 22, 23, 16]
            let targetIndex = -1
            let bestScore = -1
            for (let i = 0; i < migratedGroups.length; i++) {
                const pages = migratedGroups[i]?.pages ?? []
                let score = 0
                for (const peer of shellPeers)
                    if (pages.includes(peer))
                        score++
                if (score > bestScore) {
                    bestScore = score
                    targetIndex = i
                }
            }

            if (targetIndex >= 0) {
                const pages = migratedGroups[targetIndex].pages
                const panelsIndex = pages.indexOf(5)
                pages.splice(panelsIndex >= 0 ? panelsIndex + 1 : pages.length,
                    0, root.overviewPageIndex)
            }
        }

        // v8 upgrades the five legacy category labels even when the user
        // rearranged their pages. v7 only upgraded the exact default order,
        // leaving real installations displaying ESSENTIALS/APPEARANCE/SHELL.
        // Preserve existing relative page order and hidden page preferences.
        // Custom/renamed groups remain untouched.
        const legacyLabels = [
            Translation.tr("Essentials"), Translation.tr("Appearance"),
            Translation.tr("Shell"), Translation.tr("System"),
            Translation.tr("Reference")
        ]
        const untouchedStock = migratedGroups.length === legacyLabels.length
            && migratedGroups.every((group, index) =>
                group?.label === legacyLabels[index])

        if (sourceVersion < 8 && untouchedStock) {
            const defaults = SettingsPageRegistry.defaultCategories
            const owner = new Map()
            const grouped = defaults.map(group => ({
                label: group.label, pages: []
            }))
            for (let i = 0; i < defaults.length; i++)
                for (const page of defaults[i].pages)
                    owner.set(page, i)
            const seen = new Set(migratedHidden)
            for (const group of migratedGroups) {
                for (const page of group?.pages ?? []) {
                    if (seen.has(page) || !owner.has(page)) continue
                    grouped[owner.get(page)].pages.push(page)
                    seen.add(page)
                }
            }
            // Include pages introduced after the saved arrangement, in the
            // canonical group, instead of silently relegating them to More.
            for (const group of defaults) {
                for (const page of group.pages) {
                    if (seen.has(page)) continue
                    grouped[owner.get(page)].pages.push(page)
                    seen.add(page)
                }
            }
            root.save({ groups: grouped, hidden: migratedHidden })
            return
        }

        if (sourceVersion < 11 && Config.options?.panelFamily === "abyss") {
            const pages = [2,32,34,33,22,23,16].filter(i=>!migratedHidden.includes(i))
            let home = migratedGroups.find(group=>group?.label === "Abyss")
            if (!home) { home={label:"Abyss",pages:[]};migratedGroups.splice(1,0,home) }
            for (const group of migratedGroups) {
                if (!Array.isArray(group?.pages)) continue
                group.pages=group.pages.filter(i=>!pages.includes(i))
            }
            home.pages=pages
        }
        root.save({ groups: migratedGroups, hidden: migratedHidden })
    }

    function removePage(snapshot, categoryIndex: int, pageIndex: int, pageIdx: int): int {
        if (categoryIndex === -1) {
            const hiddenIndex = snapshot.hidden.indexOf(pageIdx)
            if (hiddenIndex < 0)
                return -1
            snapshot.hidden.splice(hiddenIndex, 1)
            return pageIdx
        }

        const pages = snapshot.groups[categoryIndex]?.pages
        if (!pages)
            return -1
        let actual = pageIndex
        if (actual < 0 || actual >= pages.length || pages[actual] !== pageIdx)
            actual = pages.indexOf(pageIdx)
        if (actual < 0)
            return -1
        return pages.splice(actual, 1)[0]
    }


    function _locationInSnapshot(snapshot, pageIdx: int): var {
        for (let categoryIndex = 0; categoryIndex < snapshot.groups.length; categoryIndex++) {
            const pages = snapshot.groups[categoryIndex]?.pages ?? []
            const pageIndex = pages.indexOf(pageIdx)
            if (pageIndex >= 0)
                return ({ categoryIndex: categoryIndex, pageIndex: pageIndex })
        }
        return null
    }

    function movePageFlat(pageIdx: int, direction: int): bool {
        const order = SettingsPageRegistry.navigationPageIndexes(false)
        const sourceFlat = order.indexOf(pageIdx)
        const targetFlat = Math.max(0, Math.min(order.length - 1, sourceFlat + direction))
        if (sourceFlat < 0 || targetFlat === sourceFlat)
            return false

        const targetPage = order[targetFlat]
        const state = root.snapshot()
        const source = root._locationInSnapshot(state, pageIdx)
        if (!source)
            return false

        const moved = root.removePage(state, source.categoryIndex, source.pageIndex, pageIdx)
        if (moved < 0)
            return false

        const target = root._locationInSnapshot(state, targetPage)
        if (!target)
            return false

        const insertIndex = target.pageIndex + (direction > 0 ? 1 : 0)
        state.groups[target.categoryIndex].pages.splice(insertIndex, 0, moved)
        root.save(state)
        return true
    }

    function hidePageById(pageIdx: int): bool {
        const state = root.snapshot()
        const source = root._locationInSnapshot(state, pageIdx)
        if (!source)
            return false
        return root.hidePage(source.categoryIndex, source.pageIndex, pageIdx)
    }

    function hidePage(categoryIndex: int, pageIndex: int, pageIdx: int): bool {
        if (categoryIndex < 0)
            return false
        const state = root.snapshot()
        const page = root.removePage(state, categoryIndex, pageIndex, pageIdx)
        if (page < 0)
            return false
        if (!state.hidden.includes(page))
            state.hidden.push(page)
        root.save(state)
        return true
    }

    function bestRestoreCategory(pageIdx: int, groups): int {
        const defaults = SettingsPageRegistry.defaultCategories
        let peers = []
        for (let i = 0; i < defaults.length; i++) {
            if (defaults[i].pages.includes(pageIdx)) {
                peers = defaults[i].pages
                break
            }
        }

        let bestIndex = groups.length > 0 ? 0 : -1
        let bestScore = -1
        for (let i = 0; i < groups.length; i++) {
            let score = 0
            for (let j = 0; j < groups[i].pages.length; j++)
                if (peers.includes(groups[i].pages[j]))
                    score++
            if (score > bestScore) {
                bestScore = score
                bestIndex = i
            }
        }
        return bestIndex
    }

    function restorePage(pageIdx: int): bool {
        const state = root.snapshot()
        const hiddenIndex = state.hidden.indexOf(pageIdx)
        if (hiddenIndex < 0)
            return false
        state.hidden.splice(hiddenIndex, 1)
        const target = root.bestRestoreCategory(pageIdx, state.groups)
        if (target < 0)
            state.groups.push({ label: Translation.tr("Essentials"), pages: [pageIdx] })
        else
            state.groups[target].pages.push(pageIdx)
        root.save(state)
        return true
    }





    function renameCategory(categoryIndex: int, label: string): bool {
        const nextLabel = String(label ?? "").trim()
        if (!nextLabel)
            return false
        const state = root.snapshot()
        if (categoryIndex < 0 || categoryIndex >= state.groups.length)
            return false
        if (state.groups[categoryIndex].label === nextLabel)
            return false
        state.groups[categoryIndex].label = nextLabel
        root.save(state)
        return true
    }

    function moveCategory(categoryIndex: int, direction: int): bool {
        const state = root.snapshot()
        const targetIndex = categoryIndex + direction
        if (categoryIndex < 0 || categoryIndex >= state.groups.length
                || targetIndex < 0 || targetIndex >= state.groups.length)
            return false
        const moved = state.groups.splice(categoryIndex, 1)[0]
        state.groups.splice(targetIndex, 0, moved)
        root.save(state)
        return true
    }

    function renamePage(pageIdx: int, name: string): bool {
        if (pageIdx < 0)
            return false
        const state = root.snapshot()
        if (!state.names || typeof state.names !== "object")
            state.names = ({})
        const nextName = String(name ?? "").trim()
        const page = SettingsPageRegistry.pages?.[pageIdx]
        const defaultName = String(page?.defaultName ?? page?.name ?? "").trim()
        const key = String(pageIdx)
        if (!nextName || nextName === defaultName) {
            if (!(key in state.names))
                return false
            delete state.names[key]
        } else {
            if (state.names[key] === nextName)
                return false
            state.names[key] = nextName
        }
        root.save(state)
        return true
    }

    function reset(): void {
        Config.setNestedValue("settingsUi.categories", "")
    }
}
