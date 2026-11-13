#!/usr/bin/env python3
"""Regression test for Slice 4 Abyss upgrades:
- (F) Deterministic, fixed positions when hovering between Edgebar Popups and Sidebars
      (`placementPriority: 1` for `quickNotes`/`notificationCenter` < Sidebar `2`,
      no hover/focus `promoteInteractionOrder` swapping) + Companion `externalBlockers`.
- (H) Quick Notes (`styledPopupHosts`) focus is preserved when Left Sidebar opens.
- (I) Closed `SidebarReveal` strictly uses a ~180px physical center trigger band,
      unaffected by `peerOpen` (Quick Notes / Overview).
- (J) Only `cava` module protrudes outward along with Left/Right Sidebar, and
      `cavaAdjustedGeometry` shifts/shrinks Cava cleanly into the exposed Sidebar
      edge segment so Right/Left Cava never overlaps an open Edgebar Popup.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_source_and_js_contracts() -> None:
    perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    bar = (ROOT / "modules/abyss/bar/AbyssBar.qml").read_text(encoding="utf-8")
    host = (ROOT / "modules/abyss/AbyssBodyHost.qml").read_text(encoding="utf-8")
    companion_surface = (ROOT / "modules/abyss/AlisCompanionSurface.qml").read_text(encoding="utf-8")

    # (H) Quick Notes / StyledPopup focus preservation in AbyssPerimeter
    assert "function presentedBodyHostForItem(item: Item): var" in perimeter
    assert "if (ph.embeddedItem === node)" in perimeter
    assert "&& !liquid.popupExclusiveFocus" in perimeter

    # (I) 180px physical center SidebarReveal trigger
    assert "readonly property bool expandedEdgeSpan: sidebarBody.open" in perimeter
    assert "expandedEdgeSpan: sidebarBody.open || peerOpen" not in perimeter
    assert "Math.max(140, axisExtent * (180 / 1080))" in perimeter
    assert "readonly property real triggerCenter: axisExtent / 2" in perimeter

    # (J) Cava-only protrusion wiring & cycle-free popup hover delivery
    assert 'if (root.editing || !rec || rec.kind !== "cava")' in bar
    assert "readonly property var baseRenderedRecords:" in bar
    assert "readonly property var clearanceDeformations:" in bar
    assert "bar.visible ? bar.clearanceDeformations : []" in perimeter
    assert 'edgeInsets: window.bodyInsets(edge,along,span,"cava")' in perimeter
    assert "leftSidebarRecord: leftPanel.progress > 0.001 ? leftPanel.record : null" in perimeter
    assert "rightSidebarRecord: rightPanel.progress > 0.001 ? rightPanel.record : null" in perimeter
    bar_block = perimeter.split("AbyssBar {", 1)[1].split("onInteraction:", 1)[0]
    assert "z:" not in bar_block, "AbyssBar must stay at default z:0 below z:1 popups so barHover never steals popup hover"
    assert "HoverHandler { id: barHover; blocking: false;" in bar_block, "barHover must never block sibling popup HoverHandlers"

    # (F) Fixed non-swapping popup/sidebar positions & Companion obstacle awareness
    assert "promoteInteractionOrder" not in perimeter, (
        "AbyssPerimeter must never call promoteInteractionOrder on hover/focus (causes popup/sidebar position swapping)"
    )
    assert '(vacancyRole === "quickNotes" || vacancyRole === "notificationCenter")' in perimeter
    assert "idleSurfaceWarmupTimer" not in perimeter, "idleSurfaceWarmupTimer causes mid-session main-thread freezes"
    assert "!window.dockBlockedByPopups(popupCheckSurface)" in perimeter
    assert "popupObstacleRects: window.popupObstacleRects" in perimeter
    assert "readonly property var obstacleRects:" in companion_surface
    assert "externalBlockers: companionExtension.obstacleRects" in perimeter

    # Extract production cavaAdjustedGeometry & cavaProtrusionForRecord bodies from AbyssBar.qml
    m_geom = re.search(
        r"function cavaAdjustedGeometry\(rec\): var \{([\s\S]*?)\n    \}",
        bar,
    )
    assert m_geom is not None, "cavaAdjustedGeometry not found in AbyssBar.qml"
    cava_geom_body = m_geom.group(1)

    m_prot = re.search(
        r"function cavaProtrusionForRecord\(rec\): real \{([\s\S]*?)\n    \}",
        bar,
    )
    assert m_prot is not None, "cavaProtrusionForRecord not found in AbyssBar.qml"
    cava_prot_body = m_prot.group(1)

    layout_js = (ROOT / "modules/abyss/looks/AbyssLayout.js").read_text(encoding="utf-8")
    vacancy_js = (ROOT / "modules/abyss/looks/AbyssVacancyBorrowing.js").read_text(encoding="utf-8")
    js_prog = (
        f"const L=(function(){{{layout_js}\nreturn {{localSurfaces,clearanceInsets}};}})();\n"
        f"const V=(function(){{{vacancy_js}\nreturn {{resolve}};}})();\n"
        f"function cavaAdjustedGeometry(root, rec) {{{cava_geom_body}\n}}\n"
        f"function cavaProtrusion(root, rec) {{"
        f"root.cavaAdjustedGeometry = (r) => cavaAdjustedGeometry(root, r);"
        f"{cava_prot_body}\n}}\n"
        r"""
const assert = require("node:assert/strict");

// 1. Cava protrusion math on left & right edges (0 -> mid -> full open, non-cava ignored)
const mockBar = {
    editing: false,
    width: 1920,
    basePaintInsets: { left: 16, top: 16, right: 16, bottom: 16 },
    popupObstacleRects: [],
    leftSidebarRecord: { edge: "left", progress: 1, surface: { x: -50, y: 180, width: 526, height: 720 } }, // innerRight = 476
    rightSidebarRecord: { edge: "right", progress: 0.5, surface: { x: 1674, y: 180, width: 296, height: 720 } } // innerLeft = 1674
};
assert.equal(cavaProtrusion(mockBar, { kind: "cava", edge: "left", along: 480, span: 120 }), 460);
assert.equal(cavaProtrusion(mockBar, { kind: "cava", edge: "right", along: 480, span: 120 }), (1920 - 16) - 1674);
assert.equal(cavaProtrusion(mockBar, { kind: "clock", edge: "left", along: 480, span: 120 }), 0, "non-cava never protrudes");
assert.equal(cavaProtrusion(mockBar, { kind: "cava", edge: "top", along: 480, span: 120 }), 0, "top cava never protrudes");
assert.equal(cavaProtrusion(mockBar, { kind: "cava", edge: "left", along: 20, span: 100 }), 0, "non-overlapping cava stays at edge");
assert.equal(cavaProtrusion({ ...mockBar, editing: true }, { kind: "cava", edge: "left", along: 480, span: 120 }), 0, "edit mode stays at edge");

// 1b. Right Cava + NotificationCenterPopup avoidance: shifts cleanly into upper exposed Sidebar edge!
const mockRightWithPopup = {
    editing: false,
    width: 1920,
    basePaintInsets: { left: 16, top: 16, right: 16, bottom: 16 },
    leftSidebarRecord: null,
    rightSidebarRecord: { edge: "right", progress: 1, surface: { x: 1450, y: 40, width: 470, height: 940 } },
    popupObstacleRects: [{ x: 1035, y: 395, width: 415, height: 585 }] // NotificationCenterPopup adjacent to Right Sidebar
};
const adjRight = cavaAdjustedGeometry(mockRightWithPopup, { kind: "cava", edge: "right", along: 389, span: 300 });
assert.equal(adjRight.protrudeOffset, (1920 - 16) - 1450);
assert.equal(adjRight.span, 300, "full 300px Cava span preserved when upper exposed segment fits");
assert(adjRight.along >= 56 && adjRight.along + adjRight.span <= 395 - 14 + 0.01,
    `Right Cava [${adjRight.along}..${adjRight.along + adjRight.span}] must clear NotificationCenterPopup top (395)`);

// 2. Cava localSurfaces extends capsule depth by protrudeOffset even on normal 16px edge
const opts = { edgeThickness: 16, edgeWidthAffectsModules: { left: true, right: true } };
const cavaRec = {
    id: "cava", kind: "cava", edge: "left", vertical: true,
    along: 480, span: 120, protrudeOffset: 460,
    content: { x: 468, y: 480, width: 32, height: 120 }
};
const clockRec = {
    id: "clock", kind: "clock", edge: "left", vertical: true,
    along: 200, span: 104, protrudeOffset: 0,
    content: { x: 8, y: 200, width: 32, height: 104 }
};
const surfs = L.localSurfaces([cavaRec, clockRec], 1920, 1080, opts, 1, 36);
assert.equal(surfs.length, 1, "only protruding cava emits localSurface on standard edge");
assert.equal(surfs[0].kind, "cava");
assert.equal(surfs[0].depth, (32 + 16) + 460);
assert.equal(surfs[0].surface.x + surfs[0].surface.width, 508, "capsule reaches 32px past 476px sidebar");

// Sidebars ignore cava in clearanceInsets so leftPanel/rightPanel stay flush to nativeInsets
const cleared = L.clearanceInsets({ left: 16, top: 16, right: 16, bottom: 16 }, surfs, "left", 180, 720, "cava");
assert.equal(cleared.left, 16, "sidebar clearance ignores protruding cava");

// 3. VacancyBorrowing respects Companion externalBlockers (e.g. PocketPane / hovered TalkCloud)
const W = 1800, H = 1000, IN = { left: 16, right: 16, top: 16, bottom: 16 }, G = 24;
const reqs = [
    { id: "leftPanel", open: true, order: 1, padding: 14, record: { edge: "left", along: 70, span: 780, targetDepth: 394, depth: 394 } },
    { id: "styledPopup0", open: true, order: 2, padding: 14, record: { edge: "bottom", along: 456, span: 368, targetDepth: 344, depth: 344 } }
];
const meta = [
    { id: "leftPanel", role: "featureSidebar" },
    { id: "styledPopup0", role: "quickNotes" }
];
const base = {
    leftPanel: { visible: true, along: 70, inward: 20, span: 780, depth: 394, content: { x: 50, y: 84, width: 366, height: 752 } },
    styledPopup0: { visible: true, along: 456, inward: 0, span: 368, depth: 344, content: { x: 470, y: 642, width: 340, height: 316 } }
};
const unblocked = V.resolve(reqs, meta, base, W, H, IN, G, []);
assert.equal(unblocked.styledPopup0.vacancyDirection, "left");
assert(unblocked.styledPopup0.content.x < 450, "expands left without Companion obstacle");

// Place Companion TalkCloud at x=[420..445], y=[680..760] -> caps leftward growth at 445 + 24 = 469
const companionCloud = [{ x: 420, y: 680, width: 25, height: 80 }];
const blocked = V.resolve(reqs, meta, base, W, H, IN, G, companionCloud);
if (blocked.styledPopup0.vacancyBorrowed) {
    assert(blocked.styledPopup0.content.x >= 445 + G - 0.01, "must stop at Companion obstacle + gap");
}
console.log("SLICE4_JS_PASS");
"""
    )
    res = subprocess.run(["node", "-e", js_prog], cwd=ROOT, capture_output=True, text=True)
    assert res.returncode == 0 and "SLICE4_JS_PASS" in res.stdout, res.stderr + res.stdout


def test_quickshell_runtime() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-slice4-runtime-") as name:
        folder = Path(name)
        for entry in [
            "modules", "services", "GlobalStates.qml", "qmldir",
            "assets", "scripts", "defaults", "translations",
        ]:
            (folder / entry).symlink_to(ROOT / entry)
        cfg_dir = folder / "config/alis"
        cfg_dir.mkdir(parents=True)
        data = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
        data["abyss"]["companion"]["enabled"] = False
        (cfg_dir / "config.json").write_text(json.dumps(data), encoding="utf-8")

        (folder / "shell.qml").write_text(
            r"""
import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
import "modules/abyss/looks/AbyssLayout.js" as ModuleLayout
ShellRoot {
    id: root
    property int stage: 0
    property int checks: 0
    property string savedSidebarPlacement: ""
    property string savedNotesPlacement: ""
    Component.onCompleted: Quickshell.watchFiles = false
    function check(cond, msg) {
        checks++
        if (!cond) throw new Error(msg)
    }

    AbyssSurfaceController {
        id: liquid
        outputWidth: 1920
        outputHeight: 1080
        edgeInsets: ({left: 16, right: 16, top: 16, bottom: 16})
        moduleRecords: bar.deformations
    }
    FocusScope { id: canvas; width: 1920; height: 1080; focus: true }
    Item {
        id: bar
        parent: canvas
        anchors.fill: parent
        property var leftSidebarRecord: sidebar.progress > 0.001 ? sidebar.record : null
        readonly property var baseRenderedRecords: [
            { id: "cava", kind: "cava", edge: "left", vertical: true, along: 480, span: 120, content: { x: 8, y: 480, width: 32, height: 120 } }
        ]
        readonly property var renderedRecords: baseRenderedRecords.map(r => {
            const sb = bar.leftSidebarRecord
            const p = sb && sb.surface ? Math.max(0, (sb.surface.x + sb.surface.width) - 16) : 0
            return p > 0 ? Object.assign({}, r, { protrudeOffset: p }) : r
        })
        readonly property var clearanceDeformations: ModuleLayout.localSurfaces(baseRenderedRecords, 1920, 1080, { edgeThickness: 16 }, 1, 36)
        readonly property var deformations: ModuleLayout.localSurfaces(renderedRecords, 1920, 1080, { edgeThickness: 16 }, 1, 36)
        HoverHandler { id: barHover; blocking: false }
    }
    Item { id: sideContent; parent: sidebar.contentParent; implicitWidth: 412; implicitHeight: 692 }
    Item {
        id: noteContent
        parent: notes.contentParent
        implicitWidth: 352
        implicitHeight: 312
        TextInput { id: noteInput; anchors.fill: parent }
    }

    function presentedBodyHostForItem(item) {
        for (let cur = item; cur; cur = cur.parent) {
            if ((cur === sidebar || cur === notes) && cur.presented)
                return cur;
        }
        return null;
    }
    function isFocusInsidePresentedBody(item) {
        return presentedBodyHostForItem(item) !== null;
    }
    function ensureEscapeFocus(activeItem) {
        if (isFocusInsidePresentedBody(activeItem))
            return false; // preserved!
        if (sidebar.presented) {
            sidebar.forceActiveFocus();
            return true;
        }
        return false;
    }

    AbyssBodyHost {
        id: sidebar
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "leftPanel"; edge: "left"
        along: 110; span: 720; depth: 440; padding: 14
        edgeInsets: ModuleLayout.clearanceInsets(liquid.edgeInsets, bar.clearanceDeformations, edge, along, span, "cava")
        placementPriority: 2
        vacancyRole: "featureSidebar"
        embeddedItem: sideContent
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }
    AbyssBodyHost {
        id: notes
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "styledPopup0"; edge: "bottom"
        along: 110; span: 380; depth: 340; padding: 14
        edgeInsets: ModuleLayout.clearanceInsets(liquid.edgeInsets, bar.clearanceDeformations, edge, along, span, "notesTimers")
        placementPriority: 1
        vacancyRole: "quickNotes"; embeddedItem: noteContent
        stackPolicy: "pyramid"; externalProgress: 1
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }

    // Mirror SidebarReveal geometry formula from AbyssPerimeter.qml
    AbyssSidebarReveal {
        id: leftReveal
        parent: canvas
        bodyItem: sidebar
        property bool peerOpen: false
        readonly property bool horizontal: Geometry.horizontal(sidebar.edge)
        readonly property real triggerThickness: 16
        readonly property var restingContent: sidebar.targetRecord.content
        readonly property real axisExtent: horizontal ? 1920 : 1080
        readonly property real closedSpan: Math.round(Math.min(220, Math.max(140, axisExtent * (180 / 1080))))
        readonly property real openStart: horizontal ? Math.max(0, restingContent.x) : Math.max(0, restingContent.y)
        readonly property real openSpan: Math.max(closedSpan, horizontal ? restingContent.width : restingContent.height)
        readonly property bool expandedEdgeSpan: sidebar.open
        readonly property real triggerSpan: expandedEdgeSpan ? openSpan : closedSpan
        readonly property real triggerCenter: axisExtent / 2
        x: 0
        y: expandedEdgeSpan
            ? Math.max(0, Math.min(1080 - height, openStart))
            : Math.max(0, Math.min(1080 - height, triggerCenter - height / 2))
        width: triggerThickness
        height: triggerSpan
        open: sidebar.open
    }

    Timer {
        interval: 150; running: true; repeat: true
        onTriggered: {
            if (!Config.ready) return
            try {
                GlobalStates.deferredPanelsReady = true
                if (stage === 0) {
                    // (I) Closed trigger is strictly 180px centered at y=450..630 on 1080p
                    check(leftReveal.height === 180, "closed trigger height === 180, got " + leftReveal.height)
                    check(leftReveal.y === 450, "closed trigger y === 450, got " + leftReveal.y)
                    leftReveal.peerOpen = true // Quick Notes Edgebar opens!
                    check(leftReveal.height === 180 && leftReveal.y === 450, "peerOpen must NOT shift or expand closed SidebarReveal")
                    notes.open = true
                }
                if (stage === 1) {
                    noteInput.forceActiveFocus()
                    check(noteInput.focus === true, "Quick Notes TextInput receives focus chain")
                    check(presentedBodyHostForItem(noteInput) === notes, "noteInput resolves inside presented Quick Notes host")
                    sidebar.open = true
                }
                if (stage === 2) {
                    // (H) Quick Notes focus remains intact even after Left Sidebar opens & ensureEscapeFocus runs
                    check(ensureEscapeFocus(noteInput) === false, "ensureEscapeFocus must NOT steal focus from Quick Notes")
                    check(noteInput.focus === true && !sidebar.focus, "Quick Notes focus preserved when Left Sidebar opens")
                    // (I) While open, SidebarReveal spans restingContent
                    check(leftReveal.height > 180, "open SidebarReveal spans open sidebar")
                    // (F) Sidebar (placementPriority 2) stays anchored flush at its fixed spot while Quick Notes
                    // (placementPriority 1) clears it cleanly without swapping positions on focus/hover changes
                    root.savedSidebarPlacement = JSON.stringify({
                        along: sidebar.placement.along,
                        span: sidebar.placement.span,
                        depth: sidebar.placement.depth,
                        inward: sidebar.placement.inward
                    })
                    root.savedNotesPlacement = JSON.stringify({
                        along: notes.placement.along,
                        span: notes.placement.span,
                        depth: notes.placement.depth,
                        inward: notes.placement.inward
                    })
                    check(sidebar.placement.along === 110 && sidebar.placement.span === 720
                        && sidebar.placement.depth === 440 && sidebar.placement.inward === 0,
                        "Higher-priority Left Sidebar stays at its exact anchored geometry")
                    const sc = sidebar.record.content
                    const nc = notes.record.content
                    const overlaps = sc.x < nc.x + nc.width && sc.x + sc.width > nc.x
                        && sc.y < nc.y + nc.height && sc.y + sc.height > nc.y
                    check(!overlaps, "Quick Notes clears Left Sidebar cleanly without overlapping")
                    sidebar.forceActiveFocus()
                }
                if (stage === 3) {
                    check(JSON.stringify({
                        along: sidebar.placement.along,
                        span: sidebar.placement.span,
                        depth: sidebar.placement.depth,
                        inward: sidebar.placement.inward
                    }) === root.savedSidebarPlacement, "Sidebar position must remain fixed when focus moves to Sidebar")
                    check(JSON.stringify({
                        along: notes.placement.along,
                        span: notes.placement.span,
                        depth: notes.placement.depth,
                        inward: notes.placement.inward
                    }) === root.savedNotesPlacement, "Quick Notes position must remain fixed when focus moves to Sidebar")
                    noteInput.forceActiveFocus()
                }
                if (stage === 4) {
                    check(JSON.stringify({
                        along: sidebar.placement.along,
                        span: sidebar.placement.span,
                        depth: sidebar.placement.depth,
                        inward: sidebar.placement.inward
                    }) === root.savedSidebarPlacement, "Sidebar position must remain fixed when focus returns to Quick Notes")
                    check(JSON.stringify({
                        along: notes.placement.along,
                        span: notes.placement.span,
                        depth: notes.placement.depth,
                        inward: notes.placement.inward
                    }) === root.savedNotesPlacement, "Quick Notes position must remain fixed when focus returns to Quick Notes")
                    sidebar.open = false
                }
                if (stage === 5) {
                    check(leftReveal.height === 180 && leftReveal.y === 450, "Closing Sidebar restores 180px physical center trigger")
                    console.info("SLICE4_RUNTIME_PASS", checks)
                    Qt.quit()
                }
                stage++
            } catch (e) {
                console.error("SLICE4_RUNTIME_FAIL", e.message, e.stack)
                Qt.quit()
            }
        }
    }
}
""",
            encoding="utf-8",
        )

        env = dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            XDG_CONFIG_HOME=str(folder / "config"),
            XDG_STATE_HOME=str(folder / "state"),
            XDG_CACHE_HOME=str(folder / "cache"),
        )
        for key in ["QS_CONFIG_NAME", "QS_CONFIG_PATH"]:
            env.pop(key, None)
        result = run_qs(folder, env, timeout=15)
        assert result.returncode == 0 and "SLICE4_RUNTIME_PASS" in result.stdout, result.stdout + result.stderr
        assert not any(
            tok in result.stdout
            for tok in ["SLICE4_RUNTIME_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Unable to assign"]
        ), result.stdout


if __name__ == "__main__":
    test_source_and_js_contracts()
    test_quickshell_runtime()
    print("PASS: Slice 4 (180px center trigger, QuickNotes focus, Cava protrusion, newest-wins space yielding)")
