#!/usr/bin/env python3
"""Native image decode/layout and reused-delegate regression; private cache only."""
from pathlib import Path
import os, shutil, struct, subprocess, tempfile, zlib

ROOT=Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: native clipboard images require Quickshell")
    raise SystemExit(0)

def png(width,height):
    def chunk(kind,data):
        return struct.pack(">I",len(data))+kind+data+struct.pack(">I",zlib.crc32(kind+data)&0xffffffff)
    scan=(b"\0"+bytes([35,170,220,255])*width)*height
    return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",width,height,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(scan))+chunk(b"IEND",b"")

with tempfile.TemporaryDirectory(prefix="alis-clipboard-image-") as name:
    folder=Path(name)
    for entry in ["services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:
        (folder/entry).symlink_to(ROOT/entry)
    # Directories bootstraps and clears session caches on first use. Keep both
    # the standalone preview and the real Abyss delegate away from owner caches.
    modules=folder/"modules";modules.mkdir()
    for entry in (ROOT/"modules").iterdir():
        if entry.name != "common": (modules/entry.name).symlink_to(entry)
    common=modules/"common";common.mkdir()
    for entry in (ROOT/"modules/common").iterdir():
        if entry.name != "Directories.qml": (common/entry.name).symlink_to(entry)
    (common/"Directories.qml").write_text((ROOT/"modules/common/Directories.qml").read_text().replace(
        "/tmp/quickshell",str(folder/"runtime")))
    config=folder/"config/alis";config.mkdir(parents=True)
    shutil.copy(ROOT/"defaults/config.json",config/"config.json")
    (folder/"one.png").write_bytes(png(200,80))
    (folder/"two.png").write_bytes(png(64,128))
    fake=folder/"cliphist-native-fixture"
    fake.write_text("#!/usr/bin/python3\nimport os,pathlib,sys,time\nroot=pathlib.Path(__file__).parent\nif sys.argv[1:]==['list']:\n time.sleep(float(os.environ.get('ALIS_CLIPBOARD_IMAGE_LIST_DELAY','.35')))\n print('2\\t[[ binary data image/png ]]')\nelif len(sys.argv)>2 and sys.argv[1]=='decode':\n if sys.argv[2]=='3': time.sleep(.35)\n sys.stdout.buffer.write((root/('one.png' if sys.argv[2] in ('1','3') else 'two.png')).read_bytes())\nelse: sys.exit(91)\n")
    fake.chmod(0o755)
    (folder/"shell.qml").write_text(r'''
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.services.deferred
import qs.modules.abyss.content
ShellRoot {
 id:root
 Component.onCompleted:Quickshell.watchFiles=false
 function named(item,name){if(item.objectName===name)return item;for(const child of item.data ?? item.children ?? []){const result=named(child,name);if(result)return result}return null}
 property int step:0
 property int ticks:0
 function check(ok,message): bool {
  if(ok)return true
  console.error("CLIPBOARD_IMAGE_FAIL",message,"step",root.step,"rows",Cliphist.entries.length);Qt.quit();return false
 }
 FloatingWindow {
  visible:true;implicitWidth:600;implicitHeight:500;color:"#111820"
  CliphistImage {
   id:preview
   x:100;y:20
   width:implicitWidth;height:implicitHeight
   maxWidth:160;maxHeight:100
   imageDecodePath:Quickshell.env("CLIPBOARD_IMAGE_CACHE")
  }
  // Instantiate after selecting the fake backend. Its real refresh must supply
  // the row; assigning entries directly races the outstanding initial list.
  Loader {
   id:abyss;x:0;y:130;width:600;height:350
   active:root.step>=5
   sourceComponent:AbyssClipboardContent {}
  }
 }
 Timer {
  interval:80;repeat:true;running:true
  onTriggered:{
   if(++root.ticks>80){root.check(false,"decode did not settle");return}
   if(!Config.ready)return
   const image=preview.children.find(child=>child.objectName==="clipboardDecodedImage")
   if(root.step===0){
    Cliphist.cliphistBinary=Quickshell.env("CLIPBOARD_IMAGE_DECODER")
    preview.entry="1\t[[ binary data png 200 × 80 ]]";root.step++
   }else if(root.step===1 && image.status===Image.Ready){
    if(!root.check(image.implicitWidth===200 && preview.width===160 && Math.abs(preview.height-64)<.1,"spaced Unicode dimensions decode and display at bounded size"))return
    preview.entry="2\t[[ binary data image/png ]]";root.step++
   }else if(root.step===2 && image.status===Image.Ready && String(preview.source).endsWith('/2')){
    if(!root.check(image.implicitWidth===64 && image.implicitHeight===128 && preview.width>0 && preview.height===100,"dimensionless metadata uses decoded intrinsic pixels"))return
    preview.entry="3\t[[ binary data png 200x80 ]]";root.step++
   }else if(root.step===3){
    preview.entry="2\t[[ binary data png ]]";root.step++
   }else if(root.step===4 && image.status===Image.Ready && String(preview.source).endsWith('/2')){
    if(!root.check(image.implicitWidth===64 && preview.width<=160 && preview.height<=100,"reused delegate never publishes a stale image"))return
    root.step++
   }else if(root.step===5){
    const rendered=abyss.item ? root.named(abyss.item,"abyssClipboardImage") : null
    const decoded=rendered ? root.named(rendered,"clipboardDecodedImage") : null
    if(!decoded || decoded.status!==Image.Ready)return
    if(!root.check(Cliphist.entries.length===1 && Cliphist.entryId(Cliphist.entries[0])==="2","Abyss row must come from the asynchronous private history backend"))return
    if(!root.check(rendered.visible && rendered.width>0 && rendered.height>0 && decoded.implicitWidth===64,"Abyss clipboard did not display the copied image"))return
    console.info("CLIPBOARD_IMAGE_PASS native-binary Unicode-metadata intrinsic-size delegate-reuse bounded-preview Abyss-history")
    Qt.quit()
   }
  }
 }
}
''')
    env=dict(os.environ,QT_QPA_PLATFORM="offscreen",QSG_RHI_BACKEND="software",
        XDG_CONFIG_HOME=str(folder/"config"),XDG_STATE_HOME=str(folder/"state"),XDG_CACHE_HOME=str(folder/"cache"),XDG_DATA_HOME=str(folder/"data"),
        DISPLAY="",WAYLAND_DISPLAY="",NIRI_SOCKET="",
        CLIPBOARD_IMAGE_CACHE=str(folder/"images"),CLIPBOARD_IMAGE_DECODER=str(fake))
    for key in ["QS_CONFIG_NAME","QS_CONFIG_PATH","QS_MANIFEST"]:env.pop(key,None)
    result=subprocess.run(["dbus-run-session","--","qs","-p",str(folder),"--no-color"],env=env,text=True,capture_output=True,timeout=15)
    output=result.stdout+result.stderr
    bad=["CLIPBOARD_IMAGE_FAIL","ReferenceError:","TypeError:","Binding loop","Unable to assign","is not a type","unavailable"]
    if result.returncode or "CLIPBOARD_IMAGE_PASS" not in output or any(word in output for word in bad):
        print(output);raise SystemExit(1)
    for line in output.splitlines():
        if "CLIPBOARD_IMAGE_PASS" in line:print(line)
