#!/usr/bin/env node
// This regression executes the actual QML wave lifecycle logic with a small
// solver spy. Native Niri frame timings and shader parity are separate gates.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {dirname,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const source=readFileSync(resolve(root,'modules/abyss/AbyssWaveController.qml'),'utf8');
const controller=readFileSync(resolve(root,'modules/abyss/AbyssSurfaceController.qml'),'utf8');
assert.ok(controller.includes('records: integrationAllowed ? root.records : []'),
    'dormant solver must not observe 60 FPS presentation geometry');
function method(name) {
    const signature='function '+name+'(): void {';
    const start=source.indexOf(signature);
    assert.ok(start>=0,'missing '+name);
    const brace=source.indexOf('{',start);
    let depth=0;
    for(let i=brace;i<source.length;i++) {
        if(source[i]==='{') depth++;
        if(source[i]==='}' && --depth===0)
            return source.slice(brace+1,i);
    }
    throw Error('unterminated '+name);
}
function handler(name,next) {
    const start=source.indexOf(name+': {');
    assert.ok(start>=0,'missing handler '+name);
    const brace=source.indexOf('{',start);
    let depth=0;
    for(let i=brace;i<source.length;i++) {
        if(source[i]==='{') depth++;
        if(source[i]==='}' && --depth===0)
            return source.slice(brace+1,i);
    }
    throw Error('unterminated '+name);
}
const recordHandler=source.match(/onRecordsChanged:\s*if \(simulation && integrationAllowed\)\s*Wave\.setMassCached\(simulation,records,massKernels\)/);
assert.ok(recordHandler,'record changes must not recalculate when waves disabled');
const wave={};
const events={creates:0,masses:[],revisions:0};
const Wave={
    create(count,w,h,params) {
        events.creates++;
        return {count,w,h,params,mass:[]};
    },
    setMassCached(simulation,records,cache) {
        events.masses.push(records.map(r=>r.id));
        simulation.mass=records.map(r=>r.id);
    }
};
const ctx={sampleCount:256,outputWidth:1920,outputHeight:1200,
    parameters:{},records:[{id:'initial'}],massKernels:new Map(),
    simulation:null,integrationAllowed:false,crestPeak:0,mode:'ACTIVE',
    revision:0,configurationChanged(){}};
const reset=new Function('Wave','ctx',
    'with(ctx) {'+method('reset')+';'+
    'ctx.massKernels=massKernels;ctx.simulation=simulation;'+
    'ctx.crestPeak=crestPeak;ctx.mode=mode;ctx.revision=revision;}');
const change=new Function('Wave','ctx',
    'with(ctx) { '+recordHandler[0].replace(/^onRecordsChanged:\s*/, '')+'; }');
const integration=new Function('Wave','ctx','reset',
    'with(ctx) {'+handler('onIntegrationAllowedChanged')+';'+
    'ctx.massKernels=massKernels;ctx.simulation=simulation;'+
    'ctx.crestPeak=crestPeak;ctx.mode=mode;ctx.revision=revision;}');
const disabledMassCount=()=>events.masses.length;
reset(Wave,ctx);
assert.equal(events.masses.length,0,'disabled solver does no reset mass scan');
for(let i=0;i<120;i++){
    ctx.records=[{id:'recording-'+i},{id:'notification-'+i}];
    change(Wave,ctx);
}
assert.equal(events.masses.length,0,'120 animated geometry frames avoided mass scans');
ctx.integrationAllowed=true;
integration(Wave,ctx,()=>reset(Wave,ctx));
assert.deepEqual(events.masses.at(-1),['recording-119','notification-119'],
    'enabling Waves must load newest geometry before next impulse');
assert.equal(events.masses.length,1);
ctx.records=[{id:'recording-active'}];
change(Wave,ctx);
assert.deepEqual(events.masses.at(-1),['recording-active'],
    'enabled Waves still receive live geometry');
ctx.integrationAllowed=false;
integration(Wave,ctx,()=>reset(Wave,ctx));
assert.equal(events.masses.length,2,'disabling solver resets without mass refresh');
ctx.records=[{id:'recording-hidden'}];
change(Wave,ctx);
assert.equal(events.masses.length,2);
ctx.integrationAllowed=true;
integration(Wave,ctx,()=>reset(Wave,ctx));
assert.deepEqual(events.masses.at(-1),['recording-hidden'],
    'reenabled Waves use latest geometry even when record updates were skipped');
assert.equal(events.masses.length,3);
console.log('PASS: inactive Wave mass scans skipped; enabled/re-enabled geometry identical at lifecycle handoff');
