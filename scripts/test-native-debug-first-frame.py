#!/usr/bin/env python3
"""Capture only an owned nested output at the first Qt host frame."""
import os,re,shutil,tempfile
from pathlib import Path
from PIL import Image
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
# Native and Quickshell window declarations from the repaired active fixtures.
samples=[('Window','scripts/test-wave-visualizer-lifecycle-runtime.py'),('FloatingWindow','scripts/test-notification-settings-runtime.py')]
with tempfile.TemporaryDirectory(prefix='alis-debug-first-frame-') as name:
 folder=Path(name)
 capture_script=folder/'capture-frame.py'
 capture_script.write_text("""
from pathlib import Path
import subprocess,sys,time
from PIL import Image
path=Path(sys.argv[1])
result=subprocess.run(["niri","msg","action","screenshot-screen","--show-pointer","false","--path",str(path)])
if result.returncode:raise SystemExit(result.returncode)
# The compositor acknowledges the request before its PNG writer completes.
# Keep the Qt host alive until this process qualifies the completed image.
deadline=time.monotonic()+3
while time.monotonic()<deadline:
 try:
  with Image.open(path) as image:image.load()
  raise SystemExit(0)
 except (FileNotFoundError,OSError):time.sleep(.05)
raise SystemExit("acknowledged first-frame capture did not finish writing")
""")
 with private_wayland(folder) as env:
  if env is None:print('SKIP: first-frame debug canvas requires private Niri');raise SystemExit(0)
  for kind,path in samples:
   source=(ROOT/path).read_text();header=re.search(r'\b'+kind+r'\s*\{([\s\S]{0,220})',source).group(1)
   color=re.search(r'\bcolor\s*:\s*("[^"]+")',header).group(1)
   screenshot=folder/(kind+'.png')
   (folder/'shell.qml').write_text('''
import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
ShellRoot {
 id:root;property int frames:0
 HOST {id:host;visible:true;WIDTH:600;HEIGHT:420;color:COLOR}
 Connections {
  target:host.contentItem.Window.window
  function onFrameSwapped(){
   root.frames++
   if(root.frames===1){shot.command=["python3",Quickshell.env("CAPTURE_SCRIPT"),Quickshell.env("SHOT")];shot.running=true}
  }
 }
 Process {id:shot;onExited:(code,status)=>{if(code===0)console.info("DEBUG_FIRST_FRAME_PASS",root.frames);else console.error("DEBUG_FIRST_FRAME_FAIL",code);Qt.quit()}}
 Timer {interval:8000;running:true;onTriggered:{console.error("DEBUG_FIRST_FRAME_FAIL deadline");Qt.quit()}}
}
'''.replace('HOST',kind).replace('WIDTH','implicitWidth' if kind=='FloatingWindow' else 'width').replace('HEIGHT','implicitHeight' if kind=='FloatingWindow' else 'height').replace('COLOR',color))
   result=run_qs(folder,dict(env,SHOT=str(screenshot),CAPTURE_SCRIPT=str(capture_script)),timeout=12)
   assert result.returncode==0 and 'DEBUG_FIRST_FRAME_PASS' in result.stdout and 'DEBUG_FIRST_FRAME_FAIL' not in result.stdout,result.stdout
   assert screenshot.is_file(),'first presented frame was not captured'
   evidence=os.environ.get('ALIS_DEBUG_FRAME_EVIDENCE')
   if evidence:
    destination=Path(evidence);destination.mkdir(parents=True,exist_ok=True)
    shutil.copy2(screenshot,destination/screenshot.name)
   image=Image.open(screenshot).convert('RGB');pixels=list(image.getdata())
   white=sum(min(pixel)>220 for pixel in pixels)
   assert white/len(pixels)<.01,(kind,'white first-frame canvas',white/len(pixels))
   center=image.getpixel((image.width//2,image.height//2));assert max(center)<80,(kind,'bright initial Qt clear',center)
   print(f'DEBUG_FIRST_FRAME_PASS {kind} actual first-frame request; owned nested output white fraction {white/len(pixels):.4f}')
