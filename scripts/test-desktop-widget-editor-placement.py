#!/usr/bin/env python3
"""Verify bottom-connected 2-tier Abyss widget customization dock placement."""
from pathlib import Path
import subprocess

source = (Path(__file__).resolve().parents[1] /
          "modules/background/widgets/DesktopWidgetEditorPlacement.js").read_text()
subprocess.run(["node", "-e", source + r'''
const assert = require('node:assert/strict');

const work = {left: 16, top: 48, right: 1184, bottom: 784};
const wide = {left: 0, top: 0, right: 1920, bottom: 1080};
const small = {left: 3.5, top: 20.25, right: 390.75, bottom: 680.5};
const fullBottom = {x: 0, y: 680, width: 1200, height: 120, key: "bottom"};
const fullTop = {x: 0, y: 0, width: 1200, height: 130, key: "top"};

// Always bottom-connected across empty, crowded, and multi-edge widget layouts
const empty = choose(work, [], "");
assert.equal(empty.edge, "bottom");
assert.equal(empty.span, 1080);
assert.equal(empty.depth, 168);
assert.equal(empty.along, 60);
assert.equal(empty.y, 784 - 168);

// Collapsed 1-tier depth (~54px) and expanded 2-tier depth (~168px)
const collapsed = choose(work, [], "", 54);
assert.equal(collapsed.edge, "bottom");
assert.equal(collapsed.depth, 54);
assert.equal(collapsed.y, 784 - 54);

const expanded = choose(work, [], "", 180);
assert.equal(expanded.edge, "bottom");
assert.equal(expanded.depth, 180);
assert.equal(expanded.y, 784 - 180);

// Never rotates to top/left/right even when bottom or all edges are occupied
assert.equal(choose(work, [fullBottom], "").edge, "bottom");
assert.equal(choose(work, [fullBottom, fullTop], "").edge, "bottom");
assert.equal(choose(work, [fullBottom, fullTop, {x: 0, y: 0, width: 110, height: 800}], "").edge, "bottom");
assert.equal(choose(work, [fullBottom], "").span, 1080, "full-width obstacle does not pointlessly shrink span");

// Slides horizontally along bottom edge to clear a bottom widget while keeping full 1080 span
const slid = choose(wide, [{x: 320, y: 940, width: 260, height: 120, key: "leftLow"}], "");
assert.equal(slid.edge, "bottom");
assert.equal(slid.span, 1080);
assert.ok(slid.x >= 320 + 260 + 12 - 1e-6, "slides past bottom obstacle without overlap");

// Clamps span cleanly into an open bottom interval when 1080 cannot fit around a corner widget
const clamped = choose(work, [{x: 920, y: 660, width: 240, height: 110, key: "corner"}], "");
assert.equal(clamped.edge, "bottom");
assert.ok(clamped.span >= 420 && clamped.span < 1080, "clamps span into clear bottom gap");
assert.ok(clamped.x + clamped.width <= 920 - 12 + 1e-6, "clamped bottom dock avoids corner widget");

// Prioritizes avoiding selectedKey (weight 4) when bottom has competing obstacles
const weighted = choose(wide, [
    {x: 60, y: 940, width: 820, height: 120, key: "sel"},
    {x: 1040, y: 940, width: 820, height: 120, key: "other"}
], "sel");
assert.equal(weighted.edge, "bottom");
assert.ok(weighted.along > 420, "shifts away from selected widget");

// 3000 deterministic crowded layouts stay bounded on bottom edge
for (const area of [work, small, wide]) {
    for (let i = 0; i < 1000; i++) {
        const widgets = Array.from({length: 8}, (_, n) => ({
            key: "w" + n,
            x: (i * 97 + n * 127) % area.right,
            y: (i * 61 + n * 211) % area.bottom,
            width: 100 + n * 30,
            height: 70 + n * 10
        }));
        const p = choose(area, widgets, "w0");
        assert.equal(p.edge, "bottom");
        assert.ok(p.x >= area.left - 1e-9 && p.y >= area.top - 1e-9);
        assert.ok(p.x + p.width <= area.right + 1e-9 && p.y + p.height <= area.bottom + 1e-9);
        assert.deepEqual(choose(area, widgets, "w0"), p, "deterministic placement");
    }
}

const crowded = [fullBottom, fullTop, {x: 0, y: 0, width: 1200, height: 800, key: "all"}];
assert.ok(Number.isFinite(choose(work, crowded, "all").along));
assert.deepEqual(choose(work, [{x: NaN, y: 0, width: 10, height: 10}], ""), choose(work, [], ""));
console.log("PASS: bottom-connected Abyss widget customization dock placement, horizontal slide/clamp, and 3000 crowded layouts");
'''], check=True)
