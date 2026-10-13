#!/usr/bin/env python3
"""Real Clock/Weather hover, stable slots and pyramid reveal on four Edges."""
import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="hadalis-weather-handoff-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.bar
import qs.modules.bar.weather
import qs.modules.abyss
ShellRoot {
 id: root
 property string edge: "top"
 property int samples: 0
 property int rendered: 0
 property int clicks: 0
 Component.onCompleted: Quickshell.watchFiles = false
 AbyssSurfaceController {
  id: controller
  presentationItem: scene
  outputWidth: scene.width; outputHeight: scene.height
  edgeInsets: ({left:8,right:8,top:8,bottom:8})
  sourceInputRegions: [Qt.rect(clockAnchor.x,clockAnchor.y,clockAnchor.width,clockAnchor.height),
    Qt.rect(weatherAnchor.x,weatherAnchor.y,weatherAnchor.width,weatherAnchor.height)]
 }
 FloatingWindow {
  visible: true; implicitWidth: 1100; implicitHeight: 800; color: "#111820"
  Item {
   id: scene; anchors.fill: parent
   Item {
    id: clockAnchor
    readonly property bool horizontal: root.edge==="top" || root.edge==="bottom"
    x: horizontal ? scene.width/2-90 : root.edge==="left"?8:scene.width-40
    y: horizontal ? (root.edge==="top"?8:scene.height-40) : scene.height/2-90
    width: horizontal?64:32; height: horizontal?32:64
    property var liquidController: controller
    property string attachedEdge: root.edge
    property string kind: "clock"
    MouseArea { anchors.fill:parent; hoverEnabled:true; onClicked:root.clicks++ }
   }
   Item {
    id: weatherAnchor
    x: clockAnchor.x+(clockAnchor.horizontal?96:0)
    y: clockAnchor.y+(clockAnchor.horizontal?0:96)
    width: clockAnchor.width; height: clockAnchor.height
    property var liquidController: controller
    property string attachedEdge: root.edge
    property string kind: "weather"
    MouseArea { anchors.fill:parent; hoverEnabled:true; onClicked:root.clicks++ }
   }
   Repeater {
    id: hosts; model: controller.popupCapacity
    delegate: AbyssBodyHost {
     id: host; required property int index
     readonly property var entry: controller.popupSlots[index] ?? null
     readonly property var popup: entry?.popup ?? null
     readonly property bool horizontal: root.edge==="top" || root.edge==="bottom"
     readonly property rect anchorBounds: popup?._anchorRect(scene.width,scene.height) ?? Qt.rect(0,0,0,0)
     anchors.fill:parent; controller:controller; identity:"styledPopup"+index
     edge:root.edge
     edgeInsets:({left:root.edge==="left"?40:8,right:root.edge==="right"?40:8,
      top:root.edge==="top"?40:8,bottom:root.edge==="bottom"?40:8})
     includeEdgeConnection:true; stackPolicy:"pyramid"
     semanticOpenOverride:popup?.liquidSemanticVisible ?? false
     open:popup?.presentationActive ?? false
     externalProgress:popup?.revealProgress ?? 0
     embeddedItem:popup?.contentItem ?? null; padding:14
     span:(horizontal?(embeddedItem?.implicitWidth ?? 1):(embeddedItem?.implicitHeight ?? 1))+padding*2
     depth:(horizontal?(embeddedItem?.implicitHeight ?? 1):(embeddedItem?.implicitWidth ?? 1))+padding*2
     along:(horizontal?anchorBounds.x+anchorBounds.width/2:anchorBounds.y+anchorBounds.height/2)-span/2
     onEntryChanged:{retainedPlacement=null;resetPyramidMotion()}
     Component.onCompleted:controller.registerPopupHost(index,host)
     Component.onDestruction:controller.unregisterPopupHost(index,host)
     HoverHandler {
      parent:host.hoverParent; enabled:host.open
      onHoveredChanged:if(host.popup) host.popup._contentHovered=hovered
     }
    }
   }
  }
 }
 ClockCalendarPopup { id:clock; hoverTarget:clockAnchor }
 WeatherPopup { id:weather; hoverTarget:weatherAnchor }
 TestCase {
  id:test; when:false; optional:true
  function check(ok,message){if(!ok)throw new Error(message)}
  function sample(){
   const content=weather.contentItem
   if(!content || !weather.presentationActive || content.height<=0)return
   const viewport=content.children[0], orbit=viewport.children[0], detail=viewport.children[1]
   check(content.currentTab===0 && content.tabPosition===0,"hover replayed a Weather tab transition")
   check(orbit.y===0 && detail.y===viewport.height,"Weather pages overlap during host resize/reveal")
   check(viewport.clip,"Weather pages escaped the common viewport")
   check(content.parent===controller._popupHost(controller._popupSlot(weather)).contentParent,
      "Weather was painted by another popup slot")
   root.samples++
  }
  function observe(ms){
   for(let i=0;i<Math.ceil(ms/12);i++){wait(12);sample()}
   if(ms>=400){
    const previous=root.rendered
    check(scene.grabToImage(image=>root.rendered++),"frame request refused")
    tryVerify(()=>root.rendered>previous,2000)
    check(root.rendered>previous,"unfocused scene render deadline")
    wait(30);sample()
   }
  }
  function enter(anchor){mouseMove(anchor,anchor.width/2,anchor.height/2)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValue("performance.reduceAnimations",false)
   Weather.data={temp:"25°",wCode:"113",description:"Overcast",sunrise:"06:00",sunset:"18:00",
    hourly:Array.from({length:8},(_,i)=>({label:String(i*3).padStart(2,"0")+":00",temp:"25°",code:"113"}))}
   for(const edge of ["top","bottom","left","right"]){
    root.edge=edge;mouseMove(scene,80,80);observe(400)
    for(const dwell of [24,70,110]){
     enter(clockAnchor);observe(300)
     check(clock.requestedVisible,"Clock did not open by hover on "+edge)
     enter(weatherAnchor);observe(dwell)
     enter(clockAnchor);observe(dwell)
     enter(weatherAnchor);observe(500)
     check(weather.requestedVisible && !clock.presentationActive,"Weather handoff retained Clock hover/tail on "+edge+" "+JSON.stringify({
      weather:{requested:weather.requestedVisible,hover:weather._anchorHover.hovered,content:weather._contentHovered},
      clock:{requested:clock.requestedVisible,hover:clock._anchorHover.hovered,module:clock.moduleHoverActive,content:clock._contentHovered,
       editor:clock.alternativeVisibleCondition,linger:clock._lingerVisible,progress:clock.revealProgress},
      anchors:{clock:[clockAnchor.x,clockAnchor.y],weather:[weatherAnchor.x,weatherAnchor.y]},
      slots:controller.popupSlots.map((entry,index)=>entry?{kind:entry.popup._liquidAnchor.kind,input:controller._popupHost(index).inputBounds}:null)}))
     check(controller.activePopups.length===1 && controller.activePopup===weather,"Weather handoff leaked a popup slot")
     const host=controller._popupHost(controller._popupSlot(weather))
     mouseMove(host.contentParent,host.contentParent.width/2,host.contentParent.height/2);observe(120)
     check(weather.requestedVisible,"Weather content transfer lost its hover lease")
     mouseMove(scene,80,80);observe(450)
     check(!weather.presentationActive && controller.activePopups.length===0,"Weather exit stranded a popup slot "+JSON.stringify({edge,
      request:weather.requestedVisible,content:weather._contentHovered,anchor:weather._anchorHover.hovered,
      hold:weather._liquidSemanticHold,linger:weather._lingerVisible,offset:weather.offsetScale}))
    }
   }
   check(root.samples>100 && root.clicks===0,"handoff fixture did not exercise hover frames")
   console.info("WEATHER_HANDOFF_PASS",root.samples,"four Edges, rapid reversal, actual Clock/Weather, stable slots, content transfer and exit")
  }catch(e){console.error("WEATHER_HANDOFF_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: Weather handoff requires private Niri")
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        data["bar"]["weather"]["enable"] = False
        (config / "config.json").write_text(json.dumps(data))
        result = run_qs(folder, env, timeout=110)
        if result.returncode or "WEATHER_HANDOFF_PASS" not in result.stdout or any(
            token in result.stdout for token in ["WEATHER_HANDOFF_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration"]
        ):
            print(result.stdout)
            print("Weather handoff process exit:", result.returncode)
            raise SystemExit(1)
        print(next(line for line in result.stdout.splitlines() if "WEATHER_HANDOFF_PASS" in line))
