# Audio profile cache: preliminary offline evidence

The frozen Round 49 candidate remains **UNPROMOTED**. Production
`BarCavaVisualizer.qml` is unchanged.

The [receipt](receipt.json) pins both source hashes and Qt 6.12.0. The
[reproducer](qv4-parity.py) executes their extracted arithmetic functions in
QV4 via QCoreApplication/QJSEngine, with no window, GPU capture, CAVA process,
owner audio or preferences. Run it with the absolute Alis repository path
as its sole argument; PySide6 is required.

10,084 frame/configuration cases and 1,364,978 checks preserve exact samples,
smoothed values, level vectors, A/B scratch rotation and comparable identity
transitions (`Object.is`, including NaN/signed zero). Cases include source
counts 0–256, seven profiles, stereo/mono, clamped/NaN strengths, smoothing,
bars/waves, repeated frames and active cycles. Profile-weight function calls
change from 199,584 to 11,088 in this workload. These are operation counts,
not measured CPU/GPU/RAM percentages or frame-time improvement.

This harness strips QML function type annotations and uses plain JS root
properties. It does **not** exercise QObject bindings, typed-call conversion,
actual QML NOTIFY/dependency behavior or rendering. Those gates, strict RGBA
comparison and uncontended matched cost measurements are still required
before promoting the candidate. The pass does not change the central task's
OPEN status. No frozen Companion G0 lineage was replayed.

## Actual QML stage — 2026-10-11

[Native reproducer](native-parity.py), [receipt](native-receipt.json) and
[full output](native.log): PASS, exit 0, 4,704 actual QML frames / 377,954 checks
on private Niri. Both components issue exactly 6,509 `_levelsChanged` signals.
This loads the original QML files with their typed functions and exercises
profile, stereo, strength, smoothing, mode, source-shape and active transitions;
exact vectors, stable selected/smooth arrays and A/B published identity agree.
The staging module explicitly registers Candidate; the initial harness import
failure was repaired before this run. Two unrelated native-dispatch warnings
remain because this isolated fixture does not link the scripts directory.

This advances typed-call/NOTIFY coverage only. Width/density/radius and complete
read/dependency-order qualification are still open. `spectrumOpacity=0` means
there is no render comparison. Strict RGBA and uncontended matched cost remain
required. Production remains unchanged, UNPROMOTED; owner focus, audio and
preferences were not used.
