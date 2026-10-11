# New features

Work after [Issues/bugs](ISSUES.md) and [Rework/optimization](REWORK_OPTIMIZATION.md).
Source-implemented features below still need their stated delivery/owner gates;
do not reimplement them solely because a checkbox is open.


- [ ] **Alis Quickshell deep performance profiler — owner request 2026-10-11:**
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

- [ ] **ABYSS-F01 — Per-module Screen Edge position lock — owner request 2026-10-11:**
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
  acceptance. State: NEW/OPEN; source implementation and
  validation NOT STARTED.

- [ ] **Edit Abyss Layout Screen Edge module multi-selection — owner request 2026-10-10:**
  Add an explicit multiple-selection mode for Screen Edge modules while
  **Edit Abyss Layout** is active. Show which modules are selected, support
  add/remove/clear selection and coherent subsequent edits when several targets
  are selected. Keep normal non-edit behavior intact; define guarded batch
  actions instead of silently changing unrelated modules. Test horizontal and
  vertical edges, cross-edge/per-output selection, drag/snapping and Cancel/
  Undo/Done/save semantics; coordinate with compact toolbar redesign in
  [Rework](REWORK_OPTIMIZATION.md). State: NEW, design/implementation and owner
  input acceptance pending.

- [ ] **Quick Notes Markdown Reading and editable Source/Live mode — owner request 2026-10-11:**
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
  State: NEW/OPEN; source audit complete at high level, design/
  implementation/test and owner acceptance pending.

- [ ] **Quick Notes image delivery:** Hadalis `add29d6f8` implements shared
  paste/import, original-byte storage, Markdown persistence and preview with
  stable asynchronous note ownership. Hadalird `b0c975a7f40bdf531012be326bc728f5c014b696`
  (0.2.1) exports referenced images to the selected Obsidian vault's configured
  attachment location. Core/optional synthetic filesystem and real QML tests
  pass, including delayed tab switching, selection, restart and collisions.
  Confirm installed versions and explicit owner paste/export with source/drafts
  retained. No fixture writes to a personal vault or reads personal clipboard.

- [ ] **Utilities feature delivery:** source already provides Monitor
  Arrangement, Display Mode, Sound Output and Night Light/Anti Flashbang pages
  with bottom-centered dots/swipe and existing display/audio backends. Verify
  actual Extend/Primary/Second-only/Mirror, hotplug/failure rollback, `wl-mirror`
  lifetime, PipeWire default sink and Night Light/Anti Flashbang sensitivity.
  Do not claim real Mirror from a synthetic fixture or introduce a second backend.

- [ ] **Non-Arch optional system gateway:** add trusted distro-owned
  provisioning beyond Arch for Hadalird helpers. Keep root gateway/policy separate
  from user-owned optional payloads and require explicit native authorization.
  Prove package ownership, removal and failure behavior per supported distro;
  never use a user-checkout installer as root or claim untested distro support.

- [ ] **Power-profile render quality delivery:** qualify Abyss automatic quality
  following and manual mode through live profile changes without reload or lost
  preferences. Hadanion owns Companion's two levels: Performance and Quality
  (former Balanced), safe old-tier migration and shared AI behavior. Hadalis
  retains the Launcher effective-quality indicator and optional host API.
  Do not silently lower manual quality as part of strict-lossless optimization.

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

- [ ] **AC-F03 — Focus cowork and bounded ambient reactions (VIS P1):**
  Reuse the Alis Focus timer/session for optional reading, book,
  coffee/sip and quiet thoughts; use permitted coarse idle/battery/
  MPRIS/search/success/failure categories with cooldown, permission
  and opt-out, not raw app content or a second clock. Favor existing
  clips before new authored gestures. State: NEW/consent gated.

- [ ] **AC-F04 — User-initiated Pocket plus visual regression authoring (VIS P1):**
  Prove Wayland drag/drop, selected original-file-safe bounded metadata,
  explicit user permission and existing Alis/Vault interfaces before
  attaching Pocket; never auto-ingest documents, edit originals or
  trigger a portal by default. Maintain four-rim pointer/one-shot/
  focus/clip/cast/disabled lifecycle regression matrix. Defer extra
  props/easter eggs until core value and cost are accepted. State:
  NEW/permissions and native proof required.

- [ ] **AC-F05 — Non-punitive bond/dialogue (VIS P1):**
  Optional familiarity, mood and preference are separate; no guilt,
  streak decay, surveillance, false intimacy or copied third-party
  character assets/catchphrases. Require clear settings and user consent.
  State: NEW, UX/privacy contract first.

- [ ] **AC-F06 — User-consented memory with inspect/edit/forget (AI P1):**
  Existing bounded SQLite consent prototype is DORMANT. Specify identity
  and device boundary, source=explicit_user, per-cast vs shared scope,
  TTL/quota, UI for viewing/editing/forgetting, migration/revoke and
  WAL/backups/external Obsidian/chat deletion semantics. Never infer
  memory silently or promise secure disk erasure from SQL DELETE alone.
  State: NEW/BLOCKED_APPROVAL.

- [ ] **AC-F07 — Optional proactive policy (AI P1):**
  Existing fake-clock policy prototype is DORMANT; require explicit
  enable, quiet hours, no wakes, ignored/dismissed backoff, event and
  daily quotas, manual mode, Focus, chat/modal, lock, fullscreen,
  idle, reduced motion and shared presentation budget. No background
  model loading or notifications until owner authorizes. State:
  NEW/BLOCKED_APPROVAL.

- [ ] **AC-F08 — Grounded Todo/Obsidian reminders (AI P1):**
  Only read typed user-authorized tasks and chosen rows; retain existing
  byte-safe explicit Mood/Energy note writes with real confirmation.
  Never promote vault text to prompt instructions, fabricate scheduled
  reminders or claim user journal was saved from a synthetic fixture.
  The optional Integration journal may not be installed. State:
  SOURCE PARTIAL/INSTALL + PERMISSION GATES.

- [ ] **AC-F09 — Shared persona expression without extra movement owner (AI P1):**
  AI may propose bounded text/expression but cannot decide scene
  location, move actor, open Popup, trigger portal or view raw content;
  use existing visual Director and generic Alis AI provider. Character
  animations must work with AI off or unavailable. State: NEW,
  depends on semantic host contract.

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

- [ ] **AI-F01 — TLP/Battery existing optional feature acceptance:**
  [Owner: Alis-Intergration main] Verify source-implemented TLP worker,
  vendor probes, charge limits, Radio Device Wizard, permission-scoped
  helpers and Classic/Waffle settings; no root action or profile
  overwrite at install or without user permission. State: IMPLEMENTED
  IN SOURCE, HOST/NATIVE ACCEPTANCE OPEN.

- [ ] **AI-F02 — Thinkfan existing optional feature acceptance:**
  [Owner: Alis-Intergration main] Verify worker status/rpm/sensors,
  permissions, fail-safe fan control and disabled/missing package
  recovery; never install/enable/change fan service automatically.
  State: SOURCE PRESENT, OWNER HARDWARE QA OPEN.

- [ ] **AI-F03 — Obsidian optional theme, Todo and Zettelkasten delivery:**
  [Owner: Alis-Intergration main] Verify theme, path settings,
  managed/Daily Note task backend, Quick Notes, Zettelkasten images/
  attachments and correct safe vault writes in synthetic fixtures,
  then consented live Obsidian. Keep notes untouched when disabled
  and generic host Todo/Notes available without optional package.
  State: SOURCE PRESENT, OWNER VAULT QA OPEN.

- [ ] **AI-F04 — Versioned package lifecycle and host delivery:**
  [Owner: Alis-Intergration main] Qualify release manifest/API,
  sourceSha-pinned atomic current-link install/update/rollback/
  uninstall, lazy worker lifetime, explicit refresh and helper
  install separated from ordinary package. Run make test and
  cross-repo Alis tests, multi-family QML, DESTDIR/PREFIX and
  absent-dependency cases. Related bugs tracked in Issues, not
  recreated here. State: SOURCE PRESENT, RELEASE GATES OPEN.

## Cross-repository code ownership

All task selection, classification, status, progress and completion for
Alis core, Alis-Companion and Alis-Intergration now belong to these
THREE Alis dev lists. Implementation, tests and technical evidence remain
in their respective source repositories. Historical satellite TODOs are
import baselines only, not separate active queues. Respect optional
default-off state, source identity, explicit permission and all
owner/desktop release gates. Do not mutate Alis stable.
