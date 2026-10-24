#!/usr/bin/env node
// UTIL-F01 presentation geometry, without starting/changing a compositor.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const source = fs.readFileSync(new URL('../modules/settings/MonitorArrangementViewport.js', import.meta.url), 'utf8');
const scope = vm.createContext({});
vm.runInContext(source.replace(/^\.pragma library\s*$/m, ''), scope);
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-7 * Math.max(1, Math.abs(a), Math.abs(b)), `${a} != ${b}`);
let fitted = 0, inverses = 0, zooms = 0;
const layouts = [
    [{x: 0, y: 0, width: 1920, height: 1080}],
    [{x: 0, y: 0, width: 1920, height: 1080}, {x: 1920, y: -400, width: 1080, height: 1920}],
    [{x: -7680, y: -1000, width: 7680, height: 4320}, {x: 0, y: 0, width: 7680, height: 4320}, {x: 7680, y: -1000, width: 7680, height: 4320}],
    [{x: -500, y: -8640, width: 2160, height: 3840}, {x: 0, y: -4320, width: 2160, height: 3840}, {x: 500, y: 0, width: 2160, height: 3840}],
    Array.from({length: 8}, (_, index) => ({x: index * 8192, y: index % 2 * 160, width: 8192, height: 4608})),
    [{x: -2000000000, y: -1500, width: 1920, height: 1080}, {x: 2000000000, y: 0, width: 2560, height: 1440}],
];
for (const layout of layouts) {
    const minX = Math.min(...layout.map(r => r.x)), minY = Math.min(...layout.map(r => r.y));
    const logical = {minX, minY, width: Math.max(...layout.map(r => r.x + r.width)) - minX,
        height: Math.max(...layout.map(r => r.y + r.height)) - minY};
    const px = Math.max(240, logical.width * .12), py = Math.max(180, logical.height * .28);
    const bounds = {minX: minX - px, minY: minY - py, width: logical.width + 2 * px, height: logical.height + 2 * py};
    for (const width of [220, 320, 420, 500, 900]) for (const height of [160, 200, 252, 360]) for (const padding of [8, 24, 36]) {
        const fit = scope.fitScale(bounds, width, Math.min(height, 252), padding) * .65;
        const offset = scope.centeredOffset(bounds, width, height, fit);
        for (const rect of layout) {
            const left = rect.x * fit + offset.x, top = rect.y * fit + offset.y;
            assert.ok(left >= -1e-6 && top >= -1e-6);
            assert.ok(left + rect.width * fit <= width + 1e-6);
            assert.ok(top + rect.height * fit <= height + 1e-6);
            near((left - offset.x) / fit, rect.x);
            near((top - offset.y) / fit, rect.y);
            fitted++; inverses += 2;
        }
        const pivot = {x: width * .3, y: height * .7};
        const next = fit * 2;
        const center = scope.centeredOffset(bounds, width, height, next);
        const pan = scope.zoomPan(pivot.x, pivot.y, fit, next, offset, center);
        const worldX = (pivot.x - offset.x) / fit, worldY = (pivot.y - offset.y) / fit;
        near(worldX * next + center.x + pan.x, pivot.x);
        near(worldY * next + center.y + pan.y, pivot.y);
        const bounded = scope.boundedPan(1e12, -1e12, logical, width, height, next);
        assert.ok(Number.isFinite(bounded.x) && Number.isFinite(bounded.y));
        assert.ok(bounded.x < 1e12 && bounded.y > -1e12);
        zooms++;
    }
}
// Frozen old 0.025 floor clips a realistic three-8K layout in this viewport.
const oldWidth = (23040 + 2 * 2764.8) * .025;
assert.ok(oldWidth > 500);
assert.equal(scope.dragCoordinate(-50, 1, 500, 120, 8), -49);
assert.equal(scope.dragCoordinate(450, -1, 500, 120, 8), 449);
assert.equal(scope.dragCoordinate(80, 5, 500, 120, 8), 85);
assert.equal(scope.dragCoordinate(80, -500, 500, 120, 8), 8);
assert.equal(scope.dragCoordinate(80, 500, 500, 120, 8), 372);
const qml = fs.readFileSync(new URL('../modules/settings/MonitorVisibilityConfig.qml', import.meta.url), 'utf8');
assert.ok(qml.includes('return ArrangementViewport.fitScale(bounds, width, tileFitHeight, innerPadding)'));
assert.ok(qml.includes('Number.EPSILON, fitScale * root.arrangementVisualScale * zoomFactor'));
assert.ok(qml.includes('ArrangementViewport.dragCoordinate(monitorRect.dragOriginCanvasX'));
assert.ok(qml.includes('acceptedButtons: Qt.MiddleButton'));
assert.ok(qml.includes('!root.monitorLayoutBusy && root.draggingLayoutOutput.length === 0'));
console.log(`MONITOR_VIEWPORT_PASS ${fitted} fitted tiles; ${inverses} inverse mappings; ${zooms} cursor-pivot zoom cases; clipped-origin drag regressions PASS`);
