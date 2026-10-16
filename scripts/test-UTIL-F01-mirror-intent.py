#!/usr/bin/env python3
"""UTIL-F01 private logical fixture; never touches Niri, wl-mirror or Owner settings."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
service = (root / "services/DisplayMode.qml").read_text()
planner = (root / "services/DisplayModePlan.js").read_text()
assert "property int _mirrorIntentRevision: 0" in service
stop = service.split("function stopMirror(manual=false)", 1)[1].split("function _startMirror", 1)[0]
assert stop.index("_mirrorIntentRevision += 1") < stop.index("if (!mirrorProcess.running) return")
exit_handler = service.split("id: mirrorProcess", 1)[1].split("onExited: exitCode =>", 1)[1]
for needle in ("const revision = root._mirrorIntentRevision",
               "Qt.callLater(() => {", "DisplayPlan.mirrorRestartAllowed(revision,",
               "root._mirrorIntentRevision, root.applying,",
               "root.connectedOutputs, restart)", "root._launchMirror(restart)"):
    assert needle in exit_handler, needle
assert "mirrorPairConnected(connectedOutputs, spec)" in service
subprocess.run(["node", "-e", planner + r"""
const assert = require('node:assert/strict');
const names=['eDP-1','DP-1','HDMI-A-1'],pair={source:'eDP-1',target:'DP-1'};
assert.equal(mirrorRestartAllowed(5,5,false,names,pair),true);
assert.equal(mirrorRestartAllowed(5,6,false,names,pair),false,'superseded Stop/Apply');
assert.equal(mirrorRestartAllowed(5,5,true,names,pair),false,'new mode applying');
assert.equal(mirrorRestartAllowed(5,5,false,['eDP-1'],pair),false,'target unplugged');
assert.equal(mirrorRestartAllowed(5,5,false,['DP-1'],pair),false,'source unplugged');
assert.equal(mirrorRestartAllowed(5,5,false,names,{source:'eDP-1',target:'eDP-1'}),false);
assert.equal(mirrorRestartAllowed(5,5,false,names,null),false);
assert.equal(mirrorRestartAllowed('5',5,false,names,pair),false);
assert.equal(mirrorRestartAllowed(NaN,NaN,false,names,pair),false);
console.log('UTIL_F01_MIRROR_INTENT_PASS');
"""], cwd=root, check=True)
print("UTIL_F01_SOURCE_INTENT_PASS")
