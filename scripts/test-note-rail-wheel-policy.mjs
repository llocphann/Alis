import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const policy = vm.createContext({});
vm.runInContext(readFileSync(new URL('../modules/sidebarRight/notepad/NoteRailWheel.js', import.meta.url), 'utf8'), policy);
const qml = readFileSync(new URL('../modules/sidebarRight/notepad/NotepadWidget.qml', import.meta.url), 'utf8');
let checks = 0;
function check(actual, expected, message) {
    checks++;
    assert.deepEqual(JSON.parse(JSON.stringify(actual)), expected, message);
}
function gesture() {
    let state = policy.idle(), clock = 1000;
    return {
        event(input, wait = 10) {
            clock += wait;
            const before = JSON.stringify(state);
            const result = policy.advance(state, input, clock);
            check(JSON.stringify(state), before, 'state was mutated across components');
            state = result.state;
            return result;
        },
        state() { return JSON.parse(JSON.stringify(state)); }
    };
}
const angle = (y, extra = {}) => ({angleDelta: {x: 0, y}, ...extra});
const pixel = (y, extra = {}) => ({pixelDelta: {x: 0, y}, angleDelta: {x: 0, y: y < 0 ? -120 : 120}, ...extra});

let g = gesture();
check(g.event(angle(-120)).step, 1, 'mouse wheel down should choose next note');
check(g.event(angle(-120)).step, 0, 'rapid wheel packets skipped adjacent note');
check(g.event(angle(-120), 145).step, 1, 'deliberate second detent was blocked');
check(g.event(angle(120)).step, -1, 'reverse direction should be immediate');
check(g.event(angle(120), 20).step, 0, 'one wheel burst skipped too fast');
g = gesture();
for (let i = 0; i < 3; i++) check(g.event(pixel(-12)).step, 0, 'touchpad packets should accumulate');
check(g.event(pixel(-12)).step, 1, '48px touchpad gesture must advance one note');
check(g.event(pixel(-12)).step, 0, 'touchpad packet should not advance another note');
check(g.event(pixel(-12), 150).step, 0, 'sub-threshold leftover scroll advanced tab');
check(g.event(pixel(-36), 10).step, 1, 'smooth continued scroll did not advance');
g = gesture();
check(g.event({pixelDelta: {x: -120, y: 0}, angleDelta: {x: -120, y: 0}}).accepted,
    false, 'horizontal swipe must never switch note');
check(g.event({angleDelta: {x: -120, y: 0}, shifted: true}).step,
    1, 'Shift remapped wheel must stay on note rail, not pan horizontally');
check(g.event({angleDelta: {x: 0, y: -120}, blocked: true}).accepted,
    false, 'Ctrl/Alt/Meta gestures should belong to their owner');
g = gesture();
check(g.event({pixelDelta: {y: -20}, phase: 1}).step, 0);
check(g.event({pixelDelta: {y: -28}, phase: 2}).step, 1);
check(g.event({pixelDelta: {y: -1000}, phase: 4}).step, 0, 'momentum coast switched notes');
check(g.event({pixelDelta: {y: -1000}, phase: 3}).step, 0, 'ScrollEnd switched notes');
check(g.event({pixelDelta: {y: -48}, phase: 1}).step, 1, 'new gesture failed after ScrollEnd');
g = gesture();
check(g.event({angleDelta: {y: 0}}).accepted, false, 'empty delta must not select previous note');
check(g.event({angleDelta: {y: Infinity}}).accepted, false, 'non-finite delta changed note');
check(g.event({pixelDelta: {y: -24}}).step, 0);
check(g.event({pixelDelta: {y: -24}}, 250).step, 0, 'old partial delta leaked into new gesture');
check(g.event({pixelDelta: {y: -24}}).step, 1, 'new high-res gesture failed to accumulate');

for (const token of [
    'import "NoteRailWheel.js" as NoteRailWheel',
    'property var _noteRailWheelState: NoteRailWheel.idle()',
    'orientation: Qt.Vertical',
    'pixelDelta: event.pixelDelta',
    'angleDelta: event.angleDelta',
    'blocked: !!(event.modifiers',
    'root._noteRailWheelState = result.state',
    'event.accepted = result.accepted',
    'if (next >= 0 && next < root.tabCount)',
    'root.switchToTab(next)'
]) {
    checks++;
    assert.ok(qml.includes(token), 'NotepadWidget failed to route wheel safely: ' + token);
}
assert.ok(!qml.includes('(event.angleDelta.y < 0 ? 1 : -1)'), 'old one-event-per-note wheel is still active');
console.log('NOTE_RAIL_WHEEL_POLICY_PASS ' + checks + ' checks: wheel/pixel/Shift/phase/momentum/reversal/cooldown/boundaries and QML integration');
