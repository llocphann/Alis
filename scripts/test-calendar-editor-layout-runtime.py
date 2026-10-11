#!/usr/bin/env python3
"""Calendar fields and Remove must fit their font and narrow popup pane."""
from pathlib import Path
import shutil
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: Calendar layout requires Quickshell")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="alis-calendar-layout-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir",
                  "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    config = folder / "config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy2(ROOT / "defaults/config.json", config / "config.json")
    (folder / "shell.qml").write_text(r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.sidebarRight.events
ShellRoot {
 id:root
 property int removals:0
 property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 function all(item,predicate){
  let found=predicate(item)?[item]:[]
  for(const child of item.children??[])found=found.concat(all(child,predicate))
  return found
 }
 FloatingWindow {
  visible:true;implicitWidth:640;implicitHeight:600;color:"#10242b"
  EventsDialog {id:editor;embeddedPresentation:true;show:true;x:16;y:16;width:292;height:310}
  EventCard {
   id:card;x:16;y:350;width:292;height:implicitHeight
   event:({id:1,title:"Synthetic event",description:"Long fixture description that wraps in a narrow Calendar pane",dateTime:new Date(Date.now()+86400000).toISOString(),category:"meeting"})
   onRemoveClicked:root.removals++
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,message){root.checks++;if(!ok)throw new Error(message)}
  function fields(){return root.all(editor,item=>item.placeholderText!==undefined && item.placeholderText.length>0)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,6000);tryCompare(Events,"ready",true,6000)
   Config.setNestedValue("panelFamily","abyss")
   Config.setNestedValue("performance.reduceAnimations",true)
   const input=fields()
   check(input.length===2,"two Add/Edit fields must remain available")
   for(const dark of [true,false]){
    Appearance.m3colors.darkmode=dark
    for(const scale of [1,1.5,2]){
     Config.setNestedValue("appearance.typography.sizeScale",scale)
     for(const paneWidth of [240,292]){
      editor.width=paneWidth;card.width=paneWidth;wait(120)
      editor.eventTitle="";editor.eventDescription="";wait(20)
      const emptyHeights=input.map(field=>field.height)
      for(const field of input){
       check(field.height-field.topPadding-field.bottomPadding>=field.contentHeight,
        "placeholder has less vertical room than its font at "+scale)
      }
      editor.eventTitle="A long event input ".repeat(12)
      editor.eventDescription=editor.eventTitle;wait(20)
      for(let i=0;i<input.length;++i){
       const field=input[i]
       check(field.height-field.topPadding-field.bottomPadding>=field.contentHeight,
        "entered text is clipped at "+scale)
       check(field.height===emptyHeights[i],"long input must scroll along its single line")
      }
      const remove=root.all(card,item=>item.buttonText==="Remove")[0]
      check(remove!==undefined,"local event must keep its Remove action")
      const p=remove.mapToItem(card,0,0)
      check(p.x>=0 && p.y>=0 && p.x+remove.width<=card.width && p.y+remove.height<=card.height,
       "Remove action escapes the card at "+scale+" / "+paneWidth)
      for(const y of [2,remove.height/2,remove.height-2]){
       const before=root.removals;mouseClick(remove,remove.width/2,y)
       check(root.removals===before+1,"Remove click target is clipped")
      }
     }
    }
   }
   Config.setNestedValue("appearance.typography.sizeScale",1)
   editor.width=292;editor.resetForm()
   editor.eventDate=new Date(Date.now()+86400000)
   wait(60)
   input[0].forceActiveFocus();keyClick(Qt.Key_A)
   check(editor.eventTitle.toLowerCase()==="a","title keyboard input did not reach form state")
   check(editor.saveEvent() && Events.list.length===1,"Add did not persist to isolated Events store")
   const saved=Events.list[0];editor.loadEvent(saved)
   editor.eventTitle="Edited fixture"
   check(editor.saveEvent() && Events.list[0].title==="Edited fixture","Edit did not retain identity")
   check(Events.removeEvent(saved.id) && Events.list.length===0,"Remove did not update isolated Events store")
   console.info("CALENDAR_EDITOR_LAYOUT_PASS",root.checks,"checks: narrow panes, 100/150/200 percent fonts, light/dark, field fit, whole Remove target, Add/Edit/Remove")
  }catch(error){console.error("CALENDAR_EDITOR_LAYOUT_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Calendar layout requires a private Niri backend")
            raise SystemExit(0)
        result = run_qs(folder, env, timeout=25)
    output = result.stdout
    bad = ["CALENDAR_EDITOR_LAYOUT_FAIL", "ReferenceError:", "TypeError:",
           "Binding loop", "Unable to assign", "is not a type",
           "Failed to load configuration"]
    if result.returncode or "CALENDAR_EDITOR_LAYOUT_PASS" not in output or any(token in output for token in bad):
        print(output)
        raise SystemExit(1)
    for line in output.splitlines():
        if "CALENDAR_EDITOR_LAYOUT_PASS" in line:
            print(line)
