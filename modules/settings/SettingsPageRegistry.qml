pragma Singleton
import QtQuick
import Quickshell
import qs.services
import qs.modules.common
import "../common/PanelFamilyPolicy.js" as FamilyPolicy

/**
 * Public Settings registry facade.
 *
 * SettingsPageRegistryData keeps historical numeric gaps as null migration
 * markers only. Retired Settings components are not retained or instantiated.
 */
Singleton {
    id: root

    // Numeric compatibility gaps are defined once in SettingsPageRegistryData.
    // They remain migration inputs only and never become Settings pages.
    readonly property int retiredTlpPageIndex: 28
    readonly property int systemPageIndex: 1
    readonly property int barPageIndex: 2
    readonly property int panelsPageIndex: 5

    // A renderer-specific page is shown only for its active panel family.
    // Keep historical slots in the registry so stored indices remain stable.
    readonly property bool abyssFamily: Config.options?.panelFamily === "abyss"
    readonly property bool waffleFamily: Config.options?.panelFamily === "waffle"
    function isPageApplicable(index: int): bool {
        if (index < 0 || index >= root.pages.length
                || root.isHiddenLegacyIndex(index) || !root.pages[index]) return false
        if (index === 38) return true
        if (root.abyssFamily)
            return ![11,26].includes(index)
        if (root.waffleFamily)
            return index !== root.barPageIndex && index !== 16 && index !== 29 && index < 32
        return index !== 11 && index < 32
    }

    // Stable route keys survive page reordering and legacy numeric slot
    // retirement. The active Settings chrome navigates inside its own window
    // instead of spawning a second instance when a related-settings link runs.
    signal navigateRequested(int pageIndex, string section)
    function pageIndexForKey(key: string): int {
        const value = String(key ?? "").trim()
        if (!value) return -1
        if (root.abyssFamily && ["shell-layout","bar"].includes(value)) return value === "bar" ? 34 : root.barPageIndex
        return root.pages.findIndex((page, index) => page?.key === value
            && page?.devNavigationHidden !== true
            && root.isPageApplicable(index))
    }
    function navigateToKey(key: string, section: string): bool {
        // Resolve moved Services sections before a lazy page is loaded. An old
        // deep link must not depend on that page's retired search controls.
        const label = String(section ?? "").toLowerCase()
        const integration = key === "services" && (label.includes("todo")
            || label.includes("to-do") || label.includes("obsidian")
            || label.includes("zettelkasten") || label.includes("quick note")
            || label.includes("calendar"))
        const index = root.pageIndexForKey(integration ? "integrations" : key)
        if (index < 0) return false
        const route = FamilyPolicy.settingsRoute(Config.options?.panelFamily, index,
            root.abyssFamily && !section
                ? ({"shell-layout":"surface",bar:"bar"}[key] ?? "")
                : String(section ?? ""))
        root.navigateRequested(route.pageIndex, route.section)
        return true
    }
    property bool _legacyTlpPowerRedirectPending: false
    property bool _legacyDockStyleMigrationDone: false
    property bool _legacyUiLocaleMigrationDone: false
    property bool _legacyBarCornerStyleMigrationDone: false
    property bool _legacyBarBackgroundMigrationDone: false
    property bool _legacySidebarSurfaceMigrationDone: false
    property bool _legacyScreenEdgeShadowMigrationDone: false

    readonly property var pages: SettingsPageRegistryData.pages.map((page, index) => {
        if (!page)
            return null
        if (root.abyssFamily && index === root.barPageIndex)
            return Object.assign({},page,{key:"abyss",name:"Surface",icon:"water",
                desc:"Screen Edge, waves and surface presentation",component:"modules/settings/AbyssConfig.qml"})
        return page
    })

    function isHiddenLegacyIndex(index: int): bool {
        return SettingsPageRegistryData.legacyHiddenIndexes.includes(index)
            || (root.abyssFamily && index === 26)
    }

    readonly property var defaultCategories: SettingsPageRegistryData.defaultCategories.map(category => ({
        label:category.label,pages:category.pages.filter(index=>root.isPageApplicable(index))
    })).filter(category=>category.pages.length > 0)

    readonly property var categories: SettingsPageRegistryData.categories.map(category => ({
        label:category.label,pages:category.pages.filter(index=>root.isPageApplicable(index))
    })).filter(category=>category.label !== "More" || category.pages.length > 0)

    readonly property var hiddenPages: SettingsPageRegistryData.hiddenPages.filter(
        index => !root.isHiddenLegacyIndex(index))

    // Keep the complete saved page order for search, shortcuts and navigation
    // editing. SettingsHierarchy derives the compact parent/child presentation.
    function navigationPageIndexes(essentialOnly = false): var {
        const order = []
        const seen = new Set()
        for (const category of root.categories) {
            for (const index of category.pages) {
                const page = root.pages[index]
                if (!page || seen.has(index) || !root.isPageApplicable(index)
                        || (essentialOnly && page.essential !== true))
                    continue
                seen.add(index)
                order.push(index)
            }
        }
        return order
    }

    readonly property var _arrangement: ({ groups: root.categories, hidden: root.hiddenPages })

    function _migrateLegacyPersistentPage(): void {
        if (!Persistent.ready || !Persistent.states?.settings)
            return

        const current = Number(Persistent.states.settings.iiPage ?? -1)
        if (root.abyssFamily && current === 26) {
            Persistent.states.settings.iiPage = root.barPageIndex
            return
        }
        if (current === root.retiredTlpPageIndex) {
            Persistent.states.settings.iiPage = root.systemPageIndex
            root._legacyTlpPowerRedirectPending = true
            return
        }
        if (SettingsPageRegistryData.legacyHiddenIndexes.includes(current)) {
            Persistent.states.settings.iiPage = root.panelsPageIndex
            return
        }
    }

    function _migrateLegacyDockStyle(): void {
        if (root._legacyDockStyleMigrationDone || !Config.ready)
            return

        root._legacyDockStyleMigrationDone = true
        if ((Config.options?.dock?.style ?? "panel") !== "panel")
            Config.setNestedValue("dock.style", "panel")
    }

    function _migrateLegacyUiLocale(): void {
        if (root._legacyUiLocaleMigrationDone || !Config.ready)
            return

        root._legacyUiLocaleMigrationDone = true
        if ((Config.options?.language?.ui ?? "en_US") !== "en_US")
            Config.setNestedValue("language.ui", "en_US")
    }

    function _migrateLegacyBarCornerStyle(): void {
        if (root._legacyBarCornerStyleMigrationDone || !Config.ready)
            return

        root._legacyBarCornerStyleMigrationDone = true
        // cornerStyle is retained only as a compatibility field for persisted
        // configs. Hug is the sole supported Classic Bar surface geometry.
        if ((Config.options?.bar?.cornerStyle ?? 0) !== 0)
            Config.setNestedValue("bar.cornerStyle", 0)
    }

    function _migrateLegacyBarBackground(): void {
        if (root._legacyBarBackgroundMigrationDone || !Config.ready)
            return

        root._legacyBarBackgroundMigrationDone = true
        // The supported Hug Bar is a structural connected surface. A legacy
        // transparent-bar value removes both its endpoint shoulders and the
        // shared inward shadow, leaving popups visually detached.
        if (!(Config.options?.bar?.showBackground ?? true))
            Config.setNestedValue("bar.showBackground", true)
    }

    function _migrateLegacySidebarSurface(): void {
        if (root._legacySidebarSurfaceMigrationDone || !Config.ready)
            return

        root._legacySidebarSurfaceMigrationDone = true
        // Panel is the sole public Sidebar surface for v1.0. Keep the old
        // fields readable so persisted configs load, then normalize them away.
        if ((Config.options?.sidebar?.style ?? "panel") !== "panel")
            Config.setNestedValue("sidebar.style", "panel")
        if (Config.options?.sidebar?.cardStyle ?? false)
            Config.setNestedValue("sidebar.cardStyle", false)
    }

    function _migrateLegacyScreenEdgeShadow(): void {
        if (root._legacyScreenEdgeShadowMigrationDone || !Config.ready)
            return

        root._legacyScreenEdgeShadowMigrationDone = true
        const size = Number(Config.options?.appearance?.screenEdge?.shadow?.size ?? 15)
        const opacity = Number(Config.options?.appearance?.screenEdge?.shadow?.opacity ?? 0.70)

        // 12px / 24% was Hadalis' provisional shadow and is too weak to read on
        // dark wallpapers. Migrate only that exact legacy pair; any user-tuned
        // value is preserved. Caelestia's current ContentWindow uses blurMax=15
        // with 0.7 shadow alpha.
        if (size === 12 && Math.abs(opacity - 0.24) < 0.001) {
            Config.setNestedValue("appearance.screenEdge.shadow.size", 15)
            Config.setNestedValue("appearance.screenEdge.shadow.opacity", 0.70)
        }
    }

    function consumeLegacyTlpPowerRedirect(): bool {
        if (!root._legacyTlpPowerRedirectPending)
            return false
        root._legacyTlpPowerRedirectPending = false
        return true
    }

    function iconForPage(idx) {
        return (idx >= 0 && idx < root.pages.length)
            ? (root.pages[idx].icon || "settings") : "settings"
    }

    function searchIndex(): var {
        return SettingsPageRegistryData.searchIndex()
            .filter(entry => !root.isHiddenLegacyIndex(entry.pageIndex))
            .map(entry => {
                const route = FamilyPolicy.settingsRoute(Config.options?.panelFamily,entry.pageIndex,entry.section)
                if (route.pageIndex !== entry.pageIndex)
                    return Object.assign({},entry,route,{pageName:"Abyss"})
                if (root.abyssFamily && entry.pageIndex === root.barPageIndex)
                    return Object.assign({},entry,{pageName:"Abyss"})
                return entry
            })
    }

    Component.onCompleted: {
        root._migrateLegacyPersistentPage()
        root._migrateLegacyDockStyle()
        root._migrateLegacyUiLocale()
        root._migrateLegacyBarCornerStyle()
        root._migrateLegacyBarBackground()
        root._migrateLegacySidebarSurface()
        root._migrateLegacyScreenEdgeShadow()
    }

    Connections {
        target: Persistent
        function onReadyChanged(): void {
            if (Persistent.ready)
                root._migrateLegacyPersistentPage()
        }
    }

    Connections {
        target: Config
        function onReadyChanged(): void {
            if (Config.ready) {
                root._migrateLegacyDockStyle()
                root._migrateLegacyUiLocale()
                root._migrateLegacyBarCornerStyle()
                root._migrateLegacyBarBackground()
                root._migrateLegacySidebarSurface()
                root._migrateLegacyScreenEdgeShadow()
            }
        }
    }
}
