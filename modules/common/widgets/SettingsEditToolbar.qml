pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import "SettingsLayoutPolicy.js" as LayoutPolicy

// Edit Settings Layout: a 2-tier Abyss customization dock connected to the
// bottom Screen Edge. Modules is an integrated tier of this dock (never a
// floating popup and never inserted into ContentPage).
AbyssCustomizationDock {
    id: root
    objectName: "settingsEditToolbar"

    property Item targetPage: null

    property int pageIndex: root.targetPage?.settingsPageIndex ?? -1
    property string customTabId: root.targetPage?.customTabId ?? SettingsLayoutManager.activeCustomTabId
    property string activeSubTabKey: root.targetPage?.activeSubTabKey ?? ""
    property string activeSubTabLabel: root.targetPage?.activeSubTabLabel ?? ""
    property var baseSubTabs: root.targetPage?.baseSubTabSpecs ?? []
    property var effectiveSubTabs: root.targetPage?.effectiveSubTabSpecs ?? []
    signal selectSubTabRequested(string subTabKey)

    readonly property bool canMoveSubTabLeft: root.targetPage
        ? Boolean(root.targetPage.canMoveSubTabLeft)
        : (root.effectiveSubTabs.length > 1 && root.activeSubTabKey.length > 0)
    readonly property bool canMoveSubTabRight: root.targetPage
        ? Boolean(root.targetPage.canMoveSubTabRight)
        : (root.effectiveSubTabs.length > 1 && root.activeSubTabKey.length > 0)
    readonly property bool canRenameSubTab: root.targetPage
        ? Boolean(root.targetPage.canRenameActiveSubTab)
        : (root.effectiveSubTabs.length > 0 && root.activeSubTabKey.length > 0)
    readonly property bool canDeleteSubTab: root.targetPage
        ? Boolean(root.targetPage.canDeleteActiveSubTab)
        : (root.effectiveSubTabs.length > 1 && root.activeSubTabKey.length > 0)
    readonly property bool hasMultipleSubTabs: root.targetPage
        ? ((root.targetPage._subTabItems?.length ?? 0) > 1 || root.effectiveSubTabs.length > 1)
        : (root.effectiveSubTabs.length > 1)
    readonly property bool hasSubTabs: Boolean(
        (root.targetPage?.effectiveSubTabSpecs?.length ?? 0) > 0
        || (root.targetPage?._subTabItems?.length ?? 0) > 0
    )

    readonly property var pageLayoutConfig: SettingsLayoutManager.getPageLayoutConfig(root.pageIndex, root.customTabId)
    readonly property string layoutMode: root.pageLayoutConfig?.layoutMode ?? "bento"
    readonly property real leftColumnRatio: root.pageLayoutConfig?.leftColumnRatio ?? 0.5

    property string inlinePromptMode: "" // "" | "new-subtab" | "rename-subtab" | "new-sidebar-tab" | "rename-sidebar-tab"
    property bool showModuleDrawer: false
    // Last non-Modules tier, restored when the Modules tier is closed (Escape / toggle).
    property string lastControlTab: "layout"
    readonly property string activeDockTab: root.activeTab
    property string moduleFilter: "all" // "all" | "current" | "hidden" | "other"
    readonly property bool compactChips: root.width > 0 && root.width < 1080

    // ── Dock chrome contract ──
    visible: SettingsLayoutManager.editMode
    contentPreferredWidth: Math.max(820, root.activeTab === "modules"
        ? Math.ceil(filterGrid.implicitWidth + 24 + galleryRow.implicitWidth)
        : (root.activeTab === "tabs"
            ? Math.ceil(tabsRow.implicitWidth + 16)
            : Math.ceil(layoutRow.implicitWidth + 16)))
    tabs: [
        {
            key: "modules",
            label: Translation.tr("Modules"),
            icon: "widgets",
            badge: root.hiddenModules.length > 0 ? root.hiddenModules.length : null,
            objectName: "modulesDrawerChipButton",
            tooltipText: Translation.tr("Browse modules: hide, unhide, or move modules onto this tab")
        },
        {
            key: "layout",
            label: Translation.tr("Layout"),
            icon: "dashboard_customize",
            objectName: "settingsDockTab_layout",
            tooltipText: Translation.tr("Bento or Free Canvas, column split, grid snap and resets")
        },
        {
            key: "tabs",
            label: Translation.tr("Tabs"),
            icon: "tab",
            objectName: "settingsDockTab_tabs",
            tooltipText: Translation.tr("Create, reorder, rename and delete sub-tabs and sidebar tabs")
        }
    ]
    activeTab: "layout"
    autoSwitchTab: false
    trayExpanded: true
    trayHeight: 104
    canUndo: SettingsLayoutManager.canUndo
    canRedo: SettingsLayoutManager.canRedo
    showUndo: true
    showRedo: true
    undoObjectName: "settingsEditUndoButton"
    redoObjectName: "settingsEditRedoButton"
    showSearch: root.activeTab === "modules"
    searchPlaceholder: Translation.tr("Search modules or pages...")
    searchObjectName: "settingsModuleSearchInput"
    showCancel: true
    doneObjectName: "settingsEditDoneButton"
    cancelObjectName: "settingsEditCancelButton"
    headerOverlayActive: root.inlinePromptMode.length > 0

    onUndoClicked: SettingsLayoutManager.undo()
    onRedoClicked: SettingsLayoutManager.redo()
    onDoneClicked: SettingsLayoutManager.commitEditMode()
    onCancelClicked: SettingsLayoutManager.cancelEditMode()
    onTabClicked: key => root.selectDockTab(key)

    function selectDockTab(key: string): void {
        if (key === "modules") {
            if (root.showModuleDrawer) {
                root.showModuleDrawer = false;
            } else {
                root.showModuleDrawer = true;
                root.activeTab = "modules";
            }
            return;
        }
        root.lastControlTab = key;
        if (root.showModuleDrawer)
            root.showModuleDrawer = false;
        root.activeTab = key;
    }

    onShowModuleDrawerChanged: {
        if (SettingsLayoutManager.moduleDrawerOpen !== root.showModuleDrawer)
            SettingsLayoutManager.moduleDrawerOpen = root.showModuleDrawer;
        root.activeTab = root.showModuleDrawer ? "modules" : root.lastControlTab;
    }

    function _setPromptMode(mode: string): void {
        root.inlinePromptMode = mode;
        if (SettingsLayoutManager.activePromptMode !== mode)
            SettingsLayoutManager.activePromptMode = mode;
    }

    Connections {
        target: SettingsLayoutManager
        function onModuleDrawerOpenChanged() {
            if (root.showModuleDrawer !== SettingsLayoutManager.moduleDrawerOpen)
                root.showModuleDrawer = SettingsLayoutManager.moduleDrawerOpen;
        }
        function onRequestedPromptModeChanged() {
            const req = String(SettingsLayoutManager.requestedPromptMode || "");
            if (req.length > 0) {
                root._setPromptMode(req);
                SettingsLayoutManager.requestedPromptMode = "";
                if (req === "rename-subtab") {
                    promptInput.text = root.activeSubTabLabel || root.activeSubTabKey;
                } else if (req === "rename-sidebar-tab") {
                    const ct = SettingsLayoutManager.getCustomTab(root.customTabId);
                    promptInput.text = ct ? ct.label : "";
                } else {
                    promptInput.text = "";
                }
                Qt.callLater(() => promptInput.forceActiveFocus());
            }
        }
        function onActivePromptModeChanged() {
            const cur = String(SettingsLayoutManager.activePromptMode || "");
            if (cur !== root.inlinePromptMode) {
                root.inlinePromptMode = cur;
                if (cur.length === 0)
                    promptInput.text = "";
            }
        }
        function onEditModeChanged() {
            if (!SettingsLayoutManager.editMode) {
                root._setPromptMode("");
                root.showModuleDrawer = false;
                root.searchText = "";
                root.moduleFilter = "all";
            }
        }
    }

    // ── Module catalogue (shared with the old picker semantics) ──
    function _matchesSearch(mod: var): bool {
        const q = String(root.searchText ?? "").trim().toLowerCase();
        if (q.length === 0)
            return true;
        const title = String(mod?.title ?? "").toLowerCase();
        const page = String(mod?.originLabel ?? "").toLowerCase();
        const sub = String(mod?.originSubTab ?? "").toLowerCase();
        return title.includes(q) || page.includes(q) || sub.includes(q);
    }

    function _isHostedOnCurrentTarget(mod: var): bool {
        if (!mod || mod.visible === false)
            return false;
        const modId = String(mod.moduleId ?? "");
        if (!modId)
            return false;
        if (SettingsLayoutManager.isModuleHostedOnTarget(
            modId, root.pageIndex, root.customTabId, root.activeSubTabKey, root.hasSubTabs
        )) {
            return true;
        }
        if (root.customTabId.length === 0 && mod.originPageIndex === root.pageIndex) {
            if (SettingsLayoutManager.isModuleMovedAway(
                modId, root.pageIndex, "", root.activeSubTabKey, root.hasSubTabs
            )) {
                return false;
            }
            const liveCard = SettingsLayoutManager.getLiveCard(modId);
            if (liveCard && liveCard._cardSubTabActive !== undefined)
                return Boolean(liveCard._cardSubTabActive);
            if (!root.hasSubTabs || !root.activeSubTabKey || !mod.originSubTab)
                return true;
            return mod.originSubTab === root.activeSubTabKey;
        }
        return false;
    }

    function _isAssignedToCurrentTargetWhenUnhidden(mod: var): bool {
        if (!mod)
            return false;
        const tCustom = String(mod.targetCustomTabId ?? "");
        if (root.customTabId.length > 0)
            return tCustom === root.customTabId;
        if (tCustom.length > 0)
            return false;
        const effectivePage = mod.targetPageIndex >= 0 ? mod.targetPageIndex : mod.originPageIndex;
        if (effectivePage !== root.pageIndex)
            return false;
        if (!root.hasSubTabs || !root.activeSubTabKey)
            return true;
        const effectiveSub = String(mod.targetSubTab || mod.originSubTab || "");
        return effectiveSub.length === 0 || effectiveSub === root.activeSubTabKey;
    }

    readonly property var _knownModules: (root.visible && SettingsLayoutManager.editMode)
        ? SettingsLayoutManager.getAllKnownModules() : []

    readonly property var currentModules: {
        const out = [];
        const list = root._knownModules;
        for (let i = 0; i < list.length; i++) {
            const m = list[i];
            if (!root._isHostedOnCurrentTarget(m))
                continue;
            const isForeign = (root.customTabId.length > 0)
                || (m.originPageIndex >= 0 && m.originPageIndex !== root.pageIndex)
                || (root.hasSubTabs && Boolean(m.targetSubTab) && Boolean(m.originSubTab) && m.targetSubTab !== m.originSubTab);
            out.push(Object.assign({}, m, {
                status: "current",
                originLabel: SettingsLayoutManager.pageNameForIndex(m.originPageIndex),
                isForeign: isForeign
            }));
        }
        return out;
    }

    readonly property var hiddenModules: {
        const out = [];
        const list = root._knownModules;
        for (let i = 0; i < list.length; i++) {
            const m = list[i];
            if (m.visible !== false)
                continue;
            out.push(Object.assign({}, m, {
                status: "hidden",
                originLabel: SettingsLayoutManager.pageNameForIndex(m.originPageIndex),
                belongsHere: root._isAssignedToCurrentTargetWhenUnhidden(m)
            }));
        }
        return out;
    }

    readonly property var otherModules: {
        const out = [];
        const list = root._knownModules;
        for (let i = 0; i < list.length; i++) {
            const m = list[i];
            if (m.visible === false || root._isHostedOnCurrentTarget(m))
                continue;
            out.push(Object.assign({}, m, {
                status: "other",
                originLabel: SettingsLayoutManager.pageNameForIndex(m.originPageIndex),
                subTabPretty: m.originSubTab ? LayoutPolicy.humanizeModuleTitle("", m.originSubTab) : ""
            }));
        }
        out.sort((a, b) => a.originLabel.localeCompare(b.originLabel) || a.title.localeCompare(b.title));
        return out;
    }

    readonly property var filteredModules: {
        let source;
        if (root.moduleFilter === "current")
            source = root.currentModules;
        else if (root.moduleFilter === "hidden")
            source = root.hiddenModules;
        else if (root.moduleFilter === "other")
            source = root.otherModules;
        else
            source = root.currentModules.concat(root.hiddenModules, root.otherModules);
        return source.filter(m => root._matchesSearch(m));
    }

    function moveHere(moduleId: string): void {
        SettingsLayoutManager.moveModuleToTarget(moduleId, {
            targetPageIndex: root.customTabId.length > 0 ? -1 : root.pageIndex,
            targetCustomTabId: root.customTabId,
            targetSubTab: root.activeSubTabKey
        });
    }

    function returnToOrigin(mod: var): void {
        if (!mod || !mod.moduleId)
            return;
        SettingsLayoutManager.moveModuleToTarget(mod.moduleId, {
            targetPageIndex: mod.originPageIndex,
            targetCustomTabId: "",
            targetSubTab: mod.originSubTab || ""
        });
    }

    function unhideAll(): void {
        const hidden = root.hiddenModules;
        for (let i = 0; i < hidden.length; i++)
            SettingsLayoutManager.setModuleVisible(hidden[i].moduleId, true);
    }

    // Badge (+ / ✓) action: add onto this tab, or take off this tab.
    function toggleModule(mod: var): void {
        if (!mod || !mod.moduleId)
            return;
        if (mod.status === "current") {
            if (mod.isForeign)
                root.returnToOrigin(mod);
            else
                SettingsLayoutManager.setModuleVisible(mod.moduleId, false);
        } else if (mod.status === "hidden" && mod.belongsHere) {
            SettingsLayoutManager.setModuleVisible(mod.moduleId, true);
        } else {
            // Moving a module onto the target also restores its visibility.
            root.moveHere(mod.moduleId);
        }
    }

    // Tile action: find a module already on this tab, otherwise add it here.
    function activateModule(mod: var): void {
        if (!mod || !mod.moduleId)
            return;
        if (mod.status === "current")
            SettingsLayoutManager.selectedModuleId = mod.moduleId;
        else
            root.toggleModule(mod);
    }

    function _submitInlinePrompt() {
        const text = String(promptInput.text ?? "").trim();
        if (!text) {
            root._setPromptMode("");
            return;
        }
        if (root.inlinePromptMode === "new-subtab") {
            if (root.targetPage && typeof root.targetPage.createNewSubTab === "function") {
                const created = root.targetPage.createNewSubTab(text);
                if (created)
                    root.selectSubTabRequested(created);
            } else {
                const newKey = SettingsLayoutManager.createSubTab(
                    root.pageIndex,
                    root.customTabId,
                    text,
                    "tab",
                    root.baseSubTabs
                );
                if (newKey)
                    root.selectSubTabRequested(newKey);
            }
        } else if (root.inlinePromptMode === "rename-subtab") {
            if (root.targetPage && typeof root.targetPage.renameActiveSubTab === "function") {
                root.targetPage.renameActiveSubTab(text);
            } else if (root.activeSubTabKey) {
                SettingsLayoutManager.renameSubTab(
                    root.pageIndex,
                    root.customTabId,
                    root.activeSubTabKey,
                    text
                );
            }
        } else if (root.inlinePromptMode === "new-sidebar-tab") {
            SettingsLayoutManager.createCustomTab(text, "dashboard_customize", 0);
        } else if (root.inlinePromptMode === "rename-sidebar-tab" && root.customTabId) {
            SettingsLayoutManager.renameCustomTab(root.customTabId, text, "");
        }
        promptInput.text = "";
        root._setPromptMode("");
    }

    function _togglePrompt(mode: string, initialText: string): void {
        if (root.inlinePromptMode === mode) {
            root._setPromptMode("");
            return;
        }
        root._setPromptMode(mode);
        promptInput.text = initialText;
        Qt.callLater(() => promptInput.forceActiveFocus());
    }

    // ── Shared Abyss pill chip ──
    component ToolbarChip: Rectangle {
        id: chip
        property string icon: ""
        property string label: ""
        property string tooltipText: ""
        property bool activeState: false
        property bool dangerState: false
        property bool chipEnabled: true
        signal clicked()

        implicitHeight: 28
        implicitWidth: chipRow.implicitWidth + (chip.label.length > 0 ? 18 : 12)
        radius: 14
        opacity: chip.chipEnabled ? 1.0 : 0.38
        color: chip.dangerState
            ? (chipMouse.containsMouse && chip.chipEnabled ? Qt.alpha(Appearance.colors.colError, 0.24) : Qt.alpha(Appearance.colors.colError, 0.12))
            : (chip.activeState
                ? Appearance.colors.colPrimary
                : (chipMouse.containsMouse && chip.chipEnabled
                    ? Appearance.colors.colLayer2Hover
                    : Qt.alpha(Appearance.colors.colLayer2, 0.62)))
        border.width: 1
        border.color: chip.dangerState
            ? Qt.alpha(Appearance.colors.colError, 0.45)
            : (chip.activeState
                ? Appearance.colors.colPrimary
                : Qt.alpha(Appearance.colors.colOutlineVariant, 0.3))

        Behavior on color {
            enabled: Appearance.animationsEnabled
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 4

            MaterialSymbol {
                visible: chip.icon.length > 0
                anchors.verticalCenter: parent.verticalCenter
                text: chip.icon
                iconSize: 15
                color: chip.dangerState
                    ? Appearance.colors.colError
                    : (chip.activeState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)
            }

            StyledText {
                visible: chip.label.length > 0
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: Text.AlignVCenter
                text: chip.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: chip.activeState ? Font.DemiBold : Font.Medium
                color: chip.dangerState
                    ? Appearance.colors.colError
                    : (chip.activeState ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1)
            }
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            enabled: chip.chipEnabled
            hoverEnabled: true
            cursorShape: chip.chipEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: chip.clicked()
        }

        StyledToolTip {
            extraVisibleCondition: chipMouse.containsMouse && chip.tooltipText.length > 0
            text: chip.tooltipText
        }
    }

    // A labelled group of chips inside a tray tier.
    component ControlGroup: Column {
        id: group
        property string title: ""
        default property alias chips: groupRow.data
        spacing: 6

        StyledText {
            text: group.title
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: Appearance.colors.colSubtext
        }

        Row {
            id: groupRow
            spacing: 5
        }
    }

    component GroupDivider: Rectangle {
        width: 1
        height: 46
        color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.3)
    }

    // ── Top strip quick toggles ──
    trailingControls: [
        ToolbarChip {
            objectName: "layoutModeQuickChipButton"
            icon: root.layoutMode === "canvas" ? "dashboard_customize" : "grid_view"
            label: root.compactChips ? "" : (root.layoutMode === "canvas" ? Translation.tr("Free Canvas") : Translation.tr("Bento Grid"))
            tooltipText: root.layoutMode === "canvas"
                ? Translation.tr("Freeform 2D Canvas mode (click to switch to 2-Column Bento Grid)")
                : Translation.tr("2-Column Bento Grid mode (click to switch to Freeform 2D Canvas)")
            activeState: root.layoutMode === "canvas"
            onClicked: SettingsLayoutManager.togglePageLayoutMode(root.pageIndex, root.customTabId)
        },
        ToolbarChip {
            objectName: "innerEditModeChipButton"
            icon: "tune"
            label: root.compactChips ? "" : Translation.tr("Rows & Sliders")
            tooltipText: Translation.tr("Toggle inner item & slider customization handles (reorder rows, rotate sliders)")
            activeState: SettingsLayoutManager.innerEditMode
            onClicked: SettingsLayoutManager.innerEditMode = !SettingsLayoutManager.innerEditMode
        },
        ToolbarChip {
            objectName: "resetPageModulesChipButton"
            icon: "fit_screen"
            label: root.compactChips ? "" : Translation.tr("Reset Page")
            tooltipText: Translation.tr("Reset all module sizes and column placements on this page to default")
            onClicked: SettingsLayoutManager.autoFitPageModules(root.pageIndex, root.customTabId)
        }
    ]

    // ── Inline naming prompt (replaces the top strip in place, same height) ──
    headerOverlay: [
        Rectangle {
            anchors.fill: parent
            anchors.topMargin: 5
            anchors.bottomMargin: 5
            radius: 15
            color: Qt.alpha(Appearance.colors.colLayer2, 0.92)
            border.width: 1
            border.color: Appearance.colors.colPrimary

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 4
                spacing: 8

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    text: root.inlinePromptMode.includes("rename") ? "edit" : "add_circle"
                    iconSize: 16
                    color: Appearance.colors.colPrimary
                }

                TextInput {
                    id: promptInput
                    objectName: "settingsEditPromptInput"
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.small
                    selectByMouse: true
                    clip: true
                    onAccepted: root._submitInlinePrompt()
                    Keys.onEscapePressed: event => {
                        promptInput.text = "";
                        root._setPromptMode("");
                        event.accepted = true;
                    }

                    StyledText {
                        visible: promptInput.text.length === 0
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.inlinePromptMode === "new-subtab"
                            ? Translation.tr("Enter new Sub-Tab name...")
                            : (root.inlinePromptMode === "new-sidebar-tab"
                                ? Translation.tr("Enter new Sidebar Tab name...")
                                : Translation.tr("Enter new Tab name..."))
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colSubtext
                    }
                }

                ToolbarChip {
                    objectName: "settingsEditPromptSaveButton"
                    Layout.alignment: Qt.AlignVCenter
                    icon: "check"
                    label: Translation.tr("Save")
                    tooltipText: Translation.tr("Confirm name")
                    activeState: true
                    onClicked: root._submitInlinePrompt()
                }

                ToolbarChip {
                    objectName: "settingsEditPromptCancelButton"
                    Layout.alignment: Qt.AlignVCenter
                    icon: "close"
                    label: Translation.tr("Cancel")
                    tooltipText: Translation.tr("Cancel naming")
                    onClicked: {
                        promptInput.text = "";
                        root._setPromptMode("");
                    }
                }
            }
        }
    ]

    // ── Tier 2: Modules gallery / Layout controls / Tabs controls ──
    Item {
        id: trayViews
        anchors.fill: parent

        // Modules: filter pills + horizontal miniature module gallery
        Item {
            id: modulesView
            objectName: "settingsDockModulesTier"
            anchors.fill: parent
            visible: root.activeTab === "modules"

            Grid {
                id: filterGrid
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                columns: 2
                rowSpacing: 5
                columnSpacing: 5

                Repeater {
                    model: [
                        { key: "all", label: Translation.tr("All"), count: root.currentModules.length + root.hiddenModules.length + root.otherModules.length },
                        { key: "current", label: Translation.tr("This Tab"), count: root.currentModules.length },
                        { key: "hidden", label: Translation.tr("Hidden"), count: root.hiddenModules.length },
                        { key: "other", label: Translation.tr("Other Pages"), count: root.otherModules.length }
                    ]
                    delegate: Rectangle {
                        id: filterPill
                        required property var modelData
                        readonly property bool selected: root.moduleFilter === filterPill.modelData.key
                        objectName: "settingsModuleFilter_" + filterPill.modelData.key
                        width: 92
                        height: 24
                        radius: 12
                        color: filterPill.selected
                            ? Appearance.colors.colPrimaryContainer
                            : (filterMouse.containsMouse ? Appearance.colors.colLayer2Hover : Qt.alpha(Appearance.colors.colLayer2, 0.55))
                        border.width: 1
                        border.color: filterPill.selected
                            ? Qt.alpha(Appearance.colors.colPrimary, 0.5)
                            : Qt.alpha(Appearance.colors.colOutlineVariant, 0.24)

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: filterPill.modelData.label
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: filterPill.selected ? Font.DemiBold : Font.Medium
                                color: filterPill.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: String(filterPill.modelData.count)
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.weight: Font.DemiBold
                                color: filterPill.selected ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext
                            }
                        }

                        MouseArea {
                            id: filterMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.moduleFilter = filterPill.modelData.key
                        }
                    }
                }

                ToolbarChip {
                    objectName: "unhideAllModulesButton"
                    visible: root.hiddenModules.length > 0
                    width: 92
                    implicitHeight: 24
                    icon: "visibility"
                    label: Translation.tr("Unhide All")
                    tooltipText: Translation.tr("Restore visibility for all hidden modules")
                    onClicked: root.unhideAll()
                }
            }

            Rectangle {
                id: modulesDivider
                anchors.left: filterGrid.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: parent.height - 16
                color: Qt.alpha(Appearance.colors.colOutlineVariant, 0.26)
            }

            Flickable {
                id: moduleGallery
                objectName: "settingsModuleGallery"
                anchors.left: modulesDivider.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.topMargin: 4
                contentWidth: galleryRow.implicitWidth
                contentHeight: height
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Connections {
                    target: root
                    function onSearchTextChanged() { moduleGallery.contentX = 0; }
                    function onModuleFilterChanged() { moduleGallery.contentX = 0; }
                }

                // The mouse wheel scrolls the gallery sideways.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: event => {
                        const horizontalDominant = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y);
                        const delta = horizontalDominant ? event.angleDelta.x : event.angleDelta.y;
                        const pixel = (event.pixelDelta.x !== 0 || event.pixelDelta.y !== 0)
                            ? (Math.abs(event.pixelDelta.x) > Math.abs(event.pixelDelta.y) ? event.pixelDelta.x : event.pixelDelta.y)
                            : delta / 120 * 160;
                        const maxX = Math.max(0, moduleGallery.contentWidth - moduleGallery.width);
                        moduleGallery.contentX = Math.max(0, Math.min(maxX, moduleGallery.contentX - pixel));
                    }
                }

                Row {
                    id: galleryRow
                    spacing: 10

                    Repeater {
                        // Tiles are only instantiated while the Modules tier is shown.
                        model: root.activeTab === "modules" ? root.filteredModules : []

                        delegate: AbyssCustomizationTile {
                            id: moduleTile
                            required property var modelData
                            readonly property string status: String(moduleTile.modelData.status ?? "")
                            objectName: "settingsModuleTile_" + moduleTile.modelData.moduleId
                            tileId: String(moduleTile.modelData.moduleId ?? "")
                            title: String(moduleTile.modelData.title ?? "")
                            subtitle: moduleTile.status === "current"
                                ? (moduleTile.modelData.isForeign
                                    ? Translation.tr("From %1").arg(moduleTile.modelData.originLabel)
                                    : Translation.tr("On this tab"))
                                : (moduleTile.status === "hidden"
                                    ? Translation.tr("Hidden · %1").arg(moduleTile.modelData.originLabel)
                                    : (moduleTile.modelData.subTabPretty
                                        ? `${moduleTile.modelData.originLabel} · ${moduleTile.modelData.subTabPretty}`
                                        : String(moduleTile.modelData.originLabel ?? "")))
                            icon: String(moduleTile.modelData.icon || "tune")
                            accentColor: moduleTile.status === "hidden"
                                ? Appearance.colors.colSubtext
                                : Appearance.colors.colPrimary
                            active: moduleTile.status === "current"
                            selected: SettingsLayoutManager.selectedModuleId === moduleTile.tileId
                            separateBadgeClick: true
                            tileWidth: 128
                            previewHeight: 60
                            tooltipText: moduleTile.status === "current"
                                ? (moduleTile.modelData.isForeign
                                    ? Translation.tr("Click to select · ✓ returns '%1' to %2").arg(moduleTile.title).arg(moduleTile.modelData.originLabel)
                                    : Translation.tr("Click to select · ✓ hides '%1' from this tab").arg(moduleTile.title))
                                : Translation.tr("Add '%1' to this tab").arg(moduleTile.title)
                            onClicked: root.activateModule(moduleTile.modelData)
                            onBadgeClicked: root.toggleModule(moduleTile.modelData)

                            // Miniature Bento card skeleton
                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: Qt.alpha(moduleTile.accentColor, moduleTile.active ? 0.10 : 0.14)
                                border.width: 1
                                border.color: Qt.alpha(moduleTile.accentColor, 0.22)

                                Column {
                                    anchors.fill: parent
                                    anchors.margins: 7
                                    anchors.rightMargin: 24
                                    spacing: 5

                                    Row {
                                        spacing: 5

                                        Rectangle {
                                            width: 16
                                            height: 16
                                            radius: 5
                                            color: Qt.alpha(moduleTile.accentColor, 0.24)

                                            MaterialSymbol {
                                                anchors.centerIn: parent
                                                text: moduleTile.icon
                                                iconSize: 11
                                                fill: 1
                                                color: moduleTile.accentColor
                                            }
                                        }

                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 40
                                            height: 5
                                            radius: 2.5
                                            color: Qt.alpha(Appearance.colors.colOnLayer1, 0.5)
                                        }
                                    }

                                    Repeater {
                                        model: 2
                                        delegate: Row {
                                            id: skeletonRow
                                            required property int index
                                            spacing: 6

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: skeletonRow.index === 0 ? 34 : 26
                                                height: 4
                                                radius: 2
                                                color: Qt.alpha(Appearance.colors.colSubtext, 0.38)
                                            }

                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: skeletonRow.index === 0 ? 14 : 30
                                                height: skeletonRow.index === 0 ? 8 : 4
                                                radius: height / 2
                                                color: Qt.alpha(moduleTile.accentColor, skeletonRow.index === 0 ? 0.55 : 0.4)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                anchors.centerIn: moduleGallery
                visible: root.filteredModules.length === 0
                text: String(root.searchText ?? "").trim().length > 0
                    ? Translation.tr("No module matches \u201c%1\u201d").arg(String(root.searchText).trim())
                    : (root.moduleFilter === "hidden"
                        ? Translation.tr("No hidden modules")
                        : Translation.tr("No modules here yet"))
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }
        }

        // Layout: arrangement mode, column split, grid snap, resets
        Flickable {
            id: layoutView
            objectName: "settingsDockLayoutTier"
            anchors.fill: parent
            visible: root.activeTab === "layout"
            contentWidth: layoutRow.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: layoutRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                ControlGroup {
                    title: Translation.tr("Arrangement")

                    ToolbarChip {
                        objectName: "settingsLayoutBentoChip"
                        icon: "grid_view"
                        label: Translation.tr("Bento Grid")
                        tooltipText: Translation.tr("Arrange modules in a 2-column Bento grid")
                        activeState: root.layoutMode !== "canvas"
                        onClicked: if (root.layoutMode === "canvas") SettingsLayoutManager.togglePageLayoutMode(root.pageIndex, root.customTabId)
                    }

                    ToolbarChip {
                        objectName: "settingsLayoutCanvasChip"
                        icon: "dashboard_customize"
                        label: Translation.tr("Free Canvas")
                        tooltipText: Translation.tr("Place modules freely on a 2D canvas")
                        activeState: root.layoutMode === "canvas"
                        onClicked: if (root.layoutMode !== "canvas") SettingsLayoutManager.togglePageLayoutMode(root.pageIndex, root.customTabId)
                    }
                }

                GroupDivider {}

                ControlGroup {
                    title: Translation.tr("Column split")

                    Repeater {
                        model: [0.5, 0.62, 0.38, 0.7]
                        delegate: ToolbarChip {
                            required property var modelData
                            objectName: "settingsColumnRatioChip_" + Math.round(modelData * 100)
                            label: `${Math.round(modelData * 100)}/${Math.round((1 - modelData) * 100)}`
                            tooltipText: Translation.tr("Set Left / Right Bento column width ratio (or drag the center split bar)")
                            chipEnabled: root.layoutMode !== "canvas"
                            activeState: Math.abs(root.leftColumnRatio - modelData) < 0.03
                            onClicked: SettingsLayoutManager.setLeftColumnRatio(root.pageIndex, root.customTabId, modelData)
                        }
                    }
                }

                GroupDivider {}

                ControlGroup {
                    title: Translation.tr("Snap grid")

                    Repeater {
                        model: [0, 8, 16, 24]
                        delegate: ToolbarChip {
                            required property var modelData
                            objectName: "settingsSnapChip_" + modelData
                            label: modelData === 0 ? Translation.tr("Off") : `${modelData}px`
                            tooltipText: modelData === 0
                                ? Translation.tr("Disable grid snapping")
                                : Translation.tr("Snap module edges to a %1px grid").arg(modelData)
                            activeState: modelData === 0
                                ? !SettingsLayoutManager.snapEnabled
                                : (SettingsLayoutManager.snapEnabled && SettingsLayoutManager.gridSize === modelData)
                            onClicked: {
                                if (modelData === 0) {
                                    SettingsLayoutManager.snapEnabled = false;
                                } else {
                                    SettingsLayoutManager.snapEnabled = true;
                                    SettingsLayoutManager.gridSize = modelData;
                                }
                            }
                        }
                    }
                }

                GroupDivider {}

                ControlGroup {
                    title: Translation.tr("Reset")

                    ToolbarChip {
                        objectName: "settingsLayoutResetPageChip"
                        icon: "fit_screen"
                        label: Translation.tr("Reset Page")
                        tooltipText: Translation.tr("Reset all module sizes and column placements on this page to default")
                        onClicked: SettingsLayoutManager.autoFitPageModules(root.pageIndex, root.customTabId)
                    }

                    ToolbarChip {
                        objectName: "resetAllLayoutsChipButton"
                        icon: "restart_alt"
                        label: Translation.tr("Reset All")
                        tooltipText: Translation.tr("Reset all Settings layouts and custom tabs to default")
                        dangerState: true
                        onClicked: SettingsLayoutManager.resetAll()
                    }
                }
            }
        }

        // Tabs: sub-tab and sidebar-tab management
        Flickable {
            id: tabsView
            objectName: "settingsDockTabsTier"
            anchors.fill: parent
            visible: root.activeTab === "tabs"
            contentWidth: tabsRow.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: tabsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                ControlGroup {
                    title: root.activeSubTabLabel.length > 0
                        ? Translation.tr("Sub-tab · %1").arg(root.activeSubTabLabel)
                        : Translation.tr("Sub-tab")

                    ToolbarChip {
                        objectName: "addCustomSubTabChipButton"
                        icon: "add"
                        label: Translation.tr("Sub-Tab")
                        tooltipText: Translation.tr("Add a new sub-tab to the current page")
                        activeState: root.inlinePromptMode === "new-subtab"
                        onClicked: root._togglePrompt("new-subtab", "")
                    }

                    ToolbarChip {
                        objectName: "moveSubTabLeftButton"
                        icon: "chevron_left"
                        label: Translation.tr("Move Left")
                        tooltipText: root.canMoveSubTabLeft
                            ? Translation.tr("Move active sub-tab (%1) one position to the left").arg(root.activeSubTabLabel || root.activeSubTabKey)
                            : Translation.tr("Active sub-tab is already at the leftmost position")
                        chipEnabled: root.hasMultipleSubTabs && root.canMoveSubTabLeft
                        onClicked: {
                            if (root.targetPage && typeof root.targetPage.reorderActiveSubTab === "function") {
                                root.targetPage.reorderActiveSubTab(-1);
                            } else {
                                SettingsLayoutManager.reorderSubTab(
                                    root.pageIndex,
                                    root.customTabId,
                                    root.activeSubTabKey,
                                    -1,
                                    root.baseSubTabs
                                );
                            }
                        }
                    }

                    ToolbarChip {
                        objectName: "moveSubTabRightButton"
                        icon: "chevron_right"
                        label: Translation.tr("Move Right")
                        tooltipText: root.canMoveSubTabRight
                            ? Translation.tr("Move active sub-tab (%1) one position to the right").arg(root.activeSubTabLabel || root.activeSubTabKey)
                            : Translation.tr("Active sub-tab is already at the rightmost position")
                        chipEnabled: root.hasMultipleSubTabs && root.canMoveSubTabRight
                        onClicked: {
                            if (root.targetPage && typeof root.targetPage.reorderActiveSubTab === "function") {
                                root.targetPage.reorderActiveSubTab(1);
                            } else {
                                SettingsLayoutManager.reorderSubTab(
                                    root.pageIndex,
                                    root.customTabId,
                                    root.activeSubTabKey,
                                    1,
                                    root.baseSubTabs
                                );
                            }
                        }
                    }

                    ToolbarChip {
                        objectName: "renameSubTabChipButton"
                        icon: "edit"
                        label: Translation.tr("Rename")
                        tooltipText: Translation.tr("Rename active sub-tab (%1)").arg(root.activeSubTabLabel || root.activeSubTabKey)
                        chipEnabled: root.canRenameSubTab
                        activeState: root.inlinePromptMode === "rename-subtab"
                        onClicked: root._togglePrompt("rename-subtab", root.activeSubTabLabel || root.activeSubTabKey)
                    }

                    ToolbarChip {
                        objectName: "deleteSubTabChipButton"
                        icon: "delete"
                        label: Translation.tr("Delete")
                        tooltipText: Translation.tr("Delete active custom sub-tab (%1)").arg(root.activeSubTabLabel || root.activeSubTabKey)
                        chipEnabled: root.canDeleteSubTab
                        dangerState: true
                        onClicked: {
                            if (root.targetPage && typeof root.targetPage.deleteActiveSubTab === "function") {
                                root.targetPage.deleteActiveSubTab();
                            } else {
                                SettingsLayoutManager.deleteSubTab(
                                    root.pageIndex,
                                    root.customTabId,
                                    root.activeSubTabKey,
                                    root.baseSubTabs
                                );
                            }
                        }
                    }
                }

                GroupDivider {}

                ControlGroup {
                    title: Translation.tr("Sidebar tab")

                    ToolbarChip {
                        objectName: "newSidebarTabChipButton"
                        icon: "post_add"
                        label: Translation.tr("New Sidebar Tab")
                        tooltipText: Translation.tr("Create a new custom tab in the Settings sidebar")
                        activeState: root.inlinePromptMode === "new-sidebar-tab"
                        onClicked: root._togglePrompt("new-sidebar-tab", "")
                    }

                    ToolbarChip {
                        objectName: "renameSidebarTabChipButton"
                        icon: "edit_note"
                        label: Translation.tr("Rename")
                        tooltipText: Translation.tr("Rename this custom sidebar tab")
                        chipEnabled: root.customTabId.length > 0
                        activeState: root.inlinePromptMode === "rename-sidebar-tab"
                        onClicked: {
                            const ct = SettingsLayoutManager.getCustomTab(root.customTabId);
                            root._setPromptMode("rename-sidebar-tab");
                            promptInput.text = ct ? ct.label : "";
                            Qt.callLater(() => promptInput.forceActiveFocus());
                        }
                    }

                    ToolbarChip {
                        objectName: "deleteSidebarTabChipButton"
                        icon: "delete_forever"
                        label: Translation.tr("Delete")
                        tooltipText: Translation.tr("Delete this custom sidebar tab and return its modules")
                        chipEnabled: root.customTabId.length > 0
                        dangerState: true
                        onClicked: SettingsLayoutManager.deleteCustomTab(root.customTabId)
                    }
                }
            }
        }
    }
}
