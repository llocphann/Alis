# Rework/optimization

Work after actionable [Issues/bugs](ISSUES.md), unless the maintainer changes
the immediate priority. [The canonical audit](../../docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md)
holds technical research; this file holds pending outcomes.

## Resource use and responsiveness

- [ ] **Abyss Panel motion stutter — received/updated 2026-10-10:**
  Specific owner Notification Edgebar-hover and Recording-start stutters have
  independent reproductions in [Issues](ISSUES.md); keep this broad
  presentation optimization separate from those correctness investigations.
  Owner reports visible judder/jank while Abyss panels/Popups appear, disappear
  and transfer across edges; supplemental video `2026-10-10_13.34.50.mp4`
  is in the request (31.93 s at ~30 fps capture), not a frame-time/CPU/GPU
  trace and not committed to this repo. This is a concrete responsiveness
  acceptance under existing Connected presentation / strict-lossless research,
  not a new render-quality tier or permission to lower visual fidelity.
  Priority after actionable hover/correctness Issues. Profile cold/warm
  open, close, reversing mid-animation, rapid multi-edge switching and
  simultaneous/pyramidal panels; record actual frame time distribution
  (p50/p95/p99/dropped frames), main-thread CPU, compositor/GPU and
  allocations on comparable exact-SHA owner output sessions. Candidate:
  `AbyssGeometry.popupShoulders` produces per-scanline native input Regions
  during animations; investigate lossless adjacent-strip compaction and
  Instantiator/Region churn without dropping painted pixels, reordering
  input-source ownership or altering shader/animation cadence. Require
  pixel-union oracle, native pointer dwell/focus/click-through checks,
  visual parity and measured before/after; keep open until owner confirms
  perceptibly smooth transitions. Candidate `6c10387d18aa1793d7ad2f2ef20eb37020d69abf`
  now coalesces contiguous same-span SDF mask strips at construction, preserving
  pixel union and reducing native Region/Instantiator objects. Across 576
  independent 4-edge/scale/softness/radius/progress cases, static mask instances
  fell from 22,752 to 10,080 (55.7% fewer **Region rectangles only**, not FPS,
  CPU, GPU or RAM). Geometry contract test additions `38437f56` and native
  hover fixture additions `5a2cb977` are committed; an offline V8 run of the
  geometry test body passed 504,005 assertions with stubs. Source has **not**
  passed Quickshell/native compositor, canonical exact-SHA or owner visual
  acceptance. Next: serial native hover/geometry test first (Issues), then
  collect comparable before/after frame pacing and cost on installed source;
  if still visibly jerky, profile allocator/animation/ShaderEffect/wave frame
  paths before proposing another lossless candidate. Do not conflate Region
  reduction with a confirmed user-visible jank fix.

  **Owner still reports jank after `6c10387`, 2026-10-10:** that Region
  compaction/physical-mask patch was reverted in `0d26291646bc9b4db6f0678c54b10f7a4b8c8962`
  as ineffective. The earlier 55.7% rectangle reduction is now **historical
  only, NOT a current resource saving**. Do not stack another workaround on
  it. New independent strict-math hot-path candidate
  `b50c3b8064317fd8feb1ccd20303315765b2f2c8` reuses the immutable
  workspace rectangle and single popup record in `popupShoulders`, avoiding
  per-pixel object allocation/record-array traversal while preserving exactly
  the same SDF operations. Direct before/after V8 tests compared full
  shoulder rectangle arrays in **720 edge/scale/softness/radius/progress cases:
  identical**. Isolated loops of 2,000 calls measured 824→621ms at softness 24
  and 1,694→1,303ms at softness 48 (single V8 environment; not a whole-shell
  FPS/CPU/GPU/memory result). Native Qt/Quickshell has NOT been tested.
  To identify actual jank instead of guessing, opt-in diagnostics
  `1633a6e1d909de0c93e8a33999cccab1b78dcac3` adds
  `abyssHoverProbe.startFrames()` / `stopFrames()`: per-output bounded
  600 QQuickWindow `frameSwapped` wall-clock interval samples with
  p50/p95/p99 and interval gaps. Disabled until explicitly called, no
  recurring profiler/timer; results can include idle gaps and are NOT
  compositor-present timestamps or hardware GPU counters. Next: collect
  installed exact-SHA source, a real captured output/frame interval sample
  during slow open/reverse/multi-edge transitions, and CPU/GPU compositor
  evidence where available. Diagnose spikes in mask rebuild, allocator
  movement, ShaderEffect/waves, or focus/remount from evidence first.
  **USER-EXPERIENCE ACCEPTANCE REMAINS OPEN.** Exact source at
  `0ded4c9b388b407506add4029a7eb8985dc426fe` passed a second
  **offline V8** run of the current repository Node geometry test body:
  518,945 assertions, same predicate/serialization checks, using emulated
  Node asserts/readFile; still NOT Qt/Quickshell or canonical. A single
  read-only collection helper
  [`scripts/collect-abyss-hover-frames.sh`](../../scripts/collect-abyss-hover-frames.sh)
  captures frame interval samples without IPC polling and then separate
  timestamped hover state samples (no native compositor mask refresh).
  After installing the new exact source, run it while reproducing motion
  and transfer, preserve the three receipts and source/installed SHA. Do
  not report whole-shell FPS gain from V8 microbench timings, and do not
  call the previous Region-count reduction current after its revert.
  **First owner measurement attempt 2026-10-10 07:18:55 UTC was BLOCKED**:
  uploaded `frame-start.txt` reports Quickshell could not find its
  `default` configuration. It contains no frame intervals or FPS; uploaded
  `identity.txt` pins only the dev checkout `ff56015cf` and
  `qs_config=auto`, not the installed shell. This was caused by the original
  collector omitting the config path, whereas the Hadalis launcher uses
  `qs -p "$config_dir" ipc call`. Fixed diagnostic collector in
  `4dc295e7f118a2445ca5ab4d6a66de2552312532` to select the live iNiR
  instance and report installed/source parity. Corrected collector still
  requires owner rerun. **Jank cause and performance acceptance UNKNOWN/OPEN**;
  no percent/fps gain inferred from the failed capture.

  **Owner's second capture (2026-10-10 07:49:30Z), Niri/eDP-1:**
  `startFrames` succeeded and `stopFrames` returned 363 intervals,
  but recorded min/p50/p95/p99/max/mean all approx
  **1,791,001,362,433–1,791,001,362,477 ms** and all
  363 intervals were flagged over16/33/100 ms. These timings
  are **INVALID**, not evidence of low FPS: the old diagnostic
  stored `Date.now()` (~1.791e12 epoch milliseconds) in a
  signed 32-bit QML `property int _frameProbePreviousMs`,
  truncating the prior timestamp before subtraction. Example
  `1791618576306 - 617213874 = 1791001362432`;
  the spurious interval magnitude is explained by that exact
  integer overflow. Since the capture time is known and the 6-second
  window cannot cross the next signed-modulo epoch boundary, the constant
  offset is exactly `417 * 4294967296 = 1791001362432 ms`; subtracting
  this from the stored summary statistics recovers **approximate Qt
  frameSwapped intervals**: min=1ms, p50=17ms, p95=18ms, p99=41ms,
  max=45ms, mean=16.573ms (363 intervals). This DOES show a slow
  upper tail in *Qt wall-clock frameSwapped events*, but cannot
  assign cause to SDF/mask/GPU/compositor, cannot reconstruct threshold
  counts from the summary, and cannot prove the user's specific
  lag reproduction overlapped these frames. Thus raw counters
  `over16ms/over33ms/idleGapsOver100ms=363` remain INVALID.
  Diagnostic-only commit
  `b8be0fcb551a319fbff0b6c2a65c062f955c5ead` changes
  that property to QML `real`, not shell rendering itself.
  User-visible Panel lag remains **OPEN/UNMEASURED**.
  Commit `15f5abbb1bc19bf5377636dbee03c7f973713330`
  makes the collector auto-package complete/partial receipts into
  **one `.tar.gz`**, preserving original IPC exit status.
  Exact committed collector blob
  `defb45271438a80cc012d611467ce6c9451f264a`
  passed real `bash -n` (exit 0) and a fake `qs -p` run:
  success with 40 snapshots and one archive (exit 0), plus an
  explicit `startFrames` failure (exit 1, partial archive).
  Those are script tests, not Niri/Qt acceptance. Next: ensure
  running shell loads the updated QML, animate in PHASE 1,
  and provide the single archive with true bounded samples.

  **Owner second one-file capture 2026-10-10 08:04:04Z:**
  `hadalis-abyss-hover-20261010-150404.tar.gz` has
  `run-result.txt exit 0` but raw `frame-start.txt`
  is `Target not found.`, the stop reply has count=0 and
  null min/p50/p95/p99/max. On the actual owner-installed
  configuration `~/.config/quickshell/inir`, the
  `AbyssPerimeter.qml` file was **DIFFERENT from checkout**
  SHA `5896b425951a774f6b209d68b50616297f455a3c`.
  The other sampled source files matched. Thus latest frame
  timing probe was **NOT actually started**; the previous
  collector falsely accepted `qs` exit code 0 on a missing
  handler. No new frame-pacing values, FPS or root-cause
  conclusions were obtained from this archive.
  `faf8ad59b9336ad6d2689b20ace52b28f22a6d45`
  now refuses mismatched installed QML and invalid IPC
  replies and still emits one uploadable archive. Exact
  Git blob `d4f52cef9342defc1fde61d1c4dfacdd67ff4f54`
  passed `bash -n` and five mocked CLI cases with
  expected status 5/6/2/0/4 and valid archives.
  Synchronize with `./setup update` from `dev`
  before `inir restart`, confirm on-disk parity and
  run the probe during actual panel animations.
  **Owner lag confirmation remains OPEN.**

  **2026-10-10 08:26:41Z additional owner archive:** the QML installation
  now matches checkout `3acf9685ce7aef5e1c7e879e2437a7001ac3f874`
  for all three sampled files, but the live Quickshell IPC call to
  `abyssHoverProbe.startFrames()` still prints `Target not found.`.
  The bounded collector correctly aborted with exit 5 and packaged
  `run-result.txt`, `frame-start.txt`, `diagnostic-error.txt`,
  `identity.txt`. NO frame/hover samples were taken. A matching
  installed file is not proof the active Perimeter instance is mounted.
  Source gating requires Abyss family critical host, deferred
  readiness, and enabled `abyssPerimeter` module; active-state
  cause cannot be determined without live IPC inventory and host status.
  The read-only collector expansion `5462432e442048be32bf7de8e1227b892ed86e93`
  now includes `qs ipc show` and `abyssHostProbe.status()`
  diagnostic outputs within the same ONE archive; it also refuses
  a zero-count frame summary. No QML lifecycle or render
  settings were changed. Jank root cause and acceptance remain OPEN.

  **VALID owner Qt frame interval trace, 2026-10-10
  09:28:01Z, `eDP-1` on Niri:** archive
  `hadalis-abyss-hover-20261010-162800.tar.gz` was
  captured at checkout `a5ebffa747ddead7799d6dd6501f712996e068bf`
  and installed source parity MATCH for all 3 tracked files.
  IPC registry includes `abyssHoverProbe.startFrames`,
  `stopFrames`; actual start reply
  `[{"output":"eDP-1","started":true,"maxIntervals":600}]`.
  Frame stop reply: count=346, min=2ms, p50=17ms,
  p95=22ms, p99=76ms, max=86ms, mean=17.5983ms;
  intervals over16.7ms=208, over33.3ms=7,
  idle gaps over100ms=0. Sum of intervals ~6.09s.
  These are real bounded Qt `QQuickWindow.frameSwapped`
  **wall-clock intervals**, not compositor present/GPU
  timings, and are valid after the QML `int` overflow
  correction. A sparse slow tail is confirmed (7/346
  intervals exceeded 33.3ms), but the log does NOT timestamp
  individual outliers or prove the owner performed a
  specific animation during that 6s window.
  The `notificationCenter` popup was first observed
  only at hover sample #35 (~09:28:18Z), which was
  AFTER the separate frame measurement ended; do NOT
  attribute those 7 outliers to that exact popup reveal.
  No root cause, before/after speed-up or acceptable
  product smoothness claim is supported. **Lag remains OPEN.**

  To avoid losing the next hover-transfer event at the end
  of the original ~9.5-second, 40-snapshot phase, collector
  `d642cce966aea969a7f843180db82bece38e970a`
  now captures 100 bounded snapshots (~24s expected
  including IPC overhead, not an exact deadline).
  `1a0875d1b0fdd9c7f572d96e1a6e1d3c6cd90c00`
  adds read-only NotificationCenter hover-grace owner state
  to the popup slot snapshot. Neither alters rendering,
  frame scheduling, animation curves, shape nor
  native input. Next: exact installed-dev native capture,
  explicitly perform opening/reversal during Phase 1,
  open and cross popup during Phase 2, share ONE `.tar.gz`.
  Native acceptance on these latest diagnostic changes
  is still PENDING.

  **Owner archive 17:06 local, 2026-10-10 (checkout
  `418fcd9e9947cfadfe1b2453257751792875d623`):**
  This is NOT a new measurement of the prior p99=76ms
  slow-frame tail. The collector aborted exit 5:
  `abyssHoverProbe.startFrames` and its earlier snapshot
  both returned `Target not found.` because
  `abyssHostProbe.status` reported
  `deferredPanelsReady=false`, `perimeterLoaded=false`,
  `perimeterActive=false`, `initialMountReady=false`,
  `coldRecreatePending=true`. All three installed
  QML/JS parity checks MATCH. Runtime IPC target absence
  was directly observed; permanence vs transient boot race
  is unproven without a subsequent status.
  No frame-intervals or hover-snapshots payloads exist
  in the archive.
  `5bab2c774df7e2ecb5c0a446e3053a981323b1cd`
  adds bounded readiness polling (100 polls, 250ms apart,
  max ~25s) to the script, with `readiness-trace.log`,
  final status, clear timeout exit 7 and automatic partial
  archive, preventing premature `startFrames` calls while
  the Perimeter is unmounted. It does not change QML
  rendering, startup, compositor layers, animation or
  actual frame pacing. Await a native ready capture
  with explicit open/close/reverse of Abyss Panel before
  attributing any slow events to animation. **Lag remains OPEN.**

  **Owner VALID capture 2026-10-10 10:33:48Z,
  `hadalis-abyss-hover-20261010-173348.tar.gz`:**
  `dev` checkout `ffef7ef8ab5ca6107f11de959b33c404d644dd50`,
  three installed QML/JS comparisons MATCH, readiness attempt 0,
  active Niri `eDP-1` Perimeter, `startFrames` started=true,
  `stopFrames` returned **342** real Qt `frameSwapped`
  wall-clock intervals: min=0ms, p50=17ms, p95=19ms,
  p99=71ms, max=184ms, mean=17.6403508772ms,
  over16.7ms=193, over33.3ms=8,
  idleGapsOver100ms=3, maxIntervalCount=600 not exhausted.
  Valid slow tail persists (8/342 >33.3ms), with three
  >100ms gaps; include clock quantization and idle gaps.
  These are NOT GPU/compositor-present timings and the
  aggregate does not identify which precise Panel animation,
  if any, was running when the slow intervals occurred.
  NotificationCenter's two observable hover/open/retract
  cycles (#66–76 and #78–87) happened later during the
  separate hover phase; do NOT assign the frame samples
  to these popup events without new correlated evidence.
  Source-only `adc17c8b63b6f169005c11a193ab69343e6024ef`
  adds at most 40 timestamped slowEvents >33.3ms
  to the opt-in frame measurement: timestampMs,
  intervalMs and snapshot-only-on-outlier values
  for Bar visibility, liquid Popup presence,
  left/right Panel, Dashboard, Controls and Settings
  reveal progress. This only reads presentation state
  when a slow interval is observed; it does not alter
  timers, motion curves, shader quality or input masks.
  Still need the owner to open/close/reverse the intended
  Panel during PHASE 1 and submit a native archive
  with event timestamps. **Lag acceptance remains OPEN.**

  **Owner bounded trace 2026-10-10 10:44:39Z (17:44 local), exact
  checkout `ab1f52dd255c32a7626fd35fcaffceadf1b304eb`:**
  `hadalis-abyss-hover-20261010-174438.tar.gz`
  successfully measured **344** Qt `frameSwapped` wall-clock
  intervals: min=0ms, p50=17ms, p95=18ms, p99=40ms,
  max=161ms, mean=17.485465ms, >16.7ms=210,
  >33.3ms=4, >100ms=2. Compared with prior
  17:33 trace (342 intervals, p99=71ms, max=184ms,
  >33.3ms=8), this is a *different non-controlled
  six-second interaction*, NOT an optimization benchmark
  or measured performance improvement.
  New bounded `slowEvents` captured exactly four spikes:
  timestampMs=1791629083567 interval=161ms,
  1791629084032=40ms, 1791629085028=84ms,
  1791629085180=137ms. All four had
  `leftPanelProgress=rightPanelProgress=dashboardProgress=
  controlPanelProgress=settingsProgress=0`;
  Bar visible true for all, liquidPopupsOpen=true
  only for the later two spikes. Thus no observed
  Panel motion coincided with these four spikes; this
  does not establish that the user never moved a Panel
  or that GPU/compositor caused delays. Popup hover
  episode #67–96 belongs to the LATER sampling phase.
  Next: obtain a controlled native open/close/reverse
  Panel capture and compare slow-events against actual
  animation state. **Lag remains OPEN.**

  **Owner capture 2026-10-10 10:58:22Z
  (`hadalis-abyss-hover-20261010-175821.tar.gz`,
  checkout `1e934698dea22d39877dfda5e8de982ebc50c5ed`):**
  three installed source files MATCH; native readiness
  attempt 6, collector exit 0, valid `eDP-1`
  `QQuickWindow.frameSwapped` trace with **358** samples.
  min=2ms, p50=17ms, p95=18ms, p99=24ms, max=80ms,
  mean=16.804469ms, >16.7ms=213, >33.3ms=3,
  >100ms=0. Opt-in `slowEvents`:
  1791629908168=42ms, popupsClosed, all sampled
  panel progress=0; 1791629908424=80ms and
  1791629909966=34ms, popupsOpen,
  all sampled panel progress=0. Four visible
  notification-center popup visits were subsequently
  observed during the SEPARATE hover phase
  (#15–29, #47–59, #70–77, #82–89).
  These intervals cannot be mapped to a specific
  opener/closer/reversal without animation state
  correlation. p99 dropping from 71→40→24ms across
  distinct owner-run traces is NOT a controlled
  before/after performance win or a resolved bug.
  FrameSlows remain real Qt wall-clock observations
  (not GPU/presentation timings).
  Diagnostic-only `d2db68cece00b95d06ec6915f51db94342c4d8da`
  now includes bounded `popupMotion` metadata
  (kind, requestedVisible, revealProgress) only
  when a slow interval occurs. No animation curve
  or compositor timing policy changed.
  Need one actual native Panel opening/reversal
  during the separate frame capture before a
  causality/optimization claim. **Lag remains OPEN.**

  **Owner 18:07 local native diagnostic**
  (`hadalis-abyss-hover-20261010-180711.tar.gz`):
  `dev` checkout `122d8e5f970102fc56919b450db5f7c42c54fa8e`,
  3 installed QML/JS checks MATCH, valid host
  `eDP-1`, collector exit 0, startFrames=true.
  `frameSwapped` wall-clock intervals: count=294,
  min=2ms, p50=17ms, p95=20ms, p99=188ms,
  max=612ms, mean=20.45918ms, over16.7=165,
  over33.3=6 and `idleGapsOver100ms=4`.
  Six timestamped intervals: 11:07:16.002Z=188ms,
  16.315Z=313ms, 16.931Z=612ms (these had
  popupsOpen=false and ALL sampled Panel progress 0);
  17.421Z=86ms with Notification Center
  revealProgress=0, requestedVisible=true;
  18.571Z=117ms with revealProgress=1;
  20.283Z=41ms with revealProgress=0.
  Those latter three still had all sampled Panel
  progress 0. They indicate concurrent Notification
  Center state at outliers but DO NOT establish
  compositor/GPU causation, whether a Panel moved
  BETWEEN frame samples, or work done in Qt between
  `frameSwapped` signals. The 100-snapshot hover
  phase was separate/later, containing six visits
  (five end before snapshot 100). Larger p99/max
  versus prior run demonstrates **measurement
  variability**, NOT a performance regression caused
  by the previous read-only diagnostic.

  **Follow-up, probe only:**
  `5760ed7b005ed15809bcf062868bd6e43f4136f5`
  adds three opt-in frame-window counters
  `panelNonzeroFrames`,
  `panelProgressChangedFrames` and
  `popupOpenFrames` so a frame sample that never
  observed a left/right/Dashboard/Controls/Settings
  Panel motion is distinguishable from a genuinely
  sampled reveal/retraction. This samples five
  already-existing numeric progress properties
  only while frame probing is explicitly active;
  no FPS policy, render quality, shader or
  animation curves are changed. Isolated test
  `scripts/test-abyss-frame-activity-probe.mjs`,
  committed `64fe2f589e6c6cdd9eb357f6c5808dff5c023fcf`,
  executes exact QML callbacks with a controlled
  0→.2→.6→1→.4→0 trace and a 73ms gap;
  all **12/12** assertions pass. Registered in
  canonical validator `bc74aeb9072a56f44031ac67978251129c227c15`.
  These counters have not yet run on owner Niri;
  full maintainer validator not executed at this SHA.
  Next capture MUST show nonzero
  `panelProgressChangedFrames` for a genuine
  Panel animation before attempting to optimize
  those transitions. **Lag acceptance remains OPEN.**

  **Owner 18:31 local source-pinned native trace:**
  `hadalis-abyss-hover-20261010-183130.tar.gz`,
  exact `dev` checkout `48ea131296a474faca11eda3dbdd97e1efa0f1c4`;
  all 3 installed source checks MATCH; collection exit=0.
  First preflight at 11:31:32.145Z: root family abyss,
  shellEntryReady=true, deferredPanelsReady=false,
  perimeterLoaded=false, pending cold re-create=true.
  Perimeter was constructed by 11:31:34.098Z but
  `nativeFirstFramesReady` stayed false until
  11:31:40.075Z; cold recreation was observed
  at 11:31:41.902Z; second Perimeter instance
  became native-frame-ready at 11:31:46.536Z
  (poll 28, approximately **14.4s** after preflight).
  This capture documents prolonged readiness/warm-up
  on this ONE startup, not the underlying compositor
  reason or a repeatable median boot regression.
  Current 600ms+450ms cold recreation policy comes
  from prior 0/16→16/16 native pointer recovery and
  must NOT be disabled on speculation.

  First valid bounded 6s `frameSwapped` trace AFTER
  readiness: count=210, p50=17ms, p95=52ms,
  p99=328ms, max=852ms, mean=28.4381ms,
  over33.3ms=15, idleGapsOver100ms=7,
  `panelNonzeroFrames=0`,
  `panelProgressChangedFrames=0`,
  `popupOpenFrames=162`.
  Largest frame gaps 852ms at 11:31:48.002Z
  and 663ms at 11:31:48.956Z occurred with
  liquidPopupsOpen=false, all five tracked Panel
  progress values 0, within 1.5–2.4s after
  readiness. A 328ms gap at 11:31:49.573Z
  coincided with NotificationCenter opening
  (`revealProgress≈0.0053`); later 95ms, 59ms,
  56ms and 38ms gaps also sampled Popup motion.
  Those sample correlations cannot prove GPU,
  compositor, Qt event-loop, shader, or popup
  animation root cause. The 100-snapshot hover
  measurement is later and separate; it showed
  4 notification popup visits and a long stable hold.
  This trace never sampled an active Left/Right,
  Dashboard, Controls or Settings Panel animation;
  **do not claim the user's Panel jank has been
  reproduced or fixed**.

  **Follow-up instrument, not performance treatment:**
  `1e06a5a7aca6b08a4bed3058a4944809ad823780`
  adds an opt-in 50ms Qt Timer heartbeat, bounded
  late-tick timestamps (>100ms gap), count/max,
  plus `barProgressChangedFrames` and Bar progress
  at slow-event timestamps. Running a timer
  only during the six-second explicit probe
  discriminates normal Qt event-loop cadence
  with sparse frameSwapped signals from correlated
  Qt timer lateness, though timer jitter is
  not GPU/compositor proof. No regular background
  timer or modification of input masks, animation
  duration, shader, cold-start remount occurs.
  `scripts/test-abyss-frame-activity-probe.mjs`
  now tests these exact QML functions and passes
  **20/20** deterministic source-level assertions
  (`ce1f272a99e3341d1262a2952b4e15af812ba3b0`,
  `87e42c3eb3c9525fde2756b40764a904c7e1da54`).
  Full native/new-checkout acceptance is PENDING.
  Preserve 18:31 trace as separate cold-tail sample;
  seek a fresh settled-shell Panel animation capture
  only if actual user-visible motion/jank persists.
  **Lag acceptance remains OPEN.**

  **Owner archive 19:03 local, 2026-10-10**
  (`hadalis-abyss-hover-20261010-190302.tar.gz`,
  exact `dev` checkout
  `1ce236724be81cf75d974ef4bb8433c62d10279b`):
  installed/checkout parity MATCH for 3 source files;
  cold readiness attempt 4 (~3.7s after preflight),
  host/Perimeter native readiness confirmed,
  collector exit 0. Output `eDP-1`,
  bounded frame sample count **277** (not exhausted),
  min=2ms, p50=17ms, p95=28ms, p99=132ms,
  max=844ms, mean=21.8989ms, over16.7ms=148,
  over33.3ms=13, over100ms=4.
  Panel state counters throughout the measured interval:
  `panelNonzeroFrames=0`,
  `panelProgressChangedFrames=0`,
  `barProgressChangedFrames=0`, `popupOpenFrames=166`.
  In other words, NO observed Left/Right/Dashboard/
  Controls/Settings/Bar animation was captured,
  while Notification Center popup was active
  for a substantial part of the sample window.

  The bounded 50ms Qt heartbeat was delivered
  112 times, with five intervals >100ms and a
  longest late interval of 293ms. At 12:03:09.951Z
  a swap interval of 844ms ended with
  Notification Center revealProgress≈0.008788,
  while a heartbeat late by 141ms ended
  at 12:03:09.845Z INSIDE that swap gap
  (approximately 09.107–09.951Z). Thus the
  Qt event loop was not completely blocked
  throughout the full 844ms; sparse swaps
  and event-loop lag are both plausible
  contributors, their root cause NOT proven.
  At 12:03:10.912Z a swap interval of 252ms
  ended with Notification Center fully shown;
  a 293ms heartbeat interval ended at
  12:03:10.929Z, overlapping that swap gap
  (approximately 10.660–10.912Z). This
  strongly supports correlated Qt timer
  lateness during part of the slow-swap event,
  but NOT compositor/GPU timing diagnosis.
  Slow-tail variability across 18:31 and
  19:03 cannot establish a source-level
  optimization or regression in the absence
  of controlled warm/cold repeated samples.

  **Read-only diagnostic continuation:**
  `974c881247870882a07ed1b0f5c6bf60783fe608`
  records the complete bounded 50ms heartbeat
  `heartbeatHistory` (cap 160 entries) during
  explicit `startFrames` only. Captures both
  normal and late Qt timer ticks, with timestamps
  and intervals, so later analysis can count
  how often the Qt event loop serviced the timer
  inside each observed frame-swapped gap.
  The focused extracted-QML regression,
  `468a1314d19dbefdfbb25f231f7cd05b2a339a4d`,
  passes **26/26** assertions (including null
  initial interval and bounded overflow).
  No window lifecycle, shader, input, render
  quality, animation or background event-loop
  behavior was modified. Native validation on
  this new diagnostic remains pending.

  **Next discrimination:** capture one truly
  settled-shell run WITHOUT restarting iNiR
  immediately before sampling, and deliberately
  activate a named Panel during PHASE 1. Compare
  with the cold-start-adjacent archive, ensure
  `panelProgressChangedFrames>0`, then correlate
  individual swaps against complete heartbeat
  chronology. If Panel motion is never sampled,
  do NOT claim a Panel-specific jank fix.
  **Lag still OPEN.**


- [ ] **Strict-lossless CPU/RAM/GPU reductions:** re-audit latest `dev` and
  promote high-value findings only after behavior, read/dependency order,
  identity/NOTIFY and lifecycle parity. Keep hidden services/lightweight warm
  surfaces fast to reopen, with heavy unused work asleep. Prefer strict lossless
  or one measured <1% trade for a large benefit; do not accumulate small trades.
  Measure comparable cold/warm/idle/active CPU, RSS, GPU/frames and latency;
  allocation or operation counts are not whole-shell resource percentages.

- [ ] **Audio Spectrum processing:** investigate the Round 49 profile-factor
  reuse candidate. Source count/profile/stereo/clamped strength are frame-invariant
  until configuration or shape changes. A candidate is prepared only in
  [the stop checkpoint's unpromoted candidate](../../docs/evidence/abyss-product/20261010-hover-checkpoint/unpromoted/bar-cava-candidate.qml)
  (copied from `/tmp/hadalis-bar-cava-candidate.qml`); product code is unchanged. Require actual
  QV4 exact sample/level parity, unchanged scratch/NOTIFY, strict render comparison
  and measured cost before implementing. Preserve upstream-like bounce, CAVA
  ownership, warm reopen and every animation/frame cadence.

- [ ] **Remaining optimization candidates:** read the current audit tail,
  distinguish CONFIRMED/HIGH CONFIDENCE from hypotheses and retire duplicates.
  Recent Notepad normalization, Overview record lookup and shared Search prefix
  findings still require their native reactivity/identity and measurement gates.
  Preserve filter-before-map observable reads in existing Abyss reductions.

- [ ] **Frozen visual qualification:** G0 `dc4d5ecfe118` remains
  `INCONCLUSIVE_CAPTURE_VARIANCE`. Analyze only saved receipt/PNG data offline;
  do not replay consumed lineage or lower strict RGBA. Do not change quality
  tiers on an unexplained translucent-pixel variance. Owner multi-output and
  whole-session resource acceptance remain separate.

## Alis Settings and Integrations redesign — owner request 2026-10-11

These items improve existing Settings/navigation and the optional integration
installer; they are NOT new third-party backends. Retain task status in Alis
dev even when implementation belongs to Alis-Intergration `main`.
Do not remove functionality, break direct Settings navigation or silently
run privileged installation just because manual buttons are retired.

- [ ] **SET-R02 — Redesign all Settings task sub-tabs for Abyss Panel — owner screenshots 2026-10-11:**
  [Owner: Alis dev; Rework/UX] All *secondary in-page task tabs* in
  Settings currently use the old compact, separate dark pill/chip
  styling. Redesign the entire shared tab family to visually belong
  to the **Abyss Panel**: a coherent liquid/connected or soft sculpted
  silhouette with restrained curvature, appropriate spacing and
  padding, clear selected/hover/focus states, readable icons and labels,
  matching Abyss material, accent, opacity and theme tokens. Aim for
  consistency with the real Abyss connected/glass surface and compact
  Settings layout, not an unrelated floating chip bar; preserve
  touch/keyboard hit target and WCAG-appropriate contrast where
  feasible. Do not force one color regardless of active desktop
  theme or add unnecessary GPU blur/shadow passes for simple tabs.

  **Owner example screenshots, supplied in 2026-10-11 chat (not yet
  persisted in Git):** (1) Displays / Input / Layout / Animations /
  Rules; (2) Audio / Power / Fan Control / Locale / Input / Safety;
  (3) Outputs / ii surfaces / Desktop widgets / Popups;
  (4) Colors / Type / Motion / Advanced. **These are EXAMPLES, not the
  full target list.** Inventory and apply to **ALL** existing and
  dynamically supplied Settings task/subsection navigators throughout
  both Settings Overlay and standalone Settings, Abyss surfaces and
  optional Integration settings. Audit `modules/settings/**`,
  `modules/waffle/settings/pages/**`, Companion/Integration page
  loaders and any local look-alike tab implementations; consolidate
  common visual behavior, do not hand-tune only four screenshot pages.

  **Concrete source discovery:** `modules/common/widgets/SettingsTaskNavigator.qml`
  currently intentionally sets `useAbyssPillShape: false` on
  `ConfigSelectionArray`, which supports an Abyss pill shape;
  `scripts/test-settings-inir-task-tabs-contract.py` currently
  *asserts that old iNiR appearance is retained inside Abyss*.
  Review `ConfigSelectionArray.qml`, its underlying selection button,
  `SettingsMaterialPreset`/shared styling and page-specific tabs.
  Change the shared Abyss-family style and update/replace the obsolete
  old-style test expectation; do not just flip one flag if shape,
  connected-surface flow, corner animation and accessibility are
  visually wrong. Keep Waffle/ii-specific styling where deliberate;
  make the effective presentation obey the selected shell family.

  **Interaction/regression:** do not change the set of tabs, selected
  values, section IDs, route keys, Settings search/deep links, saved
  page/section history or page loading/lazy activation. Verify long
  text/translations, tight screen widths, horizontal wrap/scroll
  without clipped controls, reduced-motion and fractional DPI;
  hover reversal, focus ring, arrows/tab/Enter/Escape, disabled
  states, dynamic app install/uninstall, both themes/output scales
  and no surprise settings navigation. Coordinate with SET-R01
  (remove unnecessary cross-page redirect buttons) and INT-R02
  (new Integrations Settings/Management hierarchy) so they reuse
  exactly the same component, not duplicate custom tab bars.

  **Acceptance:** one authoritative tab component/theme policy;
  source-wide inventory of all consumers (including hidden/lazy
  pages), before/after screenshots and owner review for every
  navigation family, focused QML/JS tests updated, canonical
  validation and live Niri Quickshell visual/interaction signoff.
  State: OPEN; screenshot-based requirements and source candidates
  identified, redesign/implementation NOT STARTED.

- [ ] **SET-R01 — Eliminate redundant Settings-to-Settings navigation buttons:**
  The maintainer wants **no Settings action whose only purpose is to switch
  to another Settings tab/page**. Perform a complete source/UI audit of
  `modules/settings/**`, Waffle Settings pages and the shared Settings
  registry/search/deep-link navigation. Remove pure redirect cards/buttons,
  extra promotional links and duplicate destinations, **not functional
  controls**. Owner examples include **"Use opaque Material Appearance"**
  (first locate whether it is merely navigation or changes a real value),
  **"Configure Bar modules"** (confirmed `ModulesConfig.qml` → page
  `abyss-modules`), and other unnecessary tab-hopping UI. Verified
  candidates in `dev`: `ModulesConfig.qml` "Open Typography settings";
  `QuickConfig.qml` "Bar & layout/Taskbar settings", "Wallpaper settings",
  "Theme settings", "Capture settings"; `InterfaceConfig.qml`
  "Manage availability in Shell & interface"; `ServicesConfig.qml`
  "Bar weather module" and "Obsidian, Calendar and Music Recognition";
  `SidebarsConfig.qml` AI privacy/Policies and
  `GeneralConfigCore.qml` AI privacy. Inspect their actual effects and
  eliminate only **pure navigation** after verifying what is redundant.
  Preserve real controls (e.g. Open floating tools, reset, apply, install,
  search, breadcrumb/back and system confirmation actions), direct
  navigability via the standard Settings hierarchy, Settings search
  results, saved deep links and existing Waffle/Abyss functionality.
  Do not duplicate entire page content in the original page.
  Acceptance: Settings route inventory with action-by-action decisions,
  no unnecessary cross-tab button remaining, keyboard/Back/Escape,
  Settings search, saved page selection, themes and both shell families
  passing focused and native owner UI checks. State: OPEN for
  inventory/removal; no code changes yet.

- [ ] **INT-R01 — Move TLP and Thinkfan Settings into Integrations → Settings:**
  [Owners: Alis dev host + Alis-Intergration main optional views]
  Currently `modules/settings/GeneralConfig.qml` embeds
  `TlpPowerSettings` under **System → Power**, while
  `GeneralConfigCore.qml` embeds `ThinkfanSettings` under
  **System → Fan**. Move optional app-specific TLP and Thinkfan editors
  out of the System page and into **Integrations → Settings → TLP/
  Thinkfan** as proper app subtabs (same behavior for Abyss and Waffle
  through `WIntegrationsPage.qml`). Preserve Core Battery/Power
  Profiles, warning/suspend settings and generic fan readings where
  they belong; do not move basic host-owned functionality with the
  optional package. Fix `SettingsPageRegistryData.qml`, section
  search, legacy TLP page index 28, persisted selection, focused
  shortcuts/deep links and module lazy loading to route the old
  destinations to the new Integration subtabs. With optional
  package missing/off, present a concise unavailable state without
  loading plugin QML or silently installing it. Preserve real
  TLP/Thinkfan values, apply/rollback and trusted policy boundaries.
  State: OPEN; migration tests, cross-repo source identity and owner
  Settings acceptance required.

- [ ] **INT-R02 — Redesign Integrations around exactly two top-level tabs:**
  The Integrations page should have **Settings** and **Management**,
  with compact, clear design and responsive layout. **Settings**
  contains secondary tabs for each supported app, including TLP,
  Thinkfan, Obsidian and existing Calendar/Applications configuration
  where appropriate. **Management** owns third-party app enable/
  disable toggles, availability/version/health, progress, errors,
  optional package install/update/refresh and nonprivileged
  rollback/removal as appropriate; toggling never silently changes
  privileged host policies. Current `IntegrationsConfig.qml` has
  one tall "Optional integrations" management section mixed with
  Obsidian/Calendar/Applications navigation and direct manual Gateway/
  Helper actions; replace this with an accessible two-level navigation
  model instead of adding a duplicate layer of cards. Audit dynamic
  Integration settings from Alis-Intergration, unsupported packages,
  active worker/disabled state, empty/loading/errors, keyboard/back,
  narrow screens, long app names, responsive scrollbars, search and
  saved page restoration; Waffle `WIntegrationsPage.qml` delegates
  to the same shared component. **Gateway/Helpers install/remove
  controls do not belong in Management** once setup ownership is
  validated; display concise dependency state/error only if useful.
  State: OPEN; UI hierarchy, lazy source, native and owner acceptance.

- [ ] **INT-R03 — Installer-managed Gateway and Helpers across Alis setup lifecycle:**
  Move approved Gateway and Integration system-helper provisioning
  from manually pressed Settings buttons to the supported **Alis
  `./setup install` / reinstall / update** flows (and relevant
  package-managed paths). Audit actual supported setup subcommands
  and `sdata/subcmd-install/*`, migration/update/uninstall scripts,
  `scripts/hadalird-system-package.py`,
  `assets/helpers/inir-hadalird-system-provision`, system Polkit
  assets, `services/Hadalird.qml` and Alis-Intergration
  `Makefile`/`make install-helpers`. Automatically detect, reconcile
  and **prepare** the trusted, version-matched Gateway/Helpers so the
  user does not need separate manual Settings installation. Where
  privileged writes are required, use supported package-manager/
  Polkit/sudo authorization during setup with an **explicit prompt**;
  do not self-elevate silently, run a user checkout as root or
  bypass system ownership/security. If declined, missing, unsupported
  distribution or offline, keep Alis functional and report a clear
  deferred/unavailable state and safe retry path without falsely
  claiming successful installation. Never install third-party apps,
  enable TLP/Thinkfan services or change charge/fan policy merely
  because setup ran. Handle install, idempotent reinstall/update,
  source checksums/signatures, existing compatible binaries,
  partial/uncertain results, rollback, removal/uninstall and
  package ownership without duplicate helper versions. Remove
  **manual Gateway/Helpers buttons from Integrations** only after
  provisioning is verified; preserve observability, user consent and
  explicit helper-removal authority. Use
  `scripts/test-hadalird-gateway-bootstrap.py`, system provisioning,
  install lifecycle and Polkit tests plus a real authorized machine
  acceptance; tests must not mutate personal/system policy.
  Cross-reference existing privileged
  [Hadalird/Polkit Issue](ISSUES.md); do not duplicate an already
  indeterminate privileged action. State: OPEN, security/packaging
  design and explicit native install permission required.

- [ ] **ABYSS-R01 — Comfortable corner clearance in Edit Abyss Layout:**
  The user wants Screen Edge modules **visually close to, but never
  actually flush against**, physical screen corners while
  **Edit Abyss Layout** is active. Replace the current true-endpoint
  drop/snap packing with a small consistent **corner-safe inset** for
  module content/hit target: `modules/abyss/looks/AbyssLayout.js`
  currently uses `margin = 0` in both `snapMove` and `geometry`,
  and `scripts/test-abyss-module-layout.py` explicitly asserts a
  module can touch the physical endpoint. Update the source behavior
  AND those now-obsolete assertions, including deterministic drag,
  snap guides, start/end alignment, saved normalized positions,
  per-output overrides, compact layouts and all four edges/scales.
  Derive an aesthetically modest clearance token from existing
  edge/corner geometry and viewport bounds, not a large fixed
  exclusion that wastes space. Distinguish **module content clearance**
  from optional `joinCorner` visual field/Popup attachment:
  allow the selected decorative liquid connection to bridge the
  remaining gap without extending the actual interactive module
  into a hard corner or blocking Niri hot corners. Preserve
  collision packing, multi-selection work, small-monitor clipping,
  full Edit → Save/Cancel → reopen consistency and correct
  normal-mode rendering after the edited layout is committed.
  State: OPEN; design/source/unit/native visual tests and owner
  acceptance pending.

## Existing UI and layout

- [ ] **Quickshell typography consistency — owner request 2026-10-10:**
  Standardize inconsistent text appearance across Quickshell: review font
  family/fallback, size, weight, text color, alignment, line height and theme
  roles. Reuse shared text tokens without removing intentional heading/body
  hierarchy or legitimate Abyss/Waffle distinctions. Qualify Panel, Popup,
  Settings and edit surfaces at varying scales and light/dark themes. State:
  READY for UI audit; owner visual acceptance pending.

- [ ] **Compact Edit Abyss Layout control bar — owner request 2026-10-10:**
  Redesign controls for BOTH horizontal and vertical edit orientations to
  occupy less room while preserving discoverable actions, module context,
  per-edge editing, Cancel/Undo/Done, input targets and narrow-screen access.
  Test four edges, long labels, expanded edit controls and interaction with
  screen-edge modules; coordinate with new multi-selection functionality in
  [New features](NEW_FEATURES.md). State: READY for compact design; native
  input/layout and owner visual acceptance pending.

- [ ] **Wi-Fi and Bluetooth Popups about 35% smaller — owner request 2026-10-10:**
  Reduce each Popup's displayed footprint by roughly 35% (target about 65%
  of previous width/height where viable). Preserve readable status/rows,
  usable hit targets, connection/discovery, loading/error/empty states and
  scroll access. Test long networks/devices, small screens, all attached edges
  and scaling. Separate from existing Wi-Fi/Bluetooth missing-text bug in
  [Issues](ISSUES.md). **SOURCE PATCH on dev (2026-10-11):**
  `17210c7a65c6d9f93e12e8e861adb803859c234e` reduces the
  shared `AbyssNetworkPopup` from 380×500 to 260×330 (68%/66%
  of prior dimensions), preserving the embedded mature Wi-Fi/
  Bluetooth forms and scrolling. The existing native network popup
  fixture now expects this geometry, but has NOT run in a local
  Wayland session. State: SOURCE PATCHED; native 4-edge input,
  scrolling, long names, password/pairing, scales and owner signoff OPEN.

- [ ] **Monitor Arrangement tiles about 30% smaller — owner request 2026-10-10:**
  Reduce UI monitor tiles by roughly 30% (about 70% of former displayed width/
  height), never real display resolution or compositor placement. Maintain
  correct aspect labels, selection/dragging, snapping, multi-monitor layouts,
  non-overlapping controls and responsive hit targets. Related to existing
  Utilities acceptance in [New features](NEW_FEATURES.md), not a new backend.
  **SOURCE PATCH on dev (2026-10-11):**
  `2ca620ea912e3eb8475a6e380d5b942004cd483d` updates only
  `arrangementVisualScale` to 0.65 embedded (was 0.92) and 0.70
  in Settings (was 1.0), yielding ~29–30% smaller monitor tiles.
  The logical Niri output coordinates, bounds, drag snapping and
  save/rollback paths are untouched; Utilities test expectation
  updated. State: SOURCE PATCHED; local drag/hotplug/scale,
  label readability and owner visual acceptance still OPEN.

- [ ] **Quick Notes Edgebar scrolling sensitivity — owner request 2026-10-10:**
  Tune wheel/touchpad scroll speed for predictable navigation, including
  Shift-held scrolling while performing bulk selection. Inspect modifier/event
  routing and nested scroll containers; preserve range selection, existing
  note focus and selection state without unexpected horizontal scrolling,
  acceleration or skipped notes. Check long lists, trackpad/wheel, different
  scales and ordinary versus Shift navigation. State: READY for interaction
  tuning; preferred speed and owner acceptance require native input retest.

- [ ] **DASH-R01 — Smooth Dashboard slide-in and slide-out — owner report 2026-10-11:**
  [Owner: Alis dev; Rework / animation performance] The **whole
  Dashboard** does not slide smoothly when **appearing or closing**.
  Improve both entrance and exit on the real desktop, preserving the
  connected Abyss presentation, the existing appearance/theme and
  the chosen motion language. This task concerns the main Dashboard
  surface, **not** the already source-tested 'Edit Dashboard toolbar
  slide' item immediately below and not the separate horizontal
  Dashboard Music page navigation.

  **Audit the two current presentation paths and actual active host:**
  `modules/dashboard/Dashboard.qml` (standalone retained PanelWindow,
  `_presentationTimer`, `_presentedOpen`, `panelTranslateY`,
  `_hideContentTimer`/`_renderSuspendTimer`, SurfaceMotion enter/exit
  duration/easing) and `modules/overview/OverviewDashboard.qml`
  (Abyss/Overview `popupPresented`, first reveal frame,
  `revealProgress`, bottom-edge Translate and search switch).
  Inspect `modules/abyss/content/AbyssDashboardContent.qml`,
  `modules/abyss/AbyssPerimeter.qml`, shared `SurfaceMotion` tokens,
  compositor window presentation, input mask/body allocation and
  expensive Dashboard child loaders. Determine which surface is
  actually used for the owner reproduction; do not assume the
  one-frame 16ms staging timer, easing, Qt render work or compositor
  is the cause before event-backed measurement.

  **Desired behavior:** consistent smooth slide from its correct
  attached screen edge into the workspace and back, with no
  perceptible first-frame jump, pop/fade replacing the slide,
  hitch, end-of-motion snap, stale frozen frame, blank/cyan flash,
  content resize during motion or abrupt disappearance at close.
  Close must visually finish **before** paint/layer/content is
  released, but focus and interactive hit regions must be revoked
  at the correct stage; rapid reopen while closing should reverse
  from the current presentation state without restarting from
  a hidden origin or creating a duplicate surface. Keep widgets'
  state, loaded media/artwork, search/Overview navigation and
  edit-mode content intact. Avoid forced full-surface FBO copies,
  always-on animation loops, cosmetic opacity-only workarounds
  or quality reductions that conceal real stutters.

  **Evidence and tuning:** capture source/installed SHA plus actual
  open/close event timestamps, first presented frame, translation
  progress, map/unmap/content lifetime, Qt `frameSwapped` p50/p95/p99
  intervals, input-region changes and bounded CPU/GPU diagnostics
  when supported. `frameSwapped` is NOT compositor present timing;
  characterize vs separately observed actual Niri presentation.
  Compare cold first open, warm reopen, settled/idle and loaded
  Dashboard widgets, avoiding a numerical smoothness claim from
  one unmatched clip. Reuse the existing [Abyss Panel motion
  investigation](REWORK_OPTIMIZATION.md) and the planned opt-in
  profiler rather than changing unrelated SurfaceMotion curves
  or assuming source contract PASS proves live smoothness.

  **Regression/acceptance:** first open and repeat open/close,
  close→open / open→close rapid reversals, keyboard/shortcut/
  click-outside and Escape dismissal, Dashboard ↔ Search /
  Overview transitions, edit mode, music page, fullscreen,
  multiple outputs, bottom/left/right attachment where supported,
  small screens, fractional DPI, light/dark and reduced-motion
  / animations-disabled mode. Test no ghost input blockers,
  widget resets, lost pointer/focus, content flash or visually
  disconnected Abyss edge while moving. Update focused Dashboard
  motion lifecycle/Qt contract tests (including
  `scripts/test-dashboard-presentation-motion-contract.py`) and
  perform real owner Niri/Quickshell visual/performance acceptance
  on the exact tested SHA. State: OPEN; diagnosis, implementation
  and native owner smoothness acceptance pending.

- [ ] **Edit Dashboard toolbar slide — received/updated 2026-10-10:** pushed
  `8c673129b58dbde73bf31c82df25c1085bf63e15` slides full-size connected controls
  from the attachment using the shared motion token. Input follows the clipped
  reveal; exit retains its footprint and releases input immediately. Native
  16 Dashboard/Overview × edge × size cases, reversal, complete exit, reduced
  motion, stable canvas and Undo/Cancel/Done pass. Its focused check also passes
  in the exact `10311cd96` canonical run, whose overall result is FAIL 327/8/1.
  State: source/focused-qualified; owner appearance acceptance still pending.
  [Durable focused evidence](../../docs/evidence/abyss-product/20261010-hover-checkpoint/hadalis-dashboard-toolbar-slide-motion-20261010.log).

- [ ] **Abyss Waves:** verify round crest-only geometry, no trough erosion or
  needle peaks, restrained breaker/whitewater, continuous distance attenuation,
  stable same/opposite-direction interaction and idle sleep. Preserve one shared
  wave-strength control/migration, optional/default-off waves and reduced motion.
  Calm stays below Balanced (the former Calm); Fluid/Deep should be distinct and
  restrained. Detailed wave controls belong to Custom; show numeric audio strength.

- [ ] **ABYSS-R02 — Checkbox to preserve rounded INNER workspace corners at 0px Edge width — owner clarification 2026-10-11:**
  [Owner: Alis dev; Rework] **FINAL OWNER-APPROVED GEOMETRY INTENT:**
  When an Edge in **Edit Abyss Layout** is configured with effective
  **Edge width = 0px**, offer exactly **one independent CHECKBOX option**
  such as **'Round inner workspace corners at 0px'**. With it ON,
  the workspace's **INNER boundary corners** at the physical monitor
  corner retain their smooth, concave/transitional curvature: e.g.
  at the top-right of the workspace the inner TOP edge flows by a
  quarter-curve into the inner RIGHT edge; likewise bottom-right,
  top-left and bottom-left. The 0px side has no full-width painted
  strip, but the small localized corner geometry must remain visible.
  This is the **workspace-facing inner silhouette**, NOT a rounded
  independent module, NOT its physical/outside monitor-facing
  shoulder, and NOT the outer rectangle/frame border.

  **Reference, reinterpreted correctly:**
  ![Owner crop: top-right INNER workspace corner arc, not a module shoulder](../../docs/abyss/references/physical-edge-rounded-shoulder-20261010.png)
  See the owner's later full right-edge screenshot and explicitly
  confirmed OFF (90-degree inner workspace corner) vs ON (smooth
  rounded inner workspace corner) illustration in the conversation.
  The previous detached-pill/rounded-module and outer-liquid-shoulder
  interpretations are **REJECTED** and must not guide implementation.

  **Geometry/controls:** Checkbox ON uses the EXISTING global
  **Curvature** control from Settings (`abyss.perimeter.radius`,
  `AbyssStyle.perimeterRadius`), with no extra independent radius slider.
  Outer physical screen boundary remains straight, clipped to the
  output and fully attached; the rounded arc is entirely at the
  **inner workspace boundary** where adjacent Screen Edges meet.
  Do not add physical-edge padding, detach modules, turn the 0px
  edge into a visible full strip, or add a floating outline.
  Checkbox OFF retains current zero-width square-corner behavior
  for existing users and saved layouts. At width greater than 0px,
  the checkbox is disabled/hidden with an explanatory hint and
  must not replace/change normal current Curvature behavior.
  Show an immediate geometry preview when checked/unchecked;
  when the global Curvature changes, the enabled inner arc follows.

  **State/persistence:** Place the checkbox close to Edge width
  in `modules/abyss/AbyssEdgeEditor.qml`; support chosen top,
  bottom, left and right Edge, per-output layout overrides and
  legacy defaults. Save/Cancel/Undo/Reset, hot reload and session
  restart must preserve both the choice and normal settings.
  Coordinate combinations at one monitor corner if its two meeting
  Edges have different 0px checkbox states; choose a deterministic
  corner-ownership rule so there is no seam, double arc or ghost
  curve. This option is distinct from `Module rounding`,
  `Width affects modules`, `joinCorner` and the separate ABYSS-R01
  *distance between modules and physical screen corners* rework.

  **Implementation audit:** `modules/abyss/settings/AbyssStyleSettings.qml`
  exposes `Curvature`; `modules/abyss/looks/AbyssStyle.qml` owns
  `perimeterRadius`; `modules/abyss/looks/AbyssGeometry.js` currently
  uses a special negative extent for any zero inset in its
  workspace distance field; `modules/screenCorners/ScreenEdges.qml`
  and `ScreenEdgeField.frag` have a separate inverted rounded
  workspace/frame representation. Identify the actual Abyss
  presentation path and preserve the existing single SDF/paint
  ownership and strict-lossless visual contract; do NOT blindly
  add a second overlay or change the unrelated physical Screen
  Edge/ii/Waffle corner implementation. Implement localized
  0px-corner behavior without creating a transparent input blocker.

  **Acceptance:** Compare real Niri/Quickshell output against
  the confirmed inner-boundary illustration, with visible arc
  and correct tangency at top-right/bottom-right/top-left/bottom-left.
  Test checkbox OFF/ON, one or both meeting edges at 0px,
  zero/nonzero edge-width transition, different global Curvature
  values, all four edge orientations, per-output settings,
  fractional DPI, dark/light, fullscreen enter/exit, Popup hover,
  save/cancel/undo/reset, close/reopen/restart and performance.
  Preserve existing nonzero-width corners and compositor hot
  corner input. Update focused QML/JS/field pixel tests and
  obtain owner visual signoff.
  State: OPEN; corrected checkbox specification only, NOT IMPLEMENTED.

- [ ] **ABYSS-R03 — Smooth module movement and repacking on Screen Edges — owner request 2026-10-11:**
  [Owner: Alis dev; Rework/Optimization] Improve the perceptual and
  actual responsiveness of Screen Edge modules while editing a layout:
  module drag follows the pointer smoothly with stable timing, snap
  target/guides feel predictable without jolts, and neighboring
  modules do not visibly jump or oscillate during reordering, add/
  remove, resizing, edge transfers and editing-to-normal transitions.
  Preserve existing liquid/connected geometry, theme, animation
  quality, native click/hover regions and regular Popup attachments.
  No forceful artificial tween that makes the drag target lag behind
  the cursor or obscures unexpected automatic packing.

  **Source starting points:** `modules/abyss/AbyssEdgeEditor.qml`
  updates the draft via `move` / `snapMove` during each pointer
  change, refreshes guides and schedules toolbar relocation;
  `modules/abyss/looks/AbyssLayout.js` recomputes geometry and uses
  a sort + forward/backward collision-packing pass that can shift
  neighboring records. Determine real update/event, QML binding,
  rendering and input cost before making a change; those source
  observations alone do NOT prove why the user perceives stutter.
  Keep the drag gesture's hot path bounded, avoid repeatedly
  rebuilding heavyweight content or writing Config per motion
  event; stabilize drag anchor, snap hysteresis, toolbar placement,
  visual/interactive geometry and deterministic placement across
  frames. Investigate excessive recomputation, competing input
  handlers and renderer re-layout with source-pinned trace receipts.
  Reuse the Alis opt-in performance profiler where available.

  **Lock integration:** coordinate with `ABYSS-F01` in
  [New features](NEW_FEATURES.md): collision and animation updates
  MUST NOT move a locked module. Animate/reposition only eligible
  unlocked neighbors and show an unambiguous blocked-state cue
  rather than snapping a different locked item out of place.
  **ABYSS-R01** corner spacing, **ABYSS-R02** inner corner rounding
  and pending Edit Layout multi-selection remain independent;
  ensure there are no conflicting snapping, clipping or saved-layout
  rules among them.

  **Acceptance:** deterministic source tests on the actual packing
  engine for crowded/sparse edges, long/fast repeated drags,
  crossing edges/corners, snap on/off, adjacent-locked obstacles,
  module size/visibility changes and per-output persistence;
  p50/p95/p99 drag-to-render/frame timing with exact source SHA
  and matched baseline where native capture is supported (no
  invented FPS/CPU gains). Check four edges, fractional DPI,
  small and multiple monitors, themes/reduced-motion, hover/click
  handoff, Edit → Done/Cancel/Reset → reopen, and owner visual
  acceptance under real Niri/Quickshell. State: OPEN; diagnosis,
  implementation, native smoothness proof and owner signoff pending.

- [ ] **Screen Edge/module editor:** verify separate 0px-capable widths on all
  four edges, thickness-only versus inherited module sizing, per-module overrides,
  joined nearby modules when width does not affect them, nearest-corner joins
  and adjustable module curvature. Editor owns sizing with one-module partial/
  whole-edge choice, guides/snapping and saved per-output drafts. Dragging should
  not reload heavy content or persist the full config on each pointer event.

- [ ] **Connected presentation:** finish owner appearance acceptance for Popup,
  Sidebar, Dock, Dashboard, Settings, OSK and IPC on every edge and scale. Keep
  anchored full-size reveal/retract, readable reflow and older-body slide-close
  when allocation cannot fit. Center Sidebars on physical left/right edges;
  preserve custom dimensions and hot corners. Dock content must not shrink/jitter.
  Remove redundant tooltips, stray borders and repeated row fills while retaining
  intended enclosing-panel opacity/blur and click ripples.

- [ ] **Settings refinement:** compact iOS-like parent/child navigation, Abyss
  before Waffle, no duplicate destinations/headings or generated More groups,
  one editor entry beside Lock, stable order/search/deep links and complete lazy
  pages. Keep meaningful slider units and avoid multiplying Dashboard opacity
  twice. Qualify System Monitor two-digit widths/RPM icons and OSK content-sized
  footprint. Waffle remains supported; historical ii/
  style values serve safe migration/content reuse, not a removed live theme.

- [ ] **Dashboard Music presentation:** qualify horizontal page slide and
  centered dots on the controls/uptime row; Genre/Folders tabs and multi-selection,
  folder drilldown and combined result column, shared Media/EQ DSP, bottom-anchored
  upward Queue expansion, Lyrics auto-hide and responsive remaining widths.
  Source/focused native tests already cover these behaviors; owner video/input
  acceptance is pending. Playback correctness is tracked only in Issues/bugs.

- [ ] **Recording presentation:** `fafb4687b` connects one shared control set
  to the Abyss field/allocator/input mask while retaining ii/Waffle presentation.
  Native tests pass four-edge controls, drag, connection hover, auto-hide/recovery,
  Stop callback and idle/secondary-output allocation. Confirm owner appearance
  and an actual recording/stop. No owner recording was started/stopped in fixtures.

- [ ] **Wallpaper picker polish, filename-only labels and live theme preview — owner update 2026-10-11:**
  [Owner: Alis dev; Rework] Qualify the connected thumbnail selector
  against the supplied reference, restrained search icon, borderless action
  buttons and Abyss-styled tooltips. Remove `>wallpaper`, `(grid)` and
  `(overflow)` labels from the retired picker. **When opening Change
  Wallpaper / browsing/selecting images, display only each file's basename
  (e.g. `forest.jpg`), NOT its full absolute or relative directory path.**
  Cover Wallpaper Launcher carousel/cards (currently
  `WallpaperLauncherItem.qml` displays `modelData.relativePath`,
  potentially including nested directories), selector grids, quick selectors
  and visible selected-wallpaper labels/tooltips. Use the existing
  `WallpaperLibrary.qml` `name` field or
  `FileUtils.fileNameForPath` for presentation, preserving extension,
  Unicode and truncation/ellipsis; when two files share one basename,
  retain separate selectable entries and disambiguate on deliberate details
  view, not by always showing long paths. **Keep the complete normalized path
  internally** for identity, selection, opening, applying, multi-monitor
  routing, storage and export; never apply by basename alone.
  Preview Edge/Panel/Popup colors while browsing, restore on cancel and
  retain the chosen palette on apply. Verify deeply nested directories,
  duplicate names, very long/Unicode filenames, path with spaces,
  local and animated media, selected/current indicators, keyboard search,
  alternate outputs, translations and actual native UI labels.
  Actual wallpaper application is tracked only in Issues/bugs.
  References: `/tmp/codex-clipboard-c5723427-ceae-4515-a739-3010f8a551fa.png`,
  `/tmp/codex-clipboard-3baf8385-6e63-4e7b-8306-0e0ec31f3be9.png`.
  **Filename-label source patch on dev (2026-10-11):**
  `991e5de00b6ad415fcfa42c412e04dbe3e11de16` renders
  `WallpaperLauncherItem` from the existing `WallpaperLibrary.name`
  basename WITH extension, while selection keeps the full path;
  the native carousel fixture now checks its displayed labels.
  Remaining selector/tooltip duplication audit, live theme preview,
  wallpaper application bug, native visual and owner acceptance
  are NOT covered by this commit. State: PARTIAL SOURCE PATCH; OPEN.

- [ ] **WALL-R01 — Rename iNiR Melt transition to Liquid and restore its effect safely — owner request 2026-10-11:**
  [Owner: Alis dev; Rework/transition identity and quality] Rename the
  **user-facing wallpaper transition** currently labeled
  `Liquid melt (iNiR)` to exactly **`Liquid`**, including its short
  description, settings selection, tooltips/help and relevant translated
  strings. The intended effect is the existing flowing/liquid melt, not a
  renamed ordinary fade pretending to render liquid. Source locations:
  `modules/settings/BackgroundConfig.qml` (`Liquid melt (iNiR)`,
  `inirMelt` option/description);
  `modules/common/widgets/WallpaperCrossfader.qml` (shader gating,
  transition state/fallback); and
  `modules/common/widgets/wallpaperTransitions/inirMelt.frag[.qsb]`.
  Preserve saved `background.transition.type = "inirMelt"` profiles
  by mapping them compatibly to the new `Liquid` UI selection. If a new
  internal identifier `liquid` or shader asset name is introduced,
  version/migrate config, programmatic callers/tests and installed compiled
  QSB atomically, without losing settings or silently disabling the effect.
  This task is also a concrete surface of the broader Alis identity rebrand.

  Diagnose why the Liquid effect is not working on the real Qt/Wayland
  renderer before calling it fixed. Assess actual shader compilation,
  texture priming, `frameSwapped`, QSG backend capability,
  compositor behavior and presentation sequencing; the current
  experimental flag `INIR_EXPERIMENTAL_MELT` and automatic crossfade
  fallback are not evidence of a working Liquid visual. If supported,
  restore a genuinely visible liquid animation with bounded resources
  and strict-lossless pixels before/after transition; when unsupported
  or failing, degrade gracefully to a real crossfade/instant switch,
  show accurate status as useful, and do not leave selection or image
  application blocked. **Functional wallpaper-switch failure itself is
  owned by the linked existing [wallpaper Bug](ISSUES.md), not a duplicate
  Rework fix/closure.** Avoid transition quality reductions elsewhere
  and do not run infinite render/poll loops.

  Acceptance: Settings displays only `Liquid`, existing `inirMelt`
  settings remain selected/persist on upgrade, intended fluid animation
  is visibly tested when the real backend supports it, alternate
  compositor/software renderer and forced compile/no-frame/timeouts
  complete a safe fallback, no stuck old desktop wallpaper, correct
  Overview/physical display, rapid repeated selections, durations,
  multiple monitors/fractional scale, fullscreen and owner Niri
  image/video visual signoff. Add focused QML/JS/shader-contract tests.
  State: OPEN; UI rename and native effect validation NOT IMPLEMENTED.


## Product identity, CLI and upgrade compatibility

- [ ] **Rebrand iNiR/Hadalis public surfaces to Alis — owner request 2026-10-11:**
  "Rebranch" here means a full **product rebrand**, not a Git branch-history
  rewrite. The future public shell should consistently show **Alis** from
  first installation to normal daily operation. Preserve historical sources,
  evidence, externally owned Hadanion/Hadalird names and internal compatibility
  requirements. Do NOT blindly replace every occurrence of an old string.
  **Subtasks and acceptance, all OPEN:**
  - [ ] **R1 — Full rename inventory and classification:** enumerate iNiR,
    inir, Hadalis, old repo URLs, INIR_ environment variables, package/service
    names, QML app IDs, IPC targets, config/cache/data paths, shell strings,
    icons and translations. Tag each as user-facing rename, interface
    migration, compatibility alias, historical reference or external name.
    Produce a source-path/consumer matrix and prioritize risk before edits.
  - [ ] **R2 — Public identity consistency:** make active Shell/Panel/Popup,
    Notification/OSD, greeting, Settings/About, tooltips, tray/menu,
    application launch search, error/update/permissions messages and logs
    use one Alis name, product icon and localized terminology. Keep feature
    names Abyss, Waffle and iRiS, and meaningful legacy persisted enums.
  - [ ] **R3 — New install and greeting:** update setup and the installer
    greeting, FirstRunExperience.qml, welcome.qml and BootGreeting.qml.
    First installation must say "Welcome to Alis", display Alis as
    notification sender, offer accurate Alis commands, and keep text
    legible across supported locales/scales. Upgrading a current iNiR user
    must NOT retrigger the first-run wizard or lose wizard completion.
  - [ ] **R4 — Alis command and completions:** migrate scripts/inir and
    installed entry points to a discoverable alis CLI covering real
    run/start/restart/stop/service/status/settings/welcome/logs/doctor/update
    operations and existing supported flags. Update bash/fish/zsh completion,
    launcher hints, keybinds and command examples. Provide an explicit
    temporary inir forwarding compatibility command with regression tests.
  - [ ] **R5 — Quickshell/Niri/IPC/session naming:** plan ShellId, qs -p
    config selector, IPC instance targets, process detection, Niri binds,
    desktop activation and logs. Transition inir.service, compositor wants
    links and ExecStart/ExecStopPost to one new service owner. Never start two
    Quickshell sessions, lose IPC handles, reorder layer windows or break
    restart/cold-boot; preserve a verified rollback.
  - [ ] **R6 — Lossless user-data migration:** safely migrate or alias
    ~/.config/inir, ~/.config/quickshell/inir, cache/state/data, model
    directories and INIR_* overrides to Alis equivalents. Preserve legacy
    illogical-impulse compatibility chain, user settings, themes, layouts,
    first-run marker, notes, credentials, wallpaper paths, models and
    optional service preferences. Detect collisions and symlinks; back up,
    dry-run, make idempotent and fail closed instead of overwriting.
  - [ ] **R7 — Packages, desktop files, native helper ABI:** audit and
    revise .desktop metadata, desktop icons, Makefile, Arch PKGBUILD/SRCINFO,
    install/uninstall hooks, distro/Nix outputs, native/inir-* crates/binaries
    and packaged service assets. Explicitly map sockets, DBus names, Polkit
    action IDs, privileges, allowlists, package managers and ABI consumers
    before changing them; preserve compatibility where needed. No changes
    to standalone Hadalird/Hadanion repos without authorization.
  - [ ] **R8 — Active docs, updates and translations:** update project
    links including old llocphann/Hadalis update endpoints, onboarding
    screenshots, release docs, install guides, commands, messages and
    translated user-facing text. Do not destroy valid historical commit
    references or rewrite old investigation logs to appear new.
  - [ ] **R9 — Automated regression/upgrade matrix:** test new installs,
    in-place iNiR-to-Alis upgrades, mixed/partially migrated paths,
    failed/rollback migrations, XDG/PREFIX variations, systemd lifecycle,
    Niri startup, stale binaries, completions, source-sync and
    package-managed installs, optional helpers, uninstall/reinstall,
    preserved personal data and old-command alias. Run the canonical
    maintainer validator on the exact final SHA.
  - [ ] **R10 — Real owner-desktop release acceptance:** verify first-run
    greeting, shell app identity, every common Popup and system
    notification, Settings, IPC, startup/restart, CLI and rollback under
    real Niri/Quickshell. Prove no stray active iNiR public branding
    except explicitly retained compatibility warnings. Keep OPEN until
    the owner approves; no runtime changes were requested now.

  **Dependency:** coordinate the new performance profiler CLI and config
  identity in New features so both old/current installations can be traced
  safely during transition. State: planning only; NOT IMPLEMENTED.

## Cross-repository Companion and Intergration rework

**Central task intake 2026-10-11:** implementation owners are
[Alis-Companion](https://github.com/llocphann/Alis-Companion) main
(source snapshot 732136ef65bb3c84d9339207210c955759a85b76)
and [Alis-Intergration](https://github.com/llocphann/Alis-Intergration) main
(source snapshot b0c975a7f40bdf531012be326bc728f5c014b696).
These source SHAs identify the import, **not** the installed release or
acceptance. Alis dev holds the ONLY authoritative TODO status; package code,
test scripts and historical receipts remain in each source repository.


- [ ] **AC-R01 — Companion G1 performance, strict-lossless shaders and cost baseline (VIS-03/VIS-05):**
  [Owner: Alis-Companion main] Existing read-only CPU/RSS/PSS sampling
  and comparison scripts are implemented, but no qualified GPU frametime,
  VRAM or whole-shell p95/p99 G1 baseline exists. With exact Alis/Companion
  SHAs, real PIDs and matched hardware/power/DPR, repeat disabled, hidden,
  Aqua/Octo idle/moving/grip/cast and quality tier states at least 3
  times. Sample CPU/PSS separately from actual GPU/VRAM/frame pacing;
  report NOT_MEASURED where unsupported. After G0 passes, test one
  isolated WaterDropletMaterial.frag/OctoTentacle.frag E1 candidate at a
  time against strict RGBA and comparable AB/BA performance. No
  unapproved 2D/hybrid quality downgrade or "optimization %" without
  valid proof. Link to existing Alis Quickshell profiler and strict-lossless
  research; do not duplicate its backlog. State: G0/G1 gated.
  [Renderer source](https://github.com/llocphann/Alis-Companion/blob/732136ef65bb3c84d9339207210c955759a85b76/to-do/cloud-bot/ABYSS_WATER_DROPLET_COMPANION.md).

- [ ] **AC-R02 — Preserve original Aqua/Octo look and physical visual parity:**
  [Owner: Alis-Companion main] Keep one original 3D actor, existing 30
  animation clips per cast, 5.6-second Octo grip/quicksand, physically
  owned motion, palette/face/liquid/cups, pointer pass-through and
  portals for long movements only. Review eye normals/proportions,
  transparent water contact, shadows, four rims/corners, casts,
  fractional DPI, themes, quiet/low-power behavior and input ownership.
  Some native fixtures/source Blender staging passed; reference
  visual parity, GPU budget and owner acceptance remain OPEN.
  This does not replace the new cowork-laptop feature below.

- [ ] **AC-R03 — Existing Companion voice/persona and inference cost (AI P0):**
  [Owner: Alis-Companion main; host AI in Alis dev] JS/Python Aqua/Octo
  persona, reply guard and 14 EN/VN paired prompts already exist.
  Benchmark on an explicitly selected pinned real model/provider:
  distinct casual voices, uncertainty and grounded refusals, repetition/
  crash recovery and human judgment. Record model format/quant, context,
  CPU/GPU offload, warm/cold TTFT, per-turn tokens, peak RSS/PSS/VRAM,
  cancellations and truly disabled baseline. Do not assume archived
  model IDs are installed, download automatically or infer gains from
  fixture-only tests. State: real-model assessment OPEN.
  [AI source](https://github.com/llocphann/Alis-Companion/blob/732136ef65bb3c84d9339207210c955759a85b76/to-do/cloud-bot/WULL_LOCAL_AI.md).

- [ ] **AI-R01 — Existing optional Integration Settings UI parity:**
  [Owner: Alis-Intergration main] Qualify existing TlpPowerSettings and
  Waffle equivalents, ThinkfanSettings, ObsidianThemeSettings and
  ObsidianTodoSettings for theme, readable labels, initial loading,
  backend missing/offline/disabled, error and scaling. Keep one source
  of truth for generic Alis Battery/Todo/Notes, preserve lazy disposable
  package worker lifecycle, native user focus and no implicit root
  actions. State: source implemented, owner visual/host qualification OPEN.

## Documentation maintenance

- [x] **Categorized tasks and shared AI workflow — completed 2026-10-10:**
  three active lists replace chronological/duplicate ledgers; 26 superseded
  documents are archived with evidence/current research preserved. AGENTS and
  all current entry points apply the same policy to Local and Cloud AI: classify
  on receipt, merge/split outcomes, select by category then impact/actionability,
  record dependencies and continue independent authorized work. Completion and
  seven-day archiving preserve unverified gates and concurrent status edits.
  Documentation contracts, Material-only docs, shared workflow links and diff
  checks pass. This is documentation validation, not runtime/desktop acceptance.
  Retain this recent completion until 2026-10-17, then move it to the dated
  chatbot archive.
