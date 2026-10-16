#!/usr/bin/env python3
from pathlib import Path

r=Path(__file__).resolve().parents[1]
editor=(r/"modules/abyss/AbyssEdgeEditor.qml").read_text()
bar=(r/"modules/abyss/bar/AbyssBar.qml").read_text()
bar_module=(r/"modules/abyss/bar/AbyssBarModule.qml").read_text()
perimeter=(r/"modules/abyss/AbyssPerimeter.qml").read_text()
presentation=(r/"modules/abyss/looks/AbyssPresentation.js").read_text()

assert '"utilities","launcher"' in editor
assert 'onToggled:root.change("joinCorner",checked)' in editor
assert "popupJoinedEdge: placement?.joinCorner" in bar
assert "Shared.StyledPopup {" in bar_module
assert "hoverTarget: launcherAnchor" in bar_module
assert 'liquidPresentationKind: "launcher"' in bar_module
assert "hostedPopup?._liquidAnchor?.popupJoinedEdge" in perimeter
assert "Presentation.joinedEdge(presentationKind" in perimeter
assert '"launcher"' in presentation
assert "function canJoin(kind)" in presentation
assert "function nearbyEdge(" in presentation
assert "function joinedEdge(" in presentation

# Icon visibility is configured in Settings > Module behavior, not as a
# module action in the Edit Abyss Layout toolbar.
settings=(r/"modules/settings/BarConfig.qml").read_text()
layout=(r/"modules/abyss/looks/AbyssLayout.js").read_text()
defaults=__import__("json").loads((r/"defaults/config.json").read_text())
assert 'objectName:"abyssUnifiedModuleIconVisibility"' not in editor
assert 'root.batch("showIcon"' not in editor
assert 'objectName: "abyssSettingsQuickNotesTimersIcon"' in settings
assert 'objectName: "abyssSettingsNotificationActivityIcon"' in settings
assert 'abyss.modules.iconVisibility.notesTimers' in settings
assert 'abyss.modules.iconVisibility.notificationActivity' in settings
assert 'function withSettingsIconVisibility(placements, options)' in layout
assert 'if(["remove","locked","enabled","joinCorner"].concat(placementKeys)' in layout
assert defaults["abyss"]["modules"]["iconVisibility"] == {
    "notesTimers": None, "notificationActivity": None
}
import subprocess
subprocess.run(["node","-e",r"""
const assert=require('node:assert/strict'), fs=require('node:fs'), vm=require('node:vm');
const ctx=vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1],'utf8'),ctx);
const p=[
 {id:'notesTimers',kind:'notesTimers',edge:'bottom',position:.15,showIcon:false},
 {id:'notificationActivity',kind:'notificationActivity',edge:'bottom',position:.85,showIcon:true}
];
function resolved(opts,output='eDP-1') {
 return ctx.resolve({...opts,autoUnifiedEdgeLaunchers:false},output,[])
}
const legacy={configured:true,placements:p};
const original=resolved(legacy);
assert.equal(original.find(p=>p.kind==='notesTimers').showIcon,false);
assert.equal(original.find(p=>p.kind==='notificationActivity').showIcon,true);
const nullOverrides=resolved({...legacy,iconVisibility:{notesTimers:null,notificationActivity:null}});
assert.equal(nullOverrides[0].showIcon,false,'null preserves old hidden icons');
const changed=resolved({...legacy,iconVisibility:{notesTimers:true,notificationActivity:false}});
assert.equal(changed[0].showIcon,true);
assert.equal(changed[1].showIcon,false);
assert.equal(p[0].showIcon,false,'settings must not mutate layout records');
const perOutput=resolved({configured:true,placements:[],outputLayouts:[
 {outputName:'eDP-1',placements:p,unifiedLaunchersConfigured:true}
],iconVisibility:{notesTimers:true,notificationActivity:false}});
assert.equal(perOutput[0].showIcon,true);
assert.equal(perOutput[1].showIcon,false);
const disallowed=ctx.checkedBatch(original,['notesTimers'],'showIcon',true,1920,1200,
 {edgeThickness:16,edgeSizes:{bottom:1},size:1,gap:8},1);
assert.match(disallowed.rejected,/cannot be applied/);
console.log('unified launcher icon settings JS behavior: ok');
""",str(r/"modules/abyss/looks/AbyssLayout.js")],check=True)

print("unified launcher icon settings contract: ok")
print("launcher live-editor Join Edge follows mature source-owned popup path: ok")
