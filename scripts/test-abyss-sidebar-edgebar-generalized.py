#!/usr/bin/env python3
"""Silent regression test for generalized Sidebar + Edgebar coexistence across all corners and edges.

Covers:
1. Quick Notes at TR/BR paired with Right Sidebar (both open orders + flat SDF contour).
2. Notifications at TL/BL paired with Left Sidebar (both open orders).
3. Opposite-edge isolation (Left Sidebar + TR Quick Notes never pair or stretch across desktop).
4. Simultaneous 4-surface swapped layout (Left Sidebar + BL Notifications & Right Sidebar + TR Quick Notes).
5. Both Edgebars on the same side as one Sidebar (TR Quick Notes + BR Notifications + Right Sidebar).
6. Swapped Sidebars (featureSidebar on right, systemSidebar on left) follow physical edges.
7. Module Icon mode on perpendicular edges (top-right + Right Sidebar: lateral shift / no eviction)
   and centered on vertical edge (two-sided fillOuterStrip matching both top and bottom of Sidebar).
8. Narrow screen (1366px) expanded Sidebar + adjacent bottom Edgebar pairing.
9. Same-corner trigger separation in AbyssCorners across all 4 corners (TL, TR, BL, BR).
10. Headless Quickshell runtime test verifying real AbyssBodyHost + AbyssSurfaceController +
    effectiveJoinedEdge + AbyssSidebarReveal coexistence with zero QML errors/binding loops.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_source_contracts() -> None:
    perimeter = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    corners = (ROOT / "modules/abyss/AbyssCorners.qml").read_text(encoding="utf-8")
    host = (ROOT / "modules/abyss/AbyssBodyHost.qml").read_text(encoding="utf-8")
    vacancy = (ROOT / "modules/abyss/looks/AbyssVacancyBorrowing.js").read_text(encoding="utf-8")

    for tok in (
        "function edgebarLocation(role): var",
        "function edgebarLocationPairsWithEdge(loc, sidebarEdge, sidebarDepth = 460): bool",
        "readonly property bool quickNotesPairsLeft:",
        "readonly property bool quickNotesPairsRight:",
        "readonly property bool notificationCenterPairsLeft:",
        "readonly property bool notificationCenterPairsRight:",
        "readonly property bool pairsWithLeftSidebar:",
        "readonly property bool pairsWithRightSidebar:",
        "readonly property bool sameEdgeAsPairedSidebar:",
        "placementCanShiftLaterally: !isEdgebarRole || !sameEdgeAsPairedSidebar",
        "placementCanShiftPerpendicular: true",
    ):
        assert tok in perimeter, f"AbyssPerimeter missing generalized pairing token: {tok}"

    assert 'vacancyRole === "quickNotes" && window.leftSidebarDirectInteracting' not in perimeter, (
        "AbyssPerimeter must not hardcode quickNotes -> leftSidebar hover pairing"
    )
    assert 'vacancyRole === "notificationCenter" && window.rightSidebarDirectInteracting' not in perimeter, (
        "AbyssPerimeter must not hardcode notificationCenter -> rightSidebar hover pairing"
    )
    assert 'String(base.corner ?? "").endsWith("Right")' in corners, (
        "AbyssCorners sameCornerOverlap must offset horizontally by left/right side, not vertical tangentEdge"
    )
    assert "readonly property var effectiveJoinedEdges:" in host and "if (gap <= root.padding + 12)" in host, (
        "AbyssBodyHost effectiveJoinedEdges must only weld vacancy-borrowed edges that reach the screen edge"
    )
    assert "function _sidebarEdgebarPaired(" in vacancy, (
        "AbyssVacancyBorrowing must dynamically pair any Sidebar with any colocated Edgebar"
    )
    print("GENERALIZED_SOURCE_CONTRACT_PASS")


def test_js_matrix() -> None:
    parts = ["const g={}, b={}, v={}, l={};"]
    for name, filename, exports in (
        ("g", "AbyssGeometry.js", "panel,placedPanel,joinCorner,trimCoplanarOverlap"),
        ("b", "AbyssBodyPlacement.js", "arrange"),
        ("v", "AbyssVacancyBorrowing.js", "resolve"),
        ("l", "AbyssLayout.js", "edgebarAnchorPlacement"),
    ):
        src = (ROOT / "modules/abyss/looks" / filename).read_text(encoding="utf-8")
        parts.append(f"Object.assign({name},(function(){{{src}\nreturn {{{exports}}};}})());")

    parts.append(r"""
const assert = require("node:assert/strict");
const W = 1920, H = 1080, IN = { left: 10, right: 10, top: 56, bottom: 10 }, G = 24;

function mkReq(id, role, edge, along, span, depth, order, opts = {}) {
    const padding = opts.padding ?? 14;
    const minSpan = opts.minSpan ?? Math.min(span, 240);
    const minDepth = opts.minDepth ?? Math.min(depth, 180);
    const allowLateralShift = opts.allowLateralShift !== undefined ? opts.allowLateralShift : false;
    const allowPerpendicularShift = opts.allowPerpendicularShift === true;
    const maxLateralShift = opts.maxLateralShift ?? (allowLateralShift ? 520 : 0);
    const rec = g.panel(W, H, IN, edge, along, span, depth, 1, padding, [], false);
    return {
        req: {
            id, open: true, order, priority: opts.priority ?? 2, padding,
            minSpan, minDepth, allowLateralShift, allowPerpendicularShift, maxLateralShift,
            allowInward: true, record: rec
        },
        meta: { id, role }
    };
}

function solve(items, width = W, height = H, insets = IN) {
    const reqs = items.map(x => x.req);
    const meta = items.map(x => x.meta);
    const base = b.arrange(reqs, width, height, insets, G);
    const out = v.resolve(reqs, meta, base, width, height, insets, G);
    return { base, out };
}

function noOverlap(a, c) {
    return !(a.x < c.x + c.width + G - 0.05 && a.x + a.width + G - 0.05 > c.x
        && a.y < c.y + c.height + G - 0.05 && a.y + a.height + G - 0.05 > c.y);
}

// 1. TR Quick Notes + Right Sidebar (Sidebar first -> Quick Notes expands DOWNWARD to match Sidebar bottom)
{
    const rightSb = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 1, { padding: 20, minSpan: 420, minDepth: 360 });
    const trNotes = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, 2, { padding: 14 });
    const { out } = solve([rightSb, trNotes]);
    assert.equal(out.styledPopup0.visible, true);
    assert.equal(out.rightPanel.visible, true);
    assert.equal(out.styledPopup0.inward, 0, "newer TR Quick Notes stays outer");
    assert(out.rightPanel.inward > 0, "older Right Sidebar stacks inward");
    assert.equal(out.styledPopup0.vacancyBorrowed, true, "TR Quick Notes must borrow downward");
    assert.equal(out.styledPopup0.vacancyDirection, "bottom");
    assert.equal(out.styledPopup0.along + out.styledPopup0.span, 190 + 700, "TR Quick Notes bottom matches Right Sidebar bottom (890)");
    assert(noOverlap(out.rightPanel.content, out.styledPopup0.content), "no overlap between Right Sidebar and TR Quick Notes");

    // Check trimCoplanarOverlap produces flat bottom contour at y=890
    const pSb = g.placedPanel(W, H, IN, "right", 190, 700, 460, 1, 20, [], false, out.rightPanel);
    const pQn = g.joinCorner(g.placedPanel(W, H, IN, "right", 70, 300, 420, 1, 14, [], false, out.styledPopup0), "top", W, H, IN);
    assert.equal(pSb.surface.y + pSb.surface.height, 890);
    assert.equal(pQn.surface.y + pQn.surface.height, 890);
    const trimmed = g.trimCoplanarOverlap([pSb, pQn], 30);
    assert(trimmed[1].surface.y + trimmed[1].surface.height <= 860, "expanded TR Quick Notes bottom seam recedes past softness");
}

// 2. TR Quick Notes + Right Sidebar (Quick Notes first -> Right Sidebar expands UPWARD toward top)
{
    const trNotes = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, 1, { padding: 14 });
    const rightSb = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 2, { padding: 20, minSpan: 420, minDepth: 360 });
    const { out } = solve([trNotes, rightSb]);
    assert.equal(out.rightPanel.inward, 0, "newer Right Sidebar stays outer");
    assert(out.styledPopup0.inward > 0, "older TR Quick Notes stacks inward");
    assert.equal(out.rightPanel.vacancyBorrowed, true, "Right Sidebar must borrow upward toward TR Quick Notes");
    assert.equal(out.rightPanel.vacancyDirection, "top");
    assert.equal(out.rightPanel.along, IN.top + 20, "Right Sidebar reaches top safe bound");
    assert(noOverlap(out.rightPanel.content, out.styledPopup0.content));
}

// 3. TL Notifications + Left Sidebar (both orders)
{
    const leftSb = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20, minSpan: 320, minDepth: 320 });
    const tlCenter = mkReq("styledPopup0", "notificationCenter", "left", 70, 520, 420, 2, { padding: 14 });
    const { out } = solve([leftSb, tlCenter]);
    assert.equal(out.styledPopup0.vacancyBorrowed, true);
    assert.equal(out.styledPopup0.vacancyDirection, "bottom");
    assert.equal(out.styledPopup0.along + out.styledPopup0.span, 890);
    assert(noOverlap(out.leftPanel.content, out.styledPopup0.content));

    const tlFirst = mkReq("styledPopup0", "notificationCenter", "left", 70, 520, 420, 1, { padding: 14 });
    const leftSecond = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 2, { padding: 20, minSpan: 320, minDepth: 320 });
    const res2 = solve([tlFirst, leftSecond]);
    assert.equal(res2.out.leftPanel.vacancyBorrowed, true);
    assert.equal(res2.out.leftPanel.vacancyDirection, "top");
    assert(noOverlap(res2.out.leftPanel.content, res2.out.styledPopup0.content));
}

// 4. BL Notifications + Left Sidebar & BR Quick Notes + Right Sidebar
{
    const leftSb = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20, minSpan: 320, minDepth: 320 });
    const blCenter = mkReq("styledPopup0", "notificationCenter", "left", 496, 560, 420, 2, { padding: 14 });
    const r1 = solve([leftSb, blCenter]);
    assert.equal(r1.out.styledPopup0.vacancyBorrowed, true);
    assert.equal(r1.out.styledPopup0.vacancyDirection, "top");
    assert.equal(r1.out.styledPopup0.along, 190);

    const rightSb = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 1, { padding: 20, minSpan: 420, minDepth: 360 });
    const brNotes = mkReq("styledPopup1", "quickNotes", "right", 756, 300, 420, 2, { padding: 14 });
    const r2 = solve([rightSb, brNotes]);
    assert.equal(r2.out.styledPopup1.vacancyBorrowed, true);
    assert.equal(r2.out.styledPopup1.vacancyDirection, "top");
    assert.equal(r2.out.styledPopup1.along, 190);
}

// 5. Opposite-edge isolation: Left Sidebar + TR Quick Notes must NOT pair or stretch across screen
{
    const leftSb = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20 });
    const trNotes = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, 2, { padding: 14 });
    const { base, out } = solve([leftSb, trNotes]);
    assert.strictEqual(out, base, "opposite edges must not borrow vacancy across desktop");
}

// 6. All 4 open simultaneously in swapped corners: Left Sidebar + BL Notifications & Right Sidebar + TR Quick Notes
{
    const leftSb = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20, minSpan: 320, minDepth: 320 });
    const rightSb = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 2, { padding: 20, minSpan: 420, minDepth: 360 });
    const trNotes = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, 3, { padding: 14 });
    const blCenter = mkReq("styledPopup1", "notificationCenter", "left", 496, 560, 420, 4, { padding: 14 });
    const { out } = solve([leftSb, rightSb, trNotes, blCenter]);
    assert.equal(out.styledPopup0.vacancyBorrowed, true);
    assert.equal(out.styledPopup0.vacancyDirection, "bottom");
    assert.equal(out.styledPopup0.along + out.styledPopup0.span, 890);
    assert.equal(out.styledPopup1.vacancyBorrowed, true);
    assert.equal(out.styledPopup1.vacancyDirection, "top");
    assert.equal(out.styledPopup1.along, 190);
    const rects = [out.leftPanel.content, out.rightPanel.content, out.styledPopup0.content, out.styledPopup1.content];
    for (let i = 0; i < rects.length; i++)
        for (let j = i + 1; j < rects.length; j++)
            assert(noOverlap(rects[i], rects[j]), `overlap between ${i} and ${j}`);
}

// 7. Both Edgebars on the SAME side as Right Sidebar (TR Quick Notes + BR Notifications + Right Sidebar)
{
    const rightSb = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 1, { padding: 20, minSpan: 420, minDepth: 360, allowPerpendicularShift: true });
    const trNotes = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, 2, { padding: 14 });
    const brCenter = mkReq("styledPopup1", "notificationCenter", "right", 560, 496, 420, 3, { padding: 14 });
    const { out } = solve([rightSb, trNotes, brCenter]);
    assert.equal(out.rightPanel.visible, true);
    assert.equal(out.styledPopup0.visible, true);
    assert.equal(out.styledPopup1.visible, true);
    // Newer BR Notifications fills gap up to TR Quick Notes + gap without overlapping
    assert.equal(out.styledPopup1.vacancyBorrowed, true);
    assert.equal(out.styledPopup1.vacancyDirection, "top");
    assert(noOverlap(out.styledPopup0.content, out.styledPopup1.content), "TR and BR edgebars must not collide");
    assert(noOverlap(out.rightPanel.content, out.styledPopup0.content));
    assert(noOverlap(out.rightPanel.content, out.styledPopup1.content));

    // When Right Sidebar opens NEWEST (outer) alongside BOTH TR Quick Notes and BR Notifications,
    // outer-strip borrowing merges BOTH ends cleanly ([76..1050]) with zero top/bottom cutout.
    for (const [oTr, oBr] of [[1, 2], [2, 1]]) {
        const trIn = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, oTr, { padding: 14 });
        const brIn = mkReq("styledPopup1", "notificationCenter", "right", 560, 496, 420, oBr, { padding: 14 });
        const sbOut = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 3, { padding: 20, minSpan: 420, minDepth: 360, allowPerpendicularShift: true });
        const rDual = solve([trIn, brIn, sbOut]);
        assert.equal(rDual.out.rightPanel.inward, 0);
        assert.equal(rDual.out.rightPanel.vacancyBorrowed, true);
        assert.equal(rDual.out.rightPanel.vacancyDirection, "both", "outer Right Sidebar must merge both TR and BR outer-strip borrows");
        assert.equal(rDual.out.rightPanel.along, IN.top + 20, "top reaches safe top bound");
        assert.equal(rDual.out.rightPanel.along + rDual.out.rightPanel.span, H - IN.bottom - 20, "bottom reaches safe bottom bound");
        assert(noOverlap(rDual.out.rightPanel.content, rDual.out.styledPopup0.content));
        assert(noOverlap(rDual.out.rightPanel.content, rDual.out.styledPopup1.content));
    }
}

// 8. Swapped Sidebars (featureSidebar on right, systemSidebar on left) + TR Quick Notes + BL Notifications
{
    const swappedFeature = mkReq("leftPanel", "featureSidebar", "right", 190, 700, 460, 1, { padding: 20, minSpan: 320, minDepth: 320, allowPerpendicularShift: true });
    const trNotes = mkReq("styledPopup0", "quickNotes", "right", 70, 300, 420, 2, { padding: 14 });
    const r = solve([swappedFeature, trNotes]);
    assert.equal(r.out.styledPopup0.vacancyBorrowed, true);
    assert.equal(r.out.styledPopup0.vacancyDirection, "bottom");
    assert.equal(r.out.styledPopup0.along + r.out.styledPopup0.span, 890);
}

// 9. Module Icon mode on top-right / top-left + Sidebar (both orders: zero cross-edge inward dead slab!)
{
    const topRightNotes = mkReq("styledPopup0", "quickNotes", "top", 1480, 420, 300, 1, { padding: 14, allowLateralShift: true, maxLateralShift: 524 });
    const rightSb = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 2, { padding: 20, minSpan: 420, minDepth: 360, allowPerpendicularShift: true });
    const r1 = solve([topRightNotes, rightSb]);
    assert.equal(r1.out.styledPopup0.visible, true, "top-right module icon must not be evicted by Right Sidebar");
    assert.equal(r1.out.styledPopup0.inward, 0, "top-right module icon shifts left along top edge");
    assert(r1.out.styledPopup0.lateralShift < -100, "shifted left beside Right Sidebar");
    assert(noOverlap(r1.out.rightPanel.content, r1.out.styledPopup0.content));

    const rightSbFirst = mkReq("rightPanel", "systemSidebar", "right", 190, 700, 460, 1, { padding: 20, minSpan: 420, minDepth: 360, allowPerpendicularShift: true });
    const topRightSecond = mkReq("styledPopup0", "quickNotes", "top", 1480, 420, 300, 2, { padding: 14, allowLateralShift: true, maxLateralShift: 524 });
    const r2 = solve([rightSbFirst, topRightSecond]);
    assert.equal(r2.out.styledPopup0.visible, true);
    assert.equal(r2.out.rightPanel.visible, true);
    assert.equal(r2.out.rightPanel.inward, 0, "Right Sidebar must stay at inward=0 below TopRight ModIcon instead of jumping 424px inward");
    assert.equal(r2.out.rightPanel.span, 700, "Right Sidebar retains full 700px height below TopRight ModIcon");
    assert(noOverlap(r2.out.rightPanel.content, r2.out.styledPopup0.content));

    // Tall top-right & top-left Notifications Module Icon (h=560) + Sidebar -> Sidebar fits cleanly at inward=0 below it
    const topRightNotif = mkReq("styledPopup0", "notificationCenter", "top", 1480, 420, 560, 2, { padding: 14, allowLateralShift: true, maxLateralShift: 524 });
    const r3 = solve([rightSbFirst, topRightNotif]);
    assert.equal(r3.out.rightPanel.visible, true);
    assert.equal(r3.out.rightPanel.inward, 0, "Right Sidebar stays at inward=0 below tall TopRight Notifications ModIcon");
    assert(r3.out.rightPanel.span >= 420);
    assert(noOverlap(r3.out.rightPanel.content, r3.out.styledPopup0.content));
    const placedR3 = g.placedPanel(W, H, IN, "right", 190, 700, 460, 1, 20, [], false, r3.out.rightPanel);
    for (const k of ["x", "y", "width", "height"])
        assert(Math.abs(placedR3.content[k] - r3.out.rightPanel.content[k]) < 1e-6, `shifted Sidebar placedPanel.${k} mismatch`);

    const leftSbFirst = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20, minSpan: 320, minDepth: 320, allowPerpendicularShift: true });
    const topLeftNotif = mkReq("styledPopup0", "notificationCenter", "top", 20, 420, 560, 2, { padding: 14, allowLateralShift: true, maxLateralShift: 524 });
    const r4 = solve([leftSbFirst, topLeftNotif]);
    assert.equal(r4.out.leftPanel.visible, true);
    assert.equal(r4.out.leftPanel.inward, 0, "Left Sidebar stays at inward=0 below tall TopLeft Notifications ModIcon");
    assert(noOverlap(r4.out.leftPanel.content, r4.out.styledPopup0.content));
}

// 10. Module Icon centered vertically on left edge + Left Sidebar -> two-sided fillOuterStrip ("both")
{
    const leftSb = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20, minSpan: 320, minDepth: 320 });
    const midLeftNotes = mkReq("styledPopup0", "quickNotes", "left", 390, 300, 420, 2, { padding: 14 });
    const { out } = solve([leftSb, midLeftNotes]);
    assert.equal(out.styledPopup0.vacancyBorrowed, true);
    assert.equal(out.styledPopup0.vacancyDirection, "both");
    assert.equal(out.styledPopup0.along, 190, "top aligns with Left Sidebar top");
    assert.equal(out.styledPopup0.along + out.styledPopup0.span, 890, "bottom aligns with Left Sidebar bottom");
    assert(noOverlap(out.leftPanel.content, out.styledPopup0.content));
}

// 11. Module Icon dead-center on top edge (x=750..1170) + Left Sidebar -> no unwanted cross-desktop stretch
{
    const leftSb = mkReq("leftPanel", "featureSidebar", "left", 190, 700, 460, 1, { padding: 20 });
    const topCenterNotes = mkReq("styledPopup0", "quickNotes", "top", 750, 420, 300, 2, { padding: 14, allowLateralShift: true });
    const { base, out } = solve([leftSb, topCenterNotes]);
    assert.strictEqual(out, base, "far center top popup must not stretch across empty desktop");
}

// 12. Narrow 1366px laptop screen with expanded 650px Left Sidebar + adjacent bottom Edgebar
{
    const nW = 1366, nH = 768, nIN = { left: 10, right: 10, top: 44, bottom: 10 };
    const sbRec = g.panel(nW, nH, nIN, "left", 60, 620, 650, 1, 14, [], true);
    const ebRec = g.panel(nW, nH, nIN, "bottom", 700, 380, 300, 1, 14, [], false);
    const reqs = [
        { id: "leftPanel", open: true, order: 1, priority: 2, padding: 14, minSpan: 320, minDepth: 320, allowInward: true, record: sbRec },
        { id: "styledPopup0", open: true, order: 2, priority: 2, padding: 14, minSpan: 240, minDepth: 180, allowInward: true, record: ebRec }
    ];
    const meta = [{ id: "leftPanel", role: "featureSidebar" }, { id: "styledPopup0", role: "quickNotes" }];
    const base = b.arrange(reqs, nW, nH, nIN, G);
    const out = v.resolve(reqs, meta, base, nW, nH, nIN, G);
    assert.equal(out.styledPopup0.vacancyBorrowed, true, "adjacent bottom edgebar on narrow laptop still pairs with expanded Left Sidebar");
    assert.equal(out.styledPopup0.vacancyDirection, "left");
}

// 13. AbyssCorners same-corner separation across ALL 4 corners (TL, TR, BL, BR)
{
    const cases = [
        { corner: "topLeft", edge: "top", pos: 0.05 },
        { corner: "topRight", edge: "top", pos: 0.95 },
        { corner: "bottomLeft", edge: "bottom", pos: 0.05 },
        { corner: "bottomRight", edge: "bottom", pos: 0.95 }
    ];
    for (const c of cases) {
        const opts = {
            outputLayouts: [{
                outputName: "DP-1",
                placements: [
                    { id: "notesTimers", kind: "notesTimers", edge: c.edge, position: c.pos, enabled: true },
                    { id: "notificationActivity", kind: "notificationActivity", edge: c.edge, position: c.pos, enabled: true }
                ]
            }]
        };
        const nP = l.edgebarAnchorPlacement(opts, "DP-1", "notesTimers", 1920, 1080, 14);
        const cP = l.edgebarAnchorPlacement(opts, "DP-1", "notificationActivity", 1920, 1080, 14);
        assert.equal(nP.corner, c.corner);
        assert.equal(cP.corner, c.corner);
        const step = Math.round(nP.width + 4);
        const onRight = cP.edge === "right" || cP.corner.endsWith("Right");
        const effX = onRight ? Math.max(0, Math.round(cP.x) - step) : Math.min(1920 - Math.round(cP.width), Math.round(cP.x) + step);
        const overlaps = effX < nP.x + nP.width && effX + cP.width > nP.x;
        assert(!overlaps, `same-corner overlap at ${c.corner}: notes.x=${nP.x} center.effX=${effX}`);
    }
}

console.log("GENERALIZED_JS_MATRIX_PASS");
""")
    res = subprocess.run(["node"], input="\n".join(parts), cwd=ROOT, capture_output=True, text=True)
    if res.returncode != 0 or "GENERALIZED_JS_MATRIX_PASS" not in res.stdout:
        print(res.stdout)
        print(res.stderr)
        sys.exit(1)
    print("GENERALIZED_JS_MATRIX_PASS")


QML_HARNESS = r'''//@ pragma ShellId alis-sidebar-edgebar-generalized-test
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss

ShellRoot {
    id: root
    property int checks: 0
    Component.onCompleted: Quickshell.watchFiles = false

    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    AbyssSurfaceController {
        id: liquid
        outputName: "TEST-1"
        outputWidth: 1920
        outputHeight: 1080
        edgeInsets: ({ left: 10, right: 10, top: 56, bottom: 10 })
        fifoCloseStepMs: 60
        fifoWaitCapMs: 850
    }

    Item { id: canvas; width: 1920; height: 1080 }
    Item { id: rightSideContent; implicitWidth: 420; implicitHeight: 660 }
    Item { id: trNotesContent; implicitWidth: 392; implicitHeight: 272 }
    Item { id: brCenterContent; implicitWidth: 392; implicitHeight: 468 }
    Item { id: midLeftContent; implicitWidth: 392; implicitHeight: 272 }
    Item { id: leftSideContent; implicitWidth: 420; implicitHeight: 660 }

    AbyssBodyHost {
        id: rightPanel
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "rightPanel"; edge: "right"
        along: 190; span: 700; depth: 460; padding: 20
        edgeInsets: liquid.edgeInsets
        placementPriority: 2
        vacancyRole: "systemSidebar"
        placementCanShiftLaterally: false
        placementCanShiftPerpendicular: true
        embeddedItem: rightSideContent
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }

    AbyssBodyHost {
        id: trNotes
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "styledPopup0"; edge: "right"; joinedEdge: "top"
        along: 70; span: 300; depth: 420; padding: 14
        edgeInsets: liquid.edgeInsets
        placementPriority: rightPanel.placementPriority
        vacancyRole: "quickNotes"
        placementCanShiftLaterally: false
        stackPolicy: "pyramid"; externalProgress: 1
        embeddedItem: trNotesContent
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }

    AbyssBodyHost {
        id: brCenter
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "styledPopup2"; edge: "right"; joinedEdge: "bottom"
        along: 560; span: 496; depth: 420; padding: 14
        edgeInsets: liquid.edgeInsets
        placementPriority: rightPanel.placementPriority
        vacancyRole: "notificationCenter"
        placementCanShiftLaterally: false
        stackPolicy: "pyramid"; externalProgress: 1
        embeddedItem: brCenterContent
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }

    AbyssBodyHost {
        id: leftPanel
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "leftPanel"; edge: "left"
        along: 190; span: 700; depth: 460; padding: 20
        edgeInsets: liquid.edgeInsets
        placementPriority: 2
        vacancyRole: "featureSidebar"
        placementCanShiftLaterally: false
        embeddedItem: leftSideContent
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }

    AbyssBodyHost {
        id: midLeftNotes
        parent: canvas; anchors.fill: parent; controller: liquid
        identity: "styledPopup1"; edge: "left"; joinedEdge: ""
        along: 390; span: 300; depth: 420; padding: 14
        edgeInsets: liquid.edgeInsets
        placementPriority: leftPanel.placementPriority
        vacancyRole: "quickNotes"
        placementCanShiftLaterally: false
        stackPolicy: "pyramid"; externalProgress: 1
        embeddedItem: midLeftContent
        animatePresentation: false; animatePlacementChanges: false
        stableContentSize: true; open: false
    }

    property var closeSeq: []

    AbyssSidebarReveal {
        id: rightReveal
        controller: liquid
        surfaceId: "rightPanel"
        available: true
        open: rightPanel.open
        closeDelay: 80
        onHideRequested: {
            root.closeSeq.push("rightPanel")
            rightPanel.open = false
            liquid.clearHoverSurface("rightPanel")
        }
    }

    AbyssCorners {
        id: corners
        parent: canvas
        anchors.fill: parent
        controller: liquid
        outputName: "TEST-1"
        presentationEnabled: true
        blocked: false
    }

    AbyssPerimeter {
        id: perimeter
    }

    TestCase {
        id: tc
        when: false
        optional: true

        function run() {
            try {
                GlobalStates.deferredPanelsReady = true

                // Case 1: Right Sidebar first, TR Quick Notes second -> TR Quick Notes expands downward to match bottom (890)
                rightPanel.open = true
                wait(40)
                trNotes.open = true
                wait(40)
                root.check(trNotes.activationOrder > rightPanel.activationOrder, "TR Quick Notes must be newer")
                root.check(trNotes.placement.inward === 0, "TR Quick Notes stays outer")
                root.check(rightPanel.placement.inward > 0, "Right Sidebar stacks inward")
                root.check(trNotes.placement.vacancyBorrowed === true, "TR Quick Notes borrows downward")
                root.check(trNotes.placement.vacancyDirection === "bottom", "direction is bottom, got " + trNotes.placement.vacancyDirection)
                root.check(Math.abs((trNotes.placement.along + trNotes.placement.span) - 890) < 0.5,
                    "TR Quick Notes bottom must match Right Sidebar bottom (890), got " + (trNotes.placement.along + trNotes.placement.span))
                root.check(trNotes.appliedJoinedEdge === "top", "TR Quick Notes stays welded to top edge")
                root.check(trNotes.contentParent.height > 272, "TR Quick Notes content expanded vertically")

                // Close both
                trNotes.open = false
                rightPanel.open = false
                wait(40)

                // Case 2: TR Quick Notes first, Right Sidebar second -> Right Sidebar expands upward and welds to top edge
                trNotes.open = true
                wait(40)
                rightPanel.open = true
                wait(40)
                root.check(rightPanel.placement.inward === 0, "Right Sidebar stays outer")
                root.check(trNotes.placement.inward > 0, "TR Quick Notes stacks inward")
                root.check(rightPanel.placement.vacancyBorrowed === true, "Right Sidebar borrows upward")
                root.check(rightPanel.placement.vacancyDirection === "top", "direction is top")
                root.check(rightPanel.effectiveJoinedEdge === "top",
                    "Right Sidebar reaching top safe bound must weld to top edge, got '" + rightPanel.effectiveJoinedEdge + "'")
                root.check(rightPanel.record.surface.y === -50, "Right Sidebar welded surface.y === -50")

                trNotes.open = false
                rightPanel.open = false
                wait(40)

                // Case 2b: TR Quick Notes + BR Notifications first, Right Sidebar newest -> Right Sidebar merges BOTH ends and welds BOTH top & bottom edges!
                trNotes.open = true
                wait(20)
                brCenter.open = true
                wait(20)
                rightPanel.open = true
                wait(40)
                root.check(rightPanel.placement.inward === 0, "Right Sidebar stays outer against TR+BR")
                root.check(rightPanel.placement.vacancyBorrowed === true, "Right Sidebar borrows both ends")
                root.check(rightPanel.placement.vacancyDirection === "both", "Right Sidebar vacancyDirection === both, got " + rightPanel.placement.vacancyDirection)
                root.check(rightPanel.effectiveJoinedEdges.length === 2
                    && rightPanel.effectiveJoinedEdges.includes("top")
                    && rightPanel.effectiveJoinedEdges.includes("bottom"),
                    "Right Sidebar spanning TR+BR must weld BOTH top & bottom, got " + JSON.stringify(rightPanel.effectiveJoinedEdges))
                root.check(rightPanel.record.surface.y === -50 && (rightPanel.record.surface.y + rightPanel.record.surface.height) === 1130,
                    "Right Sidebar welded top=-50 & bottom=1130, got y=" + rightPanel.record.surface.y + " h=" + rightPanel.record.surface.height)

                trNotes.open = false
                brCenter.open = false
                rightPanel.open = false
                wait(40)

                // Case 3: Mid-left Module Icon + Left Sidebar -> expands both ends cleanly, NEVER falsely welds to top/bottom edge
                leftPanel.open = true
                wait(40)
                midLeftNotes.open = true
                wait(40)
                root.check(midLeftNotes.placement.vacancyBorrowed === true, "mid-left module icon borrows both ends")
                root.check(midLeftNotes.placement.vacancyDirection === "both", "direction is both, got " + midLeftNotes.placement.vacancyDirection)
                root.check(Math.abs(midLeftNotes.placement.along - 190) < 0.5, "mid-left top matches Left Sidebar (190)")
                root.check(Math.abs((midLeftNotes.placement.along + midLeftNotes.placement.span) - 890) < 0.5, "mid-left bottom matches Left Sidebar (890)")
                root.check(midLeftNotes.effectiveJoinedEdge === "", "mid-left module icon must NOT falsely weld to screen edge")
                root.check(Math.abs(midLeftNotes.record.surface.y - 190) < 0.5, "mid-left surface.y === 190")

                midLeftNotes.open = false
                leftPanel.open = false
                wait(40)

                // Case 4: Live AbyssCorners sameCornerOverlap at topRight separates notesAnchor & centerAnchor horizontally
                Config.options.panelFamily = "abyss"
                Config.options.abyss.modules.notesTimersMode = "edgebar"
                Config.options.abyss.modules.notificationActivityMode = "edgebar"
                Config.options.abyss.modules.outputLayouts = [{
                    outputName: "TEST-1",
                    placements: [
                        { id: "notesTimers", kind: "notesTimers", edge: "top", position: 0.95, enabled: true },
                        { id: "notificationActivity", kind: "notificationActivity", edge: "top", position: 0.95, enabled: true }
                    ]
                }]
                wait(40)
                root.check(corners.notesPlacement.corner === "topRight", "notesPlacement must snap to topRight, got " + corners.notesPlacement.corner)
                root.check(corners.sameCornerOverlap === true, "sameCornerOverlap must be true when both at topRight")
                root.check(corners.centerAnchor.x + corners.centerAnchor.width <= corners.notesAnchor.x,
                    "topRight same-corner centerAnchor must shift left of notesAnchor: center=" + corners.centerAnchor.x + " notes=" + corners.notesAnchor.x)

                // Case 5: Right Sidebar + TR Quick Notes FIFO hover coexistence via rightReveal.peerHovered
                liquid._fifoHoverSeq = 0
                liquid._fifoHoverState = ({})
                liquid._fifoLastClosedId = ""
                root.closeSeq = []
                rightPanel.open = true
                rightReveal.ownedOpen = true
                rightReveal.edgeHovered = true
                wait(25)
                root.check(liquid.hoverOrderFor("rightPanel") === 1, "rightPanel gets FIFO order 1")
                // Pointer moves from Right Sidebar to TR Quick Notes -> peerHovered keeps rightPanel alive
                rightReveal.edgeHovered = false
                rightReveal.peerHovered = true
                liquid.noteHoverSurfaceActive("styledPopup0", true)
                wait(110)
                root.check(rightPanel.open === true, "Right Sidebar must stay open while paired TR Quick Notes is hovered")
                root.check(liquid.hoverOrderFor("styledPopup0") === 2, "TR Quick Notes gets FIFO order 2")

                // Pointer leaves both -> Right Sidebar (order 1) must close BEFORE TR Quick Notes (order 2)
                rightReveal.peerHovered = false
                liquid.noteHoverSurfaceLeave("styledPopup0", true)
                liquid.requestHoverSurfaceClose("styledPopup0", () => {
                    root.closeSeq.push("styledPopup0")
                    liquid.clearHoverSurface("styledPopup0")
                })
                tryVerify(() => !rightPanel.open && root.closeSeq.length === 2, 1200)
                root.check(root.closeSeq[0] === "rightPanel" && root.closeSeq[1] === "styledPopup0",
                    "FIFO close violated for Right Sidebar + TR Quick Notes: got " + JSON.stringify(root.closeSeq))

                // Case 6: Live AbyssPerimeter reactive pairing wiring (TR QuickNotes + TL Notifications + Top-Center/Top-Left/Top-Right Module Icons)
                tryVerify(() => (perimeter.outputHosts ?? []).length > 0 && perimeter.outputHosts[0].width > 0, 2000)
                const host = perimeter.outputHosts[0]
                const outName = String(host.outputName)
                Config.options.panelFamily = "abyss"
                Config.options.abyss.modules.notesTimersMode = "edgebar"
                Config.options.abyss.modules.notificationActivityMode = "edgebar"
                Config.options.abyss.modules.outputLayouts = [{
                    outputName: outName,
                    placements: [
                        { id: "notesTimers", kind: "notesTimers", edge: "top", position: 0.95, enabled: true },
                        { id: "notificationActivity", kind: "notificationActivity", edge: "top", position: 0.05, enabled: true }
                    ]
                }]
                wait(60)
                root.check(host.quickNotesPairsRight === true && host.quickNotesPairsLeft === false,
                    "Live AbyssPerimeter: TR Quick Notes must pair ONLY with Right Sidebar, got L=" + host.quickNotesPairsLeft + " R=" + host.quickNotesPairsRight)
                root.check(host.notificationCenterPairsLeft === true && host.notificationCenterPairsRight === false,
                    "Live AbyssPerimeter: TL Notifications must pair ONLY with Left Sidebar, got L=" + host.notificationCenterPairsLeft + " R=" + host.notificationCenterPairsRight)

                // Pixel-grounded perpendicular pairing check on live AbyssPerimeter (e.g. 1920px or virtual output width):
                const w = host.width
                root.check(host.edgebarLocationPairsWithEdge({ edge: "top", span: 420, cx: w * 0.5, cy: 0 }, "left", 460) === (w <= 1820),
                    "Live AbyssPerimeter: dead-center top popup must follow pixel proximity (w=" + w + ")")
                root.check(host.edgebarLocationPairsWithEdge({ edge: "top", span: 420, cx: w - 120, cy: 0 }, "right", 460) === true,
                    "Live AbyssPerimeter: top-right module pairs with Right Sidebar")
                root.check(host.edgebarLocationPairsWithEdge({ edge: "top", span: 420, cx: w - 120, cy: 0 }, "left", 460) === false,
                    "Live AbyssPerimeter: top-right module must NOT pair with Left Sidebar")
                root.check(host.edgebarLocationPairsWithEdge({ edge: "top", span: 420, cx: 120, cy: 0 }, "left", 460) === true,
                    "Live AbyssPerimeter: top-left module pairs with Left Sidebar")
                root.check(host.edgebarLocationPairsWithEdge({ edge: "top", span: 420, cx: 120, cy: 0 }, "right", 460) === false,
                    "Live AbyssPerimeter: top-left module must NOT pair with Right Sidebar")
                // Left-of-center popup on wide screen must NOT falsely pair with Right Sidebar
                if (w >= 1600) {
                    root.check(host.edgebarLocationPairsWithEdge({ edge: "top", span: 420, cx: w * 0.40, cy: 0 }, "right", 460) === false,
                        "Live AbyssPerimeter: 40% x-position must NOT falsely pair with Right Sidebar on w=" + w)
                }

                // Case 7: Switch notesTimers to Module Icon mode on top-right & verify reactive update on live AbyssPerimeter
                Config.options.abyss.modules.notesTimersMode = "module"
                wait(80)
                root.check(host.quickNotesLocation.edge === "top",
                    "Live AbyssPerimeter: top-right module icon location edge must switch to 'top', got '" + host.quickNotesLocation.edge + "'")
                root.check(host.quickNotesPairsRight === true && host.quickNotesPairsLeft === false,
                    "Live AbyssPerimeter: top-right module icon pairs ONLY with Right Sidebar, got L=" + host.quickNotesPairsLeft + " R=" + host.quickNotesPairsRight)

                // Move module icon to top-left -> pairs ONLY with Left Sidebar
                Config.options.abyss.modules.outputLayouts = [{
                    outputName: outName,
                    placements: [
                        { id: "notesTimers", kind: "notesTimers", edge: "top", position: 0.05, enabled: true },
                        { id: "notificationActivity", kind: "notificationActivity", edge: "bottom", position: 0.95, enabled: true }
                    ]
                }]
                wait(80)
                root.check(host.quickNotesPairsLeft === true && host.quickNotesPairsRight === false,
                    "Live AbyssPerimeter: top-left module icon pairs ONLY with Left Sidebar, got L=" + host.quickNotesPairsLeft + " R=" + host.quickNotesPairsRight)
                root.check(host.notificationCenterPairsRight === true && host.notificationCenterPairsLeft === false,
                    "Live AbyssPerimeter: BR Notifications edgebar pairs ONLY with Right Sidebar, got L=" + host.notificationCenterPairsLeft + " R=" + host.notificationCenterPairsRight)

                console.info("GENERALIZED_RUNTIME_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("GENERALIZED_RUNTIME_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: tc.run()
    }
}
'''


def test_runtime() -> None:
    qs = shutil.which("qs")
    if not qs:
        print("SKIP: qs unavailable")
        return

    with tempfile.TemporaryDirectory(prefix="alis-generalized-coexist-") as tmp:
        folder = Path(tmp)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
            (folder / entry).symlink_to(ROOT / entry)
        (folder / "shell.qml").write_text(QML_HARNESS, encoding="utf-8")

        env = os.environ.copy()
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env.pop("QT_QUICK_BACKEND", None)
        env.pop("QS_CONFIG_NAME", None)
        env.pop("QS_CONFIG_PATH", None)
        env["XDG_CONFIG_HOME"] = str(folder / "config")
        env["XDG_STATE_HOME"] = str(folder / "state")
        env["XDG_CACHE_HOME"] = str(folder / "cache")
        env["XDG_DATA_HOME"] = "/nonexistent"
        env["XDG_DATA_DIRS"] = "/nonexistent"
        cfg_dir = folder / "config/alis"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
        data["abyss"]["companion"]["enabled"] = False
        (cfg_dir / "config.json").write_text(json.dumps(data), encoding="utf-8")

        with private_wayland(folder) as wl_env:
            run_env = dict(wl_env)
            run_env.pop("QT_QUICK_BACKEND", None)
            res = run_qs(folder, run_env, timeout=25)
        out = (res.stdout or "") + "\n" + (res.stderr or "")
        if res.returncode != 0 or "GENERALIZED_RUNTIME_PASS" not in out or re.search(
            r"GENERALIZED_RUNTIME_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign", out
        ):
            print(out)
            sys.exit(1)
        for line in out.splitlines():
            if "GENERALIZED_RUNTIME_PASS" in line:
                print(line.strip())


if __name__ == "__main__":
    test_source_contracts()
    test_js_matrix()
    test_runtime()
