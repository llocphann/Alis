#!/usr/bin/env python3
"""Source-first Markdown Reading/Source parity in Dashboard and Weekly Planner."""
import json, os, shutil, tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs

ROOT=Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: Dashboard Notes Markdown needs Quickshell")
    raise SystemExit(0)

QML=r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.dashboard
ShellRoot {
 id:root
 property int checks:0
 property int frames:0
 property real plannerWidth:1080
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  id:window;visible:true;implicitWidth:1180;implicitHeight:800;color:"#142129"
  Item {
   id:scene;anchors.fill:parent
   DashNotes {
    id:card
    objectName:"dashboardSourceFirstCard"
    x:12;y:12;width:470;height:325
   }
   DashboardWeeklyPlanner {
    id:planner
    x:12;y:355;width:root.plannerWidth;height:400
    presentationActive:true
   }
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(condition,reason){root.checks++;if(!condition)throw Error(reason)}
  function screenshot(name){
   const previous=root.frames
   check(scene.grabToImage(img=>{img.saveToFile(Quickshell.env("NOTES_DASH_CAPTURE")+"/"+name+".png");root.frames++}),"capture")
   tryVerify(()=>root.frames>previous,3000)
  }
  function sourceView(view){
   check(!!view && view.autoMarkdownReading,"Dashboard/Planner did not use shared autoMarkdownReading")
   const editor=view.editor
   const source=findChild(editor,"quickNotesSourceEditor")
   const reader=findChild(editor,"quickNotesMarkdownReading")
   const body=findChild(editor,"quickNotesMarkdownBody")
   check(!!source && !!reader && !!body,"shared NotepadWidget lost Markdown")
   check(!editor.markdownEditing && editor.markdownReading && reader.visible,
    "Dashboard/Planner must default to Markdown Reading")
   return {editor:editor,source:source,reader:reader,body:body}
  }
  function checkRoundTrip(view,tag){
   const parts=sourceView(view),noteId=parts.editor.displayedTabId
   check(noteId.length>0,"missing stable note ID "+tag)
   const draft="# "+tag+"\n**Bold** and *italic*"
   parts.source.text=draft
   parts.editor.flushPendingSave()
   tryVerify(()=>parts.reader.visible && parts.editor.markdownReading,3000)
   check(!parts.source.activeFocus && parts.body.textFormat===Text.MarkdownText,
    "Reading must not own keyboard focus "+tag)
   check(parts.editor.displayedTabId===noteId && parts.source.text===draft,
    "Reader changed tab identity/source bytes "+tag)
   screenshot(tag+"-reading")
   mouseClick(parts.body,8,8)
   tryVerify(()=>parts.source.activeFocus && parts.editor.markdownEditing,3000)
   check(parts.editor.displayedTabId===noteId && !parts.reader.visible,
    "click-to-Source switched note "+tag)
   parts.source.text="hello"
   parts.source.select(0,5)
   keyClick(Qt.Key_B,Qt.ControlModifier)
   check(parts.source.text==="**hello**","Ctrl+B Source failed "+tag)
   parts.source.select(2,7);keyClick(Qt.Key_B,Qt.ControlModifier)
   check(parts.source.text==="hello","bold toggle failed "+tag)
   parts.source.select(0,5);keyClick(Qt.Key_K,Qt.ControlModifier)
   check(parts.source.text==="[hello](https://)","Ctrl+K Source failed "+tag)
   keyClick(Qt.Key_Escape,Qt.NoModifier)
   tryVerify(()=>parts.reader.visible && parts.editor.markdownReading,3000)
   check(Notepad.tabs[Notepad.indexForTabId(noteId)].text===parts.source.text,
    "Escape to Reading lost pending Source autosave "+tag)
   check(parts.editor.displayedTabId===noteId,"Escape lost displayed stable ID "+tag)
   return parts
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,6000)
   tryCompare(Notepad,"ready",true,6000)
   const view=findChild(card,"quickNotesSharedDashboardView")
   tryVerify(()=>view?.editor?.displayedTabId.length>0,4000)
   const a=checkRoundTrip(view,"dashboard")
   planner.sideView="notes"
   const side=findChild(planner,"plannerSharedSidePanel")
   tryVerify(()=>side?.item!==null,4000)
   const plannerView=findChild(side.item,"quickNotesSharedDashboardView")
   tryVerify(()=>plannerView?.editor?.displayedTabId.length>0,4000)
   const b=checkRoundTrip(plannerView,"planner")
   check(a.editor.markdownReading,"other note surface changed mode on Planner activity")
   root.plannerWidth=480
   wait(140)
   check(b.reader.visible && b.editor.markdownReading,
    "small Planner notes column lost Reading state")
   screenshot("planner-narrow")
   planner.sideView="todo";wait(60)
   planner.sideView="notes";wait(80)
   const reopen=findChild(side.item,"quickNotesSharedDashboardView")
   check(reopen.editor.markdownReading,"new Planner notes instance must default Reading")
   check(reopen.editor.displayedTabId.length>0,"Planner remount lost canonical note ID")
   console.info("DASHBOARD_NOTES_MARKDOWN_NATIVE_PASS",root.checks,root.frames)
  }catch(error){console.error("DASHBOARD_NOTES_MARKDOWN_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
"""
with tempfile.TemporaryDirectory(prefix="alis-dashboard-markdown-") as name:
    folder=Path(name)
    for entry in ("modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"):
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Dashboard/Planner notes needs private Niri")
            raise SystemExit(0)
        cfg=folder/"config/illogical-impulse"
        cfg.mkdir(parents=True,exist_ok=True)
        data=json.loads((ROOT/"defaults/config.json").read_text())
        data["panelFamily"]="abyss"
        (cfg/"config.json").write_text(json.dumps(data))
        dest=Path(os.environ.get("ALIS_DASHBOARD_MARKDOWN_EVIDENCE",folder/"captures"))
        dest.mkdir(parents=True,exist_ok=True)
        result=run_qs(folder,dict(env,NOTES_DASH_CAPTURE=str(dest)),timeout=50)
        (dest/"native.log").write_text(result.stdout)
        if result.returncode or "DASHBOARD_NOTES_MARKDOWN_NATIVE_PASS" not in result.stdout or any(
                t in result.stdout for t in ("DASHBOARD_NOTES_MARKDOWN_NATIVE_FAIL","ReferenceError:","TypeError:",
                    "Binding loop","Unable to assign","Failed to load configuration")):
            print(result.stdout)
            raise SystemExit(1)
        for line in result.stdout.splitlines():
            if "DASHBOARD_NOTES_MARKDOWN_NATIVE_PASS" in line:
                print(line)
