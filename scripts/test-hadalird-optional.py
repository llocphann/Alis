#!/usr/bin/env python3
"""Optional host discovery, fail-closed actions and disposable QML lifecycle."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
# The wrapper exposed by Hadalis must accept SettingsTaskSection metadata even
# when the optional Hadalird package is absent: page creation precedes payload
# discovery. Regression for IntegrationsConfig.qml:38 (owner desktop log).
integration_page = (ROOT / "modules/settings/IntegrationsConfig.qml").read_text()
obsidian_wrapper = (ROOT / "modules/settings/ObsidianThemeSettings.qml").read_text()
assert 'objectName: "integrationPluginSettings"' in integration_page
assert 'Hadalird.installedPlugins.map' in integration_page
assert 'property string settingsTaskSection: ""' in obsidian_wrapper, (
    "Integrations page passes settingsTaskSection to the Hadalis-owned wrapper"
)
spec = importlib.util.spec_from_file_location("discovery", ROOT / "scripts/hadalird-status.py")
discovery = importlib.util.module_from_spec(spec)
spec.loader.exec_module(discovery)


def package_at(path):
    path.mkdir(parents=True)
    for filename in discovery.ENTRYPOINTS.values():
        target = path / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("import QtQuick\nItem {implicitHeight:32}\n")
    (path / discovery.ENTRYPOINTS["tlpSettings"]).write_text('''
import QtQuick
Item {
 objectName:"fixture-tlp-settings"
 implicitHeight:32
 property int selectedCategoryIndex:0
 readonly property var navigationCategories:[{id:"processor"},{id:"devices"}]
 function selectCategory(index){selectedCategoryIndex=index}
}
''')
    for key,tag in (("tlpRowSettings","classic"),("tlpWaffleRowSettings","waffle")):
        (path/discovery.ENTRYPOINTS[key]).write_text('import QtQuick\nItem { objectName:"fixture-'+tag+'-row";required property var definition;property bool compactProfileRows:false;property bool singleSettingGroup:false;property string groupDescription:"";implicitHeight:32 }\n')
    (path/discovery.ENTRYPOINTS["obsidianTodoSettings"]).write_text('import QtQuick\nItem {objectName:"fixture-obsidian-todo";implicitHeight:32}\n')
    common='property bool active:false;property string vaultPath:"";property bool ready:false;property bool busy:false;property var list:[];signal migrationCommitted(var payload);signal migrationFinished(bool success,var payload);'
    (path/discovery.ENTRYPOINTS["managedTodo"]).write_text('import QtQuick\nItem {'+common+'property string notePath:"";property bool preferTasksPlugin:true;property bool allowBasicOfflineMutation:true;}\n')
    (path/discovery.ENTRYPOINTS["dailyTodo"]).write_text('import QtQuick\nItem {'+common+'property string folder:"";property string noteFormat:"";property string plannerHeading:"";property int plannerHeadingLevel:2;property int defaultDurationMinutes:30;}\n')
    (path / "HadalisSession.qml").write_text('''
import QtQuick
Item {
 id:root
 required property var host
 property int operations:0
 readonly property var tlp:host.tlpEnabled ? charge : null
 readonly property var tlpSettings:host.tlpEnabled ? settings : null
 readonly property var tlpCapabilities:host.tlpEnabled ? caps : null
 readonly property var thinkfan:host.thinkfanEnabled ? fan : null
 readonly property var obsidianTheme:null
 readonly property var zettelkasten:null
 QtObject {id:charge; property bool available:true;property int currentLimit:42;function apply(){root.operations++} function refresh(){root.operations++}}
 QtObject {id:settings;property bool available:true;property var categories:[{id:"battery-care"}];signal mutationFinished(string kind,bool success);function apply(){root.operations++;return true}}
 QtObject {id:caps;property var values:({MODE:["auto"]})}
 QtObject {id:fan;property bool available:true;function applyProfile(profile){root.operations++;return true}}
 Component.onDestruction:console.info("HADALIRD_FIXTURE_DESTROYED")
}
''')
    data = {"id":"hadalird","version":"fixture","hostApi":1,"sourceSha":"a"*40,
            "session":discovery.ENTRYPOINTS["session"],
            "settings":{key:discovery.ENTRYPOINTS[entry] for key,entry in
                        (("tlp","tlpSettings"),("thinkfan","thinkfanSettings"),("obsidian","obsidianSettings"),("obsidianTodo","obsidianTodoSettings"),
                         ("tlpRow","tlpRowSettings"),("tlpWaffle","tlpWaffleSettings"),("tlpWaffleRow","tlpWaffleRowSettings"))},
            "backends":{"managedTodo":discovery.ENTRYPOINTS["managedTodo"],"dailyTodo":discovery.ENTRYPOINTS["dailyTodo"]}}
    data["files"] = {name:hashlib.sha256((path/name).read_bytes()).hexdigest() for name in discovery.ENTRYPOINTS.values()}
    (path / "manifest.json").write_text(json.dumps(data))
    return data


with tempfile.TemporaryDirectory(prefix="hadalird-host-") as name:
    private = Path(name)
    data_home = private / "data"
    assert not discovery.inspect(private, data_home)["available"]
    package = data_home / "hadalird/releases/fixture"
    manifest = package_at(package)
    (data_home / "hadalird/current").symlink_to("releases/fixture")
    assert discovery.inspect(private, data_home)["available"]
    for field, value in (("hostApi",True),("hostApi",2),("id","foreign"),("sourceSha","bad"),("session","../../foreign.qml")):
        (package / "manifest.json").write_text(json.dumps({**manifest,field:value}))
        assert not discovery.inspect(private, data_home)["available"],field
    (package / "manifest.json").write_text(json.dumps(manifest))
    original = (package / "HadalisSession.qml").read_bytes()
    (package / "HadalisSession.qml").write_text("modified")
    assert not discovery.inspect(private, data_home)["available"]
    (package / "HadalisSession.qml").write_bytes(original)
    assert discovery.inspect(private, data_home)["available"]
    for entry in ("thinkfanSettings","obsidianTodoSettings","tlpRowSettings","tlpWaffleSettings","tlpWaffleRowSettings"):
        target=package/discovery.ENTRYPOINTS[entry]
        saved=target.read_bytes();target.unlink()
        assert not discovery.inspect(private,data_home)["available"],entry+" incomplete UI accepted"
        target.write_bytes(saved)
    old_settings={key:value for key,value in manifest["settings"].items() if key in ("tlp","obsidian")}
    (package/"manifest.json").write_text(json.dumps({**manifest,"settings":old_settings}))
    assert not discovery.inspect(private,data_home)["available"],"old incomplete UI package accepted"
    (package/"manifest.json").write_text(json.dumps(manifest))
    for present in (False, True):
        shell = private / ("present" if present else "absent")
        shell.mkdir()
        for entry in ("services","modules","GlobalStates.qml","qmldir","scripts","defaults","translations","assets"):
            (shell / entry).symlink_to(ROOT / entry)
        config = shell / "config/alis"
        config.mkdir(parents=True)
        options = json.loads((ROOT / "defaults/config.json").read_text())
        options["integrations"]["hadalird"] = {key:not present for key in ("tlp","thinkfan","obsidian")}
        options["battery"]["chargeLimit"]["enable"] = False
        (config / "config.json").write_text(json.dumps(options))
        (shell / "shell.qml").write_text('''
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.settings
ShellRoot {
 id:root
 property var charge:TlpService
 property var fan:ThinkFanService
 property var settings:TlpSettingsService
 property var theme:ObsidianTheme
 property var notes:Zettelkasten
 ObsidianTodoBackend {id:managed;active:true;vaultPath:"/not-owner-vault";notePath:"Todo.md"}
 DailyNoteTodoBackend {id:daily;active:true;vaultPath:"/not-owner-vault"}
 Window {width:800;height:600;visible:true;color:"#111820"
 TlpPowerSettings {id:power;width:400;visible:false}
 ObsidianThemeSettings {width:400;visible:false}
 ObsidianTodoSettings {id:todoUi;width:400}
 TlpSettingRow {id:classicRow;width:400;definition:({key:"fixture"});compactProfileRows:true;groupDescription:"group"}

 }
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function checkCoreBattery(){
   const original=JSON.stringify(Config.options.battery)
   tryVerify(()=>findChild(power,"batteryLowWarningControl")!==null,1000)
   check(power.implicitHeight>100,"generic battery settings collapsed to a package hint")
   check(JSON.stringify(Config.options.battery)===original,"constructing core battery settings changed preferences")
   const low=findChild(power,"batteryLowWarningControl")
   const critical=findChild(power,"batteryCriticalWarningControl")
   const full=findChild(power,"batteryFullWarningControl")
   const automatic=findChild(power,"batteryAutomaticSuspendControl")
   const suspend=findChild(power,"batterySuspendThresholdControl")
   check(critical!==null && full!==null && automatic!==null && suspend!==null,"generic battery controls depend on an optional package")
   check(low.to===100 && full.to===101 && full.from===0,"battery warning bounds changed")
   low.valueModified(25);critical.valueModified(10);full.valueModified(101)
   tryCompare(Config.options.battery,"low",25,1000)
   tryCompare(Config.options.battery,"critical",10,1000)
   tryCompare(Config.options.battery,"full",101,1000)
   automatic.toggledByUser(false)
   tryCompare(suspend,"enabled",false,1000)
   automatic.toggledByUser(true)
   tryCompare(suspend,"enabled",true,1000)
   suspend.valueModified(5)
   tryCompare(Config.options.battery,"suspend",5,1000)
   Config.setNestedValue("battery.low",30)
   tryCompare(low,"value",30,1000)
  }
  function checkCoreTodo(){
   const paths=JSON.stringify(Config.options.todo.obsidian)
   Config.setNestedValue("todo.backend","obsidian")
   tryCompare(Todo,"backend","obsidian",1000)
   const button=findChild(todoUi,"hadalisTodoFallbackRestore")
   tryVerify(()=>button!==null && button.visible && button.enabled,2000)
   check(button!==null && button.visible && button.enabled,"missing integration trapped the canonical task store "+JSON.stringify({visible:button?.visible,enabled:button?.enabled,busy:Todo.internalPersistenceBusy,parentVisible:todoUi.visible,height:todoUi.height}))
   button.clicked()
   tryCompare(Todo,"backend","internal",1000)
   check(JSON.stringify(Config.options.todo.obsidian)===paths,"fallback erased saved vault/source settings")
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,4000)
   const present=Quickshell.env("HADALIRD_PRESENT")==="1"
   if(!present){
    wait(500)
    check(!Hadalird.available && !Hadalird.enabled && Hadalird.session===null,"missing package started")
    check(Config.options.integrations.hadalird.tlp,"missing package erased the saved selection")
    check(!TlpService.available && !ThinkFanService.available && !managed.ready && !daily.ready,"missing worker reported ready")
    check(!TlpSettingsService.apply() && !ThinkFanService.applyProfile("managed") && !managed.addTask("no write") && !Zettelkasten.capture("no write","no write"),"missing action reported success")
    check(TlpSettingsService.lastError.length>0 && managed.errorMessage.length>0,"missing action gave no reason")
    checkCoreBattery()
    checkCoreTodo()
   }else{
    tryCompare(Hadalird,"available",true,4000)
    check(!Hadalird.enabled && Hadalird.session===null,"installed package enabled itself")
    check(power.navigationCategories.length===0,"disabled settings retained package categories")
    checkCoreBattery()
    checkCoreTodo()
    power.selectedCategoryIndex=1
    power.visible=true
    Config.setNestedValue("integrations.hadalird.tlp",true)
    tryVerify(()=>Hadalird.session!==null,2000)
    const owned=Hadalird.session
    tryVerify(()=>power.navigationCategories.length===2,1000)
    const page=findChild(power,"fixture-tlp-settings")
    tryVerify(()=>findChild(classicRow,"fixture-classic-row")!==null,1000)
    const row=findChild(classicRow,"fixture-classic-row")
    check(row.definition.key==="fixture" && row.compactProfileRows && row.groupDescription==="group","deferred row lost required inputs")
    classicRow.definition=({key:"changed"});tryVerify(()=>row.definition.key==="changed",1000)
    Config.setNestedValue("integrations.hadalird.obsidian",true)
    tryVerify(()=>findChild(todoUi,"fixture-obsidian-todo")!==null,1000)
    todoUi.visible=false
    tryVerify(()=>findChild(todoUi,"fixture-obsidian-todo")===null,1000)
    todoUi.visible=true
    tryVerify(()=>findChild(todoUi,"fixture-obsidian-todo")!==null,1000)
    Config.setNestedValue("integrations.hadalird.obsidian",false)
    tryVerify(()=>findChild(todoUi,"fixture-obsidian-todo")===null,1000)
    tryVerify(()=>findChild(power,"batteryLowWarningControl")===null,1000)
    check(page!==null && page.selectedCategoryIndex===1,"deferred settings lost the selected category")
    power.selectedCategoryIndex=0
    tryCompare(page,"selectedCategoryIndex",0,1000)
    page.selectCategory(1)
    tryCompare(power,"selectedCategoryIndex",1,1000)
    tryCompare(TlpService,"currentLimit",42,1000)
    check(TlpSettingsService.categories[0].id==="battery-care" && TlpRuntimeCapabilities.values.MODE[0]==="auto","host lost reactive data")
    TlpService.apply();check(owned.operations===1,"charge action did not reach its sole owner")
    check(TlpSettingsService.apply() && owned.operations===2,"settings action did not reach its sole owner")
    check(!ThinkFanService.available && !ThinkFanService.applyProfile("managed") && owned.operations===2,"disabled fan reached a worker")
    Config.setNestedValue("integrations.hadalird.thinkfan",true)
    tryCompare(ThinkFanService,"available",true,1000)
    check(Hadalird.session===owned,"enabling a peer rebuilt the session")
    check(ThinkFanService.applyProfile("managed") && owned.operations===3,"fan action lost its owner")
    Config.setNestedValue("integrations.hadalird.tlp",false)
    tryCompare(TlpService,"available",false,1000)
    tryVerify(()=>power.navigationCategories.length===0,1000)
    tryVerify(()=>findChild(power,"fixture-tlp-settings")===null,1000)
    tryVerify(()=>findChild(classicRow,"fixture-classic-row")===null,1000)
    checkCoreBattery()
    check(Config.options.battery.low===30 && Config.options.battery.full===101 && Config.options.battery.suspend===5,"unloading optional settings lost battery preferences")
    TlpService.apply();check(owned.operations===3,"disabled charge leaked an action")
    Config.setNestedValue("integrations.hadalird.thinkfan",false)
    tryVerify(()=>Hadalird.session===null,2000)
    check(!Hadalird.enabled && !ThinkFanService.available,"disabled package retained a worker")
   }
   console.info("HADALIRD_HOST_PASS",present ? "present-disabled-selected-unloaded" : "absent-fail-closed")
  }catch(error){console.error("HADALIRD_HOST_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
''')
        runtime = shell / "runtime"
        runtime.mkdir(mode=0o700)
        env = dict(os.environ,QT_QPA_PLATFORM="offscreen",XDG_RUNTIME_DIR=str(runtime),
                   XDG_CONFIG_HOME=str(shell/"config"),XDG_STATE_HOME=str(shell/"state"),XDG_CACHE_HOME=str(shell/"cache"),
                   XDG_DATA_HOME=str(data_home if present else shell/"data"),HADALIRD_PRESENT="1" if present else "0")
        env.pop("NIRI_SOCKET",None)
        env.pop("HYPRLAND_INSTANCE_SIGNATURE",None)
        result = run_qs(shell,env,timeout=20)
        if result.returncode or "HADALIRD_HOST_PASS" not in result.stdout or any(token in result.stdout for token in ("HADALIRD_HOST_FAIL","TypeError:","ReferenceError:","Binding loop","Unable to assign","Failed to load configuration","Cannot assign to non-existent property","invalid context")):
            print(result.stdout)
            raise SystemExit(1)
        if present:
            assert "HADALIRD_FIXTURE_DESTROYED" in result.stdout,"session retained engine-owned singleton work"
print("HADALIRD_HOST_PASS bounded discovery/identity, absent fail-closed, installed default-off, sole-owner actions, reactive peers and unload")
