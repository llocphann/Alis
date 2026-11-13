#!/usr/bin/env python3
"""Bounded transport failures leave the long-lived host usable."""
import json
import os
from pathlib import Path
import tempfile
from native_test_session import run_qs

ROOT=Path(__file__).resolve().parents[1]
source=(ROOT/'services/ColorPickerService.qml').read_text()
parent='''import QtQuick
import Quickshell
import qs.services
ShellRoot {
 property var picker:ColorPickerService
 property string ticket:""
 property int polls:0
 Component.onCompleted:{Quickshell.watchFiles=false;ticket=ColorPickerService.start()}
 Timer {interval:50;running:true;repeat:true;onTriggered:{
  if(ColorPickerService.status(ticket)==="pending"&&++parent.polls<120)return
  if(ColorPickerService.status(ticket)==="failed"&&!ColorPickerService.active&&ColorPickerService.lastError
      &&ColorPickerService.overlays.length===0)console.info("COLOR_PICKER_FAILURE_PASS")
  else console.error("COLOR_PICKER_FAILURE_FAIL",ColorPickerService.status(ticket),ColorPickerService.lastError)
  Qt.quit()
 }}
 id:parent
}'''
cases={
 'missing-executable':None,
 'wrong-ticket':{'ticket':999,'status':'picked','value':'#112233'},
 'invalid-hex':{'ticket':1,'status':'picked','value':'#abcdef'},
 'malformed-json':'{broken',
}
for name,reply in cases.items():
 with tempfile.TemporaryDirectory(prefix='alis-picker-failure-') as directory:
  folder=Path(directory)
  for entry in ('modules','GlobalStates.qml','qmldir','assets','scripts','defaults','translations'):
   (folder/entry).symlink_to(ROOT/entry)
  (folder/'services').mkdir()
  for entry in (ROOT/'services').iterdir():
   if entry.name!='ColorPickerService.qml':(folder/'services'/entry.name).symlink_to(entry)
  service=source
  if reply is None:
   service=service.replace('command: ["qs",','command: ["/__alis_missing_qs_worker__",',1)
  else:
   value=reply if isinstance(reply,str) else json.dumps(reply)
   message=json.dumps('ALIS_COLOR_PICKER_RESULT '+value)
   (folder/'color-picker-worker.qml').write_text('import QtQuick\nimport Quickshell\nShellRoot {\n Component.onCompleted:Quickshell.watchFiles=false\n Timer {interval:100;running:true;onTriggered:{console.info('+message+');Qt.quit()}}\n}')
  (folder/'services/ColorPickerService.qml').write_text(service)
  (folder/'shell.qml').write_text(parent)
  env=dict(os.environ,QT_QPA_PLATFORM='offscreen',ALIS_TEST_WAYLAND_SOCKET='/__alis_offscreen_import__',QS_DISABLE_CRASH_HANDLER='1')
  env.pop('WAYLAND_DISPLAY',None)
  result=run_qs(folder,env,timeout=10)
  if result.returncode or 'COLOR_PICKER_FAILURE_PASS' not in result.stdout or 'COLOR_PICKER_FAILURE_FAIL' in result.stdout:
   print(result.stdout);raise SystemExit('FAIL '+name)
  print('COLOR_PICKER_TRANSPORT_FAILURE_PASS',name)
