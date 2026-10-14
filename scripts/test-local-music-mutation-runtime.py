#!/usr/bin/env python3
"""Real LocalMusic Process/FileView ordering against an isolated MPD protocol."""
import json
import os
from pathlib import Path
import shlex
import socket
import tempfile
import threading
import time
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory(prefix="hadalis-music-mutation-") as name:
    folder = Path(name)
    def write(path, text):
        target = folder / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    state = {"queue": [], "song": -1, "state": "stop", "clearing": False, "errors": [], "playlists": {}}
    commands = []
    lock = threading.RLock()
    running = threading.Event()
    running.set()
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    listener.listen(12)
    listener.settimeout(.1)
    port = listener.getsockname()[1]
    def save():
        temp = folder / "server.next"
        temp.write_text(json.dumps(state))
        temp.replace(folder / "server.json")
    save()
    def reply(command):
        parts = shlex.split(command)
        cmd, args = parts[0], parts[1:]
        with lock:
            commands.append(command)
            if cmd == "clear":
                state.update(queue=[], song=-1, state="stop", clearing=True)
                save()
        if cmd == "clear":
            # Give the actual QML payload write and detached Play a bounded,
            # repeatable opportunity to race. No owner MPD is contacted.
            time.sleep(.55)
        with lock:
            if cmd == "clear":
                state["clearing"] = False
            elif cmd in ["add", "addid"]:
                state["queue"].append(args[0])
                save()
                return ["Id: " + str(len(state["queue"])-1)] if cmd == "addid" else []
            elif cmd in ["play", "playid"]:
                index = int(args[0]) if args else 0
                if not 0 <= index < len(state["queue"]):
                    error = "ACK [2@0] {play} Bad song index"
                    state["errors"].append(error); save()
                    return [error]
                state.update(song=index, state="play")
            elif cmd == "seekcur" and args == ["bad"]:
                return ["ACK [2@0] {seekcur} bad time"]
            elif cmd == "status":
                lines = ["state: " + state["state"], "playlistlength: " + str(len(state["queue"])), "elapsed: 0", "duration: 10"]
                if state["song"] >= 0: lines.append("song: " + str(state["song"]))
                return lines
            elif cmd == "config":
                return ["music_directory: " + str(folder / "music")]
            elif cmd == "playlistadd":
                state["playlists"].setdefault(args[0], []).append(args[1])
            elif cmd == "listplaylists":
                return ["playlist: " + entry for entry in state["playlists"]]
            elif cmd in ["currentsong", "playlistinfo"]:
                indices = range(len(state["queue"])) if cmd == "playlistinfo" else [state["song"]]
                lines = []
                for index in indices:
                    if 0 <= index < len(state["queue"]):
                        lines.extend(["file: " + state["queue"][index], "Title: Fixture", "duration: 10", "Pos: " + str(index), "Id: " + str(index)])
                return lines
            elif cmd in ["readpicture", "albumart"]:
                return ["ACK [50@0] {readpicture} No file exists"]
            elif cmd not in ["listallinfo", "listplaylists", "pause", "setvol", "random", "repeat", "single", "update"]:
                raise AssertionError("unexpected fixture command " + command)
            save()
            return []
    errors = []
    clients = []
    def serve(conn):
        try:
            with conn, conn.makefile("rwb", buffering=0) as stream:
                stream.write(b"OK MPD 0.24.15\n")
                while running.is_set():
                    line = stream.readline().decode().strip()
                    if not line: break
                    if line == "command_list_begin":
                        batch = []
                        while True:
                            entry = stream.readline().decode().strip()
                            if entry == "command_list_end": break
                            if not entry: raise AssertionError("truncated command batch")
                            batch.append(entry)
                        response = []
                        for entry in batch:
                            response = reply(entry)
                            if response and response[-1].startswith("ACK "): break
                    else: response = reply(line)
                    stream.write(("\n".join(response) + ("\n" if response else "") + ("" if response and response[-1].startswith("ACK ") else "OK\n")).encode())
        except (BrokenPipeError, ConnectionResetError): pass
        except BaseException as error: errors.append(error)
    def accept():
        while running.is_set():
            try: conn, _ = listener.accept()
            except socket.timeout: continue
            except OSError: break
            thread = threading.Thread(target=serve, args=(conn,), daemon=True)
            clients.append(thread); thread.start()
    thread = threading.Thread(target=accept, daemon=True)
    thread.start()
    write("qmldir", "module qs\nsingleton GlobalStates 1.0 GlobalStates.qml\n")
    write("GlobalStates.qml", '''pragma Singleton
import QtQuick
QtObject { property bool dashboardOpen:false; property bool overviewOpen:false
 property string overviewMode:"dashboard"; property int dashboardPage:0 }
''')
    write("services/qmldir", "module qs.services\nsingleton LocalMusic 1.0 LocalMusic.qml\nsingleton MprisController 1.0 MprisController.qml\n")
    write("services/LocalMusic.qml", (ROOT / "services/LocalMusic.qml").read_text())
    write("services/MprisController.qml", '''pragma Singleton
import QtQuick
QtObject {property var mpdPlayer:null;function ensureMpdMprisBridge(host,port){}}
''')
    write("modules/common/qmldir", "module qs.modules.common\nsingleton Config 1.0 Config.qml\nsingleton Directories 1.0 Directories.qml\n")
    write("modules/common/Config.qml", '''pragma Singleton
import QtQuick
import Quickshell
QtObject {property bool ready:true;property var options:({dashboard:{music:{enable:false}},sidebar:{music:{mpdHost:"127.0.0.1",mpdPort:Number(Quickshell.env("FIXTURE_PORT"))}}})}
''')
    write("modules/common/Directories.qml", '''pragma Singleton
import QtQuick
import Quickshell
QtObject {readonly property string scriptsPath:Quickshell.env("FIXTURE_ROOT")+"/bin"
 readonly property string stateUserPath:Quickshell.env("FIXTURE_ROOT")+"/state"
 readonly property string music:Quickshell.env("FIXTURE_ROOT")+"/music"}
''')
    write("modules/common/functions/qmldir", "module qs.modules.common.functions\nsingleton FileUtils 1.0 FileUtils.qml\n")
    write("modules/common/functions/FileUtils.qml", r'''pragma Singleton
import QtQuick
QtObject {function trimFileProtocol(value){return String(value).replace(/^file:\/\//,"")}}
''')
    write("bin/native-dispatch", "#!/usr/bin/python3\nimport os,sys\n"
          "if sys.argv[1:]==['backend-info']: print('mode=python\\nalis-mpdd=missing')\n"
          "elif sys.argv[1]=='mpd':\n"
          " if os.environ.get('FIXTURE_MPD_BACKEND')=='rust': os.execv(" + repr(str(ROOT / "native/target/release/alis-mpdd")) + ",[" + repr(str(ROOT / "native/target/release/alis-mpdd")) + ",'--compat']+sys.argv[2:])\n"
          " else: os.execv(sys.executable,[sys.executable," + repr(str(ROOT / "scripts/local_music_mpd.py")) + "]+sys.argv[2:])\n"
          "elif sys.argv[1]=='lyrics': print('{\"status\":\"not_found\",\"lines\":[]}')\n"
          "else: sys.exit(64)\n")
    (folder / "bin/native-dispatch").chmod(0o755)
    (folder / "state").mkdir()
    (folder / "music").mkdir()
    write("bin/fixture-fs", "#!/usr/bin/python3\nfrom pathlib import Path\nimport os,sys\n"
          "path=Path(os.environ['FIXTURE_ROOT'])/'state/local-music-queue-payload.json'\n"
          "if sys.argv[1]=='block':\n"
          " if path.exists(): path.unlink()\n"
          " path.mkdir()\n"
          "else: path.rmdir()\n")
    (folder / "bin/fixture-fs").chmod(0o755)
    write("shell.qml", r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.services
ShellRoot {
 FileView {id:server;path:Quickshell.env("FIXTURE_ROOT")+"/server.json";blockLoading:true}
 Process {id:filesystem}
 TestCase {
  id:test;when:false;optional:true
  function read(){server.reload();wait(20);return JSON.parse(server.text())}
  function check(ok,message){if(!ok)throw new Error(message)}
  function runChecks(){try{
   LocalMusic.mpdConnected=true
   const a={uri:"a.wav",path:"a.wav",title:"A"},b={uri:"b.wav",path:"b.wav",title:"B"}
   LocalMusic.playQueue([a,b],0,"Fixture")
   tryVerify(()=>read().clearing,4000)
   LocalMusic.jumpTo(1)
   wait(1800)
   const state=read()
   check(state.errors.length===0,"Play raced the pending queue payload: "+state.errors)
   check(state.song===1 && state.state==="play" && state.queue.length===2,"final playback command lost its FIFO position")
   LocalMusic._sendMpd("seekcur",["bad"])
   tryVerify(()=>LocalMusic.error.includes("bad time"),3000)
   check(LocalMusic.mpdConnected,"an ACK disconnected healthy MPD")
   LocalMusic.playQueue([a,b],0,"Next fixture")
   LocalMusic.jumpTo(1)
   LocalMusic.enqueueTrack(a,false)
   LocalMusic.enqueueTracks([b])
   tryVerify(()=>!LocalMusic.mpdMutationPending,5000)
   const next=read()
   check(next.errors.length===0 && next.queue.join(",")==="a.wav,b.wav,a.wav,b.wav" && next.song===1,
     "queue, Play, single and bulk enqueue did not preserve action order")
   filesystem.command=[Quickshell.env("FIXTURE_ROOT")+"/bin/fixture-fs","block"]
   filesystem.running=true;tryVerify(()=>!filesystem.running,2000)
   LocalMusic.playQueue([b],0,"Blocked payload")
   tryVerify(()=>!LocalMusic.mpdMutationPending && LocalMusic.error==="mpd_queue_payload_failed",3000)
   check(read().queue.join(",")==="a.wav,b.wav,a.wav,b.wav","failed payload changed the MPD queue")
   filesystem.command=[Quickshell.env("FIXTURE_ROOT")+"/bin/fixture-fs","unblock"]
   filesystem.running=true;tryVerify(()=>!filesystem.running,2000)
   LocalMusic.playQueue([b],0,"Identical retry")
   tryVerify(()=>!LocalMusic.mpdMutationPending,4000)
   check(read().queue.join(",")==="b.wav" && read().state==="play","identical payload retry failed to recover")
   LocalMusic.enqueueTracks([b]);LocalMusic.enqueueTracks([b])
   LocalMusic.createPlaylist("Fixture",[a,b]);LocalMusic.addTracksToPlaylist("Fixture",[a,b])
   tryVerify(()=>!LocalMusic.mpdMutationPending,5000)
   const saved=read()
   check(saved.queue.join(",")==="b.wav,b.wav,b.wav" && saved.playlists.Fixture.join(",")==="a.wav,b.wav,a.wav,b.wav",
     "repeated bulk/saved-playlist payloads failed or reordered")
   console.info("LOCAL_MUSIC_MUTATION_PASS queued payload then Play, command ACK visible, connection retained")
  }catch(e){console.error("LOCAL_MUSIC_MUTATION_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", FIXTURE_ROOT=str(folder), FIXTURE_PORT=str(port),
               XDG_CONFIG_HOME=str(folder / "config"), XDG_CACHE_HOME=str(folder / "cache"),
               XDG_STATE_HOME=str(folder / "state"))
    for key in ["NIRI_SOCKET", "WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE"]:
        env.pop(key, None)
    try:
        backends = ["python"]
        if os.access(ROOT / "native/target/release/alis-mpdd", os.X_OK): backends.append("rust")
        for backend in backends:
            with lock:
                state.update(queue=[],song=-1,state="stop",clearing=False,errors=[],playlists={})
                commands.clear();save()
            result = run_qs(folder, dict(env,FIXTURE_MPD_BACKEND=backend), timeout=18)
            if result.returncode or "LOCAL_MUSIC_MUTATION_PASS" not in result.stdout: break
            print("PASS: actual LocalMusic ordered Process transport via " + backend)
    finally:
        running.clear();listener.close();thread.join(timeout=1)
        for client in clients: client.join(timeout=2)
    if result.returncode or "LOCAL_MUSIC_MUTATION_PASS" not in result.stdout or errors or any(token in result.stdout for token in
            ["LOCAL_MUSIC_MUTATION_FAIL", "TypeError:", "ReferenceError:", "Binding loop", "Failed to load configuration", "Unable to assign"]):
        print(result.stdout)
        print("Fixture commands:", commands)
        print("Fixture final state:", state)
        print("Fixture errors:", errors)
        raise SystemExit("FAIL: LocalMusic queue/command ordering")
    print("PASS: real LocalMusic QML/FileView/Process ordering against isolated MPD protocol")
