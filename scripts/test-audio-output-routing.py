#!/usr/bin/env python3
"""Effects output resolution and real Audio dispatch with owned PipeWire/wpctl."""
import json, os, subprocess, tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
subprocess.run(["node", "-e", r'''
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict');
const routing=vm.createContext({});vm.runInContext(fs.readFileSync(process.argv[1],'utf8'),routing);
const node=(id,name,props={})=>({id,name,isSink:true,isStream:false,audio:{volume:.44},properties:{'node.name':name,...props}});
const ee=node(52,'easyeffects_sink',{'node.driver-id':'52','node.link-group':'ee_sink_group'});
const speaker=node(58,'speaker'),headphones=node(66,'headphones');
const tail=node(93,'ee_soe_output_level',{'node.link-group':'ee_sink_group'});tail.isStream=true;tail.isSink=false;
const nodes=[ee,speaker,headphones,tail];
let cases=0;
function resolve(defaultNode,links,names,expected){assert.equal(routing.resolveSink(defaultNode,nodes,links,names),expected);cases++}
resolve(ee,[],['speaker'],speaker);
resolve(ee,[],['headphones'],headphones);
resolve(ee,[],['missing'],ee);
resolve(ee,[],['speaker','headphones'],ee);
resolve(speaker,[],['headphones'],speaker);
resolve(null,[],['speaker'],null);
resolve(ee,[{source:tail,target:headphones}],['speaker'],headphones);
resolve(ee,[{source:tail,target:headphones},{source:headphones,target:tail}],[],headphones);
resolve(ee,[{source:tail,target:headphones},{source:tail,target:speaker}],[],ee);
resolve(ee,[{source:tail,target:headphones},{source:tail,target:speaker}],['speaker'],speaker);
resolve(ee,[{source:speaker,target:tail}],[],ee);
ee.properties['node.driver-id']='66';resolve(ee,[],['speaker'],speaker);
resolve(ee,[],[],headphones);
resolve(ee,[{source:tail,target:speaker}],[],speaker);
ee.properties['node.driver-id']='93';resolve(ee,[],['speaker'],speaker);
ee.properties['node.driver-id']='nan';resolve(ee,[],[],ee);
for(const text of ['[StreamOutputs]\noutputDevice=speaker\n','[StreamInputs]\noutputDevice=wrong\n[StreamOutputs]\r\noutputDevice="speaker"\r\n']){
 assert.equal(routing.outputDevice(text),'speaker');cases++
}
assert.equal(routing.outputDevice('[Window]\noutputDevice=wrong'),'');cases++;
console.log('AUDIO_ROUTING_PASS '+cases+' directed/idle/self-driver/ambiguous/disconnected/device-name cases');
''', str(ROOT / "modules/common/functions/audioRouting.js")], check=True)

with tempfile.TemporaryDirectory(prefix="alis-audio-routing-") as name:
    folder = Path(name)
    for entry in ["modules", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    services = folder / "services"
    services.mkdir()
    for entry in (ROOT / "services").iterdir():
        if entry.name != "Audio.qml": (services / entry.name).symlink_to(entry)
    # Only the external PipeWire dependency changes; all production facade,
    # QML tracking, file watching, queues, timers and wpctl processes execute.
    (services / "Audio.qml").write_text((ROOT / "services/Audio.qml").read_text().replace(
        "import Quickshell.Services.Pipewire", 'import "../fakepipewire"'))
    pipe = folder / "fakepipewire"
    pipe.mkdir()
    (pipe / "qmldir").write_text("singleton Pipewire 1.0 Pipewire.qml\nPwNode 1.0 PwNode.qml\nPwObjectTracker 1.0 PwObjectTracker.qml\n")
    (pipe / "PwObjectTracker.qml").write_text("import QtQuick\nQtObject { property var objects: [] }\n")
    (pipe / "PwNode.qml").write_text('''import QtQuick
QtObject {
 property int id:0
 property string name:""
 property string nickname:name
 property string description:name
 property var properties: ({"node.name":name})
 property bool isSink:true
 property bool isStream:false
 property bool ready:true
 property QtObject audio:QtObject {property real volume:.44;property bool muted:false}
}
''')
    (pipe / "Pipewire.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
 property PwNode effects:PwNode {id:ee;id:52;name:"easyeffects_sink";properties:({"node.name":name,"node.driver-id":"52","node.link-group":"ee_sink_group"})}
 property PwNode speaker:PwNode {id:sp;id:58;name:"speaker"}
 property PwNode headphones:PwNode {id:hp;id:66;name:"headphones"}
 property PwNode microphone:PwNode {id:mic;id:60;name:"microphone";isSink:false}
 property PwNode tail:PwNode {id:tailNode;id:93;name:"ee_soe_output_level";isStream:true;isSink:false;properties:({"node.link-group":"ee_sink_group"})}
 property PwNode defaultAudioSink:ee
 property PwNode defaultAudioSource:mic
 property PwNode preferredDefaultAudioSink:null
 property PwNode preferredDefaultAudioSource:null
 property var nodes:({values:[ee,sp,hp,mic,tailNode]})
 property var links:({values:[]})
}
'''.replace("property int id:", "property int nodeId:"))
    # QML reserves `id`; PwNode.id is a real PipeWire property. A fake QObject
    # must expose it as a read-only alias backed by a distinctly named member.
    node_source = (pipe / "PwNode.qml").read_text().replace("property int id:0", "property int nodeId:0\n readonly property int id:nodeId")
    (pipe / "PwNode.qml").write_text(node_source)
    pipe_source = (pipe / "Pipewire.qml").read_text()
    for value in [52,58,66,60,93]: pipe_source=pipe_source.replace("id:"+str(value)+";", "nodeId:"+str(value)+";")
    (pipe / "Pipewire.qml").write_text(pipe_source)
    binary = folder / "bin"
    binary.mkdir()
    wpctl = binary / "wpctl"
    wpctl.write_text('''#!/usr/bin/env python3
import json,os,sys,time
if sys.argv[1]=='get-volume':print('Volume: 0.44 MUTED' if sys.argv[2]=='60' else 'Volume: 0.73')
else:
 time.sleep(.08)
 with open(os.environ['AUDIO_LOG'],'a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
''')
    wpctl.chmod(0o700)
    (folder / "shell.qml").write_text(r'''
import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.services
import "fakepipewire" as Fake
ShellRoot {
 Component.onCompleted:Quickshell.watchFiles=false
 property var calls:[]
 property int sinkActivityCount:0
 Connections {target:Audio;function onSinkControlRequested(){sinkActivityCount++}}
 FileView {id:log;path:Quickshell.env("AUDIO_LOG");watchChanges:true;printErrors:false;onLoaded:calls=text().trim().split('\n').filter(Boolean).map(JSON.parse);onFileChanged:reload()}
 TestCase {
  id:test;when:false;optional:true
  function check(v,m){if(!v)throw new Error(m)}
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   Config.setNestedValue("audio.protection.enable",false)
   tryCompare(Audio,"sink",Fake.Pipewire.speaker,3000)
   check(Audio.defaultSink===Fake.Pipewire.effects && Audio.value===.44,"resolver changed processing default or read wrong volume")
   Audio.toggleMute();check(Fake.Pipewire.speaker.audio.muted && !Fake.Pipewire.effects.audio.muted,"mute did not target resolved output");Audio.toggleMute()
   for(let i=0;i<5;i++)Audio.incrementVolume()
   for(let i=0;i<3;i++)Audio.decrementVolume()
   Fake.Pipewire.defaultAudioSink=Fake.Pipewire.headphones
   Audio.incrementVolume()
   tryVerify(()=>calls.length===9,4000)
   check(sinkActivityCount>=11,"IPC volume/mute requests failed to signal OSD with a frozen PipeWire node")
   tryVerify(()=>Math.abs(Audio.osdSinkVolume-.73)<.0001,4000)
   check(Fake.Pipewire.headphones.audio.volume===.44,"sample must not overwrite hardware QML volume")
   check(calls.slice(0,8).every(call=>call[1]==="58") && calls[8][1]==="66","queued presses followed a later device selection")
   check(calls.slice(0,5).every(call=>call[2]==="2%+") && calls.slice(5,8).every(call=>call[2]==="2%-"),"burst input reordered or lost")
   Audio.setSinkVolume(.31);tryVerify(()=>calls.length===10,2000)
   check(calls[9][1]==="66" && calls[9][2]==="0.31","slider writes wrong output")
   Fake.Pipewire.defaultAudioSink=Fake.Pipewire.effects
   tryCompare(Audio,"sink",Fake.Pipewire.speaker,3000)
   Fake.Pipewire.links=({values:[{source:Fake.Pipewire.tail,target:Fake.Pipewire.headphones}]})
   tryCompare(Audio,"sink",Fake.Pipewire.headphones,2000)
   check(Audio.defaultSink===Fake.Pipewire.effects,"active links replaced effects default")
   console.info("AUDIO_DISPATCH_PASS effects idle/active, IPC OSD and read-back, mute/slider resolved, 9 ordered burst steps and stable device identity")
  }catch(e){console.error("AUDIO_DISPATCH_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: native Audio dispatch requires private Niri"); raise SystemExit(0)
        config = folder / "config/illogical-impulse"
        config.mkdir(parents=True, exist_ok=True)
        (config / "config.json").write_text((ROOT / "defaults/config.json").read_text())
        effects = folder / "config/easyeffects/db/easyeffectsrc"
        effects.parent.mkdir(parents=True)
        effects.write_text("[StreamOutputs]\noutputDevice=speaker\n")
        trace = folder / "audio.log"
        trace.write_text("")
        env.update(PATH=str(binary)+os.pathsep+env["PATH"], AUDIO_LOG=str(trace))
        result = run_qs(folder, env, timeout=16)
        log = result.stdout
        if result.returncode or "AUDIO_DISPATCH_PASS" not in log or any(word in log for word in [
                "AUDIO_DISPATCH_FAIL", "ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration"]):
            print(log); raise SystemExit(1)
        print("AUDIO_DISPATCH_PASS real QML facade/timers/wpctl: 9 burst steps retained; selected output identity and effects default preserved")
