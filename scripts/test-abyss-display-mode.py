#!/usr/bin/env python3
"""Exercise display-mode planning without touching real outputs."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
program = (root / "services/DisplayModePlan.js").read_text() + r"""
const assert=require('node:assert/strict');

const names=['eDP-1','DP-1','HDMI-A-1'];
let p=plan('extend',names,'eDP-1','','','');
assert.equal(p.ok,true);
assert.deepEqual(p.targets,names);
assert.deepEqual(p.actions.map(a=>a.power),['on','on','on']);

p=plan('primary-only',names,'eDP-1','','','');
assert.deepEqual(p.targets,['eDP-1']);
assert.deepEqual(p.actions,[
 {output:'eDP-1',power:'on'},
 {output:'DP-1',power:'off'},
 {output:'HDMI-A-1',power:'off'}
], 'target is enabled before any other output is disabled');

p=plan('second-only',names,'eDP-1','DP-1','','');
assert.deepEqual(p.targets,['DP-1']);
assert.equal(p.actions[0].output,'DP-1');
assert.equal(p.actions[0].power,'on');
assert(p.actions.slice(1).every(a=>a.power==='off'));

p=plan('mirror',names,'eDP-1','','eDP-1','HDMI-A-1');
assert.deepEqual(p.targets,['eDP-1','HDMI-A-1']);
assert.deepEqual(p.mirror,{source:'eDP-1',target:'HDMI-A-1'});
assert.deepEqual(p.actions.slice(0,2),[
 {output:'eDP-1',power:'on'},
 {output:'HDMI-A-1',power:'on'}
]);
assert.deepEqual(p.actions[2],{output:'DP-1',power:'off'});

assert.equal(plan('second-only',names,'eDP-1','eDP-1','','').ok,false);
assert.equal(plan('mirror',names,'eDP-1','','DP-1','DP-1').ok,false);
assert.equal(plan('bogus',names,'eDP-1','','','').ok,false);

const restored=restore(names,['DP-1','HDMI-A-1'],'eDP-1');
assert.deepEqual(restored.actions.slice(0,2),[
 {output:'DP-1',power:'on'},
 {output:'HDMI-A-1',power:'on'}
], 'rollback enables the old active set before disabling anything');
assert.deepEqual(restored.actions[2],{output:'eDP-1',power:'off'});

const fallback=restore(names,[],'eDP-1');
assert.deepEqual(fallback.targets,['eDP-1'], 'rollback never intentionally leaves every output off');

assert.deepEqual(activeNames({
 'eDP-1':{logical:{x:0,y:0}},
 'DP-1':{logical:null},
 'HDMI-A-1':{logical:{x:1920,y:0}}
}),['HDMI-A-1','eDP-1']);

// Hotplug must be evaluated against the pair actually launched, even when
// the UI would normalize a missing source/target to another connected screen.
const runningPair={source:'eDP-1',target:'HDMI-A-1'};
assert.equal(mirrorPairConnected(names,runningPair),true);
assert.equal(mirrorPairConnected(['eDP-1','DP-1'],runningPair),false);
assert.equal(mirrorPairConnected(['HDMI-A-1','DP-1'],runningPair),false);
assert.equal(mirrorPairConnected([],runningPair),false);
assert.equal(mirrorPairConnected(names,{source:'DP-1',target:'DP-1'}),false);
assert.equal(mirrorPairConnected(names,null),false);
assert.equal(mirrorPairConnected(['eDP-1','DP-1'],{source:'eDP-1',target:'DP-1'}),true);
assert.equal(mirrorPairConnected(names,{source:'',target:'DP-1'}),false);

assert.equal(mirrorRunningMessage({source:'DP-1',target:'HDMI-A-1'}),'Mirroring DP-1 to HDMI-A-1.');
assert.equal(mirrorRunningMessage(null),'');
assert.equal(mirrorStoppedMessage(true,true),'Display mirror stopped.',
    'explicit Stop must confirm the active mirror ended');
assert.equal(mirrorStoppedMessage(true,false),'',
    'internal replacement and hotplug stop retain their own status');
assert.equal(mirrorStoppedMessage(false,false),'Display mirror stopped.',
    'unexpected process exit reports a stopped session');

const original=JSON.stringify(names);
plan('extend',names,'eDP-1','','','');
assert.equal(JSON.stringify(names),original,'planner does not mutate caller output lists');
console.log('PASS: display-mode planning, safe rollback and running-mirror hotplug identity');
"""
subprocess.run(["node", "-e", program], cwd=root, check=True)
