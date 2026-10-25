#!/usr/bin/env python3
"""Qualify the actual finite wave solver, including corners and sleep."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
program = (root / "modules/abyss/looks/AbyssWave.js").read_text() + r"""
const assert=require('node:assert/strict');
assert.equal(travelEnvelope(0,1000),1);
let envelope=1;
for(let distance=1;distance<=1000;distance++) {
 const next=travelEnvelope(distance,1000);
 assert(next<envelope,'traveling crest attenuates continuously from its source');
 envelope=next;
}
assert.equal(envelope,0);assert.equal(travelEnvelope(1500,1000),0);
assert.equal(travelEnvelope(NaN,1000),0);assert.equal(travelEnvelope(2,0),0);
assert(travelEnvelope(100,1000)<.8,'attenuation is visible well before the end of travel');

// Mechanical fixtures have explicit settings; named preset tuning is checked
// independently below and must not silently change this stress workload.
const p=parameters({preset:'custom',...customDefaults});
assert.equal(bodyStrength({small:.4,large:1.7,dock:.3,notifications:.2}),1.7);
assert.equal(bodyStrength({strength:2,large:4}),2);
assert.equal(arc('top',100,1920,1200),100);
assert.equal(arc('right',100,1920,1200),2020);
assert.equal(arc('bottom',100,1920,1200),4940);
assert.equal(arc('left',100,1920,1200),6140);
let s=create(256,1920,1200,p);
assert.equal(s.mode,'SLEEPING');assert.equal(advance(s,.016),false);
impulse(s,'top',40,70,1,1);
assert.equal(s.mode,'ACTIVE');
let crossed=false,rebound=false,spread=false;
for(let i=0;i<1600;i++) {
    advance(s,1/120);
    crossed ||= s.displacement[255]>.05;
    spread ||= Math.abs(s.displacement[12])>.02;
    rebound ||= s.displacement.some(v=>v<-.03);
    assert(s.displacement.every(Number.isFinite));
}
assert(crossed,'corner wrap transmits to left edge');
assert(spread,'neighbor coupling moves energy beyond the impulse');
assert(rebound,'physical restoring spring reverses displacement');
assert.equal(s.mode,'SLEEPING');assert(s.displacement.every(v=>v===0));
const steps=s.steps;advance(s,.05);assert.equal(s.steps,steps,'sleep does no integration');
impulse(s,'bottom',900,400,-1,4);assert(s.velocity.some(v=>v<0),'close reverses the impulse');
for(const preset of Object.keys(presets)) for(const [w,h] of [[1920,1200],[480,320]]) {
    s=create(256,w,h,parameters({preset}));
    setMass(s,[{edge:'top',along:20,span:w*.7,mass:4,progress:1}]);
    assert(Math.max(...s.mass)>3);
    for(let i=0;i<10;i++) impulse(s,'top',w*.5,w*.4,1,4);
    for(let i=0;i<2400;i++) {
        advance(s,1/120);
        assert(s.displacement.every(v=>Number.isFinite(v)&&Math.abs(v)<=heightLimit(s)+.001));
        assert(s.velocity.every(Number.isFinite));
    }
    assert.equal(s.mode,'SLEEPING',preset+' eventually sleeps under heavy mass');
}
let peaks=[];
for(const preset of Object.keys(presets)) {
    let sample=create(256,1920,1200,parameters({preset})),peak=0;
    impulse(sample,'top',960,160,1,1);
    for(let i=0;i<360;i++) { advance(sample,1/120);peak=Math.max(peak,...sample.displacement.map(Math.abs)); }
    peaks.push(peak);
}
assert(peaks.every((peak,i)=>i===0 || peak>peaks[i-1]*1.2),'restrained presets retain distinct, increasing wave heights');
const custom=parameters({preset:'custom',amplitude:9,decay:-1});
assert.equal(custom.amplitude,4);assert.equal(custom.decay,0);
const travelParameters=parameters({preset:'deep'});
let touring=create(256,1280,720,travelParameters),peaksByEdge=[0,0,0,0];
assert(travel(touring,'top',640,400,1,1));
assert.equal(touring.traveling.length,2,'a popup emits in both directions');
advance(touring,.05);
assert(touring.traveling[0].center<640 && touring.traveling[1].center>640,'packets depart in opposite directions');
for(let frame=0;frame<1800;frame++) {
    advance(touring,1/120);
    touring.displacement.forEach((v,i)=>{
        const location=i*touring.length/touring.count;
        const edge=location<1280 ? 0 : location<2000 ? 1 : location<3280 ? 2 : 3;
        peaksByEdge[edge]=Math.max(peaksByEdge[edge],Math.abs(v));
        assert(Number.isFinite(v) && Math.abs(v)<=heightLimit(touring)+.001);
    });
}
assert(peaksByEdge.every(peak=>peak>2),'popup waves visibly reach all four Screen Edges');
assert.equal(touring.mode,'SLEEPING');assert.equal(touring.traveling.length,0);
assert(touring.travelTargets.every(v=>v===0),'expired packets release their drive targets');
const sleepingSteps=touring.steps;advance(touring,.05);assert.equal(touring.steps,sleepingSteps);
const canceling=create(256,1280,720,travelParameters);
travel(canceling,'top',640,400,.1,1);travel(canceling,'top',640,400,-.1,1);
for(let frame=0;frame<80;frame++) advance(canceling,1/120);
assert(canceling.displacement.every(v=>Math.abs(v)<1e-9),'opposite signed waves interfere in the same physical string');
const single=create(256,1280,720,travelParameters),reinforced=create(256,1280,720,travelParameters);
travel(single,'top',640,400,.1,1);travel(reinforced,'top',640,400,.1,1);travel(reinforced,'top',640,400,.1,1);
for(let frame=0;frame<80;frame++) { advance(single,1/120);advance(reinforced,1/120); }
assert(Math.max(...reinforced.displacement.map(Math.abs))>Math.max(...single.displacement.map(Math.abs))*1.9,'same signed waves reinforce each other');
for(let i=0;i<40;i++) travel(touring,'bottom',640,400,4,6);
assert.equal(touring.traveling.length,16,'popup storms keep a fixed packet budget');
clearTravel(touring);assert.equal(touring.traveling.length,0);
assert(!travel(create(128,1280,720,parameters({popupTravel:false})),'top',640,400,1,1),'travel option disables emission');
assert(!travel(touring,'top',Infinity,400,1,1),'malformed coordinates cannot poison the solver');
const malformedMass=create(128,1280,720,travelParameters);
travel(malformedMass,'top',640,400,1,'invalid');advance(malformedMass,.05);
assert(malformedMass.displacement.every(Number.isFinite),'malformed mass falls back to a finite popup weight');
s=create(256,1920,1200,p);
const raw=Array.from({length:64},(_,i)=>[20,70,40,95,30,50,80,10][i%8]),rawBefore=JSON.stringify(raw);
assert(spectrum(s,['top'],raw,100,.8));
const weaker=create(256,1920,1200,p),stronger=create(256,1920,1200,p);
spectrum(weaker,['top'],[1,4,2,5,1,2,3,1],100,1);
spectrum(stronger,['top'],[1,4,2,5,1,2,3,1],100,4);
assert(Math.max(...stronger.spectrumTargets.map(Math.abs))>Math.max(...weaker.spectrumTargets.map(Math.abs))*2,'strength above 100 percent still boosts quiet audio');
assert(s.spectrumTargets.some(v=>v>1) && s.spectrumTargets.some(v=>v<-1),'spectrum is a signed continuous wave');
assert(s.spectrumTargets.every((v,i)=>i*s.length/s.count<=s.width || v===0),'only the selected edge is driven');
assert.equal(JSON.stringify(raw),rawBefore,'shared analyzer frames are never mutated');
const stationaryA=create(256,1920,1200,p),stationaryB=create(256,1920,1200,p);
spectrum(stationaryA,['top'],Array.from({length:64},(_,i)=>i%2===0?95:15),100,1);
spectrum(stationaryB,['top'],Array.from({length:64},(_,i)=>i%2===0?25:85),100,1);
projectCrests(stationaryA,false);projectCrests(stationaryB,false);
const localPeaks=arr=>arr.map((v,i)=>v>1&&v>=arr[(i+arr.length-1)%arr.length]&&v>=arr[(i+1)%arr.length]?i:-1).filter(i=>i>=0);
assert.deepEqual(localPeaks(stationaryA.crests),localPeaks(stationaryB.crests),'audio wave crests stay at fixed horizontal positions and only rise/fall vertically');
for(let i=0;i<1600;i++) advance(s,1/120);
assert.equal(s.mode,'SLEEPING','stationary spectrum can settle without continuous integration');
assert.equal(s.steps,0,'audio presentation never starts the interaction solver');
assert(projectCrests(s,false)>1,'audio has a crest in its first presented frame');
assert(s.spectrumTargets.some(v=>Math.abs(v)>.1),'audio keeps its direct response shape');
const audioSteps=s.steps;advance(s,.05);assert.equal(s.steps,audioSteps);
assert.equal(spectrum(s,['top'],raw,100,.8),false,'identical audio does not wake the field');
assert(spectrum(s,['left'],raw,100,.8),'edge changes wake and release old targets');
assert(spectrum(s,[],[],100,0),'pause clears audio targets');
for(let i=0;i<1600;i++) advance(s,1/120);
assert.equal(s.mode,'SLEEPING');assert(s.displacement.every(v=>v===0),'pause restores exact flat rest');
for(const bad of [[Infinity,-2,NaN],[0,0,0],[]]) {
    spectrum(s,['top','right','bottom','left'],bad,NaN,100);
    for(let i=0;i<240;i++) advance(s,1/120);
    assert(s.displacement.every(v=>Number.isFinite(v) && Math.abs(v)<=heightLimit(s)+.001),'malformed and extreme audio stays bounded');
}

const visual=create(256,1920,1200,parameters({preset:'custom',amplitude:4,propagation:1,speed:.3,decay:.6,tension:.15,viscosity:.45,rebound:.9,corner:1}));
for(let i=0;i<visual.count;i++) {
    visual.displacement[i]=80*Math.exp(-Math.pow((i-80)/5,2))-40*Math.exp(-Math.pow((i-150)/8,2));
    visual.velocity[i]=180;
}
const signedBefore=JSON.stringify(visual.displacement),stepsBefore=visual.steps;
projectCrests(visual,true);
assert.equal(JSON.stringify(visual.displacement),signedBefore,'crest projection does not change signed interference');
assert.equal(visual.steps,stepsBefore,'projection does not integrate or wake the solver');
assert(visual.crests.every(v=>Number.isFinite(v)&&v>=0&&v<=192),'visual crests remain positive and bounded');
assert.equal(visual.crests[150],0,'negative trough does not erode the resting Edge');
assert(visual.crestPeak>80,'broad crests rise higher without raising physical energy');
const rawHalf=visual.displacement.filter(v=>v>40).length;
const visualHalf=visual.crests.filter(v=>v>visual.crestPeak*.5).length;
assert(visualHalf<rawHalf,'taller crest has narrower half-height shoulders');
assert(visual.whitewater.some(v=>v>.01),'moving steep crest produces whitewater');
projectCrests(visual,false);assert(visual.whitewater.every(v=>v===0),'disabled effects have no foam');
visual.parameters.whitewater=0;projectCrests(visual,true);
assert(visual.whitewater.every(v=>v===0),'zero whitewater setting removes the breaker');
visual.displacement.fill(0);visual.velocity.fill(0);projectCrests(visual,true);
assert.equal(visual.crestPeak,0);assert(visual.whitewater.every(v=>v===0),'flat rest has no crest or residual whitewater');
visual.displacement[80]=heightLimit(visual);projectCrests(visual,true);
assert(visual.crestPeak<visual.displacement[80] && visual.crests[79]>0 && visual.crests[81]>0,'single-sample needle is rounded into bounded shoulders');
console.log('PASS: signed interference, finite stability/sleep, compact positive crests and bounded crest-only whitewater');

"""
result = subprocess.run(["node","-e",program],cwd=root)
if result.returncode:
    raise SystemExit(result.returncode)
raise SystemExit(subprocess.run(["node",str(root / "scripts/test-abyss-wave-interaction-parity.cjs")],cwd=root).returncode)
