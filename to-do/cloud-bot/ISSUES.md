# Issues/bugs — fix first

Consolidated on 2026-10-10 from the [former task ledgers](../../docs/archive/chatbot/2026-10-10/README.md).
Open items include remaining acceptance of source fixes; they do not all mean
that implementation is missing. Refetch current `dev` before diagnosing.

## Current failures and owner reports

- [x] **P0 — fullscreen window retains hidden Screen Edges/Panel/Perimeter after switching to another window (owner report 2026-10-10):**
  Reproduce on Niri: fullscreen client A, then open/focus window B in the
  same active workspace. Screen Edges, Abyss Panel and Perimeter reportedly
  disappear even though B is the foreground normal window. Source diagnosis:
  `GameMode.hasFullscreenOnOutput()` currently treats ANY fullscreen-sized
  window on an active workspace as if it still visually covers that output,
  ignoring `workspace.active_window_id`. Niri explicitly keeps fullscreen
  windows as ordinary scrolling-layout participants, so focusing another
  window does not necessarily revoke A's fullscreen geometry. Shared gate
  drives `AbyssPerimeter.presented`, ScreenEdges frame updates, ScreenCorners,
  Sidebar and other output surfaces. Independently,
  `NiriService.handleWorkspaceActiveWindowChanged()` and
  `handleWindowFocusChanged()` compare an object key (string) to a Niri
  workspace ID (number) with `===`, potentially discarding active-window
  selection updates needed to repair this gate.
  Investigate/fix with output-local selected-window semantics and numeric-ID
  normalization, preserve actual fullscreen suppression, multi-monitor
  isolation and mapped-window/stacking ownership. Test focus A→B→A,
  second monitor, workspace switch, startup unknown selection. Do not
  change layer ordering, input masks, animation, focus or visual quality.
  **Source fix committed on dev, native acceptance still OPEN.**
  `47071303a50f26cee31a6a03aabf7297662d51f4` fixes numeric-vs-string
  workspace dictionary key comparisons in both NiriService
  active-window update handlers. `0129cb4ce8d3c81215387b0959f93f7708f5c028`
  changes GameMode's per-output fullscreen coverage to select only
  `workspace.active_window_id` (normalized as strings); while no active
  ID is reported, it falls back to the focused window or the sole
  unambiguous workspace window. Global visible-fullscreen/GameMode now
  delegates to the same foreground-aware predicate. No layer-shell,
  native input region, rendering, hover or animation logic was edited.
  This matches Niri's documented scrolling-layout fullscreen behavior
  (https://github.com/niri-wm/niri/wiki/Fullscreen-and-Maximize).
  A permanent direct-source behavior regression
  `scripts/test-niri-fullscreen-selection.mjs` was added in
  `b1b565e926d235a11f9443e9adc1f8a72ca468b1` and integrated
  with the canonical `scripts/validate-maintainer-local.sh`
  in `da3a9bf3086d8da6b0ee519015601f059871dc5c`.
  An independent isolated V8 run of the exact recorded test logic
  against the newly committed QML functions passed 14/14 assertions,
  including numeric Niri IPC workspace event updates and focus
  A(fullscreen)→B(normal)→A. The native Niri compositor scenario and
  full maintainer validation have NOT been run on this code here.
  Next: sync `dev` into the installed iNiR runtime via
  `./setup update --local` and restart, then reproduce on the
  same workspace; assert Screen Edges/Panel/Perimeter return for B,
  hide under A fullscreen, recover when A exits, remain correct
  on a second output, and don't regress popup hover/lifecycle.
  If still failing, capture Niri workspaces/windows and
  `abyssHoverProbe.snapshot` with exact running source identity.
  **Owner accepted on 2026-10-10: fullscreen switch regression is fixed.**
  Preserve the fix and the 14/14 focused source assertions.
  Note that the separately supplied 17:06 diagnostic archive reports
  an earlier checkout SHA (`418fcd9e`) and cannot by itself identify
  the exact running fix revision; owner's explicit functional
  acceptance is the basis for checking off this task. Archive after
  the normal seven-day retention window.

- [ ] **Notification Center post-notification Popup has wrong size/placement and lags — owner report 2026-10-10 21:55 ICT:**
  **Owner follow-up 2026-10-10: normal post-alert Center sizing is now OK;
  stopping screen recording and receiving the `Recording saved` notification
  still makes the transient popup lag.** This is a narrower unresolved
  case, not evidence the prior toast-to-Center separation regressed.
  Concrete path: `scripts/videos/record.sh` calls
  `notify-send "Recording saved" "${SAVE_PATH%/}/$output_name" -a Recorder`
  after the recording file is finalized, and
  `AbyssNotificationsContent.qml` previously published the transient
  `NotificationListView.contentHeight` directly. Long path cards may need
  multiple delegate/layout passes, driving repeated body requests while
  the recording indicator disappears and popup reveal starts.
  Causality of native frame pacing is **not proven**.

  Source-level refinement on `dev`:
  `98d0b387881c1d94b75dff5a78aee312bf830da5`
  batches positive ListView measurements through an on-demand 75ms
  Timer and publishes settledPopupHeight/popupLayoutReady.
  `df86dca7278f680d2c9d555c62ac7b1be8f9943e`
  enables `residentContent` while transient notifications are pending,
  measuring their card offscreen at the resting target size; only reveals
  the banner once popupLayoutReady. No new background timer,
  global mouse grab, visual quality reduction or change to the
  dedicated NotificationCenterPopup. A source-executed regression,
  `a57020f20da369baf8db183a2164cb1dbc1cc927`, verifies
  zero/provisional/measured/new-notification states and multiple
  banner/Center cases: **46/46** isolated JavaScript assertions PASS.
  This is NOT native Qt frame/presentation evidence; on-Niri recording
  stop/new-notification acceptance remains OPEN. Update the common
  technical investigation in
  [Notification post-alert geometry and recording-stop lag](../../docs/abyss/NOTIFICATION_CENTER_POST_ALERT_GEOMETRY_LAG_2026-10-10.md).

  **SOURCE-LEVEL FIX IMPLEMENTED on dev (2026-10-10); Niri acceptance OPEN.**
  The earlier native video exposed a tall right-edge notification surface
  morphing into a much smaller bottom-right Popup while a new alert was
  still present. The confirmed source-level conflict was the older
  `AbyssPerimeter.qml` transient `notification` host:
  `centerOnOutput` switched its presentationKind, edge, contentKind
  and measured contentHeight to a nearly full-screen `center` layout
  immediately when `GlobalStates.notificationCenterOpen` became true,
  even though the very same event requested this host to CLOSE and
  `AbyssBodyHost.visualResident` kept its closing animation alive.
  Source change `6f0321dec1c688d25cddcd5728ee0f2a2276f8b0`
  fixes the role conflict: the transient host now ALWAYS uses
  `presentationKind: "notifications"` and `contentKind: "popup"`,
  with independent toast-only dimensions/edge/along/obstacles;
  `!GlobalStates.notificationCenterOpen` still causes its normal
  semantic close. The dedicated NotificationCenterPopup remains the
  sole history Popup. `98415d0c43d3145920265f8f6ccdccdf79368273`
  enables stable-size toast content behind its existing reveal clip
  rather than resizing/reflowing the content with that clip.
  This removes a concrete source of extra Loader construction,
  history markAllRead coupling, a wrong-height transition and layout
  churn. It does NOT establish a native end-to-end FPS improvement.
  `scripts/test-abyss-notification-transition.mjs` runs exact
  committed QML expressions against the fresh-alert → Center-open
  transition, top/bottom placement, multiple/empty notifications,
  customized Center sizes and separate dedicated host: **32/32 PASS**
  in an isolated JS environment. Registered in
  `scripts/validate-maintainer-local.sh`. Full validator / Niri
  test and owner acceptance remain PENDING. **Keep issue OPEN**;
  next owner action: sync dev, install QML, reproduce the 21:55
  recording steps, confirm tall sidebar never appears, observe
  layout stability AND whether perceived animation lag has ended.
  Preserve the separately reverted hover/bridge work.
  **Original video and independent bug report:** Owner video
  `2026-10-10_21.55.09.mp4` (1920×1200, 30fps, ~8.73s,
  shared in ChatGPT, NOT a repository file) shows a recent notification
  toast (~0.7–1.5s), followed by a connected right-hand Notification
  Center opening with an abnormally tall/narrow silhouette
  (~1.7–2.5s), changing apparent size/attachment around
  ~2.7–2.9s, then appearing as a much shorter bottom-right
  Notifications/Activity tabbed Popup (~2.9–4.1s). The change is
  visually observable; exact frame timing, compositor involvement,
  configured dimensions and causality are **NOT** yet measured.
  This is distinct from the existing premature hover/bridge dismissal.
  Repository source offers plausible investigation sites only:
  `NotificationCenterPopup.qml` fixed requested implicit dimensions,
  `AbyssPerimeter.qml` hosted popup span/depth/edge/join,
  `AbyssBodyHost.qml` animation and retained/visual placement,
  `AbyssBodyPlacement.js` allocator shrink/stack and
  `AbyssGeometry.js` corner joins. Do not declare any of
  these the cause without an actual native before/after trace.
  **Technical analysis, video timeline, read-only native measurement
  requirements and acceptance:**
  [Notification Center post-alert sizing/lag investigation](../../docs/abyss/NOTIFICATION_CENTER_POST_ALERT_GEOMETRY_LAG_2026-10-10.md).
  Runtime source patch is committed; keep OPEN until exact-SHA Niri capture,
  controlled no-notification/with-notification reproduction,
  verified initial/resting size and owner acceptance.

- [ ] **AC-I04 — Companion-enabled Screen Edge module hover regression — owner report 2026-10-11:**
  [Owners: Alis `dev` host + Alis-Companion `main`] With **Companion
  enabled/open**, Screen Edge modules stop opening their connected Popups
  on pointer **hover**, although clicking the same module still works.
  This is a **new Companion-enabled reproduction** of the historically
  investigated Popup/Edgebar hover/input problem below; it does NOT prove
  the old defect has the same cause. Compare the exact same module, output,
  edge and placement with Companion **disabled vs enabled**, Companion
  visually absent/present, cursor idle/rapid enter/leave and click
  control; test Clock/Calendar, Weather, Media, Wi-Fi/Bluetooth and
  representative top/bottom/left/right edge modules. Observe actual Niri/
  Qt pointer enter/leave, activation leases, `AbyssPerimeter.qml`
  `nativeInputMask`/layer/keyboard focus and the shared
  `companionExtension.inputRegions` from
  `modules/abyss/HadanionSurface.qml` and the source package's actor
  hover/overlay regions. Distinguish a Companion region intercepting the
  pointer, a priority/lease change and missed hover activation; **all
  remain hypotheses until source- and event-backed diagnosis**.
  Preserve Companion drag/chat/animations, one optional actor, real input
  hit areas and click behavior; NEVER solve this by an unmasked,
  full-output interception layer or a click-only workaround. Capture
  pinned Alis/Companion/installed release SHAs and bounded exact-source
  native pointer/IPC evidence before proposing a patch. Relevant older
  [hover investigation](../../docs/abyss/POPUP_EDGE_HOVER_UNRESOLVED_2026-10-10.md)
  includes previously ineffective approaches: inspect/revert disproven
  candidates rather than stack another blind fix. Acceptance: normal
  hover → connected Popup and reverse transfer restored with Companion
  on/off, clicks unaffected, four edges/scales/outputs and actual owner
  desktop signoff. State: OPEN; NOT_DIAGNOSED, native reproduction needed.

- [ ] **Popup/Edgebar closes while hovered — received/updated 2026-10-10:**
  **Owner update, 2026-10-10 evening — LOCAL DESKTOP CHATBOT NEXT:**
  The owner retested TWO successive cloud hover/bridge fixes and explicitly
  reported **no improvement** (latest video: `2026-10-10_21.21.26.mp4`,
  supplied in the chat, not tracked in Git). At the owner's request,
  ALL runtime QML/JS, test and validation changes from the attempts were
  reverted exactly to pre-experiment commit
  `a7e76b509075ba1a3f2bc9d0c16b6a5e76672ba1`, with original source
  blob SHAs verified and no runtime/test diff at final revert
  `eb3f9d35133e41e7ad343b94c74671fc7fe5e9ac`.
  **Do not reuse** either rejected approach or claim the green 42/42 and
  31/31 source expression tests proved native pointer correctness.
  The local chatbot must investigate with real Niri/Quickshell pointer
  event/input-mask and semantic lifetime evidence before making a fix.
  **Complete technical notes, precise reproduction and acceptance:**
  [Popup–Screen Edge native hover investigation](../../docs/abyss/POPUP_EDGE_HOVER_UNRESOLVED_2026-10-10.md).
  Status **OPEN**, owner acceptance pending; no new runtime patch authorized
  by this revert/documentation action.
  NEW OWNER REPRO 2026-10-10: moving the pointer across the gap/connection
  between a Popup and its Screen Edge still loses hover/focus and automatically
  dismisses the Popup. Owner supplied `2026-10-10_13.34.50.mp4` (31.93 s,
  1920x1200, ~30 fps) in the conversation, showing multiple edge-attached
  panels; the clip is not independently frame-timing evidence or an attached
  repo fixture. Do not count the previous probe correction as a product fix.
  Preserve native/Qt pointer focus and hover separately from keyboard focus;
  require deliberate pointer transfer (physical frame → connector → body),
  sustained dwell, fast reversal, all four edges, generic and StyledPopup,
  Bar auto-hide leases and click-through to blank workspace.
  body and painted Screen Edge connections must retain hover. Pushed source
  `10311cd96892d86d86870d327d28b27e32df8fbd` repairs padding/interactive-child
  hover and coalesces Bar hold publication; its focused four-edge checks passed.
  A further composite-mask candidate for SDF shoulders, physical Edge bridges,
  source-module pointer priority and Recording input is saved **WIP / HOLD** in
  this stop checkpoint. Final shoulder geometry, Clock/Weather (1,156 samples),
  cold mount and Recording fixtures pass; final generic/mature hover fixture
  **FAILS** at left bridge x=14,y=200. That point overlaps the source anchor;
  inspect actual requested/anchor/body leases before deciding whether this is a
  probe error or runtime dismissal. Cloud continuation on 2026-10-10 committed
  test-only qualification change `c499fb3ecdb07250c710bac82f483272c42e46c2`:
  `scripts/test-popup-anchor-hover-runtime.py` now searches SDF-painted
  bridge pixels outside both source input regions and content, asserts the
  resulting point belongs to the native/hover footprint, and preserves all
  four edges, Bar leases and 900ms dwell. This removes one ambiguous oracle;
  **runtime NOT RUN, result UNKNOWN**, and no source runtime fix or product
  acceptance is claimed. Next: execute the corrected fixture on this exact
  commit with a stable private output, inspect requested/anchor/body leases
  if it fails, then run geometry/Weather/cold/Recording checks sequentially.
  Resolve failures before exact-SHA canonical clean-clone validation. Do not
  weaken all-edge dwell/input tests. Owner cold/normal hover, connected input,
  click-through and multi-output acceptance remain separate.
  Serial local validation order (preserve full logs, actual exit codes and exact
  source SHA): `python3 scripts/test-abyss-geometry-contract.py`,
  `python3 scripts/test-popup-anchor-hover-runtime.py`,
  `python3 scripts/test-popup-cold-start-lifecycle-runtime.py`,
  `python3 scripts/test-weather-popup-handoff-runtime.py`, then
  `python3 scripts/test-recording-abyss-runtime.py`. Stop on a real failure
  and diagnose rather than interpreting older PASS logs as new results.
  Once focused failures are resolved, execute
  `bash scripts/validate-maintainer-local.sh` on a clean exact-SHA checkout;
  then request independent owner desktop/multi-output acceptance.
  [Durable receipt and logs](../../docs/evidence/abyss-product/20261010-hover-checkpoint/README.md).
  The earlier maintainer stop/save/push was honored at the checkpoint.
  **NEW source candidate 2026-10-10:** `6c10387d18aa1793d7ad2f2ef20eb37020d69abf`
  extends only the popup's tangent-bounded painted input to the physical
  Screen Edge (previously stopped at its inner seam); no output-wide mask.
  It also coalesces exactly adjacent equal-span SDF strips to reduce live
  Region/Instantiator churn while retaining every covered input pixel.
  Contract additions: `38437f56` (physical seam/strict SDF occupancy) and
  `5a2cb977` (four-edge physical rim → connector → content and reverse,
  sustained 900ms, generic/StyledPopup, Bar lease, click-through, focus).
  Offline V8 execution of the repository geometry test body passed
  **504,005 assertions**, source/test blob SHAs `3d6953ae`/`372ff060`,
  with equivalent assertion and readFile stubs; 576 independent strip-union
  comparisons showed identical occupied pixels. **This is not a Qt/Quickshell
  run; runtime, exact-SHA canonical and owner session are NOT VALIDATED.**
  Next: perform the serial native commands above at fresh HEAD, preserve
  focus/lease/Region evidence on any failure, compare owner hover behavior,
  then canonical and physical multi-output acceptance. Keep issue OPEN.

  **OWNER REGRESSION RECONFIRMED 2026-10-10 (current continuation):** after
  `6c10387` and its tests, Popup still loses hover/auto-closes while crossing
  the connector, and Abyss Panel still lags. Therefore that runtime fix is
  **INEFFECTIVE / NOT ACCEPTED**, irrespective of offline 504,005 assertions;
  those assertions only proved geometry, not compositor pointer delivery.
  Dedicated non-force revert `0d26291646bc9b4db6f0678c54b10f7a4b8c8962`
  restored `AbyssGeometry.js`, the geometry test and hover runtime fixture
  to `e6d220e` source without rewriting prior history. DO NOT reinstate the
  physical outer-edge hitbox extension or Region coalescing unchanged.
  A distinct read-only diagnosis `9c6366ee5d3557a98940637dad80b667b71bc4f0`
  expands existing `abyssHoverProbe.snapshot()` with each mature popup's
  requested/semantic/linger state, source-vs-body hover, input mask registration,
  strip count and geometry; generic popup state is also captured. No automatic
  remap, global hover padding, timer delay or input interception was added.
  `abyssHoverProbe.refreshMask/swapMask/remapWindow` remain explicit bounded
  diagnostic experiments; **do not apply them automatically**. Compare
  snapshots with the installed exact source SHA during a genuine failed
  crossing: distinguish compositor mask not delivering events, source hover
  priority, and semantic timer expiry before changing input routing. Neither
  old focused PASS nor an IPC snapshot alone is physical mouse acceptance.
  Serial native fixture and canonical results on current SHA are NOT RUN;
  preserve source/device and before/after receipts.

  **Diagnostic failure received 2026-10-10, 07:18:55 UTC:** owner uploaded
  `identity.txt` and `frame-start.txt` from collector first run. Checkout
  `dev` was `ff56015cf43b16580f0373881e8471984d9633bc`;
  `qs=/usr/bin/qs`, original `qs_config=auto`. Error:
  `Could not find "default" config directory or shell.qml in any valid config path.`
  This is the diagnostic **NOT STARTED**: neither frame intervals nor pointer
  lease samples were collected; it proves neither a product bug cause nor a
  product fix. Existing `scripts/inir` explicitly targets a running config
  through `qs -p "$config_dir" ipc call`; old collector lacked `-p`.
  Corrected collector `4dc295e7f118a2445ca5ab4d6a66de2552312532`
  selects an active iNiR instance, or an explicitly provided path, and records
  installed-QML-vs-checkout match flags without starting/restarting shell.
  The corrected collector has NOT been run on the owner's desktop. Repeat
  after pulling latest `dev`; if methods are absent inspect the installed
  vs checkout flags, never treat a matching Git checkout SHA alone as proof
  that the running shell has been updated. Preserve actual command failure
  receipts and resume native hover/canonical acceptance only with live evidence.

  **2026-10-10 collector Bash syntax regression and resolution:** the next
  owner run failed at line 32 (`syntax error near unexpected token '|'`)
  because the text-mode `qs list --all` process substitution placed a pipe
  on the following line without ending the previous line with a pipe.
  A first attempted in-place fix `10a6604` was ALSO invalid: JavaScript
  replacement expanded the `$'` sequence inside `'/shell\\.qml$'` and
  duplicated the script tail. DO NOT use that commit. Final fix
  `9ba0204b4e2254393c8518526e9ddf6496b6769d` restored the exact
  840c00d source and replaced the bad pipeline without JS substitution
  expansion. Final Git blob `12dd8dd22d521f5be9312d17580c97ef7e46f780`
  was reproduced byte-for-byte in a local test environment:
  `bash -n` **exit 0** and a mocked active `qs -p` IPC sequence completed
  `startFrames`, `stopFrames`, exactly 40 `snapshot` calls, **exit 0**.
  These checks validate collector syntax and control flow only; they are
  NOT a Quickshell/Niri live test and do not close the popup/lag issues.
  Next: owner reruns after `git pull --ff-only` and supplies new receipts.

  For a read-only owner
  capture after installing the exact `dev` source, run
  `bash scripts/collect-abyss-hover-frames.sh`: 6 seconds of bounded
  frame-swapped intervals, followed by 40 at-most-150ms-apart requested
  IPC hover snapshots, each with a timestamp and actual errors preserved.
  Reproduce opening/reversal during the first phase, the source→bridge→body
  hover loss during the second. Owner now supplies **one**
  `hadalis-abyss-hover-*.tar.gz` archive rather than three separate files.
  Archive contains the original `identity.txt`, `frame-start.txt`,
  `frame-intervals.txt`, `hover-snapshots.log` and `run-result.txt`
  (on early failure, only the evidence files already produced).
  `15f5abbb1bc19bf5377636dbee03c7f973713330` adds a bounded
  exit-handler archive on both success and nonzero IPC exits; final Git
  blob `defb45271438a80cc012d611467ce6c9451f264a` passed actual
  `bash -n` exit 0 and fake `qs -p` full 40-snapshot test (exit 0)
  plus simulated failing `startFrames` (exit 1 and valid partial archive).
  This is script/mock validation, NOT production hover acceptance.

  **Real owner capture 2026-10-10 at 07:49:30Z**, checkout
  `8fd0db31006096f738dd8a4b527a009e10649558`, on Niri
  single eDP-1 output: Quickshell config resolved to
  `/home/llocphann/.config/quickshell/inir`, installed shell,
  AbyssPerimeter and AbyssGeometry file comparisons all MATCH, 40/40
  snapshot IPC calls succeeded. However **all 40 snapshots are idle**:
  `liquidPopupsOpen=false`, generic popup resident=false,
  0 mature popup slots active, Bar hover/hold=false and no module
  hovered. Therefore this trace does NOT capture a crossing or show
  why hover is lost. To reproduce next time: when script prints
  `PHASE 2/2`, OPEN the target Popup and cross its visible connector
  during the ~7 seconds. If still all idle, investigate event/mask
  delivery separately; do not assert a closed popup is an observed
  dismissal. A checkout Git SHA alone does not verify loaded shell
  identity. The helper never remaps/refreshes the mask or changes
  configuration. **Popup hover acceptance remains OPEN.**

  **Owner archive 2026-10-10 08:04:04Z (local 15:04):**
  `hadalis-abyss-hover-20261010-150404.tar.gz` contains
  `collector_exit_status=0`, but `frame-start.txt` is actually
  `Target not found.`; `frame-intervals.txt` has `count=0`
  and all quantiles null. Checkout `dev` at
  `5896b425951a774f6b209d68b50616297f455a3c`;
  Quickshell runtime location:
  `/home/llocphann/.config/quickshell/inir`.
  The installed `shell.qml` and `AbyssGeometry.js` MATCH
  checkout, but **`AbyssPerimeter.qml` is DIFFERENT**. A
  restart without a setup sync did not put the newest QML in
  the live installed runtime. The 40 snapshot IPC responses
  were successful but all had no active Popup or module hover
  (`liquidPopupsOpen=false`, empty popup slots); not a captured
  source→connector crossing. The old collector trusted an exit
  code 0 from missing target, a false positive diagnostic result.

  **Diagnostic guard fix `faf8ad59b9336ad6d2689b20ace52b28f22a6d45`:**
  fail closed if installed `shell.qml`, `AbyssPerimeter.qml`
  or `AbyssGeometry.js` differ from checkout (exit 4);
  require actual `"started":true` IPC response even if
  `qs` exits 0 with `Target not found.` (exit 5);
  require frame-summary signature (exit 6); reject invalid
  Abyss snapshots (exit 2). Preserve original exit code and
  raw receipts in one automatic `.tar.gz`, including failures.
  **Exact committed script Git blob
  `d4f52cef9342defc1fde61d1c4dfacdd67ff4f54`** was
  byte-matched by local `git hash-object`, and passed real
  `bash -n` exit 0 and five deterministic fake-IPC cases:
  missing handler 5, malformed stop 6, malformed snapshot 2,
  valid 40 snapshots 0, stale installed QML 4. Each generated
  one valid evidence archive. No new real Niri hover test on
  this corrected SHA. From checkout run the repository-supported
  `./setup update --local`, then `inir restart`, then collector
  (supported local-sync mode skips git pull and preserves dev tracking;
  full setup still performs its managed backup/sync/validation tasks).
  This safer local-sync hint was added to the collector in
  `5f7493ace0c4c3eee0f1f7e1bd7c75103a138b9a`;
  new exact blob `b19868ae8983bced8475b5133d44fddb89f0bbad`
  has `bash -n` exit 0 and differs from the five-case tested
  script only in this human-readable remediation text.
  Do not mutate installed runtime automatically from collector.
  Keep **Popup hover user acceptance OPEN**.

  **Owner archive 2026-10-10 08:26:41Z — now source MATCH, target MISSING:**
  The single `hadalis-abyss-hover-20261010-152641.tar.gz` contains
  `run-result.txt: collector_exit_status=5`,
  `frame-start.txt: Target not found.`,
  `diagnostic-error.txt` correctly refuses a successful frame probe.
  Checkout: `dev` at `3acf9685ce7aef5e1c7e879e2437a7001ac3f874`,
  running resolver: `/home/llocphann/.config/quickshell/inir`.
  Unlike the previous run, ALL THREE installed-vs-checkout source
  comparisons `shell.qml`, `AbyssPerimeter.qml` and `AbyssGeometry.js`
  now **MATCH**. This means the installed files match the checkout,
  but it does NOT establish that the active QML tree has constructed
  `AbyssPerimeter.qml` or that its IPC handler is registered.
  There are NO frame intervals and NO hover samples in this bundle;
  do NOT infer a popup dismiss cause from these absences.

  Source review on `dev`:
  `shell.qml` activates `ShellAbyssCriticalPanels.qml` only under
  `activePanelFamily=abyss` and familyMountReady; within that critical
  host the `AbyssPerimeter.qml` LazyLoader additionally requires
  `Config.ready`, deferred readiness, `enabledPanels` containing
  `abyssPerimeter`, and no diagnostic unmount. The handler
  `abyssHoverProbe` lives INSIDE that optional Perimeter. Therefore
  candidate explanations for `Target not found.` include the
  relevant family/host/Perimeter not being mounted, or a stale/failed
  live engine instance. None are yet proven by the archive.
  Distinguish them using registry and critical-host state before
  changing lifecycle or hit regions. Quickshell documents the
  read-only `qs ipc show` target/function enumeration.

  **Collector evidence expansion
  `5462432e442048be32bf7de8e1227b892ed86e93`:**
  capture `ipc-targets.txt` from `qs -p CONFIG ipc show`,
  `abyss-host-status.txt` from existing read-only
  `abyssHostProbe status`, `hover-preflight.txt` from
  `abyssHoverProbe snapshot`, plus per-probe process statuses,
  in the SAME one-file archive before `startFrames`. Keep
  fail-closed `startFrames` recognition and now reject a
  `stopFrames` result with count=0 as non-evidence (exit 6).
  Script does NOT remount or reconfigure the desktop.
  This candidate's native run is PENDING; status remains OPEN.

  **Owner archive 2026-10-10 09:28:01Z (16:28 local), exact
  checkout `a5ebffa747ddead7799d6dd6501f712996e068bf`:**
  `hadalis-abyss-hover-20261010-162800.tar.gz` was inspected
  without extracting archive paths to disk. Contains a valid
  `collector_exit_status=0`, installed/checkout parity MATCH
  for `shell.qml`, `AbyssPerimeter.qml`, `AbyssGeometry.js`,
  live IPC registry `target abyssHoverProbe` with
  `startFrames`, `stopFrames`, `snapshot`; all 3 preflight
  CLI status values 0. `abyssHostProbe.status()` returned:
  family abyss, perimeterLoaded/perimeterActive true,
  deferredPanelsReady=true, nativeFirstFramesReady=true,
  coldRecreated=true. Thus the prior `Target not found.`
  obstruction **is NOT present in this capture**.

  40 valid hover snapshots for output `eDP-1`; samples 00–34
  show no popup. Exactly samples 35–39 show an OPEN
  `notificationCenter` popup in slot 0. At #35 and #36 its
  input bounds grow from width ~0.012 to ~123.68px; #37
  width 420px and anchorHover=true. #38 (09:28:18.946Z)
  anchorHover=false but contentHover=true, establishing
  a pointer-reachable content phase. #39
  (09:28:19.186Z) anchorHover=false and contentHover=false,
  bodyHover=false, yet `requestedVisible=true`,
  `lingerVisible=true`, `hosted=true`,
  `nativeRegionRegistered=true`, `bodyReady=true`,
  `bodyAcceptsInput=true` and input width still 420px.
  `semanticHold=false` all five slots; `barPopupHoverLease`
  is false by design for NotificationCenter
  (`barAutoHideHoldEnabled: false`), NOT a lost Bar lease.
  There is **no popup dismissal observed**, because the
  original 40-snapshot window ends immediately after #39.
  Neither a true source→connector failure nor a fix is
  established by this trace. Avoid interpreting the final
  all-false hover state alone as a confirmed bug.

  **Targeted follow-up on `dev`:**
  collector `d642cce966aea969a7f843180db82bece38e970a`
  extends the bounded hover phase to 100 snapshots,
  adds `popup_seen_during_capture` and
  `popup_open_to_closed_transition_observed` markers in
  `identity.txt`, and still archives everything in one
  `.tar.gz` (a missing popup emits a warning).
  Read-only `AbyssPerimeter.qml` snapshot addition
  `1a0875d1b0fdd9c7f572d96e1a6e1d3c6cd90c00`
  exposes `humanVisibleRequest`, `rawVisibleRequest`,
  `hoverActivates` and NotificationCenter's
  `anchorHovered`, `entryBridgeHeld`, `exitGraceHeld`,
  `hoverLeaseRequested`, `hoverSessionArmed`,
  `hoverAllowed`, `explicitForThisOutput`. No hitbox,
  focus, lease duration, animation or dismissal behavior
  was modified. This requires managed local installation
  sync of new QML before a live owner rerun; the additions
  have only source-level checks, NOT native validation.
  If later samples show an unexpected closure, correlate
  the two grace timers and semantic source state before
  attempting a causal geometry workaround.
  **Popup defect acceptance remains OPEN.**

  **Owner archive 2026-10-10 10:06:09Z (17:06:09 ICT):**
  `hadalis-abyss-hover-20261010-170607.tar.gz`, on
  `dev` checkout `418fcd9e9947cfadfe1b2453257751792875d623`,
  exited `5` before measurement.
  `shell.qml`, `AbyssPerimeter.qml` and `AbyssGeometry.js`
  on disk all MATCH checkout, but registered
  `abyssHostProbe.status()` returned
  `family=abyss`, `shellEntryReady=true`,
  `deferredPanelsReady=false`,
  `perimeterLoaded=false`, `perimeterActive=false`,
  `initialMountReady=false`, `nativeFirstFramesReady=false`,
  `coldRecreatePending=true`, `coldRecreated=false`.
  `abyssHoverProbe.snapshot` and `startFrames` both printed
  `Target not found.` with CLI exit status 0. Therefore the
  optional Perimeter handler had NOT been registered when
  this one snapshot was taken; its absence is directly explained
  by the deferred/initial-mount gating in
  `shell.qml` and `ShellAbyssCriticalPanels.qml`.
  A single sample does NOT prove whether loading was merely
  delayed (e.g. immediately after shell restart) or permanently
  stalled. There are NO hover or frame samples in this archive.
  Popup loss and frame lag remain unmeasured by this run.

  **Collector hardening `5bab2c774df7e2ecb5c0a446e3053a981323b1cd`:**
  after on-disk parity check, poll `abyssHostProbe.status`
  and `abyssHoverProbe.snapshot` at 250ms intervals for
  no more than 25s until Abyss, deferred readiness, active
  loaded Perimeter, first frame, complete cold re-create
  and at least one ready output are confirmed. Log every
  result to `readiness-trace.log` and final host/preflight
  payloads to the SAME automatic one-file `.tar.gz`.
  Give distinct exit 7 and archive evidence on timeout.
  Collector never mutates input regions, remounts QML,
  disables rendering or restarts the shell.
  **Native readiness, real source→connector→popup passage,
  and user-confirmed hover behavior are still OPEN.**

  **Owner READY archive 2026-10-10 10:33:48Z (17:33 local):**
  `hadalis-abyss-hover-20261010-173348.tar.gz`, exact
  `dev` checkout `ffef7ef8ab5ca6107f11de959b33c404d644dd50`,
  installed-vs-checkout parity MATCH on all three critical
  sampled files, running Niri `eDP-1` one output.
  `collector_exit_status=0`; `ready_attempt=0`,
  `abyssHostProbe.status` shows Abyss active, deferred panels
  ready, perimeter loaded/active, coldRecreated=true,
  nativeFirstFramesReady=true; `startFrames` returned
  `started=true`, and 100/100 IPC hover snapshots parsed.
  `identity.txt` reported popup_seen=1,
  popup_open_to_closed_transition_observed=1.
  Inspecting all samples reveals TWO full open→retract→closed
  cycles for **notificationCenter** (NOT generic Bar popup):
  #66–76 (~10:34:09.564–11.507Z; order 18) and #78–87
  (~10:34:11.882–13.597Z; order 19).
  The visible input region widened to 420 px at #68/#80
  (bounds x=1490..1910, y=616..1176 on eDP-1).
  `nativeRegionRegistered=true`, `bodyAcceptsInput=true`,
  `stripCount=62` while fully open. At #72/#83 the
  StyledPopup source `anchorHover` drops from true to false,
  without any sampled `bodyHover` or `contentHover`.
  At #73/#84 `requestedVisible=false`,
  `semanticHold=true`; at #74/#85 `stripCount=0`,
  `bounds.width=0`, `bodyAcceptsInput=false`.
  Popup slot vanishes at #76/#87. These prove hover-driven
  closure, NOT that the pointer physically remained over
  a painted connector (no pointer coordinates in archive).

  **Direct source/state contradiction observed and narrowly fixed:**
  At #68–71 and #80–82, `StyledPopup._anchorHover.hovered=true`,
  yet NotificationCenter `_anchorHovered=false` and
  `hoverLeaseRequested=false`. The latter tested only
  the specialized `anchorItem.containsMouse` flag (which
  ScreenCorners gates behind its dwell-ready MouseArea).
  Commit `96262edd788bf22fc69daaf4effe78a6384a2b38`
  now makes `NotificationCenterPopup._anchorHovered`
  include the existing actual source `HoverHandler`,
  preserving an active notification hover lease instead
  of letting its `entryBridgeHeld` time out beneath
  an observed hovered anchor. This leaves existing
  configured grace periods, placement, hit regions,
  input surface and animation unchanged.
  `scripts/test-notification-center-hover-lease.mjs`
  (`196d675e458cd65d4d24e5d073ecd9c1612c6ee4`)
  executes the actual source property expressions and
  passed 23/23 isolated JavaScript assertions; the
  canonical maintainer validator now runs it via
  `418c7de3ca406f160977e9c0dfcc387d478f3e8d`.
  Actual Niri regression proof and generic popup edge
  traversal remain PENDING. Next: sync updated
  `dev` QML via `./setup update --local`, restart,
  rerun bounded archive and retest corner-to-popup
  hover dwell without leaving the painted connector.
  Do not infer the correction addresses all edge/Bar
  popup families or mark acceptance complete.

  **Owner archive 2026-10-10 10:44:39Z (17:44 ICT) on exact
  checkout `ab1f52dd255c32a7626fd35fcaffceadf1b304eb`:**
  `hadalis-abyss-hover-20261010-174438.tar.gz`, 11 files,
  collector exit=0, readiness attempt=4, all installed QML/JS
  comparisons MATCH, live Abyss Perimeter loaded and active,
  `startFrames` succeeded and 100/100 hover JSON snapshots valid.
  One sampled output `eDP-1`, only mature popup kind
  `notificationCenter`. There were **TWO** popup open/retract
  episodes (slot orders 2 and 3), despite the collector's
  boolean `popup_open_to_closed_transition_observed=1`:
  order 2 was live #67–75, lost source hover at #72 while
  neither body nor content received it; the new
  `NotificationCenter._anchorHovered` now matches its
  `StyledPopup.anchorHover` at #67–71 and its hover lease
  remains true in those same samples. #72–73 shows
  exitGraceHeld=true and requestedVisible=true, #74
  requestedVisible=false and inputBounds width=0.
  No mouse coordinates were captured, so this first
  episode cannot yet be called a spurious seam dismissal
  rather than genuine pointer departure.
  Order 3 was live #81–96: anchor hover true #81–85;
  **source→content transfer succeeded** at #86,
  `contentHover=true` and `hoverLeaseRequested=true`
  continuously #86–93 (~1.5 seconds). #94 reports all
  hover=false with exitGraceHeld=true; #95 begins retract
  after the grace (not unexpected unless the pointer stayed
  inside the painted connector). This is native evidence
  the earlier lease contradiction was repaired in the
  observed source-held phase, and that one genuine
  transfer works, NOT complete acceptance for all paths.
  Status remains OPEN pending held-pointer connector dwell,
  other Popup kinds and native regression confirmation.

  **Follow-up diagnostic precision, not a product fix:**
  `eb1be574f339fc5fb3661ca20a012dce4aa8544f`
  exposes the already-existing StyledPopup source
  HoverHandler's `scenePosition` ONLY while hovered.
  `6f51143c30ad9137608dc6fee361f49ba270b56e`
  does the same for the existing hosted popup content
  handler and records `anchorScenePoint` and
  `contentScenePoint` in `abyssHoverProbe.snapshot`.
  Qt's HandlerPoint resets coordinates when there is
  no pointer; both fields return null when unhovered.
  The corner source and Perimeter body are in DIFFERENT
  QQuickWindow coordinate systems: never treat these
  as global coordinates or proof of cursor location
  during a missed/cleared hover event. No new
  input handlers, region masks, leases, timers or
  popup rendering behavior were introduced.
  `02b26956c02a1d64466bd2d28afb230892cdadb6`
  corrects the collector's boolean-only popup cycle
  summary by adding counts while keeping the legacy
  observed flag. Reprocessing 17:44 showed opens
  at #67/#81 and closes at #76/#97: two full cycles.
  The focused diagnostic source/lease regression now
  includes the new pointer fields
  (`c0e02aa337f434d74253e317f7f306aaa6018ae5`),
  and **27/27** assertions PASS in an isolated
  JS execution of the committed source expressions.
  These are not Qt/Niri runtime tests. The new
  coordinate fields and generic-edge transfer still
  require native owner validation; issue remains OPEN.

  **Owner archive 2026-10-10 10:58:22Z (17:58 local),
  `hadalis-abyss-hover-20261010-175821.tar.gz`:**
  `dev` checkout `1e934698dea22d39877dfda5e8de982ebc50c5ed`,
  all three on-disk comparisons MATCH, native Abyss
  Perimeter ready at polling attempt 6, collector exit 0,
  100/100 snapshots valid, four
  `notificationCenter` open→closed cycles:
  #15–29→30 (order 3), #47–59→60 (order 4),
  #70–77→78 (order 5), #82–89→90 (order 6).
  This was exactly counted by the corrected
  `popup_open_transition_count=4` and
  `popup_open_to_closed_transition_count=4`.
  Anchor→hosted Popup hover was explicitly observed
  in all four cycles; 3 cycles had sustained hosted
  hover (#20–21 and #23–26 in the first,
  #50–55 in second, #73 third, #85 fourth).
  Crucially, order 3 lost both source and hosted
  hover at #22 and regained hosted hover at #23;
  the `exitGraceHeld=true` bridge prevented retraction.
  A subsequent all-false interval #27→28 ended
  the visit. This is proof that the grace sometimes
  recovers a transient loss, not proof of full native
  connector continuity or a bug-caused final close.
  The existing scene-local source/host pointers reveal
  within-hover approach positions, e.g. order 3:
  source (1919,1199), hosted (1899.48,1199)
  → (1879.97,1187.29), absent at #22,
  regained (1856.55,1171.68). These positions
  belong to separate QQuickWindows (never claim global
  location or interpolate the missing point).
  During the open state input bounds reached
  x=1490,y=616,w=420,h=560 and stripCount=62,
  `nativeRegionRegistered=true`.
  No objective basis yet to widen the native
  input mask, increase hover grace, or alter SDF paint.

  **Focused diagnostic follow-up:**
  `d2db68cece00b95d06ec6915f51db94342c4d8da`
  adds snapshot-only `hoverGeometry`:
  actual joined/raw surface bounds, edge, insets and
  point coverage by host input rectangle, connection
  strips or excluded Bar source input; null when no
  hosted pointer. This is a per-QQuickWindow local
  hit test, NOT a global pointer tracker.
  `scripts/test-abyss-hover-geometry-probe.mjs`
  (`c36358b317ecea96d8c8d9ce834051e8eadcb056`)
  passed 13/13 pure source-equivalent JS assertions;
  `6cf1f3db8f7577c9bd7d3ba58bcb312b019752fc`
  registers it in canonical validation.
  Owner Niri acceptance and general Popup hover
  regression remain OPEN; no rendering/input behavior
  was changed to produce this probe.

  **Owner archive 2026-10-10 11:07:12Z (18:07 ICT), 
  `hadalis-abyss-hover-20261010-180711.tar.gz`:**
  Checkout `122d8e5f970102fc56919b450db5f7c42c54fa8e`
  on `dev`, installed-vs-checkout files
  `shell.qml`, `AbyssPerimeter.qml`,
  `AbyssGeometry.js` all MATCH, but installed git
  HEAD unavailable; collector exit=0, readiness
  attempt 5, host ready/coldRecreated=true,
  100/100 valid output-local hover snapshots.
  Six distinct `notificationCenter` opens:
  #6–19, #24–30, #34–45, #48–55, #59–66,
  and #70–99 (last still in flight when sampling
  ended). Five observed open→closed transitions;
  summary counters exactly `6` and `5`.

  New geometry data confirms the actual hosted
  HoverHandler receives pointer on the 62 native
  shoulder/connector strips OUTSIDE the rectangular
  body input: `pointHit.inShoulderStrip=true`,
  `inInputBounds=false`, source exclusion=false
  repeatedly (e.g. #14–16, #36–41 and #74–79).
  Raw surface x=1490,y=616,w=480,h=560;
  corner-joined surface x=1490,y=616,w=480,h=634;
  main body input x=1490,y=616,w=420,h=560
  on 1920x1200 eDP-1 output. In last visit,
  stable connector hover #74–79 at (1899.48,1195.09)
  then #80–97 shows continuous body-input hover
  (e.g. 1903.39,1175.58 up to 1907.29,1085.82).
  The bridge→body transition did NOT dismiss
  the Popup. At #98 the existing HandlerPoint was
  null, then #99 requestedVisible=false with
  semanticHold=true; physical cursor position once
  hover was lost is unknown. Earlier five dismissals
  likewise follow all-false hover plus grace expiry;
  none proves the pointer remained inside the
  rendered union at dismissal. Input-region geometry
  therefore cannot yet be identified as the defect.
  This source/record supports no widening of hitboxes,
  timers, SDF union or intrusive global pointer hooks.
  Generic Popup, each screen edge, actual painted-pixel
  parity and definitive user acceptance remain OPEN.

  **Owner archive 2026-10-10 11:31:32Z (18:31 local):**
  `hadalis-abyss-hover-20261010-183130.tar.gz`, `dev`
  checkout `48ea131296a474faca11eda3dbdd97e1efa0f1c4`,
  installed `shell.qml`, `AbyssPerimeter.qml`, and
  `AbyssGeometry.js` all MATCH. Collector exit=0,
  Niri eDP-1 ready on poll 28 after ~14.4 seconds.
  All 100/100 JSON hover snapshots valid, four
  `notificationCenter` open→closed episodes:
  order 3 #08–14, order 4 #19–24, order 5 #27–31,
  order 6 #34–84; counters `4` and `4` correct.
  True hosted hover on connector strips was observed
  at #21 (1903.39,1199), #28 (1887.78,1187.29),
  #35 (1903.39,1191.19). In order 6, a transient
  complete hover loss at #36 was recovered at #37
  by the existing exitGraceHeld lease; then hosted
  `contentHover=true` continuously from #37 to #81
  (approximately 45 snapshots over ~10 seconds),
  with fully open input width 420px and
  `hoverLeaseRequested=true`. A sustained stationary
  point (1782.41,1167.78) at #48–79 retained the
  Popup; no spontaneous hover-driven dismissal while
  continuously hovered was observed. At #82–83 all
  hovered flags and scene point were absent, grace
  began, and #84 had requestedVisible=false.
  No global pointer coordinates on leave, so the
  closed episodes do NOT prove a hit-test hole.
  Connector-to-body and stable-body NotificationCenter
  subcase has positive repeated native evidence.
  Do NOT generalize to other popup types, corners,
  entire multi-edge geometry or user acceptance.
  **General product hover issue remains OPEN.**

  **Owner archive 2026-10-10 12:03:04Z (19:03 ICT),
  `hadalis-abyss-hover-20261010-190302.tar.gz`:**
  exact `dev` checkout `1ce236724be81cf75d974ef4bb8433c62d10279b`,
  all three installed-versus-checkout source checks MATCH,
  readiness polling success on attempt 4, both output
  and field ready, 100/100 valid hover snapshots,
  collector exit 0. `popup_open_transition_count=5`,
  `popup_open_to_closed_transition_count=5`.
  The five sampled `notificationCenter` slot orders
  are 3 (#00–10), 4 (#13–19), 5 (#26–32),
  6 (#45–58) and 7 (#81–97). The first order was
  already open at the start of the hover sampling,
  not proof it opened exactly at sample #00.

  In #03–07, #15–16 and #29 the hovered
  `contentScenePoint` lies in an actual
  `inShoulderStrip=true` region while outside the
  main input rectangle, with native region registered.
  In #47 order 6 starts on the strip; #48–49 all
  hover flags false, held by exit grace; #50–56
  hosted content hover returns and is continuously
  valid inside `inInputBounds=true`, so the popup
  does not close at the gap. In order 7, #85 hovered
  strip→#86–91 body input→#92–93 source anchor→
  #94 shoulder strip, all with `requestedVisible=true`.
  This includes a successful reverse transit through
  the seam without premature popup retraction.
  #95 later loses all hover, #96 grace/semantic hold,
  #97 retracts, #98 slot released. No pointer
  coordinates exist after leave, so the final close
  cannot be labeled spurious. No evidence of
  input capture over the full workspace, either.
  Notification Center seam/body hover tests have
  strong positive native evidence; actual user
  acceptance, other Popup kinds/corners and
  unusual layout transitions remain OPEN.
  No change to input mask/shape/hover timers is
  justified by this archive.


- [ ] **Canonical validation — updated 2026-10-11:** clean-clone validation
  of `9ab8d408b793a938ed2a01a9c496e9156404715e` finished **FAIL: 336 PASS,
  4 FAIL, 2 SKIP; exit 1**. Its Calendar persistence/layout, Music, warm
  Dashboard, Weather handoff, keyboard, editor, OSD and shared-content
  fixtures passed. All four failures share one source-contract drift:
  `abyssHoverProbe.startFrames/stopFrames` exist in QML but lack descriptions
  and generated CLI entries (parser, registry freshness, docs and the
  distribution check invoking that parser). `2c51aa599` adds the descriptions
  and regenerates the registry; the first three focused checks pass separately
  (exit 0). This does not upgrade the canonical result or prove owner desktop
  acceptance. [Full log](../../docs/evidence/abyss-product/20261011-9ab8d408b/canonical.log)
  and [receipt](../../docs/evidence/abyss-product/20261011-9ab8d408b/canonical.json)
  retain exact source and boundaries. QML parser capability and deferred Nix
  are the two SKIPs. Next: qualify the final committed repairs in a new
  exact-SHA clean clone; owner installed/input/visual gates remain separate.
  **Historical run:** exact committed SHA
  `10311cd96892d86d86870d327d28b27e32df8fbd` finished **FAIL: 327 PASS, 8 FAIL,
  1 SKIP**. Failures: keyboard sizing, Dashboard Music, Dashboard warm readiness,
  Equalizer presentation, Weather handoff, Abyss editor, OSD and shared content.
  [Full logs and failure details](../../docs/evidence/abyss-product/20261010-hover-checkpoint/README.md)
  are preserved. The warm fixture had a 757x852 canvas; a larger private-Niri
  output probe is recorded, but not all failures are proven environment-only.
  No retry was run after the explicit stop. The checkpoint's WIP source was
  not part of this clean-clone run and has no canonical result. Next: resolve
  affected focused failures, then validate the exact new committed SHA.
  Earlier `8b2ed6f0a` FAIL 334/1/1 remains historical; `a349d1a0c` corrected its
  stale Settings Top expectation to Bottom with 65 native forward/reverse states.
  Current canonical passes that contract; owner Polkit/focus acceptance is open.
  A previous or focused PASS never closes the overall gate.

- [ ] **Notification Popup stutter on Notification Edgebar hover and Recording start — owner report 2026-10-10:**
  Two distinct triggers need independent reproductions: (1) while a
  Notification Popup is open, hovering its Notification Edgebar opens the
  attached surface and causes visible stutter; (2) clicking **Record** starts
  recording, presents a Notification Popup and causes visible stutter. Do not
  confuse recording **start** with the separately tracked **Recording saved**
  notification on recording **stop** above, or with the pointer-hover dismissal
  issue. Root cause is UNVERIFIED; do not assume geometry, Pyramid, rendering,
  recorder or notification ownership before tracing them.
  Next: on an exact-SHA installed Niri/Quickshell desktop capture Popup/Edgebar
  lifetime, hover and recorded-frame timestamps, p50/p95/p99/dropped frames,
  compositor/main-thread load, and comparison runs without notification/
  recording; test cold/warm transitions and rapid hover. Acceptance: both
  triggers are smooth with notifications and recording still functional and
  confirmed by the owner. Link: generalized presentation jank is tracked in
  [Rework](REWORK_OPTIMIZATION.md). State: OPEN, native evidence pending.

- [ ] **Detailed Weather Popup background does not follow theme — owner report 2026-10-10:**
  Several component/card backgrounds remain grey rather than adapting to the
  selected theme. Audit `modules/bar/weather/WeatherPopupContent.qml` and
  child theme bindings, including inherited/default backgrounds. Correct
  fixed-grey surfaces without flattening meaningful component hierarchy;
  verify light/dark, wallpaper color changes, open/reopen, readable contrast
  and Abyss connected presentation. State: OPEN; needs theme screenshots,
  source validation and owner acceptance.

- [ ] **Edit Abyss Layout Media IPC preview incorrectly shows Volume IPC — owner report 2026-10-10:**
  The editor presents the **Volume IPC** sample when **Media IPC** is selected.
  Trace IPC preview type-to-component routing and restore the proper Media IPC
  sample while retaining a correct Volume IPC preview and actual IPC behavior.
  Test horizontal/vertical layout, four Screen Edges, Cancel/Done and per-output
  save/reopen. **SOURCE FIX on Alis dev (2026-10-11):**
  commit `05d5b07e3ddede9d606930b20694916385739e00` adds the
  `mediaOsd → MediaIndicator` mapping in `AbyssOsdContent.qml`
  instead of falling back to Volume. Expanded the existing real-QML
  `scripts/test-abyss-osd-content.sh` to check this preview alias;
  no desktop test was run by the cloud executor. Keep OPEN pending
  actual four-Edge editor preview, Volume control, save/reopen and
  owner visual acceptance at the installed source SHA.

- [ ] **Music tab Results / Queue scroll and scrollbar missing — owner report 2026-10-10:**
  Result, Queue and potentially other affected Music tab lists do not scroll
  and show no scrollbar. Repair content height/viewport/event routing and
  render theme-consistent scrollbar when content overflows. Check wheel,
  touchpad, drag and keyboard scrolling through long results and Queue in
  compact/expanded layouts; keep selection, search and playback behavior.
  State: OPEN; source investigation and owner desktop acceptance pending.

- [ ] **Volume/Brightness OSD missing in fullscreen; Physical Screen Edge fallback — owner report 2026-10-11:**
  Under real fullscreen, changing volume or brightness does not display its
  corresponding IPC/OSD/Popup. Restore transient Volume and Brightness feedback
  while keeping the app genuinely fullscreen. When normal Abyss Screen Edge
  surfaces are suppressed, attach the indicators visually to the **Physical
  Screen Edges** of the affected output; when no longer fullscreen, restore
  their standard connected Abyss presentation. Do not reopen an entire hidden
  edgebar/panel just to show the OSD, nor create a permanent overlay/input mask.
  Audit modules/abyss/AbyssOsdController.qml, AbyssPerimeter.qml,
  content/AbyssOsdContent.qml, modules/screenCorners/ScreenEdges.qml and
  services/GameMode.qml for visibility, output selection and fullscreen
  stacking. Niri/layer-shell placement and compositor feasibility require
  native evidence; root cause is not proven. Preserve theme, smooth arrival,
  proper timeout, focus/click-through and multi-output isolation; verify
  volume up/down/mute and brightness keys, games/videos fullscreen on each
  output, scaling, fast repeats, leaving fullscreen and nonfullscreen behavior.
  **Independent of the already owner-accepted fullscreen focus/screen-edge
  suppression regression** documented earlier; do not reopen that fix.
  State: OPEN; diagnosis, Niri functional/visual test and owner signoff pending.

- [ ] **Recording Popup Expand Controls/Minimize buttons fail; dot-only minimized hover mode — owner report 2026-10-11:**
  The Expand Controls and Minimize actions on the Recording Popup do not work.
  Restore the action handlers and connected geometry/input ownership. In
  **minimized mode**, resting UI must show **only one small blinking red dot**
  while recording: no timer, Stop/audio buttons, drag handle or expand control
  exposed until hovered. Hovering the dot temporarily expands the recording
  controls; leaving hover returns to dot-only form. Activating **Expand
  Controls** explicitly returns to persistent expanded mode; **Minimize**
  returns to minimized mode. Keep the wake/hover region available as the
  footprint collapses, and preserve stop/audio/drag access after expansion.
  Check modules/recordingOsd/RecordingControls.qml and RecordingOsd.qml,
  modules/abyss/AbyssRecordingBody.qml and shared input Regions. Source
  already exposes collapsed but it is not evidence that full dot-only mode
  works; do not infer a specific root cause. Test horizontal/vertical edges,
  rapid hover/reentry, auto-hide, click targets, focus/keyboard access,
  drag/position, different screens and scaling, lock/unlock and recording
  start/stop. Don't create transparent interception zones or accidentally
  end recording. Cross-reference the existing Recording presentation item
  in REWORK_OPTIMIZATION.md; avoid a duplicate feature item.
  **Source repair 2026-10-11:** minimized Recording now has a 14x14 resting
  footprint with one 8px dot; the timer, Stop/audio/drag/expand controls remain
  hidden until hover. Hover peeks without changing the persistent collapsed
  choice; Expand/Minimize actions set that choice explicitly. Auto-hide keeps
  the minimized dot available, and active drag keeps expanded controls resident.
  Keyboard Space/Return and accessibility press can expand the focused dot.
  `scripts/test-recording-abyss-runtime.py` passes actual native four-Edge
  minimize/leave/hover/expand/keyboard, timer, mute, auto-hide, drag, Stop,
  lock/output teardown and retained ii/Waffle cases (exit 0). Recording and
  audio backends are fixtures; no owner recording/session was changed.
  State: OPEN for final exact-SHA canonical, fractional/multi-output and
  owner desktop visual/input acceptance; focused source interactions pass.

- [ ] **New boot/runtime warnings:** owner's log runs `0ea54cc09` and reaches
  the first frame; no startup Type-unavailable failure is shown. Investigate
  `qt.svg` unresolved paint server `a`, oversized SVG buffer, DelegateModel cancel
  `18 0`, repeated Wayland text-input disable and portal app-ID registration.
  Do not hide log categories as a fix. A bounded Qt audit reproduces missing
  paint references in WhiteSur's Obsidian icon and oversized filters in some
  WhiteSur icons even at 128px; exact attribution of the owner's `<input>:1:5634`
  and buffer messages remains open. Trace the model reset and popup/text-field
  focus lifecycle independently; preserve the redacted Weather location.

- [ ] **CAL-I01 — Calendar event changes do not reach disk after the first save — discovered 2026-10-11:**
  [Alis dev; data integrity] Actual native QML reproduction against
  `services/Events.qml` at `a4750cda8`: a fresh private Events store writes
  its empty initialization file, then Add only changes the in-memory list.
  After four seconds, `_saving=true`, `_saveQueued=true` and readback still
  contains zero events. The service releases writes through `onLoaded`, but
  FileView acknowledges saves through `onSaved`/`onSaveFailed` instead.
  Fix completion/queued-save handling and no-op saves; preserve current data
  and surface write errors. Verify real Add/Edit/Remove disk readback, rapid
  coalesced changes, repeated no-op saves and write failure recovery using
  private fixture storage. Link: compact Calendar layout below. State:
  SOURCE FIX + FOCUSED NATIVE PASS; owner and canonical acceptance pending.
  Writes now finish on `onSaved`; no-op bytes never acquire a write lease,
  and queued mutations save the latest event list. On failure, retain edits
  in memory, log the error and defer cache reload until the native writer
  callback returns; readback must not replace those edits. A user retry can
  then save identical bytes after access returns. The native test passes
  **149 checks, exit 0**, including actual Add/Edit/Remove disk readback,
  rapid coalescing, duplicate no-op saves, denied writes preserving prior
  disk data, and an identical-payload retry after permission recovery.
  [Negative receipt](../../docs/evidence/abyss-product/20261011-9dd5120bf/calendar-storage-red.json)
  and [focused repair receipt](../../docs/evidence/abyss-product/20261011-9dd5120bf/calendar-storage-green.json)
  retain source/test hashes and boundaries. The callback ordering agrees
  with [upstream FileView implementation](https://github.com/quickshell-mirror/quickshell/blob/master/src/io/fileview.cpp);
  the native fixture, rather than API inference, establishes the repair.
  Actual owner event data and installed runtime were not changed.

- [ ] **Calendar Popup Add/Edit Events text fields too small; event Remove button clipped — owner report 2026-10-10:**
  Restore readable Title/Description fields and a fully visible Remove click
  target at normal/scaled fonts in compact Calendar panes. **Source repair
  and focused native checks complete on 2026-10-11; owner acceptance OPEN.**
  A private Niri probe of `9dd5120bf` measured 36px fields with 17.5px top
  and 8px bottom padding: only 10.5px remained for 19px/28px text at
  100/150 percent fonts. At 150 percent, EventCard's Remove occupied
  x=294–326 outside its 292px card. Its content also exceeded the allocated
  height by 8px because vertical margins were not included.

  EventsDialog now uses font-sized compact fields, 8px top padding and
  single-line horizontal scrolling for long embedded input. Modal fields
  retain their normal 56px floor and grow when larger fonts require it.
  EventCard allocates both vertical margins; metadata badges can shrink
  and elide while reserving the fixed Remove target inside the card.
  `python3 scripts/test-calendar-editor-layout-runtime.py`: **137 checks
  PASS, exit 0**, using actual QML in an unfocused private Niri session,
  240/292px panes, 100/150/200 percent fonts, light/dark, empty placeholders,
  long input, clicks at the top/middle/bottom of Remove, keyboard title
  entry and isolated Add/Edit/Remove in-memory state. The subsequent
  CAL-I01 extension covers real disk persistence with 149 checks. Existing Calendar/Weather
  composition contract PASS; obsolete 36px spelling assertion retired.
  Owner files, clipboard and preferences were untouched. Installed desktop
  still has the earlier source; visual/physical owner retest and exact-SHA
  canonical qualification are pending. Keep this item open until Calendar
  Popup Add/Edit/Save/Remove is accepted on the owner desktop.

- [ ] **Weather popup overlap / Calendar-Weather Pyramid flicker — owner update 2026-10-10:**
  New case: rapidly hover between Calendar Popup and Weather Popup; Weather
  intermittently flashes. PyramidPopup coordination is a *suspected*, not
  established, cause. Inspect actual `AbyssPyramidCoordinator.qml` scheduling,
  source/body hover leases, z-order and native open/retract transitions;
  preserve Calendar and Weather functionality. Acceptance includes fast
  back-and-forth hover without flashes on relevant edges, exact-SHA Niri
  evidence and owner retest. Earlier case still OPEN: reproduce the video at
  `/home/llocphann/Videos/2026-10-10_00.19.58.mp4`, especially rapid Clock/other
  module → Weather transfer. The actual four-edge fixture passed 1,148 geometry
  samples at `0ea54cc09`; it did not change Weather production code or prove
  owner visual acceptance. Verify first hover, repeated reversal, Orbit/Details
  clipping, exit and reopen with the actual installed source identity.

- [ ] **Orbital Weather light-mode text:** hourly times/labels must use readable
  theme foreground colors. Qualify light and dark mode with the owner's image
  `/tmp/codex-clipboard-f953ac4b-1666-4bb5-8c16-b22920b1ee93.png`; remove the
  redundant hover tooltip instead of repeating the wheel's information.

- [ ] **Hover popups sometimes require clicks or stay open:** qualify cold
  boot and ordinary hover independently of Edit Layout and Waffle → Abyss
  remount. Verify every affected module, source-to-body transfer, reentry and
  final leave. Connected bridge input is repaired at `be8902259`; cold hover and
  delayed anchor callbacks have focused evidence in the archived ledger.
  Preserve click-only actions, keyboard focus and empty-space click-through.

- [ ] **Wi-Fi/Bluetooth popup text missing:** the loading blocker is fixed at
  `134b0115a`, and visible-title fixtures pass through `2d31f06b9`. Confirm actual
  owner populated/empty/loading/disabled states and actions. System Tray owns
  these icons; do not reintroduce standalone Wi-Fi/Bluetooth edge modules.

- [ ] **Music fails to play:** source `8b2ed6f0a` fixes queue/transport ordering,
  repeated payload stalls and failed-write retry. Real QML passes Python/Rust
  protocol fixtures; private real MPD plays synthetic WAV/FLAC and recovers from
  decoder failure using a null output. Confirm audible owner PipeWire playback,
  Stop → long idle → Play, queue/delete, Shuffle/Repeat and actual problematic
  FLAC files. Do not alter owner music bytes, queue or output routing as a test.

- [ ] **Volume +/- and DSP crackle — owner update 2026-10-10:**
  Intermittent audible distortion occurs when an EQ DSP-bearing Popup opens
  during active media playback. The suggested cause (preset automatically
  reapplied on each Popup open/close) remains an UNVERIFIED hypothesis.
  Qualify existing relative-volume queue, default/output routing and repeated
  keypresses. Observe DSP/EasyEffects preset writes, lifecycle subscriptions,
  analyzer restarts and output changes before attributing causality.
  Verify that selecting non-flat EQ and repeatedly opening/closing EQ Popups,
  Sidebar and Dashboard does not resend the preset, disrupt playback or crackle.
  CAVA warm/lifecycle fixtures are bounded source evidence; real audio, device
  and owner acceptance remain OPEN. Avoid changing owner presets during probes.

- [ ] **Edit Widgets / Dashboard Layout offset:** verify the connected toolbar
  stays outside the workspace with real widget dimensions. Exercise desktop
  and Dashboard/Overview editors, all/hidden widgets, occupied moves/resizes,
  packed restores, small viewport, Add, Cancel/Undo/Reset and save/reopen.
  Keep a finite workspace, readable minimums and unaffected neighboring cards.
  Owner reference: `/tmp/codex-clipboard-e908c001-f054-442e-a2bf-73cd2e70cd64.png`.

- [ ] **Modules cannot reach corners / IPC editing joins:** verify corner
  placement and edge clearance with modules, IPC previews and nearby surfaces.
  Keep the preview open despite normal OSD timeout; check Cancel/Done and
  per-output persistence. Source fixes do not replace physical input acceptance.

- [ ] **Clipboard and pinned Notes/Timers:** confirm copied images render
  correctly after refresh/reopen; Clipboard History must not toggle or flicker
  Dashboard whether it was initially open or closed. Verify Notes/Timers pin,
  add/remove and editor ownership across outputs. Native image/pin fixtures
  pass; owner's interactive acceptance remains distinct.

- [ ] **Wallpaper sometimes stays unchanged on desktop while Overview updates — Liquid/iNiR Melt transition failure, owner update 2026-10-11:**
  [Owner: Alis dev; bug/high-impact wallpaper correctness] Selecting another
  image can update the **Overview preview** without changing the **actual
  desktop wallpaper**, especially when the configured iNiR Melt transition
  cannot complete. Earlier wallpaper ownership and live color-preview source
  repairs exist, but the owner reports that the end-to-end apply remains
  unreliable. Treat this as a fresh reproduction/acceptance gate, not as proof
  of a specific shader fault. **The selected valid wallpaper MUST apply even
  if any transition fails, never begins, times out, is disabled or has an
  unsupported shader/backend.** Transition animation is optional; successful
  image selection and desktop display are mandatory. Preserve the last
  successfully displayed image until the new source is actually Image.Ready;
  do not commit a broken/empty texture or claim success for an invalid file.

  Investigate the complete source chain from wallpaper picker
  (`WallpaperSelectorContent.qml`, `WallpaperLauncherContent.qml`,
  `Wallpapers.applySelectionTarget` / `apply`, `WallpaperListener`)
  through display ownership/engine (`awww` vs internal Quickshell
  `WallpaperCrossfader.qml`) and multi-output/Overview preview state.
  `WallpaperCrossfader.qml` currently recognizes `inirMelt`, gates its
  experimental shader on `INIR_EXPERIMENTAL_MELT=1`, normalizes it to
  `crossfade` in non-shader use and has a 1500ms shader-wait fallback.
  Those are **source observations, NOT native proof that fallback succeeds**.
  Capture exact source/installed SHA, actual renderer/ShaderEffect status,
  `Image.status`, `displayedSource/pendingSource`, `frameSwapped`/
  timeout, compositor output and wallpaper-backend receipts before changing
  any mechanism. Separate compile failure, source load error, an invisible
  window, stale completion, queued rapid selections, IPC/backend failure,
  canceled preview and divergent Overview source; no assumed root cause.

  Add bounded, deterministic failure-injection tests for shader not compiled,
  software backend, hidden/no frames, prime timeout, Image.Error, fallback
  completion, rapid A→B→C changes, repeated selection, preview cancel,
  image/video, different outputs, theme update and failed backend switch.
  Real Niri/Quickshell acceptance requires chosen **valid** wallpaper B
  visibly on the physical desktop/target monitor (not only Overview/palette)
  with Liquid enabled, unavailable and OFF, preserving current on failure,
  normal wallpaper/Popup input and no permanently busy transition. If the
  effect cannot render, complete the image switch with a safe fade/instant
  fallback and accurately surface the transition limitation. Linked
  transition rename/polish: [WALL-R01](REWORK_OPTIMIZATION.md).
  State: OPEN; owner regression reported, actual native failure and repair
  NOT YET verified.

- [ ] **Cheatsheet close opens Update popup:** qualify the repaired independent
  close/visibility ownership through first and repeated slide-out. No unrelated
  Update popup should appear or dismiss over it.

- [ ] **Notification timeout and retained history:** verify expiry, hover pause,
  resume and history refresh without resetting an existing timeout or pin.
  Preserve freely positioned notifications; retire obsolete Anchor controls.
  Niri reload success was subsequently retired and must remain silent; failures
  stay actionable. Verify Notification/Activity dimensions and existing Notes/
  To-do/Timers/Activities routes without duplicating their backends.

- [ ] **Hadalird helper/package state and Polkit focus:** extraction is
  source/package-qualified; owner reported helper status ready. Verify compact
  Settings status, restart/refresh, explicit install/reinstall/update/rollback/
  remove and retained data. Verify Polkit above embedded/native/Waffle Settings,
  success/cancel/focus restore and double authorization on a first install.
  Missing receipt must reconcile state, not retry a possibly successful install.
  No implicit privileged install or TLP/Thinkfan/charge-policy change.

- [ ] **CAP-I01 — Intermittent Quickshell restart during screenshot — owner report 2026-10-11:**
  [Owner: Alis dev; priority: startup/crash investigation] The shell
  sometimes appears to **reset/reinitialize when taking a screenshot**;
  the owner reports a crash after completing a screenshot hotkey. A real
  SIGSEGV/restart on 2026-10-11 is now CONFIRMED, while its correlation
  with a capture and its faulting code remain UNKNOWN. Preserve
  screenshots and normal shell state: screenshot/region-selection capture
  must never restart Quickshell, clear unrelated UI/session state or
  trigger an unrequested Settings/Panel reload. Distinguish (1) actual
  Quickshell crash or signal, (2) managed systemd/CLI restart,
  (3) QML source-watch hot reload, (4) compositor or output remount,
  and (5) temporary overlay redraw that resembles a restart.
  Do not blame grim, compositor, clipboard or GPU without receipts.

  **Investigate boundedly before editing:** identify the exact source
  and installed runtime SHAs, shell PID/uptime and user-service unit
  status just before/after an observed failure. Correlate monotonic
  timestamps, `journalctl --user` shell/Niri logs, exit status/signal,
  coredumpctl (if present), kernel OOM/driver hints, restart supervisor
  receipts and QML errors with the corresponding capture action.
  Keep diagnostic output bounded/redacted and do not expose user
  screenshot pixels, clipboard payloads, window names or secrets.
  A PID change alone is not a proved crash; a screenshot completing
  alone is not evidence that the UI did not restart.

  **Source routes to inspect:** `modules/regionSelector/RegionSelector.qml`,
  `RegionSelection.qml`, `RegionSelectorRouter.qml`, `OptionsToolbar.qml`,
  annotation/OCR follow-up, `modules/ii/overlay/recorder/Recorder.qml`,
  `scripts/inir` region screenshot dispatch and restart supervision,
  `scripts/capture-windows.sh` (Niri window preview captures with
  wl-copy/cliphist cleanup), and any relevant screenshot shortcuts.
  Capture helpers, full-screen RegionSelection overlays and
  `Quickshell.execDetached` are possible boundaries to inspect,
  NOT established fault causes. Compare direct system screenshot
  utilities with shell-initiated actions on an authorized test session.

  **Reproduction/acceptance matrix:** region select → save/copy,
  full-output screenshot, screenshot-window/preview, Edit/annotation,
  clipboard after copy, cancel/escape and repeated rapid captures;
  screenshot from hotkey versus Popup, Niri normal/fullscreen,
  all outputs/fractional scales, light/dark, active Settings/Panel,
  Companion enabled/disabled and background Recording where practical.
  Check single and 10–20 bounded consecutive captures, error/timeouts,
  screenshots actually saved/copied correctly, unmodified user files
  and zero unexpected shell PID/uptime discontinuity. Add focused
  tests for failure exits and lifecycle cleanup; native exact-SHA
  reproduction and owner retest are mandatory before closure.
  **Local investigation 2026-10-11:** user-service journal records
  `code=dumped, status=11/SEGV` at 01:07:25 +07 and a managed restart
  at 01:07:30–31. Coredump metadata identifies `/usr/bin/qs -n -p`
  for the installed shell (crashed PID 330432), signal 11/SEGV_MAPERR;
  storage is `none`, so no native stack is available. No capture event
  timestamp/source identity was retained for that crash. The current
  installed manifest is `9dd5120bf`, service started at 13:40:57 +07
  (PID 219020, restart count 0); readback hashes match current source
  for RegionSelection, AnnotationEditor, Cliphist, CliphistImage and
  AbyssPerimeter. This current manifest does NOT establish the code
  loaded by the 01:07 crash.

  Both shortcut routes are configured: Print/Ctrl+Print/Alt+Print use
  native Niri captures, while Super+Shift+S/Ctrl+Shift+S open the shell
  region menu. The owner confirmed “hotkey, crash after capture”; the
  confirmed combination is Super+Shift+S/Ctrl+Shift+S (shell region menu),
  not the native Print route. Private unfocused Niri
  tests on `9dd5120bfb0735fc5dfdf5e157139f0622d66edf` passed 10
  immediate cancels, 10 region Copy operations, three native annotation
  exports and an export/close race. QS exited normally with 13 synthetic
  PNG saves of the expected 160×96 dimensions. The same bounded cycles
  also exited normally with actual AbyssPerimeter and an isolated PNG
  clipboard watcher present (`HOST_CAPTURE_LIFECYCLE_PASS`); image-ready
  state was not separately asserted in that diagnostic. This is bounded lifecycle
  diagnosis, not reproduction of the owner failure or a repair. No user
  clipboard, screenshot pixels, preferences or shell process were changed.
  Metadata: [sanitized diagnostic receipt](../../docs/evidence/abyss-product/20261011-9dd5120bf/screenshot-diagnosis.json).
  **Actual pointer diagnosis and bounded repair 2026-10-11:** composed
  private Abyss host, actual region MouseArea press/move/release and toolbar
  cancel handlers pass 10 Copy / 10 cancel / 3 normal exports. Ten additional
  duplicate-export/close races reproduce a separate data-loss defect: only
  15 of 23 expected PNGs survive at `0a145ce1b`, with invalid QML callback
  context warnings. AnnotationEditor now guards concurrent grabs and defers
  requested close until the accepted grab callback finishes. The same native
  workload saves all 23 expected 160x96 PNGs with zero invalid-context warnings
  and QS exit 0. `scripts/test-screenshot-pointer-runtime.py` retains the
  regression; [receipt](../../docs/evidence/abyss-product/20261011-annotation-export/receipt.json)
  identifies the working source hash and before/after boundary. No SIGSEGV
  was reproduced; this export fix does not establish the owner's crash cause.
  Next: obtain a stack or timestamp-correlated capture failure, then owner
  retest at the installed SHA. State: OPEN; real crash confirmed, capture
  cause UNKNOWN; accepted-export lifecycle repaired with focused evidence.

## Cross-repository correctness and release gates

**Central task intake 2026-10-11:** implementation owners are
[Alis-Companion](https://github.com/llocphann/Alis-Companion) main
(source snapshot 732136ef65bb3c84d9339207210c955759a85b76)
and [Alis-Intergration](https://github.com/llocphann/Alis-Intergration) main
(source snapshot b0c975a7f40bdf531012be326bc728f5c014b696).
These source SHAs identify the import, **not** the installed release or
acceptance. Alis dev holds the ONLY authoritative TODO status; package code,
test scripts and historical receipts remain in each source repository.


- [ ] **AC-I01 — Companion visual G0 oracle still inconclusive (VIS-01):**
  [Owner: Alis-Companion main] Exact-source A/A GPU capture of original
  Aqua/Octo shaders previously ended INCONCLUSIVE_CAPTURE_VARIANCE
  (exit 2), despite equal source/QSB hashes. Earlier warm-up and modified
  fwidth diagnostics are not approved production/lossless fixes.
  Reproduce original shader under real owned Wayland GPU, prove strict
  repeatable A/A, negative-detectable and independent A/B captures with
  PNGs, QSB/renderer SHA and error receipts. Stop if G0 remains red;
  do not authorize E1 or weaken exact RGBA. State: BLOCKED_LOCAL/GPU.
  [Visual source](https://github.com/llocphann/Alis-Companion/blob/732136ef65bb3c84d9339207210c955759a85b76/to-do/cloud-bot/ABYSS_WATER_DROPLET_COMPANION.md).

- [ ] **AC-I02 — Companion joint host tests and physical acceptance (VIS-00):**
  [Owners: Alis-Companion main + Alis dev] Confirm both clean source SHAs,
  installed optional package SHA, compatible Alis host API, manifest and
  default-off preference; run make test with HADALIS_ROOT set to the actual
  Alis checkout, then Alis validator on the tested SHA. Require recorded
  exit codes/PASS/FAIL/SKIP. Verify live Niri/Quickshell chat, actor
  movement, four screen rims, overlay/input, drag, cast transitions,
  portals, sound/theme, lock/suspend/hotplug, DPI scaling, unload,
  cancellation, optional packages absent, no orphan helper process,
  no double actor and preserved preference. Source-only PASS is
  not complete physical owner acceptance. State: OPEN.

- [ ] **AC-I03 — Companion provider and output safety (AI P0):**
  [Owners: Alis-Companion main + Alis dev] Qualify existing shared AI
  provider/session, local GGUF and helper without a second model daemon.
  The selected local-only mode must never silently use cloud; make
  provider/privacy selection visible. Test all text/speech/check-in/
  reminder/error outputs against malformed JSON, prompt injection,
  untrusted quoted-vault data, internal/tool tokens, unauthorized commands
  and fabricated action confirmations. Preserve chat history/paging,
  cancel/retry, mid-answer cast switch, empty/restart state and bounded
  output, real chosen-model privacy and redacted logs. Model reply
  sanitization alone does NOT authorize tool use. State: OPEN;
  host + model + owner acceptance pending.
  [AI source](https://github.com/llocphann/Alis-Companion/blob/732136ef65bb3c84d9339207210c955759a85b76/to-do/cloud-bot/WULL_LOCAL_AI.md).

- [ ] **AI-I01 — Intergration package/host correctness and native release gates:**
  [Owners: Alis-Intergration main + Alis dev] Existing Hadalird manifest
  identifies version 0.2.1, hostApi 1 and optional TLP/Thinkfan/Obsidian
  workers; this repo has no active TODO file to migrate. Prove exact
  package source/host version compatibility, enable/disable/refresh,
  unloaded default-off workers, package-absent and incompatible-release
  behavior, settings lazy imports, no orphan process, no implicit
  privileged helper provisioning, no lost data and no false success.
  Run the integration make test with pinned Alis root plus corresponding
  host/Qt/Niri checks. Keep existing Alis "Hadalird helper/package state
  and Polkit focus" issue as the detailed privileged lifecycle gate.
  State: OPEN; no new runtime defect diagnosed.
  [Manifest](https://github.com/llocphann/Alis-Intergration/blob/b0c975a7f40bdf531012be326bc728f5c014b696/manifest.json).

- [ ] **AI-I02 — Integration TLP, Thinkfan, Obsidian failure-state verification:**
  [Owner: Alis-Intergration main] Test real/restricted battery limits,
  TLP vendor capabilities, charge policy and Radio Device Wizard;
  Thinkfan readings/worker status/Polkit denial and fan-safety lifecycle;
  Obsidian theme, Todo/Tasks and Daily Note backend, Zettelkasten, Quick
  Notes and image attachments with permission, path, conflict and
  byte-safe non-destructive fixture tests. Separate synthetic results
  from user-approved hardware/personal-vault tests. Preserve generic Alis
  Battery/Notes/Todo when optional package is absent; never claim a
  note, setting or privileged action succeeded without a confirmed
  execution receipt. State: OPEN/native and owner acceptance.

## Correctness and release acceptance

- [ ] **Lifecycle/input on the installed candidate:** boot without unavailable
  types/duplicate IDs; cold/warm open, fullscreen enter/exit, lock/unlock,
  suspend/resume, output removal/hotplug and fractional/transformed outputs.
  Keep Overlay input limited to real interactive bodies; no transparent blocker
  or late callback invoking destroyed objects. Native debug Niri stays unfocused
  except for required image evidence and must have dark first-frame backgrounds.
  Verify normal tray/app hover menus, nested menus and newer-menu focus ownership,
  desktop context-menu close/reopen, Quick Notes editor leases, configured hot
  corners and Overview priority. Keep Calendar/Weather responsive at small scales.

- [ ] **Feature/package identity and failure behavior:** exact installed/source
  SHA, relocatable install/update/uninstall, required runtime dependencies and
  optional absence/error recovery. Exercise missing/offline/incompatible optional
  packages, actual selected TLP/Thinkfan/Obsidian behavior after user enablement,
  and Waffle separately. Nix-specific validation remains deferred/non-blocking.

No older canonical FAIL, STOPPED run, missing receipt or consumed G0 result is
upgraded to PASS by this consolidation. Their original boundaries are archived.
