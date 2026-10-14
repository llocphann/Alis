#!/usr/bin/env python3
"""QV4 exact shoulder strips, observable fallback, and owned host snapshots."""
import json, os, shutil, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def closing_brace(source, opening):
    depth, quote, comment, escaped = 0, None, None, False
    i = opening
    while i < len(source):
        c, following = source[i], source[i:i + 2]
        if comment == "line":
            if c == "\n": comment = None
        elif comment == "block":
            if following == "*/": comment = None; i += 1
        elif quote:
            if escaped: escaped = False
            elif c == "\\": escaped = True
            elif c == quote: quote = None
        elif following == "//": comment = "line"; i += 1
        elif following == "/*": comment = "block"; i += 1
        elif c in "\"'`": quote = c
        elif c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if not depth: return i
        i += 1
    raise AssertionError("unclosed sampler function")


def unprepared_reference(source):
    """Use the preserved scalar-read path with current intentional SDF rules."""
    private = source.index("function _popupShoulders(")
    opening = source.index("{", private)
    closing = closing_brace(source, opening)
    body = source[opening + 1:closing]
    guard = body.index("    if (numericSnapshot === true")
    fast_open = body.index("{", guard)
    fast_close = closing_brace(body, fast_open)
    slow_open = body.index("{", body.index("else", fast_close))
    slow_close = closing_brace(body, slow_open)
    body = body[:guard] + body[slow_open + 1:slow_close] + body[slow_close + 1:]
    public = source.index("function popupShoulders(")
    public_open = source.index("{", public)
    public_close = closing_brace(source, public_open)
    return source[:public_open + 1] + body + source[public_close:]


with tempfile.TemporaryDirectory(prefix="alis-shoulder-sampler-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    source = (ROOT / "modules/abyss/looks/AbyssGeometry.js").read_text()
    reference = unprepared_reference(source)
    (folder / "reference.js").write_text(reference)
    shutil.copy2(ROOT / "modules/abyss/looks/AbyssGeometry.js", folder / "candidate.js")
    # Imported scripts and QML have separate Math objects. Count operations in
    # test-only copies, leaving the numeric oracle and actual host uninstrumented.
    counter = """
var _samplerArithmeticCalls=0;
function _countedMin() { _samplerArithmeticCalls++;return Math.min.apply(Math,arguments); }
function arithmeticCount(snapshot,args) {
    _samplerArithmeticCalls=0;
    if(snapshot)popupShouldersSnapshot.apply(null,args);else popupShoulders.apply(null,args);
    return _samplerArithmeticCalls;
}
"""
    for kind, text in [("reference", reference), ("candidate", source)]:
        (folder / (kind + "-counted.js")).write_text(text.replace("Math.min(", "_countedMin(") + counter)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.looks
import "reference.js" as Reference
import "candidate.js" as Candidate
import "reference-counted.js" as ReferenceCounted
import "candidate-counted.js" as CandidateCounted
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
ShellRoot {
 id:root
 property string edge:"top"
 property real reveal:1
 property bool shown:true
 property int rowFields:0
 property int numericCases:0
 property int fallbackCases:0
 property int hostCases:0
 property int activeHostCases:0
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {
  id:controller;presentationItem:scene
  outputWidth:scene.width;outputHeight:scene.height
  edgeInsets:({left:8,top:8,right:8,bottom:8})
 }
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;width:1000;height:740
   Item {id:embedded;visible:false}
   AbyssBodyHost {
    id:host;anchors.fill:parent;identity:"snapshotOracle";controller:controller
    edge:root.edge;open:root.shown;externalProgress:root.reveal
    embeddedItem:embedded;includeEdgeConnection:true
    animatePlacementChanges:false;animatePresentation:false
    edgeInsets:controller.edgeInsets;span:320.5;depth:230.25;along:120.75
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function equalRows(a,b,label){
   check(a.length===b.length,label+" row count")
   for(let i=0;i<a.length;i++)for(const key of["x","y","width","height"]){
    root.rowFields++;check(Object.is(a[i][key],b[i][key]),label+" "+i+":"+key)
   }
  }
  function observe(module,mode){
   const trace=[];let count=0;const values={x:100.25,y:-50,width:240.5,height:210}
   const surface={}
   for(const key of["x","y","width","height"])Object.defineProperty(surface,key,{get(){trace.push(key);count++;if(mode>0 && count===mode)throw new TypeError("fixture getter "+key);return values[key]}})
   const record={get surface(){trace.push("surface");return surface},get radius(){trace.push("radius");return 29}}
   let result,error=null
   try{result=module.popupShoulders(800,600,{left:8,top:8,right:8,bottom:8},"top",record,34,24,29)}catch(e){error={name:e.name,message:e.message}}
   return {trace,result,error}
  }
  function run(){try{
   tryCompare(Config,"ready",true,5000);GlobalStates.deferredPanelsReady=true
   Config.setNestedValue("performance.reduceAnimations",true)
   check(Candidate.popupShoulders.length===Reference.popupShoulders.length,"public arity changed")
   let seed=12385931;function rnd(){seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed/4294967296}
   let firstCase=null
   for(const edge of["top","bottom","left","right"])for(const zero of[false,true])for(const k of[4,24,48,64])for(let i=0;i<35;i++){
    const w=480+rnd()*1800,h=320+rnd()*1000,ins={left:8,top:8,right:8,bottom:8};if(zero)ins[edge]=0
    const n=Reference.horizontal(edge)?w:h,along=i%3===0?0:i%3===1?n-150:40+rnd()*(n-200),p=[.01,.2,.7,1,1.025][i%5]
    const rec=Reference.panel(w,h,ins,edge,along,90+rnd()*600,20+rnd()*400,p,14,[],true);rec.radius=[0,12,29,64][i%4]
    const args=[w,h,ins,edge,rec,[0,12,34,68][i%4],k,29,{[edge]:zero}]
    equalRows(Reference.popupShoulders(...args),Candidate.popupShouldersSnapshot(...args),"numeric "+root.numericCases)
    root.numericCases++;if(!firstCase)firstCase=args
   }
   for(const mode of[0,1,2,3,4,5,10,20,100]){
    check(JSON.stringify(observe(Reference,mode))===JSON.stringify(observe(Candidate,mode)),"observable read/error phase "+mode);root.fallbackCases++
   }
   for(const change of[{radius:"29"},{radius:NaN},{radius:Infinity},{width:40000},{surfaceX:40000}]){
    const args=firstCase.slice(),record=Object.assign({},args[4],{surface:Object.assign({},args[4].surface)})
    if(change.radius!==undefined)record.radius=change.radius
    if(change.width!==undefined)args[0]=change.width
    if(change.surfaceX!==undefined)record.surface.x=change.surfaceX
    args[4]=record;equalRows(Reference.popupShoulders(...args),Candidate.popupShouldersSnapshot(...args),"numeric fallback");root.fallbackCases++
   }
   check(Candidate.popupShouldersSnapshot(...firstCase)!==Candidate.popupShouldersSnapshot(...firstCase),"sampler retains a shared mutable strip array")
   // The optimized path must do less preparation work; output equality alone
   // would also pass if the caller silently reverted to the unprepared branch.
   const slow=ReferenceCounted.arithmeticCount(false,firstCase)
   const fast=CandidateCounted.arithmeticCount(true,firstCase)
   check(fast<slow,"snapshot path does not reduce invariant arithmetic "+fast+"/"+slow)
   for(const edge of["top","bottom","left","right"])for(const zero of[false,true])for(const progress of[.02,.3,.75,1]){
    root.edge=edge;root.reveal=progress
    controller.edgeInsets={left:8,top:8,right:8,bottom:8,[edge]:zero?0:8}
    controller.cornerWidthInsets=controller.edgeInsets
    controller.roundZeroCorners={[edge]:zero}
    wait(20)
    const rect=host.rawPresentationRecord.surface
    for(const key of["x","y","width","height"]){const d=Object.getOwnPropertyDescriptor(rect,key);check(d && !d.get && typeof d.value==="number","host does not own plain numeric "+key)}
    // A collapsed content box does not own native input, even if the SDF has
    // begun to paint a reveal shoulder. Compare only eligible mask production.
    const active=host.inputBounds.width>0 && host.inputBounds.height>0
    if(active)root.activeHostCases++
    const expected=active
     ? Geometry.popupShoulders(host.width,host.height,host.connectionInsets,host.edge,
       host.rawPresentationRecord,AbyssStyle.perimeterRadius,AbyssStyle.connectionDepth,AbyssStyle.neckRadius,
       controller.roundZeroCorners,controller.cornerWidthInsets) : []
    equalRows(expected,host.connectionRects,"actual host "+root.hostCases);root.hostCases++
   }
   check(root.activeHostCases===24,"host fixture missed non-collapsed snapshot cases")
   root.shown=false;wait(40)
   check(host.connectionRects.length===0 && host.connectionRegions.length===0,"closed host retains a shoulder cohort")
   root.shown=true;root.reveal=1;wait(40)
   check(host.connectionRects.length>0,"reopened host did not restore its strip cohort")
   console.info("SHOULDER_SAMPLER_NATIVE_PASS",JSON.stringify({numericCases:root.numericCases,fallbackCases:root.fallbackCases,hostCases:root.hostCases,activeHostCases:root.activeHostCases,rowFields:root.rowFields,arithmetic:{slow,fast}}))
  }catch(e){console.error("SHOULDER_SAMPLER_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None: raise SystemExit("SKIP: host sampler requires private Niri")
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["abyss"]["companion"]["enabled"] = False
        (config / "config.json").write_text(json.dumps(data))
        result = run_qs(folder, env, 80)
        if os.environ.get("ALIS_SHOULDER_SAMPLER_LOG"):
            Path(os.environ["ALIS_SHOULDER_SAMPLER_LOG"]).write_text(result.stdout)
        if result.returncode or "SHOULDER_SAMPLER_NATIVE_PASS" not in result.stdout or any(
            s in result.stdout for s in ["SHOULDER_SAMPLER_NATIVE_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration"]
        ):
            print(result.stdout)
            raise SystemExit(1)
        print(next(line for line in result.stdout.splitlines() if "SHOULDER_SAMPLER_NATIVE_PASS" in line))
