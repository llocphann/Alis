#!/usr/bin/env python3
"""DASH-F01 custom Dashboard tabs: storage, integration and JS policy contracts.

This is source/policy qualification only. Live Quickshell and Owner acceptance
remain separate and must never be inferred from a green contract result.
"""
from pathlib import Path
import json
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
src = (root / "modules/dashboard").resolve()
policy = src / "DashboardCustomTabPolicy.js"
canvas = (src / "DashboardCanvas.qml").read_text()
content = (src / "DashboardContent.qml").read_text()
header = (src / "DashboardHeader.qml").read_text()
dialog = (src / "DashboardCustomTabDialog.qml").read_text()
settings = (root / "modules/settings/DashboardConfig.qml").read_text()
qmldir = (src / "qmldir").read_text()
config = json.loads((root / "defaults/config.json").read_text())

def check(ok, message):
    if not ok:
        raise SystemExit("DASH_F01_CONTRACT_FAIL: " + message)

dashboard = config["dashboard"]
check(dashboard["customTabs"] == [], "custom tabs must begin empty")
check(dashboard["customTabLayouts"] == [], "no custom layout should be pre-populated")
check(dashboard["inactiveMinutes"] == 0, "automatic return must be disabled by default")
check(dashboard["defaultTabId"] == "", "default selection must be opt-in")
check(dashboard["lastHiddenAtMs"] == 0, "do not invent an inactive timestamp")
check("DashboardCustomTabDialog 1.0 DashboardCustomTabDialog.qml" in qmldir, "dialog QML type missing")
check(dashboard["lastPageId"] == "dashboard", "last-tab default missing")
schema = (root / "modules/common/Config.qml").read_text()
for field in [
    "property list<var> customTabs: []",
    "property list<var> customTabLayouts: []",
    'property string defaultTabId: ""',
    "property int inactiveMinutes: 0",
    "property real lastHiddenAtMs: 0",
    'property string lastPageId: "dashboard"',
]:
    check(field in schema, "JsonAdapter schema field missing: " + field)
for part in [
    'property string customTabId: ""', 'updates["dashboard.customTabLayouts"]',
    "root.layoutOptions?.workspaceWidth", "root.layoutOptions?.workspaceHeight",
    "root.customTabId.length === 0 && g.visible !== false",
    '(Config.options?.dashboard?.canvas?.widgets ?? [])',
    'updates["dashboard.pageOrder"]',
]:
    check(part in canvas, "per-tab canvas regression: " + part)
for part in [
    "TabPolicy.tabs(", "TabPolicy.available(", "TabPolicy.errorForName(",
    "TabPolicy.selectAfterInactivity(", "customPagesRepeater.itemAt(index)",
    "customTabId: customTabHost.modelData.id",
    "onCreateTabRequested", "onRenameTabRequested", "onDeleteTabRequested",
    '"dashboard.customTabs":next', '"dashboard.customTabLayouts":layouts',
    'updates["dashboard.defaultTabId"] = "dashboard"',
    'onPageIdsChanged:', 'sessionShown()', 'sessionHidden()',
    'GlobalStates.dashboardSelectionRestored = true',
    'root.canvasController?.cancelEditMode()',
    'slideProgress: root.editMode ? root.currentPage : pagePosition',
]:
    check(part in content, "content integration missing: " + part)
check("GlobalStates.dashboardPage = -1" not in content, "legacy numeric page -1 regression")
for part in [
    'objectName: "dashboardCreateCustomTab"',
    'objectName: "dashboardRenameCustomTab"',
    'objectName: "dashboardDeleteCustomTab"',
    "root.customTabs.find(", "root.createTabRequested()",
]:
    check(part in header, "header custom-tab integration missing: " + part)
check('root.dismissRequested()' in dialog and
      'root.acceptRequested(tabNameInput.text)' in dialog, "tab modal signals missing")
check('Config.setNestedValue("dashboard.defaultTabId",id)' in settings,
      "default-tab selector not saved")
check('Config.setNestedValue("dashboard.inactiveMinutes",value)' in settings,
      "inactivity duration not saved")

# DASH-F01 regression checks: built-in widget geometry must continue using
# the actual JsonAdapter QML sequence, not Array.isArray-based fallback.
check('(Config.options?.dashboard?.canvas?.widgets ?? [])' in canvas,
      "legacy widget coordinates no longer read directly")
check('Array.isArray(root.layoutOptions?.widgets)' not in canvas,
      "QML list<var> can silently fail JS Array.isArray and reset positions")
check('(Config.options?.dashboard?.canvas?.workspaceWidth ?? 0)' in canvas,
      "legacy workspace width must remain directly reactive")
check('(Config.options?.dashboard?.canvas?.workspaceHeight ?? 0)' in canvas,
      "legacy workspace height must remain directly reactive")
check('objectName: "dashboardCustomTabActions"' in header
      and 'visible: root.pageCount > 0' in header
      and 'objectName: "dashboardCreateCustomTab"\n            visible: root.editMode' in header,
      "Create tab must be hidden outside Edit while default selection remains accessible")
check('objectName: "dashboardSetDefaultTab"' in header
      and 'onClicked: root.setDefaultTabRequested(' in header,
      "set default tab button absent in Edit Dashboard Layout")
check('Config.setNestedValue("dashboard.defaultTabId", id)' in content,
      "set default tab control is not connected to saved settings")
check('anchors.centerIn: parent' in header
      and 'anchors.left: pages.right' not in header,
      "tab actions must be centered together with indicators")
# The active dot follows the exact page-strip progress. The previous selected
# dot color toggled instantly and looked like the indicator disappeared/reappeared.
for token in (
    "property real indicatorProgress: currentPage",
    'objectName: "dashboardActivePageIndicator"',
    "root.indicatorProgress",
    "root.pageDotButtonWidth + pages.spacing",
    "color: Qt.alpha(root.colText, .35)",
):
    check(token in header, "sliding page indicator missing: " + token)
check("indicatorProgress: pages.slideProgress" in content,
      "page indicator is not synchronized to the page strip")
check("index === root.currentPage ? root.colText" not in header,
      "active page still swaps dot colors instead of moving continuously")
check('onClicked: root.createTabRequested()' in header,
      "Create button must invoke naming toolbar")
# Left-to-right in Edit: Set Default, six-dot reorder handle, page
# indicators, Create. The grip is adjacent to dots; Set Default sits left.
check('id: tabReorderHandle' in header
      and 'objectName: "dashboardTabReorderHandle"' in header
      and 'anchors.right:pages.left;anchors.rightMargin:2' in header,
      "six-dot drag handle must be immediately left of tab indicators")
check('anchors.right: tabReorderHandle.left' in header
      and 'anchors.verticalCenter: pages.verticalCenter' in header,
      "Set Default must be left of the six-dot drag handle")
check('objectName: "dashboardCreateCustomTab"' in header.split("id: customTabActions",1)[1]
      .split("id: activePageIndicator",1)[0],
      "Create Custom Tab must remain to the right of the indicators")
check('dashboardSetDefaultTab' not in header.split("id: customTabActions",1)[1]
      .split("id: activePageIndicator",1)[0],
      "Set Default must not remain in right-side custom actions")

toolbar = (src / "DashboardEditToolbar.qml").read_text()
check('visible: root.editing || root.naming' in toolbar,
      "naming toolbar must temporarily replace layout controls")
check('objectName: "dashboardToolbarTabName"' in toolbar
      and 'objectName: "dashboardToolbarCreate"' in toolbar
      and 'objectName: "dashboardToolbarCancelCreate"' in toolbar,
      "name/create/cancel controls missing from the edit toolbar position")
check('visible: !root.naming' in toolbar,
      "name input must temporarily replace layout-edit actions")
# DASH-F01: the name field must not fall back to Qt's square, bright-blue
# platform focus rectangle. Its fill, text, placeholder, focus and error
# borders must follow Alis/Abyss colors across light/dark themes.
name_field = toolbar.split('id: tabNameInput', 1)[1].split('objectName: "dashboardToolbarCreate"', 1)[0]
for token in (
    'objectName: "dashboardToolbarTabName"',
    "implicitHeight: 40",
    "leftPadding: 14",
    "rightPadding: 14",
    "radius: 12",
    'objectName: "dashboardTabNameBackground"',
    "background: Rectangle {",
    "AbyssStyle.contentLayer : Appearance.colors.colLayer1",
    "AbyssStyle.textColor : Appearance.colors.colOnLayer1",
    "AbyssStyle.textColorMuted : Appearance.colors.colSubtext",
    "AbyssStyle.accent",
    "Appearance.colors.colPrimary",
    "Appearance.colors.colOutline",
    "Appearance.colors.colError",
    "Behavior on border.color",
    "enabled: Appearance.animationsEnabled",
    'onTextEdited: root.tabController?.setCustomTabName(text)',
    'onAccepted: root.tabController?.acceptCustomTabDialog()',
):
    check(token in name_field, "themed rounded custom-tab name field lost " + token)

check('root._customDialogShown && root._customDialogMode === "delete"' in content,
      "centered dialog must only be used for destructive confirmation")
standalone = (src / "Dashboard.qml").read_text()
overview = (root / "modules/overview/OverviewDashboard.qml").read_text()
abyss = (root / "modules/abyss/AbyssDashboardEditPopup.qml").read_text()
for name, src_text in [("standalone", standalone), ("overview", overview),
                       ("abyss", abyss)]:
    check('tabController:' in src_text, name + " missing naming controller")
    check('tabNamingActive' in src_text or 'controlsVisible' in src_text,
          name + " cannot reveal naming bar")
# The Abyss Dashboard is hosted through an external popup, not via the inline
# Overview toolbar. Without this explicit bridge, clicking Create opens an
# invisible naming state and appears to do nothing on the installed shell.
abyss_host = (root / "modules/abyss/content/AbyssOverviewContent.qml").read_text()
check('readonly property var tabController: dashboardContent' in overview,
      "Overview must expose DashboardContent as its naming controller")
check('tabController: root.taskView ? null : overview.item?.tabController ?? null'
      in abyss_host,
      "Abyss external edit popup does not receive the tab naming controller")
check('tabController: root.tabController' in abyss,
      "Abyss external edit toolbar lacks the forwarded naming controller")


# Responsive canvas should never discard modules when saved geometry cannot
# fit. Display packing is non-destructive; content gets an adaptive transform.
layout = (src / "DashboardLayout.js").read_text()
check("return responsiveGrid(entries,width,height,minimums,gap)" in layout,
      "overflow still hides modules instead of rearranging the view")
check("function responsiveGrid(" in layout, "adaptive grid fallback missing")
check("function _contentComfortSize(id)" in canvas
      and "readonly property real fittingScale" in canvas,
      "module internals are not scaled to fit reduced cards")
check("case \"media\": return { width: 320, height: 390 }" not in canvas,
      "fixed module minimum sizes still clamp user resize")

node = shutil.which("node")
if node:
    js = r"""
const fs = require('fs'), vm = require('vm'), assert = require('assert');
const ctx = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), ctx);
const simple = raw => JSON.parse(JSON.stringify(ctx.tabs(raw)));
assert.deepStrictEqual(simple(null), []);
assert.deepStrictEqual(simple([{id:'bad-key',name:'Unsafe'}, {id:'custom-1',name:'Morning'},
    {id:'custom-2',name:'morning'}, {id:'custom-3',name:'Music'}]),
    [{id:'custom-1',name:'Morning'}]);
assert.equal(ctx.errorForName([], '  '), 'Tab name cannot be empty');
assert.equal(ctx.errorForName([{id:'custom-1',name:'Plans'}], 'plans'), 'A tab with this name already exists');
assert.equal(ctx.errorForName([{id:'custom-1',name:'Plans'}], 'plans','custom-1'),'');
assert.equal(ctx.nextId([{id:'custom-1',name:'A'}]), 'custom-2');
assert.deepStrictEqual(JSON.parse(JSON.stringify(ctx.available([{id:'custom-1',name:'A'}],false))),
    ['dashboard','weeklyPlanner','custom-1']);
const pages=['dashboard','music','custom-1'], now=2000000000000, hidden=now-300000;
assert.equal(ctx.selectAfterInactivity(now,hidden,0,'custom-1',pages,'music'),'music');
assert.equal(ctx.selectAfterInactivity(now,hidden,6,'custom-1',pages,'music'),'music');
assert.equal(ctx.selectAfterInactivity(now,hidden,5,'custom-1',pages,'music'),'custom-1');
assert.equal(ctx.selectAfterInactivity(now,hidden,5,'removed',pages,'music'),'dashboard');
assert.equal(ctx.selectAfterInactivity(now,0,5,'custom-1',pages,'music'),'music');
assert.equal(ctx.selectAfterInactivity(hidden-1,hidden,5,'custom-1',pages,'music'),'music');
assert.equal(ctx.selectAfterInactivity(now,hidden,5,'custom-1',pages,'missing'),'custom-1');
console.log('DASH_F01_POLICY_PASS');
"""
    result = subprocess.run([node,"-e",js,str(policy)],capture_output=True,text=True)
    check(result.returncode == 0 and "DASH_F01_POLICY_PASS" in result.stdout,
          "policy runtime failed: " + result.stdout + result.stderr)
    layout_js = r"""
const fs=require("fs"),vm=require("vm"),assert=require("assert");
const ctx=vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[1],"utf8"),ctx);
const defaults=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
const entries=defaults.dashboard.canvas.widgets;
const shown=entries.filter(e=>e.visible!==false);
const min=Object.fromEntries(entries.map(e=>[e.id,{width:36,height:32}]));
for(const [width,height] of [[1920,1050],[1440,820],[1120,730],
                            [980,620],[650,450],[360,220]]) {
    const saved=JSON.stringify(entries);
    const result=ctx.project(entries,width,height,min,10,{width:0,height:0});
    assert.equal(result.overflow.length,0,"overflow at "+width+"x"+height);
    assert.equal(Object.keys(result.rects).length,shown.length,"lost module");
    assert.equal(JSON.stringify(entries),saved,"projection mutated saved layout");
    const rects=Object.values(result.rects);
    for(let i=0;i<rects.length;i++) {
        const a=rects[i];
        assert(a.x>=-0.01&&a.y>=-0.01
          &&a.x+a.width<=width+.01&&a.y+a.height<=height+.01,
          "out of bounds");
        for(let j=i+1;j<rects.length;j++)
            assert(!ctx.overlaps(a,rects[j],0),"module overlap");
    }
}
const single=[{id:"notes",x:.1,y:.2,w:.55,h:.45,visible:true}];
const projected=ctx.project(single,1280,720,{notes:{width:36,height:32}},10,{});
assert(Math.abs(projected.rects.notes.width/1280-.55)<.001);
assert(Math.abs(projected.rects.notes.height/720-.45)<.001);
console.log("DASH_F01_RESPONSIVE_PASS");
"""
    result = subprocess.run([node,"-e",layout_js,str(src/"DashboardLayout.js"),
                             str(root/"defaults/config.json")],
                            capture_output=True,text=True)
    check(result.returncode == 0 and "DASH_F01_RESPONSIVE_PASS" in result.stdout,
          "responsive layout policy failed: " + result.stdout + result.stderr)
else:
    print("DASH_F01_POLICY_SKIP: node unavailable")
print("DASH_F01_CONTRACT_PASS: edit-mode controls, default tab, responsive geometry and timeout")
