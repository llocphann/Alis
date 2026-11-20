#!/usr/bin/env node
import assert from "node:assert/strict";
import fs from "node:fs";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const layoutPath = fileURLToPath(
    new URL("../modules/abyss/looks/AbyssLayout.js", import.meta.url)
);
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(layoutPath, "utf8"), ctx);

const W = 1920;
const H = 1080;
const opts = { gap: 8, edgeThickness: 16, extents: { a: 80, b: 100, c: 90, opp: 80 } };

// 1. Quarter-axis snap (25% / 75%)
{
    const base = ctx.normalize([{ id: "a", kind: "clock", edge: "top", position: 0.1 }], "top");
    const q25 = ctx.snapMove(base, "a", W * 0.25 + 4, 12, W, H, opts, 1);
    assert.equal(q25.guides[0].label, "25%");
    assert.ok(Math.abs(q25.placements[0].position - 0.25) < 1e-4);

    const q75 = ctx.snapMove(base, "a", W * 0.75 - 5, 12, W, H, opts, 1);
    assert.equal(q75.guides[0].label, "75%");
    assert.ok(Math.abs(q75.placements[0].position - 0.75) < 1e-4);

    // Outside tolerance must stay free (guides.length === 0)
    const free = ctx.snapMove(base, "a", 620, 12, W, H, opts, 1);
    assert.equal(free.guides.length, 0);
}

// 2. Opposite-edge Mirror symmetry snap
{
    const pair = ctx.normalize([
        { id: "opp", kind: "clock", edge: "bottom", position: 0.37 },
        { id: "a", kind: "battery", edge: "top", position: 0.15 },
    ], "top");
    const snapped = ctx.snapMove(pair, "a", W * 0.37 + 3, 12, W, H, opts, 1);
    assert.equal(snapped.guides[0].label, "Mirror");
    assert.ok(Math.abs(snapped.placements.find((p) => p.id === "a").position - 0.37) < 0.01);
}

// 3. Equal-gap midpoint snap & spacing measurement descriptor
{
    const trio = ctx.normalize([
        { id: "a", kind: "clock", edge: "top", position: 0.15 },
        { id: "c", kind: "media", edge: "top", position: 0.32 },
        { id: "b", kind: "battery", edge: "top", position: 0.55 },
    ], "top");
    const recs = ctx.geometry(trio.filter((p) => p.id !== "c"), W, H, opts, 1);
    const leftRec = recs.find((r) => r.id === "a");
    const rightRec = recs.find((r) => r.id === "b");
    const midX = (leftRec.along + leftRec.span + rightRec.along) / 2;
    const eqSnap = ctx.snapMove(trio, "c", midX + 3, 12, W, H, opts, 1);
    assert.ok(eqSnap.guides[0].label.startsWith("Equal "), `Expected Equal guide, got ${eqSnap.guides[0].label}`);
    assert.ok(eqSnap.guides.some((g) => g.kind === "spacing" && g.gapPx > 0), "Expected live pixel spacing descriptor");
}

// 4. Auto-Align modes (center, distribute, mirror, packStart, packEnd, lock guard)
{
    const mods = ctx.normalize([
        { id: "a", kind: "clock", edge: "top", position: 0.12 },
        { id: "b", kind: "battery", edge: "top", position: 0.25 },
        { id: "c", kind: "weather", edge: "top", position: 0.85 },
    ], "top");

    const dist = ctx.alignEdgeModules(mods, [], "top", "distribute", W, H, opts, 1);
    assert.equal(dist.rejected, "");
    const distRecs = ctx.geometry(dist.placements, W, H, opts, 1).sort((x, y) => x.along - y.along);
    const low = distRecs[0].edgeStart;
    const high = distRecs[0].edgeEnd;
    const g0 = distRecs[0].along - low;
    const g1 = distRecs[1].along - (distRecs[0].along + distRecs[0].span);
    const g2 = distRecs[2].along - (distRecs[1].along + distRecs[1].span);
    const g3 = high - (distRecs[2].along + distRecs[2].span);
    assert.ok(Math.abs(g0 - g1) < 2 && Math.abs(g1 - g2) < 2 && Math.abs(g2 - g3) < 2, "Gaps should be equal across Edge");

    const centered = ctx.alignEdgeModules(mods, ["a", "b", "c"], "top", "center", W, H, opts, 1);
    assert.equal(centered.rejected, "");
    const cRecs = ctx.geometry(centered.placements, W, H, opts, 1).sort((x, y) => x.along - y.along);
    const groupCenter = (cRecs[0].along + cRecs[2].along + cRecs[2].span) / 2;
    assert.ok(Math.abs(groupCenter - W / 2) < 2, "Group should center symmetrically on W/2");

    const packedStart = ctx.alignEdgeModules(mods, ["a", "b"], "top", "packStart", W, H, opts, 1);
    assert.equal(packedStart.rejected, "");
    const pStartRecs = ctx.geometry(packedStart.placements, W, H, opts, 1).filter((r) => r.id === "a" || r.id === "b").sort((x, y) => x.along - y.along);
    assert.ok(Math.abs(pStartRecs[0].along - pStartRecs[0].edgeStart) < 2);
    assert.ok(Math.abs(pStartRecs[1].along - (pStartRecs[0].along + pStartRecs[0].span + opts.gap)) < 2);

    const packedEnd = ctx.alignEdgeModules(mods, ["b", "c"], "top", "packEnd", W, H, opts, 1);
    assert.equal(packedEnd.rejected, "");
    const pEndRecs = ctx.geometry(packedEnd.placements, W, H, opts, 1).filter((r) => r.id === "b" || r.id === "c").sort((x, y) => x.along - y.along);
    assert.ok(Math.abs((pEndRecs[1].along + pEndRecs[1].span) - pEndRecs[1].edgeEnd) < 2);

    const mirrored = ctx.alignEdgeModules(mods, ["a"], "top", "mirror", W, H, opts, 1);
    assert.equal(mirrored.rejected, "");
    assert.ok(Math.abs(mirrored.placements.find((p) => p.id === "a").position - 0.88) < 0.02);

    // Locked module guard
    const locked = mods.map((m) => (m.id === "a" ? { ...m, locked: true } : m));
    const denied = ctx.alignEdgeModules(locked, ["a", "b"], "top", "center", W, H, opts, 1);
    assert.ok(denied.rejected.length > 0, "Locked target must reject align");
}

console.log("ABYSS_RULER_ALIGN_PASS");
