import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const policy = vm.createContext({});
vm.runInContext(readFileSync(new URL('../modules/dashboard/DashboardPagePolicy.js', import.meta.url), 'utf8'), policy);
let checks = 0;
function eq(a, b, message) { checks++; assert.deepEqual(JSON.parse(JSON.stringify(a)), b, message); }
function permutations(ids) {
    return ids.length ? ids.flatMap((id, i) => permutations(ids.filter((_, n) => n !== i)).map(rest => [id, ...rest])) : [[]];
}
function gesture(ids, currentId) {
    let state = policy.idle(), page = currentId, time = 1000;
    return {
        step(x, y = 0, phase = 0, delay = 10, inner = false) {
            const saved = JSON.stringify(state);
            const result = policy.advance(state, {x, y}, phase, time += delay, ids, page, inner);
            eq(JSON.stringify(state), saved, 'caller gesture state mutated');
            state = result.state;
            if (result.target) page = result.target;
            return result;
        },
        page() { return page; }
    };
}
for (const ids of [...permutations(['dashboard', 'music']), ...permutations(['dashboard', 'music', 'weeklyPlanner'])]) {
    const saved = ['unknown', ids[0], ids[0], ...ids.slice(1)];
    eq(policy.ordered(saved, ids), ids, 'persisted stable order lost');
    eq(saved, ['unknown', ids[0], ids[0], ...ids.slice(1)], 'saved order mutated');
    for (let at = 0; at < ids.length; at++) {
        for (const [x, y] of [[0, 120], [0, -120], [8, 9], [-8, -9], [8, 8], [-8, 8], [NaN, 0], [Infinity, 0]]) {
            const g = gesture(ids, ids[at]);
            const r = g.step(x, y);
            eq([r.accepted, r.target, g.page()], [false, '', ids[at]], 'vertical/diagonal/invalid motion changed page');
        }
        for (const direction of [-1, 1]) {
            const g = gesture(ids, ids[at]), next = at + direction;
            const valid = next >= 0 && next < ids.length;
            eq(g.step(-direction * 31).target, '', 'sub-threshold motion changed page');
            eq(g.step(-direction).target, valid ? ids[next] : '', 'threshold/boundary target wrong');
            eq(g.page(), valid ? ids[next] : ids[at]);
            eq(g.step(-direction * 320).target, '', 'single burst skipped another page');
            if (valid) eq(g.step(direction * 32).target, ids[at], 'fast reversal failed');
        }
    }
    const phased = gesture(ids, ids[0]);
    phased.step(0, 0, 1);
    for (let tick = 0; tick < 12; tick++) {
        const r = phased.step(-8, 0, 2);
        eq(r.target, tick === 3 ? ids[1] : '', 'high-resolution phased burst skipped pages');
    }
    eq(phased.step(-120, 0, 4, 16000).target, '', 'momentum/long phased pause released latch');
    phased.step(0, 0, 3);
    if (ids.length === 3) eq(phased.step(-32, 0, 1).target, ids[2], 'new phased gesture did not release latch');
}
const ids = ['dashboard', 'music', 'weeklyPlanner'];
const burst = gesture(ids, 'dashboard');
eq(burst.step(-32).target, 'music');
eq(burst.step(-32, 0, 0, 180).target, '', 'idle boundary released burst too soon');
eq(burst.step(-32, 0, 0, 181).target, 'weeklyPlanner', 'new unphased burst stayed blocked');
const interrupted = gesture(ids, 'dashboard');
interrupted.step(-24); interrupted.step(0, 100);
eq(interrupted.step(-8).target, '', 'vertical interruption retained partial distance');
eq(interrupted.step(-24).target, 'music');
const content = gesture(ids, 'music');
content.step(-8, 0, 2, 10, true);
eq(content.step(-120, 0, 2).target, '', 'inner browser burst navigated after its edge');
eq(content.step(32, 0, 2).target, 'dashboard', 'inner browser latch blocked reversal');
eq(policy.delta({pixelDelta:{x:0,y:10},angleDelta:{x:120,y:0}}), {x:0,y:10}, 'pixel vertical signal became horizontal');
eq(policy.delta({pixelDelta:{x:-3.5,y:1},angleDelta:{x:-120,y:0}}), {x:-3.5,y:1});
eq(policy.delta({angleDelta:{x:120,y:-60}}), {x:40,y:-20});
eq(policy.ordered(['music','unknown','dashboard','weeklyPlanner'], ['dashboard']), ['dashboard'], 'disabled page remained active');
eq(policy.ordered(undefined, ['dashboard','music']), ['dashboard','music'], 'legacy config lacked defaults');
console.log(`DASHBOARD_PAGE_POLICY_PASS ${checks} checks; stable/reordered two and three pages, thresholds, vertical/diagonal, bursts, phases, reversal, inner-browser ownership`);
