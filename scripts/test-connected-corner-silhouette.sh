#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
node - "$repo_root/modules/common/perimeter/ConnectedSurfaceAbyssFrame.qml" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const frame = fs.readFileSync(process.argv[2], 'utf8');

function binding(name, next) {
    const marker = `readonly property ${name}:`;
    const start = frame.indexOf(marker);
    assert.ok(start >= 0, `missing ${name} binding`);
    const end = frame.indexOf(next, start + marker.length);
    assert.ok(end > start, `unterminated ${name} binding`);
    return frame.slice(start + marker.length, end).trim();
}

const cornerJoined = new Function('root',
    `return (${binding('bool cornerJoined', '\n\n    visible:')});`);
const paintSource = binding('rect rawPaintBounds',
    '\n\n    readonly property rect paintBounds:');
assert.ok(paintSource.startsWith('{') && paintSource.endsWith('}'));
const rawPaintBounds = new Function('root', 'Qt',
    paintSource.slice(1, -1));
const sdfSource = binding('rect sdfBodyRect',
    '\n\n    readonly property rect ownerShapeRect:');
assert.ok(sdfSource.startsWith('{') && sdfSource.endsWith('}'));
const sdfBodyRect = new Function('root', 'Qt', 'PerimeterTokens',
    sdfSource.slice(1, -1));
const joinsSource = binding('var popupPrimaryJoins',
    '\n\n    readonly property var popupShape:');
assert.ok(joinsSource.startsWith('{') && joinsSource.endsWith('}'));
const popupPrimaryJoins = new Function('root', joinsSource.slice(1, -1));
const popupShape = new Function('root',
    `return (${binding('var popupShape', '\n\n    // The shader ABI')});`);
const endJoinShape = new Function('root',
    `return (${binding('var popupEndJoinShape', '\n\n    // A box shadow')});`);

const Qt = { rect: (x, y, width, height) => ({x, y, width, height}) };
const PerimeterTokens = { abyssWeldDepth: 3 };
const cases = [
    ['top', 'start', {x: 7, y: 7, width: 103, height: 80}],
    ['top', 'end', {x: 390, y: 7, width: 103, height: 80}],
    ['bottom', 'start', {x: 7, y: 313, width: 103, height: 80}],
    ['bottom', 'end', {x: 390, y: 313, width: 103, height: 80}],
    ['left', 'start', {x: 7, y: 7, width: 100, height: 83}],
    ['left', 'end', {x: 7, y: 310, width: 100, height: 83}],
    ['right', 'start', {x: 393, y: 7, width: 100, height: 83}],
    ['right', 'end', {x: 393, y: 310, width: 100, height: 83}],
];

for (const [edge, side, expected] of cases) {
    const horizontal = edge === 'top' || edge === 'bottom';
    const body = Qt.rect(
        horizontal ? (side === 'start' ? 10 : 390)
            : (edge === 'left' ? 7 : 393),
        horizontal ? (edge === 'top' ? 7 : 313)
            : (side === 'start' ? 10 : 310),
        100, 80);
    const root = {
        body, horizontal, geometry: { edge, outerRadius: 28 },
        tangentStartJoined: side === 'start',
        tangentEndJoined: side === 'end',
        fuse: 30, aaReach: 2,
    };
    root.cornerJoined = cornerJoined(root);
    assert.equal(root.cornerJoined, true, `${edge}/${side} joins a Screen Edge`);
    root.popupPrimaryJoins = popupPrimaryJoins(root);
    assert.deepEqual(root.popupPrimaryJoins,
        ['owner', side === 'start' ? 'frame-start' : 'frame-end']);
    const paint = rawPaintBounds(root, Qt);
    const freeReach = root.fuse + root.aaReach;
    if (edge === 'top')
        assert.equal(paint.y + paint.height,
            body.y + body.height + freeReach);
    else if (edge === 'bottom')
        assert.equal(paint.y, body.y - freeReach);
    else if (edge === 'left')
        assert.equal(paint.x + paint.width,
            body.x + body.width + freeReach);
    else
        assert.equal(paint.x, body.x - freeReach);
    root.sdfBodyRect = sdfBodyRect(root, Qt, PerimeterTokens);
    assert.deepEqual(root.sdfBodyRect, expected,
        `${edge}/${side} welds only beneath its tangent Screen Edge`);
    const shape = popupShape(root);
    assert.equal(shape.fuse, 30,
        `${edge}/${side} keeps both curved owner contacts`);
    assert.equal(shape.radius, 28,
        `${edge}/${side} keeps its body radius`);
}

const center = {
    body: Qt.rect(200, 7, 100, 80), horizontal: true,
    geometry: {edge: 'top', outerRadius: 28},
    tangentStartJoined: false, tangentEndJoined: false,
    fuse: 30, aaReach: 2,
};
center.cornerJoined = cornerJoined(center);
center.popupPrimaryJoins = popupPrimaryJoins(center);
center.sdfBodyRect = sdfBodyRect(center, Qt, PerimeterTokens);
assert.equal(center.cornerJoined, false);
assert.equal(rawPaintBounds(center, Qt).height, center.body.height + 2,
    'mid-edge popups keep their previous raster bounds');
assert.deepEqual(center.sdfBodyRect, center.body,
    'popup away from output corners retains its original body geometry');
assert.equal(popupShape(center).fuse, 30,
    'popup away from output corners retains its smooth owner join');

center.tangentStartJoined = true;
center.tangentEndJoined = true;
center.cornerJoined = cornerJoined(center);
center.sdfBodyRect = sdfBodyRect(center, Qt, PerimeterTokens);
center.needsEndJoinAux = true;
assert.equal(endJoinShape(center).radius, 28,
    'both tangent contacts retain the body radius');
assert.equal(endJoinShape(center).fuse, 30,
    'the second tangent contact receives the same round fillet');
assert.deepEqual(endJoinShape(center).joins, ['owner', 'frame-end']);
assert.ok(frame.includes('root.clipExternalOwners(root.body, 0)'),
    'input stays on the original body while only the SDF reaches under owners');
console.log('connected corner silhouette: PASS (8 corners, center, both edges)');
NODE
