#!/usr/bin/env python3
"""Actual Notepad paste/import, image decoding, tab races and saved restart."""
import base64
import json
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNwmLDhPwAFFAKA8JVvSQAAAABJRU5ErkJggg==")
with tempfile.TemporaryDirectory(prefix="alis-note-image-") as name:
    folder = Path(name)
    for entry in ["modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    source = folder / "Ảnh (draft).png"
    source.write_bytes(PNG)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.sidebarRight.notepad
import qs.services
ShellRoot {
 id: root
 Component.onCompleted: Quickshell.watchFiles = false
 FloatingWindow {
  visible:true;implicitWidth:450;implicitHeight:380;color:"#111820"
  QuickNotesView { id:notes; width:430;height:320; showZettelkastenActions:false }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,message){if(!ok)throw new Error(message)}
  function find(item,predicate){
   if(predicate(item))return item
   for(const child of item.children ?? []){const result=find(child,predicate);if(result)return result}
   return null
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000);tryCompare(Notepad,"ready",true,4000)
   Config.setNestedValue("performance.reduceAnimations",true)
   const editor=notes.editor
   const first=editor._loadedTabId
   if(Quickshell.env("NOTES_RESTART")==="1"){
    tryVerify(()=>editor.imageUrls.length===1,4000)
    const image=find(editor,item=>item.objectName==="quickNoteImage")
    check(image,"restart did not materialize preview")
    tryCompare(image,"status",Image.Ready,4000)
    check(image.width>0 && image.height>0,"restart image has no visible footprint")
    console.info("QUICK_NOTES_IMAGE_RESTART_PASS");Qt.quit();return
   }
   check(editor.pasteFromClipboard(),"binary paste did not start")
   tryCompare(editor,"attachmentBusy",false,6000)
   tryVerify(()=>editor.imageUrls.length===1,4000)
   const image=find(editor,item=>item.objectName==="quickNoteImage")
   check(image,"image paste has no preview")
   tryCompare(image,"status",Image.Ready,4000)
   check(image.source.toString().startsWith("file://") && image.width>0 && image.height>0,"binary image was not displayed")
   const original=Notepad.tabs[Notepad.indexForTabId(first)].text
   check(original.includes("![Image](") && !original.includes("PNG"),"binary payload entered note text")
   check(editor.importImage(Quickshell.env("NOTES_IMAGE_SOURCE")),"image import did not start")
   editor.addTabSafely()
   const second=editor._loadedTabId
   tryCompare(editor,"attachmentBusy",false,6000)
   check(editor._loadedTabId===second && editor.imageUrls.length===0,"late import switched or polluted the newly selected note")
   check(Notepad.tabs[Notepad.indexForTabId(first)].text.length>original.length,"late import was lost from its original note")
   editor.switchToTab(Notepad.indexForTabId(first))
   tryVerify(()=>editor.imageUrls.length===1,3000)
   check(editor.insertAttachmentResult(first,0,{text:"before\n"}),"receipt insertion failed")
   const snapshot=Notepad.tabs[Notepad.indexForTabId(first)].text
   check(editor.insertAttachmentResult(first,6,{text:"replacement"},0,6,snapshot),"selected paste failed")
   check(Notepad.tabs[Notepad.indexForTabId(first)].text.startsWith("replacement\n"),"paste failed to replace the original selection")
   check(editor.insertAttachmentResult(first,0,{text:"kept\n"},0,6,snapshot),"changed draft paste failed")
   check(Notepad.tabs[Notepad.indexForTabId(first)].text.startsWith("kept\nreplacement\n"),"late paste removed text edited after its snapshot")
   editor.flushPendingSave()
   tryVerify(()=>!Notepad._saving && !Notepad._saveQueued,3000)
   check(!editor.insertAttachmentResult("deleted-note",0,{text:"lost"}),"deleted target accepted a delayed attachment")
   console.info("QUICK_NOTES_IMAGE_PASS clipboard bytes, real preview, import, tab-switch race, autosave and deleted target")
  }catch(e){console.error("QUICK_NOTES_IMAGE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            raise SystemExit("SKIP: Notes images require private Niri")
        config = folder / "config/alis"
        config.mkdir(parents=True, exist_ok=True)
        data = json.loads((ROOT / "defaults/config.json").read_text())
        data["panelFamily"] = "abyss"
        data["abyss"]["companion"]["enabled"] = False
        (config / "config.json").write_text(json.dumps(data))
        store = folder / "state/quickshell/user"
        store.mkdir(parents=True, exist_ok=True)
        (store / "notepad-tabs.json").write_text(json.dumps({"currentTab":0,"tabs":[{"id":"first","title":"Note 1","text":"draft\n"}]}))
        bindir = folder / "bin"
        bindir.mkdir()
        fake = bindir / "wl-paste"
        fake.write_text("#!/usr/bin/python3\nimport sys,time\nfrom pathlib import Path\n"
                        "if '--list-types' in sys.argv: print('image/png')\n"
                        "else:\n time.sleep(.25)\n sys.stdout.buffer.write(Path(" + repr(str(source)) + ").read_bytes())\n")
        fake.chmod(0o755)
        env["PATH"] = str(bindir) + ":" + env.get("PATH", "")
        env["NOTES_IMAGE_SOURCE"] = source.as_uri()
        for restart in [False, True]:
            if restart:
                saved = json.loads((store / "notepad-tabs.json").read_text())
                saved["currentTab"] = 0
                (store / "notepad-tabs.json").write_text(json.dumps(saved))
                env["NOTES_RESTART"] = "1"
            result = run_qs(folder, env, timeout=25)
            marker = "QUICK_NOTES_IMAGE_RESTART_PASS" if restart else "QUICK_NOTES_IMAGE_PASS"
            if result.returncode or marker not in result.stdout or any(token in result.stdout for token in
                ["QUICK_NOTES_IMAGE_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration", "Unable to assign"]):
                print(result.stdout)
                raise SystemExit(1)
            print(next(line for line in result.stdout.splitlines() if marker in line))
        if source.read_bytes() != PNG:
            raise SystemExit("source image changed")
        images = list((store / "notepad-attachments").iterdir())
        if len(images) != 1 or images[0].read_bytes() != PNG:
            raise SystemExit("persistence/deduplication changed the copied image")
