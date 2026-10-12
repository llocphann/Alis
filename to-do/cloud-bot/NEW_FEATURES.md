# New features

**Active checkpoint — 2026-10-12:** cloud/local are synchronized through
`3ea5d892d`; strict-lossless R03 cache source `458ad7197` and qualification
`484427acf` are pushed. R03 remains OPEN: cached wave/placement outputs are
exactly qualified, but dense reordering and owner smoothness remain unresolved.
[Cache evidence and retained failures](../../docs/evidence/abyss-product/20261012-r03-mass-placement-cache/README.md).
Frozen full clean-clone `484427acf` is RUNNING; no final PASS is claimed.
Earlier full `7e31685bc` FAIL 373/7/1 and scoped `cfc852bee` 16 PASS/1 FAIL
remain historical independent receipts. G0 remains offline-only.

**Latest direct priority:** finish the current source/qualification milestone,
then **ABYSS-R08** immediately. Resume the remaining explicit queue afterwards;
R03 and POP-I01 stay open independently. ABYSS-F02 modifier-only selection is
already implemented in cowork `77bba9432` with native fixture `d982c7d02`;
use Ctrl/Shift + click and do not recreate a toolbar mode toggle.
Only exact five-hour remaining below 3% triggers checkpoint/push and the
existing single reset+3minute continuation; weekly limits never trigger it.
Preserve cowork work, owner preferences and independent acceptance gates.

Work first under the [shared priority effective 2026-10-12](README.md), with
related [Issues/bugs](ISSUES.md) and [Rework/optimization](REWORK_OPTIMIZATION.md)
handled alongside the selected feature in the same single-agent context.
Source-implemented features below still need their stated delivery/owner gates;
do not reimplement them solely because a checkbox is open.

**Latest explicit owner priority — 2026-10-12:** finish the current Abyss
qualification, then **POP-I01 → DASH-F01 → ABYSS-R08 → ABYSS-F02 →
NOTES-R01 → ABYSS-R09 → CAL-R01 → NOTES-F01 → DASH-R03**, continuing
without the former stop-after-group rule. Their category identities remain
separate; this explicit sequence overrides the general feature-first queue.
ABYSS-F02 now requires **Ctrl/Shift + click only**, with no toolbar mode toggle;
its prior toggle-based milestone stays historical and the refinement is OPEN.

**Immediate owner priority — updated 2026-10-12:** qualify completed feature source milestones after
DASH-F01/F02 source milestones. Weekly Planner `f62f24361`, tab reorder
`f94de0535` and Events durable acknowledgement prerequisite `ccd750167`
have separate focused evidence; committed canonical and owner gates stay open.
An earlier canonical was stopped at five-hour2%, with four partial failures;
[its frozen receipt](../../docs/evidence/abyss-product/20261012-f94de0535-stopped/README.md)
preserves the consumed result. Single reset+3minute continuation fired04:29ICT. Frozen multi-selection
canonical593368c15 was STOPPED at five-hour1%, with318 completed checks:
311PASS/7FAIL/0SKIP and no full summary. New Dashboard0becc72ab fixes below
are qualified only by their pinned focused bytes until a newer full run. No historical task backfill,
owner preference, AI/vault consent or installed Companion change is authorized
by the continuation. AGENDA-F01 now has source/focused linking evidence below;
Per-module locks `a450be887` are source/focused PASS; multi-selection source/focused PASS now follows below.
Full qualification/owner gates
remain open across these feature milestones. Frozen Agenda source0465 completed
FAIL359/7/1; [raw exact receipt](../../docs/evidence/abyss-product/20261012-0465ffc5a/README.md)
keeps that result independent of lock and multi-selection work.
Historical delivery sequence was **DASH-F01 → DASH-F02 → AGENDA-F01 →
ABYSS-F01 → Screen Edge multi-selection**; the latest explicit sequence above
now controls further work. Carry out their related data/input repairs and
Rework/optimization alongside delivery, preserving remaining canonical and
desktop acceptance gates. Do not resume the former Issues → Rework → Features
order or close unverified Issues because their source is implemented.


**2026-10-12 09:34 ICT owner continuation:** the five-hour window is now
0%used, next reset14:33:24ICT. The consumed stop checkpoint below remains
historical; no additional timer was created before this human continuation.
Composed Dashboard/Overview dimension/slide capture now focusedPASS16cases/
211motion samples/48PNG with previous focus restored and unchanged oracles;
[qualification](../../docs/evidence/abyss-product/20261012-dashboard-field-capture/README.md).
Continue related remaining canonical failures, then fresh frozen full run;
source/focused and owner/installed gates remain separate.

**2026-10-12 06:53 ICT quota checkpoint:** stop all product/test work because
only the exact five-hour window remains1%; weekly62%used is not a stop trigger.
Reset09:29:29ICT; continue once at09:32:29ICT. Source cohorts now implemented:
Weekly Plannerf62f24361; tab reorderf94de0535; Agenda host0465ffc5a /
optional Integration4d0aa3f; module locksa450be887; multi-selection593368c15;
Dashboard canvas/Music checkbox focused qualification0becc72ab. Preserve their
source/focused evidence; do not reimplement completed milestones. Latest full
attempt [STOPPED raw receipt](../../docs/evidence/abyss-product/20261012-593368c15-stopped/README.md)
is318completed311PASS/7FAIL/0SKIP, not full PASS. Ancestor0465 completeFAIL
359/7/1 remains immutable. Next: qualify feature cohort with related remaining
Dashboard motion/toolbar, Recording, Settings, hover and IPC repairs; freeze a
new canonical from actual fresh committed SHA after repairs. All stated
owner/installed/material/multi-output and Companion gates remain OPEN.


- [ ] **PERF-F01 — Alis Quickshell deep performance profiler — owner request 2026-10-11:**
  Add an opt-in, bounded debug suite to trace actual Alis resource costs:
  CPU, GPU, RAM/PSS/RSS, frame pacing and QML/JavaScript/render hotspots,
  with per-module/per-popup attribution ONLY where instrumentation or
  controlled evidence permits. Existing inir doctor --perf, ResourceUsage,
  MemoryPressureService and Abyss frame/hover collector are starting points,
  not full component attribution. Distinguish **direct measurement**,
  **instrumented span**, **controlled A/B estimate**, **correlation** and
  **unavailable**; never invent exact GPU %, VRAM, RAM or CPU numbers for
  individual QML objects from a process-wide or system-wide counter.
  **Work packages, all OPEN:**
  - [ ] **P1 — Architecture and observability map:** inventory shell.qml,
    Quickshell windows and services, Qt GUI/render/audio threads, native
    helper PIDs and Niri compositor, then map Abyss/Waffle, Screen Edges,
    Panel, Popup, Dashboard, Wallpaper, Media/EQ, Weather, Notifications,
    Recording, AI and shared QML loaders. Document attribution limitations
    per resource, GPU vendor, compositor and permission level.
  - [ ] **P2 — User-initiated trace command:** expose alis debug perf
    start/status/stop/report (or equivalent under alis doctor --perf).
    Support fixed-duration sessions, cancel, caps on sample rate/memory/
    output size, machine-readable exit errors, exact source SHA and
    running qs -p config identity. Remain compatible with inir during
    brand migration. Reject stale installs, wrong instance, absent IPC
    handlers, missing receipts and empty traces instead of false success.
  - [ ] **P3 — CPU and thread scheduler timeline:** collect timestamped
    /proc and cgroup CPU times for Quickshell PID, main/render/media
    threads, child Rust/Python helpers and Niri independently. Normalize
    multicore percentages, sampler interval, PID restarts and power
    profile. Optional perf/flamegraph capture only with explicit
    authorization and hardware/kernel support, never implicit root.
  - [ ] **P4 — Memory and object lifetime:** track RSS/PSS/USS if available,
    JavaScript/GC and JSGCHeap/memfd accumulation, Loader/Window lifetime,
    image/video/texture caches and alloc/free deltas across repeat
    open/close cycles. Mark shared caches and unattributable process
    memory rather than assigning it arbitrarily to a single module.
  - [ ] **P5 — GPU and VRAM capabilities:** inspect rendering backend/
    Qt Quick RHI, driver/renderer and safe DRM fdinfo or available
    vendor engine/memory counters (NVIDIA/AMD/Intel). Separate shell,
    compositor and global GPU usage. Capture QSG/render-phase timing where
    possible. Report unsupported counters as unknown, not zero;
    global GPU busy percentage CANNOT prove one Popup's GPU cost.
  - [ ] **P6 — QML/JS lifecycle probes:** opt-in instrumented spans for
    expensive function handlers, models/bindings where feasible,
    Loader incubation, object create/destroy, timer wakeups, shaders,
    images/video decode, popup geometry and connection/hover transitions.
    Key events to module, window and output, with duration and scope;
    idle logging overhead should be nearly zero when disabled.
  - [ ] **P7 — Frame-time and input correlation:** measure per-window
    QQuickWindow frameSwapped intervals and, where available, Qt GUI/
    render phases, alongside hover/click/Popup/Recording/animation
    events. Compute p50/p95/p99/max, count and long-frame episodes.
    FrameSwapped wall-clock callbacks are NOT compositor presentation
    timestamps. Do not poll IPC while measuring the same short frame.
  - [ ] **P8 — Component cost ranking with uncertainty:** correlate
    measured thread CPU, event spans, optional stack samples and
    deliberately isolated on/off A/B traces. Report confidence, units
    and method per component, and top offenders by verified duration,
    allocation changes or associated frame spikes. Preserve GPU shared
    passes, caching and inclusive/exclusive span limitations. Use
    unavailable when reliable module attribution cannot be made.
  - [ ] **P9 — Reproducible workload scenarios:** baseline cold boot and
    stable idle, then Panel/Screen Edge hover, multi-popup Pyramid
    transitions, Notifications, Recording start/stop, Calendar/Weather,
    Dashboard/Music/EQ, wallpaper/video, fullscreen, multi-output,
    fractional scaling and low-power state. Record exact source SHA,
    system/Qt/Quickshell/Niri version, GPU driver, monitor and
    profile settings and capture overhead. Compare matched baselines.
  - [ ] **P10 — Reports and optional debug UI:** export compact JSON,
    optionally CSV/HTML, chronological hot spans, CPU thread timeline,
    RAM growth, GPU support level, stutter episodes and before/after
    comparisons. An optional developer view may follow only once
    collectors are correct; no always-on debug animation or timer.
  - [ ] **P11 — Privacy/security and safety budget:** disabled by default;
    no upload, unsolicited persistent logging or sudo. Redact
    notifications, credentials, window titles, note text, clipboard,
    file paths, network names and access tokens. Bound runtime/buffers/
    disk size; recover cleanly from cancel/crash/restart and quantify
    profiler perturbation. Never modify user content, graphics quality
    or physical input to gather metrics.
  - [ ] **P12 — Correctness and native validation:** test counter
    wraparound, timebase, nested spans, PID changes, absent GPU sensors,
    permission failures, missing/mismatched IPC, output switches and
    privacy redaction. Verify native Quickshell/Qt/Niri timings and
    on/off overhead on the same deployed SHA. A fixture pass cannot
    prove true per-module GPU costs or on-screen frame smoothness.
  - [ ] **P13 — Link performance research and existing bugs:** define
    trace schema and limitations, attach measured results to the
    canonical strict-lossless GPU/RAM/CPU audit and existing Abyss
    stutter/Notification/Recording investigations. Do not duplicate
    their bug tasks, replay consumed receipts or claim improvements
    without matched before/after evidence.

  **State:** NEW/READY for design and source audit, NOT IMPLEMENTED.
  Alis CLI/identity dependency is tracked in Rework/optimization.
  No revived Automation/MegaQML service is required.
  **Owner priority override — 2026-10-12 (feature #1): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [x] **ABYSS-F01 — Per-module Screen Edge position lock — owner request 2026-10-11:**
  [Owner: Alis dev; NEW feature] In **Edit Abyss Layout**, allow the
  user to independently **Lock position / Unlock position** for
  each Screen Edge module. Show a compact lock control near the
  selected module's positioning/size actions and an unmistakable
  lock glyph/state on its editor handle; support pointer and
  accessible keyboard interaction. Default all existing modules
  to UNLOCKED for backward compatibility. A locked module stays
  in the user-approved position and edge: dragging, snapping,
  inserting, deleting, resizing or reordering **other** modules
  may NOT silently move it, change its alignment/edge or reorder
  its anchored slot. Moving a locked module itself requires
  explicit unlock first; normal viewing and Popup actions remain
  usable and unchanged.

  **Collision semantics:** treat locked records as immovable
  obstacles/reservations in the production geometry and snap
  solver, **not only disabled drag handles**. Move or compress
  unlocked items within valid capacity while preserving their
  relative order when possible. If the requested new position
  cannot fit (including all-locked/full edges), clamp/reject
  that move and give clear non-destructive feedback; never push
  or overlap a locked module, clip it or silently unlock it.
  If a global resize, resolution/hotplug, font scale or changed
  edge width makes an old locked layout mathematically infeasible,
  define deterministic migration/fallback and surface the
  conflict to the user before persisting changes. Avoid
  claiming absolute physical-pixel stability across resolutions:
  document normalized vs per-output anchoring and handle outputs
  with different available geometry explicitly.

  **Persistence/source:** extend `normalize`, `move`, `snapMove`,
  `geometry`, `resolve`, `optionsForOutput`/`saveProfile` in
  `modules/abyss/looks/AbyssLayout.js` as appropriate; save a
  stable per-ID lock flag (and any genuinely required anchor)
  with the module's global or output-only placement. Update
  `modules/abyss/AbyssEdgeEditor.qml` draft/handle, selection,
  save/cancel/reset and per-output override behavior. Locking
  is **Edit-layout placement protection**, not a new lock on
  normal Popup hover/click, config synchronization or the
  companion actor. Existing user data, hidden/disabled modules,
  join-corner decorations and custom size inheritance survive.

  **Related features:** pending multi-selection of Screen Edge
  modules must visibly identify locked selections and skip or
  explicitly reject batch moves/resize for them, never silently
  modify a mixed group; normal undo/cancel/Done must be exact.
  Coordinate with `ABYSS-R03` movement smoothness in
  [Rework](REWORK_OPTIMIZATION.md) and existing corner/snap
  behaviors. No new second layout engine or background agent.

  **Acceptance:** unit/property/real-QML regression tests covering
  A locked / B dragged into A; insert or delete beside A;
  move A attempt; unlock A; multiple locked slots, different
  alignments, edge crossing, small viewport/over-capacity,
  output hotplug/scaling, custom widths/sizes, hidden/zero-size
  modules, multi-select, save/undo/cancel/reset and relaunch.
  Verify locked layout coordinates remain unchanged wherever
  feasible, unmovable conflicts have visible feedback,
  neighbors/Popups stay interactive, and saved lock state
  survives restart under both default and per-output layouts.
  Require native Niri/Quickshell pointer, visual and owner
  acceptance. State: SOURCE IMPLEMENTED / focused PASS — 2026-10-12.
  Normalized center/compression anchors are captured from the approved visible
  slot; default existing records remain unlocked. Locked reservations stay
  fixed through feasible neighbor move/snap/insert/delete/size edits; a bounded
  ordered interval solver fits unlocked groups. Full/infeasible moves are
  rejected; output/font/width conflicts expose deterministic ordinary packing
  without changing stored anchors/flags and block Done until repaired.
  Handle glyph, Lock/Unlock control, keyboard L/Enter/Space, bounded64-step Undo,
  Cancel/Reset and global/output-only persistence use the existing editor.
  Concurrent changes to the same global/output source refuse Done, including
  after Undo Reset; other output profiles survive. Related Qt map serialization
  and compact-grid clipping repairs are tracked in ABYSS-I02.
  Focused PASS7044 pure/property checks (192 pre-feature no-lock geometry/input
  comparisons), actual QV4/private-native62checks/26foreground frames and
  independent JSON/process restart, existing four-edge/small-output editor
  oracle, four editor contracts and parser. [Pinned working-source evidence](../../docs/evidence/abyss-product/20261012-module-locks/README.md).
  Full exact-SHA canonical, installed/owner normal-popup and physical pointer,
  actual multi-output/hotplug and full Abyss material acceptance remain OPEN.
  Continue Screen Edge multi-selection with explicit locked-batch guards.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [x] **ABYSS-F02 — Edit Abyss Layout Screen Edge module multi-selection — owner request 2026-10-10:**
  Support modifier-based multiple selection for Screen Edge modules while
  **Edit Abyss Layout** is active.
  **Owner correction 2026-10-12 — OPEN follow-up:** remove the toolbar
  selection-mode toggle. Normal click selects a module; Ctrl + click and
  Shift + click build/toggle coherent multiple selections. Keep accessible
  keyboard selection, batch/drag guards, visual selection and Undo/Cancel/Save;
  transient selection must not persist as a setting. Prior implementation
  and evidence below are retained, not proof this new interaction is delivered.
  **Modifier-input source milestone (2026-10-12):** the selection-mode
  checkbox is removed. Normal click replaces the selected group, Ctrl-click
  toggles a module, Shift-click selects the contiguous visual-order range
  from its stable anchor, and Ctrl+Shift extends the current set. Ctrl+Space
  and Shift+Space on focused handles mirror pointer semantics; Ctrl+A
  selects all in the active editor without an activation mode. Multi-group
  drag and locked/transactional batch guards remain tied to the actual
  selection size, not a user setting. The shared pure selection helper
  and Node policy regression are added; the existing native fixture now
  uses actual Ctrl-click instead of the removed checkbox.
  **Not yet qualified:** canonical exact-SHA regression, actual
  Niri/Quickshell Ctrl/Shift pointer and keyboard gesture, toolbar/hit
  region behavior at fractional/vertical edges, and owner acceptance.
  **Drag regression discovered and repaired (2026-10-12):** An
  ordinary mouse-down on an already selected handle was collapsing the
  multi-selection before `checkedGroupMove` began. Keep selected groups
  unchanged through a real drag; defer single-target collapse until mouse
  release without movement. Prevent pointer jitter from becoming an
  accidental drag with a bounded motion threshold. Repaired the native
  group drag fixture with explicit selection-retention and click-collapse
  assertions, plus pure `AbyssSelection.js` decision tests. This is a
  source milestone; actual private Niri gesture/owner validation remains
  outstanding.
  **Hoàn thành (bot báo xong) — Owner chưa verified (2026-10-12):**
  The full requested source implementation, including the later owner
  Ctrl/Shift-click correction and removal of the mode toggle, is delivered
  as Alis dev `77bba943292b039f8d8d48ede0617ae024c4d2b0`, with the
  additional native modifier gesture fixture update at
  `d982c7d0217928acf07052eb2d35aae2618fc262`. Seven focused pure
  JavaScript cases were executed directly on the actual helper blob
  `0c1697a0a559694f25b28f52413a2e66d6e4cb0c`, PASS.
  The owner has NOT verified pointer/keyboard feel, and the actual Niri
  fixture/canonical exact-SHA validator were NOT RUN in this connector
  environment. Preserve historical source, native and verification
  evidence above; outstanding owner/installed/native gates remain separate.
  Show which modules are selected, support
  add/remove/clear selection and coherent subsequent edits when several targets
  are selected. Keep normal non-edit behavior intact; define guarded batch
  actions instead of silently changing unrelated modules. Test horizontal and
  vertical edges, cross-edge/per-output selection, drag/snapping and Cancel/
  Undo/Done/save semantics; coordinate with compact toolbar redesign in
  [Rework](REWORK_OPTIMIZATION.md). State: SOURCE IMPLEMENTED / focused PASS —
  2026-10-12. Explicit editor-only selection set/primary target, visible lock/
  selection state, pointer add/Ctrl-toggle, Space/Ctrl+A and Clear. Exact-target
  batch lock/unlock/enable/disable/remove/custom-size/resize/alignment reject
  locked/stale/infeasible placement edits atomically. Same-Edge groups preserve
  gaps/order through drag/snapping and cross-Edge destination orientation;
  mixed-Edge sets have batch controls with explicit group-drag rejection.
  Source geometry snapshots and bounded measurement reflow repair the new
  cross-Edge gap defect (ABYSS-I03); Reset/Cancel invalidate queued moves.
  Undo preserves draft/selection; global/output-only Save preserves other
  profiles and rejects concurrent source changes. No selection setting is saved.
  Pure1588 and lock regression7044 PASS; actual QV4/private-native55checks,
  2processes/13foreground captures, actual JSON reads and restart PASS.
  [Pinned source/raw evidence](../../docs/evidence/abyss-product/20261012-multi-selection/README.md).
  Full committed-SHA canonical, installed/owner physical pointer and normal
  Popups, full Abyss material and actual multi-output/hotplug remain OPEN.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.


- [x] **DASH-F03 — Checkbox to show/hide Music tab scrollbars in Dashboard Settings — owner request 2026-10-11:**
  [Owner: Alis dev; New Feature] Add exactly **one independent
  checkbox** in **Settings → Dashboard → Music**, such as
  **"Show Music scrollbars"**, backed by a persistent Boolean
  `dashboard.music.showScrollbars` with a backwards-compatible
  default of **ON**. It changes only the visual presentation of
  scrollbars in the **Dashboard Music tab**, including all its
  scrollable subviews: Genre/Folders/Playlist/Results/Queue/
  Lyrics vertical tracks and the horizontal multi-column Music
  browser scrollbar. Do not affect Sidebar Music, general
  Dashboard, Calendar, Weekly Planner or unrelated app lists.
  Apply changes live without needing to reopen Dashboard;
  ensure theme-aware style and contrast when visible.

  **Source starting points:**
  `modules/settings/DashboardMusicSettings.qml` owns
  the Music enable switch and the new single scrollbar preference;
  `modules/dashboard/DashboardMusic.qml` declares a shared
  `MusicScrollBar: ScrollBar` (`ScrollBar.AsNeeded`) used by
  several ListViews plus a separate
  `ScrollBar.horizontal` on `musicColumnsViewport`.
  Introduce the persistent setting through the repo's validated
  config default/schema/migration path (`defaults/config.json`
  and related tests), update both scrollbar owners and avoid
  duplicating options in multiple Settings pages.

  **Critical semantics:** Unchecked must hide scrollbar chrome
  only, NOT disable wheel/touchpad scrolling, touch/flick,
  drag-to-scroll of content, keyboard Home/End/PageUp/PageDown,
  programmatic position, nested Music navigation or normal
  cursor/focus. It is acceptable that the draggable scrollbar
  thumb itself is unavailable while hidden; the content remains
  navigable by other supported inputs. A checkbox flip may not
  resize/clobber list contents, lose scroll offset, restart music
  playback or reload/swap playlist/queue. When checked, preserve
  existing overflow-only thumb visibility; do not force bars
  onto lists with no overflow. In particular coordinate with
  **DASH-R02** horizontal-only page navigation so hiding
  scrollbar never causes vertical wheel to switch tabs, and
  with the existing [Music scroll correctness issue](ISSUES.md).

  **Acceptance:** checkbox ON/OFF live and persisted after
  Settings close/reopen and shell restart; all six Music lists
  and horizontal viewport with empty/short/overflow content;
  hidden scrollbar plus successful wheel/touchpad/keyboard
  scrolling and queue operations; visible normal thumb
  drag/hover/overflow; no nested gesture interception or
  unexpected page switch, layout width jump, clipping or
  playback interruption. Test small/large/fractional monitors,
  dark/light, disabled Music and optionally unloaded Music
  page, migration from old config (default ON), source QML
  assertions and real Niri/Quickshell owner visual review.
  **Cloud source milestone (2026-10-12):** one persistent
  `dashboard.music.showScrollbars` flag (default ON), one Dashboard
  Music Settings checkbox, and a single policy bound to the existing
  six vertical and one horizontal scrollbar. `ScrollBar.AlwaysOff`
  hides visual chrome only; Flickable and underlying event routing
  are untouched. Expanded `test-dashboard-music-scroll-runtime.py`
  for OFF/ON toggling and actual vertical-wheel navigation.
  **2026-10-12 focused qualification:** actual QV4/private-Niri
  2processes/181checks/49rendered frames PASS; exactly one Settings checkbox
  clicked OFF, close/reopen, FileView write acknowledgement, independent
  JSON readback and actual second-process saved-OFF restart. Six-list
  visible thumb/wheel/keyboard and hidden vertical/horizontal navigation
  preserve allocation/offset/selection/transport and page. Default ON,
  unallocated/disabled Music, short/empty six-list and measured1300px
  horizontal no-overflow are covered. Empty-list acceptance uncovered
  related DASH-I08 custom-thumb overflow and DASH-I10 Queue disposal
  TypeError, both fixed forward with retained raw failures.
  [Pinned source/raw evidence](../../docs/evidence/abyss-product/20261012-music-scrollbar/README.md).
  State: SOURCE/FOCUSED PASS; source-pinned full canonical, installed/owner
  layout/touchpad/flick, dark/light/fractional/multi-output and actual audio
  playback remain OPEN. Fixture transport parity is not actual MPD/audio.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [ ] **DASH-F01 — Weekly Planner: new Dashboard tab for Agenda / Events / Todo / Quick Notes — owner request 2026-10-11:**
  [Owner: Alis dev; New Feature] Add a full **Weekly Planner** Dashboard
  page inspired by the owner's first screenshot (Obsidian Day Planner-like
  week-at-a-glance: 7 dated day columns and vertical hourly timeline).
  This is a visual/concept reference, NOT permission to copy plugin code.
  Show prev/next week, Today, current day/time line, all-day section,
  time-scaled events with overlap handling, completed/pending Todo and
  relevant Quick Notes links/preview. Localized weekdays, calendar
  week-start, date rollover/time zones and DST must be correct. Support
  scrolling, small screens/fractional scales and keyboard access without
  clipping the planner's 7-day representation.

  Use ONE existing canonical source per domain: `services/Events.qml`
  for local Agenda/Events, `services/CalendarSync.qml` for read-only
  imported events, `services/Todo.qml` for tasks, `services/Notepad.qml`
  for Quick Notes. Allow click-driven create/edit Agenda, add/toggle Todo,
  open Quick Notes and navigate date/time; only add drag-to-reschedule
  after safe edit/cancel/collision semantics are designed and tested.
  Respect recurring, multi-day and all-day events; mark imported sources
  read-only and keep existing links/attachments and optional Obsidian vault
  permission boundaries. No second data backend, duplicated reminders
  or automatic writes to user notes.

  `modules/dashboard/DashboardContent.qml` currently handles only
  `dashboardPage` 0/1 (Dashboard/Music) and `DashboardHeader.qml`
  emits ordinal page-dot selections. Extend to stable-ID pages:
  Dashboard, Music, Weekly Planner, preserving existing order, active
  tab, page slide, warm/loading semantics and both standalone and
  Abyss/Overview-hosted Dashboard. Coordinate new ordering with
  `DASH-F02`, one-way Agenda task linking with `AGENDA-F01`
  and event persistence gate `CAL-I01`. Do not conflate this new
  **page** with the already existing Agenda/Todo/Calendar canvas widgets.

  Acceptance: week grid with 0/one/overlapping/recurring/all-day events;
  navigation across month/year/DST, today marker, working-hour scroll,
  Todo and note view/edit without duplicates, read-only imports,
  multi-output/theme/reduced-motion, no leaked focus, bounded render
  cost, optional integrations absent and data intact after restart.
  Deterministic date/geometry tests plus owner-approved Niri UI.
  **Owner refinement — 2026-10-12 (Edit Events inline expanded column):**
  Selecting a local event or clicking a time slot in the **Weekly
  Planner Dashboard tab** must open **Edit/Create Events as a real
  expandable column INSIDE the Dashboard**, using the same shared
  expanding side-column layout as Todo and Quick Notes. Do NOT launch
  a separate Sidebar Left/Right, floating popup or full-page modal
  overlay for this Weekly Planner action. Coordinate one pane state
  (events / todo / notes / closed): opening Events expands the
  adjacent column and reflows/shrinks the planner; switching between
  the three preserves expected unsaved-edit/cancel/focus behavior.
  Keep the Events form accessible and scrollable on small screens,
  but **hide visible scrollbar chrome in this Edit Events column**
  without disabling wheel/touchpad/keyboard scrolling or hiding
  field controls. Preserve date/time slot prefill, existing local
  event fields, stable event identity, Save/Cancel/Remove, validation,
  read-only imported events, timezone/DST, source persistence and
  no duplicate write backend. Leave unrelated Dashboard Agenda
  invocation and Calendar Popup editor behavior unchanged.
  **Existing gap:** `modules/dashboard/DashboardWeeklyPlanner.qml`
  currently offers `sideView` Todo/Notes only; `DashboardContent.qml`
  routes `onRequestEventsDialog` through the full-area
  `agendaDialogLoader` / `EventsDialog`. Move the Weekly
  Planner route into the shared in-page expandable column and
  test mode switching, narrow responsive layout, outside click/
  Escape, unsaved edits, no focus leakage, and owner screenshot.
  Coordinate Day/date and All day header material in
  `REWORK_OPTIMIZATION.md` (DASH-R03).
  **State of this follow-up:** NOT IMPLEMENTED / OPEN, despite
  the earlier Weekly Planner grid and shared Todo/Notes native PASS.
  **Incremental source milestone — 2026-10-12 (still OPEN):**
  Weekly Planner now uses the existing embedded `EventsDialog` as an
  expandable column alongside the shared Todo/Notes panel; the normal
  Dashboard Agenda path is unchanged. It preserves slot prefill and
  canonical Events add/update/remove, hides only the inline scrollbar
  chrome while retaining scrolling, and keeps unfinished local Event
  form state loaded when switching temporarily to Todo or Notes.
  Escape and Cancel close the inline editor. A private Niri regression
  fixture now exercises narrow layout, 09:15 prefill, draft retention
  across panel switches and Cancel. It was **NOT RUN** in the connector
  environment. **2026-10-12 additional source repair:** the embedded
  Events form now records the canonical prefilled/loaded fields as a
  baseline. A different event/slot click while that form is dirty
  preserves its draft, returns to Events from Todo/Notes and displays
  a Save/Cancel warning instead of overwriting it. Failed saves
  also show a warning. The private-Niri fixture now covers this
  transition, also **NOT RUN**. Keep source/live-save, focus, outside-click,
  narrow/fractional, installed/restart and owner acceptance gates OPEN.

  **Owner refinement — 2026-10-12 (Quick Notes Markdown parity):**
  The `notes` expanded column inside Weekly Planner must expose
  the same Markdown Reading / Source Editing choice, Ctrl+B/Ctrl+I/
  Ctrl+K shortcuts, stable-ID autosave, and managed attachment preview
  as the shared Edgebar Quick Notes, WITHOUT a duplicate editor or
  data backend. The same requirement applies to the regular Dashboard
  Quick Notes card. Keep the existing Dashboard Source-first default;
  Reading is an explicit user-selectable mode, not a hover-triggered
  focus/mode switch in Dashboard. Owner details and the unified
  native acceptance matrix live in the existing Quick Notes Markdown
  feature below; do not create a second feature or close either gate.
  State: SOURCE IMPLEMENTED / FOCUSED PASS — 2026-10-12, after Todo durability
  and shared Settings task-tab milestones. One bounded weekly projection of canonical
  Events/CalendarSync with actual civil-day boundaries (23/24/25h), overlapping
  and all-day slices, stable-ID third page and shared Todo/Quick Notes panels.
  Imported events remain read-only; view projections do not write recurrences
  or reminders. Pure policy PASS four time zones; actual private-Niri grid
  PASS30 checks/9 captures including 480×410 shared panels and DST. Actual
  three-page Dashboard/Music host, clicked Agenda time prefill, pinned-week
  cold reload and repaired Music Settings typed preference PASS on the private
  basic render loop. Original Queue animation failures and bounded probes are
  retained; this does not qualify the owner's render loop or upgrade earlier
  canonical failures. [Source-byte receipt and all raw evidence](../../docs/evidence/abyss-product/20261012-weekly-planner/README.md).
  Full committed-SHA canonical, installed data/restart, owner visual and
  multi-output/fractional/input acceptance remain OPEN; continue `DASH-F02`.

- [x] **DASH-F02 — Drag-reorder Dashboard tab indicators in Edit Dashboard Layout — owner request 2026-10-11:**
  [Owner: Alis dev; New Feature] In **Edit Dashboard Layout**, drag
  page indicators (dots) to reorder entire Dashboard **tabs/pages**,
  including Dashboard, Music and the new Weekly Planner (DASH-F01).
  Do NOT reorder canvas widget cards or Settings subtabs.
  `DashboardHeader.qml` currently draws ordinal
  `dashboardPageDots` using `pageCount` and index-specific
  labels, while `DashboardContent.qml` and
  `GlobalStates.dashboardPage` assume numeric page IDs;
  replace that fragile ordering with stable page IDs plus a
  versioned saved order and migration for old 0/1 selections.
  Default order preserves current Dashboard→Music, appending Planner;
  disabled Music/hidden pages must not erase persisted choices.

  Show a draggable affordance, insertion preview and pointer ghost
  only in edit mode, with drag threshold, Escape/cancel, focus and
  keyboard alternative to change order. Changing indicator order
  must update page navigation, content order, slide direction,
  wheel/touchpad, tooltips, active indicator and accessibility
  consistently; never just move the decorative dots.
  Share the page-order model with any Settings-hosted Dashboard
  editor; save only on Done, allow Undo/Cancel/Reset and persist
  across restart. Avoid writing Config on every pointer movement.
  Preserve card editing, Dashboard Music scroll, agenda dialogs,
  long press/click, normal non-edit selection and all Abyss edges.

  Acceptance: reorder three tabs both directions, repeat/reverse
  and cancelled drags, current tab identity, disabled Music, legacy
  two-page config, unknown/future page IDs, Reset/Undo/Done,
  close/reopen/restart, touchpad/keyboard/fractional DPI; no
  duplicated/missing tabs, wrong content or overlay input. Add
  source and real Niri pointer regression tests.
  State: SOURCE IMPLEMENTED / FOCUSED PASS — 2026-10-12, after Weekly Planner.
  Visible-slot stable-ID reorder preserves hidden/unknown pages; real edit-only
  drag with threshold/label ghost/insertion/Escape, Alt+Left/Right and moved-tab
  focus share the existing Canvas draft/Undo/Cancel/Reset/Done transaction.
  Reset means last Done, consistent with widget editing. No per-pointer Config
  write; concurrent order blocks Done, including after Undo Reset. Pure policy
  PASS1857; actual private-Niri PASS60 checks/14 frames on measured DPR1.25,
  four saved images, actual JSON readback and headless restart PASS.
  [Source-byte receipt, failures and raw evidence](../../docs/evidence/abyss-product/20261012-dashboard-tab-order/README.md).
  Final committed-SHA canonical and owner/installed, all edges/families,
  multi-output/physical touchpad gates OPEN. Continue `AGENDA-F01` after this
  source milestone; do not close waiting acceptance or repeat unrelated Issues.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [x] **CAL-F01 — Calendar Popup agenda indicators and configurable maximum — owner screenshots 2026-10-11:**
  [Owner: Alis dev; New Feature] Display compact event/Agenda
  indicator dots below the relevant dates in the **Calendar Popup**,
  matching the owner's Dashboard Calendar reference (third image).
  Provide **Settings → Calendar → Maximum indicators per day**,
  bounded (suggest 0–5; 0 hides, default 3). The limit controls
  visual dots, NOT the actual count of stored events; support a
  subtle +/overflow cue or accessible count when more exist.
  Reuse colors/source distinctions where meaningful, without
  equating the number of unique colors to total event count.
  Preserve compact 30px day cells and legibility in light/dark.

  Source parity: `modules/common/widgets/ObsidianMonthCalendar.qml`
  already supports `showEventDots`, `eventCount` and
  `eventColors` but hardcodes a maximum 3. Dashboard
  `modules/sidebarRight/calendar/CalendarWidget.qml` supplies
  these and enables dots; `modules/bar/ClockCalendarContent.qml`
  currently supplies neither counts nor `showEventDots`.
  Reuse `Events.getEventsForDate` and
  `CalendarSync.getEventsForDate`; update after local
  add/edit/remove, external calendar refresh, month navigation
  and midnight, including adjacent-month days. Put a validated
  preference in `defaults/config.json` and the active Calendar
  Settings route, respecting existing ii/Abyss Settings hierarchy.
  Avoid a second renderer/overlay; share configurable max with
  Dashboard month view if appropriate and avoid changing its
  current visual defaults without explicit user intent.

  Acceptance: zero, 1, many and overflow dots at max 0/1/3/5;
  local, external, all-day, recurring events and mixed colors;
  time zone, prev/next month, theme/fractional DPI, readable
  today/selected days, live settings changes, restart persistence
  and owner photo parity; source tests and native Niri visual QA.
  **Cloud source milestone (2026-10-12):** opt-in counted event
  dots for Calendar Popup reuse `ObsidianMonthCalendar` without
  changing Sidebar/Dashboard's existing unique-source-color style.
  `ClockCalendarContent` supplies one color per local/ICS event and
  updates on local add/edit/remove, ICS refresh, month/date change.
  Integrations → Calendar Settings now provides one persisted 0–5
  `calendar.maxEventDots` control (default 3); 0 hides indicators,
  overflow displays a + cue without changing actual event counts.
  Added native private-Niri 0/1/3/5 event-dot/overflow regression
  and English source strings; test is not yet run on a Wayland worker.
  State: SOURCE PATCHED / OPEN for focused/native Niri visual,
  Settings persistence, recurrence/long-name/month-edge and owner QA.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [x] **AGENDA-F01 — Creating an Agenda automatically creates one linked To-do (not vice versa) — owner request 2026-10-11:**
  [Owner: Alis dev; New Feature] **Local Agenda/Event creation
  ⇒ exactly one corresponding Todo item**, automatically after
  durable event creation. **Independent Todo creation ⇒ no Agenda**,
  no calendar reservation, no implied reminder. The linked task
  shares sensible title/date/time/details but keeps its own
  completed/pending state; completing Todo must NOT cancel the
  scheduled Agenda or vice versa. Show a clear linked relationship
  across Calendar Popup, Dashboard Agenda/Todo and Weekly Planner,
  without rendering the same event twice or sending duplicate alarms.

  Data design must live at the canonical `services/Events.qml`
  + `services/Todo.qml` mutation/adapter boundary, not in
  separate popup forms. Events persist numeric IDs and Todo
  can use internal JSON/txt or opt-in Obsidian Markdown backend;
  specify stable event→task ID / occurrence link schema,
  versioned migration, idempotent reconciliation on failed/
  delayed writes, retries and process restart. **CAL-I01**
  separately tracks Event disk persistence: do not create
  phantom Todos from events that were not durably saved.
  If Todo is not ready/busy/unsupported, show a pending-link
  warning and bounded safe retry, not silent loss or creation
  of duplicates. Respect user-chosen Obsidian backend/privacy,
  permissions and existing external Markdown task edits.

  Define owned-field sync for title/date/time changes while
  preserving independent Todo notes and completion; explicit
  non-destructive delete/unlink policy and safe recurrence
  semantics (one item per eligible created occurrence, no
  runaway duplication). Existing historical Agenda/Todo data
  preserved; any backfill must be opt-in and previewable.
  Imported external `CalendarSync`/ICS events are read-only
  and should NOT auto-generate tasks merely due to sync.

  Acceptance: create via Calendar Popup, Dashboard and Planner
  yields one linked Todo; Todo-only creates none; edit/delete,
  recurrence, completion, repeated save/retry, crash between
  stores, cancel/undo, internal vs Obsidian and package absent,
  restart and cross-surface updates are deterministic and
  preserve user files. Add source/fixture and owner native QA.
  State: SOURCE IMPLEMENTED / focused PASS — 2026-10-12, after
  `DASH-F01`/`DASH-F02` source milestones. Versioned per-created-occurrence
  keys and a durable unlink/delete outbox live in Events; Todo consumes actual
  event/task acknowledgements. Provider/source-date are pinned before mutation;
  no historical/imported-event backfill, inverse Todo→Agenda or task resurrection.
  Title/date/time/details update while task completion/notes remain independent.
  Event deletion/unlink retains task; explicit task deletion detaches durably
  first. Pending feedback and three bounded optional-worker retries replace
  indefinite polling; explicit retry restores failed actual writes.
  Shared Calendar/Planner/Dashboard relationship UI includes Retry/Unlink with
  Enter/Space/pointer control; virtual recurrence projection carries no false
  saved-task badge. Optional workers belong to Alis-Intergration main
  `4d0aa3f508fdd6bd953696d92bf529f1fb9f4b32` (package0.2.2), without owner install.
  Focused PASS: pure142; internal8 processes/24checks; Events-only bootstrap3
  actual processes/disk readbacks; internal persistence6/77 and Events6/59;
  optional bridge16 processes/48checks across both note modes; UI28checks/
  8captures with actual shared stores and private compositor allocation.
  [Source hashes, raw failures/fix-forwards, readbacks and acceptance limits](../../docs/evidence/abyss-product/20261012-agenda-internal/README.md).
  First data prerequisite: Events exposes only acknowledged, cloned durable
  snapshots and save failure/busy feedback; Agenda→Todo must consume that
  boundary, never `eventAdded` or an optimistic FileView cache. Actual headless
  PASS6 startup/restart processes, 45 QML checks and 6 independent JSON
  readbacks: coalescing, deferred refresh, denied save, explicit/cached retry
  and no phantom acknowledgements. [Pinned prerequisite evidence](../../docs/evidence/abyss-product/20261012-events-durable-boundary/README.md).
  Stopped canonical `f94de0535` predates this feature. Fresh committed exact-SHA
  full qualification, source-switch/midnight and older-package retry cases,
  installed identity, owner Calendar/Dashboard/Planner creation and actual
  external-vault acceptance remain OPEN. Continue ABYSS-F01 while preserving
  these gates; source/focused evidence alone does not complete the feature.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.

- [ ] **NOTES-F01 — Quick Notes Markdown Reading and editable Source/Live mode — owner request 2026-10-11:**
  [Owner: Alis dev; NEW feature] Upgrade existing shared Quick Notes into
  a genuine **Markdown note reader and editor** without replacing the
  canonical Notepad tab/content/autosave model. The user wants
  **two primary interaction states**, not two separate note copies:
  **Reading** when the Quick Notes popup is revealed by **hover with
  no actual editor/text-input focus**, and **Editing** once the user
  clicks the note body to input text. Reading must render Markdown
  like Obsidian Reading mode; Editing must offer Source editing and/or
  Obsidian-style **Live Editing** with a clear, durable mode choice
  (initially allow a reliable Source editor while providing a plan
  to qualify Live Editing; neither should silently corrupt syntax).
  Hover alone, pointer movement, a pinned popup or tab switch must
  NOT steal keyboard focus or change the note bytes. In Reading mode
  a click on the rendered text activates the editor for the same
  note; keep editor mode through typing/selection even if the pointer
  leaves the popup. Exit to Reading only on deliberate blur/outside
  click/escape/close where safe, after flushing pending changes;
  retain caret/selection and scroll mapping sensibly on return.

  **Markdown coverage:** headings, bold/italic, inline code/fenced
  blocks, links, lists, nested/numbered lists, checkboxes, blockquotes,
  horizontal rules and images/attachments at minimum. Keep ordinary
  plain text readable; unsupported markup remains visible as literal
  source rather than being silently discarded. Reading mode must
  show real visual formatting, not a TextArea displaying Markdown
  punctuation. Live Editing (if selected) should show formatted
  text while revealing underlying syntax near the caret/selection,
  with reversible edits and no HTML conversion of saved note text.
  Avoid a huge always-running Markdown parser or web engine.

  **Formatting shortcuts in Editing:** implement Ctrl+B to wrap/toggle
  **bold** and Ctrl+I to wrap/toggle *italic* for the selected text;
  when nothing is selected, insert paired markers and position the
  caret between them. Add appropriate standard shortcuts such as
  Ctrl+K for link, plus optionally a simple toolbar/commands for
  headings, lists, task lists, quote, inline/code block and strikethrough
  (with documented, conflict-free bindings). Preserve selection,
  undo/redo, Unicode/IME composition, word boundaries, multiline
  selections and literal backslash/code-fence contexts. Shortcuts
  must work only while the editor has focus, and must not override
  system/window actions, Ctrl+V image import, Ctrl+S flush or normal
  clipboard behavior. Keyboard accessibility is mandatory.

  **Single owner, many surfaces:** investigate
  `modules/screenCorners/QuickNotesPopup.qml` (hover/pin/OnDemand vs
  Exclusive keyboard focus and editor activation),
  `modules/sidebarRight/notepad/QuickNotesView.qml`,
  `NotepadWidget.qml` (existing TextArea, autosave, cursor, image
  preview, paste/image import and current Ctrl+V/Ctrl+S),
  `services/Notepad.qml` (stable note ID, persisted plain Markdown
  string in notepad-tabs.json), Sidebar Left and Dashboard reusers,
  and the separate legacy ii Notes content as an explicit
  compatibility decision. Share the Markdown parsing/rendering
  and editing commands rather than cloning one popup-only editor;
  preserve compact Quick Notes UI and existing multi-tab workflows.
  Keep concurrent views on one note synchronized by stable ID,
  without discarding unsaved changes or overwriting an external
  Obsidian-exported note.

  **Owner refinement — 2026-10-12 (Dashboard & Weekly Planner parity
  with Quick Notes Edgebar; source work still OPEN):**
  - Extend the same shared `NotepadWidget` / `QuickNotesView` Markdown
    Reading and Source Editing experience to **Dashboard Quick Notes**
    (`modules/dashboard/DashNotes.qml`) and to the **Quick Notes
    expanded column in Weekly Planner** (the same `DashNotes` loaded
    through `DashboardWeeklyPlanner.qml`). No cloned editor, note
    store, attachment import pipeline or second autosave scheduler.
  - **Reading:** render actual Markdown as in the Edgebar; no keyboard
    focus/caret or implicit note edits. Unlike the hover Edgebar,
    Dashboard/Weekly Planner MUST preserve their existing
    **Source-first default** and offer a clear, keyboard-accessible
    Reading/Source switch. Do not force Reading on hover, tab/page
    selection, load, dashboard open or ordinary pointer movement.
    A user deliberately choosing Reading may click the note body
    to return to Source Editing; exiting Source flushes pending
    changes without changing note identity.
  - **Source Editing:** preserve normal writing and selections;
    Ctrl+B / Ctrl+I wrap/toggle bold and italic, and Ctrl+K inserts
    Markdown links, sharing the existing `MarkdownNote.js` helper.
    Keep Ctrl+V image/text paste, Ctrl+S save, Unicode/IME,
    Undo/Redo, keyboard focus and context menu working.
  - **Autosave/attachments:** keep the existing Notepad stable note
    ID and pending-save synchronization across Dashboard,
    Weekly Planner, Sidebar and Edgebar, including when switching
    note tabs, modes, Dashboard pages, expanding/collapsing the
    planner column or closing the host. Reuse the Alis-managed
    attachment preview and existing paste/import helpers.
  - **No regression:** Sidebar Notes retains its present Source
    editor behavior, and the Edgebar keeps hover-to-Reading with
    explicit click-to-edit. A new optional Reading switch must not
    steal focus, unexpectedly persist a global mode, increase
    background renderer work when hidden, or change Waffle/
    connected Abyss theming.
  - **Implementation gap confirmed at receipt:** `QuickNotesView.qml`
    currently defaults `readingOnHover: false`; `DashNotes.qml`
    does not expose a Reading toggle, although formatting shortcuts,
    the Markdown renderer, autosave and attachment preview live
    in the shared `NotepadWidget.qml`. Wire a deliberate mode
    selector through the shared view and ensure it is usable in
    Dashboard's normal card and the narrow Weekly Planner expanded
    column.
  - **Acceptance:** source contract plus actual native Niri/
    Quickshell tests on both Dashboard and Weekly Planner: default
    Source; switch to formatted Reading without focus; click back
    to Editing; Ctrl+B/I/K selection and empty-selection cases;
    unchanged saved Markdown bytes and note IDs; attachments;
    autosave/Undo/Redo/IME; multiple note views editing/reloading;
    expand/collapse, tab/page switch, Today/next week, narrow
    widths, theme changes, restart, and no accidental focus/data
    loss. Keep OPEN until both surfaces and owner UI are verified.

  **Security & performance:** render untrusted note Markdown as data,
  never executable HTML/JS/QML; sanitize or disable raw HTML,
  JavaScript/data URLs and remote image/network fetching by default.
  File links and attachment paths must respect existing safe local
  note-attachment ownership, explicit user interaction and
  permission boundaries. Do not load note images, large documents
  or heavy renderer work when hidden; bound parsed document size
  and support long-note scrolling with responsive lazy/idle updates.
  Preserve literal Markdown bytes and image attachment references
  through viewing, editing, copy/paste, save/reload and
  Zettelkasten/Obsidian export. Existing [Quick Notes image delivery]
  (below) remains a separate accepted-source/native delivery gate;
  do not duplicate its helper or reimport images on mode changes.

  **Acceptance:** popup first hover -> Markdown Reading without
  cursor/keyboard grab; click note -> Source/Live Editing; Ctrl+B/
  Ctrl+I (selection and empty selection), link and formatting
  actions, undo/redo, IME and escaped punctuation; outside click/
  Escape/pin behavior, rapid hover reversal, tab switch, simultaneous
  Sidebar/Dashboard/corner notes, copied/attached images, empty
  notes, long notes, checklists, theme/scale/fractional monitors,
  disabled optional Obsidian and after restart. Verify identical
  stored Markdown text and stable note ID across each transition.
  Add QML/parser/formatting/focus/performance tests and require
  native Niri/Quickshell owner visual + input acceptance.
  **Source milestone on Alis dev (2026-10-12):** the bottom-left
  Quick Notes hover surface uses the existing stable-ID NotepadWidget
  in Markdown Reading mode (Qt native MarkdownText rendering; no editor
  keyboard focus until an explicit note-body click). Source Editing
  retains the canonical TextArea, 800ms autosave and tab identity;
  Ctrl+B/Ctrl+I/Ctrl+K apply reversible Markdown marker edits on the
  original bytes, without HTML conversion. External image URLs/raw
  HTML are not loaded by the preview; existing owned hashed image
  attachments remain visible in the separate lazy attachment rail.
  Sidebar/Dashboard maintain their previous Source-first behavior;
  Live Editing near-caret rendering is NOT implemented.
  **Verification at source `bb370eff16db3c53ff45a99a93f962fe6df89eb9`:**
  the exact Git blob `MarkdownNote.js` (SHA
  `7a624cf2a0168f814e79a1d80254f2ab1fa9a6bf`) and matching
  `test-quick-notes-markdown-policy.mjs` blob (SHA
  `dbeda1516c6b7b2d1ea7af001bdfcc4250c2aed9`) run with
  Node: **14 tests PASS**. GitHub CI [run 38162496197]
  (https://github.com/llocphann/Alis/actions/runs/38162496197)
  confirms the Markdown policy PASS, source QML guards and translation
  source parity PASS. The private-Niri Markdown QML fixture exits
  with a **SKIP: qs unavailable**, not an actual native PASS.
  Full CI is FAIL (323 PASS / 33 FAIL / 2 SKIP): most failures require
  missing Quickshell and there are separate pre-existing/independent
  source-contract mismatches; it does not certify this patch's desktop
  rendering, focus, IME, undo or compatibility behavior.
  State: SOURCE PATCHED / OPEN for native markdown fidelity,
  preview/Source focus, Unicode/IME/undo/restart, mouse/touchpad,
  attachment parity, full canonical and owner UI acceptance.
  **Cloud continuation (2026-10-12):** dashboard and Weekly Planner
  now share an explicit keyboard-focusable Reading/Source switch through
  DashNotes → QuickNotesView → the existing NotepadWidget. Source stays
  the default; switching to Reading flushes the stable-ID draft and
  cancels pending editor-focus callbacks; clicking the rendered text
  returns to Source without replacing the note or attachment pipeline.
  The Edgebar hover behavior and Sidebar default remain unchanged.
  Added source and private-native multi-surface regression covering both
  Dashboard card and Planner notes column. Native owner/installed
  acceptance and exact-SHA full canonical remain OPEN. This completes
  a requested source milestone, NOT the entire NOTES-F01.

- [x] **NOTES-F02 — Quick Notes image delivery:** Hadalis `add29d6f8` implements shared
  paste/import, original-byte storage, Markdown persistence and preview with
  stable asynchronous note ownership. Hadalird `b0c975a7f40bdf531012be326bc728f5c014b696`
  (0.2.1) exports referenced images to the selected Obsidian vault's configured
  attachment location. Core/optional synthetic filesystem and real QML tests
  pass, including delayed tab switching, selection, restart and collisions.
  Confirm installed versions and explicit owner paste/export with source/drafts
  retained. No fixture writes to a personal vault or reads personal clipboard.
  **Completion classification — 2026-10-12 (maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** Quick Notes image paste/import/export source delivery and its synthetic filesystem/real-QML tests reported complete; owner real paste/vault attachment flow remains unverified. Previously recorded full-canonical FAIL/SKIP, partial native coverage and independent unresolved regressions remain factual; no fresh PASS or physical owner approval is claimed.

- [ ] **UTIL-F01 — Utilities feature delivery:** source already provides Monitor
  Arrangement, Display Mode, Sound Output and Night Light/Anti Flashbang pages
  with bottom-centered dots/swipe and existing display/audio backends. Verify
  actual Extend/Primary/Second-only/Mirror, hotplug/failure rollback, `wl-mirror`
  lifetime, PipeWire default sink and Night Light/Anti Flashbang sensitivity.
  Do not claim real Mirror from a synthetic fixture or introduce a second backend.
  **Cloud source fix, 2026-10-12:** the active wl-mirror process now retains
  its original source/target as separate immutable runtime identity. Niri
  hotplug must stop that process before dropdown selections are normalized,
  including when every output vanishes; deferred mirror restarts revalidate
  both outputs before spawn. Eight additional pure policy cases cover source,
  target, all-output disconnect, invalid pairs and valid replacement pairs.
  This is a *bounded source milestone*, not proof of live wl-mirror, device
  recovery, PipeWire or Night Light acceptance. Owner/multi-monitor and
  hardware tests remain OPEN; do not mark UTIL-F01 complete.
  **Status accuracy repair, 2026-10-12 — Alis dev `fa935f2f8ef06e1e71d42a38f42641ff7db2cbca`:**
  Mirror start now reports the immutable launched source/target instead of
  possibly reselected dropdown values. Explicit user Stop announces mirror
  termination; internal Apply/hotplug stops leave their own status intact
  and a subsequent Apply supersedes a pending manual Stop. The same
  DisplayModePlan JS fixture was executed directly on the exact modified
  source with **34 focused assertions PASS** (planning, rollback, mirror
  pairs/status); physical Niri/wl-mirror, hotplug and canonical native
  validation were NOT RUN. UTIL-F01 remains OPEN.

- [ ] **SYS-F01 — Non-Arch optional system gateway:** add trusted distro-owned
  provisioning beyond Arch for Hadalird helpers. Keep root gateway/policy separate
  from user-owned optional payloads and require explicit native authorization.
  Prove package ownership, removal and failure behavior per supported distro;
  never use a user-checkout installer as root or claim untested distro support.
  **Owner priority override — 2026-10-12 (#12): VERY LAST / DEFERRED.** Non-Arch optional system gateway is almost the final portfolio task: do not select or implement it until all other currently requested New Features, Rework and Issues, including the other deferred features, are complete. Revisit only after an explicit maintainer reprioritization.

- [x] **POWER-F01 — Power-profile render quality delivery:** qualify Abyss automatic quality
  following and manual mode through live profile changes without reload or lost
  preferences. Hadanion owns Companion's two levels: Performance and Quality
  (former Balanced), safe old-tier migration and shared AI behavior. Hadalis
  retains the Launcher effective-quality indicator and optional host API.
  Do not silently lower manual quality as part of strict-lossless optimization.
  **Owner verified — 2026-10-12 (maintainer explicit confirmation, feature #13):** Hoàn thành / Owner verified. This newer confirmation supersedes the historical 'owner acceptance pending' text for this task. Preserve prior source, tests, package/hardware evidence and any recorded FAIL/SKIP unchanged; do not infer that unrun checks passed. Reopen only for a new requirement or reported regression.

## Alis-Companion — centralized features and permissions

**Central task intake 2026-10-11:** implementation owners are
[Alis-Companion](https://github.com/llocphann/Alis-Companion) main
(source snapshot 732136ef65bb3c84d9339207210c955759a85b76)
and [Alis-Intergration](https://github.com/llocphann/Alis-Intergration) main
(source snapshot b0c975a7f40bdf531012be326bc728f5c014b696).
These source SHAs identify the import, **not** the installed release or
acceptance. Alis dev holds the ONLY authoritative TODO status; package code,
test scripts and historical receipts remain in each source repository.


**Visual source:** [active snapshot](https://github.com/llocphann/Alis-Companion/blob/732136ef65bb3c84d9339207210c955759a85b76/to-do/cloud-bot/ABYSS_WATER_DROPLET_COMPANION.md).
**AI source:** [active snapshot](https://github.com/llocphann/Alis-Companion/blob/732136ef65bb3c84d9339207210c955759a85b76/to-do/cloud-bot/WULL_LOCAL_AI.md).
All statuses below represent remaining tasks; previously implemented
source, synthetic fixtures and staged 3D previews must NOT be rebuilt.

- [ ] **AC-F01 — Opt-in semantic host event bridge (VIS-02):**
  Alis dev owns authenticated, versioned, bounded semantic event reduction
  and consent; Companion owns the already staged receiving schema, existing
  WullPresence, WullCuriosity, WullMotion and Director arbitration.
  Validate stale/order/unknown/replay rejection, one visual clock/epoch,
  focus, 45-second permission grace, background lock/fullscreen/security
  priority, direct chat/drag/modal, portal/cowork and disconnect/revoke.
  Synthetic protocol QML fixtures already qualified; no live host
  transport, sensors or agent hooks authorized. State: SOURCE-READY,
  LIVE BLOCKED_APPROVAL.
  **Owner priority override — 2026-10-12 (feature #14): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F02 — Original 3D cowork laptop (VIS-04):**
  The Aqua and Octo original Blender scenes, 8 added performances per
  cast, interruption-safe controller and private native previews exist;
  they are STAGING, not a shipped working actor. Finish ONE actor runtime
  asset/material for laptop_open -> typing/thinking/agent/pause -> close,
  uninterrupted across short focus changes and interrupted safely by
  cast/drag/chat/portal. Respect theme, original liquid/limbs/cups,
  4-rim connection, corners, hit-regions, scaling, accessibility,
  disabled/reduced motion and GPU budget. Do not open portal or spawn
  another actor on mere laptop appearance. Require native owner approval.
  State: PARTIAL SOURCE, LIVE OPEN.
  **Owner priority override — 2026-10-12 (feature #15): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F03 — Focus cowork and bounded ambient reactions (VIS P1):**
  Reuse the Alis Focus timer/session for optional reading, book,
  coffee/sip and quiet thoughts; use permitted coarse idle/battery/
  MPRIS/search/success/failure categories with cooldown, permission
  and opt-out, not raw app content or a second clock. Favor existing
  clips before new authored gestures. State: NEW/consent gated.
  **Owner priority override — 2026-10-12 (feature #16): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F04 — User-initiated Pocket plus visual regression authoring (VIS P1):**
  Prove Wayland drag/drop, selected original-file-safe bounded metadata,
  explicit user permission and existing Alis/Vault interfaces before
  attaching Pocket; never auto-ingest documents, edit originals or
  trigger a portal by default. Maintain four-rim pointer/one-shot/
  focus/clip/cast/disabled lifecycle regression matrix. Defer extra
  props/easter eggs until core value and cost are accepted. State:
  NEW/permissions and native proof required.
  **Owner priority override — 2026-10-12 (feature #17): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F05 — Non-punitive bond/dialogue (VIS P1):**
  Optional familiarity, mood and preference are separate; no guilt,
  streak decay, surveillance, false intimacy or copied third-party
  character assets/catchphrases. Require clear settings and user consent.
  State: NEW, UX/privacy contract first.
  **Owner priority override — 2026-10-12 (feature #18): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F06 — User-consented memory with inspect/edit/forget (AI P1):**
  Existing bounded SQLite consent prototype is DORMANT. Specify identity
  and device boundary, source=explicit_user, per-cast vs shared scope,
  TTL/quota, UI for viewing/editing/forgetting, migration/revoke and
  WAL/backups/external Obsidian/chat deletion semantics. Never infer
  memory silently or promise secure disk erasure from SQL DELETE alone.
  State: NEW/BLOCKED_APPROVAL.
  **Owner priority override — 2026-10-12 (feature #19): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F07 — Optional proactive policy (AI P1):**
  Existing fake-clock policy prototype is DORMANT; require explicit
  enable, quiet hours, no wakes, ignored/dismissed backoff, event and
  daily quotas, manual mode, Focus, chat/modal, lock, fullscreen,
  idle, reduced motion and shared presentation budget. No background
  model loading or notifications until owner authorizes. State:
  NEW/BLOCKED_APPROVAL.
  **Owner priority override — 2026-10-12 (feature #20): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F08 — Grounded Todo/Obsidian reminders (AI P1):**
  Only read typed user-authorized tasks and chosen rows; retain existing
  byte-safe explicit Mood/Energy note writes with real confirmation.
  Never promote vault text to prompt instructions, fabricate scheduled
  reminders or claim user journal was saved from a synthetic fixture.
  The optional Integration journal may not be installed. State:
  SOURCE PARTIAL/INSTALL + PERMISSION GATES.
  **Owner priority override — 2026-10-12 (feature #21): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F09 — Shared persona expression without extra movement owner (AI P1):**
  AI may propose bounded text/expression but cannot decide scene
  location, move actor, open Popup, trigger portal or view raw content;
  use existing visual Director and generic Alis AI provider. Character
  animations must work with AI off or unavailable. State: NEW,
  depends on semantic host contract.
  **Owner priority override — 2026-10-12 (feature #22): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

- [ ] **AC-F10 — Typed local tools / conditional RAG research (AI P2):**
  Start with read-only typed existing state/repo/doc metadata; any
  user-approved edits/actions need allowlisted capability, explicit
  confirmation, receipts, timeout, cancel/idempotence and rollback.
  Consider RAG and 2-model Reflex/Brain routing only if real workload
  measurements establish value and privacy. Archived suggested GGUF
  models are not assumed installed. **Distillation, SFT/LoRA, autonomous
  diary, self-modifying persona, Discord/MCP, aggressive sensors and
  broad coding-agent automation remain DEFERRED / OUT OF SCOPE.**
  State: RESEARCH ONLY, further authorization required.
  **Owner priority override — 2026-10-12 (feature #23): FINAL-PHASE / DEFERRED.** Do not select or implement this feature until all other non-deferred New Features, Rework and Issues have been completed. Keep scope and safety/consent gates unchanged; only an explicit maintainer reprioritization can move it earlier.

## Alis-Intergration — centralized optional package features

**Central task intake 2026-10-11:** implementation owners are
[Alis-Companion](https://github.com/llocphann/Alis-Companion) main
(source snapshot 732136ef65bb3c84d9339207210c955759a85b76)
and [Alis-Intergration](https://github.com/llocphann/Alis-Intergration) main
(source snapshot b0c975a7f40bdf531012be326bc728f5c014b696).
These source SHAs identify the import, **not** the installed release or
acceptance. Alis dev holds the ONLY authoritative TODO status; package code,
test scripts and historical receipts remain in each source repository.


There was NO active TODO directory in the integration repository; these
outcomes come from its manifest, README, source and outstanding Alis
host acceptance, not from an invented prior roadmap.

- [x] **AI-F01 — TLP/Battery existing optional feature acceptance:**
  [Owner: Alis-Intergration main] Verify source-implemented TLP worker,
  vendor probes, charge limits, Radio Device Wizard, permission-scoped
  helpers and Classic/Waffle settings; no root action or profile
  overwrite at install or without user permission. State: IMPLEMENTED
  IN SOURCE, HOST/NATIVE ACCEPTANCE OPEN.
  **Owner verified — 2026-10-12 (maintainer explicit confirmation, feature #24):** Hoàn thành / Owner verified. This newer confirmation supersedes the historical 'owner acceptance pending' text for this task. Preserve prior source, tests, package/hardware evidence and any recorded FAIL/SKIP unchanged; do not infer that unrun checks passed. Reopen only for a new requirement or reported regression.

- [x] **AI-F02 — Thinkfan existing optional feature acceptance:**
  [Owner: Alis-Intergration main] Verify worker status/rpm/sensors,
  permissions, fail-safe fan control and disabled/missing package
  recovery; never install/enable/change fan service automatically.
  State: SOURCE PRESENT, OWNER HARDWARE QA OPEN.
  **Owner verified — 2026-10-12 (maintainer explicit confirmation, feature #25):** Hoàn thành / Owner verified. This newer confirmation supersedes the historical 'owner acceptance pending' text for this task. Preserve prior source, tests, package/hardware evidence and any recorded FAIL/SKIP unchanged; do not infer that unrun checks passed. Reopen only for a new requirement or reported regression.

- [x] **AI-F03 — Obsidian optional theme, Todo and Zettelkasten delivery:**
  [Owner: Alis-Intergration main] Verify theme, path settings,
  managed/Daily Note task backend, Quick Notes, Zettelkasten images/
  attachments and correct safe vault writes in synthetic fixtures,
  then consented live Obsidian. Keep notes untouched when disabled
  and generic host Todo/Notes available without optional package.
  State: SOURCE PRESENT, OWNER VAULT QA OPEN.
  **Owner verified — 2026-10-12 (maintainer explicit confirmation, feature #26):** Hoàn thành / Owner verified. This newer confirmation supersedes the historical 'owner acceptance pending' text for this task. Preserve prior source, tests, package/hardware evidence and any recorded FAIL/SKIP unchanged; do not infer that unrun checks passed. Reopen only for a new requirement or reported regression.

- [x] **AI-F04 — Versioned package lifecycle and host delivery:**
  [Owner: Alis-Intergration main] Qualify release manifest/API,
  sourceSha-pinned atomic current-link install/update/rollback/
  uninstall, lazy worker lifetime, explicit refresh and helper
  install separated from ordinary package. Run make test and
  cross-repo Alis tests, multi-family QML, DESTDIR/PREFIX and
  absent-dependency cases. Related bugs tracked in Issues, not
  recreated here. State: SOURCE PRESENT, RELEASE GATES OPEN.
  **Owner verified — 2026-10-12 (maintainer explicit confirmation, feature #27):** Hoàn thành / Owner verified. This newer confirmation supersedes the historical 'owner acceptance pending' text for this task. Preserve prior source, tests, package/hardware evidence and any recorded FAIL/SKIP unchanged; do not infer that unrun checks passed. Reopen only for a new requirement or reported regression.

- [ ] **COMP-F01 — Install/update Companion automatically with Alis — owner clarification 2026-10-12:**
  [Owner: Alis dev; New feature / installation integration] Alis must
  install and update Companion itself rather than prompting users to clone,
  choose or manually install the separate source repository.
  Retain the separate `Alis-Companion` source and its immutable runtime
  releases, pin a known-compatible source SHA in Alis, preserve the active
  release on build failure, and use the normal Alis install/update/reinstall
  lifecycle. Leave optional AI permissions and activation preference off
  until the owner chooses them; never run a third-party build as root or
  rewrite an owner's separate Companion checkout.
  **Implementation milestone (source, 2026-10-12):** A pinned
  `scripts/companion-manager.py` manager now runs during
  `./setup install`, `reinstall`, `update` (including no-op and
  package-managed update entry points). It delegates to the Companion
  immutable/atomic installer, validates the activated source identity,
  rejects foreign remotes and unsafe checkouts, and keeps setup from
  claiming success after a failed sync. Settings no longer links to an
  external manual installer. Offline synthetic lifecycle fixture added.
  **Still OPEN:** exact-SHA canonical and actual first-time Rust build;
  source/API/runtime startup, installed identity/restart/rollback, low
  connectivity, owner acceptance. Staged system package `make install`,
  Nix and Arch installation do not provision an arbitrary desktop user's
  home; package-managed user provisioning needs separate packaging work
  before claiming universal Alis auto-install. Do not mark owner verified.

## Cross-repository code ownership

All task selection, classification, status, progress and completion for
Alis core, Alis-Companion and Alis-Intergration now belong to these
THREE Alis dev lists. Implementation, tests and technical evidence remain
in their respective source repositories. Historical satellite TODOs are
import baselines only, not separate active queues. Respect optional
default-off state, source identity, explicit permission and all
owner/desktop release gates. Do not mutate Alis stable.
