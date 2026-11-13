#!/usr/bin/env python3
"""Regression guard for the shared loading presentation.

Loading without a label uses a rotating gear. Loading with a label uses only
animated 'Loading', without the retired morphing shape or adjacent spinner.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


gear = read("modules/common/widgets/MaterialLoadingIndicator.qml")
label = read("modules/common/widgets/LoadingText.qml")
qmldir = read("modules/common/widgets/qmldir")
locale = read("translations/en_US.json")

for token in ('text: "settings"', "RotationAnimation on rotation",
              "property bool loading: true", "property real pullProgress: 0",
              "property real implicitSize: 48", "property color color:"):
    assert token in gear, f"gear loader contract missing {token!r}"
for retired in ("MaterialShape {", "SoftBurst", "Cookie9Sided", "leapAnimation"):
    assert retired not in gear, f"retired morphing loader remains: {retired}"
assert 'text: Translation.tr("Loading")' in label
assert "SequentialAnimation on opacity" in label
assert "SequentialAnimation on scale" in label
assert "MaterialLoadingIndicator {" not in label
assert "LoadingText 1.0 LoadingText.qml" in qmldir
assert '"Loading": "Loading"' in locale

# Text-only task status; page navigation remains the separate Floating Gear.
task = read("modules/common/widgets/SettingsTaskLoadingState.qml")
assert "LoadingText {" in task
assert "MaterialLoadingIndicator {" not in task
assert "property string text:" not in task
assert "visible: root.loading && root._shown" in task
assert "root._shown = false" in task
assert "minimumVisibleTimer" not in task
assert "_hidePending" not in task
assert "Component.onCompleted:" in task

page = read("modules/common/widgets/SettingsPageLoadingOverlay.qml")
assert "MaterialLoadingIndicator {" in page
assert "LoadingText {" not in page
assert "property string text:" not in page
assert "SettingsMaterialPreset.cardColor" not in page
assert "SettingsMaterialPreset.cardRadius" not in page
assert "showDelayTimer" not in page and "_shown" not in page
assert "visible: root.loading" in page and "loading: root.loading" in page
assert 'color: "transparent"' in page
assert "border.color: SettingsMaterialPreset.accentColor" in page
assert "color: SettingsMaterialPreset.accentColor" in page
import re
ring = re.search(r"Item\s*\{\s*anchors.centerIn: parent\s*width: (\d+)\s*height: width", page)
glyph = re.search(r"MaterialLoadingIndicator\s*\{[^}]*implicitSize: (\d+)", page, re.S)
assert ring and glyph, "Floating Gear must size its ring and glyph"
assert 60 <= int(ring[1]) <= 68
assert 36 <= int(glyph[1]) * 0.8 <= 40
assert "RotationAnimation on rotation" not in page, "Ring must remain static"

host = read("modules/settings/SettingsPageHost.qml")
assert 'import "SettingsPageLoadingState.js" as PageLoadState' in host
assert "PageLoadState.shouldShow(" in host

for path, name in (
    ("settings.qml", "pagesStack"),
    ("modules/settings/SettingsFocus.qml", "pageHost"),
    ("modules/settings/SettingsOverlay.qml", "overlayPagesHost"),
):
    content = read(path)
    assert ("loading: " + name + ".loading && !" + name + ".error") in content, path
    assert ("loading: " + name + ".loading && !" + name + ".currentItem") not in content, path

# Exercise the QML-imported production policy across initial, pending, Ready,
# stale pending, Error and disabled states, not merely spelling assertions.
import subprocess
policy_test = r"""
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const context = {};
vm.createContext(context);
vm.runInContext(fs.readFileSync(process.argv[1], 'utf8'), context);
const cases = [
    ['initial pre-request', [true,2,4,true,-1,-1,0,-1,0,1], true],
    ['initial Loading', [true,2,4,true,-1,2,2,-1,0,1], true],
    ['initial Null', [true,2,4,true,-1,2,0,-1,0,1], true],
    ['initial Ready', [true,2,4,true,-1,2,1,-1,0,1], false],
    ['old Ready pending Loading', [true,3,4,true,-1,2,1,3,2,1], true],
    ['old Ready pending Null', [true,3,4,true,-1,2,1,3,0,1], true],
    ['old Ready pending Ready', [true,3,4,true,-1,2,1,3,1,1], false],
    ['request before processing', [true,3,4,true,-1,2,1,-1,0,1], true],
    ['return to current Ready', [true,2,4,true,-1,2,1,3,2,1], false],
    ['requested Error', [true,3,4,true,3,2,1,3,3,1], false],
    ['host disabled', [false,3,4,true,-1,2,1,3,2,1], false],
    ['missing source', [true,3,4,false,-1,2,1,3,2,1], false],
    ['invalid index', [true,-1,4,true,-1,2,1,-1,0,1], false]
];
const hostSource=fs.readFileSync(process.argv[2], 'utf8');
const loading=hostSource.match(/readonly property bool loading:\s*\{([\s\S]*?)\n    \}/)[1];
for (const [name, args, expected] of cases) {
    assert.equal(context.shouldShow(...args), expected, name);
    const statuses={};statuses[args[5]]=args[6];statuses[args[7]]=args[8];
    const inputs={PageLoadState:context,Loader:{Null:0,Ready:1},loadEnabled:args[0],requestedIndex:args[1],pages:Array(args[2]),
        _sourceFor:()=>args[3] ? '/test.qml' : '',_errorIndex:args[4],_currentIndex:args[5],_pendingIndex:args[7],_pageStatuses:statuses,
        _loaderFor:()=>{throw Error('Loading binding must not create/read a Loader')}};
    assert.equal(vm.runInNewContext('(function(){'+loading+'})()',inputs),expected,'host binding: '+name);
}
console.log('Settings requested-page loading policy: PASS (' + cases.length + ' cases)');
"""
subprocess.run(["node", "-e", policy_test,
                str(ROOT / "modules/settings/SettingsPageLoadingState.js"),str(ROOT / "modules/settings/SettingsPageHost.qml")], check=True)

for path in (
    "settings.qml",
    "modules/settings/SettingsFocus.qml",
    "modules/settings/SettingsOverlay.qml",
):
    content = read(path)
    assert 'text: Translation.tr("Loading page…")' not in content, path
    assert 'text: Translation.tr("Loading section…")' not in content, path

for path in (
    "modules/sidebarLeft/news/NewsView.qml",
    "modules/overview/ActionModeView.qml",
    "modules/mediaControls/components/PlayerLyrics.qml",
    "modules/waffle/notificationPopup/WNotificationItem.qml",
):
    assert "LoadingText {" in read(path), path

for path in (
    "modules/sidebarLeft/news/NewsView.qml",
    "modules/waffle/notificationPopup/WNotificationItem.qml",
    "waffleSettings.qml",
):
    assert 'Translation.tr("Loading...")' not in read(path), path

assert "BusyIndicator {" not in read("modules/overview/ActionModeView.qml")
waffle = read("waffleSettings.qml")
assert 'text: Translation.tr("Loading")' in waffle
assert "id: startupLoadingLabel" in waffle
assert "SequentialAnimation on opacity" in waffle
assert "SequentialAnimation on scale" in waffle

# Intentional icon-only activity (buffering, session login and update badge)
# must use a gear. Action-specific status/progress text stays available.
assert 'root.loginInProgress ? "settings" : "arrow_forward"' in read("dots/sddm/pixel/Main.qml")
for path in ("modules/bar/ShellUpdateIndicator.qml",
             "modules/shellUpdate/ShellUpdateOverlay.qml"):
    assert '"progress_activity"' not in read(path), path

# Preserve non-loading icons (Preview, success, errors), but never render one
# alongside a busy/loading label in the wallpaper and encoder settings.
for path in ("modules/settings/GowallWallpaperEditor.qml",
             "modules/waffle/settings/pages/WGowallPage.qml",
             "modules/settings/ToolsConfig.qml",
             "modules/wallpaperLauncher/WallpaperLauncherContent.qml"):
    content = read(path)
    assert "LoadingText {" in content, path
    assert '"progress_activity"' not in content, path

print("Shared loading presentation contracts: PASS")
