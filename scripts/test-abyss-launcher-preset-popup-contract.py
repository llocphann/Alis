#!/usr/bin/env python3
from pathlib import Path
import json,re,subprocess

r = Path(__file__).resolve().parents[1]
bar_module = (r / "modules/abyss/bar/AbyssBarModule.qml").read_text()
bar = (r / "modules/abyss/bar/AbyssBar.qml").read_text()
styled = (r / "modules/bar/StyledPopup.qml").read_text()
perimeter = (r / "modules/abyss/AbyssPerimeter.qml").read_text()
content = (r / "modules/abyss/content/AbyssLauncherControlsPopup.qml").read_text()

assert "Shared.StyledPopup {" in bar_module
assert 'liquidPresentationKind: "launcher"' in bar_module
assert "hoverTarget: launcherAnchor" in bar_module
assert 'root.hoverRequest("launcher")' not in bar_module
assert "property string liquidPresentationKind" in styled
assert "hostedPopup?.liquidPresentationKind" in perimeter

assert "popupJoinedEdge: placement?.joinCorner" in bar
assert "hostedPopup?._liquidAnchor?.popupJoinedEdge" in perimeter

# Launcher stays on the existing compact segmented-control primitive.
# Each section is one horizontal row: icons stay visible for every option and
# only the selected mode/preset exposes its label.
assert 'text: Translation.tr("Surface Performance")' in content
assert 'text: Translation.tr("Wave Preset")' in content
assert "component CompactChoice: SelectionGroupButton" in content
assert 'buttonText: selected ? labelText : ""' in content
assert "buttonIcon: iconName" in content
assert "toggled: selected" in content
assert content.count("RowLayout {") >= 2
assert content.count("Layout.alignment: Qt.AlignLeft") >= 4
assert "Layout.alignment: Qt.AlignHCenter" not in content
assert "color: Appearance.colors.colLayer0Border" in content
assert "opacity: 0.65" in content
assert "WindowDialogSeparator" not in content
assert "implicitWidth: Math.ceil(contentColumn.implicitWidth)" in content
assert "width: parent.width" not in content
assert "implicitHeight: 34" in content
assert "AbyssButton" not in content
assert "import qs.services" in content

# Run the actual QML method bodies with a recorded Config boundary. Manual
# quality must leave Aqua's policy alone and turn off automatic Abyss quality;
# wave selection must persist every preset value without changing enablement.
methods={}
for method in ['applyQuality','applyWavePreset']:
 match=re.search(r'function '+method+r'\(value\):\s*void\s*\{([\s\S]*?)\n    \}',content)
 assert match,method
 methods[method]=match.group(1)
subprocess.run(['node','-e',r'''
const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const methods=JSON.parse(process.argv[1]),Wave=vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2],'utf8').replace(/^\.pragma.*$/mg,''),Wave);
let changes=[];
const Config={setNestedValues:updates=>changes.push(JSON.parse(JSON.stringify(updates)))};
const context=vm.createContext({Config,Wave});
for(const [name,body] of Object.entries(methods))vm.runInContext('function '+name+'(value){'+body+'}',context);
for(const quality of ['performance','balanced','quality']) {
 changes=[];context.applyQuality(quality);
 assert.deepEqual(changes,[{'abyss.quality':quality,'abyss.autoQuality':false}]);
}
for(const preset of ['calm','balanced','fluid','deep']) {
 changes=[];context.applyWavePreset(preset);
 const expected={'abyss.waves.preset':preset};
 for(const [key,value] of Object.entries(Wave.presets[preset]))expected['abyss.waves.'+key]=value;
 assert.deepEqual(changes,[expected]);assert(!('abyss.waves.enabled' in changes[0]));
}
''',json.dumps(methods),str(r/'modules/abyss/looks/AbyssWave.js')],check=True)

print("abyss launcher mature-popup + text/icon contract: ok")
