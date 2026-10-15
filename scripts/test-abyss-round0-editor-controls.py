#!/usr/bin/env python3
"""Eight real Launcher/Battery editor scenes through mouse controls, Save and Cancel."""
import argparse
import json
import math
from pathlib import Path
import tempfile

from PIL import Image, ImageChops
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
temporary = tempfile.TemporaryDirectory(prefix="alis-round0-controls-images-") if args.output is None else None
output = Path(temporary.name) if temporary else args.output.resolve()
output.mkdir(parents=True, exist_ok=True)


def pixels(box, image, case):
    sx, sy = image.width/case["width"], image.height/case["height"]
    return (max(0, math.floor(box[0]*sx)), max(0, math.floor(box[1]*sy)),
            min(image.width, math.ceil(box[2]*sx)), min(image.height, math.ceil(box[3]*sy)))


def check_images(cases):
    endpoints = hidden = 0
    for case in cases:
        label, edge = case["label"], case["edge"]
        off = Image.open(output/(label+"-bare-off.png")).convert("RGBA")
        on = Image.open(output/(label+"-bare-on.png")).convert("RGBA")
        rect = case["record"]["surface"]
        # Independent, separate upper/lower physical-edge ROIs. The original
        # circle-oracle fixture owns detailed contour qualification; this probe
        # proves that actual button events reach those same rendered endpoints.
        for tangent, upper in ((rect["y"], True), (rect["y"]+rect["height"], False)):
            if not 0 < tangent < case["height"]:
                assert case["joined"], "unjoined centered control left the viewport"
                continue  # The retained corner weld intentionally ends offscreen.
            first, last = (tangent-40, tangent) if upper else (tangent, tangent+40)
            box = (0, first, 40, last) if edge == "left" else (case["width"]-40, first, case["width"], last)
            box = pixels(box, on, case)
            assert ImageChops.difference(off.crop(box), on.crop(box)).getbbox(alpha_only=False), (
                label, "actual Round0 control did not change", "upper" if upper else "lower")
            endpoints += 1
        if case["custom"]:
            coupled = Image.open(output/(label+"-coupled-on.png")).convert("RGBA")
            assert on.size == coupled.size and on.tobytes() == coupled.tobytes(), (
                label, "Width affects modules changed valid custom-module rounding")
        else:
            image = Image.open(output/(label+"-intentional-hidden.png")).convert("RGBA")
            reach = max(96, rect["x"]+rect["width"]+40) if edge == "left" else max(96, case["width"]-rect["x"]+40)
            first, last = max(0, rect["y"]-40), min(case["height"], rect["y"]+rect["height"]+40)
            box = (0, first, reach, last) if edge == "left" else (case["width"]-reach, first, case["width"], last)
            assert image.crop(pixels(box, image, case)).getchannel("A").getbbox() is None, (
                label, "intentional inherited 0px hide retained old module paint")
            hidden += 1
    assert endpoints == 12 and hidden == 4, "reported-kind/visible-endpoint/intentional-hide matrix incomplete"
    return endpoints, hidden


with tempfile.TemporaryDirectory(prefix="alis-round0-controls-native-") as name:
    folder = Path(name)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssLayout.js" as Layout
ShellRoot {
 id:root
 property var cases:[]
 property int frames:0
 property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 FileView {id:disk;path:Config.filePath;blockLoading:true;printErrors:false}
 AbyssSurfaceController {id:liquid;outputWidth:scene.width;outputHeight:scene.height;presentationItem:field}
 FloatingWindow {
  visible:true;implicitWidth:1000;implicitHeight:740;color:"#111820"
  Item {
   id:scene;width:850;height:480
   AbyssField {
    id:field;anchors.fill:parent;boundInterior:true
    records:bar.deformations
    edgeInsets:Layout.edgeInsetsForModules(bar.placements,bar.layoutOptions,Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
    cornerWidthInsets:Layout.edgeInsetsForModules([],bar.layoutOptions,Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
    roundZeroCorners:bar.layoutOptions.edgeRoundZeroCorners
   }
   AbyssBar {
    id:bar;anchors.fill:parent;outputName:"fixture";edge:"top";editing:editor.visible
    draftPlacements:editor.visible?editor.draft:null;draftOptions:editor.visible?editor.draftOptions:null;liquidController:liquid
   }
   AbyssEdgeEditor {id:editor;anchors.fill:parent;outputName:"fixture";moduleLayer:bar;controller:liquid;visible:GlobalStates.abyssEditing}
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){root.checks++;if(!value)throw new Error(message)}
  function control(name){
   const item=findChild(editor,name);check(!!item,"missing actual control "+name)
   let view=item.parent;while(view&&view.contentHeight===undefined)view=view.parent
   check(!!view,"control has no actual scroll viewport "+name)
   const point=item.mapToItem(view.contentItem,0,0)
   view.contentY=Math.max(0,Math.min(view.contentHeight-view.height,point.y-view.height/2));wait(50)
   check(item.visible&&item.enabled,"actual control unavailable "+name)
   return item
  }
  function click(name){const item=control(name);mouseClick(item,item.width/2,item.height/2);wait(80);return item}
  function zeroWidth(){
   const slider=control("abyssEdgeWidthSlider")
   mouseClick(slider,slider.leftPadding+.5,slider.height/2)
   tryCompare(slider,"value",0,1000)
   check(editor.edgeThicknesses[editor.editingEdge]===0,"actual slider moved signal did not update draft width")
  }
  function capture(label){
   tryVerify(()=>field.ready,5000);wait(40);let done=false
   check(field.grabToImage(result=>{check(result.saveToFile(Quickshell.env("ROUND0_CONTROL_OUTPUT")+"/"+label+".png"),"save actual image");done=true;root.frames++}),"capture refused")
   tryVerify(()=>done,5000)
  }
  function open(edge){GlobalStates.abyssEditing=true;tryCompare(editor,"visible",true,1000);wait(100);editor.editingEdge=edge;editor.selectedId="reported"}
  function configured(){return JSON.stringify(Config.options.abyss.modules)}
  function run(){try{
   tryCompare(Config,"ready",true,6000)
   check(Config.filePath.startsWith(Quickshell.env("ROUND0_CONTROL_CONFIG")),"fixture escaped private config")
   Config.setNestedValues({"performance.reduceAnimations":true,"abyss.perimeter.thickness":10,"abyss.perimeter.radius":20,
    "abyss.effects.blur.enabled":false,"abyss.content.blurRadius":0,"abyss.effects.refraction.enabled":false,
    "abyss.surface.opacity":1,"abyss.content.opacity":1,"abyss.effects.shadowStrength":0,
    "abyss.effects.glow.strength":0,"abyss.effects.surfaceHighlight":0,"abyss.waves.enabled":false})
   for(const edge of ["left","right"])for(const custom of [false,true])for(const joined of [false,true]){
    const kind=edge==="left"?"distroIcon":"battery",label=kind+"-"+(custom?"custom":"inherited")+"-"+(joined?"joined":"plain")
    const profile={outputName:"fixture",gap:8,size:1,
     placements:Layout.normalize([{id:"reported",kind:kind,edge:edge,customSize:custom,size:1,depth:1,
      joinCorner:joined,alignment:joined?(edge==="left"?"start":"end"):"free",position:joined?(edge==="left"?0:1):.5}],edge),
     edgeThicknesses:edge==="left"?{top:0,right:16,bottom:24,left:10}:{top:8,right:10,bottom:0,left:32},
     edgeWidthAffectsModules:{top:false,right:false,bottom:false,left:false},edgeRoundZeroCorners:{top:false,right:false,bottom:false,left:false},
     edgeModuleRadii:{top:-1,right:-1,bottom:-1,left:-1},edgeJoinModules:{top:false,right:false,bottom:false,left:false}}
    Config.setNestedValues({"abyss.modules.configured":true,"abyss.modules.outputLayouts":[profile]});wait(100)
    const saved=configured();open(edge)
    const rounding=findChild(editor,"abyssRoundZeroCorners")
    check(!rounding.enabled&&!rounding.checked,"nonzero saved width did not disable Round0")
    zeroWidth();tryVerify(()=>rounding.enabled,1000)
    check(field.cornerWidthInsets[edge]===0,"draft width failed field authority")
    tryVerify(()=>bar.deformations.length===1,3000)
    const item=bar.itemForId("reported"),feature=item.feature
    const record=JSON.parse(JSON.stringify(bar.deformations[0]))
    capture(label+"-bare-off")
    click("abyssRoundZeroCorners")
    check(rounding.checked&&editor.edgeRoundZeroCorners[edge]===true&&field.physicalContactEdges[edge==="left"?3:1],"actual Round0 button failed binding/draft/field")
    capture(label+"-bare-on")
    click("abyssScaleModulesToggle")
    check(editor.edgeWidthAffectsModules[edge]===true,"actual Width affects modules button failed draft")
    tryVerify(()=>bar.deformations.length===(custom?1:0),2000)
    check(field.physicalContactEdges[edge==="left"?3:1],"width toggle disabled configured0 mask")
    check(bar.itemForId("reported")===item&&item.feature===feature,"width toggle destroyed the real module/feature")
    capture(label+(custom?"-coupled-on":"-intentional-hidden"))
    check(configured()===saved,"preview controls wrote saved settings")
    root.cases.push({label:label,edge:edge,custom:custom,joined:joined,record:record,width:scene.width,height:scene.height})
    click("abyssLayoutCancel");tryCompare(editor,"visible",false,1000)
    check(configured()===saved,"actual Cancel changed saved profile")
    open(edge)
    check(editor.edgeThicknesses[edge]===10&&!editor.edgeRoundZeroCorners[edge]&&!editor.edgeWidthAffectsModules[edge],"Cancel/reopen retained unsaved controls")
    zeroWidth();click("abyssRoundZeroCorners");click("abyssScaleModulesToggle")
    click("abyssLayoutDone");tryCompare(editor,"visible",false,1000)
    const stored=Layout.optionsForOutput(Config.options.abyss.modules,"fixture")
    check(stored.edgeThicknesses[edge]===0&&stored.edgeRoundZeroCorners[edge]&&stored.edgeWidthAffectsModules[edge],"actual Done failed saved settings")
    tryVerify(()=>{disk.reload();try{const p=JSON.parse(disk.text()).abyss.modules.outputLayouts.find(p=>p.outputName==="fixture");return p.edgeThicknesses[edge]===0&&p.edgeRoundZeroCorners[edge]&&p.edgeWidthAffectsModules[edge]}catch(error){return false}},4000)
    open(edge);check(editor.edgeThicknesses[edge]===0&&editor.edgeRoundZeroCorners[edge]&&editor.edgeWidthAffectsModules[edge],"saved control state failed reopen")
    tryVerify(()=>bar.deformations.length===(custom?1:0),2000)
    click("abyssLayoutCancel");tryCompare(editor,"visible",false,1000)
   }
   console.info("ROUND0_CONTROL_CASES",JSON.stringify(root.cases))
   console.info("ROUND0_CONTROL_NATIVE_PASS",root.cases.length,"scenes",root.checks,"control assertions",root.frames,"images")
  }catch(error){console.error("ROUND0_CONTROL_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.run()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: editor control test requires private Niri/OpenGL")
        config = folder/"config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT/"defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        data["abyss"]["modules"]["configured"] = True
        data["abyss"]["modules"]["placements"] = []
        (config/"config.json").write_text(json.dumps(data))
        env.update(ROUND0_CONTROL_OUTPUT=str(output), ROUND0_CONTROL_CONFIG=str(folder/"config"), QSG_RHI_BACKEND="opengl")
        result = run_qs(folder, env, timeout=100)
        (output/"native.log").write_text(result.stdout)
        (output/"native-exit.json").write_text(json.dumps({"actual_exit":result.returncode})+"\n")
        bad = ("ROUND0_CONTROL_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "shader preparation failed")
        if result.returncode or "ROUND0_CONTROL_NATIVE_PASS" not in result.stdout or any(word in result.stdout for word in bad):
            print(result.stdout)
            raise SystemExit(1)
        prefix = "ROUND0_CONTROL_CASES "
        lines = [line.split(prefix, 1)[1] for line in result.stdout.splitlines() if prefix in line]
        assert len(lines) == 1
        cases = json.loads(lines[0])
        (output/"cases.json").write_text(json.dumps(cases, indent=2)+"\n")
        assert len(cases) == 8
        endpoints, hidden = check_images(cases)
        print(f"ROUND0_CONTROL_PASS 8 actual button/slider Save/Cancel scenes; {endpoints} endpoint ROIs; {hidden} intentional inherited 0px hides; custom toggle exact RGBA")
