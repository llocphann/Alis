#!/usr/bin/env python3
"""Deep unit + Quickshell runtime verification for modular Settings layout, cross-tab drag-and-drop, tab CRUD, inner item reordering, and vertical/resizable sliders."""

import json
import os
import subprocess
import tempfile
import time
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]


def strip_qml_js_pragmas(source: str) -> str:
    lines = [
        line for line in source.splitlines()
        if not line.strip().startswith(".pragma") and not line.strip().startswith(".import")
    ]
    return "\n".join(lines)


def run_policy_unit_tests() -> None:
    policy_src = strip_qml_js_pragmas(
        (ROOT / "modules/common/widgets/SettingsLayoutPolicy.js").read_text(encoding="utf-8")
    )
    js_driver = r"""
const assert = require("assert");
""" + policy_src + r"""

// 1. Empty / invalid / legacy state parsing
const empty1 = parseState("");
assert.strictEqual(empty1.version, SCHEMA_VERSION);
assert.deepStrictEqual(empty1.modules, {});
assert.deepStrictEqual(empty1.customTabs, []);

const malformed = parseState("{not-valid-json");
assert.strictEqual(malformed.version, SCHEMA_VERSION);
assert.deepStrictEqual(malformed.modules, {});

// 2. Module sizing & boundary clamping
let st = emptyState();
st = resizeModule(st, "p0:audio-card", {
    widthRatio: 0.1, // below 0.25 -> clamped to 0.25
    customHeight: 40, // below 88 -> clamped to 88
    innerColumns: 9, // above 3 -> clamped to 3
    contentFitMode: "scale",
    canvasX: 15,
    canvasY: 31,
    canvasW: 100, // below 180 -> clamped to 180
    canvasH: 50   // below 88 -> clamped to 88
}, true, 16);
let mCfg = getModuleConfig(st, "p0:audio-card");
assert.strictEqual(mCfg.widthRatio, 0.25);
assert.strictEqual(mCfg.customHeight, 96);
assert.strictEqual(mCfg.innerColumns, 3);
assert.strictEqual(mCfg.contentFitMode, "scale");
assert.strictEqual(mCfg.canvasX, 16);
assert.strictEqual(mCfg.canvasY, 32);
assert.strictEqual(mCfg.canvasW, 180);
assert.strictEqual(mCfg.canvasH, 88);

// Reset custom height to 0 (auto height)
st = resizeModule(st, "p0:audio-card", { customHeight: 0, widthRatio: 0.75 }, false, 16);
mCfg = getModuleConfig(st, "p0:audio-card");
assert.strictEqual(mCfg.customHeight, 0);
assert.strictEqual(mCfg.widthRatio, 0.75);
assert.strictEqual(mCfg.contentFitMode, "scale");

// Default contentFitMode on a newly resized module must be "scale" (auto-scale)
st = resizeModule(st, "p2:new-card", { customHeight: 200 }, false, 16);
assert.strictEqual(getModuleConfig(st, "p2:new-card").contentFitMode, "scale");

// Legacy v1 state with default "scroll" must migrate to "scale" on parseState,
// and unplaced v1 entries (canvasX=0, canvasY=0, canvasW=0, canvasH=0) must normalize canvasX=-1, canvasY=-1
const legacyV1Raw = JSON.stringify({
    version: 1,
    modules: {
        "p4:color-themes": {
            originPageIndex: 4,
            customHeight: 240,
            widthRatio: 0.75,
            contentFitMode: "scroll",
            canvasX: 0,
            canvasY: 0,
            canvasW: 0,
            canvasH: 0
        },
        "p39:system-utilities": {
            originPageIndex: 39,
            originSubTab: "utilities",
            column: "left",
            order: 0,
            widthRatio: 0,
            customHeight: 0,
            contentFitMode: "scroll",
            canvasX: 0,
            canvasY: 0,
            canvasW: 0,
            canvasH: 0
        }
    }
});
const migratedV2 = parseState(legacyV1Raw);
assert.strictEqual(migratedV2.version, SCHEMA_VERSION);
assert.strictEqual(getModuleConfig(migratedV2, "p4:color-themes").contentFitMode, "scale");
assert.strictEqual(getModuleConfig(migratedV2, "p4:color-themes").customHeight, 240);
assert.strictEqual(getModuleConfig(migratedV2, "p4:color-themes").canvasX, -1);
assert.strictEqual(getModuleConfig(migratedV2, "p4:color-themes").canvasY, -1);
assert.strictEqual(getModuleConfig(migratedV2, "p39:system-utilities").canvasX, -1);
assert.strictEqual(getModuleConfig(migratedV2, "p39:system-utilities").canvasY, -1);

// 3. Snap to grid
assert.strictEqual(snapValue(23, 16, true), 16);
assert.strictEqual(snapValue(25, 16, true), 32);
assert.strictEqual(snapValue(25, 16, false), 25);

// 4. Bento vs Canvas page layout mode & column split ratio
st = updatePageLayoutConfig(st, 0, "", { layoutMode: "canvas", leftColumnRatio: 0.95 });
let pLayout = getPageLayoutConfig(st, 0, "");
assert.strictEqual(pLayout.layoutMode, "canvas");
assert.strictEqual(pLayout.leftColumnRatio, 0.78); // clamped to 0.78

st = updatePageLayoutConfig(st, 0, "", { layoutMode: "bento", leftColumnRatio: 0.10 });
pLayout = getPageLayoutConfig(st, 0, "");
assert.strictEqual(pLayout.layoutMode, "bento");
assert.strictEqual(pLayout.leftColumnRatio, 0.22); // clamped to 0.22

// 5. Reordering modules within a bucket
st = reorderModulesInBucket(st, ["m3", "m1", "m2"], "left");
assert.strictEqual(getModuleConfig(st, "m3").order, 10);
assert.strictEqual(getModuleConfig(st, "m1").order, 20);
assert.strictEqual(getModuleConfig(st, "m2").order, 30);
assert.strictEqual(getModuleConfig(st, "m3").column, "left");

// 6. Custom Sidebar Tab CRUD + Reordering + Safe module return on delete
let res1 = createCustomTab(st, "Audio & Mic", "volume_up", 0);
st = res1.state;
const tab1 = res1.tabId;
assert(tab1.startsWith("custom-"));

let res2 = createCustomTab(st, "Workspace Hub", "dashboard", 0);
st = res2.state;
const tab2 = res2.tabId;
assert.strictEqual(st.customTabs.length, 2);

st = renameCustomTab(st, tab1, "Pro Audio", "");
assert.strictEqual(st.customTabs[0].label, "Pro Audio");

st = moveCustomTab(st, tab2, -1, 0);
assert.strictEqual(st.customTabs[0].id, tab2);
assert.strictEqual(st.customTabs[1].id, tab1);

// Move a module from page 0 into custom tab1, and another from page 2 into page 4
st = moveModuleToTarget(
    st,
    "p0:mixer",
    { originPageIndex: 0, originSubTab: "general", title: "Mixer", icon: "volume_up" },
    { targetPageIndex: -1, targetCustomTabId: tab1, targetSubTab: "" }
);
assert.deepStrictEqual(getDonorPageIndexesForTarget(st, -1, tab1), [0]);

st = moveModuleToTarget(
    st,
    "p2:bar-edge",
    { originPageIndex: 2, originSubTab: "layout", title: "Bar Edge", icon: "tune" },
    { targetPageIndex: 4, targetCustomTabId: "", targetSubTab: "colors" }
);
assert.deepStrictEqual(getDonorPageIndexesForTarget(st, 4, ""), [2]);

// Deleting custom tab1 must return "p0:mixer" safely to its origin page 0
st = deleteCustomTab(st, tab1);
assert.strictEqual(st.customTabs.length, 1);
const returnedCfg = getModuleConfig(st, "p0:mixer");
assert.strictEqual(returnedCfg.targetCustomTabId, "");
assert.strictEqual(returnedCfg.targetPageIndex, 0);

// 7. Sub-tab CRUD + Reorder + Rename + Delete
const baseSubs = [
    { key: "colors", label: "Colors", icon: "palette" },
    { key: "typography", label: "Typography", icon: "text_fields" }
];
let subRes = createSubTab(st, 4, "", "My Shaders", "auto_awesome", baseSubs);
st = subRes.state;
const customSubKey = subRes.subTabKey;
let effSubs = getEffectiveSubTabs(st, 4, "", baseSubs);
assert.strictEqual(effSubs.length, 3);
assert.strictEqual(effSubs[2].key, customSubKey);
assert.strictEqual(effSubs[2].custom, true);

st = renameSubTab(st, 4, "", "colors", "Palette & Tone");
effSubs = getEffectiveSubTabs(st, 4, "", baseSubs);
assert.strictEqual(effSubs[0].label, "Palette & Tone");

st = reorderSubTab(st, 4, "", customSubKey, -1, baseSubs);
effSubs = getEffectiveSubTabs(st, 4, "", baseSubs);
assert.strictEqual(effSubs[1].key, customSubKey);

// Move module into customSubKey, then delete customSubKey -> module subTab falls back to remaining[0]
st = moveModuleToTarget(
    st,
    "p2:bar-edge",
    { originPageIndex: 2, originSubTab: "layout" },
    { targetPageIndex: 4, targetCustomTabId: "", targetSubTab: customSubKey }
);
assert.strictEqual(getModuleConfig(st, "p2:bar-edge").targetSubTab, customSubKey);
st = deleteSubTab(st, 4, "", customSubKey, baseSubs);
assert.strictEqual(getModuleConfig(st, "p2:bar-edge").targetSubTab, "colors");

// Verify createSubTab on a page with 0 baseSubTabs sets custom=false on auto-created "overview" tab
let zeroBaseSubRes = createSubTab(st, 23, "", "Extra Panel", "tab", []);
st = zeroBaseSubRes.state;
let zeroBaseEffSubs = getEffectiveSubTabs(st, 23, "", []);
assert.strictEqual(zeroBaseEffSubs.length, 2);
assert.strictEqual(zeroBaseEffSubs[0].key, "overview");
assert.strictEqual(zeroBaseEffSubs[0].custom, false);
assert.strictEqual(zeroBaseEffSubs[1].key, zeroBaseSubRes.subTabKey);
assert.strictEqual(zeroBaseEffSubs[1].custom, true);

// Verify page-level foreign module (targetSubTab: "") is hosted on "overview" but NOT duplicated onto custom sub-tab
st = moveModuleToTarget(
    st,
    "p2:bar-edge",
    { originPageIndex: 2, originSubTab: "layout" },
    { targetPageIndex: 23, targetCustomTabId: "", targetSubTab: "" }
);
assert.strictEqual(isModuleHostedOnTarget(st, "p2:bar-edge", 23, "", "overview", true), true);
assert.strictEqual(isModuleHostedOnTarget(st, "p2:bar-edge", 23, "", zeroBaseSubRes.subTabKey, true), false);

// 8. Inner Settings Item Reordering & Sizing
const defItems = ["row-a", "row-b", "row-c"];
assert.deepStrictEqual(getInnerOrder(st, "card-1::group-0", defItems), ["row-a", "row-b", "row-c"]);
st = moveInnerItem(st, "card-1::group-0", "row-c", -1, defItems);
assert.deepStrictEqual(getInnerOrder(st, "card-1::group-0", defItems), ["row-a", "row-c", "row-b"]);
st = moveInnerItem(st, "card-1::group-0", "row-b", "row-a", defItems);
assert.deepStrictEqual(getInnerOrder(st, "card-1::group-0", defItems), ["row-b", "row-a", "row-c"]);

st = updateInnerItemConfig(st, "card-1::group-0::row-a", { widthRatio: 0.5, alignment: "center" });
const rowACfg = getInnerItemConfig(st, "card-1::group-0::row-a");
assert.strictEqual(rowACfg.widthRatio, 0.5);
assert.strictEqual(rowACfg.alignment, "center");

// 9. Slider Orientation Rotation & Sizing
assert.strictEqual(getSliderConfig(st, "slider-vol").orientation, "horizontal");
st = toggleSliderOrientation(st, "slider-vol");
assert.strictEqual(getSliderConfig(st, "slider-vol").orientation, "vertical");
st = resizeSlider(st, "slider-vol", 220, 18, "m");
assert.strictEqual(getSliderConfig(st, "slider-vol").length, 220);
assert.strictEqual(getSliderConfig(st, "slider-vol").thickness, 18);
assert.strictEqual(getSliderConfig(st, "slider-vol").configuration, "m");
st = toggleSliderOrientation(st, "slider-vol");
assert.strictEqual(getSliderConfig(st, "slider-vol").orientation, "horizontal");
st = resetSlider(st, "slider-vol");
assert.strictEqual(getSliderConfig(st, "slider-vol").length, 0);
assert.strictEqual(getSliderConfig(st, "slider-vol").thickness, 0);

// 10. resetModule cleans up innerOrders, innerItems, and sliders belonging to that module
st = resizeModule(st, "p4:color-themes", { customHeight: 220, widthRatio: 0.6 }, false, 16);
st = moveInnerItem(st, "p4:color-themes:group-0", "row-c", -1, defItems);
st = updateInnerItemConfig(st, "p4:color-themes:group-0::row-a", { widthRatio: 0.5, alignment: "center" });
st = resizeSlider(st, "p4:slider:color-themes-opacity-0", 180, 14, "s");
st = resetModule(st, "p4:color-themes");
assert.strictEqual(getModuleConfig(st, "p4:color-themes").customHeight, 0);
assert.deepStrictEqual(getInnerOrder(st, "p4:color-themes:group-0", defItems), defItems);
assert.strictEqual(getInnerItemConfig(st, "p4:color-themes:group-0::row-a").widthRatio, 0);
assert.strictEqual(getInnerItemConfig(st, "p4:color-themes:group-0::row-a").alignment, "fill");
assert.strictEqual(getSliderConfig(st, "p4:slider:color-themes-opacity-0").length, 0);
assert.strictEqual(getInnerItemConfig(st, "card-1::group-0::row-a").widthRatio, 0.5);

// 11. humanizeModuleTitle strips p<N>:/custom: prefixes for legacy/unloaded entries while preserving real card titles
assert.strictEqual(humanizeModuleTitle("", "p25:blur-glass-power"), "Blur Glass Power");
assert.strictEqual(humanizeModuleTitle("p25:wallpaper-blur-dim", "p25:wallpaper-blur-dim"), "Wallpaper Blur Dim");
assert.strictEqual(humanizeModuleTitle("", "p25:cava-spectrum-options"), "Cava Spectrum Options");
assert.strictEqual(humanizeModuleTitle("", "p24:ai-ui-osd"), "AI UI OSD");
assert.strictEqual(humanizeModuleTitle("Providers & models", "p24:providers-models"), "Providers & models");

console.log("POLICY_UNIT_TESTS_PASS");
"""
    out = subprocess.check_output(["node", "-e", js_driver], text=True)
    assert "POLICY_UNIT_TESTS_PASS" in out, out
    print("PASS: SettingsLayoutPolicy.js unit & edge-case tests")


def run_quickshell_runtime_tests() -> None:
    qml_test = r"""
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
import qs.services

Window {
    id: root
    visible: true
    width: 1280
    height: 860
    color: "#111820"

    Component.onCompleted: Quickshell.watchFiles = false

    Item {
        id: host
        anchors.fill: parent
    }

    SettingsOverlay {
        id: overlay
        embeddedHost: host
        settingsOpen: true
    }

    TestCase {
        id: test
        when: false
        optional: true

        function check(cond, msg) {
            if (!cond)
                throw new Error(msg);
        }

        function findByObjectName(item, name) {
            if (!item) return null;
            if (item.objectName === name) return item;
            const ch = item.children || [];
            for (let i = 0; i < ch.length; i++) {
                const found = findByObjectName(ch[i], name);
                if (found) return found;
            }
            return null;
        }

        function findFirstSlider(item) {
            if (!item) return null;
            if (item.hasOwnProperty("sliderLayoutId") && item.hasOwnProperty("isVertical"))
                return item;
            const ch = item.children || [];
            for (let i = 0; i < ch.length; i++) {
                const found = findFirstSlider(ch[i]);
                if (found) return found;
            }
            return null;
        }

        function findAllSliders(item, out) {
            const list = out || [];
            if (!item) return list;
            if (item.hasOwnProperty("sliderLayoutId") && item.hasOwnProperty("isVertical") && item.visible)
                list.push(item);
            const ch = item.children || [];
            for (let i = 0; i < ch.length; i++)
                findAllSliders(ch[i], list);
            return list;
        }

        function findInnerOverlay(item) {
            if (!item) return null;
            if (item.objectName === "settingsInnerReorderOverlay" && (item._visibleItems?.length ?? 0) >= 2)
                return item;
            const ch = item.children || [];
            for (let i = 0; i < ch.length; i++) {
                const found = findInnerOverlay(ch[i]);
                if (found) return found;
            }
            return null;
        }

        function findAllInnerOverlays(item, out) {
            const list = out || [];
            if (!item) return list;
            if (item.objectName === "settingsInnerReorderOverlay" && (item._visibleItems?.length ?? 0) >= 2)
                list.push(item);
            const ch = item.children || [];
            for (let i = 0; i < ch.length; i++)
                findAllInnerOverlays(ch[i], list);
            return list;
        }

        function runSuite() {
            try {
                tryCompare(Config, "ready", true, 4000);
                tryCompare(Persistent, "ready", true, 4000);
                tryCompare(overlay, "_navigationInitialized", true, 4000);
                Config.setNestedValues({
                    "panelFamily": "abyss",
                    "performance.reduceAnimations": true,
                    "settingsUi.moduleLayout": ""
                });

                // Navigate to Bar settings (page 2) which has multiple SettingsCardSection cards & sliders
                overlay.overlayCurrentPage = 2;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 2 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);

                const barPage = overlay.pageHost.currentItem;
                const registeredIdsPage2 = Object.keys(SettingsLayoutManager._liveCardsByModuleId).filter(
                    id => id.indexOf("p2:") === 0 && SettingsLayoutManager._liveCardsByModuleId[id].visible
                );
                check(registeredIdsPage2.length >= 2, "Expected at least 2 visible SettingsCardSection modules on Bar page, got: " + registeredIdsPage2.length);

                const firstModuleId = registeredIdsPage2[0];
                const secondModuleId = registeredIdsPage2[1];
                const firstCard = SettingsLayoutManager._liveCardsByModuleId[firstModuleId];
                const secondCard = SettingsLayoutManager._liveCardsByModuleId[secondModuleId];
                check(firstCard !== null && firstCard !== undefined, "Live card lookup failed for " + firstModuleId);
                check(secondCard !== null && secondCard !== undefined, "Live card lookup failed for " + secondModuleId);
                check(SettingsLayoutManager.availableNavigationPages.length > 0 && SettingsLayoutManager.availableNavigationPages[0].pageIndex !== undefined,
                    "availableNavigationPages entries must expose pageIndex for Move Module To Tab menu");

                // 1. Verify External SettingsEditToolbar, Fixed Sidebar Width (204), + Tab Button Alignment, Tooltips & Hover-Focused Module Controls
                const editBtn = findByObjectName(host, "overlayEditSettingsLayoutButton");
                check(editBtn !== null, "overlayEditSettingsLayoutButton not found");
                const navCol = findByObjectName(host, "settingsOverlayNavColumn");
                check(navCol !== null && Math.round(navCol.width) === 204,
                    "Sidebar navColumn must start at fixed width 204, got: " + (navCol ? navCol.width : "null"));
                const availHeightBeforeEdit = barPage.availableCardContentHeight;
                check(findByObjectName(barPage, "settingsEditToolbar") === null,
                    "SettingsEditToolbar must NOT live inside ContentPage");

                SettingsLayoutManager.beginEditMode();
                wait(100);
                check(SettingsLayoutManager.editMode === true, "Edit mode did not activate");
                check(SettingsLayoutManager.innerEditMode === false,
                    "innerEditMode must default to false when entering editMode to avoid control clutter");
                check(Math.round(navCol.width) === 204,
                    "Sidebar navColumn must NOT expand when editMode is active, got: " + navCol.width);
                overlay.navEditMode = true;
                wait(60);
                check(Math.round(navCol.width) === 204,
                    "Sidebar navColumn must NOT expand when navEditMode is active, got: " + navCol.width);
                overlay.navEditMode = false;
                wait(60);

                // External toolbar must be hosted outside ContentPage and must not shrink availableCardContentHeight
                check(findByObjectName(barPage, "settingsEditToolbar") === null,
                    "SettingsEditToolbar must not be created inside ContentPage in editMode");
                check(Math.abs(barPage.availableCardContentHeight - availHeightBeforeEdit) < 0.5,
                    "Entering editMode must not shrink ContentPage availableCardContentHeight (" + barPage.availableCardContentHeight + " vs " + availHeightBeforeEdit + ")");
                const extToolbar = findByObjectName(host, "settingsEditToolbar");
                check(extToolbar !== null && extToolbar.visible === true,
                    "External SettingsEditToolbar must be visible when editMode is active");

                // Verify toolbar buttons expose descriptive hover tooltips
                for (const btnName of [
                    "moveSubTabLeftButton", "moveSubTabRightButton", "innerEditModeChipButton",
                    "addCustomSubTabChipButton", "renameSubTabChipButton", "deleteSubTabChipButton",
                    "settingsEditDoneButton", "settingsEditCancelButton"
                ]) {
                    const b = findByObjectName(extToolbar, btnName);
                    check(b !== null && typeof b.tooltipText === "string" && b.tooltipText.length > 5,
                        "Expected toolbar button " + btnName + " with non-empty tooltipText");
                }

                // Verify + Tab button contentItem centering in the sub-tab bar
                const addSubTabBtn = findByObjectName(barPage, "addSubTabPillButton");
                check(addSubTabBtn !== null && addSubTabBtn.visible === true, "addSubTabPillButton must be visible in editMode");
                check(Math.abs(addSubTabBtn.contentItem.width - addSubTabBtn.width) <= 2,
                    "addSubTabPillButton contentItem must fill button width so icon+label center properly");

                // Verify module edit controls are hidden until hovered/selected (no drag-button clutter across all modules)
                SettingsLayoutManager.selectedModuleId = "";
                wait(60);
                const firstCardToolbar = findByObjectName(firstCard, "cardEditToolbar");
                const secondCardToolbar = findByObjectName(secondCard, "cardEditToolbar");
                check(firstCardToolbar !== null && secondCardToolbar !== null, "cardEditToolbar must exist on modules in editMode");
                check(!(firstCardToolbar.visible && secondCardToolbar.visible),
                    "Unselected modules must not display cardEditToolbar on all cards simultaneously");
                const unhoveredCard = !firstCardToolbar.visible ? firstCard : secondCard;
                const unhoveredModId = !firstCardToolbar.visible ? firstModuleId : secondModuleId;
                const unhoveredToolbar = !firstCardToolbar.visible ? firstCardToolbar : secondCardToolbar;
                check(unhoveredToolbar.visible === false,
                    "Unhovered & unselected module must keep cardEditToolbar hidden");
                SettingsLayoutManager.selectedModuleId = unhoveredModId;
                wait(60);
                check(unhoveredToolbar.visible === true,
                    "Selecting/activating a module must reveal its cardEditToolbar");
                SettingsLayoutManager.selectedModuleId = "";
                wait(60);
                check(unhoveredToolbar.visible === false,
                    "Deselecting an unhovered module must hide its cardEditToolbar again");

                // Verify Sub-tab Left / Right visibly reorders _subTabItems across categorySiblingPages
                check(barPage._subTabItems.length >= 2, "Expected at least 2 sub-tab pills on Bar page");
                const initialOrderKey0 = barPage._subTabItems[0].orderKey;
                const initialOrderKey1 = barPage._subTabItems[1].orderKey;
                check(barPage._activeSubTabIndex === 0, "Expected Bar page sub-tab to start at index 0");
                check(barPage.canMoveSubTabLeft === false && barPage.canMoveSubTabRight === true,
                    "At index 0, canMoveSubTabLeft must be false and canMoveSubTabRight must be true");
                check(barPage.reorderActiveSubTab(1) === true, "reorderActiveSubTab(1) should return true");
                wait(80);
                check(barPage._subTabItems[0].orderKey === initialOrderKey1 && barPage._subTabItems[1].orderKey === initialOrderKey0,
                    "reorderActiveSubTab(1) did not swap the first two sub-tab pills");
                check(barPage._activeSubTabIndex === 1 && barPage.canMoveSubTabLeft === true,
                    "After moving active sub-tab right to index 1, canMoveSubTabLeft must be true");
                check(barPage.reorderActiveSubTab(-1) === true, "reorderActiveSubTab(-1) should return true");
                wait(80);
                check(barPage._subTabItems[0].orderKey === initialOrderKey0 && barPage._subTabItems[1].orderKey === initialOrderKey1,
                    "reorderActiveSubTab(-1) did not restore original sub-tab pill order");

                // Verify createNewSubTab on a categorySiblingPages page inserts after active pill without jumping ahead of sibling 0
                const siblingCreatedSubKey = barPage.createNewSubTab("Sibling Custom Tab");
                wait(80);
                check(siblingCreatedSubKey === "subtab-sibling-custom-tab", "Unexpected siblingCreatedSubKey: " + siblingCreatedSubKey);
                check(barPage._subTabItems[0].orderKey === initialOrderKey0
                    && barPage._subTabItems[1].orderKey === ("p2:" + siblingCreatedSubKey)
                    && barPage._subTabItems[2].orderKey === initialOrderKey1,
                    "createNewSubTab on category sibling page must insert after active sibling without jumping to index 0, got: "
                    + JSON.stringify(barPage._subTabItems.map(i => i.orderKey)));
                check(barPage._activeSubTabIndex === 1 && barPage.canMoveSubTabLeft === true && barPage.canMoveSubTabRight === true,
                    "Newly created custom sub-tab at index 1 must allow moving both left and right");
                check(barPage.deleteActiveSubTab() === true, "deleteActiveSubTab() should return true for custom sub-tab");
                wait(80);
                check(barPage._subTabItems[0].orderKey === initialOrderKey0 && barPage._subTabItems[1].orderKey === initialOrderKey1,
                    "deleteActiveSubTab() must restore sibling sub-tab order");

                // Verify inline naming prompt replaces primaryRow in-place without changing toolbar height
                const toolbarHeightBeforePrompt = extToolbar.height;
                SettingsLayoutManager.requestInlinePrompt("new-subtab");
                wait(60);
                check(SettingsLayoutManager.activePromptMode === "new-subtab" && extToolbar.inlinePromptMode === "new-subtab",
                    "requestInlinePrompt must activate new-subtab prompt mode");
                check(Math.abs(extToolbar.height - toolbarHeightBeforePrompt) <= 1,
                    "Opening inline naming prompt must not change external toolbar height (" + extToolbar.height + " vs " + toolbarHeightBeforePrompt + ")");
                SettingsLayoutManager.activePromptMode = "";
                wait(60);

                // Verify Modules is an integrated tier of the bottom-connected Abyss customization dock:
                // no floating SettingsModulePickerPopover, nothing inserted into ContentPage, constant dock height
                check(findByObjectName(host, "settingsModulePickerPopover") === null,
                    "Retired floating SettingsModulePickerPopover must not be mounted anywhere in Settings");
                const extToolbarBottom = extToolbar.mapToItem(host, 0, extToolbar.height).y;
                check(Math.abs(extToolbarBottom - host.height) <= 1,
                    "External Settings customization dock must connect to the bottom edge (bottom=" + extToolbarBottom + " host=" + host.height + ")");
                const modChipBtn = findByObjectName(extToolbar, "modulesDrawerChipButton");
                check(modChipBtn !== null && modChipBtn.tooltipText.length > 5, "modulesDrawerChipButton missing on external toolbar");
                check(extToolbar.activeDockTab !== "modules" && SettingsLayoutManager.moduleDrawerOpen === false,
                    "Modules tier must start closed when entering editMode");
                SettingsLayoutManager.moduleDrawerOpen = true;
                wait(80);
                check(extToolbar.showModuleDrawer === true && extToolbar.activeDockTab === "modules",
                    "moduleDrawerOpen must activate the dock's Modules tier");
                check(Math.abs(extToolbar.height - toolbarHeightBeforePrompt) <= 1,
                    "Opening the Modules tier must NOT change the dock height (" + extToolbar.height + " vs " + toolbarHeightBeforePrompt + ")");
                check(Math.abs(barPage.availableCardContentHeight - availHeightBeforeEdit) < 0.5,
                    "Opening the Modules tier must NOT shrink ContentPage availableCardContentHeight");
                check(findByObjectName(barPage, "settingsModulePickerPopover") === null
                    && findByObjectName(barPage, "settingsModuleGallery") === null,
                    "Module management must NOT be inserted inside ContentPage / Settings Layout");
                check(findByObjectName(host, "settingsModulePickerPopover") === null,
                    "Opening Modules must not mount a floating popup");
                const moduleGallery = findByObjectName(extToolbar, "settingsModuleGallery");
                check(moduleGallery !== null && moduleGallery.visible === true,
                    "Dock Modules tier must show the horizontal module gallery");
                const dockSearch = findByObjectName(extToolbar, "settingsModuleSearchInput");
                check(dockSearch !== null && dockSearch.visible === true, "Dock module search must be visible on the Modules tier");
                SettingsLayoutManager.resizeModule("p25:blur-glass-power", { customHeight: 160 });
                wait(40);
                const legacyKnown = SettingsLayoutManager.getAllKnownModules().find(m => m.moduleId === "p25:blur-glass-power");
                check(legacyKnown && legacyKnown.title === "Blur Glass Power",
                    "Unloaded legacy module IDs must humanize cleanly instead of showing raw p25:* ID, got: " + (legacyKnown ? legacyKnown.title : "null"));
                const legacyTile = findByObjectName(extToolbar, "settingsModuleTile_p25:blur-glass-power");
                check(legacyTile !== null && legacyTile.title === "Blur Glass Power" && legacyTile.active === false,
                    "Legacy module tile must show humanized title with + badge, got: " + (legacyTile ? legacyTile.title : "null"));
                extToolbar.searchText = "blur glass";
                wait(60);
                check(extToolbar.filteredModules.length >= 1
                    && extToolbar.filteredModules.some(m => m.moduleId === "p25:blur-glass-power")
                    && extToolbar.filteredModules.every(m => m.title.toLowerCase().includes("blur glass")
                        || String(m.originLabel).toLowerCase().includes("blur glass")),
                    "Dock search must filter module tiles live, got: " + JSON.stringify(extToolbar.filteredModules.map(m => m.title)));
                extToolbar.searchText = "";
                wait(60);
                check(extToolbar.currentModules.some(m => m.moduleId === firstModuleId),
                    "Visible module on this tab must be listed in the dock's current modules");
                const activeTile = findByObjectName(extToolbar, "settingsModuleTile_" + firstModuleId);
                check(activeTile !== null && activeTile.active === true, "Visible module tile must show the ✓ badge");
                activeTile.clicked();
                wait(40);
                check(SettingsLayoutManager.selectedModuleId === firstModuleId && SettingsLayoutManager.editMode === true,
                    "Clicking a module already on this tab must select it on the canvas");
                SettingsLayoutManager.selectedModuleId = "";
                activeTile.badgeClicked();
                wait(60);
                check(extToolbar.hiddenModules.some(m => m.moduleId === firstModuleId)
                    && SettingsLayoutManager.getModuleConfig(firstModuleId).visible === false,
                    "✓ badge must hide the module from this tab, got hidden=" + JSON.stringify(extToolbar.hiddenModules.map(m => m.moduleId)));
                extToolbar.moduleFilter = "hidden";
                wait(60);
                const unhideBtn = findByObjectName(extToolbar, "unhideAllModulesButton");
                check(unhideBtn !== null && unhideBtn.visible === true, "Unhide All pill must appear when any module is hidden");
                const hiddenTile = findByObjectName(extToolbar, "settingsModuleTile_" + firstModuleId);
                check(hiddenTile !== null && hiddenTile.active === false && extToolbar.filteredModules.every(m => m.status === "hidden"),
                    "Hidden filter must show the hidden module with a + badge");
                hiddenTile.badgeClicked();
                wait(60);
                check(extToolbar.hiddenModules.length === 0 && firstCard.visible === true,
                    "+ badge on a hidden module must restore it onto this tab");
                SettingsLayoutManager.setModuleVisible(firstModuleId, false);
                wait(60);
                extToolbar.unhideAll();
                wait(60);
                check(extToolbar.hiddenModules.length === 0 && firstCard.visible === true,
                    "Dock unhideAll() must restore hidden module visibility");
                extToolbar.moduleFilter = "all";
                SettingsLayoutManager.resetModule("p25:blur-glass-power");
                overlay.handleEscape();
                wait(60);
                check(SettingsLayoutManager.moduleDrawerOpen === false && SettingsLayoutManager.editMode === true
                    && extToolbar.activeDockTab !== "modules",
                    "First Escape while the Modules tier is open must close only the tier and keep editMode active");
                check(Math.abs(extToolbar.height - toolbarHeightBeforePrompt) <= 1,
                    "Closing the Modules tier must not change the dock height");

                // Bottom-docked dock overlaps the page bottom: the page gains a scroll reserve so its last
                // cards can scroll clear above the dock, without changing availableCardContentHeight
                check(Math.abs(barPage.editBottomScrollReserve - extToolbar.height) <= 1 && barPage._editScrollReserve > 0,
                    "ContentPage must receive the dock overlap as editBottomScrollReserve (" + barPage.editBottomScrollReserve + " vs " + extToolbar.height + ")");
                check(Math.abs(barPage.availableCardContentHeight - availHeightBeforeEdit) < 0.5,
                    "Edit scroll reserve must not change availableCardContentHeight");
                check(barPage.interactive === true && barPage.contentHeight - barPage.height >= barPage._editScrollReserve - 1,
                    "Page must be scrollable by at least the dock overlap in editMode (range=" + (barPage.contentHeight - barPage.height) + ")");
                barPage.contentY = barPage.contentHeight - barPage.height;
                wait(40);
                check(barPage.contentY >= barPage._editScrollReserve - 1,
                    "Page must scroll its bottom clear above the dock, got contentY=" + barPage.contentY);
                barPage.contentY = 0;
                wait(40);

                // 2. Test Module Resizing & Responsive Breakpoints (default contentFitMode === "scale", widthRatio, customHeight, innerColumns)
                check(firstCard.moduleContentFitMode === "scale" && secondCard.moduleContentFitMode === "scale",
                    "Modules must default to contentFitMode === 'scale'");
                const fullFirstWidthBeforeResize = firstCard.renderedCardWidth;
                SettingsLayoutManager.resizeModule(firstModuleId, {
                    widthRatio: 0.5,
                    customHeight: 256,
                    innerColumns: 2
                });
                wait(100);
                check(Math.abs(firstCard.moduleWidthRatio - 0.5) < 0.01, "moduleWidthRatio did not update to 0.5");
                check(firstCard.renderedCardWidth < fullFirstWidthBeforeResize * 0.65,
                    "Resizing moduleWidthRatio to 0.5 must actually shrink renderedCardWidth (" + firstCard.renderedCardWidth + " vs " + fullFirstWidthBeforeResize + ")");
                check(firstCard.moduleCustomHeight === 256, "moduleCustomHeight did not update to 256: " + firstCard.moduleCustomHeight);
                check(firstCard.moduleInnerColumns === 2, "moduleInnerColumns did not update to 2");
                check(firstCard.moduleContentFitMode === "scale", "Resizing module without explicit contentFitMode must keep 'scale' default");

                SettingsLayoutManager.resizeModule(firstModuleId, {
                    contentFitMode: "scroll"
                });
                wait(80);
                check(firstCard.moduleContentFitMode === "scroll", "moduleContentFitMode did not update to scroll");

                SettingsLayoutManager.resizeModule(firstModuleId, {
                    contentFitMode: "scale"
                });
                wait(80);
                check(firstCard.moduleContentFitMode === "scale", "moduleContentFitMode did not update back to scale");

                // 3. Test Freeform Canvas Mode vs Bento Mode + Bento Split Ratio
                SettingsLayoutManager.updatePageLayoutConfig(2, "", { layoutMode: "canvas" });
                wait(120);
                check(barPage.isCanvasLayoutMode === true, "Page did not switch to canvas layout mode");
                SettingsLayoutManager.resizeModule(firstModuleId, {
                    canvasX: 64,
                    canvasY: 48,
                    canvasW: 400,
                    canvasH: 224
                });
                wait(100);
                check(firstCard.x === 64 && firstCard.y === 48, "Card canvas position did not update: " + firstCard.x + "," + firstCard.y);
                check(firstCard.width === 400 && firstCard.height === 224, "Card canvas size did not update: " + firstCard.width + "x" + firstCard.height);

                SettingsLayoutManager.updatePageLayoutConfig(2, "", { layoutMode: "bento" });
                SettingsLayoutManager.setLeftColumnRatio(2, "", 0.6);
                wait(120);
                check(barPage.isCanvasLayoutMode === false, "Page did not return to bento layout mode");
                check(Math.abs(barPage.leftColumnRatio - 0.6) < 0.01, "leftColumnRatio did not update to 0.6");

                // 4. Test Sub-Tab Creation, Renaming, Reordering, Module Move to Sub-Tab, and Deletion
                const baseSubs = barPage.baseSubTabSpecs;
                const createdSubKey = SettingsLayoutManager.createSubTab(2, "", "Custom Edge Tab", "tune", baseSubs);
                check(createdSubKey.length > 0, "Failed to create custom sub-tab");
                wait(100);
                check(barPage.effectiveSubTabSpecs.some(opt => opt.key === createdSubKey), "Custom sub-tab not present in effectiveSubTabSpecs");
                check(barPage._subTabItems.some(it => it.kind === "siblingPage" && it.pageIndex === 2),
                    "Creating custom sub-tab on sibling page must preserve the page's own siblingPage pill in _subTabItems");
                check(barPage._subTabItems.some(it => it.kind === "customSubTab" && it.value === createdSubKey),
                    "Custom sub-tab pill must appear in _subTabItems");

                SettingsLayoutManager.renameSubTab(2, "", createdSubKey, "Renamed Sub-Tab");
                wait(80);
                check(barPage.effectiveSubTabSpecs.some(opt => opt.key === createdSubKey && opt.label === "Renamed Sub-Tab"), "Sub-tab rename did not apply");

                SettingsLayoutManager.moveModuleToTarget(firstModuleId, {
                    targetPageIndex: 2,
                    targetCustomTabId: "",
                    targetSubTab: createdSubKey
                });
                wait(100);
                barPage.customActiveSubTab = createdSubKey;
                barPage._updateCardTabs();
                wait(100);
                check(barPage._eligibleCards.includes(firstCard), "Module moved to custom sub-tab should be eligible when that sub-tab is active");
                check(!barPage._eligibleCards.includes(secondCard), "Unmoved native cards must not appear on custom sub-tab");

                // Delete the active custom sub-tab WITHOUT manually clearing barPage.customActiveSubTab
                SettingsLayoutManager.deleteSubTab(2, "", createdSubKey, baseSubs);
                barPage._updateCardTabs();
                wait(100);
                check(barPage.customActiveSubTab === "", "Deleting active custom sub-tab must automatically reset customActiveSubTab to empty");
                check(!barPage.effectiveSubTabSpecs.some(opt => opt.key === createdSubKey), "Deleted custom sub-tab still present");
                check(barPage._eligibleCards.includes(firstCard) && barPage._eligibleCards.includes(secondCard),
                    "Native cards and returned card must be visible after deleting active custom sub-tab");

                // 5. Test Custom Sidebar Tab Creation, Switching Between Custom Tabs, Cross-Tab Module Move, Foreign Card Reparenting, Rename, Delete
                const customTabId = SettingsLayoutManager.createCustomTab("My Custom Tab", "dashboard_customize", 0);
                check(customTabId.length > 0, "Failed to create custom sidebar tab");
                wait(120);

                // Move firstModuleId from Bar page (page 2) into customTabId
                SettingsLayoutManager.moveModuleToTarget(firstModuleId, {
                    targetPageIndex: -1,
                    targetCustomTabId: customTabId,
                    targetSubTab: "",
                    column: "left"
                });
                wait(150);

                // Verify donor page 2 is kept alive in _donorIndices and firstCard is hosted inside CustomSettingsTabPage
                tryVerify(() => overlay.pageHost.showingCustomTab === true && overlay.pageHost.currentItem !== null, 4000);
                wait(150);
                check(overlay.pageHost._donorIndices.includes(2), "SettingsPageHost did not retain donor page 2");
                check(firstCard._foreignHosted === true && firstCard._hostedByCustomTabId === customTabId,
                    "Live card was not reparented into CustomSettingsTabPage");
                check(firstCard.visible === true, "Foreign hosted card is not visible on CustomSettingsTabPage");

                // Verify donor page _updateCardTabs() does NOT steal back a foreign-hosted card
                barPage._updateCardTabs();
                wait(80);
                check(firstCard._foreignHosted === true && firstCard._hostedByCustomTabId === customTabId && firstCard._cardSubTabActive === true,
                    "Donor page _updateCardTabs() stole back a foreign-hosted card from CustomSettingsTabPage");

                // Create a second custom tab, move secondModuleId to it, and verify switching activeCustomTabId updates CustomSettingsTabPage
                const customTabId2 = SettingsLayoutManager.createCustomTab("Second Custom Tab", "tune", 0);
                SettingsLayoutManager.moveModuleToTarget(secondModuleId, {
                    targetPageIndex: -1,
                    targetCustomTabId: customTabId2,
                    targetSubTab: "",
                    column: "left"
                });
                wait(150);
                check(overlay.pageHost.currentItem._eligibleCards.includes(secondCard) && !overlay.pageHost.currentItem._eligibleCards.includes(firstCard),
                    "Switching to customTabId2 did not update CustomSettingsTabPage eligible cards");
                SettingsLayoutManager.activeCustomTabId = customTabId;
                wait(120);
                check(overlay.pageHost.currentItem._eligibleCards.includes(firstCard) && !overlay.pageHost.currentItem._eligibleCards.includes(secondCard),
                    "Switching back to customTabId did not update CustomSettingsTabPage eligible cards");

                // Rename custom tab
                SettingsLayoutManager.renameCustomTab(customTabId, "Renamed Sidebar Tab", "");
                wait(60);
                check(SettingsLayoutManager.getCustomTab(customTabId).label === "Renamed Sidebar Tab", "Custom sidebar tab rename failed");

                // Delete both custom tabs -> cards return to origin page 2 and activeCustomTabId clears
                SettingsLayoutManager.deleteCustomTab(customTabId2);
                SettingsLayoutManager.deleteCustomTab(customTabId);
                wait(150);
                check(SettingsLayoutManager.activeCustomTabId === "", "activeCustomTabId did not clear on delete");
                check(firstCard.isMovedToForeignPage === false && secondCard.isMovedToForeignPage === false,
                    "Cards did not return to origin page after custom tab deletion");

                // 6. Test Slider Rotation (Horizontal <-> Vertical), Uniqueness Across Cards, and Length/Thickness Resizing on Sidebars page (page 23)
                overlay.overlayCurrentPage = 23;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 23 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const sidebarsPage = overlay.pageHost.currentItem;
                const allSliders = findAllSliders(sidebarsPage);
                check(allSliders.length >= 2, "Expected at least 2 StyledSliders on Sidebars page, got: " + allSliders.length);
                const slider = allSliders[0];
                const otherSlider = allSliders[allSliders.length - 1];
                const sliderId = slider.sliderLayoutId;
                check(sliderId.length > 0, "Slider has empty sliderLayoutId");
                check(sliderId !== otherSlider.sliderLayoutId,
                    "Sliders in different cards/rows collided with identical sliderLayoutId: " + sliderId);
                check(slider.isVertical === false, "Slider should start horizontal");

                SettingsLayoutManager.toggleSliderOrientation(sliderId);
                wait(80);
                check(slider.isVertical === true && slider.orientation === Qt.Vertical, "Slider did not rotate to Qt.Vertical");
                check(otherSlider.isVertical === false, "Rotating one slider must not rotate another slider on the same page");

                SettingsLayoutManager.resizeSlider(sliderId, 190, 16, "");
                wait(80);
                check(slider.customLength === 190 && slider.implicitHeight === 190, "Vertical slider length did not resize to 190: " + slider.implicitHeight);
                check(slider.customThickness === 16 && slider.effectiveTrackWidth === 16, "Slider thickness did not resize to 16: " + slider.effectiveTrackWidth);

                // 7. Test Inner Item Reordering & Per-Item Width/Alignment inside SettingsGroup + Unique Container IDs Across Cards
                SettingsLayoutManager.innerEditMode = true;
                wait(100);
                const sliderPill = findByObjectName(slider, "sliderControlPill");
                check(sliderPill !== null && sliderPill.x >= 0,
                    "Vertical slider control pill must not be clipped at negative x: " + (sliderPill ? sliderPill.x : "null"));

                const allInnerOverlays = findAllInnerOverlays(sidebarsPage);
                check(allInnerOverlays.length >= 2, "Expected at least 2 SettingsInnerReorderOverlays on Sidebars page, got: " + allInnerOverlays.length);
                check(allInnerOverlays[0].containerId !== allInnerOverlays[1].containerId,
                    "SettingsGroup/ContentSubsection containerIds collided across cards: " + allInnerOverlays[0].containerId);
                const innerOverlay = allInnerOverlays[0];
                const secondInnerOverlay = allInnerOverlays[1];
                const secondOrigKey0 = secondInnerOverlay._visibleItems[0].key;
                const origKey0 = innerOverlay._visibleItems[0].key;
                const origKey1 = innerOverlay._visibleItems[1].key;
                SettingsLayoutManager.moveInnerItem(innerOverlay.containerId, origKey0, 1, innerOverlay._defaultKeys);
                wait(100);
                check(innerOverlay._visibleItems[0].key === origKey1 && innerOverlay._visibleItems[1].key === origKey0,
                    "Inner item reordering did not swap live items: " + innerOverlay._visibleItems[0].key + " vs " + origKey1);
                check(secondInnerOverlay._visibleItems[0].key === secondOrigKey0,
                    "Reordering inner items in Card 1 must not reorder inner items in Card 2");

                const targetFullId = innerOverlay._visibleItems[0].fullId;
                SettingsLayoutManager.updateInnerItemConfig(targetFullId, { widthRatio: 0.5, alignment: "center" });
                wait(100);
                check(Math.abs(innerOverlay._visibleItems[0].widthRatio - 0.5) < 0.01, "Inner item widthRatio did not update to 0.5");
                check(innerOverlay._visibleItems[0].alignment === "center", "Inner item alignment did not update to center");

                // 8. Test Global Pointer Drag-and-Drop Coordinator (beginModuleDrag -> updateModuleDrag -> finishModuleDrag)
                const dragOverlay = findByObjectName(host, "settingsModuleDragOverlay");
                check(dragOverlay !== null, "settingsModuleDragOverlay not found");
                const customDragTabId = SettingsLayoutManager.createCustomTab("Drop Target Tab", "tab", 0);
                SettingsLayoutManager.activeCustomTabId = "";
                wait(100);
                const fakeDropZone = Qt.createQmlObject('import QtQuick; Item { visible: true; x: 200; y: 200; width: 160; height: 60 }', host);
                SettingsLayoutManager.registerDropTarget("test-drop-tab", fakeDropZone, {
                    kind: "sidebar-custom-tab",
                    customTabId: customDragTabId,
                    label: "Drop Target Tab"
                });
                const sidebarsCardIds = Object.keys(SettingsLayoutManager._liveCardsByModuleId).filter(
                    id => id.indexOf("p23:") === 0 && SettingsLayoutManager._liveCardsByModuleId[id].visible
                );
                check(sidebarsCardIds.length >= 1, "Expected visible card on Sidebars page");
                const dragModId = sidebarsCardIds[0];
                const dragCardObj = SettingsLayoutManager._liveCardsByModuleId[dragModId];
                SettingsLayoutManager.beginModuleDrag(dragModId, dragCardObj, 100, 100);
                check(SettingsLayoutManager.draggingModule === true, "draggingModule did not activate");
                SettingsLayoutManager.updateModuleDrag(240, 220);
                check(SettingsLayoutManager.hoveredDropTarget && SettingsLayoutManager.hoveredDropTarget.targetId === "test-drop-tab",
                    "Global drag hit-test did not match test-drop-tab: " + (SettingsLayoutManager.hoveredDropTarget?.targetId ?? "null"));
                SettingsLayoutManager.finishModuleDrag(240, 220);
                wait(100);
                check(SettingsLayoutManager.getModuleConfig(dragModId).targetCustomTabId === customDragTabId,
                    "Global drag drop did not move module to customDragTabId");
                SettingsLayoutManager.unregisterDropTarget("test-drop-tab", fakeDropZone);
                fakeDropZone.destroy();
                SettingsLayoutManager.deleteCustomTab(customDragTabId);
                wait(80);

                // 9. Test Sidebar Category CRUD (createCategory, movePageToCategory, deleteCategory)
                const catCountBefore = SettingsPageRegistry.categories.length;
                const createdOk = SettingsArrangement.createCategory("Runtime Custom Category");
                wait(80);
                check(createdOk && SettingsPageRegistry.categories.length === catCountBefore + 1,
                    "createCategory did not add a sidebar category");
                const createdCatIdx = SettingsPageRegistry.categories.length - 1;
                SettingsArrangement.movePageToCategory(23, createdCatIdx, 0);
                wait(80);
                check(SettingsPageRegistry.categories[createdCatIdx].pages.includes(23),
                    "movePageToCategory did not move page 23 into created category");
                SettingsArrangement.deleteCategory(createdCatIdx);
                wait(80);
                check(SettingsPageRegistry.categories.length === catCountBefore,
                    "deleteCategory did not remove category and merge pages");
                SettingsArrangement.reset();

                // 10. Test Undo / Redo, Persistence & Malformed Config Resilience
                check(SettingsLayoutManager.canUndo === true, "Undo stack should not be empty");
                SettingsLayoutManager.undo();
                wait(60);
                check(SettingsLayoutManager.canRedo === true, "Redo stack should not be empty after undo");
                SettingsLayoutManager.redo();
                wait(60);
                check((Config.options?.settingsUi?.moduleLayout ?? "").length > 10, "moduleLayout was not persisted to Config");

                // Inject malformed JSON into Config and verify SettingsLayoutManager recovers cleanly
                Config.setNestedValue("settingsUi.moduleLayout", "{{malformed_json");
                wait(60);
                check(SettingsLayoutManager.state.version === 2, "SettingsLayoutManager did not recover from malformed JSON");

                // Reset everything cleanly
                SettingsLayoutManager.resetAll();
                SettingsLayoutManager.innerEditMode = false;
                SettingsLayoutManager.editMode = false;
                wait(100);
                const sliderAfterReset = findFirstSlider(overlay.pageHost.currentItem);
                check(sliderAfterReset !== null && sliderAfterReset.isVertical === false, "Reset all layouts did not restore slider orientation");

                // 11. Test Transactional Edit Mode: Escape / Cancel discards session changes, Done commits them (matching Dashboard)
                SettingsLayoutManager.beginEditMode();
                wait(80);
                SettingsLayoutManager.resizeModule(dragModId, { widthRatio: 0.5, customHeight: 288 });
                wait(80);
                check(dragCardObj.moduleCustomHeight === 288, "Module height did not update during edit session");
                const escHandled = overlay.handleEscape();
                wait(100);
                check(escHandled === true, "overlay.handleEscape() must return true when cancelling Settings editMode");
                check(SettingsLayoutManager.editMode === false, "Escape must exit SettingsLayoutManager.editMode");
                check(dragCardObj.moduleCustomHeight === 0 && dragCardObj.moduleWidthRatio === 0,
                    "Pressing Escape during editMode must discard unsaved layout changes, got height=" + dragCardObj.moduleCustomHeight + " widthRatio=" + dragCardObj.moduleWidthRatio);

                // Now enter editMode, make a change, and commit via Done (commitEditMode)
                SettingsLayoutManager.beginEditMode();
                wait(80);
                SettingsLayoutManager.resizeModule(dragModId, { customHeight: 272 });
                wait(80);
                SettingsLayoutManager.commitEditMode();
                wait(80);
                check(SettingsLayoutManager.editMode === false, "commitEditMode() must exit editMode");
                check(dragCardObj.moduleCustomHeight === 272,
                    "commitEditMode() must preserve committed layout changes, got height=" + dragCardObj.moduleCustomHeight);

                // Subsequent edit session: Escape while inline prompt is open cancels prompt first, second Escape reverts session
                SettingsLayoutManager.beginEditMode();
                wait(60);
                SettingsLayoutManager.resizeModule(dragModId, { customHeight: 336 });
                SettingsLayoutManager.requestInlinePrompt("new-subtab");
                wait(60);
                check(dragCardObj.moduleCustomHeight === 336, "Module height did not update to 336");
                check(SettingsLayoutManager.activePromptMode === "new-subtab", "Inline prompt did not open");
                overlay.handleEscape();
                wait(60);
                check(SettingsLayoutManager.activePromptMode === "" && SettingsLayoutManager.editMode === true && dragCardObj.moduleCustomHeight === 336,
                    "First Escape while naming prompt is open must close only the prompt and keep editMode active");
                overlay.handleEscape();
                wait(80);
                check(SettingsLayoutManager.editMode === false && dragCardObj.moduleCustomHeight === 272,
                    "Second Escape must exit editMode and revert to the snapshot at edit-session entry (272), got: " + dragCardObj.moduleCustomHeight);

                SettingsLayoutManager.resetAll();
                wait(60);

                // 12. Verify Standard Height Scroll Threshold (Themes & Style / Custom Theme = standardBentoHeight), Hidden Scrollbars, and Button Vertical Alignment
                overlay.overlayCurrentPage = 4; // ThemesConfig
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 4 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const themesPage4 = overlay.pageHost.currentItem;
                check(themesPage4.showVerticalScrollBar === false,
                    "ContentPage must hide vertical scrollbar (showVerticalScrollBar === false)");
                check(themesPage4.verticalScrollBar.visible === false,
                    "ThemesConfig vertical ScrollBar must never be visible");
                check(themesPage4.exceedsStandardHeight === false && themesPage4.interactive === false,
                    "Themes & Style ('colors') must match standardBentoHeight and disable scrolling, got pageContentBodyHeight="
                    + themesPage4.pageContentBodyHeight + " standardPageBodyHeight=" + themesPage4.standardPageBodyHeight
                    + " interactive=" + themesPage4.interactive);

                // Switch to Custom Theme ('advanced') sub-tab and verify it also matches standardBentoHeight without scrolling
                themesPage4.activeSection = "advanced";
                wait(150);
                check(themesPage4.exceedsStandardHeight === false && themesPage4.interactive === false,
                    "Custom Theme ('advanced') must match standardBentoHeight and disable scrolling, got pageContentBodyHeight="
                    + themesPage4.pageContentBodyHeight + " standardPageBodyHeight=" + themesPage4.standardPageBodyHeight
                    + " interactive=" + themesPage4.interactive);
                themesPage4.activeSection = "colors";
                wait(100);

                // Switch back to Bar page (page 2): verify default state (737 <= standardBentoHeight 901) does not scroll,
                // and when an active module exceeds standardBentoHeight, scrolling activates WITHOUT showing a scrollbar
                overlay.overlayCurrentPage = 2;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 2 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const barPageScrollCheck = overlay.pageHost.currentItem;
                check(barPageScrollCheck.exceedsStandardHeight === false && barPageScrollCheck.interactive === false,
                    "Bar page at default height (<= standardBentoHeight) must have interactive=false, got body="
                    + barPageScrollCheck.pageContentBodyHeight + " standard=" + barPageScrollCheck.standardPageBodyHeight);
                check(barPageScrollCheck.verticalScrollBar.visible === false,
                    "Bar page vertical scrollbar must remain hidden when non-interactive");

                // Resize an active module on Bar page so total pageContentBodyHeight exceeds standardPageBodyHeight
                const barModIds = Object.keys(SettingsLayoutManager._liveCardsByModuleId).filter(
                    id => id.indexOf("p2:") === 0
                        && SettingsLayoutManager._liveCardsByModuleId[id].visible
                        && SettingsLayoutManager._liveCardsByModuleId[id]._cardSubTabActive
                );
                check(barModIds.length >= 1, "Expected at least 1 visible active module on Bar page for scroll threshold test");
                SettingsLayoutManager.resizeModule(barModIds[0], { customHeight: 1100 });
                wait(150);
                check(barPageScrollCheck.pageContentBodyHeight > barPageScrollCheck.standardPageBodyHeight + 2,
                    "Resized Bar page should exceed standardPageBodyHeight, got body="
                    + barPageScrollCheck.pageContentBodyHeight + " standard=" + barPageScrollCheck.standardPageBodyHeight);
                check(barPageScrollCheck.exceedsStandardHeight === true && barPageScrollCheck.interactive === true,
                    "ContentPage exceeding standardBentoHeight must enable scrolling (interactive=true)");
                check(barPageScrollCheck.verticalScrollBar.visible === false,
                    "ContentPage exceeding standardBentoHeight must still hide vertical scrollbar (visible=false)");

                // Scroll to bottom of tall page, then shrink module height while still > standardPageBodyHeight and verify contentY clamps to new maxY
                const maxScrollTall = Math.max(0, barPageScrollCheck.contentHeight - barPageScrollCheck.height);
                barPageScrollCheck.contentY = maxScrollTall;
                wait(40);
                SettingsLayoutManager.resizeModule(barModIds[0], { customHeight: 950 });
                wait(150);
                const maxScrollMid = Math.max(0, barPageScrollCheck.contentHeight - barPageScrollCheck.height);
                check(barPageScrollCheck.interactive === true && barPageScrollCheck.contentY <= maxScrollMid + 1,
                    "When contentHeight shrinks while page remains interactive, contentY must clamp to new maxY (" + maxScrollMid + "), got: " + barPageScrollCheck.contentY + " interactive=" + barPageScrollCheck.interactive);

                // Reset module height so page returns <= standardBentoHeight and verify contentY resets to 0 and rejects programmatic scroll
                barPageScrollCheck.contentY = 48;
                wait(40);
                SettingsLayoutManager.resetAll();
                wait(150);
                check(barPageScrollCheck.exceedsStandardHeight === false && barPageScrollCheck.interactive === false,
                    "After resetting module height back <= standardBentoHeight, interactive must return to false");
                check(Math.abs(barPageScrollCheck.contentY) <= 1,
                    "When interactive becomes false, contentY must reset to 0, got: " + barPageScrollCheck.contentY);
                barPageScrollCheck.contentY = 120;
                wait(30);
                check(Math.abs(barPageScrollCheck.contentY) <= 1,
                    "Non-interactive ContentPage must clamp programmatic contentY back to 0, got: " + barPageScrollCheck.contentY);

                // Verify standardBentoHeight reactivity and Themes & Style / Custom Theme non-scrolling across fontSizeScale changes (0.85, 1.25, 1.0)
                const stdAt10 = SettingsMaterialPreset.standardBentoHeight;
                Config.setNestedValue("appearance.typography.sizeScale", 0.85);
                wait(150);
                check(SettingsMaterialPreset.standardBentoHeight < stdAt10 - 15,
                    "SettingsMaterialPreset.standardBentoHeight must reactively decrease when sizeScale=0.85 even off ThemesConfig, got: "
                    + SettingsMaterialPreset.standardBentoHeight + " vs " + stdAt10);
                overlay.overlayCurrentPage = 4;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 4 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const themesAt085 = overlay.pageHost.currentItem;
                themesAt085.activeSection = "colors";
                wait(120);
                check(themesAt085.exceedsStandardHeight === false && themesAt085.interactive === false,
                    "Themes & Style ('colors') at sizeScale=0.85 must not scroll, got body="
                    + themesAt085.pageContentBodyHeight + " standard=" + themesAt085.standardPageBodyHeight);
                themesAt085.activeSection = "advanced";
                wait(150);
                check(themesAt085.exceedsStandardHeight === false && themesAt085.interactive === false,
                    "Custom Theme ('advanced') at sizeScale=0.85 must not scroll, got body="
                    + themesAt085.pageContentBodyHeight + " standard=" + themesAt085.standardPageBodyHeight);

                Config.setNestedValue("appearance.typography.sizeScale", 1.25);
                wait(150);
                check(themesAt085.exceedsStandardHeight === false && themesAt085.interactive === false,
                    "Custom Theme ('advanced') at sizeScale=1.25 must not scroll, got body="
                    + themesAt085.pageContentBodyHeight + " standard=" + themesAt085.standardPageBodyHeight);
                themesAt085.activeSection = "colors";
                wait(150);
                check(themesAt085.exceedsStandardHeight === false && themesAt085.interactive === false,
                    "Themes & Style ('colors') at sizeScale=1.25 must not scroll, got body="
                    + themesAt085.pageContentBodyHeight + " standard=" + themesAt085.standardPageBodyHeight);

                Config.setNestedValue("appearance.typography.sizeScale", 1.0);
                wait(150);

                // Verify embedded ContentPages inside Loaders (AbyssPopupsConfig page 33 & AbyssConfig page 2 'bar' section) do not get crushed to 0 height
                overlay.overlayCurrentPage = 33;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 33 && overlay.pageHost.currentItem !== null, 6000);
                wait(200);
                const popupsPage33 = overlay.pageHost.currentItem;
                check(popupsPage33.pageContentBodyHeight > 200 && popupsPage33.sharedPopupsHeight > 200,
                    "AbyssPopupsConfig (page 33) embedded InterfaceConfig Loader must not be collapsed to 0 height, got body="
                    + popupsPage33.pageContentBodyHeight + " sharedPopupsHeight=" + popupsPage33.sharedPopupsHeight);

                overlay.overlayCurrentPage = 2;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 2 && overlay.pageHost.currentItem !== null, 6000);
                wait(120);
                const barPageForButtons = overlay.pageHost.currentItem;
                barPageForButtons.activateSettingsSearchSection("behavior");
                wait(150);
                check(barPageForButtons.pageContentBodyHeight > 200,
                    "AbyssConfig (page 2) embedded BarConfig Loader ('bar' section) must not be collapsed to 0 height, got: " + barPageForButtons.pageContentBodyHeight);
                barPageForButtons.activeSection = "surface";
                wait(100);

                // Verify Icon + Text vertical center alignment in buttons/chips across Settings
                SettingsLayoutManager.beginEditMode();
                wait(100);
                const editLayoutBtn = findByObjectName(host, "overlayEditSettingsLayoutButton");
                check(editLayoutBtn !== null && editLayoutBtn.contentItem !== null, "overlayEditSettingsLayoutButton missing contentItem");
                const editBtnChildren = editLayoutBtn.contentItem.children || [];
                if (editBtnChildren.length >= 2) {
                    const c0 = editBtnChildren[0].mapToItem(editLayoutBtn, 0, editBtnChildren[0].height / 2).y;
                    const c1 = editBtnChildren[1].mapToItem(editLayoutBtn, 0, editBtnChildren[1].height / 2).y;
                    const btnMid = editLayoutBtn.height / 2;
                    check(Math.abs(c0 - c1) <= 1.5 && Math.abs(c0 - btnMid) <= 2.0,
                        "overlayEditSettingsLayoutButton icon and text must be vertically centered: iconY=" + c0 + " textY=" + c1 + " btnMid=" + btnMid);
                }
                const addSubTabBtn12 = findByObjectName(barPageForButtons, "addSubTabPillButton");
                check(addSubTabBtn12 !== null && addSubTabBtn12.visible, "addSubTabPillButton should be visible in editMode");
                const addSubRow = (addSubTabBtn12.contentItem?.children?.length === 1) ? addSubTabBtn12.contentItem.children[0] : addSubTabBtn12.contentItem;
                if (addSubRow && (addSubRow.children?.length ?? 0) >= 2) {
                    const iconItem = addSubRow.children[0];
                    const textItem = addSubRow.children[1];
                    const iconMid = iconItem.mapToItem(addSubTabBtn12, 0, iconItem.height / 2).y;
                    const textMid = textItem.mapToItem(addSubTabBtn12, 0, textItem.height / 2).y;
                    const pillMid = addSubTabBtn12.height / 2;
                    check(Math.abs(iconMid - textMid) <= 1.5 && Math.abs(iconMid - pillMid) <= 2.0,
                        "addSubTabPillButton icon and text must be vertically centered: iconMid=" + iconMid + " textMid=" + textMid + " pillMid=" + pillMid);
                }
                // Sub-tab actions live in the dock's Tabs tier; open it before checking chip visibility
                extToolbar.selectDockTab("tabs");
                wait(40);
                check(extToolbar.activeDockTab === "tabs", "Dock Tabs tier did not activate");
                for (const chipName of ["innerEditModeChipButton", "addCustomSubTabChipButton", "settingsEditDoneButton"]) {
                    const chipBtn = findByObjectName(extToolbar, chipName);
                    check(chipBtn !== null && chipBtn.visible, "Expected visible toolbar chip: " + chipName);
                    const chipRow = (chipBtn.contentItem?.children?.length === 1) ? chipBtn.contentItem.children[0] : chipBtn.contentItem;
                    const visKids = (chipRow?.children || []).filter(k => k.visible);
                    if (visKids.length >= 2) {
                        const k0 = visKids[0].mapToItem(chipBtn, 0, visKids[0].height / 2).y;
                        const k1 = visKids[1].mapToItem(chipBtn, 0, visKids[1].height / 2).y;
                        const cMid = chipBtn.height / 2;
                        check(Math.abs(k0 - k1) <= 1.5 && Math.abs(k0 - cMid) <= 2.0,
                            chipName + " icon and text must be vertically centered: k0=" + k0 + " k1=" + k1 + " cMid=" + cMid);
                    }
                }
                SettingsLayoutManager.cancelEditMode();
                wait(60);

                // --- Test 13: AiConfig (page 24) loads cleanly with SettingsGroup.spacing and zero _donorIndices binding loops ---
                overlay.overlayCurrentPage = 24;
                wait(180);
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 24 && overlay.pageHost.currentItem !== null && !overlay.pageHost.error, 4000);
                const aiPage = overlay.pageHost.currentItem;
                check(aiPage !== null && !overlay.pageHost.error, "AiConfig (page 24) must load without error");

                // --- Test 14: Resize & Auto-Scale Flow Modules + Reset Module / Reset Page / Reset All without freezing ---
                overlay.overlayCurrentPage = 4; // ThemesConfig has Flow layouts inside SettingsCardSection
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 4 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const themesPageForResize = overlay.pageHost.currentItem;
                themesPageForResize.activeSection = "colors";
                wait(120);
                SettingsLayoutManager.beginEditMode();
                wait(100);
                const themeCards = themesPageForResize._eligibleCards || [];
                check(themeCards.length >= 2, "Expected at least 2 eligible cards on Themes & Style, got: " + themeCards.length);
                const flowCard = themeCards[0];
                const flowModId = flowCard.moduleId;
                const naturalFlowHeight = flowCard.naturalCardImplicitHeight;
                check(flowModId.length > 0, "Expected non-empty moduleId on flowCard");
                check(flowCard.moduleContentFitMode === "scale", "Flow card must default to 'scale' fit mode");

                // Select the card to activate its hover/selection toolbar, then verify simplified Customize button, Popover, and non-colliding handles
                SettingsLayoutManager.selectedModuleId = flowModId;
                wait(60);
                const customizeBtn = findByObjectName(flowCard, "moduleCustomizeButton");
                const customizePopover = findByObjectName(flowCard, "moduleCustomizePopover");
                const handleE = findByObjectName(flowCard, "cardResizeHandle_e");
                const handleS = findByObjectName(flowCard, "cardResizeHandle_s");
                const handleSE = findByObjectName(flowCard, "cardResizeHandle_se");
                const handleN = findByObjectName(flowCard, "cardResizeHandle_n");
                const handleNW = findByObjectName(flowCard, "cardResizeHandle_nw");
                const handleNE = findByObjectName(flowCard, "cardResizeHandle_ne");
                check(customizeBtn !== null && customizeBtn.visible, "moduleCustomizeButton must be visible on selected card in editMode");
                check(customizePopover !== null && customizePopover.visible === false, "moduleCustomizePopover must start closed");
                check(handleE !== null && handleE.visible && handleS !== null && handleS.visible && handleSE !== null && handleSE.visible,
                    "Bento card must show E, S, and SE resize handles when selected");
                check(handleN !== null && !handleN.visible && handleNW !== null && !handleNW.visible && handleNE !== null && !handleNE.visible,
                    "Top resize handles (N, NW, NE) must remain hidden so header drag and Customize button are never blocked");

                // Verify opening Customize popover elevates card z-order and pressing Escape closes the popover FIRST without exiting editMode
                flowCard.showMoveMenu = true;
                wait(60);
                check(customizePopover.visible === true && flowCard.z >= 100 && SettingsLayoutManager.openCustomizeModuleId === flowModId,
                    "moduleCustomizePopover must become visible and elevate card z-order when showMoveMenu is true");
                overlay.handleEscape();
                wait(60);
                check(flowCard.showMoveMenu === false && customizePopover.visible === false && SettingsLayoutManager.editMode === true,
                    "First Escape while moduleCustomizePopover is open must close only the popover and keep editMode active");

                // Verify width-only narrowing (customHeight === 0) auto-scales content AND reduces card height proportionally without blank space
                SettingsLayoutManager.resizeModule(flowModId, {
                    column: "left",
                    widthRatio: 0.5,
                    customHeight: 0
                });
                wait(150);
                check(flowCard.contentScaleFactor < 0.85,
                    "Narrowing module width below 380px must auto-scale content (< 0.85), got: " + flowCard.contentScaleFactor + " width=" + flowCard.renderedCardWidth);
                check(flowCard.renderedCardHeight < naturalFlowHeight - 40,
                    "Narrowing module width with auto-scale must proportionally shrink card height without dead bottom space (" + flowCard.renderedCardHeight + " vs " + naturalFlowHeight + ")");

                // Resize both widthRatio and customHeight smaller than natural height on a Flow-containing module
                SettingsLayoutManager.resizeModule(flowModId, {
                    column: "full",
                    widthRatio: 0.6,
                    customHeight: 176
                });
                wait(150);
                check(flowCard.moduleContentFitMode === "scale", "Resized Flow card must stay in 'scale' fit mode");
                check(flowCard.moduleCustomHeight === 176 && Math.abs(flowCard.renderedCardHeight - 176) <= 2,
                    "Resized Flow card height must be 176, got: " + flowCard.renderedCardHeight);
                check(flowCard.contentScaleFactor < 1.0 && flowCard.contentScaleFactor >= 0.35,
                    "Resized Flow card smaller than natural height must auto-scale content (< 1.0), got: " + flowCard.contentScaleFactor);
                const resetQuickBtn = findByObjectName(flowCard, "moduleResetQuickButton");
                check(resetQuickBtn !== null && resetQuickBtn.visible,
                    "moduleResetQuickButton must appear on card header once customized");

                // Reset individual module via resetModule and verify it returns to natural height without freezing
                SettingsLayoutManager.resetModule(flowModId);
                wait(150);
                check(flowCard.moduleCustomHeight === 0 && flowCard.moduleWidthRatio === 0 && flowCard.contentScaleFactor === 1.0,
                    "resetModule must clear customHeight, widthRatio, and restore contentScaleFactor=1.0");
                check(Math.abs(flowCard.naturalCardImplicitHeight - naturalFlowHeight) <= 4,
                    "resetModule must restore Flow card natural height (" + flowCard.naturalCardImplicitHeight + " vs " + naturalFlowHeight + ")");

                // Resize multiple modules on Themes page, then run autoFitPageModules (Reset Page) and verify clean restoration
                SettingsLayoutManager.resizeModule(flowModId, { widthRatio: 0.5, customHeight: 192 });
                SettingsLayoutManager.resizeModule(themeCards[1].moduleId, { widthRatio: 0.75, customHeight: 208 });
                wait(150);
                SettingsLayoutManager.autoFitPageModules(4, "");
                wait(150);
                check(flowCard.moduleCustomHeight === 0 && themeCards[1].moduleCustomHeight === 0,
                    "autoFitPageModules (Reset Page) must reset customHeight to 0 on all page modules");
                check(flowCard.moduleWidthRatio === 0 && themeCards[1].moduleWidthRatio === 0,
                    "autoFitPageModules (Reset Page) must reset widthRatio to 0 on all page modules");
                // In editMode the bottom-docked dock adds a scroll reserve; body height still fits the standard budget
                check(themesPageForResize.exceedsStandardHeight === false
                    && themesPageForResize.interactive === (themesPageForResize._editScrollReserve > 0),
                    "After autoFitPageModules on Themes & Style, page must return to standardBentoHeight without scrolling, got body="
                    + themesPageForResize.pageContentBodyHeight + " standard=" + themesPageForResize.standardPageBodyHeight);

                // Verify Canvas mode module reset immediately restores default Canvas dimensions instead of staying stuck at custom canvasW/canvasH
                SettingsLayoutManager.updatePageLayoutConfig(4, "", { layoutMode: "canvas" });
                wait(120);
                check(flowCard.isCanvasMode === true, "Themes card should enter canvas mode");
                const defaultCanvasW = flowCard.width;
                const defaultCanvasH = flowCard.height;
                SettingsLayoutManager.resizeModule(flowModId, { canvasX: 32, canvasY: 32, canvasW: 320, canvasH: 192 });
                wait(100);
                check(flowCard.width === 320 && flowCard.height === 192, "Canvas resize did not apply 320x192");
                SettingsLayoutManager.resizeModule(flowModId, { widthRatio: 0, customHeight: 0, canvasW: 0, canvasH: 0 });
                wait(100);
                check(Math.abs(flowCard.width - defaultCanvasW) <= 4 && Math.abs(flowCard.height - defaultCanvasH) <= 4,
                    "Resetting canvasW/canvasH to 0 must immediately restore default Canvas dimensions (" + flowCard.width + "x" + flowCard.height + " vs " + defaultCanvasW + "x" + defaultCanvasH + ")");
                SettingsLayoutManager.autoFitPageModules(4, "");
                wait(120);

                // Verify Custom Theme sub-tab ('advanced') height parity (<= 824px viewport budget) and full Edit Mode support
                const colorsBodyHeight = themesPageForResize.pageContentBodyHeight;
                check(colorsBodyHeight >= 780 && colorsBodyHeight <= 824,
                    "Themes & Style ('colors') body height must fit 1920x1200 viewport (780..824px), got: " + colorsBodyHeight);

                themesPageForResize.activeSection = "advanced";
                wait(180);
                const customThemeCard = SettingsLayoutManager._liveCardsByModuleId["p4:custom-theme-editor"];
                check(customThemeCard !== null && customThemeCard !== undefined && customThemeCard.visible && customThemeCard._cardSubTabActive,
                    "Custom Theme Editor ('p4:custom-theme-editor') must be registered and active on 'advanced' sub-tab");
                const advancedBodyHeight = themesPageForResize.pageContentBodyHeight;
                check(Math.abs(advancedBodyHeight - colorsBodyHeight) <= 2 && advancedBodyHeight <= 824,
                    "Custom Theme ('advanced') body height must match Themes & Style ('colors') and stay <= 824px, got advanced="
                    + advancedBodyHeight + " colors=" + colorsBodyHeight);
                // In editMode the bottom-docked dock adds a scroll reserve; body height still fits the standard budget
                check(themesPageForResize.exceedsStandardHeight === false
                    && themesPageForResize.interactive === (themesPageForResize._editScrollReserve > 0),
                    "Custom Theme ('advanced') must fit within standardPageBodyHeight without scrolling, got body="
                    + advancedBodyHeight + " standard=" + themesPageForResize.standardPageBodyHeight);

                SettingsLayoutManager.selectedModuleId = "p4:custom-theme-editor";
                wait(80);
                const customThemeCustomizeBtn = findByObjectName(customThemeCard, "moduleCustomizeButton");
                const customThemeHandleS = findByObjectName(customThemeCard, "cardResizeHandle_s");
                check(customThemeCustomizeBtn !== null && customThemeCustomizeBtn.visible && customThemeHandleS !== null && customThemeHandleS.visible,
                    "Custom Theme Editor card must expose moduleCustomizeButton and resize handles in Edit Mode");

                const customThemeInnerOverlays = findAllInnerOverlays(customThemeCard).filter(o => o.visible);
                check(customThemeInnerOverlays.length >= 3,
                    "Custom Theme Editor inner card containers (left-col, right-col, bottom-grid) must expose visible reorder/sizing overlays in Bento Edit Mode, got: "
                    + customThemeInnerOverlays.length);

                SettingsLayoutManager.resizeModule("p4:custom-theme-editor", { customHeight: 624 });
                wait(120);
                check(Math.abs(customThemeCard.renderedCardHeight - 624) <= 2,
                    "Resizing p4:custom-theme-editor to customHeight=624 must update renderedCardHeight, got: " + customThemeCard.renderedCardHeight);

                SettingsLayoutManager.autoFitPageModules(4, "");
                wait(120);
                check(customThemeCard.moduleCustomHeight === 0 && Math.abs(customThemeCard.renderedCardHeight - colorsBodyHeight) <= 2,
                    "autoFitPageModules on Custom Theme must restore standard height (" + colorsBodyHeight + "), got: " + customThemeCard.renderedCardHeight);
                themesPageForResize.activeSection = "colors";
                wait(100);

                // --- Test 15: EffectsConfig (page 25, _preventBentoReparent GridLayout + Layout.fillHeight cards) height resize, Canvas safety, and reset ---
                overlay.overlayCurrentPage = 25;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 25 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const effectsPage = overlay.pageHost.currentItem;
                const effectsModIds = Object.keys(SettingsLayoutManager._liveCardsByModuleId).filter(
                    id => id.indexOf("p25:") === 0
                        && SettingsLayoutManager._liveCardsByModuleId[id].visible
                        && SettingsLayoutManager._liveCardsByModuleId[id]._cardSubTabActive
                );
                check(effectsModIds.length >= 1, "Expected at least 1 active card on EffectsConfig (page 25)");
                const fxCard = SettingsLayoutManager._liveCardsByModuleId[effectsModIds[0]];
                const fxDefaultWidth = fxCard.renderedCardWidth;
                check(fxDefaultWidth > 200, "EffectsConfig card must have valid width > 200, got: " + fxDefaultWidth);

                // Resize height on a Layout.fillHeight card and verify renderedCardHeight honors customHeight
                SettingsLayoutManager.resizeModule(fxCard.moduleId, { customHeight: 176 });
                wait(120);
                check(Math.abs(fxCard.renderedCardHeight - 176) <= 2,
                    "EffectsConfig card with Layout.fillHeight: true must honor customHeight=176 when resized, got: " + fxCard.renderedCardHeight);

                // Switch EffectsConfig to canvas mode and verify _preventBentoReparent GridLayout cards do NOT collapse to 0 width
                SettingsLayoutManager.updatePageLayoutConfig(25, "", { layoutMode: "canvas" });
                wait(120);
                check(fxCard.isCanvasMode === false && fxCard.renderedCardWidth > 200,
                    "_preventBentoReparent card inside GridLayout must keep isCanvasMode=false and non-zero width when page is in canvas mode, got width=" + fxCard.renderedCardWidth);

                SettingsLayoutManager.autoFitPageModules(25, "");
                wait(120);
                check(fxCard.moduleCustomHeight === 0 && fxCard.renderedCardWidth > 200,
                    "autoFitPageModules on EffectsConfig must cleanly restore default card sizing");

                SettingsLayoutManager.resetAll();
                SettingsLayoutManager.commitEditMode();
                wait(100);

                // --- Test 16: DefaultAppsConfig (page 39) Full-Width Inner Layout, Single-Card EditMode Width Preservation, Equal Grid Columns & Strict Horizontal Containment ---
                CompositorService.isNiri = true;
                overlay.overlayCurrentPage = 39;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 39 && overlay.pageHost.currentItem !== null, 6000);
                wait(300);
                const appsPage39 = overlay.pageHost.currentItem;
                appsPage39.activeSection = "primary";
                wait(200);

                // Stress-test long app name + Flatpak · Flathub + Portable badge + Niri shortcut button
                const mockZenApp = {
                    identityKey: "flatpak:flathub:app.zen_browser.zen",
                    desktopId: "alis-app-zen-browser.desktop",
                    name: "Zen Browser Developer Edition With Extremely Long Application Title That Must Elide Cleanly",
                    exec: "/home/llocphann/Applications/Zen-Browser-Developer-Edition-Very-Long-Path-x86_64.AppImage --profile /home/llocphann/.zen",
                    icon: "web-browser",
                    source: "flatpak",
                    sourceBadge: "Flatpak · Flathub",
                    installed: true,
                    isFlatpak: true
                };
                const mockNetApp = {
                    identityKey: "native:nm-connection-editor",
                    desktopId: "nm-connection-editor.desktop",
                    name: "Advanced Network Configuration & Virtual Interface Manager Utility",
                    exec: "/usr/bin/nm-connection-editor --keep-above",
                    icon: "preferences-system-network",
                    source: "native",
                    sourceBadge: "Native",
                    installed: true
                };
                const mockPortableOfficeApp = {
                    identityKey: "native:alis-app-portable-zsync",
                    desktopId: "alis-app-portable-zsync.desktop",
                    name: "LibreOffice Portable",
                    exec: "/tmp/LibreOffice.AppImage",
                    icon: "x-office-document",
                    source: "native",
                    sourceBadge: "Native",
                    installed: true
                };
                AppLauncher.discoveredApps = (AppLauncher.discoveredApps ?? []).concat([
                    mockZenApp,
                    mockNetApp,
                    mockPortableOfficeApp
                ]);
                AppLauncher.selectDiscoveredApp("browser", mockZenApp);
                AppLauncher.selectDiscoveredApp("network", mockNetApp);
                wait(150);

                const twoColGrid = findByObjectName(appsPage39, "defaultAppsTwoColumnGrid");
                const portableSec = findByObjectName(appsPage39, "defaultAppsPortableSection");
                check(twoColGrid !== null && portableSec !== null && twoColGrid.width > 800,
                    "defaultAppsTwoColumnGrid must fill page width (>800), got: " + (twoColGrid ? twoColGrid.width : "null"));

                function verifySlotsContainment(slotDefs, labelPrefix) {
                    for (let i = 0; i < slotDefs.length; i++) {
                        const sid = slotDefs[i].id;
                        const cur = findByObjectName(appsPage39, "defaultAppCurrent_" + sid);
                        const nameTxt = findByObjectName(appsPage39, "defaultAppName_" + sid);
                        const badge = findByObjectName(appsPage39, "defaultAppBadge_" + sid);
                        const chooseBtn = findByObjectName(appsPage39, "defaultAppChooseBtn_" + sid);
                        const syncBtn = findByObjectName(appsPage39, "defaultAppSyncXdgBtn_" + sid);
                        const shortBtn = findByObjectName(appsPage39, "defaultAppShortcutBtn_" + sid);
                        const customBtn = findByObjectName(appsPage39, "defaultAppCustomBtn_" + sid);
                        check(cur !== null && nameTxt !== null && badge !== null && chooseBtn !== null,
                            labelPrefix + " missing slot elements for " + sid);
                        const nameBox = nameTxt.mapToItem(cur, 0, 0);
                        const badgeBox = badge.mapToItem(cur, 0, 0);
                        const chooseBox = chooseBtn.mapToItem(cur, 0, 0);
                        const lastBtn = (syncBtn && syncBtn.visible) ? syncBtn : ((shortBtn && shortBtn.visible) ? shortBtn : customBtn);
                        const lastBox = lastBtn.mapToItem(cur, 0, 0);
                        check((lastBox.x + lastBtn.width) <= (cur.width - 5.5),
                            labelPrefix + " slot " + sid + " action buttons overflowed card border: lastBtnRight="
                            + (lastBox.x + lastBtn.width) + " curW=" + cur.width);
                        check((badgeBox.x + badge.width) <= (chooseBox.x - 4.0),
                            labelPrefix + " slot " + sid + " badge collided with action buttons: badgeRight="
                            + (badgeBox.x + badge.width) + " chooseX=" + chooseBox.x);
                        check((nameBox.x + nameTxt.width) <= (badgeBox.x + 1.0),
                            labelPrefix + " slot " + sid + " app name overlapped source badge: nameRight="
                            + (nameBox.x + nameTxt.width) + " badgeX=" + badgeBox.x);
                        check(nameTxt.width >= Math.min(nameTxt.implicitWidth - 0.5, 48),
                            labelPrefix + " slot " + sid + " app name was crushed below readable minimum width: got "
                            + nameTxt.width + " (implicitWidth=" + nameTxt.implicitWidth + ")");
                    }
                }

                verifySlotsContainment(AppLauncher.primarySlotDefinitions(), "PrimarySlots");

                // Verify Portable Applications (ApplicationsConfig) inside DefaultAppsConfig 2-column grid:
                // 1) Long app name without Default slot pill uses >45% of titleTagsRow width (not prematurely truncated at 42%)
                // 2) Portable app with AppImage + zsync + long "Default: Office Documents (.docx, .xlsx, .pptx)" badge keeps app name >= 48px and never overflows
                AppLauncher.selectDiscoveredApp("officeSuite", mockPortableOfficeApp);
                portableSec.managedApps = [
                    {
                        id: "portable-plain",
                        name: "SuperLongPortableApplicationNameWithoutDefaultRoleAssigned",
                        kind: "appimage",
                        hasZsync: false,
                        installed: true,
                        execPath: "/tmp/plain.AppImage"
                    },
                    {
                        id: "portable-zsync",
                        name: "LibreOffice Portable Suite With Long Name",
                        kind: "appimage",
                        hasZsync: true,
                        installed: true,
                        execPath: "/tmp/LibreOffice.AppImage"
                    }
                ];
                wait(150);
                const plainCard = findByObjectName(portableSec, "portableAppCard_portable-plain");
                const plainName = findByObjectName(portableSec, "portableAppName_portable-plain");
                const zsyncCard = findByObjectName(portableSec, "portableAppCard_portable-zsync");
                const zsyncName = findByObjectName(portableSec, "portableAppName_portable-zsync");
                const zsyncDefBadge = findByObjectName(portableSec, "portableDefaultBadge_portable-zsync");
                const zsyncRemoveBtn = findByObjectName(portableSec, "removeApplicationBtn_portable-zsync");
                check(plainCard !== null && plainName !== null && zsyncCard !== null && zsyncName !== null && zsyncDefBadge !== null && zsyncRemoveBtn !== null,
                    "Expected portableAppCard elements to be instantiated in ApplicationsConfig");
                check(plainName.width > plainName.parent.width * 0.48,
                    "Portable app name without Default badge must not be prematurely truncated at 42% of row width: nameW="
                    + plainName.width + " rowW=" + plainName.parent.width);
                check(zsyncName.width >= 48 && zsyncDefBadge.visible,
                    "Portable app name with AppImage + zsync + Default: Office Documents badge must remain >= 48px wide, got: " + zsyncName.width);
                const zsyncBadgeRightInRow = zsyncDefBadge.x + zsyncDefBadge.width;
                check(zsyncBadgeRightInRow <= zsyncDefBadge.parent.width + 1,
                    "Portable app badges must not overflow titleTagsRow width: badgeRight=" + zsyncBadgeRightInRow + " rowW=" + zsyncDefBadge.parent.width);
                const zsyncRemoveBox = zsyncRemoveBtn.mapToItem(zsyncCard, 0, 0);
                check((zsyncRemoveBox.x + zsyncRemoveBtn.width) <= (zsyncCard.width - 5.5),
                    "Portable app remove button must stay inside card right border: btnRight=" + (zsyncRemoveBox.x + zsyncRemoveBtn.width) + " cardW=" + zsyncCard.width);

                // Switch to System Utilities ('utilities'): verify full-width inner layout and equal 2-column grid widths
                appsPage39.activeSection = "utilities";
                wait(200);
                const utilCard = findByObjectName(appsPage39, "defaultAppsUtilitiesCard");
                const utilDisc = findByObjectName(appsPage39, "defaultAppsUtilitiesDiscoverySummary");
                const utilSecContent = findByObjectName(utilCard, "sectionContent");
                check(utilCard !== null && utilSecContent !== null && utilDisc !== null,
                    "System Utilities card / sectionContent / discovery bar not found");
                check(utilCard.width > 900 && Math.abs(utilSecContent.width - (utilCard.width - 22)) <= 2 && Math.abs(utilDisc.width - utilSecContent.width) <= 2,
                    "System Utilities inner sectionContent and discovery bar must fill full card width, got cardW="
                    + utilCard.width + " secContentW=" + utilSecContent.width + " discW=" + utilDisc.width);
                verifySlotsContainment(AppLauncher.utilitySlotDefinitions(), "UtilitySlots");

                const curManageUser = findByObjectName(appsPage39, "defaultAppCurrent_manageUser");
                const curNetwork = findByObjectName(appsPage39, "defaultAppCurrent_network");
                check(curManageUser !== null && curNetwork !== null && Math.abs(curManageUser.width - curNetwork.width) <= 2,
                    "System Utilities 2-column grid must have equal column widths: left=" + (curManageUser ? curManageUser.width : 0)
                    + " right=" + (curNetwork ? curNetwork.width : 0));

                // Entering editMode on a single-card sub-tab must keep the card at 100% full width (not squished to 50% by empty rightBentoColumn)
                SettingsLayoutManager.beginEditMode();
                wait(120);
                check(utilCard.width > 900 && Math.abs(utilSecContent.width - (utilCard.width - 22)) <= 2,
                    "Single-card System Utilities must remain full-width in editMode, got cardW=" + utilCard.width + " secContentW=" + utilSecContent.width);

                // Resizing a full-width card to widthRatio=0.5 (~497px wide, contentFlickable ~475px >= 468px single Bento column)
                // must lay out at 475px with contentScaleFactor === 1.0 (not shrunk to 0.49x!), and slots must still contain their badges/buttons
                SettingsLayoutManager.resizeModule(utilCard.moduleId, { widthRatio: 0.5 });
                wait(150);
                check(Math.abs(utilCard.contentScaleFactor - 1.0) < 0.02,
                    "Full-width card resized to widthRatio=0.5 (~475px content width >= 468px Bento column) must keep contentScaleFactor=1.0, got: " + utilCard.contentScaleFactor);
                verifySlotsContainment(AppLauncher.utilitySlotDefinitions(), "UtilitySlotsAtHalfWidth");
                SettingsLayoutManager.resetModule(utilCard.moduleId);
                wait(120);

                // Switch to Autostart sub-tab ('autostart') and verify long "Default: Office Documents (.docx, .xlsx, .pptx)" badge
                // elides cleanly without crushing autostartAppName_* to 0px
                SettingsLayoutManager.cancelEditMode();
                wait(100);
                appsPage39.activeSection = "autostart";
                wait(200);
                const autostartList = findByObjectName(appsPage39, "autostartAppsListView");
                check(autostartList !== null, "Expected autostartAppsListView in AutostartConfig");
                autostartList.model = [
                    {
                        id: "alis-app-portable-zsync",
                        name: "LibreOffice Portable Document Suite With Long Title",
                        comment: "Office productivity suite",
                        exec: "/tmp/LibreOffice.AppImage",
                        icon: "x-office-document"
                    }
                ];
                wait(150);
                const autoName = findByObjectName(appsPage39, "autostartAppName_alis-app-portable-zsync");
                const autoDefBadge = findByObjectName(appsPage39, "autostartDefaultBadge_alis-app-portable-zsync");
                check(autoName !== null && autoDefBadge !== null && autoDefBadge.visible,
                    "Expected autostartAppName and autostartDefaultBadge in AutostartConfig");
                check(autoName.width >= 68,
                    "Autostart app name with long Default: Office Documents badge must retain readable width (>=68px), got: " + autoName.width);
                check((autoDefBadge.x + autoDefBadge.width) <= (autoDefBadge.parent.width + 1),
                    "Autostart Default role badge must stay strictly inside appTitleBadgeRow: badgeRight="
                    + (autoDefBadge.x + autoDefBadge.width) + " rowW=" + autoDefBadge.parent.width);

                // Verify that on a Bento page where all cards are in the left column (_leftBentoCount >= 1, _rightBentoCount === 0),
                // starting a module drag expands the empty rightBentoColumn drop target to match leftBentoColumn height (>=150px, not clamped to 44px)
                overlay.overlayCurrentPage = 4;
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 4 && overlay.pageHost.currentItem !== null, 6000);
                wait(150);
                const bentoDragPage = overlay.pageHost.currentItem;
                SettingsLayoutManager.beginEditMode();
                wait(80);
                const bentoCards = bentoDragPage._eligibleCards || [];
                for (let bi = 0; bi < bentoCards.length; bi++) {
                    SettingsLayoutManager.resizeModule(bentoCards[bi].moduleId, { column: "left" });
                }
                wait(120);
                const rightBentoCol = findByObjectName(bentoDragPage, "rightBentoColumn");
                SettingsLayoutManager.beginModuleDrag(bentoCards[0].moduleId, bentoCards[0], 200, 200);
                wait(80);
                check(rightBentoCol !== null && rightBentoCol.visible && rightBentoCol.height >= 150,
                    "Empty rightBentoColumn during module drag must expand to sibling column height (>=150px), got: " + (rightBentoCol ? rightBentoCol.height : 0));
                const rightDropPt = rightBentoCol.mapToItem(null, rightBentoCol.width / 2, 140);
                SettingsLayoutManager.updateModuleDrag(rightDropPt.x, rightDropPt.y);
                check(SettingsLayoutManager.hoveredDropTarget && SettingsLayoutManager.hoveredDropTarget.targetId.indexOf("col-right:") === 0,
                    "Dragging to y=140 inside empty rightBentoColumn must hit col-right drop target, got: " + (SettingsLayoutManager.hoveredDropTarget?.targetId ?? "null"));
                SettingsLayoutManager.cancelModuleDrag();
                SettingsLayoutManager.cancelEditMode();
                wait(100);

                console.info("SETTINGS_MODULAR_LAYOUT_RUNTIME_PASS");
            } catch (e) {
                console.error("SETTINGS_MODULAR_LAYOUT_RUNTIME_FAIL", e.message, e.stack);
            }
            Qt.quit();
        }
    }

    Timer {
        interval: 100
        running: true
        onTriggered: test.runSuite()
    }
}
"""
    with tempfile.TemporaryDirectory(prefix="alis-settings-modular-") as name:
        folder = Path(name)
        for entry in [
            "modules", "services", "GlobalStates.qml", "qmldir", "assets",
            "scripts", "defaults", "translations", "settings.qml", "waffleSettings.qml"
        ]:
            (folder / entry).symlink_to(ROOT / entry)
        (folder / "shell.qml").write_text(qml_test, encoding="utf-8")
        runtime = folder / "runtime"
        runtime.mkdir(mode=0o700, exist_ok=True)
        base_env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime))
        for key in [
            "WAYLAND_DISPLAY",
            "NIRI_SOCKET",
            "DISPLAY",
            "HYPRLAND_INSTANCE_SIGNATURE",
            "QS_CONFIG_NAME",
            "QS_CONFIG_PATH",
            "QS_MANIFEST",
        ]:
            base_env.pop(key, None)
        for kind in ["config", "cache", "data", "state"]:
            (folder / kind).mkdir(parents=True, exist_ok=True)
            base_env[f"XDG_{kind.upper()}_HOME"] = str(folder / kind)
        sock = "wayland-alis-headless-settings"
        kwin = subprocess.Popen(
            ["kwin_wayland", "--virtual", "--socket", sock, "--width", "1280", "--height", "900"],
            env=base_env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        try:
            for _ in range(80):
                if (runtime / sock).exists():
                    break
                time.sleep(0.05)
            env = dict(
                base_env,
                WAYLAND_DISPLAY=sock,
                QT_QPA_PLATFORM="wayland",
                QT_QUICK_BACKEND="software",
                QSG_RHI_BACKEND="software",
            )
            conf = folder / "config/alis"
            conf.mkdir(parents=True, exist_ok=True)
            value = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
            value["panelFamily"] = "abyss"
            (conf / "config.json").write_text(json.dumps(value), encoding="utf-8")
            result = run_qs(folder, env, timeout=75)
        finally:
            if kwin.poll() is None:
                os.killpg(kwin.pid, 15)
                try:
                    kwin.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    os.killpg(kwin.pid, 9)
        output = result.stdout
        if (
            result.returncode
            or "SETTINGS_MODULAR_LAYOUT_RUNTIME_PASS" not in output
            or any(
                err in output
                for err in [
                    "SETTINGS_MODULAR_LAYOUT_RUNTIME_FAIL",
                    "ReferenceError:",
                    "TypeError:",
                    "Unable to assign",
                    "Cannot assign to non-existent property",
                    "Binding loop detected for property \"_donorIndices\"",
                    "failed to load page",
                    "Failed to load configuration",
                ]
            )
        ):
            print(output)
            raise SystemExit(1)
        print("PASS: Quickshell runtime modular layout, cross-tab drag/move, custom tabs, and vertical/resizable sliders")


if __name__ == "__main__":
    run_policy_unit_tests()
    run_quickshell_runtime_tests()
