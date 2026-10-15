#!/usr/bin/env python3
"""Freeze the pre-fix Canvas renderer; compare paint operations and idle work."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "modules/mediaControls/EqualizerPanel.qml").read_text()
paint = source.split("                    onPaint: {\n", 1)[1].split(
    "\n                    }\n", 1
)[0]
candidate_predicate = "sweep > -0.12 && sweep <= 1.16"
reference_predicate = "sweep >= -0.12 && sweep <= 1.16"
assert paint.count(candidate_predicate) == 1
reference = paint.replace(candidate_predicate, reference_predicate)
# Reconstruct the exact e18dce398 pre-fix handler without duplicating 213 lines.
# Any other drawing change must deliberately requalify this frozen reference.
assert hashlib.sha256(reference.encode()).hexdigest() == (
    "6553969a59c1075d25ec60c3e3b06084b1eef94267872f21e1751e85d58512f1"
), "Canvas drawing changed beyond the qualified idle-sweep predicate"
gain_to_y = source.split("    function gainToY(gain, height): real {\n", 1)[1].split(
    "\n    }\n", 1
)[0]

program = r"""
const vm = require('node:vm');
const assert = require('node:assert/strict');
const input = JSON.parse(require('node:fs').readFileSync(0, 'utf8'));
function instrument(body) {
    return body.replaceAll('samples.push(', 'captureSample(samples, ')
        .replace('const p1 = samples[i - 1]',
            'sweepSegmentsVisited++; const p1 = samples[i - 1]');
}
const referenceScript = new vm.Script('(function(){' + instrument(input.reference) + '})()');
const candidateScript = new vm.Script('(function(){' + instrument(input.paint) + '})()');
const gainScript = new vm.Script('(function(gain,height){' + input.gainToY + '})');
let cases = 0, idleCases = 0;
function renderer(script) {
    let operations = [], path = [];
    const context = {globalAlpha: 1};
    // Record only operations that paint pixels. Property changes and path
    // construction alone do not alter Canvas output.
    const strokeState = () => [context.globalAlpha, context.strokeStyle,
        context.lineWidth, context.lineCap, context.lineJoin];
    context.clearRect = (...args) => operations.push(['clear', ...args]);
    context.fillRect = (...args) => operations.push(['fill', ...args,
        context.globalAlpha, context.fillStyle]);
    context.beginPath = () => { path = []; };
    context.moveTo = (...args) => path.push(['move', ...args]);
    context.lineTo = (...args) => path.push(['line', ...args]);
    context.stroke = () => operations.push(['stroke', ...strokeState(), path.slice()]);
    const state = vm.createContext({
        width: 1, height: 1,
        root: {compactLayout: false, eqAccentColor: '#336699'},
        EqualizerService: {dspMinimumBandGain: -12, dspMaximumBandGain: 12},
        eqCava: {}, Appearance: {colors: {colLayer2: '#192027'}},
        Qt: {lighter: (color, factor) => [color, factor]},
        Date: {now: () => state.frozenMs},
        getContext: () => context,
        captureSample: (samples, value) => { state.captured++; samples.push(value); },
        captured: 0, sweepSegmentsVisited: 0,
        bandRepeater: {itemAt: index => state.useHandles
            ? {curvePoint: () => ({x: (index + .5) * state.width / 10,
                y: state.root.gainToY(state.gains[index], state.height)})}
            : null}
    });
    state.root.gainToY = gainScript.runInContext(state);
    return options => {
        operations = []; path = [];
        context.globalAlpha = 1;
        Object.assign(state, options, {captured: 0, sweepSegmentsVisited: 0});
        Object.assign(state.root, {compactLayout: options.compact,
            eqLightningHighlight: options.highlight,
            eqPresetSweepProgress: options.sweep});
        state.EqualizerService.dspBands = options.gains.map(gain => ({gain}));
        state.eqCava.points = options.spectrum;
        state.eqCava.normalizationCeiling = options.ceiling;
        script.runInContext(state);
        // JSON removes realm-specific Array prototypes, retaining every number,
        // coordinate, style and painting order exactly (no tolerance).
        return {operations: JSON.stringify(operations), captured: state.captured,
            segments: state.sweepSegmentsVisited};
    };
}
const reference = renderer(referenceScript), candidate = renderer(candidateScript);
const curves = [Array(10).fill(0), [5,7,5,2,1,0,0,0,1,2],
    [-12,12,-12,12,-12,12,-12,12,-12,12]];
const sweeps = [-.120001,-.12,-.119999,-.09,-.035,0,.05,.5,1,1.16,1.160001];
// Plot widths span narrow supported containers through large dashboard cards;
// heights include collapsed/transition frames. Both real handle coordinates
// and the missing-delegate fallback use the production gain mapping.
for (const width of [32,64,95,196,300,426,768,1536])
for (const height of [1,31,64,89,107,240])
for (const compact of [false,true])
for (const useHandles of [false,true])
for (const highlight of [0,.5,1])
for (let i = 0; i < sweeps.length; i++) {
    const options = {width,height,compact,useHandles,highlight,sweep:sweeps[i],
        frozenMs: [0,250,9500,123456789][i % 4], gains:curves[i % curves.length],
        spectrum: i % 3 === 0 ? [] : Array.from({length:i % 2 ? 64 : 128},
            (_, index) => (index * 37) % 101), ceiling: i % 2 ? 100 : 73};
    const before = reference(options), after = candidate(options);
    assert.ok(after.operations === before.operations, 'paint mismatch: ' + JSON.stringify(options));
    if (options.sweep === -.12) {
        assert.equal(before.captured, 201);
        assert.equal(before.segments, 198);
        assert.equal(after.captured, 0, 'rest sentinel retained trace sample capture');
        assert.equal(after.segments, 0, 'rest sentinel retained preset sweep traversal');
        idleCases++;
    } else {
        assert.equal(after.captured, before.captured, 'active sweep sample count changed');
        assert.equal(after.segments, before.segments, 'active sweep traversal changed');
    }
    cases++;
}
console.log(`EQ_IDLE_SWEEP_PASS ${cases} frozen-time Canvas operation parity cases; `
    + `${idleCases} idle cases: 201 sample captures and 198 segment visits -> 0; `
    + 'connector/spectrum/active sweep draw operations unchanged');
"""
result = subprocess.run(
    ["node", "-e", program],
    input=json.dumps({"reference": reference, "paint": paint, "gainToY": gain_to_y}),
    text=True,
    capture_output=True,
)
print(result.stdout, end="")
if result.returncode:
    raise SystemExit(result.stderr)
