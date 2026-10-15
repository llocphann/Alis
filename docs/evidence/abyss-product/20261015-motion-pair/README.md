# Instrumented Dashboard motion diagnostic pair

One serialized `grab → no-grab` pair on frozen Alis source `77439bddc018cf6e9486c5088f72c76a0efaf060`. Both native processes exited 0 and completed all 16 original Dashboard/Overview × edge × size cases. Geometry, native input, reversals and reduced-motion checks remained active: 5,521 checks with grabs and 5,159 without image assertions in the control.

The no-grab control acknowledges requests on frame swaps without GPU readback. Both lanes retain the same pending/phase flow. Temporary source instrumentation only logs widget Loader activation/status; no production source or owner runtime was changed.

The historical **4,716 ms** callback was **not reproduced**: maximum actual grab callback 53 ms, no-readback acknowledgment 38 ms. Startup/loading GUI heartbeat gaps were 1,623/842 ms. Maximum observed intermediate-progress swap intervals were 150/44 ms. Endpoint-only gaps are stored separately and are not counted as active-motion misses. One ordered, instrumented pair cannot establish cause, improvement, resource savings, FPS or Owner smoothness acceptance. CPU/RSS and host-load observations are diagnostic only; image readback/PNG and logging work differ between lanes.

`bounded-pair-summary.json` records exact PID cleanup and observed CPU/RSS. `qualified-summary.json.gz` and per-lane compressed JSON preserve the trace. Full unstructured logs and images remain private at the paths/hashes in `manifest.json`; incidental host/Weather lines are omitted. The explicit diagnostic JSON records are published separately. No image/pixel-parity claim follows from these checks.

## Reproduce only with an explicitly quiet host and available budget

From a checkout containing the pinned commit, choose a **new** temporary directory:

```bash
mkdir /tmp/alis-motion-repro-77439bddc
cp docs/evidence/abyss-product/20261015-motion-pair/reproduce/*.py /tmp/alis-motion-repro-77439bddc/
ALIS_DIAGNOSTIC_REPO="$PWD" python3 /tmp/alis-motion-repro-77439bddc/prepare.py
python3 /tmp/alis-motion-repro-77439bddc/run_pair.py --host-quiet-confirmed --order grab,no-grab --timeout 120 --output /tmp/alis-motion-repro-77439bddc/result-pair
python3 /tmp/alis-motion-repro-77439bddc/analyze.py /tmp/alis-motion-repro-77439bddc/result-pair
```

Preparation does not start native processes. Each lane has a 120-second OS bound, private XDG/D-Bus/Niri state, independent owned-QS CPU samples and process-group cleanup; no explicit focus request. The reproduction preparation script differs from the original only by taking the checkout path from `ALIS_DIAGNOSTIC_REPO`. Original driver hashes are retained in the manifest. The standalone `qmlformat` probe returned 1 without diagnostics; actual native loading subsequently completed both full lanes. No further variant or benchmark was run.
