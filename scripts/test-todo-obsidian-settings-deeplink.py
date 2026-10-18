#!/usr/bin/env python3
"""Guard unified To-do and Quick Notes Settings deep links from dashboard surfaces."""

from pathlib import Path
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]
states = (ROOT / "GlobalStates.qml").read_text(encoding="utf-8")
services = (ROOT / "modules" / "settings" / "ServicesConfig.qml").read_text(encoding="utf-8")
integrations = (ROOT / "modules" / "settings" / "IntegrationsConfig.qml").read_text(encoding="utf-8")
registry = (ROOT / "modules" / "settings" / "SettingsPageRegistryData.qml").read_text(encoding="utf-8")
overlay = (ROOT / "modules" / "settings" / "SettingsOverlay.qml").read_text(encoding="utf-8")
focus = (ROOT / "modules" / "settings" / "SettingsFocus.qml").read_text(encoding="utf-8")
window = (ROOT / "settings.qml").read_text(encoding="utf-8")

for token in (
    'property string settingsOverlayRequestedSection: ""',
    "function openSettingsSection(index: int, section: string): void",
    '"QS_SETTINGS_SECTION=" + targetSection',
):
    assert token in states, f"missing settings deep-link contract: {token}"

assert 'Quickshell.env("QS_SETTINGS_SECTION")' in window
assert "function activateSettingsSearchSection(section: string): bool" in services
assert overlay.count("if (requestedPage < 0)") >= 1
assert focus.count("if (requestedPage < 0)") >= 1
assert 'label.includes("todo") || label.includes("to-do") || label.includes("obsidian")' in services
assert 'SettingsPageRegistry.navigateToKey("integrations",section)' in services
assert re.search(r'settingsPageIndex:\s*38\b', integrations)
assert '"obsidian"' in integrations and '"calendar"' in integrations

assert 'pageIndex: 38, pageName: root.pages[38].name' in registry
assert 'section: Translation.tr("To-do & Quick Notes")' in registry
assert '"quick notes"' in registry and '"vault"' in registry

for name, source in (("rail", overlay), ("focus", focus)):
    assert "settingsOverlayRequestedSection" in source, f"{name} overlay lost section deep link"
    assert "consumeSettingsDeepLink" in source, f"{name} overlay lost deep-link consumer"

subprocess.run(["node", "-e", r'''
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync(process.argv[1],'utf8');
const body=source.match(/function navigateToKey\([^)]*\):\s*bool\s*\{([\s\S]*?)\n    \}/)[1];
for(const abyssFamily of [true,false]){
 const events=[];
 const root={abyssFamily,pageIndexForKey:key=>({services:7,system:1,integrations:38,bar:34,'shell-layout':2}[key] ?? -1),navigateRequested:(...args)=>events.push(args)};
 const policy=vm.createContext({});
 vm.runInContext(fs.readFileSync(process.argv[2],'utf8').replace(/^\.pragma library\s*$/m,''),policy);
 const context=vm.createContext({root,FamilyPolicy:policy,Config:{options:{panelFamily:abyssFamily?'abyss':'waffle'}}});
 const navigate=vm.runInContext('(function(key,section){'+body+'})',context);
 for(const section of ['Todo','To-do & Quick Notes','Obsidian vault','Zettelkasten','Quick Notes','Calendar Sync','SERVICES · OBSIDIAN']){
  assert.equal(navigate('services',section),true);assert.deepEqual(events.pop(),[38,section]);
 }
 for(const section of ['Data','Weather','System','Network','Updates','']){
  assert.equal(navigate('services',section),true);assert.deepEqual(events.pop(),[7,section]);
 }
 for(const section of ['Thinkfan','Fan Control','TLP','Cooling','Thermal']){
  assert.equal(navigate('system',section),true);assert.deepEqual(events.pop(),[38,section]);
 }
 for(const section of ['Audio','Power','Battery','Input']){
  assert.equal(navigate('system',section),true);assert.deepEqual(events.pop(),[1,section]);
 }
 assert.equal(navigate('integrations','Calendar Sync'),true);assert.deepEqual(events.pop(),[38,'Calendar Sync']);
 assert.equal(navigate('missing','Obsidian'),false);assert.equal(events.length,0);
}
console.log('Moved Services deep links: PASS (legacy Services/System routes, missing targets and both families)');
''', str(ROOT / "modules/settings/SettingsPageRegistry.qml"), str(ROOT / "modules/common/PanelFamilyPolicy.js")], check=True)
print("Todo/Obsidian settings deep-link contract: PASS")
