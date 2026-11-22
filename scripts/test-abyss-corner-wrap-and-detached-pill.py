#!/usr/bin/env python3
"""Unit + silent offscreen Quickshell runtime verification for Screen Edge
Module Corner Wrap (cornerWrap) and Detached Circle/Pill (detached) features.
"""
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# ─── Part 1: Exhaustive AbyssLayout.js Geometry, Policy & Legacy-Data Tests ───
JS_PROGRAM = (ROOT / "modules/abyss/looks/AbyssLayout.js").read_text(encoding="utf-8") + r"""
const assert = require('node:assert/strict');

// 1. Legacy persisted fixtures without cornerWrap/detached normalize cleanly with zero key drift or mutation
const legacyRaw = [
    { id: 'clock', kind: 'clock', edge: 'top', position: 0.5 },
    { id: 'distro', kind: 'distroIcon', edge: 'top', position: 0.08, joinCorner: true }
];
const legacySnapshot = JSON.stringify(legacyRaw);
const legacyNorm = normalize(legacyRaw, 'top');
assert.equal(JSON.stringify(legacyRaw), legacySnapshot, 'legacy input objects must not be mutated');
assert.equal(legacyNorm[0].cornerWrap, undefined, 'legacy placement stays free of cornerWrap key');
assert.equal(legacyNorm[0].detached, undefined, 'legacy placement stays free of detached key');
assert.equal(legacyNorm[1].joinCorner, true, 'legacy joinCorner preserved');
const legacyResolved = resolve({ configured: true, placements: legacyRaw }, 'DP-1', []);
assert.equal(legacyResolved[0].cornerWrap, undefined, 'resolved legacy placement stays free of cornerWrap');
assert.equal(legacyResolved[0].detached, undefined, 'resolved legacy placement stays free of detached');
assert.equal(legacyResolved[1].joinCorner, true, 'resolved legacy joinCorner preserved');

// 2. Corner Wrap across all 4 corners + 0px edge resilience: L-shaped arm geometry,
//    2-arm SDF localSurfaces, neighbor clearance on BOTH edges, and zero bloat on full edge paint strip
const cornerCases = [
    ['top', 0.05, 'topLeft', 'top', 'left', true, true],
    ['top', 0.95, 'topRight', 'top', 'right', false, true],
    ['bottom', 0.05, 'bottomLeft', 'bottom', 'left', true, false],
    ['bottom', 0.95, 'bottomRight', 'bottom', 'right', false, false],
    ['left', 0.10, 'topLeft', 'top', 'left', true, true],
    ['right', 0.90, 'bottomRight', 'bottom', 'right', false, false],
];
for (const [edge, pos, expectedCorner, hEdge, vEdge] of cornerCases) {
    for (const bareEdge of [0, 16]) {
        const placements = normalize([
            { id: 'cava1', kind: 'cava', edge, position: pos, cornerWrap: true },
            { id: 'hNeighbor', kind: 'clock', edge: hEdge, position: pos < 0.5 ? 0.02 : 0.98 },
            { id: 'vNeighbor', kind: 'battery', edge: vEdge, position: (expectedCorner.startsWith('top') ? 0.02 : 0.98) }
        ], 'top');
        const opts = { edgeThickness: bareEdge, gap: 8, cornerRadius: 34 };
        const recs = geometry(placements, 1920, 1080, opts, 1);
        const cw = recs.find(r => r.id === 'cava1');
        assert.ok(cw && cw.cornerWrap === true, `cornerWrap record present at bareEdge=${bareEdge}`);
        assert.equal(cw.wrapCorner, expectedCorner, 'resolved corner matches ' + expectedCorner);
        assert.ok(cw.wrapHorizontalRect && cw.wrapVerticalRect, 'both L-arms computed');
        assert.ok(cw.wrapArmH > cw.wrapThickness && cw.wrapArmV > cw.wrapThickness, 'arms extend past thickness');
        assert.ok(cw.wrapThickness >= 32, 'cornerWrap keeps full thickness even at 0px global edge');

        if (bareEdge > 0) {
            const hn = recs.find(r => r.id === 'hNeighbor');
            const vn = recs.find(r => r.id === 'vNeighbor');
            for (const arm of [cw.wrapHorizontalRect, cw.wrapVerticalRect]) {
                for (const nb of [hn, vn]) {
                    const c = nb.content;
                    const overlaps = !(c.x + c.width <= arm.x + 0.5 || arm.x + arm.width <= c.x + 0.5
                        || c.y + c.height <= arm.y + 0.5 || arm.y + arm.height <= c.y + 0.5);
                    assert.equal(overlaps, false, `neighbor ${nb.id} overlaps ${expectedCorner} arm`);
                }
            }
        }

        // Verify localSurfaces emits 2 fused SDF arms tagged with ownerId
        const ls = localSurfaces(recs, 1920, 1080, opts, 1, 48);
        const arms = ls.filter(s => s.cornerWrapArm === true);
        assert.equal(arms.length, 2, '2 SDF arm records emitted for ' + expectedCorner);
        assert.ok(arms.every(a => a.ownerId === 'cava1'), 'cornerWrap SDF arms carry ownerId');
        assert.deepEqual(new Set(arms.map(a => a.edge)), new Set([hEdge, vEdge]), 'SDF arms span both corner edges');

        // Verify painted edge strip does not bloat when ONLY a cornerWrap module sits on that edge
        const solo = normalize([{ id: 'solo', kind: 'cava', edge, position: pos, cornerWrap: true }], 'top');
        const paintInsets = edgeInsetsForModules(solo, opts, 1, bareEdge, 48, false);
        assert.equal(paintInsets[hEdge], bareEdge, 'cornerWrap does not bloat bare painted horizontal edge');
        assert.equal(paintInsets[vEdge], bareEdge, 'cornerWrap does not bloat bare painted vertical edge');
        const resInsets = edgeInsetsForModules(solo, opts, 1, bareEdge, 48, true);
        assert.ok(resInsets[hEdge] >= 48 && resInsets[vEdge] >= 48, 'Wayland reservation protects both corner arms');
    }
}

// 3. Duplicate corner conflict rejection (same corner via adjacent edges & via same edge)
for (const [label, pair] of [
    ['adjacent-topLeft', [
        { id: 'm1', kind: 'cava', edge: 'top', position: 0.05, cornerWrap: true },
        { id: 'm2', kind: 'clock', edge: 'left', position: 0.05, cornerWrap: true }
    ]],
    ['adjacent-bottomRight', [
        { id: 'm1', kind: 'cava', edge: 'bottom', position: 0.95, cornerWrap: true },
        { id: 'm2', kind: 'battery', edge: 'right', position: 0.95, cornerWrap: true }
    ]],
    ['same-edge-topRight', [
        { id: 'm1', kind: 'cava', edge: 'top', position: 0.85, cornerWrap: true },
        { id: 'm2', kind: 'clock', edge: 'top', position: 0.95, cornerWrap: true }
    ]]
]) {
    const dupCorner = normalize(pair, 'top');
    const dupRecs = geometry(dupCorner, 1920, 1080, { edgeThickness: 16 }, 1);
    assert.ok(conflicts(dupRecs).length > 0, `same-corner conflict reported for ${label}`);
    assert.ok(dupRecs.every(r => Boolean(r.capacityConflict)), `every colliding module carries capacityConflict for ${label}`);
}
// Toggling cornerWrap on a second module targeting an occupied corner is rejected by checkedBatch
const occupiedBase = normalize([
    { id: 'm1', kind: 'cava', edge: 'top', position: 0.05, cornerWrap: true },
    { id: 'm2', kind: 'clock', edge: 'left', position: 0.05 }
], 'top');
const dupBatch = checkedBatch(occupiedBase, ['m2'], 'cornerWrap', true, 1920, 1080, { edgeThickness: 16 }, 1);
assert.ok(dupBatch.rejected.length > 0, 'checkedBatch rejects second cornerWrap on occupied corner');
assert.equal(dupBatch.placements.find(p => p.id === 'm2').cornerWrap, undefined, 'rejected toggle preserves previous placement');

// 4. Dragging a corner-wrapped module snaps cleanly between all 4 screen corners
let cwDraft = normalize([{ id: 'm1', kind: 'workspaces', edge: 'top', position: 0.05, cornerWrap: true }], 'top');
cwDraft = move(cwDraft, 'm1', 1850, 990, 1920, 1080);
assert.equal(cornerWrapCorner(cwDraft[0]), 'bottomRight', 'drag to bottom-right quadrant snaps corner');
cwDraft = move(cwDraft, 'm1', 40, 1020, 1920, 1080);
assert.equal(cornerWrapCorner(cwDraft[0]), 'bottomLeft', 'drag to bottom-left quadrant snaps corner');

// 5. alignEdgeModules protects cornerWrap modules (excludes on whole-edge, rejects on explicit selection)
const alignMix = normalize([
    { id: 'cw1', kind: 'cava', edge: 'top', position: 0.05, cornerWrap: true },
    { id: 'lin1', kind: 'clock', edge: 'top', position: 0.25 }
], 'top');
const wholeAlign = alignEdgeModules(alignMix, [], 'top', 'center', 1920, 1080, { edgeThickness: 16 }, 1);
assert.equal(wholeAlign.rejected, '');
assert.equal(wholeAlign.placements.find(p => p.id === 'cw1').position, 0.05, 'whole-edge align leaves cornerWrap untouched');
assert.equal(wholeAlign.placements.find(p => p.id === 'lin1').alignment, 'center', 'whole-edge align still centers linear modules');
const directAlign = alignEdgeModules(alignMix, ['cw1'], 'top', 'center', 1920, 1080, { edgeThickness: 16 }, 1);
assert.ok(directAlign.rejected.length > 0, 'direct align on cornerWrap rejected cleanly');

// 6. widthFrameBetween matches cornerWrapArm pairs without collapsing or duplicating
const wfOptsA = { edgeThickness: 16, edgeWidthAffectsModules: { top: true, left: true, right: true, bottom: true } };
const wfOptsB = { edgeThickness: 16, edgeWidthAffectsModules: { top: false, left: true, right: true, bottom: true } };
const wfA = widthFrame(alignMix, 1920, 1080, wfOptsA, 1, 48, 22, 96);
const wfB = widthFrame(alignMix, 1920, 1080, wfOptsB, 1, 48, 22, 96);
const wfMid = widthFrameBetween(wfA, wfB, 0.5);
const midArms = wfMid.deformations.filter(d => d.cornerWrapArm === true);
assert.equal(midArms.length, 2, 'widthFrameBetween preserves exactly 2 cornerWrapArm surfaces (no duplication/collapse)');
assert.ok(midArms.every(a => a.surface.width > 40 && a.surface.height > 40), 'mid-morph cornerWrapArm stays full size');

// 7. Unified icon launchers cannot cornerWrap, but CAN detach into a circle icon
assert.equal(canCornerWrap('notesTimers'), false);
assert.equal(canDetachModule('notesTimers'), true);
const badCw = checkedBatch(
    normalize([{ id: 'nt', kind: 'notesTimers', edge: 'bottom', position: 0.1 }], 'bottom'),
    ['nt'], 'cornerWrap', true, 1920, 1080, { edgeThickness: 16 }, 1
);
assert.ok(badCw.rejected.length > 0, 'unified launcher rejected for cornerWrap');

// 8. Detached Circle & Pill modules across all 4 edges + both per-edge 0px and global 0px edge (iNiR iRiS island mode)
for (const edge of ['top', 'right', 'bottom', 'left']) {
    for (const cfgMode of ['global0', 'edge0', 'edge16']) {
        const bareWidth = cfgMode === 'edge16' ? 16 : 0;
        const placements = normalize([
            { id: 'iconMod', kind: 'distroIcon', edge, position: 0.15, detached: true },
            { id: 'pillMod', kind: 'clock', edge, position: 0.50, detached: true },
            { id: 'uniMod', kind: 'notesTimers', edge, position: 0.85, detached: true }
        ], edge);
        const opts = cfgMode === 'global0'
            ? { edgeThickness: 0, gap: 8 }
            : { edgeThickness: 16, edgeThicknesses: { [edge]: bareWidth }, gap: 8 };
        const recs = geometry(placements, 1920, 1080, opts, 1);
        assert.equal(recs.length, 3, `detached modules stay visible at ${cfgMode} on ${edge}`);
        const iconRec = recs.find(r => r.id === 'iconMod');
        const pillRec = recs.find(r => r.id === 'pillMod');
        const uniRec = recs.find(r => r.id === 'uniMod');

        assert.equal(iconRec.detachedShape, 'circle', 'distroIcon becomes circle icon');
        assert.equal(iconRec.content.width, iconRec.content.height, 'circle icon has equal width & height');
        assert.ok(iconRec.content.width >= 36 && iconRec.content.width <= 48, `unmeasured distroIcon detached circle stays compact (~40px), got ${iconRec.content.width}`);
        assert.equal(uniRec.detachedShape, 'circle', 'notesTimers becomes circle icon');
        assert.equal(uniRec.content.width, uniRec.content.height, 'unified circle icon is square');
        assert.equal(pillRec.detachedShape, 'pill', 'clock becomes rounded pill');
        const pillCross = (edge === 'top' || edge === 'bottom') ? pillRec.content.height : pillRec.content.width;
        assert.ok(pillCross >= 38, `detached pill keeps full 1.0x height even at ${cfgMode}, got ${pillCross}`);
        assert.equal(pillRec.detachedRadius, Math.min(pillRec.content.width, pillRec.content.height) * 0.5);

        // Verify physical separation (gap) from screen edge
        for (const r of recs) {
            if (edge === 'top') assert.ok(r.content.y >= bareWidth + 8, 'top detached floats below edge');
            if (edge === 'bottom') assert.ok(r.content.y + r.content.height <= 1080 - bareWidth - 8, 'bottom detached floats above edge');
            if (edge === 'left') assert.ok(r.content.x >= bareWidth + 8, 'left detached floats right of edge');
            if (edge === 'right') assert.ok(r.content.x + r.content.width <= 1920 - bareWidth - 8, 'right detached floats left of edge');
        }

        // Verify ZERO SDF localSurfaces (never melts back into screen edge!)
        const ls = localSurfaces(recs, 1920, 1080, opts, 1, 48);
        assert.equal(ls.length, 0, 'detached pills emit zero SDF edge-fused surfaces');

        // Verify detachedClearanceRecords pushes popups cleanly past detached pills
        const detClear = detachedClearanceRecords(recs, 1920, 1080);
        assert.equal(detClear.length, 3, 'all 3 detached modules emit popup clearance records');
        const cleared = clearanceInsets({ top: bareWidth, bottom: bareWidth, left: bareWidth, right: bareWidth },
            detClear, edge, pillRec.along, pillRec.span, pillRec.kind);
        assert.ok(cleared[edge] >= bareWidth + 44, `popup clearance clears detached pill on ${edge}: ${cleared[edge]}`);

        // Verify bare painted edge stays thin while Wayland reservation protects floating pills
        const paint = edgeInsetsForModules(placements, opts, 1, bareWidth, 48, false);
        assert.equal(paint[edge], bareWidth, 'detached pills do not bloat painted edge strip');
        const reserve = edgeInsetsForModules(placements, opts, 1, bareWidth, 48, true);
        assert.ok(reserve[edge] >= bareWidth + 44, 'Wayland reservation protects detached pills');
    }
}

// 8b. Rotated detached pill on vertical/horizontal edges must stay a sleek pill (never a giant circle!)
for (const edge of ['left', 'right']) {
    const rotPlacements = normalize([
        { id: 'rotClock', kind: 'clock', edge, position: 0.5, rotation: 0, detached: true }
    ], edge);
    const rotOpts = { edgeThickness: 16, gap: 8, extents: { rotClock: 120 } };
    const rotRecs = geometry(rotPlacements, 1920, 1080, rotOpts, 1);
    const rc = rotRecs[0];
    assert.equal(rc.detachedShape, 'pill', `rotated 0deg clock on ${edge} stays pill, not circle`);
    assert.equal(rc.content.width, 140, `rotated 0deg 120x32 clock on ${edge} gets 10px long-axis pad => 140px wide`);
    assert.equal(rc.content.height, 40, `rotated 0deg 120x32 clock on ${edge} gets 4px short-axis pad => 40px tall`);
    assert.ok(rc.content.width > rc.content.height, `rotated 0deg clock on ${edge} has content.width > content.height`);
    assert.equal(rc.detachedRadius, 20, `rotated pill radius is half of short axis (20px)`);
    const rotReserve = edgeInsetsForModules(rotPlacements, rotOpts, 1, 16, 48, true);
    assert.ok(rotReserve[edge] >= 16 + 8 + 140 + 6, `Wayland reservation protects full 140px rotated pill on ${edge}: got ${rotReserve[edge]}`);
}
for (const edge of ['top', 'bottom']) {
    const rotPlacements = normalize([
        { id: 'rotClock', kind: 'clock', edge, position: 0.5, rotation: 90, detached: true }
    ], edge);
    const rotOpts = { edgeThickness: 16, gap: 8, extents: { rotClock: 120 } };
    const rotRecs = geometry(rotPlacements, 1920, 1080, rotOpts, 1);
    const rc = rotRecs[0];
    assert.equal(rc.detachedShape, 'pill', `rotated 90deg clock on ${edge} stays pill, not circle`);
    assert.equal(rc.content.width, 40, `rotated 90deg 120x32 clock on ${edge} gets 4px short-axis pad => 40px wide`);
    assert.equal(rc.content.height, 140, `rotated 90deg 120x32 clock on ${edge} gets 10px long-axis pad => 140px tall`);
    assert.ok(rc.content.height > rc.content.width, `rotated 90deg clock on ${edge} has content.height > content.width`);
}

// 8c. Locking detached circle/pill modules (including rotated 0deg vertical-edge pill & unmeasured distroIcon)
//     must preserve exact rendered dimensions (lockScale === 1, never shrinking detached distroIcon to ~18px).
for (const tc of [
    { id: 'lkDistro', kind: 'distroIcon', edge: 'top', position: 0.2, detached: true },
    { id: 'lkNotes', kind: 'notesTimers', edge: 'bottom', position: 0.2, detached: true },
    { id: 'lkClock', kind: 'clock', edge: 'top', position: 0.5, detached: true },
    { id: 'lkRotClock', kind: 'clock', edge: 'left', position: 0.5, rotation: 0, detached: true },
    { id: 'lkRotClockTop', kind: 'clock', edge: 'top', position: 0.5, rotation: 90, detached: true },
]) {
    const base = normalize([tc], tc.edge);
    const opts = { edgeThickness: 16, gap: 8 };
    const before = geometry(base, 1920, 1080, opts, 1)[0];
    const lockedRes = checkedBatch(base, [tc.id], 'locked', true, 1920, 1080, opts, 1, [before]);
    assert.equal(lockedRes.rejected, '', `locking detached ${tc.id} should succeed`);
    assert.ok(Math.abs((lockedRes.placements[0].lockScale ?? 1) - 1) < 1e-6, `locking detached ${tc.id} must keep lockScale===1, got ${lockedRes.placements[0].lockScale}`);
    const after = geometry(lockedRes.placements, 1920, 1080, opts, 1)[0];
    assert.equal(after.content.width, before.content.width, `locked detached ${tc.id} width unchanged`);
    assert.equal(after.content.height, before.content.height, `locked detached ${tc.id} height unchanged`);
}

// 8d. Rotating a non-cava corner-wrapped module is rejected cleanly by checkedBatch,
//     while corner-wrapped Cava supports flipping bar direction (0° outward <-> 180° inward)
{
    const cwRotBase = normalize([{ id: 'cwRot', kind: 'clock', edge: 'top', position: 0.05, cornerWrap: true }], 'top');
    const cwRotRes = checkedBatch(cwRotBase, ['cwRot'], 'rotation', 'step', 1920, 1080, { edgeThickness: 16 }, 1);
    assert.ok(cwRotRes.rejected.includes('Straighten'), `checkedBatch must reject rotating non-cava cornerWrap module, got: ${cwRotRes.rejected}`);
    assert.equal(cwRotRes.placements[0].rotation, undefined, 'rejected cornerWrap rotation must not mutate placement');

    const cwCavaBase = normalize([{ id: 'cwCava', kind: 'cava', edge: 'bottom', position: 0.05, cornerWrap: true }], 'bottom');
    const cwCavaFlip1 = checkedBatch(cwCavaBase, ['cwCava'], 'rotation', 'step', 1920, 1080, { edgeThickness: 16 }, 1);
    assert.equal(cwCavaFlip1.rejected, '', `corner-wrapped cava flip should succeed, got: ${cwCavaFlip1.rejected}`);
    assert.equal(cwCavaFlip1.placements[0].rotation, 180, 'first flip on cornerWrap cava must set rotation=180 (inward)');
    assert.equal(cwCavaFlip1.placements[0].cornerWrap, true, 'flipping cornerWrap cava must keep cornerWrap=true');
    const cwCavaFlip2 = checkedBatch(cwCavaFlip1.placements, ['cwCava'], 'rotation', 'step', 1920, 1080, { edgeThickness: 16 }, 1);
    assert.equal(cwCavaFlip2.rejected, '', 'second flip on cornerWrap cava should succeed');
    assert.equal(cwCavaFlip2.placements[0].rotation, 0, 'second flip on cornerWrap cava must return rotation=0 (outward)');
}

// 9. Mutual exclusivity in checkedBatch & saveProfile -> resolve roundtrip (both per-output AND global profiles)
let batchState = normalize([
    { id: 'clk', kind: 'clock', edge: 'top', position: 0.05, joinCorner: true },
    { id: 'bat', kind: 'battery', edge: 'right', position: 0.50 },
    { id: 'leg', kind: 'weather', edge: 'bottom', position: 0.50 }
], 'top');
let r1 = checkedBatch(batchState, ['clk'], 'detached', true, 1920, 1080, { edgeThickness: 16 }, 1);
assert.equal(r1.rejected, '');
assert.equal(r1.placements.find(p => p.id === 'clk').detached, true);
assert.equal(r1.placements.find(p => p.id === 'clk').joinCorner, false);
assert.equal(r1.placements.find(p => p.id === 'clk').cornerWrap, undefined);

let r2 = checkedBatch(r1.placements, ['clk'], 'cornerWrap', true, 1920, 1080, { edgeThickness: 16 }, 1);
assert.equal(r2.rejected, '');
assert.equal(r2.placements.find(p => p.id === 'clk').cornerWrap, true);
assert.equal(r2.placements.find(p => p.id === 'clk').detached, undefined);
assert.equal(r2.placements.find(p => p.id === 'clk').joinCorner, false);

let r3 = checkedBatch(r2.placements, ['bat'], 'detached', true, 1920, 1080, { edgeThickness: 16 }, 1);
assert.equal(r3.rejected, '');
assert.equal(r3.placements.find(p => p.id === 'bat').detached, true);

// Per-output profile save -> resolve roundtrip
const savedPerOutput = saveProfile({}, 'DP-1', r3.placements, 8, true);
const reloadedPerOutput = resolve({ outputLayouts: savedPerOutput['abyss.modules.outputLayouts'] }, 'DP-1', []);
assert.equal(reloadedPerOutput.find(p => p.id === 'clk').cornerWrap, true, 'per-output cornerWrap survives save/reload');
assert.equal(reloadedPerOutput.find(p => p.id === 'clk').detached, undefined);
assert.equal(reloadedPerOutput.find(p => p.id === 'bat').detached, true, 'per-output detached survives save/reload');
assert.equal(reloadedPerOutput.find(p => p.id === 'bat').cornerWrap, undefined);
assert.equal(reloadedPerOutput.find(p => p.id === 'leg').cornerWrap, undefined, 'unrelated legacy placement stays clean');
assert.equal(reloadedPerOutput.find(p => p.id === 'leg').detached, undefined, 'unrelated legacy placement stays clean');

// Global profile save -> resolve roundtrip
const savedGlobal = saveProfile({}, 'DP-1', r3.placements, 8, false);
const reloadedGlobal = resolve({
    configured: savedGlobal['abyss.modules.configured'],
    placements: savedGlobal['abyss.modules.placements'],
    outputLayouts: savedGlobal['abyss.modules.outputLayouts']
}, 'HDMI-A-1', []);
assert.equal(reloadedGlobal.find(p => p.id === 'clk').cornerWrap, true, 'global cornerWrap survives save/reload');
assert.equal(reloadedGlobal.find(p => p.id === 'bat').detached, true, 'global detached survives save/reload');
assert.equal(reloadedGlobal.find(p => p.id === 'leg').cornerWrap, undefined, 'global legacy placement stays clean');
assert.equal(reloadedGlobal.find(p => p.id === 'leg').detached, undefined, 'global legacy placement stays clean');

// 10. Auto-hidden idle timer/shellUpdate (extents=0, editing=false) must never bloat edgeInsetsForModules
//     (paint OR reservation) or break singleModuleExpansion='local'; cornerWrapMetrics must keep unclipped arm space.
{
    const soloIdle = normalize([
        { id: 'idleT', kind: 'timer', edge: 'bottom', position: 0.5 },
        { id: 'idleU', kind: 'shellUpdate', edge: 'right', position: 0.5 }
    ], 'top');
    const idleOpts = { edgeThickness: 16, editing: false, extents: { idleT: 0, idleU: 0 } };
    const idlePaint = edgeInsetsForModules(soloIdle, idleOpts, 1, 16, 48, false);
    const idleRes = edgeInsetsForModules(soloIdle, idleOpts, 1, 16, 48, true);
    assert.deepEqual(idlePaint, { top: 16, right: 16, bottom: 16, left: 16 }, 'idle timer/shellUpdate must not bloat paintInsets');
    assert.deepEqual(idleRes, { top: 16, right: 16, bottom: 16, left: 16 }, 'idle timer/shellUpdate must not bloat reservationInsets');

    const localMix = normalize([
        { id: 'clk', kind: 'clock', edge: 'top', position: 0.5 },
        { id: 'idleT', kind: 'timer', edge: 'top', position: 0.8 }
    ], 'top');
    const localOpts = {
        edgeThickness: 16,
        editing: false,
        singleModuleExpansion: { top: 'local', right: 'edge', bottom: 'edge', left: 'edge' },
        extents: { clk: 104, idleT: 0 }
    };
    const localPaint = edgeInsetsForModules(localMix, localOpts, 1, 16, 48, false);
    assert.equal(localPaint.top, 16, 'idle timer alongside 1 normal module must preserve singleModuleExpansion=local');

    for (const sz of [0.6, 1.0, 1.8]) {
        for (const cr of [28, 48]) {
            const tRec = geometry(normalize([{ id: 'cwT', kind: 'timer', edge: 'top', position: 0.05, cornerWrap: true, customSize: true, size: sz }], 'top'), 1920, 1080, { edgeThickness: 16, cornerRadius: cr, editing: true }, 1)[0];
            const uRec = geometry(normalize([{ id: 'cwU', kind: 'shellUpdate', edge: 'bottom', position: 0.95, cornerWrap: true, customSize: true, size: sz }], 'top'), 1920, 1080, { edgeThickness: 16, cornerRadius: cr, editing: true }, 1)[0];
            assert.ok(tRec.wrapArmH >= 70, `cwTimer arm too narrow at size=${sz} cr=${cr}: ${tRec.wrapArmH}`);
            assert.ok(uRec.wrapArmH >= 74, `cwUpdate arm too narrow at size=${sz} cr=${cr}: ${uRec.wrapArmH}`);
        }
    }

    // 9b. Cava bend-module keeps full scale at edgeThickness=10, reacts to cavaWidth/cavaHeight, and emits clean L-arm SDF corners without fillet bulge
    {
        const cw120 = geometry(normalize([{ id: 'cwCava', kind: 'cava', edge: 'top', position: 0.02, cornerWrap: true }], 'top'), 1920, 1080, { edgeThickness: 10, edgeWidthAffectsModules: { top: false }, cavaWidth: 120, cavaHeight: 22 }, 1);
        const cw280 = geometry(normalize([{ id: 'cwCava', kind: 'cava', edge: 'top', position: 0.02, cornerWrap: true }], 'top'), 1920, 1080, { edgeThickness: 10, edgeWidthAffectsModules: { top: false }, cavaWidth: 280, cavaHeight: 22 }, 1);
        const cwTall = geometry(normalize([{ id: 'cwCava', kind: 'cava', edge: 'top', position: 0.02, cornerWrap: true }], 'top'), 1920, 1080, { edgeThickness: 10, edgeWidthAffectsModules: { top: false }, cavaWidth: 120, cavaHeight: 30 }, 1);
        assert.ok(cw120[0].wrapArmH >= 84, `cava at edgeThickness=10 must not shrink to tiny corner stub: ${cw120[0].wrapArmH}`);
        assert.ok(cw280[0].wrapArmH > cw120[0].wrapArmH + 60, `cavaWidth must scale corner-wrap arms: 120->${cw120[0].wrapArmH}, 280->${cw280[0].wrapArmH}`);
        assert.ok(cwTall[0].wrapThickness > cw120[0].wrapThickness, `cavaHeight must scale wrapThickness: 22->${cw120[0].wrapThickness}, 30->${cwTall[0].wrapThickness}`);
        const surf120 = localSurfaces(cw120, 1920, 1080, { edgeThickness: 10, cornerRadius: 28 }, 1, 48);
        const arms = surf120.filter(s => s.cornerWrapArm === true);
        const fillets = surf120.filter(s => s.cornerWrapFillet === true);
        assert.equal(arms.length, 2, 'cornerWrap emits strictly 2 arm surfaces');
        assert.equal(fillets.length, 0, 'cornerWrap emits zero extra bulging fillet square');
        for (const a of arms) {
            const band = a.depth;
            assert.ok(a.radius <= Math.max(8, Math.floor((a.span - band) * 0.62)), `cornerWrap arm tip radius ${a.radius} too large for span ${a.span}`);
        }
        // Width morph handles cornerWrapArm surfaces cleanly with joined top strip and no NaN or duplication
        const cwPl = normalize([
            { id: 'cwCava', kind: 'cava', edge: 'top', position: 0.02, cornerWrap: true },
            { id: 'clk1', kind: 'clock', edge: 'top', position: 0.16 }
        ], 'top');
        const f0 = widthFrame(cwPl, 1920, 1080, { edgeThickness: 0, edgeJoinModules: { top: true }, cornerRadius: 28, cavaWidth: 160 }, 1, 48, 28, 84);
        const f1 = widthFrame(cwPl, 1920, 1080, { edgeThickness: 40, edgeJoinModules: { top: true }, cornerRadius: 28, cavaWidth: 160 }, 1, 48, 28, 84);
        const mid = widthFrameBetween(f0, f1, 0.5);
        assert.equal(mid.deformations.filter(d => d.cornerWrapArm === true).length, 2, 'widthFrameBetween preserves 2 cornerWrapArms');
        assert.equal(mid.deformations.filter(d => d.cornerWrapFillet === true).length, 0, 'widthFrameBetween preserves zero cornerWrapFillet');
    }
}

console.log('ABYSS_CORNER_WRAP_AND_DETACHED_LAYOUT_PASS');
"""

subprocess.run(["node"], input=JS_PROGRAM, text=True, check=True, timeout=15)

# ─── Part 2: Parametric Corner Curve Math & QML Wiring Contracts ───
CURVE_TEST = r"""
const assert = require('node:assert/strict');
function makeCurve(wrapCorner, width, height, wrapThickness, wrapArcRadius) {
    const mirrorX = wrapCorner === 'topRight' || wrapCorner === 'bottomRight';
    const mirrorY = wrapCorner === 'bottomLeft' || wrapCorner === 'bottomRight';
    const halfT = Math.max(12, wrapThickness * 0.5);
    const safeRadius = Math.max(10, Math.min(wrapArcRadius, Math.min(width, height) - halfT - 6));
    const endPad = Math.max(8, halfT * 0.55);
    const segH = Math.max(0, (width - endPad) - (halfT + safeRadius));
    const segArc = Math.PI * 0.5 * safeRadius;
    const segV = Math.max(0, (height - endPad) - (halfT + safeRadius));
    const totalPathLength = Math.max(1, segH + segArc + segV);
    return function pointAt(t) {
        const clamped = Math.max(0, Math.min(1, Number(t) || 0));
        const s = clamped * totalPathLength;
        let lx = halfT, ly = halfT, nx = 0, ny = 1;
        if (s <= segH) {
            lx = (width - endPad) - s; ly = halfT; nx = 0; ny = 1;
        } else if (s <= segH + segArc && safeRadius > 0.01) {
            const a = Math.max(0, Math.min(Math.PI * 0.5, (s - segH) / safeRadius));
            lx = halfT + safeRadius - safeRadius * Math.sin(a);
            ly = halfT + safeRadius - safeRadius * Math.cos(a);
            nx = Math.sin(a); ny = Math.cos(a);
        } else {
            const s2 = Math.max(0, s - segH - segArc);
            lx = halfT; ly = halfT + safeRadius + s2; nx = 1; ny = 0;
        }
        const x = mirrorX ? (width - lx) : lx;
        const y = mirrorY ? (height - ly) : ly;
        const inX = mirrorX ? -nx : nx;
        const inY = mirrorY ? -ny : ny;
        return { x, y, nx: inX, ny: inY };
    };
}
for (const corner of ['topLeft', 'topRight', 'bottomLeft', 'bottomRight']) {
    const ptAt = makeCurve(corner, 140, 140, 32, 24);
    for (let i = 0; i <= 20; ++i) {
        const p = ptAt(i / 20);
        assert.ok(p.x >= 0 && p.x <= 140 && p.y >= 0 && p.y <= 140, `${corner} t=${i/20} out of bounds`);
        assert.ok(Math.abs(Math.hypot(p.nx, p.ny) - 1) < 1e-6, `${corner} normal not unit length`);
    }
    const mid = ptAt(0.5);
    const wantX = corner.includes('Left') ? 1 : -1;
    const wantY = corner.includes('top') ? 1 : -1;
    assert.ok(mid.nx * wantX > 0.6 && mid.ny * wantY > 0.6, `${corner} apex normal points outward`);
}
console.log('ABYSS_CORNER_CURVE_MATH_PASS');
"""
subprocess.run(["node"], input=CURVE_TEST, text=True, check=True, timeout=10)

bar_mod = (ROOT / "modules/abyss/bar/AbyssBarModule.qml").read_text(encoding="utf-8")
bar_qml = (ROOT / "modules/abyss/bar/AbyssBar.qml").read_text(encoding="utf-8")
editor_qml = (ROOT / "modules/abyss/AbyssEdgeEditor.qml").read_text(encoding="utf-8")
cw_qml = (ROOT / "modules/abyss/bar/AbyssCornerWrapContent.qml").read_text(encoding="utf-8")
timer_ind = (ROOT / "modules/bar/TimerIndicator.qml").read_text(encoding="utf-8")
upd_ind = (ROOT / "modules/bar/ShellUpdateIndicator.qml").read_text(encoding="utf-8")

assert "abyssMicMeterEnabled: true" in bar_mod, "concurrent Mic Meter WIP line must remain intact"
assert 'objectName: "abyssDetachedPillSurface"' in bar_mod
assert 'objectName: "abyssCornerWrapContentLoader"' in bar_mod
assert "AbyssStyle.surface" in bar_mod and "AbyssStyle.surfaceDeep" in bar_mod
assert "colLayer1Base" not in bar_mod.split("detachedPillBg")[1].split("Rectangle {")[0], "detachedPillBg must match Screen Edge surface color rather than washing out to colLayer1Base"
assert "Config.options?.bar?.cava?.width" in cw_qml and "Config.options?.bar?.cava?.height" in cw_qml
assert "Config.options?.bar?.cava?.barSpacing" in cw_qml and "Config.options?.bar?.cava?.barRadius" in cw_qml
assert "Config.options?.bar?.cava?.mirror" in cw_qml and "Config.options?.appearance?.cava?.bars" in cw_qml
assert "computeNormalizedBars(" in cw_qml and "cornerCavaProc.audioSignalActive" in cw_qml
assert "Config.options?.bar?.cava?.width" in bar_qml and "Config.options?.bar?.cava?.height" in bar_qml
assert "Config.options?.bar?.cava?.width" in editor_qml and "Config.options?.bar?.cava?.height" in editor_qml
assert "editPreview: root.editing" in bar_mod
assert "editing: root.editing" in bar_mod
assert "wrapHorizontalRect" in bar_qml and "wrapVerticalRect" in bar_qml
assert "detachedClearanceRecords(" in bar_qml
assert "editing: root.editing" in bar_qml
assert "syncMeasuredSpan()" in bar_qml
assert "onFeatureChanged: syncMeasuredSpan()" in bar_qml
assert "onPlacementChanged: syncMeasuredSpan()" in bar_qml
assert "geometry === undefined || geometry.cornerWrap === true" in bar_qml
assert "hoverActivates: !root.showEditPreview" in timer_ind and "hoverActivates: !root.showEditPreview" in upd_ind
assert "hoverEnabled: !root.showEditPreview" in timer_ind and "hoverEnabled: !root.showEditPreview" in upd_ind
assert "verticalContent ? updateBadgeText.implicitHeight : updateBadgeText.implicitWidth" in upd_ind
assert 'root.useHorizontalDock ? "abyssModuleCornerWrap" : ""' in editor_qml
assert '!root.useHorizontalDock ? "abyssModuleCornerWrap" : ""' in editor_qml
assert 'root.useHorizontalDock ? "abyssModuleDetached" : ""' in editor_qml
assert '!root.useHorizontalDock ? "abyssModuleDetached" : ""' in editor_qml
assert "dockModuleInspectorScroll" in editor_qml
assert "readonly property var horizontalCenter:" not in cw_qml, "must never shadow QQuickItem FINAL horizontalCenter"
assert "readonly property var verticalCenter:" not in cw_qml, "must never shadow QQuickItem FINAL verticalCenter"
assert "ColorPickerService.start()" in cw_qml
assert "Audio.toggleMicMute()" in cw_qml
assert "function pointAt(t: real): var" in cw_qml
assert "function containsArmPoint(px: real, py: real): bool" in cw_qml
assert cw_qml.count("containmentMask: armContainmentMask") >= 9, "root + all 8 bounding-box MouseAreas must use armContainmentMask"
assert "property bool editing:" in cw_qml
assert "readonly property bool contentAvailable:" in cw_qml
assert "showEditPreview" in cw_qml and "showEditPreview" in timer_ind and "showEditPreview" in upd_ind
assert "function containsPointerPoint(px: real, py: real): bool" in bar_mod
assert "containmentMask:" in bar_mod
assert "import QtQuick.Shapes" in editor_qml
assert 'objectName: "abyssCornerWrapOutline"' in editor_qml
assert "PathArc.Counterclockwise" in editor_qml
assert "import qs.modules.abyss.content" in cw_qml

qmlformat = "/usr/lib/qt6/bin/qmlformat"
if Path(qmlformat).is_file():
    for rel in [
        "modules/abyss/bar/AbyssCornerWrapContent.qml",
        "modules/abyss/bar/AbyssBarModule.qml",
        "modules/abyss/bar/AbyssBar.qml",
        "modules/abyss/AbyssEdgeEditor.qml",
        "modules/bar/TimerIndicator.qml",
        "modules/bar/ShellUpdateIndicator.qml",
    ]:
        subprocess.run([qmlformat, str(ROOT / rel)], stdout=subprocess.DEVNULL, check=True)
print("ABYSS_CORNER_DETACHED_CONTRACT_PASS")

# ─── Part 3: Silent Offscreen Quickshell Runtime Compilation & Instantiation Test ───
# Always executes AbyssBar, AbyssBarModule, ALL 14 AbyssCornerWrapContent kinds,
# and AbyssEdgeEditor in real Qt6/Quickshell QML engine (catching FINAL property
# collisions, invalid imports, binding loops, and inspector layout bugs even in
# sandboxes without a Wayland compositor).
if not shutil.which("qs"):
    print("SKIP_OFFSCREEN_RUNTIME: qs unavailable")
    raise SystemExit(0)

def make_panelwindow_free_stub(rel_path: str) -> str:
    txt = (ROOT / rel_path).read_text(encoding="utf-8")
    lines = ["import QtQuick", "Item {", "    id: root", "    property bool active: false", "    property var item: null"]
    seen = {"active", "item"}
    for line in txt.splitlines():
        ms = re.match(r"^    (signal\s+\w+.*)", line)
        if ms:
            lines.append("    " + ms.group(1))
            continue
        m = re.match(r"^    ((?:required\s+)?(?:readonly\s+)?property\s+(\S+)\s+(\w+))", line)
        if not m:
            continue
        ptype, pname = m.group(2), m.group(3)
        if pname in seen or pname in ("id", "x", "y", "width", "height", "visible", "enabled", "opacity", "z", "parent", "data", "children", "anchors"):
            continue
        seen.add(pname)
        if ptype == "bool": default = "false"
        elif ptype in ("int", "real", "double"): default = "0"
        elif ptype == "string": default = '""'
        elif ptype in ("var", "Item", "QtObject", "Component"): default = "null"
        elif ptype == "color": default = '"transparent"'
        else: continue
        lines.append(f"    property {ptype} {pname}: {default}")
    lines.append("    default property alias _stubContent: host.data")
    lines.append("    function open() {}")
    lines.append("    function close() {}")
    lines.append("    function popup() {}")
    lines.append("    function toggle() {}")
    lines.append("    Item { id: host }")
    lines.append("}")
    return "\n".join(lines)

def copy_modules_with_stubs(src_root: Path, dst_root: Path, stubs: dict[str, str]):
    dst_root.mkdir(parents=True, exist_ok=True)
    for p in src_root.iterdir():
        rel = str(p.relative_to(ROOT))
        if rel in stubs:
            (dst_root / p.name).write_text(stubs[rel], encoding="utf-8")
        elif p.is_dir() and any(s.startswith(rel + "/") for s in stubs):
            copy_modules_with_stubs(p, dst_root / p.name, stubs)
        else:
            (dst_root / p.name).symlink_to(p)

with tempfile.TemporaryDirectory(prefix="alis-corner-detached-rt-") as name:
    folder = Path(name)
    for entry in ["services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    stubs = {
        "modules/bar/StyledPopup.qml": make_panelwindow_free_stub("modules/bar/StyledPopup.qml"),
        "modules/common/widgets/ContextMenu.qml": make_panelwindow_free_stub("modules/common/widgets/ContextMenu.qml"),
    }
    copy_modules_with_stubs(ROOT / "modules", folder / "modules", stubs)

    cfg = folder / "config/alis"
    cfg.mkdir(parents=True)
    data = json.loads((ROOT / "defaults/config.json").read_text(encoding="utf-8"))
    data["panelFamily"] = "abyss"
    data["abyss"]["companion"]["enabled"] = False
    data["shellUpdates"]["enabled"] = False
    (cfg / "config.json").write_text(json.dumps(data), encoding="utf-8")

    (folder / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.bar as SharedBar
import qs.modules.abyss
import qs.modules.abyss.bar
import "modules/abyss/looks/AbyssLayout.js" as Layout

ShellRoot {
    id: root
    Component.onCompleted: Quickshell.watchFiles = false

    Item {
        id: stage
        width: 1280
        height: 720

        AbyssSurfaceController {
            id: controller
            outputWidth: stage.width
            outputHeight: stage.height
            presentationItem: stage
        }

        AbyssBar {
            id: bar
            anchors.fill: parent
            outputName: "OFFSCREEN-1"
            edge: "top"
            editing: true
            liquidController: controller
            draftPlacements: Layout.normalize([
                { id: "cwCava", kind: "cava", edge: "top", position: 0.05, cornerWrap: true },
                { id: "cwWs", kind: "workspaces", edge: "bottom", position: 0.95, cornerWrap: true },
                { id: "cwRes", kind: "resources", edge: "top", position: 0.95, cornerWrap: true },
                { id: "cwClk", kind: "clock", edge: "bottom", position: 0.05, cornerWrap: true },
                { id: "detClock", kind: "clock", edge: "top", position: 0.5, detached: true },
                { id: "detIcon", kind: "distroIcon", edge: "top", position: 0.72, detached: true },
                { id: "detRotClock", kind: "clock", edge: "left", position: 0.5, rotation: 0, detached: true }
            ], "top")
        }

        // Dedicated bar for Timer & Updates edit-mode sample preview vs non-editing auto-hide lifecycle
        AbyssBar {
            id: previewBar
            anchors.fill: parent
            outputName: "OFFSCREEN-1"
            edge: "top"
            editing: true
            liquidController: controller
            draftPlacements: Layout.normalize([
                { id: "linTimer", kind: "timer", edge: "top", position: 0.25 },
                { id: "linUpdate", kind: "shellUpdate", edge: "top", position: 0.38 },
                { id: "rotTopTimer", kind: "timer", edge: "top", position: 0.56, rotation: 90 },
                { id: "rotTopUpdate", kind: "shellUpdate", edge: "top", position: 0.68, rotation: 90 },
                { id: "rotTimer", kind: "timer", edge: "left", position: 0.35 },
                { id: "rotUpdate", kind: "shellUpdate", edge: "right", position: 0.35 },
                { id: "detTimer", kind: "timer", edge: "bottom", position: 0.35, detached: true },
                { id: "detUpdate", kind: "shellUpdate", edge: "bottom", position: 0.58, detached: true },
                { id: "cwTimer", kind: "timer", edge: "top", position: 0.95, cornerWrap: true },
                { id: "cwUpdate", kind: "shellUpdate", edge: "bottom", position: 0.05, cornerWrap: true },
                { id: "cwTimerSmall", kind: "timer", edge: "top", position: 0.05, cornerWrap: true, customSize: true, size: 0.6 },
                { id: "cwUpdateLarge", kind: "shellUpdate", edge: "bottom", position: 0.95, cornerWrap: true, customSize: true, size: 1.8 }
            ], "top")
        }

        // Cancel-after-cornerWrap-toggle regression bar
        AbyssBar {
            id: cancelBar
            anchors.fill: parent
            outputName: "OFFSCREEN-1"
            edge: "top"
            editing: false
            liquidController: controller
            draftPlacements: Layout.normalize([
                { id: "cancelTimer", kind: "timer", edge: "top", position: 0.3 },
                { id: "cancelUpdate", kind: "shellUpdate", edge: "top", position: 0.5 }
            ], "top")
        }

        // Non-edited secondary output verifies multi-monitor isolation (never shows phantom preview)
        AbyssBar {
            id: otherOutputBar
            anchors.fill: parent
            outputName: "OFFSCREEN-2"
            edge: "top"
            editing: false
            liquidController: controller
            draftPlacements: Layout.normalize([
                { id: "otherLinTimer", kind: "timer", edge: "top", position: 0.3 },
                { id: "otherLinUpdate", kind: "shellUpdate", edge: "top", position: 0.5 },
                { id: "otherCwTimer", kind: "timer", edge: "top", position: 0.95, cornerWrap: true },
                { id: "otherCwUpdate", kind: "shellUpdate", edge: "bottom", position: 0.05, cornerWrap: true }
            ], "top")
        }

        // Standalone indicators verifying GlobalStates.abyssEditing default binding
        SharedBar.TimerIndicator { id: standaloneTimer }
        SharedBar.ShellUpdateIndicator { id: standaloneUpdate; y: 48 }
        AbyssCornerWrapContent { id: standaloneCwTimer; width: 140; height: 140; kind: "timer"; outputName: "OFFSCREEN-1"; wrapCorner: "topRight" }
        AbyssCornerWrapContent { id: standaloneCwUpdate; width: 140; height: 140; kind: "shellUpdate"; outputName: "OFFSCREEN-1"; wrapCorner: "bottomLeft" }

        Repeater {
            id: allKindsRepeater
            model: ["cava", "workspaces", "resources", "clock", "media", "battery", "weather", "activeWindow", "utilButtons", "taskbar", "tray", "distroIcon", "timer", "shellUpdate"]
            delegate: AbyssCornerWrapContent {
                required property string modelData
                required property int index
                width: 140
                height: 140
                kind: modelData
                outputName: "OFFSCREEN-1"
                wrapCorner: ["topLeft", "topRight", "bottomLeft", "bottomRight"][index % 4]
            }
        }

        AbyssEdgeEditor {
            id: editor
            anchors.fill: parent
            outputName: "OFFSCREEN-1"
            moduleLayer: bar
            controller: controller
            visible: true
        }
    }

    function findByObjectName(item, target) {
        if (!item) return null
        if (item.objectName === target) return item
        const kids = item.children ?? []
        for (let i = 0; i < kids.length; ++i) {
            const found = findByObjectName(kids[i], target)
            if (found) return found
        }
        return null
    }

    function setIdleIndicators() {
        TimerService.pomodoroRunning = false
        TimerService.pomodoroSecondsLeft = TimerService.pomodoroLapDuration
        TimerService.countdownRunning = false
        TimerService.countdownDuration = 0
        TimerService.countdownSecondsLeft = 0
        TimerService.stopwatchRunning = false
        TimerService.stopwatchTime = 0
        TimerService.stopwatchLaps = []
        if (Persistent?.states?.timer)
            Persistent.states.timer.pinnedToBar = false
        ShellUpdates.hasUpdate = false
        ShellUpdates.isUpdating = false
        ShellUpdates.commitsBehind = 0
    }

    property int testPhase: 0

    function fail(msg) {
        console.error("ABYSS_CORNER_DETACHED_RUNTIME_FAIL", msg)
        Qt.quit()
    }

    Timer {
        id: phaseTimer
        interval: 350
        running: true
        repeat: false
        onTriggered: {
            try {
                if (root.testPhase === 0) {
                    // Existing Corner Wrap, Detached Pill & Editor assertions
                    const cwItem = bar.itemForId("cwCava")
                    const wsItem = bar.itemForId("cwWs")
                    const clkItem = bar.itemForId("detClock")
                    const iconItem = bar.itemForId("detIcon")
                    const rotClkItem = bar.itemForId("detRotClock")
                    if (!cwItem || !cwItem.cornerWrap || cwItem.wrapCorner !== "topLeft")
                        throw new Error("cwCava cornerWrap state invalid")
                    if (cwItem.popupJoinedEdge !== "left")
                        throw new Error("cwCava popupJoinedEdge expected left, got " + cwItem.popupJoinedEdge)
                    if (!wsItem || !wsItem.cornerWrap || wsItem.wrapCorner !== "bottomRight")
                        throw new Error("cwWs cornerWrap state invalid")
                    if (!clkItem || !clkItem.detached || clkItem.detachedShape !== "pill")
                        throw new Error("detClock detached pill state invalid")
                    if (!iconItem || !iconItem.detached || iconItem.detachedShape !== "circle")
                        throw new Error("detIcon detached circle state invalid")
                    if (iconItem.width > 52 || iconItem.height > 52)
                        throw new Error("detIcon detached circle bloated: " + iconItem.width + "x" + iconItem.height)
                    if (!rotClkItem || !rotClkItem.detached || rotClkItem.detachedShape !== "pill")
                        throw new Error("detRotClock rotated detached state invalid: " + (rotClkItem ? rotClkItem.detachedShape : "null"))
                    if (!(rotClkItem.width > rotClkItem.height))
                        throw new Error("detRotClock on left edge with rotation 0 turned into circle/square: " + rotClkItem.width + "x" + rotClkItem.height)
                    const pillSurface = root.findByObjectName(clkItem, "abyssDetachedPillSurface")
                    if (!pillSurface || !pillSurface.visible)
                        throw new Error("detached pill surface missing or hidden")
                    const cwLoader = root.findByObjectName(cwItem, "abyssCornerWrapContentLoader")
                    if (!cwLoader || !cwLoader.active || !cwLoader.item)
                        throw new Error("cornerWrap content loader inactive")
                    if (!cwItem.contains(Qt.point(16, 16)) || !cwItem.contains(Qt.point(cwItem.width - 12, 16)) || !cwItem.contains(Qt.point(16, cwItem.height - 12)))
                        throw new Error("cwItem (topLeft) rejected valid corner/arm point")
                    if (cwItem.contains(Qt.point(cwItem.width - 10, cwItem.height - 10)))
                        throw new Error("cwItem (topLeft) leaked hit-test into empty inner desktop quadrant")
                    if (allKindsRepeater.count !== 14)
                        throw new Error("expected 14 cornerWrap kinds, got " + allKindsRepeater.count)
                    for (let k = 0; k < allKindsRepeater.count; ++k) {
                        const inst = allKindsRepeater.itemAt(k)
                        if (!inst || !inst.hArmCenter || !inst.vArmCenter)
                            throw new Error("cornerWrap kind index " + k + " missing arm geometry")
                        const c = inst.wrapCorner
                        const mx = (c === "topRight" || c === "bottomRight")
                        const my = (c === "bottomLeft" || c === "bottomRight")
                        const apexX = mx ? inst.width - 16 : 16
                        const apexY = my ? inst.height - 16 : 16
                        const hArmX = mx ? 20 : inst.width - 20
                        const hArmY = apexY
                        const vArmX = apexX
                        const vArmY = my ? 20 : inst.height - 20
                        const innerX = mx ? 30 : inst.width - 30
                        const innerY = my ? 30 : inst.height - 30
                        if (!inst.containsArmPoint(apexX, apexY))
                            throw new Error(inst.kind + " (" + c + ") rejected corner apex")
                        if (!inst.containsArmPoint(hArmX, hArmY))
                            throw new Error(inst.kind + " (" + c + ") rejected horizontal arm")
                        if (!inst.containsArmPoint(vArmX, vArmY))
                            throw new Error(inst.kind + " (" + c + ") rejected vertical arm")
                        if (inst.containsArmPoint(innerX, innerY))
                            throw new Error(inst.kind + " (" + c + ") leaked hit-test in inner desktop quadrant")
                        if (inst.containsArmPoint(-4, apexY) || inst.containsArmPoint(inst.width + 4, apexY))
                            throw new Error(inst.kind + " (" + c + ") accepted out-of-bounds point")
                        const loadedChild = inst.children[0] && inst.children[0].item ? inst.children[0].item : null
                        if (loadedChild && typeof loadedChild.contains === "function" && loadedChild.hoverEnabled === true) {
                            if (!loadedChild.contains(Qt.point(apexX, apexY)))
                                throw new Error(inst.kind + " MouseArea rejected corner apex")
                            if (loadedChild.contains(Qt.point(innerX, innerY)))
                                throw new Error(inst.kind + " MouseArea leaked hover into inner desktop quadrant")
                        }
                    }
                    editor.draft = Layout.normalize([
                        { id: "testMod", kind: "clock", edge: "top", position: 0.25 }
                    ], "top")
                    editor.refreshHandles()
                    editor.select("testMod")
                    const cwBtn = root.findByObjectName(editor, "abyssModuleCornerWrap")
                    const detBtn = root.findByObjectName(editor, "abyssModuleDetached")
                    if (!cwBtn || !detBtn)
                        throw new Error("editor toggle buttons missing: cw=" + cwBtn + " det=" + detBtn)
                    editor.change("cornerWrap", true)
                    if (editor.draft[0].cornerWrap !== true || editor.draft[0].detached === true)
                        throw new Error("editor cornerWrap toggle failed")
                    if (editor.canRotateSelection)
                        throw new Error("rotate should be disabled while module is corner-wrapped")
                    editor.rotateSelection()
                    if (!editor.feedback.includes("Straighten"))
                        throw new Error("rotateSelection on cornerWrap gave misleading feedback: " + editor.feedback)
                    const outline = root.findByObjectName(editor, "abyssCornerWrapOutline")
                    if (!outline)
                        throw new Error("editor seamless L-shape abyssCornerWrapOutline missing")
                    editor.change("detached", true)
                    if (editor.draft[0].detached !== true || editor.draft[0].cornerWrap === true)
                        throw new Error("editor detached toggle failed")
                    if (!editor.canRotateSelection)
                        throw new Error("rotate should re-enable after switching from cornerWrap to detached")
                    if (bar.deformations.some(d => d.detachedClearance === true))
                        throw new Error("detached clearance leaked into SDF deformations")
                    if (!bar.clearanceDeformations.some(d => d.detachedClearance === true))
                        throw new Error("detached clearance missing from clearanceDeformations")

                    // Prepare Phase 1: Idle Timer & ShellUpdates in Edit Abyss Layout
                    root.setIdleIndicators()
                    GlobalStates.abyssEditorTargetOutput = "OFFSCREEN-1"
                    GlobalStates.abyssEditing = true
                    previewBar.editing = true
                    // Also open cancelBar in edit mode and toggle both indicators to cornerWrap
                    cancelBar.editing = true
                    cancelBar.draftPlacements = Layout.normalize([
                        { id: "cancelTimer", kind: "timer", edge: "top", position: 0.05, cornerWrap: true },
                        { id: "cancelUpdate", kind: "shellUpdate", edge: "bottom", position: 0.95, cornerWrap: true }
                    ], "top")
                    root.testPhase = 1
                    phaseTimer.interval = 120
                    phaseTimer.restart()
                    return
                }

                if (root.testPhase === 1) {
                    // Phase 1: Edit Mode Sample Previews across linear, rotated, detached, and corner-wrap
                    const ids = ["linTimer", "linUpdate", "rotTopTimer", "rotTopUpdate", "rotTimer", "rotUpdate", "detTimer", "detUpdate", "cwTimer", "cwUpdate", "cwTimerSmall", "cwUpdateLarge"]
                    for (const id of ids) {
                        const m = previewBar.itemForId(id)
                        if (!m || !m.visible || !m.geometry || !m.contentAvailable)
                            throw new Error("Phase 1 edit preview hidden for " + id + ": vis=" + (m ? m.visible : "null") + " avail=" + (m ? m.contentAvailable : "null"))
                        if (!(m.width > 0 && m.height > 0))
                            throw new Error("Phase 1 zero-sized box for " + id + ": " + m.width + "x" + m.height)
                    }
                    // Linear Timer sample
                    const linTimer = previewBar.itemForId("linTimer")
                    if (!linTimer.feature || !linTimer.feature.showEditPreview || !linTimer.feature.visible)
                        throw new Error("linTimer sample preview not visible in edit mode")
                    if (linTimer.feature.hoverEnabled)
                        throw new Error("linTimer must disable hoverEnabled during showEditPreview")
                    if (linTimer.feature.timeText !== "25:00")
                        throw new Error("linTimer sample text expected 25:00, got " + linTimer.feature.timeText)
                    if (!(linTimer.naturalSpan > 35))
                        throw new Error("linTimer naturalSpan too small/zero in edit mode: " + linTimer.naturalSpan)
                    const linTimerLabel = root.findByObjectName(linTimer, "timerIndicatorLabel")
                    const linTimerHg = root.findByObjectName(linTimer, "barHourglassIcon")
                    if (!linTimerLabel || linTimerLabel.text !== "25:00" || !linTimerHg || !linTimerHg.visible)
                        throw new Error("linTimer hourglass or label missing in edit mode")
                    // Manually rotated 90deg Timer on top edge (perpendicular)
                    const rotTopTimer = previewBar.itemForId("rotTopTimer")
                    const rotTopLabel = root.findByObjectName(rotTopTimer, "timerIndicatorLabel")
                    if (!rotTopTimer.feature || !rotTopTimer.feature.verticalContent || !rotTopTimer.feature.showEditPreview)
                        throw new Error("rotTopTimer verticalContent sample state invalid")
                    if (!rotTopLabel || rotTopLabel.text !== "25\n00")
                        throw new Error("rotTopTimer rotated label expected 25\\n00, got " + (rotTopLabel ? rotTopLabel.text : "null"))
                    if (!(rotTopTimer.height > rotTopTimer.width))
                        throw new Error("rotTopTimer perpendicular rotation dimensions invalid: " + rotTopTimer.width + "x" + rotTopTimer.height)
                    // Rotated Timer sample
                    const rotTimer = previewBar.itemForId("rotTimer")
                    const rotTimerLabel = root.findByObjectName(rotTimer, "timerIndicatorLabel")
                    if (!rotTimer.feature || !rotTimer.feature.verticalContent || !rotTimer.feature.showEditPreview)
                        throw new Error("rotTimer verticalContent sample state invalid")
                    if (!rotTimerLabel || rotTimerLabel.text !== "25\n00")
                        throw new Error("rotTimer rotated label expected 25\\n00, got " + (rotTimerLabel ? rotTimerLabel.text : "null"))
                    if (!(rotTimer.naturalSpan > 30))
                        throw new Error("rotTimer naturalSpan too small: " + rotTimer.naturalSpan)
                    // Detached Timer sample
                    const detTimer = previewBar.itemForId("detTimer")
                    const detTimerSurface = root.findByObjectName(detTimer, "abyssDetachedPillSurface")
                    if (!detTimer.detached || !detTimerSurface || !detTimerSurface.visible || !detTimer.feature.visible)
                        throw new Error("detTimer detached pill sample missing")
                    if (!(detTimer.width >= detTimer.naturalSpan))
                        throw new Error("detTimer detached pill clipped content: w=" + detTimer.width + " natural=" + detTimer.naturalSpan)
                    // Linear, Rotated & Detached Updates samples
                    for (const uid of ["linUpdate", "rotTopUpdate", "rotUpdate", "detUpdate"]) {
                        const u = previewBar.itemForId(uid)
                        const badge = root.findByObjectName(u, "shellUpdateBadgeText")
                        if (!u.feature || !u.feature.showEditPreview || !u.feature.visible)
                            throw new Error(uid + " sample preview not visible in edit mode")
                        if (u.feature.hoverEnabled)
                            throw new Error(uid + " must disable hoverEnabled during showEditPreview")
                        if (!badge || badge.text !== "3")
                            throw new Error(uid + " sample badge expected '3', got " + (badge ? badge.text : "null"))
                        if (!(u.naturalSpan > 25))
                            throw new Error(uid + " naturalSpan too small/zero in edit mode: " + u.naturalSpan)
                    }
                    const rotTopUpdate = previewBar.itemForId("rotTopUpdate")
                    if (!(rotTopUpdate.naturalSpan >= 48) || !(rotTopUpdate.height > rotTopUpdate.width))
                        throw new Error("rotTopUpdate rotated badge geometry invalid: span=" + rotTopUpdate.naturalSpan + " box=" + rotTopUpdate.width + "x" + rotTopUpdate.height)
                    const detUpdate = previewBar.itemForId("detUpdate")
                    const detUpdSurface = root.findByObjectName(detUpdate, "abyssDetachedPillSurface")
                    if (!detUpdate.detached || !detUpdSurface || !detUpdSurface.visible)
                        throw new Error("detUpdate detached pill surface missing")
                    if (!(detUpdate.width >= detUpdate.naturalSpan))
                        throw new Error("detUpdate detached pill clipped content: w=" + detUpdate.width + " natural=" + detUpdate.naturalSpan)
                    // Corner-Wrap Timer & Updates samples across scales 0.6x, 1.0x, 1.8x (must NEVER truncate or overflow!)
                    for (const cid of ["cwTimer", "cwTimerSmall"]) {
                        const cwT = previewBar.itemForId(cid)
                        const lbl = root.findByObjectName(cwT, "cornerWrapTimerLabel")
                        const hg = root.findByObjectName(cwT, "cornerWrapTimerHourglass")
                        if (!cwT.cornerWrap || !lbl || lbl.text !== "25:00" || !hg || !hg.visible)
                            throw new Error(cid + " corner-wrap sample invalid: label=" + (lbl ? lbl.text : "null"))
                        if (lbl.truncated)
                            throw new Error(cid + " corner-wrap sample label truncated: w=" + lbl.width + " impW=" + lbl.implicitWidth)
                        if (lbl.x < -0.5 || lbl.x + lbl.width > cwT.width + 0.5)
                            throw new Error(cid + " corner-wrap sample label overflowed box: [" + lbl.x + ".." + (lbl.x + lbl.width) + "] vs w=" + cwT.width)
                    }
                    for (const cid of ["cwUpdate", "cwUpdateLarge"]) {
                        const cwU = previewBar.itemForId(cid)
                        const lbl = root.findByObjectName(cwU, "cornerWrapUpdateLabel")
                        const bdg = root.findByObjectName(cwU, "cornerWrapUpdateBadge")
                        if (!cwU.cornerWrap || !lbl || lbl.text !== "Update" || !bdg || bdg.text !== "3")
                            throw new Error(cid + " corner-wrap sample invalid: label=" + (lbl ? lbl.text : "null") + " badge=" + (bdg ? bdg.text : "null"))
                        if (lbl.truncated || bdg.truncated)
                            throw new Error(cid + " corner-wrap sample truncated: lblTrunc=" + lbl.truncated + " bdgTrunc=" + bdg.truncated)
                        if (lbl.x < -0.5 || lbl.x + lbl.width > cwU.width + 0.5)
                            throw new Error(cid + " corner-wrap sample label overflowed box: [" + lbl.x + ".." + (lbl.x + lbl.width) + "] vs w=" + cwU.width)
                    }
                    // Multi-monitor isolation: OFFSCREEN-2 (editing: false) stays 100% hidden with zero inset bloat even while OFFSCREEN-1 is editing
                    if (otherOutputBar.layoutRecords.length !== 0 || otherOutputBar.deformations.length !== 0)
                        throw new Error("Non-edited monitor OFFSCREEN-2 leaked phantom timer/update slots: recs=" + otherOutputBar.layoutRecords.length + " defs=" + otherOutputBar.deformations.length)
                    for (const side of ["top", "right", "bottom", "left"]) {
                        if ((otherOutputBar.targetFrame?.paintInsets?.[side] ?? 0) > 16 || (otherOutputBar.targetFrame?.reservationInsets?.[side] ?? 0) > 16)
                            throw new Error("Non-edited monitor OFFSCREEN-2 bloated inset on " + side + ": paint=" + otherOutputBar.targetFrame?.paintInsets?.[side] + " res=" + otherOutputBar.targetFrame?.reservationInsets?.[side])
                    }

                    // Transition to Phase 2: Exit Edit Mode while still idle + simulate Cancel on cancelBar (simultaneous editing=false + cornerWrap=false)
                    GlobalStates.abyssEditing = false
                    previewBar.editing = false
                    cancelBar.editing = false
                    cancelBar.draftPlacements = Layout.normalize([
                        { id: "cancelTimer", kind: "timer", edge: "top", position: 0.3 },
                        { id: "cancelUpdate", kind: "shellUpdate", edge: "top", position: 0.5 }
                    ], "top")
                    root.testPhase = 2
                    phaseTimer.interval = 160
                    phaseTimer.restart()
                    return
                }

                if (root.testPhase === 2) {
                    // Phase 2: Non-editing idle auto-hide across ALL modes (linear, rotated, detached, corner-wrap)
                    const ids = ["linTimer", "linUpdate", "rotTopTimer", "rotTopUpdate", "rotTimer", "rotUpdate", "detTimer", "detUpdate", "cwTimer", "cwUpdate", "cwTimerSmall", "cwUpdateLarge"]
                    for (const id of ids) {
                        const m = previewBar.itemForId(id)
                        if (!m)
                            throw new Error("Phase 2 missing module instance " + id)
                        if (m.contentAvailable || m.visible || m.geometry !== undefined)
                            throw new Error("Phase 2 phantom idle slot remained for " + id + ": avail=" + m.contentAvailable + " vis=" + m.visible + " geom=" + Boolean(m.geometry))
                        if (!m.cornerWrap && m.naturalSpan !== 0)
                            throw new Error("Phase 2 non-zero naturalSpan while idle for " + id + ": " + m.naturalSpan)
                    }
                    // Verify zero corner-wrap Loader thrashing when idle outside edit mode
                    for (const cid of ["cwTimer", "cwUpdate", "cwTimerSmall", "cwUpdateLarge"]) {
                        const cm = previewBar.itemForId(cid)
                        if (!cm.cornerWrap || cm.feature !== null)
                            throw new Error("Phase 2 cornerWrap module thrashed loader while idle: " + cid + " cornerWrap=" + cm.cornerWrap + " feature=" + Boolean(cm.feature))
                    }
                    if (previewBar.layoutRecords.length !== 0)
                        throw new Error("Phase 2 phantom layoutRecords while idle: " + previewBar.layoutRecords.length)
                    if (previewBar.deformations.length !== 0)
                        throw new Error("Phase 2 phantom SDF deformations while idle: " + previewBar.deformations.length)
                    if (previewBar.clearanceDeformations.length !== 0)
                        throw new Error("Phase 2 phantom clearanceDeformations while idle: " + previewBar.clearanceDeformations.length)
                    for (const side of ["top", "right", "bottom", "left"]) {
                        if ((previewBar.targetFrame?.paintInsets?.[side] ?? 0) > 16 || (previewBar.targetFrame?.reservationInsets?.[side] ?? 0) > 16)
                            throw new Error("Phase 2 idle previewBar bloated inset on " + side + ": paint=" + previewBar.targetFrame?.paintInsets?.[side] + " res=" + previewBar.targetFrame?.reservationInsets?.[side])
                    }
                    // Verify Cancel-after-cornerWrap-toggle cleanly collapses to 0 with zero phantom records/insets
                    if (cancelBar.layoutRecords.length !== 0 || cancelBar.deformations.length !== 0
                            || (cancelBar.measuredExtents["cancelTimer"] ?? -1) !== 0 || (cancelBar.measuredExtents["cancelUpdate"] ?? -1) !== 0)
                        throw new Error("Phase 2 cancelBar leaked phantom state after cornerWrap Cancel: recs=" + cancelBar.layoutRecords.length + " extents=" + JSON.stringify(cancelBar.measuredExtents))

                    // Transition to Phase 3: Live active Countdown & pending ShellUpdate outside edit mode
                    TimerService.countdownDuration = 60
                    TimerService.countdownSecondsLeft = 45
                    ShellUpdates.hasUpdate = true
                    ShellUpdates.commitsBehind = 5
                    root.testPhase = 3
                    phaseTimer.interval = 120
                    phaseTimer.restart()
                    return
                }

                if (root.testPhase === 3) {
                    // Phase 3: Live indicators appear cleanly outside edit mode (including corner-wrap!)
                    const ids = ["linTimer", "linUpdate", "rotTopTimer", "rotTopUpdate", "rotTimer", "rotUpdate", "detTimer", "detUpdate", "cwTimer", "cwUpdate", "cwTimerSmall", "cwUpdateLarge"]
                    for (const id of ids) {
                        const m = previewBar.itemForId(id)
                        if (!m || !m.contentAvailable || !m.visible || !m.geometry)
                            throw new Error("Phase 3 live active module failed to appear for " + id)
                    }
                    const linTimer = previewBar.itemForId("linTimer")
                    if (linTimer.feature.showEditPreview || linTimer.feature.timeText !== "00:45")
                        throw new Error("Phase 3 linTimer should show live 00:45, got " + linTimer.feature.timeText)
                    const cwTimer = previewBar.itemForId("cwTimer")
                    const cwTimerLabel = root.findByObjectName(cwTimer, "cornerWrapTimerLabel")
                    if (!cwTimer.cornerWrap || !cwTimerLabel || cwTimerLabel.text !== "00:45")
                        throw new Error("Phase 3 cwTimer should show live 00:45, got " + (cwTimerLabel ? cwTimerLabel.text : "null"))
                    if (!(previewBar.measuredExtents["cwTimer"] >= 60))
                        throw new Error("Phase 3 cwTimer re-activated with clipped extent: " + previewBar.measuredExtents["cwTimer"])
                    const linUpdate = previewBar.itemForId("linUpdate")
                    const linUpdBadge = root.findByObjectName(linUpdate, "shellUpdateBadgeText")
                    if (linUpdate.feature.showEditPreview || !linUpdBadge || linUpdBadge.text !== "5")
                        throw new Error("Phase 3 linUpdate should show live badge 5, got " + (linUpdBadge ? linUpdBadge.text : "null"))
                    const cwUpdate = previewBar.itemForId("cwUpdate")
                    const cwUpdBadge = root.findByObjectName(cwUpdate, "cornerWrapUpdateBadge")
                    if (!cwUpdate.cornerWrap || !cwUpdBadge || cwUpdBadge.text !== "5")
                        throw new Error("Phase 3 cwUpdate should show live badge 5, got " + (cwUpdBadge ? cwUpdBadge.text : "null"))
                    if (!(previewBar.measuredExtents["cwUpdate"] >= 70))
                        throw new Error("Phase 3 cwUpdate re-activated with clipped extent: " + previewBar.measuredExtents["cwUpdate"])

                    // Transition to Phase 4: Enter Edit Mode WHILE live timer & update are active
                    previewBar.editing = true
                    root.testPhase = 4
                    phaseTimer.interval = 120
                    phaseTimer.restart()
                    return
                }

                if (root.testPhase === 4) {
                    // Phase 4: Live active timer/update must NOT be overwritten by sample data during edit mode
                    const linTimer = previewBar.itemForId("linTimer")
                    const cwTimerLabel = root.findByObjectName(previewBar.itemForId("cwTimer"), "cornerWrapTimerLabel")
                    const linUpdBadge = root.findByObjectName(previewBar.itemForId("linUpdate"), "shellUpdateBadgeText")
                    const cwUpdBadge = root.findByObjectName(previewBar.itemForId("cwUpdate"), "cornerWrapUpdateBadge")
                    if (linTimer.feature.showEditPreview || linTimer.feature.timeText !== "00:45")
                        throw new Error("Phase 4 edit mode clobbered live timer")
                    if (!cwTimerLabel || cwTimerLabel.text !== "00:45")
                        throw new Error("Phase 4 edit mode clobbered live corner-wrap timer")
                    if (!linUpdBadge || linUpdBadge.text !== "5" || !cwUpdBadge || cwUpdBadge.text !== "5")
                        throw new Error("Phase 4 edit mode clobbered live update badge")

                    // Clear live states while still editing -> must fall back seamlessly to sample previews
                    root.setIdleIndicators()
                    root.testPhase = 5
                    phaseTimer.interval = 120
                    phaseTimer.restart()
                    return
                }

                if (root.testPhase === 5) {
                    const linTimer = previewBar.itemForId("linTimer")
                    const cwTimerLabel = root.findByObjectName(previewBar.itemForId("cwTimer"), "cornerWrapTimerLabel")
                    const linUpdBadge = root.findByObjectName(previewBar.itemForId("linUpdate"), "shellUpdateBadgeText")
                    const cwUpdBadge = root.findByObjectName(previewBar.itemForId("cwUpdate"), "cornerWrapUpdateBadge")
                    if (!linTimer.feature.showEditPreview || linTimer.feature.timeText !== "25:00")
                        throw new Error("Phase 5 failed to fall back to timer sample while editing")
                    if (!cwTimerLabel || cwTimerLabel.text !== "25:00")
                        throw new Error("Phase 5 failed to fall back to corner-wrap timer sample while editing")
                    if (!linUpdBadge || linUpdBadge.text !== "3" || !cwUpdBadge || cwUpdBadge.text !== "3")
                        throw new Error("Phase 5 failed to fall back to update sample while editing")

                    // Exit edit mode again + verify standalone GlobalStates.abyssEditing default binding
                    previewBar.editing = false
                    GlobalStates.abyssEditorTargetOutput = ""
                    GlobalStates.abyssEditing = false
                    root.testPhase = 6
                    phaseTimer.interval = 120
                    phaseTimer.restart()
                    return
                }

                if (root.testPhase === 6) {
                    if (previewBar.layoutRecords.length !== 0 || previewBar.deformations.length !== 0 || previewBar.clearanceDeformations.length !== 0)
                        throw new Error("Phase 6 failed to re-hide idle modules after exiting edit mode")
                    if (standaloneTimer.contentAvailable || standaloneTimer.visible || standaloneTimer.implicitWidth !== 0)
                        throw new Error("Phase 6 standaloneTimer visible while idle outside GlobalStates.abyssEditing")
                    if (standaloneUpdate.contentAvailable || standaloneUpdate.visible || standaloneUpdate.implicitWidth !== 0)
                        throw new Error("Phase 6 standaloneUpdate visible while idle outside GlobalStates.abyssEditing: avail=" + standaloneUpdate.contentAvailable + " vis=" + standaloneUpdate.visible + " w=" + standaloneUpdate.implicitWidth + " editPrev=" + standaloneUpdate.editPreview + " live=" + standaloneUpdate.liveContentAvailable)
                    if (standaloneCwTimer.contentAvailable || standaloneCwUpdate.contentAvailable)
                        throw new Error("Phase 6 standalone cornerWrap contentAvailable true while idle outside GlobalStates.abyssEditing")

                    GlobalStates.abyssEditing = true
                    if (!standaloneTimer.contentAvailable || !standaloneTimer.showEditPreview || !standaloneTimer.visible || !(standaloneTimer.implicitWidth > 35))
                        throw new Error("Phase 6 standaloneTimer failed to show sample on GlobalStates.abyssEditing=true: w=" + standaloneTimer.implicitWidth)
                    if (!standaloneUpdate.contentAvailable || !standaloneUpdate.showEditPreview || !standaloneUpdate.visible || !(standaloneUpdate.implicitWidth > 25))
                        throw new Error("Phase 6 standaloneUpdate failed to show sample on GlobalStates.abyssEditing=true: w=" + standaloneUpdate.implicitWidth)
                    if (!standaloneCwTimer.contentAvailable || !standaloneCwUpdate.contentAvailable)
                        throw new Error("Phase 6 standalone cornerWrap failed to enable sample on GlobalStates.abyssEditing=true")

                    GlobalStates.abyssEditing = false
                    if (standaloneTimer.contentAvailable || standaloneTimer.implicitWidth !== 0)
                        throw new Error("Phase 6 standaloneTimer failed to re-hide on GlobalStates.abyssEditing=false")
                    if (standaloneUpdate.contentAvailable || standaloneUpdate.implicitWidth !== 0)
                        throw new Error("Phase 6 standaloneUpdate failed to re-hide on GlobalStates.abyssEditing=false")
                    if (standaloneCwTimer.contentAvailable || standaloneCwUpdate.contentAvailable)
                        throw new Error("Phase 6 standalone cornerWrap failed to re-hide on GlobalStates.abyssEditing=false")

                    // Verify vertical Classic Bar orientation + pinnedToBar parity remain intact
                    standaloneTimer.vertical = true
                    standaloneUpdate.vertical = true
                    if (standaloneTimer.implicitWidth !== 0 || standaloneTimer.implicitHeight !== 0)
                        throw new Error("Phase 6 vertical idle standaloneTimer must stay 0x0")
                    if (standaloneUpdate.implicitWidth !== 0 || standaloneUpdate.implicitHeight !== 0)
                        throw new Error("Phase 6 vertical idle standaloneUpdate must stay 0x0")
                    if (Persistent?.states?.timer) {
                        Persistent.states.timer.pinnedToBar = true
                        if (!standaloneTimer.contentAvailable || !standaloneTimer.showPinnedIdle || standaloneTimer.showEditPreview)
                            throw new Error("Phase 6 pinnedToBar idle state broken")
                        if (!standaloneCwTimer.contentAvailable)
                            throw new Error("Phase 6 cornerWrap timer failed to honor pinnedToBar")
                        Persistent.states.timer.pinnedToBar = false
                        if (standaloneTimer.contentAvailable || standaloneTimer.implicitWidth !== 0)
                            throw new Error("Phase 6 unpinned standaloneTimer failed to collapse to 0")
                    }

                    console.info("ABYSS_CORNER_DETACHED_RUNTIME_PASS")
                    Qt.quit()
                }
            } catch (e) {
                root.fail(e.message)
            }
        }
    }
}
''', encoding="utf-8")

    env = os.environ.copy()
    for k in ["WAYLAND_DISPLAY", "DISPLAY", "QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"]:
        env.pop(k, None)
    env.update(
        QT_QPA_PLATFORM="offscreen",
        QT_QUICK_BACKEND="software",
        XDG_CONFIG_HOME=str(folder / "config"),
        XDG_STATE_HOME=str(folder / "state"),
        XDG_CACHE_HOME=str(folder / "cache"),
    )
    res = subprocess.run(["qs", "-p", str(folder), "--no-color"], env=env, text=True, capture_output=True, timeout=25)
    log = res.stdout + res.stderr
    bad = ["ABYSS_CORNER_DETACHED_RUNTIME_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Cannot assign", "Cannot override FINAL"]
    if res.returncode != 0 or "ABYSS_CORNER_DETACHED_RUNTIME_PASS" not in log or any(b in log for b in bad):
        print(log)
        raise SystemExit(1)
    print("ABYSS_CORNER_DETACHED_RUNTIME_PASS")
