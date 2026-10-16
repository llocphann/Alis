#!/usr/bin/env python3
"""Real-QML Markdown Reading/Source Editing on private Notes, no owner state."""
import json
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
    # Never read or write the installed desktop's notes. Use isolated XDG
    # config/state and seed stable identities, generated/custom titles.
    config = folder / "config/alis"
    config.mkdir(parents=True)
    settings = json.loads((ROOT / "defaults/config.json").read_text())
    settings["panelFamily"] = "abyss"
    settings["abyss"]["companion"]["enabled"] = False
    (config / "config.json").write_text(json.dumps(settings))
    store = folder / "state/quickshell/user"
    store.mkdir(parents=True)
    note_file = store / "notepad-tabs.json"
    note_file.write_text(json.dumps({
        "currentTab": 0,
        "tabs": [
            {"id": "fixture-markdown", "title": "Note 17", "text": "seed"},
            {"id": "fixture-custom", "title": "Custom title", "text": "unchanged"}
        ]
    }))
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
   verticalDotNavigation:true;autoMarkdownReading:true
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
   const longText="# Long note\n"+("row with **bold** and [link](https://example.invalid) ✓\n").repeat(420)
   check(id==="fixture-markdown","fixture note identity changed on load")
   check(Notepad.tabs[0].title==="Note 1" && Notepad.tabs[1].title==="Custom title",
    "generated title migration changed custom title or order")
   const reader=findChild(editor,"quickNotesMarkdownReading")
   const body=findChild(editor,"quickNotesMarkdownBody")
   const source=findChild(editor,"quickNotesSourceEditor")
   check(!!reader && !!body && !!source,"shared Reading/Source widgets missing")
   check(reader.visible && !editor.markdownEditing && !source.activeFocus,
    "Reading must be visible without taking keyboard focus")
   if (Quickshell.env("NOTES_RESTART")==="1") {
    check(source.text===longText && Notepad.tabs[0].text===longText,
     "restart changed long Markdown source bytes")
    check(id==="fixture-markdown" && Notepad.tabs[1].id==="fixture-custom",
     "restart changed saved note identity")
    console.info("QUICK_NOTES_MARKDOWN_RESTART_PASS",root.checks,
     "private long-note disk reload, stable ids and titles")
    Qt.quit();return
   }
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
   // Exercise underline and alignment with the real TextArea shortcuts.
   source.text="underlined";source.select(0,10)
   keyClick(Qt.Key_U,Qt.ControlModifier)
   check(source.text==="<u>underlined</u>","Ctrl+U must wrap selected text")
   source.text="paragraph one\nparagraph two"
   source.cursorPosition=source.text.indexOf("two")+1
   const beforeAlignment=source.cursorPosition
   keyClick(Qt.Key_E,Qt.ControlModifier | Qt.ShiftModifier)
   check(source.text==='paragraph one\n<p align="center">paragraph two</p>',
    "Ctrl+Shift+E must align only the current paragraph")
   check(source.cursorPosition===beforeAlignment+'<p align="center">'.length,
    "alignment moved the caret away from the logical character")
   // Long-note editing and Ctrl+S must not lose the caret/selection.
   source.text=longText
   source.cursorPosition=1100
   keyClick(Qt.Key_S,Qt.ControlModifier)
   check(source.cursorPosition===1100,"explicit save shifted the caret")
   keyClick(Qt.Key_Escape)
   tryVerify(()=>reader.visible && !editor.markdownEditing && !source.activeFocus,3000)
   tryVerify(()=>!Notepad._saving && !Notepad._saveQueued,4000)
   check(reader.visible && !editor.markdownEditing,
    "first Escape must restore Reading without closing the host")
   check(Notepad.tabs[Notepad.indexForTabId(id)].text===source.text,
    "Escape must flush exact long Markdown Source bytes")
   check(editor.displayedTabId===id,"reading round-trip switched note")
   console.info("QUICK_NOTES_MARKDOWN_NATIVE_PASS",root.checks,
    "private Reading/Source, Escape, shortcuts, caret, long notes and save")
  }catch(error){console.error("QUICK_NOTES_MARKDOWN_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
""")
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Quick Notes Markdown needs a private Niri session")
            raise SystemExit(0)
        for restart in (False, True):
            env["NOTES_RESTART"] = "1" if restart else "0"
            result = run_qs(folder, env, timeout=45)
            marker = ("QUICK_NOTES_MARKDOWN_RESTART_PASS" if restart
                      else "QUICK_NOTES_MARKDOWN_NATIVE_PASS")
            bad = ["QUICK_NOTES_MARKDOWN_NATIVE_FAIL", "ReferenceError:",
                   "TypeError:", "Binding loop", "Unable to assign",
                   "is not a type", "Failed to load configuration"]
            if result.returncode or marker not in result.stdout or any(
                    token in result.stdout for token in bad):
                print(result.stdout)
                raise SystemExit(1)
            print(next(line for line in result.stdout.splitlines() if marker in line))
            # An explicit disk readback, not just a QML in-memory property.
            saved = json.loads(note_file.read_text())
            expected_long = "# Long note\n" + (
                "row with **bold** and [link](https://example.invalid) ✓\n" * 420)
            tabs = saved["tabs"]
            if (saved["currentTab"] != 0 or len(tabs) != 2
                    or tabs[0] != {"id": "fixture-markdown",
                                    "title": "Note 1", "text": expected_long}
                    or tabs[1] != {"id": "fixture-custom",
                                    "title": "Custom title",
                                    "text": "unchanged"}):
                raise SystemExit("FAIL: private note disk readback does not match")
