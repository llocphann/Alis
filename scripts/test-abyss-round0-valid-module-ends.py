#!/usr/bin/env python3
"""Actual editor drafts/module backings/GPU: independently inspect both contact endpoints."""
import argparse
import json
import math
from pathlib import Path
import tempfile

from PIL import Image, ImageChops
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, help="retain PNGs, metadata and raw native log")
args = parser.parse_args()


def endpoint_checks(case, folder):
    with Image.open(folder / (case["label"] + "-off.png")) as image:
        off = image.convert("RGBA")
    with Image.open(folder / (case["label"] + "-on.png")) as image:
        on = image.convert("RGBA")
    assert off.size == on.size
    width, height = case["width"], case["height"]
    sx, sy = on.width / width, on.height / height
    edge = case["edge"]
    horizontal = edge in {"top", "bottom"}
    checked = 0
    for record in case["records"]:
        box, foreground = record["surface"], record["content"]
        start = box["x"] if horizontal else box["y"]
        span = box["width"] if horizontal else box["height"]
        expected_start = foreground["x"] if horizontal else foreground["y"]
        expected_span = foreground["width"] if horizontal else foreground["height"]
        extent = width if horizontal else height
        if case.get("joined"):
            if case["weldEnd"] == "start":
                assert abs(start+50) < .01, "start weld did not cross physical boundary"
                assert abs(start+span-expected_start-expected_span-8) < .01
            else:
                assert abs(start-expected_start+8) < .01
                assert abs(start+span-extent-50) < .01, "end weld did not cross physical boundary"
        else:
            assert abs(start - expected_start + 8) < .01, "backing start lost its actual module"
            assert abs(span - expected_span - 16) < .01, "backing end lost its actual module"
        depth = (box["y"] + box["height"] if edge == "top" else height - box["y"] if edge == "bottom"
                 else box["x"] + box["width"] if edge == "left" else width - box["x"])
        body_rounding = min(record.get("radius", case["bodyRadius"]), box["width"] / 2, box["height"] / 2)
        radius = min(case["curvature"], span / 2, depth - body_rounding)
        assert radius > 4, "fixture did not create a valid exposed contact"
        for end in ("upper-or-start", "lower-or-end"):
            endpoint = start if end == "upper-or-start" else start + span
            if endpoint <= 0 or endpoint >= extent:
                # Corner welds deliberately place one tangent endpoint outside
                # the viewport. A missing offscreen curve is not a regression.
                assert case.get("joinComparison"), "centered control unexpectedly crossed the viewport"
                continue
            first = endpoint - radius if end == "upper-or-start" else endpoint
            last = endpoint if end == "upper-or-start" else endpoint + radius
            if horizontal:
                roi = (first, 0 if edge == "top" else height-radius,
                       last, radius if edge == "top" else height)
            else:
                roi = (0 if edge == "left" else width-radius, first,
                       radius if edge == "left" else width, last)
            pixel_roi = (max(0, math.floor(roi[0]*sx)), max(0, math.floor(roi[1]*sy)),
                         min(on.width, math.ceil(roi[2]*sx)), min(on.height, math.ceil(roi[3]*sy)))
            positive = negative = 0
            # Independent circle/rectangle oracle, never Geometry.distance() or
            # popupShoulders(): a common defect there cannot make this PASS.
            for py in range(pixel_roi[1], pixel_roi[3]):
                for px in range(pixel_roi[0], pixel_roi[2]):
                    x, y = (px+.5)/sx, (py+.5)/sy
                    tangent = x if horizontal else y
                    normal = y if edge == "top" else height-y if edge == "bottom" else x if edge == "left" else width-x
                    gap = endpoint-tangent if end == "upper-or-start" else tangent-endpoint
                    q = radius-gap
                    if not (gap > 1 and q > 1 and 1 < normal < radius-1):
                        continue
                    circle_distance = math.hypot(q, normal-radius)-radius
                    if circle_distance > 1:
                        assert off.getpixel((px, py))[3] == 0, (case["label"], end, "control pixel already painted", px, py)
                        assert on.getpixel((px, py))[3] >= 240, (case["label"], end, "valid rounded endpoint missing", px, py)
                        positive += 1
                    elif circle_distance < -2:
                        assert on.getpixel((px, py))[3] == 0, (case["label"], end, "contact protrudes past tangent circle", px, py)
                        negative += 1
            assert positive > 0 and negative > 0, (case["label"], end, "endpoint ROI lacked independent probes")
            checked += 1
    return checked


def weld_checks(cases, folder):
    groups = {}
    for case in cases:
        if case.get("joinComparison"):
            groups.setdefault(case["joinComparison"], {})[case["joined"]] = case
    assert len(groups) == 4, "reported Launcher/Battery weld controls incomplete"
    for controls in groups.values():
        plain, joined = controls[False], controls[True]
        assert plain["records"][0]["content"] == joined["records"][0]["content"], "weld moved the real feature"
        with Image.open(folder/(plain["label"]+"-on.png")) as image:
            before = image.convert("RGBA")
        with Image.open(folder/(joined["label"]+"-on.png")) as image:
            after = image.convert("RGBA")
        sx, sy = after.width/joined["width"], after.height/joined["height"]
        reach = 96
        roi = (0, 0, reach, reach) if joined["edge"] == "left" else (
            joined["width"]-reach, joined["height"]-reach, joined["width"], joined["height"])
        roi = tuple(round(v*(sx if i%2 == 0 else sy)) for i,v in enumerate(roi))
        assert ImageChops.difference(before.crop(roi), after.crop(roi)).getbbox(alpha_only=False), (
            joined["label"], "actual corner-weld pixels unchanged versus nonjoined control")
    return len(groups)


temporary = tempfile.TemporaryDirectory(prefix="alis-round0-module-ends-") if args.output is None else None
destination = Path(temporary.name) if temporary else args.output.resolve()
destination.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="alis-round0-module-native-") as name:
    folder = Path(name)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssLayout.js" as Layout
ShellRoot {
 id:root
 property bool showEditor:false
 property var cases:[]
 property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 AbyssSurfaceController {id:liquid;outputWidth:scene.width;outputHeight:scene.height;presentationItem:field}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;width:850;height:480
   AbyssField {
    id:field;anchors.fill:parent
    boundInterior:true
    renderScale:Window.window?.screen?.devicePixelRatio??1
    records:bar.deformations
    edgeInsets:Layout.edgeInsetsForModules(bar.placements,bar.layoutOptions,Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
    cornerWidthInsets:Layout.edgeInsetsForModules([],bar.layoutOptions,Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
    roundZeroCorners:bar.layoutOptions.edgeRoundZeroCorners
   }
   AbyssBar {
    id:bar;anchors.fill:parent;outputName:"fixture";edge:"top";editing:editor.visible
    draftPlacements:editor.visible?editor.draft:null
    draftOptions:editor.visible?editor.draftOptions:null
    liquidController:liquid
   }
   AbyssEdgeEditor {id:editor;anchors.fill:parent;outputName:"fixture";moduleLayer:bar;controller:liquid;visible:root.showEditor}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function capture(label){
   tryVerify(()=>field.ready,5000);wait(40)
   let done=false
   check(field.grabToImage(result=>{check(result.saveToFile(Quickshell.env("ROUND0_END_OUTPUT")+"/"+label+".png"),"save actual GPU image");done=true;root.frames++}),"capture refused")
   tryVerify(()=>done,5000)
  }
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   Config.setNestedValues({"performance.reduceAnimations":true,"bar.verbose":false,
    "abyss.effects.blur.enabled":false,"abyss.content.blurRadius":0,"abyss.effects.refraction.enabled":false,
    "abyss.surface.opacity":1,"abyss.content.opacity":1,"abyss.effects.shadowStrength":0,
    "abyss.effects.glow.strength":0,"abyss.effects.surfaceHighlight":0,"abyss.waves.enabled":false})
   const saved=JSON.stringify(Config.options.abyss.modules)
   root.showEditor=true;wait(100)
   // Exact reported kinds and retained corner-join direction come first.
   // A zero adjacent paint Edge exposes the weld; the remaining two neighbors
   // stay nonzero. Centered nonjoined controls below test both free endpoints.
   for(const edge of ["left","right"])for(const affects of [false,true]){
    const kind=edge==="left"?"distroIcon":"battery",weldEnd=edge==="left"?"start":"end"
    const comparison=kind+"-"+edge+"-"+(affects?"coupled":"bare")
    editor.editingEdge=edge
    editor.edgeThicknesses=edge==="left"?{top:0,right:16,bottom:24,left:0}:{top:8,right:0,bottom:0,left:32}
    editor.edgeWidthAffectsModules={top:true,right:true,bottom:true,left:true,[edge]:affects}
    editor.edgeModuleRadii={top:-1,right:-1,bottom:-1,left:-1}
    Config.setNestedValue("abyss.perimeter.radius",20)
    for(const joined of [false,true]){
     editor.edgeRoundZeroCorners={top:false,right:false,bottom:false,left:false}
     editor.draft=Layout.normalize([{id:"reported",kind:kind,edge:edge,alignment:weldEnd,
      position:edge==="left"?0:1,joinCorner:joined,customSize:true,size:1,depth:1}],edge)
     tryVerify(()=>bar.deformations.length===1&&editor.layoutConflicts.length===0,5000);wait(120)
     const before=JSON.stringify(bar.deformations),label="reported-"+comparison+"-"+(joined?"joined":"plain")
     capture(label+"-off");editor.edgeRoundZeroCorners={[edge]:true}
     tryVerify(()=>field.physicalContactEdges[edge==="left"?3:1]===true,1000)
     capture(label+"-on")
     check(JSON.stringify(bar.deformations)===before,"reported preview changed during capture")
     check(JSON.stringify(Config.options.abyss.modules)===saved,"reported preview wrote saved settings")
     root.cases.push({label:label,edge:edge,kind:kind,width:scene.width,height:scene.height,curvature:20,
      bodyRadius:AbyssStyle.neckRadius,records:JSON.parse(before),joined:joined,weldEnd:weldEnd,joinComparison:comparison})
    }
   }
   // Start with the owner's actual reported preview kinds/orientations.
   for(const edge of ["left","right","top","bottom"])for(const count of [1,2])for(const curvature of [12,34]){
    const kind=edge==="left"?"distroIcon":edge==="right"?"battery":"clock"
    editor.editingEdge=edge
    editor.edgeThicknesses={top:8,right:16,bottom:24,left:32,[edge]:0}
    editor.edgeJoinModules={top:false,right:false,bottom:false,left:false}
    editor.edgeModuleRadii={top:-1,right:-1,bottom:-1,left:-1}
    editor.draft=Layout.normalize(Array.from({length:count},(_,i)=>({id:"probe"+i,kind:kind,edge:edge,
     position:count===1?.5:i===0?.25:.75,customSize:true,size:i===0?1:.8})),edge)
    Config.setNestedValue("abyss.perimeter.radius",curvature)
    const identities=[]
    for(const affects of [false,true]){
     editor.edgeWidthAffectsModules={top:true,right:true,bottom:true,left:true,[edge]:affects}
     editor.edgeRoundZeroCorners={top:false,right:false,bottom:false,left:false}
     tryVerify(()=>bar.deformations.length===count&&editor.layoutConflicts.length===0,5000);wait(120)
     check(bar.placements.length===count,"valid custom-size module disappeared")
     const current=bar.placements.map(p=>bar.itemForId(p.id))
     if(!identities.length)for(const item of current)identities.push([item,item.feature])
     else for(let i=0;i<current.length;i++)check(current[i]===identities[i][0]&&current[i].feature===identities[i][1],"width-affects toggle recreated module/feature")
     const before=JSON.stringify(bar.deformations)
     const label=kind+"-"+edge+"-"+count+"-"+curvature+"-"+(affects?"coupled":"bare")
     capture(label+"-off")
     editor.edgeRoundZeroCorners={[edge]:true}
     const at=["top","right","bottom","left"].indexOf(edge)
     tryVerify(()=>field.physicalContactEdges[at]===true,1000)
     check(field.cornerWidthInsets[edge]===0,"draft configured width did not reach field")
     capture(label+"-on")
     check(JSON.stringify(bar.deformations)===before,"capture pair changed actual backing geometry")
     check(JSON.stringify(Config.options.abyss.modules)===saved,"transient preview changed saved module settings")
     root.cases.push({label:label,edge:edge,kind:kind,width:scene.width,height:scene.height,curvature:curvature,
      bodyRadius:AbyssStyle.neckRadius,records:JSON.parse(before)})
    }
   }
   console.info("ROUND0_MODULE_END_CASES",JSON.stringify(root.cases))
   console.info("ROUND0_MODULE_END_NATIVE_PASS",root.cases.length,"scenes",root.frames,"actual GPU images")
  }catch(error){console.error("ROUND0_MODULE_END_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: valid module endpoint test requires private Niri/OpenGL")
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        defaults = json.loads((ROOT / "defaults/config.json").read_text())
        defaults["panelFamily"] = "abyss"
        defaults["abyss"]["companion"]["enabled"] = False
        defaults["abyss"]["modules"]["configured"] = True
        defaults["abyss"]["modules"]["placements"] = []
        (config / "config.json").write_text(json.dumps(defaults))
        env.update(ROUND0_END_OUTPUT=str(destination), QSG_RHI_BACKEND="opengl")
        result = run_qs(folder, env, timeout=100)
        (destination / "native.log").write_text(result.stdout)
        bad = ("ROUND0_MODULE_END_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "shader preparation failed")
        if result.returncode or "ROUND0_MODULE_END_NATIVE_PASS" not in result.stdout or any(word in result.stdout for word in bad):
            print(result.stdout)
            raise SystemExit(1)
        prefix = "ROUND0_MODULE_END_CASES "
        lines = [line.split(prefix, 1)[1] for line in result.stdout.splitlines() if prefix in line]
        assert len(lines) == 1, "missing exact endpoint metadata"
        cases = json.loads(lines[0])
        (destination / "cases.json").write_text(json.dumps(cases, indent=2) + "\n")
        assert len(cases) == 40, "reported weld + four-edge policies/single+multiple/radii matrix incomplete"
        endpoints = sum(endpoint_checks(case, destination) for case in cases)
        assert endpoints == 104, "visible upper/lower endpoint coverage incomplete"
        welds = weld_checks(cases, destination)
        print(f"ROUND0_MODULE_END_PASS {len(cases)} actual draft scenes, {endpoints} independent visible endpoint ROIs, {welds} joined/nonjoined GPU controls, stable features and saved settings")
