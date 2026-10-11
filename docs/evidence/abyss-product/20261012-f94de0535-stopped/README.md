# Frozen canonical run stopped at the five-hour threshold

Source: `f94de053514954b07635381a318025fc76a3d522`, clean clone. Frozen driver SHA256: `de94fa7950e376f21c61d66fc025858757ac5cdd073a79a513f4f1fe08900770`; arguments `--current-repo --strict-qml`, Qt parser path `/usr/lib/qt6/bin`.

**STOPPED, exit -15**, at 2026-10-11T19:03:19Z, because the actual five-hour window had 2% remaining. The exact owned driver and descendants were terminated; no full validator summary exists. Of **235 completed checks**, **231 PASS / 4 FAIL / 0 SKIP**; these are partial counts, not a completed canonical result. The interrupted next check has no outcome.

Four consumed failures remain visible:

- Check78 Calendar editor layout: Remove action escapes the card at DPR1.5 / width240. Root cause remains unproven.
- Check98 Dashboard editor field: Dashboard/top1280×900 Edit changes widget allocation933×546→933×540. Earlier bounded unchanged-runtime success does not diagnose this failure.
- Check155 Material global style: fixture requires literal generic padding after task-scoped conditional expressions. Fixture-only fix-forward `f003ec5f927d42baa8636eb2368a20decf337134` separately passes its original18 family/palette/shape cases while evaluating the real default padding expressions. This does not change this frozen result.
- Check188 Recording runtime: native connected controls exit1 after Configuration Loaded, without a specific assertion/geometry. NOT_DIAGNOSED; no production fix claimed.

This source precedes Events durable-snapshot `ccd7501679f425d135a92f217447808531cc38b6` and the Material fixture repair. Its partial results do not qualify newer source. DASH-F01/F02 and Events prerequisite focused evidence, committed full canonical qualification and installed/physical owner acceptance remain separate. No resource percentage is implied.

[Raw validator log](canonical.log), [raw terminal](terminal.log), [original outer receipt](canonical.json), [stop receipt](stop-receipt.json) and frozen driver are retained without rewriting the consumed run. A single existing thread heartbeat was updated to reset+3minutes (04:29:37 ICT12October2026) and fired at04:29:49; the new five-hour window was read as100% remaining. The priority remains New features first with related Rework/Issues alongside.
