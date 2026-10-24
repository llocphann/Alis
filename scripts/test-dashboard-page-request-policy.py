#!/usr/bin/env python3
"""Execute actual navigation methods; native Loader/frame tests are separate."""
from pathlib import Path
import json
import re
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / "modules/dashboard/DashboardContent.qml").read_text()
# DASH-F01: tab sliding uses constant-speed travel. This does not measure
# frame pacing on the Owner's display; that needs separate native verification.
slide = source.split("Behavior on pagePosition {", 1)
assert len(slide) == 2, "Dashboard tab motion behavior missing"
slide = slide[1].split("DashboardCanvas {", 1)[0]
assert "duration: Appearance.animation.elementMove.duration" in slide
assert "easing.type: Easing.Linear" in slide, "Dashboard tab travel is not linear"
assert "Easing.OutCubic" not in slide, "Dashboard tab deceleration regression"
assert "root.presentationActive && Appearance.animationsEnabled && !root.editMode" in slide
methods = []
for name in ["selectPage", "requestPage", "commitPendingPage", "pageLoadFailed"]:
    match = re.search(r"    function " + name + r"\(([^)]*)\): void \{(.*?)\n    \}", source, re.S)
    assert match, name
    methods.append("root." + name + "=function(" + match[1] + "){" + match[2] + "};")
program = r'''
const vm=require('node:vm'),assert=require('node:assert/strict');
const root={pageIds:['dashboard','music','weeklyPlanner','custom-1'],navigationAllowed:true,
 _pendingPageId:'',_synchronousPageId:'',_userPageNavigation:false,pendingPageReady:false};
const GlobalStates={dashboardPageId:'dashboard',dashboardPage:0};
Object.defineProperty(root,'currentPageId',{get(){return GlobalStates.dashboardPageId}});
const context=vm.createContext({root,GlobalStates,pageIds:root.pageIds,
 PagePolicy:{defaultOrder:['dashboard','music','weeklyPlanner']},console:{warn(){}}});
'''+"vm.runInContext("+json.dumps("\n".join(methods))+",context);\n"+r'''
const old=()=>GlobalStates.dashboardPageId;
root.requestPage('music');
assert.equal(old(),'dashboard','cold request replaced the usable page before readiness');
assert.equal(root._pendingPageId,'music');
root.commitPendingPage();assert.equal(old(),'dashboard','unready target committed');
root.pendingPageReady=true;root.commitPendingPage();
assert.equal(old(),'music');assert.equal(root._pendingPageId,'');
assert.equal(GlobalStates.dashboardPage,1,'legacy numeric selection lost');
root.pendingPageReady=false;
root.requestPage('weeklyPlanner');root.requestPage('dashboard');
assert.equal(old(),'music','a later request must also wait for readiness');
assert.equal(root._pendingPageId,'dashboard','replacement request lost');
root.pendingPageReady=true;root.commitPendingPage();assert.equal(old(),'dashboard');
root.pendingPageReady=false;root.requestPage('music');root.requestPage('dashboard');
root.pendingPageReady=true;root.commitPendingPage();assert.equal(old(),'dashboard','cancelled target replayed');
root.requestPage('music');root.selectPage('weeklyPlanner');
root.commitPendingPage();assert.equal(old(),'weeklyPlanner','programmatic selection lost to an old request');
assert.equal(root._synchronousPageId,'weeklyPlanner','restoration lost synchronous loading');
root.requestPage('custom-1');root.pageLoadFailed('music');
assert.equal(root._pendingPageId,'custom-1','unrelated loader cancelled the target');
root.pageLoadFailed('custom-1');assert.equal(root._pendingPageId,'');
assert.equal(old(),'weeklyPlanner','failed loading replaced the old page');
root.requestPage('music');root.navigationAllowed=false;root.commitPendingPage();
assert.equal(root._pendingPageId,'');assert.equal(old(),'weeklyPlanner','hidden/editing state accepted a late target');
root.requestPage('custom-1');assert.equal(root._pendingPageId,'','blocked navigation accepted a request');
root.navigationAllowed=true;root.requestPage('does-not-exist');assert.equal(root._pendingPageId,'');
for(const target of root.pageIds){
 root.selectPage('dashboard');root.pendingPageReady=false;root.requestPage(target);
 assert.equal(old(),'dashboard');
 root.pendingPageReady=true;root.commitPendingPage();assert.equal(old(),target);
 assert.equal(root._pendingPageId,'');
}
console.log('DASH_PAGE_REQUEST_POLICY_PASS readiness, replacement/cancel, failure, hidden/edit and synchronous restore');
'''
subprocess.run(["node"], input=program, text=True, check=True, timeout=10)
