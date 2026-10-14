#!/usr/bin/env python3
"""Actual QV4 payload interpreter parity and optional JSON parse measurement.

No GUI, MPD connection, artwork loading or playback is started. The two
production interpreter methods execute in typed QML objects with a private
MPRIS stub. Parsing timings are local to this synthetic payload, not shell FPS.
"""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--report-dir", type=Path)
    args = parser.parse_args()
    source = (ROOT / "services/LocalMusic.qml").read_text()
    functions = "\n".join(re.search(r"^    function " + name + r"\(.*?^    }", source, re.M | re.S)[0]
                          for name in ["_applyCurrentTrack", "_applyPayload"])
    with tempfile.TemporaryDirectory(prefix="alis-lean-qv4-") as name:
        folder = Path(name)
        (folder / "services").mkdir()
        (folder / "services/qmldir").write_text("module qs.services\nsingleton MprisController 1.0 MprisController.qml\n")
        (folder / "services/MprisController.qml").write_text("""pragma Singleton
import QtQuick
QtObject {property var calls:[];function ensureMpdMprisBridge(host,port){calls=calls.concat([[host,port]])}}
""")
        count = 10000 if args.benchmark else 96
        tracks = [{"uri": f"Album {i // 12}/track-{i}.flac", "path": f"/private-music/{i}.flac",
                   "folder": f"Album {i // 12}", "genre": "Jazz", "title": f"Song {i} ♫",
                   "artist": "Artist ß", "album": "Album", "art": "", "duration": 123.456}
                  for i in range(count)]
        full = {"connected": True, "musicRoot": "/private-music", "tracks": tracks,
                "playlists": [{"id": "mpd:list", "tracks": tracks[:3]}], "queue": tracks[:3],
                "current": tracks[0], "status": {"state": "pause", "song": "0", "elapsed": "12.3",
                "duration": "123.456", "volume": "67", "random": "1", "repeat": "1", "single": "0"},
                "folders": [{"id": "folder:Album", "tracks": tracks}]}
        lean = {k: v for k, v in full.items() if k != "folders"}
        for label, payload in [("full", full), ("lean", lean)]:
            (folder / (label + ".json")).write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
        program = r'''import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 id:root
 component Snapshot: QtObject {
  property bool mpdConnected:false
  property string error:"before"
  property string mpdHost:"private.invalid"
  property int mpdPort:6600
  property string detectedLibraryFolder:""
  property var libraryTracks:[]
  property var playlists:[]
  property var activeQueue:[]
  property string mpdState:"stop"
  property int currentIndex:-1
  property int resumeIndex:-1
  property real currentPosition:0
  property real currentDuration:0
  property real volume:.5
  property bool shuffleMode:false
  property int repeatMode:0
  property string currentUri:""
  property string currentPath:""
  property string currentTitle:""
  property string currentArtist:""
  property string currentAlbum:""
  property string currentArt:""
  __FUNCTIONS__
 }
 Snapshot {id:before}
 Snapshot {id:after}
 FileView {id:full;path:Quickshell.env("FIXTURE_ROOT")+"/full.json";blockLoading:true}
 FileView {id:lean;path:Quickshell.env("FIXTURE_ROOT")+"/lean.json";blockLoading:true}
 property int checks:0
 property var timings:[]
 property int round:0
 property var sink:null
 function check(value,message){checks++;if(!value)throw new Error(message)}
 function parity(){
  const keys=["mpdConnected","error","detectedLibraryFolder","libraryTracks","playlists","activeQueue",
    "mpdState","currentIndex","resumeIndex","currentPosition","currentDuration","volume","shuffleMode",
    "repeatMode","currentUri","currentPath","currentTitle","currentArtist","currentAlbum","currentArt"]
  for(const state of ["play","pause","stop"])for(const song of [-1,0,2,99])for(const library of [false,true]){
   const a=JSON.parse(full.text()),b=JSON.parse(lean.text())
   a.status.state=b.status.state=state;a.status.song=b.status.song=song
   if(song!==0){delete a.current;delete b.current}
   before._applyPayload(a,library);after._applyPayload(b,library)
   for(const key of keys)check(JSON.stringify(before[key])===JSON.stringify(after[key]),key+" changed")
   check(before.activeQueue===a.queue && after.activeQueue===b.queue,"queue identity changed")
   if(library)check(before.libraryTracks===a.tracks && after.libraryTracks===b.tracks,"library identity changed")
  }
  for(const a of [null,{connected:false,error:"offline"},{connected:true},{connected:true,status:{error:"decoder"}}]){
   before._applyPayload(a,true);after._applyPayload(a,true)
   for(const key of keys)check(JSON.stringify(before[key])===JSON.stringify(after[key]),"edge "+key)
  }
  const payload=JSON.parse(full.text())
  Object.defineProperty(payload,"folders",{get(){throw new Error("Unused folders was read")}})
  before._applyPayload(payload,true)
  check(true,"unused folder getter")
 }
 function measure(label){
  const text=label==="full"?full.text():lean.text()
  const start=Date.now()
  for(let i=0;i<8;i++){
   const payload=JSON.parse(text)
   if(payload.tracks.length!==__COUNT__)throw new Error("Parse result lost tracks")
   sink=payload.tracks[0].title
  }
  timings.push({round:round,mode:label,milliseconds:Date.now()-start,iterations:8})
 }
 Timer {interval:50;running:true;repeat:true;onTriggered:{try{
  if(root.round===0)root.parity()
  if(Quickshell.env("FIXTURE_BENCHMARK")==="1"){
   if(root.round%2===0){root.measure("full");root.measure("lean")}
   else{root.measure("lean");root.measure("full")}
  }
  root.round++
  if(root.round===(Quickshell.env("FIXTURE_BENCHMARK")==="1"?8:1)){
   console.info("LEAN_QML_RESULT",JSON.stringify({checks:root.checks,timings:root.timings,scope:"QV4 synthetic JSON parse and production interpreter methods; no GPU or whole-shell gain"}))
   Qt.quit()
  }
 }catch(e){console.error("LEAN_QML_FAIL",e.message,e.stack);Qt.quit()}}}
}
'''.replace("__FUNCTIONS__", functions).replace("__COUNT__", str(count))
        (folder / "shell.qml").write_text(program)
        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", FIXTURE_ROOT=str(folder),
                   FIXTURE_BENCHMARK="1" if args.benchmark else "0")
        for key in ["NIRI_SOCKET", "WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
            env.pop(key, None)
        for key in ["XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_RUNTIME_DIR"]:
            env[key] = str(folder / key)
            Path(env[key]).mkdir(mode=0o700)
        result = run_qs(folder, env, timeout=90)
        if args.report_dir:
            args.report_dir.mkdir(parents=True, exist_ok=True)
            (args.report_dir / "shell.qml").write_text(program)
            (args.report_dir / "raw.txt").write_text(result.stdout)
        assert result.returncode == 0, result.stdout
        assert not any(token in result.stdout for token in
                       ["LEAN_QML_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration"]), result.stdout
        line = next(line for line in result.stdout.splitlines() if "LEAN_QML_RESULT " in line)
        data = json.loads(line.split("LEAN_QML_RESULT ", 1)[1])
        if args.report_dir:
            (args.report_dir / "result.json").write_text(json.dumps(data, indent=2) + "\n")
        print(f"LEAN_QML_PASS {data['checks']} checks; typed interpreter state and JS array identities")


if __name__ == "__main__":
    main()
