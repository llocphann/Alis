#!/usr/bin/env python3
"""Roundtrip real CLI argv through Quickshell's typed IPC argument parser."""
import os
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-music-ipc-") as directory:
    folder = Path(directory)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
 id:root
 property int index:0
 property var cases:[[],["/tmp/A #.wav"],["/tmp/Unicode 音楽.flac","file:///tmp/encoded%20path.wav","/tmp/'literal`$(not-a-command)'.ogg"]]
 property var expected:[]
 IpcHandler {
  target:"dashboard"
  // A real string parameter verifies transport independently of LocalMusic's
  // own processing. This fixture never accesses MPD or any real audio files.
  function openMusic(payload:string):string{return payload}
 }
 function next(){
  if(index===cases.length){console.info("LOCAL_MUSIC_IPC_PASS",index);Qt.quit();return}
  expected=cases[index]
  client.command=[Quickshell.env("CLI_PATH"),"local-music","--config",Quickshell.shellDir,"--"].concat(expected)
  client.running=true
 }
 Process {
  id:client
  stdout:StdioCollector{id:output}
  stderr:StdioCollector{id:errors}
  onExited:(code,status)=>{
   try{
    if(code!==0)throw new Error("CLI exit "+code+": "+errors.text)
    const decoded=JSON.parse(output.text.trim())
    if(JSON.stringify(decoded)!==JSON.stringify(root.expected))throw new Error("argv changed "+output.text)
    root.index++;Qt.callLater(root.next)
   }catch(e){console.error("LOCAL_MUSIC_IPC_FAIL",e.message);Qt.quit()}
  }
 }
 Timer{interval:200;running:true;onTriggered:root.next()}
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", CLI_PATH=str(ROOT / "scripts/alis"))
    result = run_qs(folder, env, timeout=20)
    print(result.stdout)
    assert result.returncode == 0 and "LOCAL_MUSIC_IPC_PASS 3" in result.stdout
    assert "LOCAL_MUSIC_IPC_FAIL" not in result.stdout
