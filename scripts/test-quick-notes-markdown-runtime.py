#!/usr/bin/env python3
"""Real-QML Markdown Reading/Source Editing on private Notes, no owner state."""
import shutil
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: Quick Notes Markdown requires Quickshell")
    raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix="alis-note-markdown-") as name:
    folder = Path(name)
    for entry in ["modules","services","GlobalStates.qml","qmldir","assets",
                  "scripts","defaults","translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    config = folder/"config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy2(ROOT/"defaults/config.json",config/"config.json")
    (folder/"shell.qml").write_text(r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.sidebarRight.notepad
ShellRoot {
 id:root
 property int checks:0
 Component.onCompleted:Quickshell.watchFiles=false
 FloatingWindow {
  visible:true;implicitWidth:680;implicitHeight:480;color:"#142129"
  QuickNotesView {
   id:view;x:12;y:12;width:460;height:360
   showHeader:false;showZettelkastenActions:false
   verticalDotNavigation:true;readingOnHover:true
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,message){root.checks++;if(!ok)throw new Error(message)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,6000)
   tryCompare(Notepad,"ready",true,6000)
   const editor=view.editor
   tryVerify(()=>editor.displayedTabId.length>0,3000)
   const id=editor.displayedTabId
   const reader=findChild(editor,"quickNotesMarkdownReading")
   const body=findChild(editor,"quickNotesMarkdownBody")
   const source=findChild(editor,"quickNotesSourceEditor")
   check(!!reader && !!body && !!source,"shared Reading/Source widgets missing")
   check(reader.visible && !editor.markdownEditing && !source.activeFocus,
    "hover Reading must be unfocused")
   const raw="# Demo\n**bold** and *italic*\n![remote](https://untrusted.invalid/a.png)"
   check(Notepad.setTabTextById(id,raw),"private note update rejected")
   tryVerify(()=>source.text===raw,2000)
   check(body.text.includes("# Demo") && !body.text.includes("![remote]"),
    "rendered Markdown policy leaked image URL")
   check(body.textFormat===Text.MarkdownText,"preview not a Markdown renderer")
   check(!source.activeFocus,"reading grabbed keyboard focus")
   // Activate the actual content item and retain its stable note identity.
   mouseClick(body,12,12)
   tryVerify(()=>editor.markdownEditing && source.activeFocus,3000)
   check(!reader.visible,"Source should replace Reading after explicit click")
   check(editor.displayedTabId===id,"source transition lost tab identity")
   source.text="hello";source.select(0,5)
   keyClick(Qt.Key_B,Qt.ControlModifier)
   check(source.text==="**hello**","Ctrl+B must format selected Source bytes")
   source.select(2,7);keyClick(Qt.Key_B,Qt.ControlModifier)
   check(source.text==="hello","Ctrl+B must toggle surrounding markers")
   source.cursorPosition=source.text.length
   keyClick(Qt.Key_I,Qt.ControlModifier)
   check(source.text==="hello**","Ctrl+I must insert paired markers")
   source.text="link";source.select(0,4)
   keyClick(Qt.Key_K,Qt.ControlModifier)
   check(source.text==="[link](https://)","Ctrl+K must create Markdown link")
   editor.releaseEditorFocus()
   check(reader.visible && !editor.markdownEditing,
    "explicit release must restore Reading")
   check(Notepad.tabs[Notepad.indexForTabId(id)].text===source.text,
    "switching back to Reading must flush exact Markdown Source bytes")
   check(editor.displayedTabId===id,"reading round-trip switched note")
   console.info("QUICK_NOTES_MARKDOWN_NATIVE_PASS",root.checks,
    "private Reading/Source, focus, formatting, no Markdown byte conversion")
  }catch(error){console.error("QUICK_NOTES_MARKDOWN_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
""")
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Quick Notes Markdown needs a private Niri session")
            raise SystemExit(0)
        result = run_qs(folder,env,timeout=30)
    bad=["QUICK_NOTES_MARKDOWN_NATIVE_FAIL","ReferenceError:","TypeError:",
         "Binding loop","Unable to assign","is not a type",
         "Failed to load configuration"]
    if result.returncode or "QUICK_NOTES_MARKDOWN_NATIVE_PASS" not in result.stdout or any(x in result.stdout for x in bad):
        print(result.stdout)
        raise SystemExit(1)
    for line in result.stdout.splitlines():
        if "QUICK_NOTES_MARKDOWN_NATIVE_PASS" in line:
            print(line)
