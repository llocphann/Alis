#!/usr/bin/env python3
"""Owned in-process context producer; no desktop observation or inference."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='alis-context-') as temporary:
    private=Path(temporary)
    for name in ('CompanionContext.qml','CompanionContextPolicy.js'):
        shutil.copy2(ROOT/'services'/name,private/name)
    (private/'shell.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "CompanionContextPolicy.js" as Policy
ShellRoot {
 id:root
 property double stamp:100000
 property var packets:[]
 QtObject {id:trusted}
 QtObject {id:stranger}
 CompanionContext {id:feed;owner:trusted;clock:()=>root.stamp}
 Connections {target:feed;function onFrame(packet): void {root.packets.push(JSON.parse(packet))}}
 function check(value,label): void {if(!value)throw new Error(label)}
 Timer {interval:1;running:true;onTriggered:{
  try {
   check(Policy.category("org.kde.konsole")==="terminal" && Policy.category("dev.zed.Zed")==="editor","category allowlist")
   for(const value of [null,[],"private window title","kitty --private-file", "x".repeat(1000)])
    check(Policy.category(value)==="other","unrecognized category accepted")
   check(feed.bind(trusted)===null && !feed.active && packets.length===0,"default-off generated context")
   feed.permitted=true;feed.shareFocus=true;feed.category="terminal"
   check(feed.bind(stranger)===null && packets.length===0,"foreign object authenticated")
   const first=feed.bind(trusted)
   check(first.version===1 && /^[0-9a-f]{16}$/.test(first.generation),"invalid generation")
   check(!feed.activate(stranger,first.generation) && !feed.activate(trusted,"old"),"foreign activation")
   check(feed.activate(trusted,first.generation) && packets[0].payload.category==="terminal","initial snapshot")
   feed.shareAi=true;feed.aiBusy=true;feed.synchronizeAgent()
   const token=feed.agentToken
   check(/^[0-9a-f]{16}$/.test(token),"invalid anonymous token")
   root.stamp+=1000;feed.aiWaiting=true;feed.synchronizeAgent()
   check(packets[packets.length-1].payload.word==="needs_input","wait not reduced")
   feed.finished();check(feed.agentToken===token && packets[packets.length-1].payload.word==="needs_input","approval wait became completion")
   feed.aiWaiting=false;feed.aiBusy=false
   feed.finished();check(!feed.agentToken && packets[packets.length-1].payload.word==="finished","completion")
   feed.aiBusy=true;feed.aiWaiting=false;feed.synchronizeAgent()
   feed.shareAi=false;check(!feed.agentToken && packets[packets.length-1].payload.word==="ended","AI revocation")
   feed.category="private window title";feed.publishFocus()
   check(packets[packets.length-1].payload.category==="none","invalid category leaked")
   feed.shareFocus=false;feed.publishFocus()
   check(packets[packets.length-1].payload.category==="none","focus revocation")
   feed.permitted=false
   const length=packets.length
   check(!feed.active && feed.peer===null && !feed.send("heartbeat",{}) && packets.length===length,"revoked peer retained context")
   feed.permitted=true
   const second=feed.bind(trusted)
   check(second.generation!==first.generation && !feed.activate(trusted,first.generation),"generation reused")
   check(feed.activate(trusted,second.generation),"reconnect")
   root.stamp--
   check(!feed.send("heartbeat",{}) && !feed.active,"backwards clock retained connection")
   console.info("CONTEXT_PACKETS="+JSON.stringify(packets))
   console.info("COMPANION_CONTEXT_HOST_PASS peerIdentity defaultOff typedReduction freshGeneration orderedFrames revocation clock noInference")
  }catch(e){console.error("COMPANION_CONTEXT_HOST_FAIL",e.message)}
  Qt.quit()
 }}
}
''')
    env=os.environ.copy()
    for key in ('WAYLAND_DISPLAY','NIRI_SOCKET','QS_CONFIG_NAME','QS_CONFIG_PATH','QS_MANIFEST'):env.pop(key,None)
    for kind in ('config','data','state','cache','runtime'):
        folder=private/kind;folder.mkdir(mode=0o700)
        env['XDG_'+('RUNTIME_DIR' if kind=='runtime' else kind.upper()+'_HOME')]=str(folder)
    env.update(QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QT_NO_XDG_DESKTOP_PORTAL='1')
    process=subprocess.Popen(['dbus-run-session','--','qs','-p',str(private),'--no-color'],env=env,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
    try:output,_=process.communicate(timeout=10)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGTERM);output,_=process.communicate(timeout=3)
        raise SystemExit('Context fixture timed out: '+output[-5000:])
    if process.returncode or 'COMPANION_CONTEXT_HOST_PASS' not in output or any(word in output for word in
            ('COMPANION_CONTEXT_HOST_FAIL','TypeError:','ReferenceError:','Binding loop','Unable to assign')):
        raise SystemExit(output)
    lines=[line.split('CONTEXT_PACKETS=',1)[1] for line in output.splitlines() if 'CONTEXT_PACKETS=' in line]
    frames=json.loads(lines[0]);last={}
    for frame in frames:
        assert set(frame)=={'version','generation','sequence','issuedAtMs','kind','payload'} and frame['version']==1
        generation=frame['generation'];assert frame['sequence']==last.get(generation,0)+1
        last[generation]=frame['sequence']
        fields={'focus':{'category'},'agent':{'word','token'},'heartbeat':set()}[frame['kind']]
        assert set(frame['payload'])==fields
    assert 'private window title' not in json.dumps(frames)
print('COMPANION_CONTEXT_HOST_PASS peerIdentity defaultOff typedReduction freshGeneration orderedFrames revocation clock noInference')
