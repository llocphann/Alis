#!/usr/bin/env python3
"""UTIL-F01 source delivery contract: read-only; physical device gates remain Owner-only."""
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
def source(name):
    return (repo / name).read_text(encoding="utf-8")
def requires(path, *tokens):
    text = source(path)
    for token in tokens:
        assert token in text, f"{path}: missing {token}"

popup = "modules/abyss/content/AbyssUtilitiesPopup.qml"
requires(popup,
    'readonly property var pageTitles:', '"Monitor arrangement", "Display mode", "Sound", "Eye protection"',
    'SwipeView {', 'interactive: true', 'active: Math.abs(SwipeView.index - pages.currentIndex) <= 1',
    'model: pages.count', 'TapHandler {', 'pages.currentIndex = parent.index',
    'embeddedArrangementOnly: true', 'activeSection: "outputs"',
    'onClicked: DisplayMode.apply("extend")',
    'onClicked: DisplayMode.apply("primary-only")',
    'onClicked: DisplayMode.apply("second-only")',
    'DisplayMode.setMirrorSource(DisplayMode.connectedOutputs[currentIndex])',
    'DisplayMode.setMirrorTarget(outputIds[currentIndex])',
    'DisplayMode.stopMirror(true)', 'DisplayMode.apply("mirror")',
    'CompositorService.isNiri && !DisplayMode.applying',
    'Audio.outputDevices.map', 'Audio.inputDevices.map',
    'Audio.setDefaultSink(device)', 'Audio.setDefaultSource(device)',
    'Audio.setSinkVolume(value)', 'Audio.setSourceVolume(value)',
    'Audio.toggleMute()', 'Audio.toggleMicMute()',
    'NightLightDialog {', 'embeddedPresentation: true')
requires("modules/settings/MonitorVisibilityConfig.qml",
    'property bool embeddedArrangementOnly: false',
    'objectName: "monitorArrangementCanvas"',
    'function commitMonitorPosition(', 'monitorLayoutBusy',
    'monitorPositionFinished(outputName, false)')
requires("services/DisplayMode.qml",
    'nativeDispatchPath', 'function _actionFailed(detail)',
    'DisplayPlan.restore(', 'function stopMirror(',
    '_pendingMirrorRestart', 'mirrorPairConnected(connectedOutputs, spec)')
requires("services/Audio.qml",
    'readonly property PwNode rawSink: Pipewire.defaultAudioSink',
    'property PwNode source: Pipewire.defaultAudioSource',
    'function setDefaultSink(node)', 'function setDefaultSource(node)',
    'function setSinkVolume(target: real)', 'function setSourceVolume(target: real)')
requires("modules/sidebarRight/nightLight/NightLightDialog.qml",
    'id: nightLightPrimaryToggles', 'id: antiFlashbangPrimaryToggles',
    'Hyprsunset.toggle(checked)', 'light.antiFlashbang.enable',
    'component EmbeddedSliderRow: RowLayout')
requires("services/Hyprsunset.qml",
    'function reEvaluate()', 'function _nextScheduleBoundaryMs()',
    'property bool _pendingDisable: false', 'id: backendStopProc')
requires("services/antiFlashbangPolicy.js",
    'function multiplier(', 'function bounded(')
print("UTIL_F01_SOURCE_DELIVERY_PASS: display, audio, eye-protection, navigation")
