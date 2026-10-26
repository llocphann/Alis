#!/usr/bin/env python3
"""Private pointer navigation and deep links on the actual Settings chrome."""
import json,tempfile
from pathlib import Path
from native_test_session import private_wayland,run_qs
ROOT=Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='hadalis-settings-hierarchy-') as name:
 folder=Path(name)
 for entry in ['modules','services','GlobalStates.qml','qmldir','assets','scripts','defaults','translations','settings.qml','waffleSettings.qml']:(folder/entry).symlink_to(ROOT/entry)
 vault=folder/'vault/.obsidian';vault.mkdir(parents=True)
 (vault/'appearance.json').write_text(json.dumps({'cssTheme':'Border','enabledCssSnippets':['user-snippet'],'ownerSetting':42}))
 (folder/'shell.qml').write_text(r"""
import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.settings
import qs.services
Window {
 id:root;visible:true;width:1120;height:820;color:"#111820"
 property int frames:0
 Component.onCompleted:Quickshell.watchFiles=false
 Item {id:host;anchors.fill:parent}
 SettingsOverlay {id:overlay;embeddedHost:host;settingsOpen:true}
 TestCase {
  id:test;when:false;optional:true
  function check(value,message){if(!value)throw new Error(message)}
  function find(item,name){if(!item)return null;if(item.objectName===name)return item;for(const child of item.children ?? []){const result=find(child,name);if(result)return result}return null}
  function clickNavigation(name){
   tryVerify(()=>find(host,name)!==null,5000)
   const before=root.frames
   check(host.grabToImage(image=>root.frames++),"navigation frame request failed")
   tryVerify(()=>root.frames>before,2500)
   const button=find(host,name)
   check(button && button.width>0 && button.height>0 && button.enabled,"navigation button unavailable: "+name)
   mouseClick(button,button.width/2,button.height/2)
  }
  function runChecks(){try {
   tryCompare(Config,"ready",true,4000)
   tryCompare(Persistent,"ready",true,4000)
   tryCompare(overlay,"_navigationInitialized",true,4000)
   Config.setNestedValues({"panelFamily":"abyss","performance.reduceAnimations":true})
   tryVerify(()=>find(host,"settingsNav_abyss")!==null,8000)
   overlay.navGroup="";wait(100)
   check(overlay.visibleNavItems.length===overlay.navPageOrder.length,"single-level sidebar did not expose all ordered pages")
   check(!overlay.visibleNavItems.some(item=>Boolean(item.back || item.groupKey)),"single-level sidebar retained nested folder or back rows")
   clickNavigation("settingsNav_abyss");wait(180)
   check(overlay.overlayCurrentPage===2,"Abyss page changed its numeric route: "+overlay.overlayCurrentPage)
   clickNavigation("settingsNav_abyss-modules");wait(180)
   check(overlay.overlayCurrentPage===34,"Bar modules page changed its numeric route: "+overlay.overlayCurrentPage)
   check(SettingsPageRegistry.navigateToKey("integrations","Calendar Sync"),"integration deep link is unreachable")
   tryVerify(()=>overlay.pageHost?.currentIndex===38 && overlay.pageHost?.currentItem?.activeSection==="calendar",7000)
   check(SettingsPageRegistry.navigateToKey("modules","Modules"),"legacy Modules route is unreachable")
   tryVerify(()=>overlay.pageHost?.currentIndex===34 && overlay.pageHost?.currentItem?.activeSection==="modules",7000)
   check(SettingsPageRegistry.navigateToKey("modules","panels"),"Shell availability route is unreachable")
   tryVerify(()=>overlay.pageHost?.currentIndex===10 && overlay.pageHost?.currentItem?.settingsTaskNavigator!==null,7000)
   const modulePage=overlay.pageHost.currentItem
   check(!modulePage.settingsTaskNavigator.options.some(option=>option.value==="modules"),
         "Abyss retained an empty redirect-only Modules sub-tab")
   modulePage.activeSection="modules"
   check(modulePage.activeSection==="panels","old module selection exposes an empty tab")
   Config.setNestedValue("panelFamily","waffle");wait(100)
   check(modulePage.settingsTaskNavigator.options.some(option=>option.value==="modules"),
         "Waffle lost its real module controls")
   modulePage.activeSection="modules"
   check(modulePage.activeSection==="modules","Waffle module selection was incorrectly redirected")
   Config.setNestedValue("panelFamily","abyss");wait(100)
   check(modulePage.activeSection==="panels","family switch retained the empty Abyss module tab")
   check(SettingsPageRegistry.navigateToKey("services","To-do & Quick Notes"),"legacy Services deep link is unreachable")
   tryVerify(()=>overlay.pageHost?.currentIndex===38 && overlay.pageHost?.currentItem?.activePlugin==="management",7000)
   overlay.pageHost.currentItem.activateSettingsSearchSection("To-do & Quick Notes")
   check(overlay.pageHost.currentItem.activePlugin==="management","legacy data search lost its destination")
   Config.setNestedValues({"todo.obsidian.vaultPath":Quickshell.env("OBSIDIAN_VAULT"),"integrations.obsidian.autoTheme":true})
   // Actual theme apply/restore and vault fields belong to Hadalird's native
   // suite. Core navigation must work without activating a missing package.
   check(!Hadalird.obsidianEnabled && !ObsidianTheme.enabled && !ObsidianTheme.busy,
         "missing optional integration activated a worker")
   overlay.navEditMode=true;wait(100)
   check(overlay.visibleNavItems.length===overlay.navPageOrder.length,"navigation editor lost full page order")
   overlay.navEditMode=false;overlay.settingsOpen=false;wait(200)
   const component=Qt.createComponent("settings.qml")
   check(component.status===Component.Ready,"standalone Settings could not compile: "+component.errorString())
   const standalone=component.createObject(null)
   check(standalone!==null,"standalone Settings could not open")
   tryVerify(()=>standalone.navPageOrder.length>0,3000)
   standalone.currentPage=38;wait(350)
   check(standalone.navGroup==="apps" && standalone.pages[38].key==="integrations","standalone does not share hierarchy and routes")
   standalone.destroy()
   Config.setNestedValue("panelFamily","waffle")
   const wc=Qt.createComponent("waffleSettings.qml")
   check(wc.status===Component.Ready,"Waffle Settings could not compile: "+wc.errorString())
   const waffle=wc.createObject(null);check(waffle!==null,"Waffle Settings could not open")
   waffle.currentPage=19
   tryCompare(Persistent,"ready",true,3000)
   tryCompare(waffle,"_navigationInitialized",true,3000)
   waffle.currentPage=19
   tryVerify(()=>find(waffle.contentItem,"waffleIntegration")!==null,5000)
   const integration=find(waffle.contentItem,"waffleIntegration")
   integration.activateSettingsSearchSection("Calendar Sync")
   check(integration.settingsPageIndex===19 && integration.activeSection==="calendar","Waffle integration changed old numeric routes")
   waffle.destroy()
   console.info("SETTINGS_HIERARCHY_NATIVE_PASS pointer-parent child Back deep-link legacy-search edit-order standalone")
  }catch(e){console.error("SETTINGS_HIERARCHY_NATIVE_FAIL",e.message,e.stack)}Qt.quit()}
 }
 Timer {interval:100;running:true;onTriggered:test.runChecks()}
}
""")
 with private_wayland(folder) as env:
  if env is None:print('SKIP: Settings native navigation requires private Niri');raise SystemExit(0)
  conf=folder/'config/alis';conf.mkdir(parents=True,exist_ok=True)
  value=json.loads((ROOT/'defaults/config.json').read_text());value['panelFamily']='abyss';(conf/'config.json').write_text(json.dumps(value))
  env.update(QT_QUICK_BACKEND='software',OBSIDIAN_VAULT=str(vault.parent))
  result=run_qs(folder,env,timeout=40);output=result.stdout
  if result.returncode or 'SETTINGS_HIERARCHY_NATIVE_PASS' not in output or any(e in output for e in ['SETTINGS_HIERARCHY_NATIVE_FAIL','ReferenceError:','TypeError:','Unable to assign','Binding loop','Failed to load configuration']):print(output);raise SystemExit(1)
  final=json.loads((vault/'appearance.json').read_text());assert final=={'cssTheme':'Border','enabledCssSnippets':['user-snippet'],'ownerSetting':42},'core changed a vault without its optional integration'
  for line in output.splitlines():
   if 'SETTINGS_HIERARCHY_NATIVE_PASS' in line:print(line)
