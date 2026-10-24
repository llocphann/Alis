#!/usr/bin/env python3
"""Execute actual navigation methods; native Loader/frame tests are separate."""
from pathlib import Path
import json
import re
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / "modules/dashboard/DashboardContent.qml").read_text()
# DASH-F01: keep full-size motion monotone (no perceptible overshoot) and
# prevent transient custom page Loader creation/destruction during a slide.
slide = source.split("Behavior on pagePosition {", 1)
assert len(slide) == 2, "Dashboard tab motion behavior missing"
slide = slide[1].split("DashboardCanvas {", 1)[0]
for token in (
    "duration: Appearance.animation.elementMove.duration",
    "easing.type: Easing.BezierSpline",
    "easing.bezierCurve: Appearance.animationCurves.standard",
    "root.presentationActive && Appearance.animationsEnabled && !root.editMode",
):
    assert token in slide, f"Dashboard page transition lost {token}"
appearance = (root / "modules/common/Appearance.qml").read_text()
match = re.search(r"readonly property list<real> standard:\s*\[([^]]+)\]", appearance)
assert match, "standard curve missing"
curve = [float(v.strip()) for v in match.group(1).split(",")]
assert len(curve) == 6 and curve[4:] == [1, 1]
assert 0 <= curve[1] <= curve[3] <= 1, "Dashboard spline can overshoot"
assert "id: pageStrip" in source
assert "x: -pages.slideProgress * pages.width" in source
for token in (
    'x: root.pageIds.indexOf("dashboard") * pages.width',
    'x: root.pageIds.indexOf("music") * pages.width',
    'x:root.pageIds.indexOf("weeklyPlanner")*pages.width',
    "x: pageIndex * pages.width",
):
    assert token in source, f"Dashboard page not anchored in shared strip: {token}"
assert source.count("pages.slideProgress * pages.width") == 1, "Per-page slide update regression"
custom_loader = source.split("id: customCanvasLoader", 1)[1].split("sourceComponent: DashboardCanvas", 1)[0]
assert "customTabHost.visible" not in custom_loader, "Mid-slide passing custom page starts its Loader"
assert "root._pendingPageId === customTabHost.modelData.id" in custom_loader
assert "root._slideHeldCustomIds.includes(customTabHost.modelData.id)" in custom_loader
assert "root._slideHeldCustomIds = root._slideHeldCustomIds.concat([previousId])" in source
assert "Math.abs(pages.pagePosition - root.currentPage) < 0.001" in source
assert "onTriggered: root._slideHeldCustomIds = []" in source
assert 'property string _pageSavePendingId: ""' in source
persist = source.split("function onDashboardPageIdChanged(): void {", 1)[1]
persist = persist.split("function onDashboardPageIdChanged", 1)[0].split("    }", 1)[0]
assert "root._pageSavePendingId = id" in persist
assert 'Config.setNestedValue("dashboard.lastPageId",id)' not in persist
assert 'Config.setNestedValue("dashboard.lastPageId", id)' in source
assert "interval: 200" in source and "onTriggered: root.flushPageSelection()" in source
assert "Math.abs(pages.pagePosition - root.currentPage) < 0.001" in source
assert "root.flushPageSelection()" in source.split("onPresentationActiveChanged: {", 1)[1].split("onPageIdsChanged", 1)[0]
planner = (root / "modules/dashboard/DashboardWeeklyPlanner.qml").read_text()
assert 'function refreshFollowingToday(): void {' in planner
assert 'Qt.formatDate(root.selectedDate, "yyyy-MM-dd")' in planner
assert 'onPresentationActiveChanged: if (presentationActive) root.refreshFollowingToday()' in planner
assert 'onTodayKeyChanged: root.refreshFollowingToday()' in planner
methods = []
for name in ["selectPage", "requestPage", "commitPendingPage", "pageLoadFailed"]:
    match = re.search(r"    function " + name + r"\(([^)]*)\): void \{(.*?)\n    \}", source, re.S)
    assert match, name
    methods.append("root." + name + "=function(" + match[1] + "){" + match[2] + "};")
program = r'''
const vm=require('node:vm'),assert=require('node:assert/strict');
const root={pageIds:['dashboard','music','weeklyPlanner','custom-1'],navigationAllowed:true,
 _pendingPageId:'',_synchronousPageId:'',_userPageNavigation:false,pendingPageReady:false,
 _slideHeldCustomIds:[]};
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
root.selectPage('dashboard');
assert.ok(root._slideHeldCustomIds.includes('custom-1'),'outgoing custom page was dropped before slide');
console.log('DASH_PAGE_REQUEST_POLICY_PASS request policy, monotone easing and safe custom Loader lease');
'''
subprocess.run(["node"], input=program, text=True, check=True, timeout=10)
