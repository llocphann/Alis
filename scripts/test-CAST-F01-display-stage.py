#!/usr/bin/env python3
"""CAST-F01 stage 1: deterministic display identity/recovery checks; no real outputs touched."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
plan = (root / "services/DisplayModePlan.js").read_text(encoding="utf-8")
js = plan + r"""
const assert = require('node:assert/strict');

const names = ['eDP-1', 'HDMI-A-1'];
assert.equal(internalOutput(names), 'eDP-1');
assert.equal(internalOutput(['LVDS-1', 'HDMI-A-1']), 'LVDS-1');
assert.equal(internalOutput(['DSI-1', 'DP-1']), 'DSI-1');
assert.equal(internalOutput(['DP-1', 'HDMI-A-1']), '',
    'never infer the internal monitor from alphabetical output ordering');
assert.equal(internalOutput(['not-eDP-1']), '');

assert.equal(outputLabel('HDMI-A-1', {make:'LG Electronics',model:'OLED TV'}),
    'LG Electronics OLED TV (HDMI-A-1)');
assert.equal(outputLabel('DP-1', {make:'Unknown',model:''}), 'DP-1');
assert.equal(outputLabel('eDP-1', null), 'eDP-1');
assert.equal(outputLabel('HDMI-A-1', {make:'',model:'ABC'}), 'ABC (HDMI-A-1)');

assert.equal(recoveryTarget(['eDP-1'],[], 'HDMI-A-1', 'eDP-1'), 'eDP-1',
    'TV-only session may recover its known internal display after unplug');
assert.equal(recoveryTarget(names, [], 'HDMI-A-1', 'eDP-1'), '',
    'never recover while intended TV is still connected');
assert.equal(recoveryTarget(['eDP-1','DP-1'], ['DP-1'], 'HDMI-A-1','eDP-1'), '',
    'another live screen means no automatic recovery is needed');
assert.equal(recoveryTarget(['DP-1'],[], 'HDMI-A-1', 'eDP-1'), '',
    'do not power an unavailable laptop connector');
assert.equal(recoveryTarget(['eDP-1'],[], '', 'eDP-1'), '',
    'unknown former TV session must not trigger global output policy');
assert.equal(recoveryTarget(['eDP-1'],[], 'eDP-1', 'eDP-1'), '');
console.log('CAST_F01_PLAN_PASS');
"""
subprocess.run(["node", "-e", js], cwd=root, check=True)

display = (root / "services/DisplayMode.qml").read_text(encoding="utf-8")
popup = (root / "modules/abyss/content/AbyssUtilitiesPopup.qml").read_text(encoding="utf-8")
for token in (
    "_recoverAfterExternalLoss()", "DisplayPlan.recoveryTarget(",
    "DisplayPlan.internalOutput(connectedOutputs)", 'id: laptopRecovery',
    'target, "dpms=on"', 'mode === "second-only"',
):
    assert token in display, token

for token in (
    "DisplayMode.outputLabel(output)", "DisplayMode.connectedOutputs[currentIndex]",
    "DisplayMode.setMirrorTarget(outputIds[currentIndex])",
    'command: ["/bin/sh", "-c", "command -v gnome-network-displays',
    'Quickshell.execDetached(["gnome-network-displays"])',
    'visible: root.wirelessToolAvailable',
):
    assert token in popup, token

# No misleading native TV inventory or unconditional external-app launch.
assert "org.gnome.NetworkDisplays.Manager" not in popup
print("CAST_F01_SOURCE_PASS: labels, physical safety fallback, optional wireless launcher")
