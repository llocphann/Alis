#!/usr/bin/env python3
"""CAST-F01 wired-TV audio policy and QML routing contract: no host audio changes."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
plan = (root / "services/ProjectAudioPolicy.js").read_text(encoding="utf-8")
tests = r"""
const assert=require('node:assert/strict');
const sink=(n,id,props={})=>({id,name:n,isSink:true,isStream:false,properties:{'node.name':n,...props}});
const laptop=sink('alsa_output.pci-0000_00_1f.3.analog-stereo',12);
const hdmi=sink('alsa_output.pci-0000_01_00.1.hdmi-stereo',13);
const dp=sink('alsa_output.pci-0000_01_00.1.hdmi-surround',14, {'device.profile.name':'output:hdmi-surround'});
const analogUSB=sink('alsa_output.usb-Laptop-Headset.analog-stereo',15);
const virtual=sink('easyeffects_sink',16,{'node.virtual':'true','monitor.passthrough':'true'});
const cast=sink('gnome_network_displays_12345678',17);
assert.equal(name(hdmi),'alsa_output.pci-0000_01_00.1.hdmi-stereo');
assert.equal(isTvSink(hdmi),true);
assert.equal(isTvSink(dp),true);
assert.equal(isTvSink(laptop),false);
assert.equal(isTvSink(analogUSB),false);
assert.equal(isTvSink(virtual),false);
assert.equal(isTvSink(cast),false);
assert.equal(isEffects(virtual),true);
assert.equal(chooseTvSink([laptop,hdmi,virtual,cast]),hdmi);
assert.equal(chooseTvSink([laptop,virtual,analogUSB]),null);
assert.equal(chooseTvSink([laptop,hdmi,dp]),null,'multiple digital sinks must require manual choice');
assert.equal(findByName([laptop,hdmi],name(laptop)),laptop);
assert.equal(safeToRestore(hdmi,name(hdmi),name(laptop),[laptop,hdmi]),true);
assert.equal(safeToRestore(laptop,name(hdmi),name(laptop),[laptop,hdmi]),false);
assert.equal(safeToRestore(hdmi,name(hdmi),name(laptop),[hdmi]),false);
assert.equal(safeToRestore(hdmi,name(hdmi),name(hdmi),[laptop,hdmi]),false);
console.log('CAST_F01_AUDIO_POLICY_PASS');
"""
subprocess.run(["node", "-e", plan + tests], cwd=root, check=True)

qml = (root / "services/ProjectAudio.qml").read_text()
display = (root / "services/DisplayMode.qml").read_text()
popup = (root / "modules/abyss/content/AbyssUtilitiesPopup.qml").read_text()
qmldir = (root / "services/qmldir").read_text()

for token in (
    'singleton ProjectAudio 1.0 ProjectAudio.qml',
):
    assert token in qmldir, token
for token in (
    'function beginWired(outputName)', 'function endWired()', 'function releaseOwnership()',
    'Policy.chooseTvSink(Audio.outputDevices)', 'Policy.isEffects(Audio.rawSink)',
    'Policy.safeToRestore(Audio.rawSink, _selectedName,',
    'routeProcess.command = ["wpctl", "set-default", String(id)]',
    'if (routeProcess.running) return',
):
    assert token in qml, token
for token in (
    'ProjectAudio.beginWired(_requestedExternalTarget)',
    'ProjectAudio.beginWired(externals[0])',
    'ProjectAudio.beginWired(root._runningMirrorPair.target)',
    'ProjectAudio.endWired()',
    'ProjectAudio.activeOutput',
):
    assert token in display, token
assert 'ProjectAudio.releaseOwnership()' in popup
assert 'ProjectAudio.statusMessage' in popup
assert 'Audio.setDefaultSink(device)' in popup
assert 'setDefaultSource' not in qml
assert 'restart' not in qml.lower() or 'restoreTimer.restart()' in qml
print("CAST_F01_AUDIO_SOURCE_PASS: session-scoped conservative routing")
