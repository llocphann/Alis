# Rework/optimization

**Owner UI follow-up — 2026-10-12 23:46 ICT, Weekly Planner paged Add/Edit Event (source implementation; native OPEN):** `EventsDialog.qml` splits the existing form into two animated horizontal pages in Planner only: page 1 Basic Info, Date & Time, shared Month Calendar and All day/Start/End; page 2 Repeat, Category, Priority, Reminder and related controls. A single 36px rounded-square footer action changes from `arrow_forward` on page 1 to `arrow_back` on page 2. Page transitions do not save or recreate the draft, reset to page 1 on new/edit, and scroll to top; standalone dialog and Calendar Popup retain the one-page layout. For active-only choice labels `ConfigSelectionArray.qml` now stages the previous label's collapse before expanding the new one, reduces horizontal padding/allocates width for a single line, and `SelectionGroupButton.qml` clips the full button and the text viewport so glyphs never bleed beyond the hit surface. Both page/animation policies have source assertions in `scripts/test-weekly-planner-expanded-event-editor-contract.py`. Await exact-commit CI and native Quickshell/Niri tests for rapid left-to-right/right-to-left options, layout at small/large font scaling, page slide timing, keyboard access, Cancel, Save, Delete and owner approval. No migration patch restored.


**Owner screenshot follow-up — 2026-10-12, Weekly Planner Add/Edit Event footer alignment (source patch, native OPEN):** Three bottom icon-only actions Delete, Cancel, Save/Confirm were too close to/cropped against their outer corners in the narrow embedded pane. `EventsDialog.qml` now overrides `WindowDialogButtonRow`'s general `-8px` gutters with equal positive 12px insets on left/right, 6px top and 12px bottom, and fills the available footer width. All embedded Planner icon controls retain a consistent 36px hit target and centered glyph; compact Calendar Popup and standalone modal geometry are untouched. `scripts/test-weekly-planner-expanded-event-editor-contract.py` asserts the geometry. Source patched; exact-SHA CI and owner visual acceptance OPEN.


**Owner correction — 2026-10-12 22:22 ICT, CURRENT POLICY (supersedes earlier migration notes below):** Automatic legacy Events migration was explicitly **withdrawn** by owner. Source commit `477603bbd685` removes `Occurrences.migrateLegacy`, `Events._resumeLegacyMigration`, versioned migration bootstrapping and the migration test. The Events loader now reads stored event rows unchanged; unknown JSON root metadata (including any existing original-event backup) is transparently preserved during later saves. Do **not** automatically merge/normalize old events or restore previously merged events; do not delete owners' data. Existing multi-date `occurrences`, create/edit, reminder and Todo logic remain. `scripts/test-events-no-automatic-migration.mjs` replaces the obsolete test. In Weekly Planner, All day/Delete/Cancel/Save are icon-only with tooltips as in Calendar Popup; full textual controls remain in standalone modal only. Repeat/Category/Priority/Reminder keep a stable `buttonText` and animate a clipped label viewport; active opens left-to-right, inactive retracts right-to-left. Source implementation done; installed SHA, Qt rendering, rapid toggling, click/reopen and CI/owner acceptance remain OPEN. No UI migration button.


**Owner follow-up — 2026-10-12, Weekly Planner Add/Edit Events refinement + v2 automatic migration (native OPEN):** Add/Event title gets top inset; planner Repeat/Category/Priority/Reminder use an opt-in selection component showing icon + text only on the selected option and icon-only (with tooltip and accessible name) otherwise. Start, End and All-day switch occupy one horizontal row. Date & Time embeds the exact shared `ObsidianMonthCalendar` used by Calendar Popup (month navigation, today's date, local/external event dots), rather than the unrelated DatePicker. Editing now shows the labelled Delete/Remove action. Scrollbar is hidden while form Flickable remains usable. Calendar Popup density stays unchanged. **Migration v2** reruns when a store already contains a v1 backup, waits for a *ready* Todo backend before treating absent task identities as stale, safely groups same-title events without a live Todo, and does not merge records with live linked Tasks or another provider. `getUpcomingEvents` now projects all dates of a canonical multi-occurrence Event. Original v1 snapshot retained; no migration UI/button. Tests: `test-event-occurrences-migration.mjs`, `test-weekly-planner-expanded-event-editor-contract.py`, canonical validator. Installed source SHA, live disk migration and pointer/layout acceptance still REQUIRED: do not mark complete yet.


**Owner follow-up — 2026-10-12, Weekly Planner Event editor/resize UI:** `DashboardWeeklyPlanner.qml` now selects roomy `EventsDialog.qml` planner form and `DashTodo`-matching background; Calendar Popup continues compact. Top/bottom resize indicators are 2 px tall, at most 28 px wide, invisible until hover or resize, while preserving 9 px pointer hit areas. Automatic legacy occurrences conversion is handled by `services/Events.qml` on file load without a button; see AGENDA-F02 backlog and regression tests. Source patched; native pointer/render validation and owner acceptance OPEN.


**Source completion checkpoint — 2026-10-12, Owner chưa verified:** CAL-R02 `0caa2e60f`/`23c32b0e2` removes the Calendar-specific Add FAB and date-click opens the same inline Add pane; ABYSS-R13 `7b9cb4fae`/`34ece9d67` retains only IPC/OSD independent placements. These are bot-reported source completions, **not** owner/native PASS. Legacy popup records remain untouched; real 4-edge keyboard/pointer, hover, Cancel and input acceptance remain OPEN.

- [x] **CAL-R02 — Calendar Popup date-click Add Events (owner 2026-10-12):** Remove the "+" FAB only in Calendar Popup; click any displayed calendar day to open its inline Add Event editor with that civil date prefilled. Editing a date preserves other draft fields. Keep other EventsWidget instances, keyboard, Cancel and outside click behavior. Source: `ClockCalendarContent.qml`, `EventsWidget.qml`, commits `0caa2e60f`/`23c32b0e2`. Native exact-SHA, four-edge popup and owner acceptance OPEN.

- [x] **ABYSS-R13 — Edit Abyss Layout IPC-only placement options (owner 2026-10-12):** Remove individual Popup relocation choices from this editor because popups follow Screen Edge modules, while retaining IPC/OSD position previews, per-output overrides and Undo/Done/Cancel. Do not erase legacy stored position data or change popup host ownership. Source: `AbyssEdgeEditor.qml` at `7b9cb4fae`; QML native/owner and installed four-edge acceptance OPEN.


**Quota checkpoint — 2026-10-12 18:08 ICT:** exact five-hour remaining
**2%** triggered stop of all owned product/test processes. Weekly remaining
7% is not the trigger. Source/cache `458ad7197` and evidence `484427acf`
are pushed; valid cloud edits through `be280954e` are preserved locally.
Frozen full clean-clone `484427acf` is **STOPPED, exit -15**, after
**305 completed checks: 282 PASS / 23 FAIL**, without a full summary.
[Raw receipts, frozen driver and focused evidence](../../docs/evidence/abyss-product/20261012-r03-mass-placement-cache/README.md).
Native failures retain their real FAIL status; nested context is recorded,
but no root cause or full-source PASS is claimed. Prior 7e31685bc/cfc852bee
receipts and G0 remain historical/offline; no consumed lineage is replayed.

**Next action after reset:** finish qualification of the current R03 milestone
by diagnosing the relevant failures, then take **ABYSS-R08 immediately** under
the latest direct owner priority. R03 remains OPEN for dense reorder jumps
(the four-module pure case drifts 207 px on a 25 px drag), actual protocol
tracking and owner smoothness. POP-I01 remains OPEN independently. Continue
the remaining explicit queue afterwards. ABYSS-F02's modifier-only Ctrl/Shift
selection already exists in 77bba9432/d982c7d02; do not recreate its toggle.
The existing heartbeat will continue this chat once at **2026-10-12 19:40:35
ICT**, exactly this five-hour reset +3 minutes. Preserve owner preferences,
consent, cowork work and independent installed/multi-output gates.

Follow the [shared feature-first priority](README.md): address Rework and
optimization related to the selected New feature alongside its implementation.
Other work remains actionable when no selected feature can advance.
[The canonical audit](../../docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md)
holds technical research; this file holds pending outcomes.

**Latest owner scope — 2026-10-12:** finish qualification of the current
Dashboard and delivered **R05 → R03/R01 → R02 → R06/R07** group, then
continue **POP-I01 → DASH-F01 → ABYSS-R08 → ABYSS-F02 → NOTES-R01 →
ABYSS-R09 → CAL-R01 → NOTES-F01 → DASH-R03**. The owner explicitly
revoked the previous stop-after-Abyss instruction: **do not stop after that
group**. Handle their related prerequisites in the same single-agent context;
preserve cowork edits, owner preferences and independent verification gates.
ABYSS-F02 is reopened for modifier-based selection: **Ctrl + click / Shift +
click**, without a toolbar mode toggle. Coordinate that correction with R08.
Only exact five-hour remaining below 3% triggers the existing quota checkpoint
and one reset+3minute continuation policy; weekly limits never trigger it.

## Resource use and responsiveness


**2026-10-12 06:53 ICT checkpoint:** feature-first cohort is source/focused;
Dashboard0becc72ab preserves dots-only canvas height and qualifies Music visual
scrollbar preference without changing list allocation or transport. Full
frozen593368c15 [stopped receipt](../../docs/evidence/abyss-product/20261012-593368c15-stopped/README.md)
contains318completed311PASS/7FAIL/0SKIP, no full summary. Related motion/capture,
toolbar clearance, hover and Recording work remains actionable alongside feature
qualification; no RAM/CPU/GPU percentage measured/claimed. Keep G0dc4d5ecfe118
INCONCLUSIVE offline-only; do not replay lineage or reduce strict RGBA. Stop
all work at exact five-hour1%; resume once09:32:29ICT after its reset3minutes.

- [ ] **ABYSS-R09 — Abyss Panel motion stutter — received/updated 2026-10-10:**
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


- [ ] **OPT-R01 — Strict-lossless CPU/RAM/GPU reductions:** re-audit latest `dev` and
  promote high-value findings only after behavior, read/dependency order,
  identity/NOTIFY and lifecycle parity. Keep hidden services/lightweight warm
  surfaces fast to reopen, with heavy unused work asleep. Prefer strict lossless
  or one measured <1% trade for a large benefit; do not accumulate small trades.
  Measure comparable cold/warm/idle/active CPU, RSS, GPU/frames and latency;
  allocation or operation counts are not whole-shell resource percentages.

- [ ] **AUDIO-R01 — Audio Spectrum processing:** investigate the Round 49 profile-factor
  reuse candidate. Source count/profile/stereo/clamped strength are frame-invariant
  until configuration or shape changes. A candidate is prepared only in
  [the stop checkpoint's unpromoted candidate](../../docs/evidence/abyss-product/20261010-hover-checkpoint/unpromoted/bar-cava-candidate.qml)
  (copied from `/tmp/hadalis-bar-cava-candidate.qml`); product code is unchanged. Require actual
  QV4 exact sample/level parity, unchanged scratch/NOTIFY, strict render comparison
  and measured cost before implementing. Preserve upstream-like bounce, CAVA
  ownership, warm reopen and every animation/frame cadence.
  **Preliminary offline stage 2026-10-11:** extracted baseline/candidate
  arithmetic executes in QV4 (Qt 6.12.0): 10,084 cases / 1,364,978 checks
  preserve exact sample, smooth and level vectors plus comparable A/B scratch
  identity transitions. Profile-weight calls are 199,584 vs 11,088 for this
  workload; these are operation counts, not resource or frame-time gains.
  [Reproducer, frozen hashes and boundary](../../docs/evidence/abyss-product/20261011-cava-profile-qv4/README.md).
  **Actual QML stage:** private Niri loads both typed components; 4,704
  frames / 377,954 checks PASS, exit 0, with matching 6,509 `_levelsChanged`
  signals, vectors, stable sample/smooth buffers and published A/B identities.
  Configuration/source/active transitions are covered; full read/dependency
  order and width/density/radius transitions remain open. Opacity is zero:
  no render proof. Strict RGBA and uncontended matched cost remain required.
  Both stage receipts preserve their scope and source hashes. Candidate remains
  UNPROMOTED; product and owner settings are unchanged.

- [ ] **OPT-R02 — Remaining optimization candidates:** read the current audit tail,
  distinguish CONFIRMED/HIGH CONFIDENCE from hypotheses and retire duplicates.
  Recent Notepad normalization, Overview record lookup and shared Search prefix
  findings still require their native reactivity/identity and measurement gates.
  Preserve filter-before-map observable reads in existing Abyss reductions.

- [ ] **VIS-R01 — Frozen visual qualification:** G0 `dc4d5ecfe118` remains
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

- [x] **SET-R02 — Redesign all Settings task sub-tabs for Abyss Panel — owner screenshots 2026-10-11:**
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
  **Candidate in progress 2026-10-12:** shared task navigator gains a single
  themed rail with sculpted selected/hover/focus states, bounded labels and
  keyboard arrows/Home/End/Enter. All current consumers share it, including
  optional Companion and Abyss wrappers; regular value choices and Waffle's
  styling remain separate. No extra per-tab blur, texture or liquid renderer.
  Actual private-native qualification PASS4642 QML checks /168 captures on
  DPR1/1.25, dark/light, font scales1/1.25, narrow/full widths, key/focus,
  disabled and dynamic models, motion reversal and zero opacity. Existing
  Overlay/standalone navigation PASS;22 consumers inventoried; four actual
  page families have before/after captures. Original candidate compile failure
  and subsequent repair evidence are retained.
  [Source hashes, inventory, images and raw checks](../../docs/evidence/abyss-product/20261012-settings-task-tabs/README.md).
  State: SOURCE IMPLEMENTED / focused native PASS.
  Owner visual/physical review and committed canonical remain OPEN.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [x] **ABYSS-R06 — Remove toggles for mandatory Abyss runtime modules — owner 2026-10-12:**
  [Owner: Alis dev; Rework] When Abyss Panel is selected, structural modules
  required for rendering/interaction must be treated as **always enabled**
  and removed from the visible Modules toggle list. Optional modules
  must remain user-toggleable; do NOT classify everything enabled by
  default as mandatory. Inventory dependency/mount chains and document
  a concrete mandatory-vs-optional table before implementation.
  Source: `modules/abyss/settings/AbyssStyleSettings.qml` creates the
  `moduleToggleGrid` from `enabledPanels`; `modules/common/
  PanelFamilyPolicy.js` owns family defaults, migration and reset;
  `modules/abyss/critical/ShellAbyssCriticalPanels.qml` gates the
  one-and-only `abyssPerimeter` SDF field host using `enabledPanels`.
  The Perimeter is a strong mandatory candidate. Individually evaluate
  Background, Bar, Dock, Popup, Sidebar Left/Right, Notification Popup/
  Center, OSD, Clipboard, Overview, Lock, Polkit, Session Screen and
  other panels; do not prematurely force optional or privileged helpers.
  Enforce the required set in runtime AND configuration reconciliation
  (not a hidden switch with an ineffective saved-off value). Preserve
  Waffle, profile migration, old saved `enabledPanels`, reset, optional
  packages, per-output layouts and user-consent boundaries.
  Acceptance: mandatory hosts cannot be disabled on Abyss and
  are absent from the toggle UI; optional hosts still toggle;
  no loss of field, input, fullscreen OSD or startup when old
  profiles disable a required ID. Test migration, switch Abyss/Waffle,
  restart, live Niri on multiple outputs.
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Pre-implementation dependency inventory selects only Perimeter as mandatory.
  Policy, Config load/live mutations and actual critical runtime enforce it;
  its toggle is absent. Optional/security/package preferences and Waffle remain
  independent. Policy 117, family and three Config regressions PASS;
  combined native 165 checks/25 frames/2 processes PASS, actual field readiness.
  [Inventory/evidence](../../docs/evidence/abyss-product/20261012-abyss-r06-r07/README.md).
  Owner/installed/multi-output/fractional and full canonical remain pending.

- [ ] **SET-R03 — Short, essential help text across all Settings — owner 2026-10-12:**
  [Owner: Alis dev; Rework/UI copy] Review **every** Settings page
  (Overlay, standalone, Abyss, Waffle, Integrations, Companion and
  dynamically injected pages) and simplify long on-screen notes,
  descriptions, hints and tooltips into a **few essential words**.
  Remove unnecessary duplication when the label already explains
  the action. Avoid paragraphs, long instructional sentences or
  repetitive headings. Examples from screenshot: the two long
  explanatory paragraphs below Abyss Modules toggles. Search
  `modules/settings/**`, `modules/abyss/settings/**`, other
  supported family pages and shared `SettingsNote`,
  `SettingsTaskNavigator`, `description` and `StyledToolTip` uses.
  Preserve essential consent/security, data-loss and privileged
  operation warnings; move lengthy technical help to discoverable
  documentation rather than stripping safety meaning. Maintain
  localization/source parity, accessible names, Settings search,
  layout/hierarchy and all functional behavior. Acceptance:
  audited copy inventory and brief English UI labels in every
  Settings family; long translations, small screens and native
  owner screenshot review. State: IN PROGRESS / OPEN; partial Abyss, standalone, Sidebar, Waffle, AI and Integration passes.

  **2026-10-12 scoped source milestone (not entire task):** shortened
  11 Abyss help/description strings, merged the two verbose Modules notes
  into one actionable line, preserved individual controls and the wallpaper-
  not-window-capture disclosure. Source `3e524125b`; follow-up test
  `e045cf075`. 17/17 connector-level static source assertions PASS
  (not a native or Python test execution). **Still OPEN:** copy inventory
  and simplification across standalone/Overlay, Waffle, Integrations,
  Companion and dynamically injected Settings, accessibility/localization,
  exact-SHA validator and owner visual/scale approval.

  **2026-10-12 additional cross-family pass:** shortened Sidebar corner/
  hover tooltips (`3210cc2f2`), Waffle General (`42a7360cd`),
  Background (`4fba99955`) and Interface (`209684dd6`) help text;
  synchronized English catalog (`62b2cd27c`, `829e6a60b`,
  `1d85bd00d`) and added regression guards (`32d3cd9be`,
  `9a536d996`). At GitHub HEAD `9a536d996`, 30/30 static source
  assertions PASS, 0 FAIL. Python/QML, canonical, native and owner
  acceptance have NOT been executed or claimed. SET-R03 remains OPEN
  for the rest of the Settings page inventory and native visual review.

  **2026-10-12 continuation — scoped standalone/AI milestone:**
  Revised 22 long UI descriptions across Dashboard, Modules, Advanced,
  Sidebars and Background (sources `3e8f02f13`, `6645b8d14`,
  `e19d95229`, `34f424479`, `0bad688c6`).
  Revised 12 further source occurrences across AI, Waffle AI,
  Integrations, System and Background (`064d3a248`, `5f56a0a48`,
  `296457794`, `f0bd19ea0`, `ba425d9cf`).
  English key parity updated at `916164ccf` and `61fb9f8cd`; safety
  wording about local-only inference, Advanced raw commands, environment-only
  API-key delivery, GPU cost and restart was preserved.
  Regression source at `e4c0c6b1a` and `c3817ef79`. GitHub source-head
  `c3817ef79`: 34/34 new source-plus-locale static assertions PASS,
  0 FAIL across nine page files. **No executed Python, Qt, canonical or
  owner/native test is claimed.** Remaining: full settings-copy audit
  including dynamically injected/Companion pages, translation/source search,
  native small-screen, accessibility, permission-warning and owner review;
  SET-R03 stays [ ] OPEN.

  **2026-10-12 continued Rework milestone (source-only, no runtime claim):**
  45 additional descriptions abbreviated: Services 5, Interface 6,
  Autostart 5, Niri 7, Themes 3, Bar 3, Tools 5, Quick 4,
  Desktop Widgets 5, Monitor Visibility 1, Dock 1.
  Implementation: `ac23efed9`, `f73458e42`, `c42f460f9`,
  `b3ea019c8`, `9a79e3b4b`, `e427f8e3a`, `3b68c5500`,
  `cb3d89ec3`, `82a1cbaff`, `bbc2e6897`, `908d3b47f`.
  Translation additions in `507043a45` and `61add959d` retain
  legacy keys to avoid breaking other users of older English strings.
  The source contract now guards these 45 strings at `ee86c091c`
  and `ad9ffb240`. At source `ad9ffb240`, connector-level read-only
  assertions found **85/85 PASS, 0 FAIL** across 22 UI files for
  the complete current cross-family concise-copy test dictionary.
  This is **NOT** execution of the Python contract, QML parser,
  full exact-SHA canonical test or live desktop. Local Git CLI
  cannot resolve github.com in this environment, so no remote
  clone/validator PASS has been observed. Preserve safety and behavior
  disclaimers (notification history, 15-second display revert,
  niri-owned autostart, screenshot local/no-AI limitations, original
  recording retention and restart requirements).
  SET-R03 remains OPEN: comprehensive on-screen copy inventory,
  dynamic/optional Companion and Integration plugin UI, small screens,
  accessibility/translation search and installed owner visual acceptance.

  **2026-10-12 late continuation — Waffle and optional wrapper scope:**
  After checking current `dev` (local bot delivering Utilities and notification
  source independently), shortened 17 Waffle page help occurrences in Modules,
  Workspace Strip, Themes, Background, Bar and Style. Additional 7 shared
  Effects/Custom Theme/Shell Layout/Waffle parent strings were shortened.
  The Companion fallback is concise and translated; Obsidian Theme, Obsidian
  Todo, Thinkfan and Waffle TLP absent-package notices now use English
  `Translation.tr` with the same loading/retry behavior. Source commits
  `dfd1221be`, `45f8e5d4e`, `4622145a9`, `47825981b`, `573fa92f4`,
  `69fca0b62`, `8df9fbacb`, `d0cf4c0a2`, `f9c6c8b5b`,
  `7456fad67`, `a7097093a`, `702577a80`, `9594e0dc0`,
  `4b97a1548` and `48d963b31`; locale keys added at `37e18d0b3`
  and `c7438973f`. Focused source-copy tests added at `875922cb4`,
  `536d24c41` and `71d1b7e9b` and preserve loader/retry
  references. Connector checks on the source snapshots:
  Waffle/optional 23/23 source+English key PASS and shared 7/7 PASS;
  these are **not** execution of the Python contract or a canonical
  desktop/QML acceptance. The dynamically loaded third-party plugin's
  own contents remain outside this host-only pass. Keep this [ ] OPEN
  until full Settings inventory, source-level test execution, native
  responsiveness/small-screen/accessibility and owner review are complete.

- [x] **SET-R04 — Remove "Use opaque Material appearance" preset button — owner 2026-10-12:**
  [Owner: Alis dev; Rework/removal] Delete the **button** from
  `modules/abyss/settings/AbyssStyleSettings.qml` completely.
  This button performs a real batch `Config.setNestedValues`
  change (surface/content opacity, blur, waves, refraction, glow,
  highlight, perimeter radius): it is NOT a Settings redirect.
  Previous SET-R01 research kept it for that reason, but this
  explicit owner removal request **supersedes that keep decision**.
  Preserve each individual opacity/blur/effects/radius setting and
  its saved value; do not trigger the old preset or reset users'
  current appearance on upgrade. Remove dead UI text and update
  test/translation expectations.
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Removed the batch preset button/handler without touching saved Config
  or standalone appearance controls: source `86428c775`; guarded with
  regression assertions in `b7c64013d` and `e045cf075`.
  Shipped en_US catalog has no stale preset text. All 17 connector-level
  source assertions PASS at `e045cf075`; these are NOT executed Python,
  canonical, native or owner acceptance results. Exact-SHA validator,
  physical Settings inspection and owner acceptance remain pending.

- [x] **ABYSS-R07 — Screen Edge Clock and Date use shared Typography — owner 2026-10-12:**
  [Owner: Alis dev; Rework/font settings] On Top, Bottom,
  Left AND Right Abyss Screen Edges, Clock/Date must inherit
  the main Settings → Typography font family and size scale,
  with meaningful time/date hierarchy derived from shared tokens.
  Remove the separate Time font, Time size (px), Date font,
  Date size (px) controls from the Abyss Clock settings section
  in `modules/settings/BarConfig.qml`.
  `modules/bar/ClockWidget.qml` currently reads
  `bar.clock.timeFontFamily/timePixelSize/dateFontFamily/datePixelSize`
  and falls back to `Appearance.font.family.main` and shared
  pixel-size tokens. Audit the rotated Left/Right path
  `modules/verticalBar/VerticalClockWidget.qml` in light of
  ABYSS-R05 (full-design rotation, no compact variant).
  Use one typography source-of-truth without silently modifying
  Waffle or other still-valid consumers of legacy settings.
  Preserve old config keys as inert/compatibility values when
  appropriate, not destructive deletion. Keep time/date formats,
  font contrast, dynamic theme and calendar hover/click behavior.
  Acceptance: changing global Typography live-updates Clock/Date
  on all four edges and survives restart; no independent Clock/Date
  font/size controls in Abyss settings; test multiple scales,
  locales, small screens, focus/popup hitboxes, owner native
  visual signoff.
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Abyss's resident full Clock uses shared Typography family/large-small tokens
  on four Edges, with one global scale. Separate font/px controls are absent;
  legacy consumer behavior and saved values remain. Native two fonts × three
  scales × four Edges, Settings object inspection and JSON restart PASS within
  combined 165 checks/25 frames. Translation parity PASS.
  [Evidence](../../docs/evidence/abyss-product/20261012-abyss-r06-r07/README.md).
  Owner/installed, fractional/multi-output and full canonical remain pending.

- [x] **SET-R01 — Eliminate redundant Settings-to-Settings navigation buttons:**
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
  passing focused and native owner UI checks. **Audit 2026-10-12:** twelve
  core pure redirect buttons are identified in Modules/Quick/Interface/
  System/Sidebars/Services, plus one in Alis-Companion (13 total).
  Services' old search delegation is compatibility,
  not a visible button. Opaque Material was preserved in the earlier navigation-only audit
  because it changes real settings, but the owner's newer explicit
  removal request supersedes that decision (SET-R04).
  reload/Open config/Shortcuts/floating tools/install/calendar actions stay.
  Remove empty redirect wrappers, hide Abyss' now-empty Modules sub-tab while
  retaining real Waffle module controls and canonical/legacy routes.
  **Source/focused native 2026-10-12:** all 13 pure redirects and empty wrappers
  removed. Legacy Abyss page10 Modules routes map to canonical page34; direct
  stale selection/family change reconciles Panels. Real Waffle Modules remain.
  Five source/behavior checks and actual private-Niri navigation PASS exit0:
  pointer parent/child/Back, legacy search/deep links, family switch, order
  editor and standalone Abyss/Waffle. Companion source is
  `7ba1529ccf1f3f5b2940883f7e83777230b89018`, selected package check PASS1/0/0;
  Integration `7c3623da5cf8741a0b82cb4d3d8054017dfa99d0` has no pure redirect.
  [Action inventory, hashes and native evidence](../../docs/evidence/abyss-product/20261012-settings-redirect/README.md).
  State: SOURCE IMPLEMENTED / OPEN for committed canonical, owner both-theme
  UI/keyboard/Escape, saved selection and physical/multi-output acceptance.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

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

- [x] **ABYSS-R01 — Comfortable corner clearance in Edit Abyss Layout:**
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
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Curvature/type-derived modest content inset, dynamic perpendicular-corner
  clearance and inset snap guides are implemented; decorative joins retain
  their original physical reach. Normalized centers and locked reservations
  survive save/reopen. Focused geometry 729, locks 7166, multi-selection 1482,
  native pointer 78/17, native locks 62/26 and native multi 55/13 PASS.
  [Evidence](../../docs/evidence/abyss-product/20261012-abyss-drag-corners/README.md).
  Owner, wl_pointer, fractional/multi-output and full canonical gates remain
  pending separately.

## Existing UI and layout

- [ ] **TYPE-R01 — Quickshell typography consistency — owner request 2026-10-10:**
  Standardize inconsistent text appearance across Quickshell: review font
  family/fallback, size, weight, text color, alignment, line height and theme
  roles. Reuse shared text tokens without removing intentional heading/body
  hierarchy or legitimate Abyss/Waffle distinctions. Qualify Panel, Popup,
  Settings and edit surfaces at varying scales and light/dark themes. State:
  READY for UI audit; owner visual acceptance pending.

- [x] **ABYSS-R08 — Compact Edit Abyss Layout control bar — owner request 2026-10-10:**
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Source `86af17627` is pushed: compact defaults on four Edges, discoverable
  immediate actions, disclosed full tuning, quick IPC selector, bounded
  scrolling/minimum widths and retained drafts. No selection toggle.
  Clean exact-source scoped 8 PASS; actual Qt 1454 checks/24 field frames,
  drag 84/19 and legacy editor PASS. Focused locks62/26, multi59/12,
  zero74/26 +33 GPU comparisons PASS. Failed variants retained.
  [Evidence](../../docs/evidence/abyss-product/20261012-r08-compact-editor/README.md).
  Owner/installed, physical pointer, true fractional/multiple outputs and
  current full canonical gates remain separate. R03 and POP-I01 stay open.
  **Priority reconfirmed 2026-10-12:** next immediately after the current
  ABYSS-R03 source/qualification milestone, ahead of the former next-item
  queue. Keep R03's remaining work and independent failed/owner gates open.
  Redesign controls for BOTH horizontal and vertical edit orientations to
  occupy less room while preserving discoverable actions, module context,
  per-edge editing, Cancel/Undo/Done, input targets and narrow-screen access.
  Test four edges, long labels, expanded edit controls and interaction with
  screen-edge modules; coordinate with new multi-selection functionality in
  [New features](NEW_FEATURES.md). Source/qualified scoped delivery is complete;
  owner visual acceptance pending.
  **Owner follow-up 2026-10-12:** Centre icon-only button glyphs, shorten
  Editor width and Options sliders, replace concise slider captions with
  accessible glyphs/tooltips and remove keyboard instructions from the
  footer while keeping existing shortcuts, input and feedback.
  Source refinement awaiting owner/native four-Edge and scale verification.
  **Second owner screenshot, 2026-10-12:** Earlier icon/slider-only
  reduction still displayed one-component-per-row with excessive horizontal
  blank space. Rework into shared adaptive 3/2/1-column groups:
  module palette+Add, icon+sliders+context actions, Scale/Join/Round
  conditions, and grouped selection lock/visibility/remove controls.
  Place output-only beside Modules/IPC, remove side headings/separators;
  retain all draft operations, per-Edge semantics, IPC, scroll and tooltips.
  Source commit `b13e4a7dd` on dev; native four-Edge, fractional scaling and
  owner visual sign-off remain independent gates.

- [x] **NET-R01 — Wi-Fi and Bluetooth Popups about 35% smaller — owner request 2026-10-10:**
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
  **OWNER VERIFIED — 2026-10-11 22:19 ICT:** Maintainer accepts the compact Wi-Fi/Bluetooth Popup design delivered by the 260×330 source patch. This closes the owner-requested size/appearance rework. The previous line describing absent full local Wayland testing is historical and does not become a claimed native PASS; network connectivity/loading, other popup behavior, multi-edge/fractional scale and regression testing remain ordinary independent validation requirements.

- [x] **MON-R01 — Monitor Arrangement tiles about 30% smaller — owner request 2026-10-10:**
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
  **Follow-up source adjustment (2026-10-11, owner screenshot):** fixed-height
  Utilities left an oversized blank band between Monitor Arrangement and
  the four page indicators. Let the embedded canvas fill the usable viewport,
  retaining the previous compact tile fit budget and unchanged Niri positions.
  Extended the existing native fixture to check the gap at real 620×400 size.
  State: SOURCE PATCHED; owner screenshot, scale and multi-output acceptance OPEN.
  **OWNER VERIFIED — 2026-10-11 22:19 ICT:** Maintainer accepts the resized monitor tiles and removed blank space above/below the tab-indicator region from the two documented source commits. Close this size/spacing rework. Keep actual output placement unchanged; the earlier lack of exhaustive local drag/hotplug/multi-output testing remains an evidence limitation, not a newly asserted native PASS.

- [ ] **NOTES-R01 — Quick Notes Edgebar scrolling sensitivity — owner request 2026-10-10:**
  Tune wheel/touchpad scroll speed for predictable navigation, including
  Shift-held scrolling while performing bulk selection. Inspect modifier/event
  routing and nested scroll containers; preserve range selection, existing
  note focus and selection state without unexpected horizontal scrolling,
  acceleration or skipped notes. Check long lists, trackpad/wheel, different
  scales and ordinary versus Shift navigation. State: READY for interaction
  tuning; preferred speed and owner acceptance require native input retest.

  **2026-10-12 source implementation, Owner chưa verified:** Existing
  `NotepadWidget.qml` note-indicator rail switched tab for every wheel
  packet from only `angleDelta.y`, including touchpad packets that may have
  no angle delta. Added pure `NoteRailWheel.js` with pixel-vs-angle
  normalization (48 px / 120 angle units per note), bounded accumulation,
  140 ms repeat gate, direction reversal, 240 ms burst reset, end/momentum
  handling, and Shift-remapped wheel routing; Ctrl/Alt/Meta wheel is left to
  the owning surface. `NotepadWidget` now consumes handled wheel events,
  preserves the tab-index boundary, and keeps per-widget gesture state
  without changing the note text, selected ID or autosave path.
  Source commits: `3182e0073` and `6d71700f0`; node test
  `scripts/test-note-rail-wheel-policy.mjs` in `e0c7f972d`; canonical
  validator wired at `856537845`. **60/60 test assertions PASS** when
  the exact checked-in JS and adapted committed test logic were executed
  in an isolated V8 runner; this does NOT claim executing Node itself or
  native Qt/Niri. **Open owner gates:** physical wheel/touchpad,
  Shift-held bulk selection, long note rails, compact Edgebar and varying
  display scale / interaction feel. Leave this task [ ] pending.


- [x] **CAL-R01 — Compact Calendar Popup Events to Today / Tomorrow / Day After — owner screenshot 2026-10-11:**
  [Owner: Alis dev; Rework/UX] The **Events pane immediately beside
  the Calendar Popup** should show only Today's, Tomorrow's and
  the Day After Tomorrow's events, three **local calendar dates**
  inclusive rather than a rolling 72-hour timer. Match the
  owner's second screenshot: compact, readable event cards
  beside the calendar; group by date with clear headers and
  chronological order. Include in-progress/all-day events for
  today and handle recurring entries correctly. Show a correct
  filtered badge count, an appropriate 3-day empty state and
  scrolling if many events occur in the permitted window.
  Events after day +2 must remain available in full Agenda/
  Weekly Planner, not deleted or globally filtered.

  Scope strictly to `modules/bar/ClockCalendarContent.qml`'s
  `EventsWidget`. Currently `EventsWidget.qml` combines
  `Events.getUpcomingEvents(30)` and 30 days of CalendarSync
  external buckets. Introduce a caller-specified 3-day range
  and/or shared filtered query so other consumers retain their
  normal horizon; `modules/dashboard/DashAgenda.qml` uses
  **14-day** lookahead and must remain unchanged. Avoid fetching
  30 days only to hide 27, preserve local/external read-only
  behavior, Add/Edit/Remove editor, FAB focus and month-calendar
  geometry. Validate midnight rollover, local/UTC boundaries,
  multi-day/recurring events, empty/loading and source refresh.

  Acceptance: only day offsets 0,1,2 visible with labels and
  correct count; day 3+ excluded from this small panel but still
  present in full Agenda; source/date ordering, changes after
  midnight, all-day/in-progress, 0/1/long lists, scroll,
  theme/scaling and popup focus; verify no Dashboard Agenda
  truncation and owner native screenshot parity. Coordinate
  with CAL-F01 indicators.
  **Owner refinement — 2026-10-12 (Events scrollbar):** in the
  **Calendar Popup Events pane only**, hide the scrollbar track/thumb
  entirely (e.g. popup-scoped `ScrollBar.AlwaysOff`) while preserving
  vertical wheel/touchpad/finger/keyboard scrolling, focus, FAB,
  event cards and the Add/Edit/Remove form. Do NOT globally disable
  `EventsWidget` scrolling or hide scrollbars in unrelated Sidebar/
  Dashboard hosts. Test 0/1/many events, narrow/high-DPI windows and
  scrolling to the final event.
  **Implemented in source, 2026-10-12:** Alis dev
  `3f3af8cc5bda987fd651c58c8d074d58d337875f` delivers
  `compactCalendarWindow` for Calendar Popup only. It uses the
  shared WeeklyPlanner recurrence/DST/all-day projector over exactly
  three local calendar dates, groups rows by day, and preserves
  original Events/CalendarSync objects and canonical Edit/Remove IDs.
  EventCard gains a caller-only compact mode and correct end-time
  active/in-progress status. Other EventsWidget users keep the
  30-day query and Dashboard Agenda retains 14 days. A follow-up
  scopes invisible scroll chrome to both Calendar Events list
  and embedded editor without disabling scrolling, and gives its
  empty state a three-day-specific English label.
  **Verification:** 23 focused JS projection/time assertions PASS at
  initial source SHA; the two new scrollbar contracts also passed in
  the source-level follow-up. Actual Niri/Quickshell native layout,
  touch/wheel/accessibility, full exact-SHA canonical, hot
  midnight refresh and owner screenshot acceptance are NOT RUN.
  **Hoàn thành (bot báo xong) — Owner chưa verified.**

- [ ] **DASH-R03 — Weekly Planner Day/date + All day header material parity — owner screenshot 2026-10-12:**
  [Owner: Alis dev; Rework / Material UX] The 7-column date/day header
  and its **All day** strip in Dashboard Weekly Planner currently read
  as a flat, detached dark band (owner screenshot) rather than an
  Abyss-connected content surface. Rework the two header regions as one
  coherent, compact Abyss Panel material language, with deliberate
  header/column divisions, selected/today/hover states and no unnecessary
  independent cards or expensive new shader/blur passes.
  Match the **theme-color semantics of the owner-approved Detailed
  Weather Popup content background**, not a hard-coded screenshot tint:
  reuse `AbyssStyle.contentLayer` / theme accent/ink/contrast policy,
  allowing live wallpaper/theme changes and preserving Waffle/non-Abyss
  styling. Source starting points:
  `modules/dashboard/DashboardWeeklyPlanner.qml` (date column header,
  All day band and sticky left/top corner), and
  `modules/bar/weather/WeatherPopupContent.qml` as palette reference.
  Preserve seven aligned columns, date/time zones/DST positioning,
  all-day expand/collapse, current-day indicator, time scroll and
  event hit testing. Verify narrow/fractional screens, multi-output,
  light/dark, long weekday/date translations, foreground contrast,
  scroll anchoring and actual Niri screenshots. Coordinate with
  DASH-F01's new in-Dashboard expandable Edit Events column.
  **Source milestone 2026-10-12 — not yet accepted:** Weekly Planner
  date, All day and sticky corner share the same Detailed Weather palette:
  `AbyssStyle.contentLayer`, accent and contrast-safe ink, with a
  Material fallback outside Abyss. Selected/today/hover feedback and
  contiguous dividers do not add shader or blur passes. Source grid, DST,
  event projection and scroll hit testing remain unchanged. Existing
  private-Niri runtime fixture now checks seven aligned headers, pinned
  scrolling and surface color agreement; the GitHub-only environment
  cannot run that fixture, so it is **NOT RUN**. Await owner Niri
  screenshots, light/dark and fractional/multi-output/long-date checks.
  Task remains OPEN; no native or owner approval is implied.
  **Owner correction 2026-10-12 (two screenshots, supersedes Weather-palette
  target above):** date headings, sticky corner and All-day band must show
  the **same background as the time grid below**, not a separate opaque
  Weather-themed card. The timeline itself uses transparent day cells over
  the Dashboard. Source `0c712d629` therefore sets `headerSurface` to
  transparent, makes the heading ink follow the timeline ink, and retains
  day/today/hover highlights, dividers and seven-column positioning.
  Private Niri fixture has a new alpha=0 and shared-ink assertion at
  `bb03f6097`; it is **not run yet** on the committed source.
  Responsive/theme/contrast and owner installed screenshots remain OPEN;
  do not claim native or visual acceptance.


- [ ] **DASH-R02 — Horizontal-only Dashboard gesture page navigation — owner request 2026-10-11:**
  [Owner: Alis dev; Rework/UX] **Only horizontal left/right swipe
  or horizontal scroll may change Dashboard tabs/pages. Vertical
  scrolling/swiping must NEVER switch Dashboard tabs** — on the
  page body, header, page indicators or nested Music/Weekly Planner
  content. Preserve explicit intentional selection by clicking
  a page indicator or accessible keyboard navigation; the
  restriction is for gesture routing, not removal of page dots.

  **Source evidence:** `modules/dashboard/DashboardContent.qml`
  at intake had an overlay `WheelHandler` with
  `orientation: Qt.Vertical` which writes numeric
  `GlobalStates.dashboardPage` and a second horizontal handler.
  `modules/dashboard/DashboardHeader.qml` separately has a
  vertical `WheelHandler` calling `pageRequested()`. Eliminate
  vertical page-switch behavior in BOTH owners and audit other
  swipe/wheel shortcuts for equivalent accidental switching.
  Do NOT merely block all vertical events; route them to the
  intended child Flickable/ListView/Scrollbar and allow normal
  scrolling of Genre, Folders, Results, Playlist, Queue, Lyrics,
  future Weekly Planner's time axis and the Dashboard's other
  scrollable widgets. Horizontal gestures must have predictable
  direction and threshold/debounce/hysteresis (avoid one
  high-resolution touchpad gesture skipping multiple tabs),
  continuous/faithful slide, fast reversal and safe boundary
  behavior. Respect Music's nested horizontal browser:
  let `DashboardMusic.panHorizontally()` or the inner Flickable
  consume a genuine horizontal content-scroll first; switch
  pages only when the inner surface cannot appropriately consume
  that gesture, without trapping navigation forever.

  Coordinate with **DASH-F01** (third Weekly Planner page),
  **DASH-F02** (drag-reordered stable tab IDs) in
  [New Features](NEW_FEATURES.md): gesture navigation operates on
  the active persisted page order, not hardcoded 0/1, and may be
  disabled only while a tab indicator is actively being dragged
  or an edit/dialog gesture owns input. Maintain accessibility,
  navigation through page indicator click, scroll with Shift if
  OS/toolkit maps that action to a horizontal delta, and
  reduced-motion without inventing a gesture-based page switch
  from a vertical-only signal. Existing Music Results/Queue
  vertical-scroll bug in [Issues](ISSUES.md) remains an independent
  correctness gate and must not regress.

  **Acceptance:** two-page and three-page Dashboard; vertical
  wheel/touchpad up/down across header, dots, canvas, Music
  list/Queue/Lyrics and Planner never changes page but scrolls
  vertical contents as appropriate; horizontal touchpad/swipe,
  horizontal wheel and deliberate page-dot clicks change the
  correct adjacent page, honor reordered tabs, first/last edge
  boundaries and nested Music column scroll. Test fast gesture
  bursts, drag thresholds, wheel over list/scrollbar, Shift-wheel,
  diagonal touchpad movement, keyboard, scale/theme, open/close/
  restart and real Niri/Quickshell owner acceptance. Update
  focused QML/JS gesture-routing contracts and scroll fixtures.
  **Source implementation, 2026-10-11:** vertical handlers are removed from
  body/header; one shared horizontal burst/phase threshold, fast reversal,
  boundary and Music-content ownership policy now drives stable IDs and
  persisted active order. Numeric Music=1 compatibility is retained;
  dialogs/editing suspend both dots and gestures. Baseline exact b543bb760
  reproduces vertical switching (expected FAIL, exit 1). Candidate Node
  policy passes 990 checks over two/three-page order permutations; actual
  Dashboard/Music controls, all six overflow lists, LocalMusic demand and
  Python/Rust mutation fixtures PASS (each exit 0).
  [Source pins and focused evidence](../../docs/evidence/abyss-product/20261011-dashboard-navigation/README.md).
  Product milestone `8edd331797771924435a91ed1ed8abac382490c2` is pushed;
  combined material source is `553525a25d6b93ab63b02a3233eee3c909579b38`.
  Frozen clean-clone b44899d50 canonical now PASS 349/0/2, exit 0; prior
  interrupted/not-started receipts remain retained. Later CFG-I02 must be
  qualified separately. State: OPEN for owner touchpad/mouse/scaling and
  multi-output acceptance; actual third Planner page (DASH-F01), dot drag
  transactions (DASH-F02) and their native three-page/restart gates remain
  NOT IMPLEMENTED. Do not turn policy permutations into product acceptance.

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

- [x] **DASH-R04 — Edit Dashboard toolbar slide — received/updated 2026-10-10:** pushed
  `8c673129b58dbde73bf31c82df25c1085bf63e15` slides full-size connected controls
  from the attachment using the shared motion token. Input follows the clipped
  reveal; exit retains its footprint and releases input immediately. Native
  16 Dashboard/Overview × edge × size cases, reversal, complete exit, reduced
  motion, stable canvas and Undo/Cancel/Done pass. Its focused check also passes
  in the exact `10311cd96` canonical run, whose overall result is FAIL 327/8/1.
  State: source/focused-qualified; owner appearance acceptance still pending.
  [Durable focused evidence](../../docs/evidence/abyss-product/20261010-hover-checkpoint/hadalis-dashboard-toolbar-slide-motion-20261010.log).
  **2026-10-12 current capture qualification:** after DashboardHeader0becc72ab
  dimension repair, original composed-route/slide oracles PASS16cases,
  211native motion samples/48PNG on source-pinned working bytes. Explicit
  image-verification invocation focuses only its own private Niri and restores
  the previous parent target; default tests keep their non-focusing behavior.
  [New raw images/receipt](../../docs/evidence/abyss-product/20261012-dashboard-field-capture/README.md).
  Earlier unfocused sampling FAIL is retained; owner palette/material,
  installed/multi-output and exact newer full-canonical gates remain OPEN.
  **Completion classification — 2026-10-12 (maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** Edit Dashboard toolbar motion implementation and subsequent native composed-route/motion checks reported complete; owner material/desktop visual review remains unverified. Previously recorded full-canonical FAIL/SKIP, partial native coverage and independent unresolved regressions remain factual; no fresh PASS or physical owner approval is claimed.

- [ ] **ABYSS-R10 — Abyss Waves:** verify round crest-only geometry, no trough erosion or
  needle peaks, restrained breaker/whitewater, continuous distance attenuation,
  stable same/opposite-direction interaction and idle sleep. Preserve one shared
  wave-strength control/migration, optional/default-off waves and reduced motion.
  Calm stays below Balanced (the former Calm); Fluid/Deep should be distinct and
  restrained. Detailed wave controls belong to Custom; show numeric audio strength.

- [x] **ABYSS-R02 — Checkbox to preserve rounded INNER workspace corners at 0px Edge width — owner clarification 2026-10-11:**
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
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Independent 0px checkbox, shared Curvature, OR corner ownership and one-field
  localized inner arcs are implemented; no new strip or input blocker.
  Policy 9606, native controls 68/24, fresh-process restart 2 and GPU
  30 strict RGBA comparisons/24 PNG PASS, including original OFF/nonzero parity.
  [Evidence](../../docs/evidence/abyss-product/20261012-abyss-r02/README.md).
  Owner, installed fullscreen/input, fractional/multi-output and current
  exact-SHA canonical remain separate pending gates.

- [x] **ABYSS-R04 — Unified Panel and Content card opacity slider — owner request 2026-10-11:**
  [Owner: Alis dev; Rework/Settings] In Abyss **Surface** Settings,
  **Content card opacity** and **Panel background opacity** should
  have ONE shared opacity slider, rather than two independent sliders.
  Keep a single clearly labeled **Panel & content opacity** control,
  driving both enclosing Panel/Popup/Dashboard/Sidebar/Settings
  background transparency and their built-in content-card tint
  consistently. No separate visible `Content card opacity` slider.
  Cards must respond immediately and consistently with the parent
  material; do not multiply the same alpha twice over stacked card
  backgrounds and accidentally make content unreadable/overly dim.
  Leave Screen Edge's own `Surface opacity` slider separate, and
  do not couple the shared content opacity to wallpaper blur.

  **Verified source:** `modules/abyss/settings/AbyssStyleSettings.qml`
  currently exposes independent `abyss.content.opacity` (with
  -1 = inherit Screen Edge) and `abyss.content.cardOpacity` (.9
  default) sliders. `AbyssStyle.qml` resolves separate
  `contentOpacity` and `cardOpacity`; `contentLayer` and
  `SettingsMaterialPreset.qml` use the latter for cards/groups,
  while `AbyssField.qml` passes contentOpacity into the field
  shader. Use ONE effective source-of-truth property in the
  shared palette/material path; preserve both normal QML and
  shader consumers with no duplicate opacity multiplier.
  Audit `modules/dashboard/DashCard.qml`, Dashboard appearance
  controls, all Abyss content-card consumers and the existing
  'Panel background follows Screen Edge' checkbox. The latter
  should continue to mean opacity inheritance **only if chosen**
  and must NOT incidentally overwrite blur settings. Keep the
  distinct `dashboard.appearance.cardOpacity` setting if it
  applies to a genuinely separate per-Dashboard widget-layer
  control; reconcile/remove duplicate user-visible sliders when
  they control the same built-in Abyss material.

  **Config migration:** choose one documented deterministic
  precedence for legacy `abyss.content.opacity`,
  `abyss.content.cardOpacity` and inherited -1, preserving
  existing explicit user-selected content-opacity values where
  possible, without resetting the Screen Edge opacity or
  saved per-output settings. Retire/alias the legacy card key
  safely instead of writing two independent values which drift
  after Settings close/reopen or shell hot reload. Opaque Material
  preset must set the unified control correctly. Provide
  readable typography and stable contrast at 0/25/50/75/100%
  alpha; test popup, Dashboard, Sidebar, IPC and Settings cards,
  light/dark, themes, multiple outputs, animations and
  restart persistence.

  **Acceptance:** exactly one visible shared slider in Abyss
  Surface Settings; moving it updates panel backdrop + content
  cards together without unintended double-transparency; 0%
  is a valid explicit value, 100% is opaque, `Surface opacity`
  and `Panel background blur` remain separate. Live focused
  QML/style/field pixel fixtures and native Niri/Quickshell
  owner screenshots required. Linked blur correctness:
  [ABYSS-I01](ISSUES.md). **Implemented/focused qualification 2026-10-11:**
  one shared slider, live card alias, independent Edge/blur and opaque action
  are implemented. Raw migration schema 1 preserves explicit Panel opacity
  including 0/-1; only an absent opacity adopts legacy card alpha. Unknown/
  optional/per-output data and future schemas are retained. Pure policy
  221 checks, five actual Config cases/ten startup-restart processes, Settings
  413 + four restart checks, 120 field captures/270 pixel checks and content
  smoke PASS, each exit 0. [Source pins/evidence](../../docs/evidence/abyss-product/20261011-unified-opacity/README.md).
  A separate extra unchanged Config flush missed its four-second lease
  deadline; raw failure retained, cause NOT_DIAGNOSED, no flush repair claimed.
  Product `553525a25d6b93ab63b02a3233eee3c909579b38` is pushed.
  After reset, frozen clean-clone b44899d50 canonical PASS 349/0/2, exit 0;
  prior launcher/stop receipts are retained. CFG-I02 now repairs migration
  with nonempty custom data and requires a separate new committed run.
  State: OPEN for owner visual/theme/typography,
  per-surface contrast, animation and multiple-output acceptance.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [x] **ABYSS-R05 — Preserve the full module design when placed on Left/Right Screen Edges — owner requirement 2026-10-12:**
  [Owner: Alis dev; Rework / four-edge visual and geometry parity]
  **ALL Screen Edge modules** must retain the same **non-compact
  component design, visible content, proportions, controls, icon/text
  hierarchy and user-configured size** they have on Top/Bottom when
  moved to Left/Right. Do **NOT** automatically swap to old Material
  vertical/compact bar variants, drop labels, collapse information,
  change widget style or silently reduce their scale solely because
  an edge is vertical. **Only rotate/reorient the original module to
  face the appropriate Screen Edge** (Top/Bottom/Left/Right). Rotating
  a full design means correct 90°/270° orientation, pivot/anchors,
  transformed width/height and input coordinates, NOT recreating a
  narrower substitute. Existing intentionally explicit custom size/
  appearance settings should remain respected; moving between edges
  must not silently rewrite their saved values.

  **Source starting points:** `modules/abyss/bar/AbyssBarModule.qml`
  currently branches on `vertical` to load the distinct
  `Vertical.Resources`, `Vertical.VerticalClockWidget`,
  `Vertical.VerticalMedia` and `Vertical.BatteryIndicator`
  variants; other module kinds pass `vertical` to child controls
  and `compact` to Clock/UtilButtons. Review EVERY module kind,
  including Workspaces, Weather, Tray, Taskbar, Active Window,
  Distro/Launcher, Utilities, Timer and Shell Update, plus installed
  or optional modules; use the original horizontal/full-content
  presentation with a shared edge-orientation transform rather than
  replacing it with Material-era vertical layouts.
  `modules/abyss/bar/AbyssBar.qml` selects the physical edge,
  exposes `naturalSpan` and `contentScale`, and passes
  `placement?.compact`; `modules/abyss/looks/AbyssLayout.js`
  has orientation-specific `extent()` and `geometry()` with a
  capacity `scale` factor. Audit measured extents, 90°/270° bounding
  boxes, hit region, corner joins and center/alignment carefully:
  removing only the QML `Vertical.*` branch is insufficient.

  **Size and capacity:** preserve each module's configured visual
  size and layout on all four edges; Left/Right rotation may swap
  physical width and height but must not shrink fonts, icons, card
  surfaces, controls or their proportional relationships. For a
  crowded/short edge, do NOT silently apply a compact fallback or
  proportional auto-shrink. Determine an explicit non-destructive
  capacity rule (bounded repositioning, placement rejected with
  clear editor feedback, or another reviewed non-clipping solution)
  so other modules cannot overlap, vanish, steal click targets or
  move unpredictably. Coordinate with ABYSS-R01 (corner clearance),
  ABYSS-R03 (smooth repacking), ABYSS-F01 (locked positions) and
  per-output/edge-width/custom-size configuration. Preserve Popup
  attachment, hover, mouse/touch, keyboard, tooltips, OSD and
  fullscreen interactions; module *content* remains fully usable.

  **Acceptance:** for each supported module, compare Top → Right →
  Bottom → Left → Top on the same config: same content/controls and
  design, no automatic compact variant, no unintended size drift;
  only orientation and swapped axis dimensions differ. Verify
  long labels/text, animation and hover/popup placement, rotation
  direction, readability, exact hit regions, crowded edges, locked
  neighbors, four-corner crossing, output-only profiles, saved
  Done/Cancel/Reset, restart, dark/light themes, 1x/fractional DPI,
  multiple monitors and small screen limits. Add deterministic
  geometry/orientation and source QML tests, followed by real
  Niri/Quickshell before/after captures and owner visual signoff.
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  All 13 kinds keep their resident full component with ±90° orientation,
  precise fractional pivot and configured size. Crowded edges reject explicitly
  with retained inventory, bounded repair action and zero hidden input.
  Focused policy 3772, locks 6262, multi-selection 1610 and native
  683 checks/106 frames/65 PNG PASS. Evidence:
  [R05](../../docs/evidence/abyss-product/20261012-abyss-r05/README.md).
  Owner/installed, populated feeds, wl_pointer, fractional/multi-output
  and current exact-SHA canonical remain separate pending gates.

- [ ] **ABYSS-R03 — Smooth module movement and repacking on Screen Edges — owner request/reconfirmed 2026-10-11 13:36 ICT:**
  **2026-10-12 strict-lossless partial milestone, source `458ad7197`:**
  after synchronizing cloud/local `58853ae54`, reuse exact synchronous wave
  kernels/mass snapshots and equal plain-data body placements. Host-owned
  caches avoid the rejected global registry's destruction leak. Qt/QV4
  433526 exact checks, 821 lifecycle checks/160 hosts, native drag 84/19,
  body retention/focus and GPU wave checks PASS. Initial focus FAIL and
  rejected variants retained; no accepted CPU/GPU/RAM percentage claimed.
  [Evidence](../../docs/evidence/abyss-product/20261012-r03-mass-placement-cache/README.md).
  STILL OPEN for dense actual wl_pointer tracking, owner video smoothness
  and current exact-SHA qualification; POP-I01 remains independent.
  A deterministic four-module layout shows 207 px additional displacement
  for a 25 px drag when old nominal centers reorder; this is pure geometry,
  not an owner replay. Primary reservation/release semantics still need a
  repair and lock/group/native proof. Frozen clean-clone `484427acf` is
  RUNNING; first nested-context native press FAIL is retained. Latest owner
  priority selects R08 after this qualification milestone, with remaining
  R03 work coordinated alongside its editor changes.
  **2026-10-12 focused partial source repair — STILL OPEN:** actual private
  virtual-pointer drag exposed source hover remaining true while the module
  is disabled for Edit, holding Resources popup open. Separate source input
  eligibility from presentation; editor handles retain source priority.
  Four-edge native ownership 150 checks/57 frames, cold/remount and original
  serial four-edge hover PASS; explicit protocol pin remains presented with
  source hover false. Dense drag/frame gaps still need diagnosis; no resource
  gain/owner acceptance claimed. [Raw variants and failures](../../docs/evidence/abyss-product/20261012-r03-source-input-owner/README.md).
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

  **Owner follow-up (2026-10-11, 13:36 ICT):** Screen Edge modules STILL
  do not move smoothly when the user changes their position. Treat this as
  a concrete outstanding **Edit Abyss Layout drag/reposition smoothness**
  acceptance failure, not simply an optional polishing idea. Reproduce
  pointer-follow lag, micro-stutter or nonuniform speed of the dragged module
  separately from the abrupt jumping/repacking of other modules. Check
  transitions while dragging past snap anchors or neighboring modules,
  crossing corner bounds and during release/settling; collect on-screen
  frame/input evidence before attributing root cause. The rendered module
  should follow the pointer continuously and land predictably, without
  a delayed catch-up animation, teleport, oscillation or editor flicker.

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
  **Reconfirmation is NOT a tested performance regression**: require an
  owner-observed before/after drag capture on the exact tested runtime,
  matched sampling conditions and separate judgments for dragged-module
  tracking vs neighbor displacement before closing ABYSS-R03.
  **Hoàn thành (bot báo xong) — Owner chưa verified, 2026-10-12.**
  Grab-point retention, edge hysteresis, direct primary tracking, unlocked
  neighbor animation, actual rendered field/handle/input geometry and coalesced
  extent measurements are implemented. Final native Qt pointer gesture PASS
  78 checks/17 frames, pin and multi-selection restart regressions PASS.
  [Evidence](../../docs/evidence/abyss-product/20261012-abyss-drag-corners/README.md).
  Matched owner before/after, physical wl_pointer latency/percentiles and
  installed-owner perceived smoothness are still unverified; no FPS/resource
  improvement is claimed. Existing canonical FAIL/STOPPED gates remain factual.
  Follow-up: actual native resize reproduced a transient corner overrun.
  Dimension/orientation changes now settle safely on their Edge; ordinary
  neighbor motion remains smooth. Focused native 84/19/6 PNG PASS; failing
  baseline retained. Source spelling fixtures for editor masks and shared
  Typography were corrected without weakening their behavior contracts.
  **Owner re-test 2026-10-12 — VIDEO CONFIRMS STILL LAGGING; REOPENED [ ]:**
  The owner explicitly rejects the actual Edit Abyss Layout smoothness after
  the previous source/focused-PASS milestone. In the supplied 40-second,
  1920x1200 H.264 recording `2026-10-12_14.01.54.mp4`, module drag,
  placement/orientation switches and the connected System Resources
  expanded/hover Popup presentation exhibit discontinuous visible geometry.
  Decoded video is 1200 uniformly spaced 30 FPS samples (33.333 ms/sample).
  Around 26.867→26.900 s, the expanded region switches Top→Left between
  adjacent recorded frames. Around 29.300→29.333 s, the left-side region
  becomes a broad horizontal popup/material field between adjacent frames.
  Around 30.400→30.600 s, its connected content retracts over ~6 frames.
  These are VIDEO PRESENTATION observations, not measured true Quickshell FPS,
  QSG swap intervals, compositor latency, or proof of a single code cause.
  The original upload remains in the owner's ChatGPT conversation and is
  NOT committed to Git; no private video paths or frames are assumed on
  the owner desktop. Full timestamp/source-limited audit:
  [Edit drag and module-popup jank video review](../../docs/abyss/ABYSS_EDIT_DRAG_JANK_VIDEO_REVIEW_2026-10-12.md).
  **Required separate acceptance gates:** (1) dragged module pointer tracking
  and neighbor repacking, (2) cross-Edge rotation/connected shape continuity,
  (3) Popup/expanded-module lifecycle and anchored motion WHILE editing.
  Compare same module with popup closed/open and other modules stationary,
  normal/top/left/right/bottom crossing, snap and pinned neighbor cases.
  Collect bounded exact-installed-SHA physical wl_pointer/input, QML drag
  callback/geometry/deformation/mask/Popup lifecycle and presented-frame
  chronology BEFORE asserting root cause or claiming improved FPS.
  Source paths to instrument: AbyssEdgeEditor.qml.move/onPositionChanged,
  AbyssLayout.js.geometry/packGeometry/localSurfaces, AbyssBar.qml
  layoutRecords/renderedRecords/deformations, module dimension rearm,
  AbyssPerimeter.qml field/input mask and popup host/hover lifecycle.
  No global FPS or GPU-per-module figure can be inferred from 30 FPS capture.
  Historical bot-reported source completion and previous scoped PASS remain
  recorded above, but they DO NOT close this explicitly observed owner
  regression. State: OPEN / OWNER-REJECTED SMOOTHNESS; no new runtime fix
  or owner acceptance recorded.

- [ ] **ABYSS-R11 — Screen Edge/module editor:** verify separate 0px-capable widths on all
  four edges, thickness-only versus inherited module sizing, per-module overrides,
  joined nearby modules when width does not affect them, nearest-corner joins
  and adjustable module curvature. Editor owns sizing with one-module partial/
  whole-edge choice, guides/snapping and saved per-output drafts. Dragging should
  not reload heavy content or persist the full config on each pointer event.

- [ ] **ABYSS-R12 — Connected presentation:** finish owner appearance acceptance for Popup,
  Sidebar, Dock, Dashboard, Settings, OSK and IPC on every edge and scale. Keep
  anchored full-size reveal/retract, readable reflow and older-body slide-close
  when allocation cannot fit. Center Sidebars on physical left/right edges;
  preserve custom dimensions and hot corners. Dock content must not shrink/jitter.
  Remove redundant tooltips, stray borders and repeated row fills while retaining
  intended enclosing-panel opacity/blur and click ripples.

- [ ] **SET-R05 — Settings refinement:** compact iOS-like parent/child navigation, Abyss
  before Waffle, no duplicate destinations/headings or generated More groups,
  one editor entry beside Lock, stable order/search/deep links and complete lazy
  pages. Keep meaningful slider units and avoid multiplying Dashboard opacity
  twice. Qualify System Monitor two-digit widths/RPM icons and OSK content-sized
  footprint. Waffle remains supported; historical ii/
  style values serve safe migration/content reuse, not a removed live theme.

- [ ] **DASH-R05 — Dashboard Music presentation:** qualify horizontal page slide and
  centered dots on the controls/uptime row; Genre/Folders tabs and multi-selection,
  folder drilldown and combined result column, shared Media/EQ DSP, bottom-anchored
  upward Queue expansion, Lyrics auto-hide and responsive remaining widths.
  Source/focused native tests already cover these behaviors; owner video/input
  acceptance is pending. Playback correctness is tracked only in Issues/bugs.

- [x] **REC-R01 — Recording presentation:** `fafb4687b` connects one shared control set
  to the Abyss field/allocator/input mask while retaining ii/Waffle presentation.
  Native tests pass four-edge controls, drag, connection hover, auto-hide/recovery,
  Stop callback and idle/secondary-output allocation. Confirm owner appearance
  and an actual recording/stop. No owner recording was started/stopped in fixtures.
  **Completion classification — 2026-10-12 (maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** Shared Recording presentation source delivery and four-edge native fixture coverage reported complete; owner actual recording/appearance remains unverified. Previously recorded full-canonical FAIL/SKIP, partial native coverage and independent unresolved regressions remain factual; no fresh PASS or physical owner approval is claimed.

- [ ] **WALL-R02 — Wallpaper picker polish, filename-only labels and live theme preview — owner update 2026-10-11:**
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

  **2026-10-12 follow-up — folder action tooltip only:** In addition to
  the existing file/card basename rendering, `WallpaperLauncherContent.qml`
  now presents only `FileUtils.folderNameForPath(browseFolder)` in the folder
  action tooltip, not the full chosen directory. It continues to store/use
  the complete normalized folder path for scanning, dialog preselection
  and applying selected media. Source `652e3633f`; native carousel fixture
  extended at `ec25ea603` to assert the basename hint and unchanged
  `WALLPAPER_FIXTURES` identity. Refetched source check at
  `23f8cbac3`: **9/9 static invariants PASS**, across launcher, library,
  grid/coverflow and fixture source. This is not a native or full
  canonical PASS. Still OPEN: preview/owner visual evidence, duplicate
  basenames, animated media and multiple output tests, and remaining
  tooltip/selected-name acceptance. No wallpaper application bug was
  claimed repaired.

  **Existing preview ownership (read-only verification):**
  `WallpaperLauncherList.previewCurrent` debounces highlight (180 ms
  static, 500 ms animated) and calls `Wallpapers.previewWallpaper`.
  The service requests `MaterialThemeLoader.previewWallpaperColors` and
  awww preview. `GlobalStates.onWallpaperLauncherOpenChanged` calls
  `Wallpapers.cancelWallpaperPreview` on close, while Apply uses
  `clearWallpaperPreview` before committing the chosen full path.
  `scripts/test-wallpaper-color-preview-runtime.py` already includes
  palette/cancel/latest-generation expectations. Source presence is not
  proof of the owner's visual acceptance or no render glitches. Do not
  duplicate this path or mark preview verified without exact-source
  native tests; remaining WALL-R02 acceptance stays open.

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

- [ ] **BRAND-R01 — Rebrand iNiR/Hadalis public surfaces to Alis — owner request 2026-10-11:**
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

- [x] **AI-R01 — Existing optional Integration Settings UI parity:**
  [Owner: Alis-Intergration main] Qualify existing TlpPowerSettings and
  Waffle equivalents, ThinkfanSettings, ObsidianThemeSettings and
  ObsidianTodoSettings for theme, readable labels, initial loading,
  backend missing/offline/disabled, error and scaling. Keep one source
  of truth for generic Alis Battery/Todo/Notes, preserve lazy disposable
  package worker lifecycle, native user focus and no implicit root
  actions. State: source implemented, owner visual/host qualification OPEN.

## Documentation maintenance
  **Completion classification — 2026-10-12 (maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** Optional Integration Settings UI source implementation reported complete; this separate UI parity item was not explicitly among the owner's #24-27 verified feature IDs, so remains owner-unverified. Previously recorded full-canonical FAIL/SKIP, partial native coverage and independent unresolved regressions remain factual; no fresh PASS or physical owner approval is claimed.

- [x] **TASK-R01 — Categorized tasks and shared AI workflow — completed 2026-10-10:**
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
  **Completion classification — 2026-10-12: Hoàn thành (bot báo xong) — Owner chưa verified.** The task explicitly reports the shared workflow and documentation migration completed on 2026-10-10; prior documentation contract PASS does not represent a separate owner signoff. Retain the original seven-day archive note without inventing an owner-verification date.
