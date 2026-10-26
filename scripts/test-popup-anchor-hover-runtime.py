#!/usr/bin/env python3
"""Real pointer transfer for StyledPopup hosted by the existing Abyss field."""
import json
import os
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-popup-hover-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.bar
import qs.modules.abyss
import qs.modules.abyss.content
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssGeometry.js" as Geometry
ShellRoot {
 id: root
 property int frames: 0
 property int clicks: 0
 property int idleCloses: 0
 property int genericCloses: 0
 property bool barRevealed: true
 property string edge: "bottom"
 property bool joinCorner: false
 property bool trailingCorner: false
 property var trace: []
 function snapshot(stage, point) {
  const c=host.record.content
  const p=point ? Qt.point(point[0],point[1]) : Qt.point(-1,-1)
  root.trace=root.trace.concat([{
   stage,edge:root.edge,point,scene:[scene.width,scene.height],
   content:{x:c.x,y:c.y,width:c.width,height:c.height},
   input:host.inputBounds,source:controller.sourceInputRegions,
   requested:popup.requestedVisible,body:popup._contentHovered,
   anchor:popup._anchorHover.hovered,progress:popup.revealProgress,
   contains:host.hoverParent.contains(Qt.point(p.x-host.hoverParent.x,p.y-host.hoverParent.y))
  }]).slice(-80)
 }
 QtObject { id: trigger; property bool triggerHovered: true }
 Component.onCompleted: Quickshell.watchFiles=false
 AbyssSurfaceController {
  id: controller
  presentationItem: scene
  outputWidth: scene.width; outputHeight: scene.height
  edgeInsets: ({left:8,right:8,top:8,bottom:8})
  sourceInputRegions: [Qt.rect(anchor.x,anchor.y,
    anchor.visible && anchor.enabled ? anchor.width : 0,anchor.height)]
 }
 FloatingWindow {
  id: window; visible:true; implicitWidth:640; implicitHeight:360; color:"#111820"
  Item {
   id: scene; anchors.fill:parent
   Item {
    id: anchor
    x: root.edge==="left" ? 8 : root.edge==="right" ? scene.width-40
      : root.joinCorner ? (root.trailingCorner ? scene.width-144 : 64) : 160
    y: root.edge==="top" ? 8 : root.edge==="bottom" ? scene.height-40
      : root.joinCorner ? (root.trailingCorner ? scene.height-144 : 64) : 160
    width: root.edge==="left" || root.edge==="right" ? 32 : 80
    height: root.edge==="left" || root.edge==="right" ? 80 : 32
    property var liquidController: controller
    property string attachedEdge: root.edge
    property string kind: "clock"
    visible: root.barRevealed || GlobalStates.barPopupHoverHeld(window.screen.name)
    MouseArea { anchors.fill:parent; hoverEnabled:true; onClicked:root.clicks++ }
   }
   AbyssBodyHost {
    id: host; anchors.fill:parent
    readonly property var popupEntry: controller.popupSlots[0]
    readonly property var hostedPopup: popupEntry?.popup ?? null
    identity:"styledPopup0"; controller:controller; edge:root.edge
    joinedEdge: !root.joinCorner ? "" : Geometry.horizontal(root.edge)
      ? (root.trailingCorner ? "right" : "left") : (root.trailingCorner ? "bottom" : "top")
    includeEdgeConnection:true
    open:hostedPopup?.presentationActive ?? false
    externalProgress:hostedPopup?.revealProgress ?? 0
    embeddedItem:hostedPopup?.contentItem ?? null
    padding:14; span:root.edge==="left" || root.edge==="right" ? 128 : 208
    depth:root.edge==="left" || root.edge==="right" ? 208 : 128
    along: !root.joinCorner ? 136 : root.trailingCorner
      ? (Geometry.horizontal(root.edge) ? scene.width : scene.height)-host.span-32 : 32
    // Production placement clearance includes module depth; painting does not.
    edgeInsets:({left:root.edge==="left" ? 40 : 8,right:root.edge==="right" ? 40 : 8,
     top:root.edge==="top" ? 40 : 8,bottom:root.edge==="bottom" ? 40 : 8})
    Component.onCompleted:controller.registerPopupHost(0,host)
    Component.onDestruction:controller.unregisterPopupHost(0,host)
    HoverHandler {
     parent:host.hoverParent; enabled:host.open
     onHoveredChanged:if(host.hostedPopup) host.hostedPopup._contentHovered=hovered
    }
   }
   AbyssGenericPopupPresenter {
    id: genericHost; anchors.fill:parent
    controller:controller;outputName:window.screen.name
    outputWidth:scene.width;outputHeight:scene.height
    presentationInsets:controller.edgeInsets
    requestedKind:"utilities";requestedOpen:false
    requestedFallbackEdge:root.edge;requestedAlongCenter:260
    onCloseRequested: { root.genericCloses++;requestedOpen=false }
   }
   AbyssPopupContent {
    id: generic; x:320; y:40; width:300; height:180
    kind:"launcher"; enabled:false; visible:enabled; participant:trigger; idleDismissDelay:150
    onCloseRequested: { root.idleCloses++;enabled=false }
    MaterialTextField { id: editor; visible:false; z:2; width:140; height:40; text:"fixture"; enableSettingsSearch:false }
   }
  }
 }
 StyledPopup {
  id: popup; hoverTarget:anchor
  Rectangle {
   implicitWidth:180; implicitHeight:100; color:"#29414b"
   MouseArea { anchors.fill:parent;hoverEnabled:true;onClicked:root.clicks++ }
  }
 }
 ResourcesPopup { id: resourcesPopup }
 TestCase {
  id: test; when:false; optional:true
  function check(v,m) { if(!v) throw new Error(m) }
  function render() {
   const before=root.frames
   check(scene.grabToImage(image=>root.frames++),"frame request refused")
   tryVerify(()=>root.frames>before,2000)
   check(root.frames>before,"scene render deadline")
  }
  function outside() { mouseMove(scene,600,20);wait(160);render();root.barRevealed=true }
  function runChecks() { try {
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValue("performance.reduceAnimations",true)
   Config.setNestedValue("bar.autoHide.enable",true)
   GlobalStates.deferredPanelsReady=true
   render();outside()
   check(!popup.requestedVisible,"popup starts open")
   for(const edge of ["bottom","top","left","right"]) {
    root.snapshot("edge-start",null)
    root.edge=edge;render();outside()
    mouseMove(anchor,anchor.width/2,anchor.height/2);wait(80);render()
    check(popup.requestedVisible && controller.activePopup===popup,"bare Item anchor did not open by hover on "+edge)
    check(popup.contentItem.parent===host.contentParent,"popup content was not hosted by the existing field")
    // Test the PAINTED connection, not source-anchor hover. A source region
    // has pointer priority and is intentionally excluded from the body mask.
    // The old left probe (14,200) overlapped the source (8..40,160..240);
    // _contentHovered=false there is not evidence of a broken body lease.
    const content=host.record.content
    const ins=controller.edgeInsets
    const source=controller.sourceInputRegions[0]
    const surface=host.rawPresentationRecord.surface
    const horizontal=edge==="top" || edge==="bottom"
    const cross=edge==="left" ? ins.left+6 : edge==="right" ? scene.width-ins.right-6
      : edge==="top" ? ins.top+6 : scene.height-ins.bottom-6
    const center=horizontal ? content.x+content.width/2 : content.y+content.height/2
    const minT=Math.max(0,Math.ceil(horizontal ? surface.x : surface.y))
    const maxT=Math.min((horizontal ? scene.width : scene.height)-1,
      Math.floor((horizontal ? surface.x+surface.width : surface.y+surface.height)-1))
    let bridge=null
    for(let delta=0;delta<=maxT-minT && bridge===null;delta++){
     for(const tangent of [Math.floor(center-delta),Math.ceil(center+delta)]){
      if(tangent<minT || tangent>maxT) continue
      const px=horizontal ? tangent : cross
      const py=horizontal ? cross : tangent
      if(Geometry.rectContains(source,px,py)
          || Geometry.rectContains(content,px,py)) continue
      if(Geometry.distance(px,py,scene.width,scene.height,ins,
          AbyssStyle.perimeterRadius,[host.rawPresentationRecord],
          AbyssStyle.connectionDepth,AbyssStyle.neckRadius)>=0) continue
      bridge=[px,py]
      break
     }
    }
    check(bridge!==null,"no painted connection probe outside source/content on "+edge)
    const x=bridge[0],y=bridge[1]
    check(!Geometry.rectContains(source,x,y)
          && !Geometry.rectContains(content,x,y),"bridge probe overlaps source/content")
    check(Geometry.rectContains(host.inputBounds,x,y)
          || host.connectionRects.some(rect=>Geometry.rectContains(rect,x,y)),
          "painted bridge pixel missing from body/native input footprint on "+edge)
    const before=JSON.stringify({content,input:host.inputBounds,x,y,edge:host.edge,source})
    mouseMove(scene,x,y);wait(220);render()
    // The source hover timer expires after handoff. The actual output lease
    // must keep its auto-hide source visible while the pointer owns the popup.
    root.barRevealed=false
    check(popup.requestedVisible && popup._contentHovered,
       "dwelling on the visible "+edge+" connection closed the popup: "+before)
    mouseMove(host.contentParent,host.contentParent.width/2,host.contentParent.height/2);wait(900);render()
    check(popup.requestedVisible && popup._contentHovered,"anchor-to-popup handoff collapsed the popup")
    // Straight portions of the painted body include 14 px of padding around
    // the feature. Hovering those pixels must hold the same lease as content.
    const padPoints=[
     [content.x-7,content.y+content.height/2],
     [content.x+content.width+7,content.y+content.height/2],
     [content.x+content.width/2,content.y-7],
     [content.x+content.width/2,content.y+content.height+7]
    ]
    check(controller.nativeInputRegions.includes(host.nativeInputRegion),"popup mask did not reach native owner")
    const maskRows=host.nativeInputRegion.regions[1].regions
    check(maskRows.length===host.connectionRects.length,"native shoulder mask lost strips")
    for(let i=0;i<maskRows.length;i++){
     const actual=maskRows[i],expected=host.connectionRects[i]
     check(actual.x===expected.x && actual.y===expected.y && actual.width===expected.width && actual.height===expected.height,"native shoulder mask differs from hover mask")
    }
    const s=host.rawPresentationRecord.surface
    const shoulders=edge==="top" || edge==="bottom"
     ? [[s.x-5,edge==="top" ? ins.top+3 : scene.height-ins.bottom-3],
        [s.x+s.width+5,edge==="top" ? ins.top+3 : scene.height-ins.bottom-3]]
     : [[edge==="left" ? ins.left+3 : scene.width-ins.right-3,s.y-5],
        [edge==="left" ? ins.left+3 : scene.width-ins.right-3,s.y+s.height+5]]
    for(const point of shoulders){
     check(Geometry.distance(point[0],point[1],scene.width,scene.height,ins,AbyssStyle.perimeterRadius,[host.rawPresentationRecord],AbyssStyle.connectionDepth,AbyssStyle.neckRadius)<0,"shoulder probe is not painted")
    }
    padPoints.push(...shoulders)
    for(const point of padPoints){
     root.snapshot("padding-before",point)
     mouseMove(scene,point[0],point[1]);wait(900);render()
     root.snapshot("padding-after",point)
     check(popup.requestedVisible && popup._contentHovered,"painted popup padding dismissed owner on "+edge+": "+JSON.stringify({point,input:host.inputBounds,content:host.record.content,requested:popup.requestedVisible,hosted:host.hostedPopup!==null}))
     check(GlobalStates.barPopupHoverHeld(window.screen.name) && anchor.visible,"hovered popup let the Edgebar auto-hide")
    }
    const blank=edge==="top" || edge==="bottom"
     ? [s.x-5,content.y+content.height/2]
     : [content.x+content.width/2,s.y-5]
    check(Geometry.distance(blank[0],blank[1],scene.width,scene.height,ins,AbyssStyle.perimeterRadius,[host.rawPresentationRecord],AbyssStyle.connectionDepth,AbyssStyle.neckRadius)>0,"blank probe overlaps paint")
    check(!host.hoverParent.contains(Qt.point(blank[0]-host.hoverParent.x,blank[1]-host.hoverParent.y)),"shoulder mask widened into blank desktop")
    mouseMove(scene,blank[0],blank[1]);wait(160);render()
    check(!popup.requestedVisible,"blank desktop retained popup hover")
    outside()
    check(!popup.requestedVisible && !popup.presentationActive && controller.activePopup===null,"pointer exit left a stale popup lease")
    check(!GlobalStates.barPopupHoverHeld(window.screen.name),"final exit retained an auto-hide Bar lease")
    check(host.connectionRects.length===0 && host.connectionRegions.length===0,"closed popup retained shoulder mask allocations")
   }
   // The adjacent weld is painted outside the original popup footprint.
   // It must receive native input and retain body hover on both corner ends.
   for(const edge of ["top","right","bottom","left"]) for(const trailing of [false,true]) {
    root.edge=edge;root.trailingCorner=trailing;root.joinCorner=true;render()
    mouseMove(scene,scene.width/2,scene.height/2);wait(160);render()
    mouseMove(anchor,anchor.width/2,anchor.height/2);wait(100);render()
    check(popup.requestedVisible,"joined source did not open on "+edge)
    check(host.record.joinedEdge===host.joinedEdge,"configured adjacent weld was not painted")
    const c=host.record.content,adjacent=host.joinedEdge
    const body=[c.x+c.width/2,c.y+c.height/2]
    const weld=adjacent==="left" ? [4,body[1]] : adjacent==="right" ? [scene.width-4,body[1]]
      : adjacent==="top" ? [body[0],4] : [body[0],scene.height-4]
    const primaryWeld=edge==="left" ? [4,body[1]] : edge==="right" ? [scene.width-4,body[1]]
      : edge==="top" ? [body[0],4] : [body[0],scene.height-4]
    const cornerWeld=[(edge==="left" || adjacent==="left") ? 4 : scene.width-4,
      (edge==="top" || adjacent==="top") ? 4 : scene.height-4]
    function owned(point) {
     return !controller.sourceInputRegions.some(r=>Geometry.rectContains(r,point[0],point[1]))
      && host.hoverParent.contains(Qt.point(point[0]-host.hoverParent.x,point[1]-host.hoverParent.y))
    }
    function nativeContains(point) {
     return host.nativeInputRegion.regions.some(region=>region.regions.length>0
      ? region.regions.some(r=>Geometry.rectContains(r,point[0],point[1]))
      : Geometry.rectContains(region,point[0],point[1]))
    }
    check(!Geometry.rectContains(host.rawPresentationRecord.surface,weld[0],weld[1]),"weld probe already belongs to unjoined body")
    check(Geometry.distance(weld[0],weld[1],scene.width,scene.height,controller.edgeInsets,
      AbyssStyle.perimeterRadius,[host.record],AbyssStyle.connectionDepth,AbyssStyle.neckRadius)<0,"adjacent probe is not painted")
    const shoulder=host.connectionRects.find(r=>r.width>0 && r.height>0
      && !Geometry.rectContains(host.inputBounds,r.x+r.width/2,r.y+r.height/2)
      && (Geometry.horizontal(edge) ? r.height>1 : r.width>1)
      && owned([r.x+r.width/2,r.y+r.height/2]))
    check(shoulder!==undefined,"adjacent shoulder probe is missing on "+edge)
    // QtTest mouseMove takes integer coordinates. Round before containment
    // checks so a 1px strip's .5 center cannot be rounded out of that strip.
    const shoulderPoint=[Math.floor(shoulder.x+shoulder.width/2),
      Math.floor(shoulder.y+shoulder.height/2)]
    for(const point of [body,weld,primaryWeld,cornerWeld,shoulderPoint,body]) {
     check(owned(point) && nativeContains(point),"joined paint is outside native/hover mask on "+edge)
     mouseMove(scene,point[0],point[1]);wait(220);render()
     check(popup.requestedVisible && popup._contentHovered,"adjacent weld/shoulder dismissed popup on "+edge)
    }
    const source=[anchor.x+anchor.width/2,anchor.y+anchor.height/2]
    check(!owned(source),"joined popup stole source-module input")
    mouseMove(scene,source[0],source[1]);wait(120);render()
    check(popup.requestedVisible,"reverse joined handoff dismissed popup")
    mouseMove(scene,scene.width/2,scene.height/2);wait(160);render()
    check(!popup.presentationActive && host.connectionRects.length===0
      && host.connectionRegions.length===0,"joined close retained input or a lease")
   }
   root.joinCorner=false;root.edge="bottom";render();outside()
   mouseMove(anchor,40,16);wait(80);render()
   popup.dismissPresentation();wait(40)
   check(!popup.requestedVisible,"explicit dismissal failed")
   outside();mouseMove(anchor,40,16);wait(80);render()
   check(popup.requestedVisible,"dismissed hover popup could not reopen after leaving")
   anchor.enabled=false;wait(160);render()
   check(!popup.presentationActive,"disabled anchor retained a presentation lease")
   outside();anchor.enabled=true;popup.hoverActivates=false
   mouseMove(anchor,40,16);wait(120);render()
   check(!popup.requestedVisible,"click-only popup was opened by hover")
   popup.alternativeVisibleCondition=true;wait(80);render()
   check(popup.requestedVisible && controller.activePopup===popup,"explicit click-only request stopped working")
   popup.alternativeVisibleCondition=false;outside()
   check(!popup.presentationActive && root.clicks===0,"hover test clicked the trigger or leaked the popup")
   for(const edge of ["bottom","top","left","right"]){
    root.edge=edge;genericHost.hoverKind="utilities";genericHost.requestedOpen=true
    tryCompare(genericHost,"ready",true,4000);render()
    const feature=genericHost.contentItem.item
    const child=Qt.createQmlObject('import QtQuick; MouseArea { anchors.fill:parent;hoverEnabled:true;acceptedButtons:Qt.NoButton;z:10 }',feature)
    const body=feature.participant
    const c=genericHost.record.content,ins=controller.edgeInsets
    const horizontal=edge==="top" || edge==="bottom"
    const center=horizontal ? c.x+c.width/2 : c.y+c.height/2
    const cross=edge==="left" ? ins.left+6 : edge==="right" ? scene.width-ins.right-6
      : edge==="top" ? ins.top+6 : scene.height-ins.bottom-6
    function ownedPoint(point){
     return point[0]>=0 && point[1]>=0 && point[0]<scene.width && point[1]<scene.height
      && !controller.sourceInputRegions.some(r=>Geometry.rectContains(r,point[0],point[1]))
      && body.hoverParent.contains(Qt.point(point[0]-body.hoverParent.x,point[1]-body.hoverParent.y))
    }
    // A narrow output can move the generic body's center over another module.
    // Source regions have pointer priority and intentionally exclude body hover.
    // Probe a painted bridge pixel owned by this body, as in the StyledPopup case.
    let bridge=null
    for(let delta=0;delta<(horizontal?scene.width:scene.height) && bridge===null;delta++){
     for(const tangent of [Math.floor(center-delta),Math.ceil(center+delta)]){
      const point=horizontal ? [tangent,cross] : [cross,tangent]
      if(!ownedPoint(point) || Geometry.rectContains(c,point[0],point[1]))continue
      if(Geometry.distance(point[0],point[1],scene.width,scene.height,ins,
       AbyssStyle.perimeterRadius,[body.rawPresentationRecord],AbyssStyle.connectionDepth,AbyssStyle.neckRadius)<0){bridge=point;break}
     }
    }
    check(bridge!==null,"generic body has no owned painted bridge probe on "+edge)
    function paddingPoint(x,y,tangentAxis,extent){
     for(let delta=0;delta<=extent/2;delta++){
      for(const direction of [-1,1]){
       const point=[x,y];point[tangentAxis]+=direction*delta
       if(ownedPoint(point) && Geometry.distance(point[0],point[1],scene.width,scene.height,ins,
        AbyssStyle.perimeterRadius,[body.rawPresentationRecord],AbyssStyle.connectionDepth,AbyssStyle.neckRadius)<0)return point
      }
     }
     throw new Error("generic padding has no owned painted probe on "+edge)
    }
    const points=[
     bridge,
     [c.x+c.width/2,c.y+c.height/2],
     paddingPoint(c.x-7,c.y+c.height/2,1,c.height),
     paddingPoint(c.x+c.width+7,c.y+c.height/2,1,c.height),
     paddingPoint(c.x+c.width/2,c.y-7,0,c.width),
     paddingPoint(c.x+c.width/2,c.y+c.height+7,0,c.width)
    ]
    for(const point of points){
     check(ownedPoint(point),"generic probe overlaps source/outside input on "+edge+": "+JSON.stringify(point))
     mouseMove(scene,point[0],point[1]);genericHost.hoverKind="";wait(900);render()
     check(genericHost.requestedOpen && root.genericCloses===0,"generic body/bridge/padding idle timer closed a hovered popup on "+edge+": "+JSON.stringify(point))
    }
    child.destroy()
    if(edge==="bottom" || edge==="left"){
     const point=[anchor.x+anchor.width/2,anchor.y+anchor.height/2]
     check(!ownedPoint(point),"generic body stole source-module priority")
     mouseMove(anchor,anchor.width/2,anchor.height/2)
    }else mouseMove(scene,scene.width-10,scene.height/2)
    wait(900);render()
    check(!genericHost.requestedOpen,"generic popup did not close after final leave")
    check(root.genericCloses===1,"generic dismissal emitted more than once")
    root.genericCloses=0
   }
   const coldWidth=resourcesPopup.contentItem.implicitWidth
   const coldHeight=resourcesPopup.contentItem.implicitHeight
   check(coldWidth>0 && coldHeight>0,"ResourcesPopup content had zero initial implicit size")
   ResourceUsage.ensureRunning(false,false)
   tryVerify(()=>ResourceUsage.memoryTotal>0,1000)
   ResourceUsage.cpuTemp=64;ResourceUsage.gpuTemp=58;ResourceUsage.cpuUsage=0.42;ResourceUsage.gpuUsage=0.37
   wait(40);render()
   check(resourcesPopup.contentItem.implicitWidth===coldWidth && resourcesPopup.contentItem.implicitHeight===coldHeight,
    "ResourcesPopup implicit size shifted between cold and warm telemetry: "+JSON.stringify({coldWidth,coldHeight,warmWidth:resourcesPopup.contentItem.implicitWidth,warmHeight:resourcesPopup.contentItem.implicitHeight}))
   ResourceUsage.stop()
   generic.enabled=true;generic.forceActiveFocus();wait(40)
   check(generic.activeFocus,"focus fixture did not acquire Qt focus")
   trigger.triggerHovered=false;wait(400)
   check(root.idleCloses===1,"retained Qt focus left the hover popup stuck open after pointer exit")
   trigger.triggerHovered=true;generic.enabled=true;editor.visible=true
   editor.forceActiveFocus();wait(60)
   check(generic.editorFocusHeld,"editable text did not hold its own popup input session")
   trigger.triggerHovered=false;wait(400)
   check(root.idleCloses===1,"idle dismissal interrupted an editable text session")
   editor.readOnly=true;wait(400)
   check(root.idleCloses===2,"read-only text retained a stale input session")
   console.info("POPUP_ANCHOR_HOVER_PASS")
  } catch(e) {
   console.error("POPUP_ANCHOR_HOVER_TRACE",JSON.stringify(root.trace))
   console.error("POPUP_ANCHOR_HOVER_FAIL",e.message,e.stack)
  } Qt.quit() }
 }
 Timer { interval:100;running:true;onTriggered:test.runChecks() }
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: popup hover requires a private Niri surface")
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        (config / "config.json").write_text(json.dumps(data))
        # Every grab retains its 2-second deadline; sustained body/padding dwell
        # must outlast actual hide timers even when nested Niri is unfocused.
        result = run_qs(folder, env, timeout=230)
        if os.environ.get("ALIS_POPUP_HOVER_LOG"):
            Path(os.environ["ALIS_POPUP_HOVER_LOG"]).write_text(result.stdout)
        if result.returncode or "POPUP_ANCHOR_HOVER_PASS" not in result.stdout or any(
            token in result.stdout for token in ["POPUP_ANCHOR_HOVER_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Object set as mask", "Failed to load configuration"]
        ):
            print(result.stdout)
            raise SystemExit(1)
        print("POPUP_ANCHOR_HOVER_PASS four-edge sustained body/padding/bridge/shoulder hover with interactive children, generic idle timers, auto-hide Bar hold/release, reentry and click-only/editor focus")
