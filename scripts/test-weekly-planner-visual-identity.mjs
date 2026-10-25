#!/usr/bin/env node
// View-only collision recovery applies equally to saved, mixed and reloaded data.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=process.env.ALIS_PLANNER_SOURCE_ROOT || path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const policy=vm.createContext({Math,Number,String,JSON,Object,Map,Set,Array});
vm.runInContext(fs.readFileSync(path.join(root,'modules/dashboard/PlannerEventPalette.js'),'utf8'),policy);
const key=(event,source='local')=>policy.identity ? policy.identity(event,source) : JSON.stringify([source,event.id ?? event.uid]);
const assign=(local,external=[])=>policy.assignPositions ? policy.assignPositions(local,external)
 : Object.fromEntries(local.map(event=>[key(event),policy.paletteSlot(event,'local',8)/7]));
const collisions=Array.from({length:64},(_,i)=>({id:1+8*i,title:'Class '+i,recurrence:'weekly',
 occurrences:[{startDate:'2032-10-19T09:00:00Z',owner:{keep:i}}],unknown:{keep:true}}));
const original=JSON.stringify(collisions);
const positions=assign(collisions);
assert.equal(new Set(collisions.map(event=>positions[key(event)])).size,64,
 'distinct Event IDs separated by eight must not reuse the same gradient position');
assert.ok(Object.values(positions).every(value=>value>=0 && value<=1));
for(const event of collisions)assert.equal(assign([event])[key(event)],positions[key(event)],
 'deleting/filtering other Events must not change a surviving Event color');
assert.deepEqual(JSON.parse(JSON.stringify(assign(collisions.slice().reverse()))),JSON.parse(JSON.stringify(positions)),
 'storage sorting must not reshuffle identity colors');
const edited=JSON.parse(original);edited[2].title='Renamed';edited[2].occurrences[0].startDate='2033-01-02T09:00:00Z';
assert.deepEqual(JSON.parse(JSON.stringify(assign(edited))),JSON.parse(JSON.stringify(positions)),
 'renaming/dragging a saved occurrence must not change its Event color');
assert.deepEqual(JSON.parse(JSON.stringify(assign(JSON.parse(original)))),JSON.parse(JSON.stringify(positions)));
const consecutive=Array.from({length:8},(_,i)=>({id:i+1}));
const normal=assign(consecutive);
assert.equal(new Set(consecutive.map(event=>normal[key(event)])).size,8);
for(const event of consecutive)assert.equal(normal[key(event)],policy.position(event,'local'),
 'inventory and direct rendering must use the same stable position');
const large=[0,4294967295,4294967296,4294967297,Number.MAX_SAFE_INTEGER-1,Number.MAX_SAFE_INTEGER];
assert.equal(new Set(large.map(id=>policy.position({id},'local'))).size,large.length,
 'large legacy IDs must not be truncated to a 32-bit identity');
assert.deepEqual(Object.keys(assign([])),[]);
const old=collisions.slice(0,4),oldPositions=assign(old);
const newMixed=assign(old.concat([{id:32,title:'New Event'},{id:33,title:'New Event'}]));
for(const event of old)assert.equal(newMixed[key(event)],oldPositions[key(event)],
 'new monotonic local Event IDs must not steal an older identity color');
const externals=[{uid:'outside-1',sourceColor:'#aabbcc'},{uid:'outside-2',sourceColor:'#aabbcc'}];
const mixed=assign(collisions,externals);
assert.notEqual(mixed[key(externals[0],'external')],mixed[key(externals[1],'external')]);
assert.deepEqual(JSON.parse(JSON.stringify(assign(Object.assign({length:collisions.length},collisions)))),JSON.parse(JSON.stringify(positions)),
 'read-only Qt sequence views must have the same identity cache');
assert.equal(JSON.stringify(collisions),original,'view assignment must not rewrite persisted records');
console.log('PLANNER_VISUAL_IDENTITY_PASS: 64 formerly colliding IDs, add/delete/filter/reorder/rename/drag/reload, legacy API and large IDs');
