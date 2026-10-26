#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
runtime_root="$(cd -- "$script_dir/.." && pwd)"
service="$runtime_root/services/deferred/EqualizerService.qml"
backend="$runtime_root/services/deferred/EasyEffects.qml"
helper="$runtime_root/scripts/equalizer-control.sh"
panel="$runtime_root/modules/mediaControls/EqualizerPanel.qml"
player="$runtime_root/modules/mediaControls/PlayerControl.qml"

python3 - "$service" "$backend" "$helper" "$panel" "$player" <<'PY'
import pathlib
import sys

service = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
backend = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
helper = pathlib.Path(sys.argv[3]).read_text(encoding="utf-8")
panel = pathlib.Path(sys.argv[4]).read_text(encoding="utf-8")
player = pathlib.Path(sys.argv[5]).read_text(encoding="utf-8")

def require(text: str, token: str, source: str) -> None:
    if token not in text:
        raise SystemExit(f"FAIL: {source} missing contract token: {token}")

def forbid(text: str, token: str, source: str) -> None:
    if token in text:
        raise SystemExit(f"FAIL: {source} contains retired/unsafe token: {token}")

# Deferred lifecycle: Media presentation is still the only consumer.
for token in (
    "property bool enabled: false",
    "function registerConsumer()",
    "function unregisterConsumer()",
    "target: root.enabled ? EasyEffects : null",
    "EasyEffects.fetchAvailability()",
    "function startBackend()",
    "function _startTransportProbe()",
    "function _retryStaleTransportProbe(generation)",
    "if (!root._transportChecked) {",
    "root._startTransportProbe()",
    "root._retryStaleTransportProbe(generation)",
):
    require(service, token, "EqualizerService")

# The fixed ten-band facade and Serpantinum preset curves remain the public UI contract.
for token in (
    "readonly property var dspFrequencies:",
    "[31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]",
    '"Bass":    [5, 7, 5, 2, 1, 0, 0, 0, 1, 2]',
    '"Treble":  [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6]',
    "function setDspBandGain(index, gain)",
    "function applyDspPreset(name)",
    'Quickshell.shellPath("scripts/equalizer-control.sh")',
    'EasyEffects.nativeInstalled ? "native" : "flatpak"',
    '"command -v python3 >/dev/null 2>&1"',
):
    require(service, token, "EqualizerService")

# Startup/reload recovery: a transport result from an older EasyEffects
# lifecycle generation must retry instead of being treated as unavailable.
probe_start = service.index("id: transportProbe")
probe_end = service.index("id: stateReadProc", probe_start)
probe_block = service[probe_start:probe_end]
for token in (
    "if (!root.enabled)",
    "if (generation !== root._lifecycleGeneration) {",
    "root._retryStaleTransportProbe(generation)",
    "root._transportChecked = true",
):
    require(probe_block, token, "EqualizerService transportProbe")

refresh_start = service.index("function _refreshBackendState()")
refresh_end = service.index("function _readState()", refresh_start)
refresh_block = service[refresh_start:refresh_end]
unchecked = refresh_block.index("if (!root._transportChecked)")
unavailable = refresh_block.index("if (!root._transportAvailable)")
if unchecked > unavailable:
    raise SystemExit(
        "FAIL: Equalizer reports transport unavailable before a current-generation probe completes"
    )

# The DSP names above are now the sole public service API. Earlier aliases had
# no in-repo callers and only kept a second vocabulary alive.
for token in (
    "property list<string> presets",
    "readonly property string activePreset:",
    "readonly property var bands:",
    "bandControlAvailable",
    "function applyPreset(",
    "function setBandGain(",
    "function reset()",
):
    forbid(service, token, "EqualizerService")

# Backend socket/property protocol remains helper-owned rather than leaking into
# the deferred QML facade.
for token in (
    "get_property:output:equalizer:",
    "set_property:output:equalizer:",
    "load_preset:output:",
    "malformed-band-response",
    "id: bandRefreshProc",
):
    forbid(service, token, "EqualizerService")

# State is accepted only as ten finite clamped values and published after a
# successful apply, so failed backend loads cannot pretend that DSP changed.
for token in (
    "function _normalizeGains(values)",
    "values.length !== root.dspFrequencies.length",
    "Math.max(root.dspMinimumBandGain",
    "property var _pendingGains: []",
    "const normalized = root._normalizeGains(root._pendingGains)",
    'root.error = "dsp-apply-failed"',
):
    require(service, token, "EqualizerService")

# Helper updates the active Equalizer database directly and persists the same
# Equalizer fields into the active preset file. It must never reload the preset,
# because reloading rebuilds the whole pipeline and can discard unsaved
# Convolver/Limiter state.
for token in (
    "slider_map = {",
    "0: 0,",
    "1: 3,",
    "2: 6,",
    "3: 9,",
    "4: 12,",
    "5: 15,",
    "6: 18,",
    "7: 21,",
    "8: 24,",
    "9: 27,",
    "socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)",
    'active_preset = request("get_last_loaded_preset:output")',
    'plugin_prefix = f"output:equalizer:{instance_id}"',
    'require_property(f"get_property:{plugin_prefix}:numBands")',
    'send(f"set_property:{plugin_prefix}:numBands:32")',
    'send(f"set_property:{plugin_prefix}:{channel}:band{index}Frequency:{frequency}")',
    'send(f"set_property:{plugin_prefix}:{channel}:band{index}Gain:{gain}")',
    'equalizer["num-bands"] = 32',
    'equalizer["split-channels"] = False',
    'atomic_text_write(preset_path, json.dumps(document, indent=4) + "\\n")',
    'mv -f "$state_candidate" "$state_file"',
):
    require(helper, token, "equalizer-control.sh")

for token in (
    "load_preset:output:",
    "alis_live_eq",
    "socat",
):
    forbid(helper, token, "equalizer-control.sh")

live_apply_pos = helper.index('send(f"set_property:{plugin_prefix}:numBands:32")')
preset_write_pos = helper.index(
    'atomic_text_write(preset_path, json.dumps(document, indent=4) + "\\n")'
)
state_commit_pos = helper.index('mv -f "$state_candidate" "$state_file"')
if not live_apply_pos < preset_write_pos < state_commit_pos:
    raise SystemExit("FAIL: live EQ apply/preset persistence/state commit ordering regressed")

for token in (
    '"XDG_DATA_HOME"',
    '"XDG_CONFIG_HOME"',
    '".var/app/com.github.wwmm.easyeffects"',
    '"data/easyeffects/output"',
    '"config/easyeffects/output"',
    "command -v python3",
):
    require(helper, token, "equalizer-control.sh")

# UI owns only facade calls. It must not contain backend/socket/preset-file logic.
# CAVA bars and the DSP controls share one graph. The only Slider declaration
# is the ten-band node delegate inside that graph; the connector itself restores
# the old three-layer electric-current animation without bringing back the
# detached lower slider row.
for token in (
    "EqualizerService.registerConsumer()",
    "EqualizerService.unregisterConsumer()",
    "CavaProcess {",
    "id: eqCava",
    "active: root.active",
    "sampleCount: 64",
    "const spectrum = eqCava.points ?? []",
    "Number(eqCava.normalizationCeiling)",
    "id: analyzerCanvas",
    "model: EqualizerService.dspBands",
    "function curvePoint()",
    "handleItem.mapToItem(",
    "EqualizerService.setDspBandGain(",
    "function applyPreset(name): void",
    "EqualizerService.applyDspPreset(name)",
    "property real eqLightningHighlight: 0.0",
    "property real eqPresetSweepProgress: -0.12",
    "function triggerEqLightning(): void",
    "function triggerPresetSweep(): void",
    "function beginBandLightning(index, gain): void",
    "function previewBandLightning(index, gain): void",
    "function endBandLightning(index, gain): void",
    "id: presetSweepAnim",
    "id: eqLightningAnim",
    'property: "eqPresetSweepProgress"',
    "const sweepTail = 0.22",
    "const sweepLead = 0.035",
    "ctx.lineWidth = 5.5",
    "ctx.lineWidth = 2.4",
    "ctx.lineWidth = 1.0",
    "id: bandRepeater",
    "cursorShape: bandSlider.enabled",
    "Qt.SizeVerCursor",
    "id: bandControlRow",
    "width: parent.width / 10",
    "readonly property int presetStripHeight:",
    "implicitHeight: root.presetStripHeight",
    "RowLayout {",
    "Layout.alignment: Qt.AlignVCenter",
):
    require(panel, token, "EqualizerPanel")
for token in (
    "EasyEffectsServer",
    "socat",
    "equalizer-control.sh",
    "load_preset:output:",
    "id: lightningCanvas",
    "ctx.bezierCurveTo(",
):
    forbid(panel, token, "EqualizerPanel")

# Compact media transport controls intentionally keep accessible buttonText but
# no hover popups for Previous / Play-Pause / Next.
for token in (
    'buttonText: Translation.tr("Previous")',
    'buttonText: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")',
    'buttonText: Translation.tr("Next")',
):
    require(player, token, "PlayerControl")
for token in (
    'StyledToolTip { text: Translation.tr("Previous") }',
    'StyledToolTip { text: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play") }',
    'StyledToolTip { text: Translation.tr("Next") }',
):
    forbid(player, token, "PlayerControl")

# Existing EasyEffects native/Flatpak ownership remains unchanged.
for token in (
    'command: ["/usr/bin/env", "flatpak", "ps", "--columns=application"]',
    'l.trim() === "com.github.wwmm.easyeffects"',
    'Quickshell.execDetached(["/usr/bin/env", "easyeffects", "--service-mode"])',
    'Quickshell.execDetached(["/usr/bin/env", "flatpak", "run", "com.github.wwmm.easyeffects", "--service-mode"])',
):
    require(backend, token, "EasyEffects")

print("PASS: Media DSP updates the live active Equalizer without pipeline reload, with integrated CAVA response graph and compact transport UI")
PY
python3 "$script_dir/test-equalizer-presentation-runtime.py"
