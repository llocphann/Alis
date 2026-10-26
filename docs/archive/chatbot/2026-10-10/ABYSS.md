> Historical snapshot archived on 2026-10-10 from Hadalis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../../to-do/README.md).

# Cloud Bot — Abyss outstanding work

This is a consolidation of the former root README runtime/unfinished checklists; it is **not** a claim that source-complete work needs reimplementation. Re-audit the latest `dev` and require owner-session evidence for visual or hardware acceptance. Historical patches, status and the original continuation prompt are archived at [`../../docs/archive/ABYSS_CHECKPOINT_BEFORE_TODO_2026-09-30.md`](../../ABYSS_CHECKPOINT_BEFORE_TODO_2026-09-30.md). Never reapply failed/reverted popup patches blindly.

## Unresolved owner report

- [ ] **Wi-Fi/Bluetooth System Tray popup text is missing.** Hover opens the shell popup, but the maintainer reports no text inside it. Check the actual embedded WifiDialog/BluetoothDialog loading, page/label visibility, foreground colors, content sizing/allocator reflow and live device/network state. Verify empty/disabled/loading states and populated lists, readable labels/actions, first hover and reopen. Preserve System Tray ownership; do not reintroduce standalone connectivity modules. The loading blocker is fixed in `134b0115a` and visible-title/native contracts pass through `2d31f06b9`; owner-session hover and populated-list visual acceptance of the report remain open.

## Other runtime findings needing reconciliation

- [ ] **Settings navigation visual acceptance:** the old shared indicator jumped when Headings expanded/collapsed. `0c804b5ac` replaces that presentation with compact parent/child navigation and selection owned by each button. Native parent/child/Back, stable routes, custom order, hidden-page restore and integration deep links pass in the canonical `3881227eb` run. Verify the new presentation on the owner desktop before closing this visual gate; the rejected shared-indicator geometry is retired.
- [ ] **System Monitor popup refinement:** source-side two-digit CPU Load width reservation and RPM/Level Material icons are present; live-validate that one/two-digit CPU changes no longer resize the popup and fan metrics remain aligned/readable.
- [ ] **Shell boot integrity:** the installed/runtime shell must remain free of `Type ... unavailable`, duplicate-identifier and singleton-construction failures on the exact candidate.
- [ ] **Connected-surface acceptance:** Popup, Left/Right Sidebar, Dashboard, Settings, Dock and OSK still require live Niri validation for contact geometry, seam/gap behavior, edge ownership, hover transfer/retract, fractional scale and multi-output.
- [ ] **Screen Edge / Bar lifecycle:** validate idle/maximized visibility, width/radius/shadow settings, auto-hide ownership and fullscreen enter/exit without stranded or blank Bar content.
- [ ] **Music/media:** validate Local Music Stop -> long idle -> Play, bulk folder/track selection, queue operations and unified Shuffle/Repeat/CAVA behavior. CAVA/EasyEffects DSP lifecycle still needs live audio/player-switch/reopen validation.
- [ ] **Dashboard/Overview:** ii Overview now releases its heavy multi-output tree after the configured exit animation plus a small safety grace instead of inheriting the five-minute retained-surface cache; Dashboard keeps its separate mapped-retained contract. Live-validate Overview cold open/reopen and Dashboard/Overview motion without the rejected whole-Dashboard scene-graph cache; artwork/controls must not flash cyan, rebuild or disappear during open/close.
- [ ] **Calendar/Weather:** validate responsive Calendar interaction and the fixed-footprint two-tab Weather wheel/slide behavior across supported scaling.
- [ ] **ThinkFan/TLP:** validate installed helper/polkit reconciliation, profile-follow synchronization, active-session authorization and uninstall ownership on maintainer hardware.
- [ ] **Material-only cleanup:** the public/runtime boundary is source-complete; only intentional migration compatibility may remain. Finish the final active-tree residue audit and live visual acceptance before closing the gate.
- [ ] **Release gate:** run `bash scripts/validate-maintainer-local.sh` plus Niri/Quickshell live smoke tests on the exact candidate SHA before closing runtime-sensitive P0 gates.

## Six refinement requirements — source exists; reconcile acceptance

- [ ] Verify current source and acceptance for: **First implementation priority: crest/ripple-only waves with breaker/whitewater.** Do not render troughs that sink the Screen Edge below its resting thickness. Round and smooth crest tips, allow taller crests and narrower bases, and remove occasional needle-shaped peaks. Add restrained breaker/whitewater at active crests. Preserve signed wave physics for same/opposite-direction interaction, but project a bounded positive crest profile into geometry/material rendering. Smooth both the sampled profile and its interpolation; avoid sharp clipping of a signed signal at zero. Reuse the shared field shader for whitewater rather than adding per-wave particles/capture/FBOs. Honor effects, shared strength, reduced motion and idle sleep; keep the no-waves resting Edge unchanged. Visual acceptance still requires recordings of isolated ripples, crossing packets, audio and strong popup emergence on all four Edges.
- [ ] Verify current source and acceptance for: **Physical Edge thickness slider:** add a numeric px slider in Edit Abyss Layout for the selected Edge. Shared module size / Overall size are not a substitute. Preserve per-output drafts, Cancel/Done and local-versus-whole expansion for a lone module; thickness must influence inherited module sizing without breaking explicit custom sizes or body clearance.
- [ ] Verify current source and acceptance for: **Clipboard History flickers Dashboard:** opening and closing Clipboard History must not toggle Dashboard. Trace the actual open/close ownership and focus callbacks; preserve Dashboard's prior state and clipboard interaction. Capture first/repeated open-close with Dashboard initially both closed and open before claiming a fix.
- [ ] Verify current source and acceptance for: **IPC joins:** expose the same nearby-corner / adjacent-Edge join option for IPC targets as for module popups. Keep a persistent example while editing, save the join per kind/output, honor Cancel, and validate corner clearance, masks and readable content.
- [x] **Niri reload success popup retired by maintainer:** successful Niri config reloads are intentionally silent and must not create a popup/notification. Keep Niri reload failures actionable; do not reintroduce the retired success notification during Abyss presentation work.
- [ ] Verify current source and acceptance for: **Smoother ocean profile:** amplitude alone is insufficient. Qualify round, tall crests with compact shoulders, no trough erosion and readable bodies at the stronger presets; keep finite propagation, stability and resource bounds. This refines the previous ocean-scale request rather than replacing the existing interaction/strength settings.

## Original supplemental requirements — preserve scope

The following 12+14 requirements originated in the 2026-09-28 handoff. They are **verification inventory**, not 26 new implementation orders; reconcile every item against later implementation/evidence.

- [ ] Reconcile: **Weather hover regression:** reproduce the initial simultaneous rendering of Detailed Weather and Orbital Weather, followed by the detailed tab sliding down. Fix initialization, tab visibility/layout and transition ordering; verify first hover, repeated hover, close/reopen and a recording.
- [ ] Reconcile: **Repository-wide efficiency/correctness:** audit all functions and optimize resource use with measured before/after behavior. Debug each feature using live diagnostics, screenshots/image analysis and recordings alongside regression scripts; script success alone is insufficient.
- [ ] Reconcile: **Utilities Popup:** add Monitor Arrangements; Display Mode (Extend, Mirror, Second Screen only, etc.); Sound Output; and Night light/Anti Flashbang tabs. Tab indicators are circular dots at bottom-center; support sliding left/right. Complete Anti Flashbang so it works reliably, responds more sensitively and provides deeper customization. Reuse supported display/audio backends and existing content where appropriate.
- [ ] Reconcile: **Finite Dashboard:** remove scrolling. Available module space is bounded by the actual Dashboard dimensions. Stop modules jumping or scrambling; fit or reject moves/resizes/restores within that space while preserving readable minimums, other cards, saved layout and empty-layout Add controls. Do not solve packed restore by growing a scrollable workspace.
- [ ] Reconcile: **Editor-owned module sizing:** remove Overall module scale and Top/Left/Right/Bottom Edge module size controls from Settings; integrate sizing into Edit Abyss Layout. Fix the reported nonfunctional four-edge controls. When an Edge has only one module, provide a choice to expand only the module's part of the Edge or the entire Edge; retain explicit per-module sizing and safe config migration.
- [ ] Reconcile: **Sidebar centering:** center Sidebar Left/Right on the corresponding physical Left/Right Edge, preserving custom dimensions and output ownership.
- [ ] Reconcile: **Connectivity popups / ownership:** keep the mature Wi-Fi and Bluetooth popup contents with usable actions/live service state, but **do not expose Wi-Fi or Bluetooth as separate Screen Edge modules**. The System Tray already owns the built-in Wi-Fi/Bluetooth status icons; hovering those two icons opens the corresponding connected popup.
- [ ] Reconcile: **Settings row backgrounds:** locate and remove the repeated row backgrounds like Show Header, Power buttons and Preload Dashboard in the Abyss Settings tab and equivalent settings elsewhere. Preserve the enclosing panel's requested fill/opacity/blur; this does not authorize removing all panel backgrounds.
- [ ] Reconcile: **Persistent IPC editing target:** while editing an IPC position in Edit Abyss Layout, keep that target/example open continuously so its position is visible and adjustable, including when the real OSD's normal timeout would expire. Preserve Cancel/Done and safe preview controls.
- [ ] Reconcile: **Merged popups:** keep each popup's anchor position, shrink/reflow its content only within readable limits, and combine both contents without overlap. If both still cannot fit, close the old popup and present the new one. Closing uses a sliding animation, never an abrupt disappearance. Supersedes the previous inward/lateral tier relocation strategy.
- [ ] Reconcile: **Notification/Activity parity:** Activity Popup dimensions must match Notification Popup dimensions.
- [ ] Reconcile: **Traveling waves:** add controls for popup-driven waves; for example, Media Popup emerging sends a configurable strong/weak ripple in both directions along the Screen Edges. Waves must interact with waves traveling in the same or opposite direction, remain stable/bounded, respect shared effects/reduced-motion settings and return to idle sleep.
- [ ] Reconcile: **Dashboard correctness first:** resize the modules inside Dashboard (not merely its outer frame). Keep editing/add controls accessible after hiding every widget. Moving into occupied space must resolve safely or reject/clamp the move when no space exists; never scramble or overlap other widgets. Preserve saved layout, minimum sizes, cancel, undo/reset and both Dashboard/Overview routes.
- [ ] Reconcile: **Inherited feature parity:** restore Quick Notes, To-do and Timers at bottom left plus Notifications and Activities from mature Material content. Audit actual routes and enabled/hidden state before claiming a missing backend.
- [ ] Reconcile: **Ocean-scale waves:** raise safe amplitude/strength limits and make Calm/Balanced/Fluid/Deep presets visibly distinct. Show detailed wave controls only for Custom. Keep waves optional/default off, finite propagation, bounded stability and idle sleep. Audio spectrum must visibly drive the same Screen Edge and have a numeric strength readout.
- [ ] Reconcile: **One wave-strength control:** combine popup/Dashboard/IPC/Settings/etc. strength controls into one shared setting with migration from old per-surface keys. Adjust small control ripples sensibly using that shared setting.
- [ ] Reconcile: **Numeric settings:** sliders display their current value at the right, with meaningful units (% for opacity/scale, px for dimensions/blur, etc.), including audio strength. Reuse a common control instead of special-casing every page.
- [ ] Reconcile: **Surface placement/composition:** simultaneous popup/Dashboard/IPC/Settings bodies keep their positions and shrink/reflow readable contents when space permits; otherwise slide-close the older body and show the newer one. Fit/reflow each content allocation to avoid content overlap while merging outer geometry. Preserve focus, hit masks, close behavior and reopen state.
- [ ] Reconcile: **Edge/module sizing:** Screen Edge width also influences module sizing on that Edge, respecting shared Edge size and explicit per-module overrides. Keep the resting physical edge flat and thick, not permanently indented by modules.
- [ ] Reconcile: **Material presentation:** add opacity/blur controls for module/popup backgrounds. Remove thin borders around transparent, unfilled controls/results/context-menu rows; use coherent Abyss fills. Main Settings tabs have no border; subsidiary choice buttons have a wave shape and ripple on click, honoring shared wave/reduced-motion settings.
- [ ] Reconcile: **Sidebar/hot-corner parity:** inherit mature hot-corner hover settings; restore custom Sidebar width and height. Keep left/right reveal at the middle of physical edges and no sidebar icon modules. Remove the redundant Desktop & Layout Sidebars page; retain the Abyss route and shared feature preferences.
- [ ] Reconcile: **Settings navigation:** remove Easy mode and its toggle; there is one mode. Put one Edit Abyss Layout icon beside the lock at top right in the old mode-toggle location. Remove scattered duplicate editor buttons/pages. Abyss is a heading with focused tabs, not one giant tab containing every setting. Audit/merge overlapping Abyss and Desktop & Layout pages and similar settings. Fix heading removal, drag/drop persistence, duplicate Abyss headings and repeated generated More groups. Preserve custom navigation without losing settings.
- [ ] Reconcile: **Live Editor:** support representative popup/IPC previews and position edits, including near-corner joins. Smooth module dragging and resizing; avoid reloading heavy content or persisting the whole config every pointer event. Preserve guide/snapping/start-center-end alignment, per-output profiles, custom size and Cancel/Done.
- [ ] Reconcile: **Tray/app interaction:** hovering ordinary system-tray/application icons opens the actionable menu normally shown on right click, instead of a name tooltip. The built-in System Tray Wi-Fi/Bluetooth status icons are the deliberate exception: they hover-open the shell Wi-Fi/Bluetooth popup instead of an applet menu. Preserve dismissal, keyboard/pointer access and application actions.
- [ ] Reconcile: **Dock motion:** opening/closing a popup must retain Dock content size; remove shrinking/jitter while preserving normal autohide, previews and menu input.
- [ ] Reconcile: **Acceptance still open:** native motion/layout/gesture videos, multiple outputs/hotplug/suspend/fractional scaling, fullscreen/lock lifecycle and apples-to-apples CPU/RSS/frame evidence. Do not infer completion from solver idle sleep alone. Validate media idle resume/queue/Shuffle/Repeat/CAVA and ThinkFan/TLP hardware authorization. Recheck Settings active-indicator behavior and System Monitor widths/alignment. Keep lock/polkit/region-selection critical native hosts safe.

## Seven prioritized follow-ups from the historical checkpoint

These are checkpoint tasks and may have been superseded by newer `dev` commits; inspect current evidence and the latest optimization handoff before acting.

1. **Utilities Popup is source-complete but not runtime/hardware accepted.** Remote `dev` now contains the four lazy pages, focused embedded Monitor Arrangement, safe session Display Mode service, real PipeWire Sound Output selection, embedded Night Light/Anti Flashbang, bottom-center dots, horizontal swipe/keys and the Utilities launcher inside Quick Actions (the temporary standalone Edge module is retired by migration 055). Added contracts are `scripts/test-abyss-display-mode.py`, `scripts/test-abyss-utilities-popup.sh` and the updated popup-presentation regression. Run the canonical validator on the exact current SHA, then validate four-Edge placement, small/fractional outputs, real multi-output Extend/Primary/Second-only, hotplug during a transition, rollback after a failed Niri action, `wl-mirror` start/stop/disconnect, real PipeWire default-sink changes, and Night Light/Anti Flashbang input/scroll behavior. Do not claim the old 204/0/2 result covers these commits; do not fake Mirror.
2. **Anchored composition/focus is source-implemented through allocator + simultaneous StyledPopup ownership, but not accepted yet.** `2874ff988` retains anchors, partitions inward, reflows to readable minima and evicts only when necessary; `84a53ee4d` supports simultaneous mature StyledPopups; `f6b479bbe` separates reveal from eviction motion; `35fdf061d` makes newest focus-requesting popup arbitration/restoration match native StyledPopup OnDemand/Exclusive semantics. Do not revert to lateral relocation or single-active ownership. Next, qualify physical focus/input ordering for Settings/Dashboard/IPC/Sidebar/corner combinations on all edges and small/fractional outputs, including a newer popup forcing an older one to slide-close and later restore without losing draft/keyboard state. Generic native menus remain outside field allocation; Recording now has an Abyss field participant (qualification below).
3. **Dashboard/Editor coverage:** exercise packed restored layouts, every widget, hidden overflow/Add, viewport shrink, cancel/undo/reset and save/reopen with physical input. No scroll/growing workspace or neighbour scrambling. Verify real Calendar/Weather/Media/Resources/network examples, small/fractional Editor toolbar fit, joins, per-output/latest-config merges and persistent IPC targets. Measure drag frame cost; identity retention and a two-card video alone do not prove smoothness everywhere.
4. **Inherited interaction, wallpaper/hot-corner Overview and connectivity:** `4a25474f9` ports the mature cross-output Quick Notes editor lease into Abyss: editor ownership is compare-and-set by output, non-owner Notes/Notification Center corner triggers stay dormant while the lease is held, and monitor removal releases a stale owner. `55bb439a6` removes the retired Orbit hot-corner path, and `ffe46cbae` gives Niri Overview configured-corner priority over all remaining Abyss Quick Notes/Notification/Sidebar corner input on each output. The focused corner contract guards both source rules; real two-output keyboard/pointer focus is still an acceptance gate. Next qualify Sidebar custom dimensions/hot corners on multiple outputs. Validate both wallpaper paths: `4a2143b68` for field material alpha/blur/output-aware video stills, and `7f795a0e5` for Niri built-in Overview backdrop wallpaper from hot-corner/Mod+Tab activation. Confirm no gray compositor backdrop remains with the default enabled backdrop, and verify blur/dim, disabled-backdrop behavior, video and multiple outputs. Connectivity ownership is now the System Tray only: migration 053 removes old Wi-Fi/Bluetooth Edge placements and `6ef3d4756` makes the built-in status icons hover-open the mature connection popup. Live-check Wi-Fi→popup, Bluetooth→popup, transfer from icon into popup, switching between the two, same-icon re-entry, real association/pairing/device removal/service errors, plus ordinary tray DBus nested menus/app actions/keyboard access. Real backlight/DDC/night-light sensitivity, latency and failure behavior remain separate from fake-hardware tests.
5. **Settings/public design audit:** finish overlap/deduplication across Abyss, Desktop Panels and shared widgets; consolidate Dashboard card-opacity multiplying global content opacity. Audit all units, remaining result/media/Sidebar/native-menu fills, borderless navigation and active indicators, ordinary button wave faces and readable preset differences. Finish Orbital Weather appearance. Confirm the final public Abyss/Waffle-only migration, historic Material aliases and flat opaque/no-effects inheritance without deleting supported Waffle or dropping mature features.
6. **Whole repo efficiency/product gates:** debug each function with real diagnostics/images/recordings and comparable CPU/RSS/frame/GPU measurements. Solver-only speedup is not shell parity. Qualify multi-output/hotplug/suspend/fractional/transformed/fullscreen/lock/polkit/region-selection behavior, Waffle, media idle resume/queue/Shuffle/Repeat/CAVA and ThinkFan/TLP actual permissions. Investigate duplicate private helper/restart lifetime symptoms before assigning a product root cause; terminate only explicitly owned QA processes. Preserve unrelated Cargo.lock/captures/perf data.
7. **Final closure:** run canonical validation for new runtime changes on their exact local SHA, preserve failures, complete native acceptance and keep every requirement group above until proven. This checkpoint stops for usage, not completion. Continue in one agent on dev; the latest request authorizes normal checkpoint pushes to origin/dev before quota exhaustion, without branch, PR, force-push or stable changes. Update this README again before the next quota stop and explicitly record skipped/unrun validation. No daily automation should be created.

## Operating boundaries

- Preserve mature Material content and Waffle as a supported independent family.
- Do not confuse source-complete checkboxes with owner-live acceptance.
- The separate optimization program has its own [research checklist](OPTIMIZATION.md); never implement research findings without maintainer authorization.



## Maintainer product redesign — 2026-10-07

The maintainer authorized implementation of the following 21 requirements.
This resumes product work in one agent context. The earlier Dashboard draft and
its stop checkpoint remain historical evidence; reconcile current source before
reusing it. The maintainer has lifted the earlier automation exclusion; preserve concurrent work.
Use native/local regression tests and the canonical maintainer validator; record
exact source SHA and keep owner-session desktop acceptance separate.

The checkboxes below now mean **source implemented with focused local/native
contracts**, not owner-session visual/hardware acceptance. Canonical validation
passed on the exact source SHA recorded below; earlier owner-session gates
above remain open.

1. [x] Replace existing wallpaper picker presentations with one Caelestia-like
   selector rendered through Abyss connected surfaces; preserve selection,
   folders, format previews, output targeting and existing wallpaper backend.
2. [x] Use the current iNiR liquid wallpaper transition and its presented-frame
   priming/ownership guarantees; compare pinned upstream sources.
3. [x] Use the AI tab's providers/catalog/auth/request path for Aqua chat. The
   Aqua page adds only model selection and thinking effort for its AI controls.
4. [x] Configure physical Screen Edge width independently for top/right/bottom/
   left. Each Edge chooses thickness-only or inherited Edge/module sizing;
   preserve per-output editor drafts, explicit custom sizes and Cancel/Done.
5. [x] Present Abyss Panel Style before Waffle Style in Settings.
6. [x] Offer automatic Abyss and Aqua render quality following power profile;
   retain an explicit manual mode and react to profile changes without reload.
7. [x] Aqua has two render levels: Performance and Quality. Quality uses the
   former Balanced rendering; migrate old Balanced/Quality safely.
8. [x] Never automatically open Aqua chat input. Hover offers two cloud actions:
   Obsidian (energy/mood/schedule/etc.) and AI (chatbox). Daily mood/energy is
   chosen once; later bubbles show contextual read-only phrases. Schedule/todo
   reminders use appropriate popup notifications.
9. [x] Fix Clipboard History copied-image rendering, decoding and delegate
   lifecycle; exercise native binary ingress and actual image display.
10. [x] Aqua uses water portals for long-distance travel, with destination
    clearance, cancellation and bounded visual lifetime.
11. [x] Add rolling locomotion alongside existing walk/run behavior.
12. [x] Fix the clipped Aqua/quicksand boundary during Dock disappearance;
    exercise the real paint/input bounds and opening/closing frames.
13. [x] Rework Settings into compact grouped navigation with subsidiary pages,
    inspired by iOS; retain stable keys, migration, search and deep links.
14. [x] Traveling Abyss waves attenuate crest height continuously with distance,
    while preserving stability, interaction and idle sleep.
15. [x] Show Aqua's effective render quality in the Launcher popup.
16. [x] Rework the Onscreen Keyboard popup into Abyss connected presentation,
    preserving typing, dragging/pin and keyboard focus behavior.
17. [x] Add Obsidian auto-theming with vault/application and configuration path
    selection. Resolve the active theme and derive a palette mapping from the
    maintainer's current theme; preserve theme choice and unrelated config.
18. [x] Give third-party application integrations one Settings destination with
    focused subsidiary sections (including Obsidian theming).
19. [x] Place Notes add/remove actions beside the Notes indicator in one group.
20. [x] Repair Notes and Timers Screen Edge pin/hold-open ownership.
21. [x] Ensure Niri test/debug windows and helper backgrounds are dark before
    their first presented frame; retain isolated tests and owner-session scope.


### Implemented source and bounded validation

- **Wallpaper / style order (1, 2, 5):** `42e0855aa` consolidates picker routes,
  compatibility IPC and II/Waffle content into one connected carousel. Five
  rounded thumbnails, an enlarged center, extension-free captions and the lower
  search pill follow the supplemental image. `inirMelt` has presented-frame
  texture priming, final-request coalescing, reduced-motion/error fallback and
  one wallpaper owner. Pinned references: [Caelestia shell](https://github.com/caelestia-dots/shell)
  `6f7ce62b7a6ff9e37b66526065643ca6e9d65783` and
  [iNiR wallpaper](https://github.com/snowarch/iNiR/wiki/WALLPAPER)
  `db2233ce73e827373943aabd170f2ada8bf28471`. Native carousel/cache/melt and
  migration/mode contracts passed. Actual owner wallpaper/video/multi-output
  acceptance remains open.
- **Shared AI / companion interaction (3, 6, 7, 8, 15):** `8ab2d0914`,
  `6230f4ba7` and `e139c9c14` share the AI catalog/auth/transport while preserving
  separate chat state, bounded inference, cancel/timeouts and no automatic chat
  requests. Hover cloud actions, once-per-day check-in, read-only context and
  deterministic task/calendar reminders have owned native tests. Power policy
  and two render tiers have contract coverage; actual hardware profile changes
  and resource savings are not claimed.
- **Clipboard / Notes (9, 19, 20):** `e62791eb7`, `33b9afaab` and `2052838e2`
  cover binary image decode/dimensions/cache, actual Image.Ready rows and
  delegate reuse, grouped Notes actions and pinned Notes/Timers hold-open with
  editor ownership. Native fake-ingress/click/pin/reopen checks passed.
- **Edges / waves (4, 14):** `93319fa22` and `8df930178` add independent physical
  widths and per-Edge module inheritance, and continuous travel attenuation.
  Per-output/custom-size policy and finite/monotone solver contracts passed;
  owner recordings and editor acceptance across outputs/scales remain open.
- **Settings / integrations (13, 18):** `0c804b5ac` preserves existing numeric
  routes, search/deep links, hidden/custom order and Waffle while introducing
  parent/child navigation and one Integrations destination. Actual native
  parent/child/Back/search/edit navigation, standalone/Waffle opening and a
  missing initial Persistent state file passed. Loader status readback also
  removes a native loading binding loop.
- **OSK (16):** `4bbb3bbba` composes the keyboard within the existing output
  field, with per-output edge/position, bounded drag, pin and key release.
  Actual native key clicks used an owned fake ydotool backend; live typing into
  owner applications is still a separate acceptance gate.
- **Obsidian (17):** `5f257833f` adds vault config/application path controls and
  optional automatic coloring through one owned CSS snippet. Read-only owner
  inspection identified Border/Carbon Cyan's 14-stop ramp; shell background,
  text and accent follow its gradient weights. Active theme, fonts, unrelated
  preferences and snippets are preserved. Ten filesystem contracts and actual
  Settings automatic-apply/restore passed. No owner vault was changed during
  validation. [Obsidian CSS snippets](https://obsidian.md/help/snippets) supplies
  the supported theme-preserving application mechanism.
- **Water travel / immersion (10, 11, 12):** `7bb4fe9ad` adds two finite portal
  openings for long supported travel, a hidden midpoint transfer, live
  destination proof/cancellation and whole-rotation rolling. It preserves the
  Aqua/Octo cast and its `f0e70dd98` handoff. Immersion masks the bounded body
  capture with the same field geometry/waves/contact, including pulled and sink
  actions, instead of the old rectangular plane. Native portal cancellation,
  roll and curved alpha pixels on all four Edges plus Dock passed. The capture
  is released at rest; this visual feature is not a strict-lossless performance
  optimization or a measured RAM/FPS improvement.
- **Dark debug hosts (21):** `3f98729f9` sets an initial dark clear in 21 active
  Qt test hosts. Actual first-frame requests on the owned nested output passed
  for Window and FloatingWindow. Historical/frozen benchmark fixture blobs and
  consumed evidence were preserved.

### Canonical validation — 2026-10-07

Both runs used the default remote clean-clone mode of
`bash scripts/validate-maintainer-local.sh`. The failed log was preserved.

- **Initial FAIL:** `998239aaca31a33d270af278bc2a705679ff3aee`,
  368 PASS / 17 FAIL / 3 SKIP.
  Local log: `/tmp/hadalis-maintainer-validation-redesign-20261007.log`.
  SHA-256: `d4f74c2c01bb5bfd18859d78b233d4890f0832b497e3bd1e76579968490fe06f`.
- **Final PASS:** `3881227eb8a626d470d05db1d68cdb2be04dab2b`,
  386 PASS / 0 FAIL / 3 SKIP. The validated source tree remained clean.
  Local log: `/tmp/hadalis-maintainer-validation-redesign-rerun-20261007.log`.
  SHA-256: `f2a5af0f23988882978b84673fb57679436ce79d65b7e05259fca5f3734df57d`.
- **Skipped/deferred:** the manual Aqua perimeter test, the QML parser pass
  because the installed qmlformat Qt version could not be determined, and the
  dedicated Nix contract. Native Qt behavior tests did run; Nix remains in-tree
  and non-blocking.

The repair series preserves physical falls/jumps instead of substituting portals
(`a6032978d`), keeps the native curiosity fixture inside the existing 1–3 s UI
lease (`7358032e8`), fixes light-mode Launcher ink (`6e4027715`), restores shared
wallpaper loading and query/unload behavior (`4d712c01c`), and resolves moved
Services integration links before lazy navigation (`a200be741`). Behavior tests
exercise the current palettes, compact navigation, editor labels and batched
presets (`1d2c5fff4`, `77ea6a968`). `7cae1d951` preserves the original dependency
blobs of an inert historical rim proof; no consumed native benchmark was rerun.
`3881227eb` repairs documentation/task links. The complete canonical rerun also
passes notification timeout, copied clipboard images, Notes/Timers pinning,
Dashboard/Widget editing, wallpaper switching, shared AI/Obsidian, OSK, portal,
rolling/immersion, Waffle, install/update and package lifecycle contracts.

This PASS applies only to `3881227eb8a626d470d05db1d68cdb2be04dab2b`.
Later documentation commits and concurrent work are separate evidence, not a
new canonical qualification. Private logs remain local; this note records their
identity and results rather than publishing desktop diagnostics.

### Remaining acceptance

**SOURCE_COMPLETE / LOCAL_VALIDATED:** all 21 source requirement groups above.
**NOT_COMPLETE:** owner-session visual/hardware acceptance and comparable
whole-repository resource measurements.

Owner-session wallpaper application, populated connectivity lists, physical
keyboard input, multi-output/hotplug/fractional scaling, fullscreen/lock/focus,
live Obsidian reload and actual power transitions remain unqualified. Earlier
owner reports and whole-repo CPU/RAM/GPU/frame measurements above remain open.
No savings percentage or CI qualification is inferred from these source changes.

## Maintainer additions — 2026-10-07

The maintainer resumes implementation and reopens Dashboard acceptance. The
earlier 21-group source checklist does not close these newly reported problems.

- [x] **DSP presentation isolation:** a non-Flat EQ preset must keep playing
  uninterrupted when opening/reopening any popup, Sidebar or Dashboard. Trace
  DSP writes and analyzer restarts; presentation changes must not reapply a
  preset or reconstruct the audio pipeline.
- [x] **Finish Dashboard editing:** the Abyss editor controls belong above the
  Dashboard in the existing connected field. Entering edit mode must preserve
  the actual widget workspace and dimensions. Qualify packed/empty layouts,
  move/resize/collision, Add, undo/cancel/save and narrow outputs on the composed
  native surface, not only an isolated toolbar.
- [x] **Research-backed optimization:** implement the highest-value current
  candidates in `docs/optimization/STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md` after
  current-source verification and behavior parity. Prefer strict lossless. Any
  justified small tradeoff requires a measured large gain and one cumulative
  budget below 1%; independent small losses must not silently accumulate.
- [x] **Light warm readiness:** reduce unnecessary RAM/CPU/GPU work and heavy
  residency while preserving prompt open/reopen. Separate retained lightweight
  state from expensive running work; do not cold-start every surface on demand.
  Record lifecycle and latency evidence without extrapolating synthetic counts
  to whole-shell resource percentages.
- [x] **Individual Edge 0px:** each physical edge accepts zero width. Preserve
  independent per-edge edge-only/module-inheritance controls and per-output
  drafts. The new iRiS reference shows thin bare edges and local module bulges:
  a zero-width bare edge must not erase separately sized modules or their input.
- [x] **Audio Spectrum bounce and cost:** compare the old iNiR upstream wave,
  restore its responsive bounce, and remove avoidable analyzer/solver/render
  churn. Keep one shared analyzer, finite idle teardown and fast warm reopen.

Reference: `codex-clipboard-16fe5201-4a20-4c62-973e-553a2cafe08e.png`, supplied by
the maintainer; it illustrates edge/module geometry rather than authorizing
unrelated wallpaper or desktop changes. These additions are **SOURCE_COMPLETE / CANONICAL_PENDING**;
the existing exact-SHA validation result above remains historical evidence.

### Additional visual requirements — 2026-10-07

- [x] **Join local modules:** when an Edge uses edge-only width, provide a
  per-edge checkbox to join nearby module bulges, analogous to the existing
  nearby Edge/corner join. Keep distant groups separate and preserve module
  dimensions/input and per-output draft/cancel/save behavior.
- [x] **Compact OSK:** fit the connected keyboard body to its actual keys and
  controls; remove the large unused margin shown in the new screenshot while
  preserving drag/pin, typing focus and held-key release.
- [x] **Wallpaper search / hover surfaces:** replace the malformed search icon,
  remove the Caelestia `>wallpaper` prefix, remove search action borders and use
  Abyss presentation for retained hover tips. Audit shared hover surfaces;
  remove Orbital Weather's redundant tooltip because the orbit already displays
  the same information.

The three new screenshots illustrate current OSK margins, Wallpaper search and
bordered action controls. These additions extend the active work above.


### Maintainer additions — 2026-10-08

All checkboxes here identify implemented source and focused regression coverage.
They do not substitute for owner-session visual/audio/hardware acceptance.

- [x] Aqua and Octo keep the takeoff support orientation during Jump/Fly on
  top/right/bottom/left Edges; landing adopts the destination frame.
- [x] Place the shared Obsidian Vault Path first, followed by vault/application
  configuration paths and executable, in one Obsidian card above task options.
  Preserve the canonical Todo/Quick Notes path and clear the legacy override.
- [x] Keep Cheatsheet's feature and dimensions through the closing slide;
  an empty utility selector must not swap in Update. Explicit Update still opens.
- [x] Let the nearest visible module within 160px connect its local backing to
  a Screen Corner, with a real checkbox; preserve foreground dimensions/input.
- [x] Give edge-only module backing a 0–64px rounding override per Edge/output
  and an inherit action. The GPU field and immersion mask share record radii.
- [x] Expose CSS Snippet theming explicitly. Apply/disable owns only
  `.obsidian/snippets/99_Hadalis_Theme.css` and its enabled-snippet entry.
  Read the existing Carbon Cyan stops from Abyssal-Vault and Obsidian-Vault;
  exercise their appearance layouts on temporary copies, preserving theme,
  fonts, other snippets and user preferences.

### Source milestones and bounded evidence — 2026-10-08

- DSP isolation `3142861f9`: four real Bass reopen cycles generate zero DSP
  writes; genuine keyboard edits apply once and finish after closing. Fake owned
  helper/socket tests preserve the audio-pipeline contract; physical audio remains
  owner acceptance.
- Edge 0px `57c5fca52`, joins `8d99a6534`, corners/rounding `f28c3f508`:
  four-edge/output draft Cancel/Done and actual input/paint geometry pass.
  Real GPU captures prove inherit/default pixel parity, square/rounded contours
  and a painted corner weld. Wave/immersion packages are regenerated together.
- Dashboard editor `8f625d1f0`: 16 native route/edge/size cases, stable workspace,
  controls above the shared field, empty layouts, Undo/Cancel/Done and input release.
- Warm readiness `8ecb12748`: both real Dashboard routes reuse the same canvas
  and card objects during a bounded 1.2s cache. Hidden paint/input, media activity,
  sampling and sorting leases are off; expiry unloads the tree. Closed startup
  does not allocate a Dashboard. This is a lifecycle proof, not RSS/latency percent.
- Spectrum `000b5b9a1`: old iNiR signed carrier/phase bounce, one shared CAVA
  owner, 800ms idle grace, bounded warm capacity. Five 64-bar popup cycles cause
  zero analyzer restarts; only real capacity growth restarts once. Audio-only
  frames cause zero elastic-solver steps. Thirty frozen interaction traces /
  18,000 frames preserve all original physics samples exactly. Spectrum appearance
  is an authorized redesign, separate from strict-lossless physics optimization.
- OSK `faef460b0`, Wallpaper/tips `1518f95b2`: real content sizing, key/pin/drag
  lifecycle, search/navigation/actions, shared hover presentation and redundant
  Orbital Weather tooltip removal pass focused native contracts.
- Airborne orientation `6bf1338bd`: 16 real cast/edge/mode frames and landing.
  Utility slide `bf650f931`: actual output retains Cheatsheet, unloads after close
  and opens deliberate Update. Obsidian `1ab03d221`: native ordered path fields,
  shared-vault migration/clear plus 11 filesystem tests including both reference
  layouts. Owner vaults were inspected read-only, not rewritten by test fixtures.
- Music `9376fa34f`: no runtime consumer of the removed folder snapshot root;
  100 frozen/new snapshot cases preserve retained state and array identities.
  MPD payload/protocol and Songs folder derivation remain unchanged. JSON may
  still allocate the unused folders transiently; no RSS saving is asserted.
- Weather `63ea47423`: exact existing 72-sample tables reused only inside one
  binding evaluation, with fresh tables after resize/data/mode changes. 10,800
  arithmetic cases and 288 native QV4 reactive geometry cases match old values.
  Eight qualifying hours in one quadrant build 8 → 1 tables (87.5% fewer builds
  at this step). The liquid direct formula and uncached delegate fallback remain.

**CANONICAL_PENDING:** run the maintainer validator on the new committed exact
SHA, with direct strict QML parsing. The earlier `3881227eb` result remains
historical. **NOT_COMPLETE:** physical owner-session acceptance and comparable
whole-shell CPU/RAM/GPU/latency measurements. No approximation or stacked small
tradeoff was introduced by the two research candidates; intentional UI/audio
redesigns are recorded separately. No automation or timer was created.

## Maintainer additions and checkpoint — 2026-10-09

Earlier completed source groups do not close the new requirements below.

- [x] Source and live new-window readback: nested Niri debug windows stay
  unfocused (`86d976a2c`). Run focused checks relevant to the affected product.
- [x] Source/package extraction: TLP, Thinkfan and Obsidian are optional Hadalird integrations (final qualification below).
  Hadalird `e9922c53a261a9b47be7f521f6a64cff334dde27` is pushed on `main`:
  disposable selected workers/settings, verified immutable user package and
  separately requested privileged helpers. Native host tests use the actual
  package entry and private vault/hardware fixtures. Hadalis `d10fc5f87` provides
  bounded package discovery, default-off switches and typed reactive facades;
  absent, invalid and disabled packages fail closed. Migration `e793a4f80`
  retains explicitly selected old features and explicit new true/false choices
  without installing packages or touching system state (49 cases pass).
  `41bd19306` removes mandatory Arch helper/policy/schema installation and
  destructive removal hooks; actual stable/git package functions and private
  removal hooks pass. No optional integration has been deployed to the owner.
  Duplicate payloads/implementation tests and obsolete helper targets were
  removed in `e17c7edc0`. Remaining app-specific settings moved in `8ca68efe4`;
  source/package/update qualification is complete below. Owner hardware and
  actual installed desktop acceptance remain separate.
- [ ] Complete current Alis-Companion requirements using its own canonical task files.
  Companion source belongs to Alis-Companion, not Hadalis. Refetch `main` before work;
  concurrent source changes exist. Offline guards are bounded evidence only.
- [x] Source and focused validation: Local Music moves from Sidebar Left into a
  lazy Dashboard page (`6abf56328350b5871f1c626b2752d5e25d658539`). Centered round
  dots, native horizontal gestures, five columns, empty initial Results, genre
  or folder children, queue search/play/removal, selection, playlists, shared
  playback/volume, Lyrics and narrow panning are covered. Existing MPD settings
  and enabled/disabled intent are preserved by migration 059; cold UI restores
  lightweight browsing state and Edit Layout locks page switching.
- [x] Policy clarified by the maintainer: ONLY five-hour remaining below 3%
  stops work and schedules continuation after that window's reset +3 minutes.
  Weekly usage never triggers this policy. Do not consume reset credits.
  Five-hour readback reached 2% remaining: development and test jobs stopped.
  A single continuation heartbeat was scheduled for **2026-10-09 12:28:09 GMT+7**,
  exactly three minutes after that window's reset (12:25:09 GMT+7), and fired at
  12:28:36. New five-hour readback is 100% remaining; work resumed. Timer ID:
  `ti-p-t-c-hadalis-sau-reset-5-gi`. The weekly window was ignored.

### Validation and deployment boundaries

Focused native Music, migration/model, MPD/lyrics, English catalog/source and
Qt 6 QML parsing pass. Actual unfocused field input passes all 16 Dashboard
route/edge/size cases, preserving Undo/Cancel/Done. Fixture `d8b40c8a0` renders
its owned field before input; the earlier readiness failure also reproduced
on the pre-Music baseline. Both Dashboard routes pass bounded warm-cache checks:
no eager tree, hidden leases/input/paint off, immediate reuse, expiry at 1.2 s.
Focused logs are in the private validation state directory for 2026-10-09.

Hadalird's focused package/helper/Obsidian checks and real host fixture pass.
The current core Arch fixture executes both package functions with private
native-binary placeholders, verifies privileged payload absence and preserves
private TLP files on removal. It does not prove a compiled Arch transaction,
actual hardware behavior or final extraction completeness.
The non-VCS Arch source pin still predates optional host adapters; update that
reviewed snapshot only after the final candidate is qualified. The focused
package fixture explicitly uses current source, not the default archive pin.

Resume first with duplicate ownership and stale regression contracts:
`Makefile` helper targets, `scripts/test-local-distribution.sh`, the old core
TLP/helper/Obsidian implementation tests and runtime payload exclusions. Move
their implementation oracles to Hadalird; preserve generic host and shared
policy contracts. Inspect native Todo ownership before removing any backend.
Register the new host/migration/lifecycle checks in the canonical acceptance
path, then continue Alis-Companion's current task files from fresh `main`.

These checks are not a canonical PASS or post-update owner-session acceptance.
The canonical `4e3dcde86878fc1cad4957ca08434e0f837fb925` result remains historical:
405 checks, 404 PASS, one wallpaper hover failure, two deferred skips; log hash
`899ecdd804f5978bf7a0314f737d6d509107889cf68bd640532978840a6ba89f`.
The subsequent focused wallpaper-hover correction passes, but no full-suite
result is inferred for later source. Music and newer product changes have not
been deployed to the owner's desktop. Unrelated working-tree changes and
`docs/evidence/megaqml/` are preserved.

**NOT_COMPLETE:** optional Hadalird extraction, remaining Alis-Companion requirements,
final exact-source canonical validation, owner-session acceptance and comparable
whole-shell CPU/RAM/GPU/latency measurements. No resource percentages are claimed.

## Latest maintainer UI additions — 2026-10-09

All five additions below have source implementations and focused evidence;
owner-session acceptance and canonical validation of the combined candidate
remain open. These changes have been pushed on `dev` and are not yet deployed.

- [x] **Colors while browsing wallpapers** (`f845b07a8`): highlighted images
  preview the shell's shared palette through the existing native/Python color
  backend. Only one generator runs with the latest pending selection; closed
  pickers invalidate late results. Cancel restores independent copies of every
  color/mode, and a real theme update during browsing becomes the restore point.
  Configuration, active colors files and external application themes are not
  written by preview. External apply requests are deferred until preview ends.
  The cache has at most 32 palette entries, with image/stat/options/backend
  invalidation. Actual native Abyss field repaint, all-color restore, fast
  changes, failed generation, apply handoff and private external-hook behavior
  pass in `test-wallpaper-color-preview-runtime.py`; the actual worker/cache
  contract and existing native carousel also pass. No percentage saving is
  inferred from cache size or job ownership.
- [x] **Hover opening and automatic dismissal** (`68e4fa144`): StyledPopup
  observes its actual source Item across interactive descendants instead of
  relying on legacy MouseArea hover flags. Generic hover popups retain genuine
  editable text focus while the window is active; a clicked button's retained
  Qt focus no longer prevents idle dismissal. Native pointer entry, four
  reopen/transfer/exit cycles, explicit dismissal/reentry, disabled anchors,
  click-only requests and editable/read-only text pass. Both old nested-anchor
  hover failure and retained-focus dismissal failure were reproduced before
  their fixes. Live System Tray/menu/application behavior still needs acceptance.
- [x] **Dashboard Music refinement** (`c0a4f97a5`): Dashboard and Music slide
  horizontally with outgoing input/sampling disabled; editing sees the original
  workspace immediately even during a page transition. Music reuses Media
  Popup's compact EqualizerPanel and removes its second decorative CAVA owner.
  Lyrics hides when empty, expanding the remaining four columns; narrow layouts
  remain pannable. Native Music navigation/playback/queue/selection/volume/cold
  restore/edit lock and all 16 composed Dashboard editor cases pass. Four
  non-flat DSP reopen cycles pass with zero presentation-driven DSP writes.
  Actual audio, MPD idle resume and owner-session appearance remain separate.
- [x] **One Change Wallpaper action** (`2f82895ec`): remove the old Grid and
  Coverflow labels/actions from the public command list; retain the historic
  coverflow action ID as a compatibility route to the same selector. Actual
  GlobalActions search parity (Node 960 and QV4 220 cases), English catalog/source
  and Qt 6 parsing pass. Supported Waffle presentation/IPC is preserved.
- [x] **Modules at physical corners** (`45f456c6c`): remove the fixed 34 px
  placement inset from snap/geometry without rewriting persisted layouts.
  Pure boundary/snap/join cases cover both ends of all four Edges at small,
  normal and fractional dimensions; native field inherited/square/rounded
  contours and corner fill pass. Owner drag/drop at every corner remains open.

Hadalird `696fb5f` separately qualifies relocated helper/schema/config paths
and polkit authorization through staged package behavior; duplicate core
ownership and stale implementation-specific core tests still require cleanup.
The broad product task remains **NOT_COMPLETE**; no full canonical PASS,
installed-file update, hardware/owner acceptance or shell resource measurement
is asserted for these source milestones.

## Maintainer follow-up — 2026-10-09: Screen Edge hover and Music browser

Source-only fixes on Hadalis `dev` (do not cherry-pick to `stable` without qualified release acceptance):

- [x] Screen Edge module pointer hover is forwarded to the existing
  `StyledPopup` source lease (no second popup owner); clicking Weather no
  longer routes to Sidebar Right. The existing right-click Weather refresh,
  keyboard entry and pointer leave/retract remain routed through WeatherBar.
  Source commit `19dcbf7e59b6`.
- [x] Swap Dashboard Uptime and the header icon action group, keeping centered
  page dots. Source commit `19dcbf7e59b6`.
- [x] Add vertical WheelHandler navigation alongside horizontal page gestures;
  pass nested Music list wheel input through instead of stealing scrolling.
  Dashboard Edit mode locks navigation. First Escape exits Edit mode or restores
  the currently selected Genre/Folder filter, second Escape closes Dashboard;
  the unfiltered Dashboard tab closes on Escape. Source commits `1a67aaacb5b6`,
  `bd7d6c8c739d` and `9e7dadde66c9`.
- [x] Hide Folders while browsing a Genre and vice versa, restoring both on
  first Escape. Add explicit Play All and Play Selected controls to Results
  and split the existing Music playback/EQ column into Now Playing and a
  separate live Queue list (same MPD/Equalizer backends). Source commits
  `bd7d6c8c739d`, `ec1b98c1467e`. Adjust source/native regression
  expectations for the new column structure; never reduce existing assertions.
- [ ] **P0 exact-source qualification:** run the new
  `scripts/test-dashboard-music-browser-navigation-contract.py`, the
  affected native `test-dashboard-music-runtime.py` and
  `test-popup-anchor-hover-runtime.py`, plus canonical
  `bash scripts/validate-maintainer-local.sh` on the newest `dev` HEAD.
  Record PASS/FAIL/SKIP and distinguish missing CI dependencies from defects.
- [ ] **Owner desktop acceptance:** hover Weather/Clock/Resources/Battery/Media/
  Launcher/System Tray across supported Screen Edges, move pointer into popup
  and away, verify dismissal on pointer/focus loss and keyboard behavior;
  verify Weather left click never opens Sidebar Right. Test mouse/touchpad
  horizontal and vertical page switching without hijacking Music list scrolling;
  two-step Escape, Library/Queue/Results selection, Play All/Selected, EQ DSP
  and MPD continuity at normal/narrow/fractional scales.
- [ ] **Deployment:** source changes have **not** been applied to the installed
  owner desktop. No real Niri/Quickshell or physical audio acceptance is claimed.

## Maintainer follow-up — 2026-10-09: retry Screen Edge hover; tabbed Music library

This is a source-only continuation of the previous follow-up; it does **not**
imply the installed local desktop has received these patches.

- [x] Remove the imperative `moduleHoverActive` mirroring path. The existing
  `StyledPopup` now reacts to the live Screen Edge module hover and underlying
  `hoverTarget.containsMouse` / feature pointer state. One popup/controller
  owner remains; the hover/leave transfer hold and click/focus policy are kept.
  Source commit `3de9e30c41bf`. This is a defensively broadened detection
  path, not evidence that the owner-desktop cause was reproduced.
- [x] Replace separate Genre and Folders columns with one Library pane
  containing Genre/Folders tabs; preserve each source list, Folder Playlists,
  independent MPD backend and lightweight tab choice over cold UI. The first
  Escape clears a selected library drill-down; the second closes Dashboard.
  Source commit `4202d77a8d56`.
- [x] Reserve **57%** of the playback/queue height for Queue and 43% for
  Now playing/DSP. Now playing can scroll its own controls if the physical
  viewport is too short; no secondary EQ/CAVA backend was introduced. Rebalanced
  horizontal widths for Library / Results / Playback+Queue / optional Lyrics.
- [ ] Run updated static and real QML/Niri tests against the **latest** commit;
  validate hover **without any click** in Weather, Battery, Resources, Clock,
  Media, Launcher and tray, plus focus-loss dismissal, transfer, and
  per-output masks. Confirm actual installed source SHA matches tested SHA.
- [ ] Native Dashboard Music: tab switch, folder traversal and playlist
  preservation, first/second Escape, queue larger than controls, both scroll
  areas, narrow/wide/fractional DPI, and real MPD/EQ playback.
- [ ] Keep exact-source whole-suite failures and local Wayland acceptance open,
  and preserve unrelated Hadalird/Companion work and `stable`.

## Media/Queue hover rework — 2026-10-09

- [x] Reuse **actual `DashMedia`** component from Dashboard tab in Music
  page rather than a separate PlayerControl/EQ panel. Keep Dashboard tab's
  active MPRIS path unchanged; Music supplies its current LocalMusic MPD
  playback adapter and optional volume slider. No duplicated player/DSP
  implementation, no separate CAVA consumer.
- [x] Queue defaults to a **compact 22%** preview, leaving **78%** of vertical
  column space for the full Dashboard music module. Hover over the Queue body
  expands its share to **66% upwards** while the player shrinks to 34% and
  DashMedia suspends/hides its EQ/DSP. Pointer exit applies a 160 ms
  anti-flicker grace before collapsing and restoring EQ/DSP. Reset when
  presentation closes. Native test assertions added for both transitions.
- [ ] **Owner native acceptance:** run current-head `test-dashboard-music-runtime.py`,
  `test-dashboard-media-shared-player-contract.py`,
  `test-dashboard-music-browser-navigation-contract.py`,
  plus canonical validation. Inspect source-matched rendered images at
  small/normal/fractional sizes, pointer movement (including queue row hover),
  sustained DSP off during expansion, DSP recovery without reapplying EQ
  presets, idle/local MPD and global MPRIS playback.
- [ ] **Deployment:** the installed desktop has not been updated by these
  commits. This is source-implemented, not native-qualified or DONE; leave
  the installed/owner GPU+audio QA gate open.

This section supersedes the previous static 57% Queue default sizing decision.

Layout safety: on short monitors, Queue hover keeps at least 208 px of
player/volume space when available, bounded by the actual column height; the
nominal 34%/66% split applies when it does not clip transport controls.

## Music intrinsic sizing + conditional Screen Edge indicators — 2026-10-09

- [x] Bound Music Player/Queue combined column width to 315–380 px rather
  than proportionally consuming a third of wide dashboards. Give freed width
  to Results; keep library and optional lyrics proportional and retain
  horizontal panning on narrower windows.
- [x] Size the shared `DashMedia` card to its actual implicit media/player/
  volume/EQ height rather than 78% of the entire column. Queue owns the
  reclaimed vertical space. On hover the same EQ temporarily disappears,
  intrinsic height falls, and Queue naturally expands upward. On pointer
  leave the card/EQ returns; short-screen Queue keeps a 108 px minimum
  viewport before clipping the media card.
- [x] Timer and Shell Update now have explicit `contentAvailable` status
  that immediately releases their widths/visibility when idle. Physical
  Screen Edge geometry excludes zero measured extents entirely (including
  associated gaps and deformations) while Edit mode still exposes selectable
  placeholders. This applies with `edgeWidthAffectsModules=false` too.
- [ ] Native Niri/Quickshell check: verify measured/visible Module state
  transitions while timer starts/stops, pinned idle toggles, Update
  appears/disappears, both width-affects settings, multiple outputs and
  corner placement. Verify Queue hover, normal and short viewport, media
  artwork controls, and zero wasted vertical space before release.
- [ ] Exact-HEAD canonical and native test receipts required; no owner
  desktop acceptance or stable release is claimed.

## Niri Screen Edge hover-only-in-Editor fix — 2026-10-09

### Evidence and diagnosis boundary
- The Abyss full-output PanelWindow in `modules/abyss/AbyssPerimeter.qml`
  selected `WlrLayer.Top` in ordinary idle use, but `WlrLayer.Overlay`
  while `editorOpen` or `liquid.popupsOpen`. The same repo's mature
  `modules/bar/Bar.qml` already selects `Overlay` for Niri at idle.
- A hover-owned `StyledPopup` may therefore trigger a layer promotion just
  as it requests visibility. This is an implementation-supported source-level
  failure mechanism, **not** a proven physical compositor trace; a private
  Niri/owner-desktop reproduction is still required to confirm causality.
- The user observes that Edit Abyss Layout renders hover popups while normal
  mode does not. Earlier fixes only broadened individual hover-state detection;
  this cutover changes the **upstream compositor layer policy**, not another
  duplicated pointer handler.

### Source completed on dev
- [x] Keep Niri Abyss host at `WlrLayer.Overlay` while output is presented during ordinary idle and
  hover-owned popup lifecycle (not while fullscreen-hidden), so it cannot transition from Top to Overlay
  as `liquid.popupsOpen` toggles. Non-Niri layer behavior remains unchanged;
  `settingsNativeDialogOpen -> Bottom` and `PolkitService.active -> Top`
  retain priority, with existing `nativeInputMask`, dialog mask, utility
  mask and input-region ownership unchanged.
- [x] Add `scripts/test-abyss-niri-hover-layer-contract.py`: evaluate the
  **actual extracted QML layer expression** in Node across 14 scenarios
  (normal, popup, editor, overrides, Niri/non-Niri). Assert module input
  regions and `StyledPopup` source-hover ownership remain unchanged.

### Native acceptance is required before DONE
- [ ] On the installed **exact dev SHA**, Niri and Quickshell **stable**,
  log source SHA, timestamp and exit status. Capture normal vs editor
  hover at Clock, Weather, Battery, Resources, Media, Launcher, System Tray
  (plus Wi-Fi/Bluetooth/utilities generic hover), without clicking.
- [ ] For each open, move pointer from icon to interactive popup, then into
  workspace; verify it stays visible during transfer and closes after
  pointer/focus exit. Repeat enter/leave 4 times; test keyboard focus
  separately from hover and confirm Weather never opens Right Sidebar.
- [ ] Verify the compositor surface stays at Overlay before/during/after
  a hover popup on Niri, while the input mask captures only actual module/
  popup regions (no full-screen transparent pointer blocker). Check idle
  desktop click-through, multiple outputs, fullscreen, editor open/close,
  native Settings dialog and Polkit.
- [ ] Run the new source policy test, `test-popup-anchor-hover-runtime.py`,
  `test-abyss-bar-popup-autohide-contract.py`, `test-connected-input-lifecycle.py`
  and canonical maintainer validation. Separate CI missing dependency
  failures from native functional defects; no source-only pass is production
  acceptance.
- [ ] If the symptom persists, collect bounded evidence: actual mapped
  surface layer, module Region/input bounds, `AbyssBarModule.hovered`,
  `StyledPopup.moduleHoverActive`, `requestedVisible`,
  `_anchorReady`, `liquid.popupsOpen` and compositor pointer trace.
  Do not infer another cause or blindly add hover handlers.

**Status:** source-fix staged on `dev`, not installed, not native-qualified,
not eligible for stable promotion.

## 2026-10-09 — Normal Screen Edge hover / Hadalird migration boundary

**Evidence:** owner's Niri + Quickshell startup reports installed Git source
`999455dc0`; Edit Abyss Layout exposes hover but normal Screen Edges
still require clicks. Git checkout freshness does not guarantee the synced
`~/.config/quickshell/inir` QML tree has identical files.

**Changes on dev (not a claimed native fix):**
- [x] Native Mask: replace `AbyssBar.qml` Region `item: module` with
  bounded integer regions derived from actual `AbyssBarModule` x/y/width/
  height. Keep each region zero sized when module is hidden or disabled
  (Edit Mode already supplies independent handle regions). Invalidate
  `Region.changed()` on source geometry/availability transitions.
- [x] Add source and production QML guards for normal/edited hitbox
  bounds, fractional outward rounding, module drag position updates,
  and re-enabling normal mode without remounting.
- [x] Hadalis optional settings wrapper
  `modules/settings/ObsidianThemeSettings.qml` explicitly accepts
  `settingsTaskSection`; fixes IntegrationsConfig page 38 instantiation
  independent of whether Hadalird is installed. No Hadalird repo edits.
- [ ] **Do not mark DONE** until owner Niri/Quickshell verifies hover
  without clicking at Weather, Clock, Battery, Media, Resources, Launcher,
  tray and Wi-Fi/Bluetooth, with normal/edit toggles, focus/pointer exit
  dismissal, full-output transparency click-through, hot corners, multi-output
  and 125% DPI. Collect exact installed QML SHA / source checkout comparison.
- [ ] In case of continued failure, capture live normal/edit
  `bar.inputRegions` sizes/positions, hoverTarget MouseArea.containsMouse,
  StyledPopup `_anchorReady` / `requestedVisible` /
  `presentationActive`, and `liquid.popupSlots`, without assuming
  Hadalird caused a pointer-input failure.

## 2026-10-09 — Cold-start Abyss hover differs from Waffle → Abyss remount

**Owner observation:** after installing/updating Hadalis, initial Abyss module
hover does not show popups; switching **Abyss → Waffle → Abyss** restores
hover for every module. This is a more discriminating lifecycle clue than
the previous standalone pointer/layer tests; neither Hadalird nor input
mask has been proven responsible.

- [x] In `StyledPopup.qml`, force owner/window anchor rediscovery on
  hoverTarget/ancestor reparenting or controller changes, and during a
  **bounded 18×60 ms cold-mount window**; never poll permanently.
  Read-only derived `_liquidAnchor` and `_anchorWindow` now depend on an
  explicit hierarchy generation. Keep existing popup slots, focus behavior,
  click/hover rules and other compositor policy; no additional popup owner.
- [x] Add source contract and **private Niri pointer test** that creates
  StyledPopup before attachment to an Abyss-like parent, then mounts its
  parent/controller, verifies hover without a click, removes/restores
  controller like a family switch, and repeats open/close.
- [ ] Exact-source CI and native private Niri run; inspect failures rather
  than interpreting static token checks as end-to-end coverage.
- [ ] **Owner real desktop:** compare initial cold Abyss boot hover to
  Waffle→Abyss remount at the same installed SHA. Capture `_anchorReady`,
  `_liquidAnchor`, `_liquidController`, `requestedVisible`,
  `presentationActive`, `bar.inputRegions`, and `liquid.popupSlots`
  only if symptoms persist. Check unmodified input click-through, Weather
  no Sidebar Right, and hover dismissal on losing focus.
- [ ] Do not promote to `stable` or claim root cause proven until the
  owner reproduces a PASS on a fresh shell start.

The owner boot log also shows `shellEntryReady` at **T+1390 ms**, longer
than the bounded construction-time retry. Readiness signals now explicitly
restart a bounded anchor rescan when `shellEntryReady` or
`deferredPanelsReady` becomes true, covering asynchronous initial window
attachment without any permanent idle polling.

## 2026-10-09 18:41 +07 — Optional extraction and runtime qualification checkpoint

**Overall: NOT_COMPLETE.** Source milestones below are pushed to `dev`;
they have not been installed on the owner's desktop or promoted to `stable`.
Preserve the existing normal/cold hover acceptance items above.

- [x] `fb0ea45b0`: Local Music demand refresh follows Dashboard/Overview
  Music visibility. Private production-QML demand oracle and performance
  lifecycle checks passed; no owner MPD session was changed.
- [x] `e17c7edc0`: remove ten byte-identical optional payload duplicates and
  seven implementation tests from Core; Hadalird owns TLP/Thinkfan helpers,
  policies/schema and Obsidian/Todo/Zettelkasten workers. Core retains host
  facades/shared UI. Default staged install/update/uninstall prunes stale
  managed duplicates and preserves separately installed optional files.
  Ownership receipt: `~/.local/state/hadalis-validation/20261009/optional-ownership-source-parity.json`.
- [x] `751c1f294`: Core battery warning/suspend controls remain available
  without optional TLP. Native absent/disabled/selected/unload cases passed;
  old wrapper failed the same control-presence oracle.
- [x] Hadalird `d4bad57`: package owns native vault/config/application path
  editing and actual theme apply/restore coverage. Focused path and host
  lifecycle tests passed; Core navigation verifies missing integration stays
  dormant. No owner Obsidian vault/theme was edited.
- [x] `663e18909`, `8d693c5f9`: qualify current responsive Music columns,
  tabbed Library, shared Media/Queue/EQ, optional Lyrics, playback actions and
  slide transitions. Move obsolete optional implementation assertions into
  their owning package. Native bar auxiliary indicator tests passed.
- [x] `d227b961e`: defer cold anchor rescan beyond `_anchorWindow` binding
  evaluation. Existing native cold/remount test now passes without the old
  binding-loop warning. Full private pointer test also passed in
  `/tmp/hadalis-popup-hover-final-20261009.log`, including all four transfers,
  dismissal/reentry, click-only request and editable/read-only focus leases.
  Its process deadline covers the unchanged 22 frame/input steps; frame
  completion is asserted explicitly (QtTest `tryVerify` returns no value).
- [x] `85ecb55a3`: valid font during tooltip construction. Diagnostic clone
  located undefined `defaultFont` on actual tooltip text; Settings hierarchy
  native test now passes without font warnings. Live font binding is retained.
- [x] `6e8781e58`: hydrate notification history once, establish native ID
  offset before publishing cold ingress, and preserve active wrappers/timers/
  hover holds on subsequent persistence completions and history refresh.
  Native lifetime test passed with missing history and seeded ID 37;
  old source fails the explicit refresh identity/hold oracle at stage 18.
  Original canonical timeout failure was independently traced to owner
  fullscreen enabling GameMode suppression, not proven history corruption.
  The headless lifetime fixture now disables auto fullscreen detection and
  Niri animation control only in its private configuration.
- [x] `8e0a70628`: actual pointer navigation waits for rendered controls;
  Core hierarchy checks shared/legacy/deep links and optional absence.
  Dock/taskbar and embedded Settings shell tests now use private dark Niri
  plus private D-Bus. Owner nested-Niri rule is `open-focused false`.
  Dock/taskbar private test passed.

**Canonical receipt:** clean-clone `--current-repo --strict-qml` at exact
`751c1f2947eb622a3186b35b40fc9ccdebf22c5c` completed **FAIL: 300 PASS,
20 FAIL, 1 SKIP**. Log:
`~/.local/state/hadalis-validation/20261009/751c1f294-canonical.log`, SHA256
`3aac5cc044cbc7412912cc67078e48bafbbad4f514c1bf3ad8a323cc3669ace5`.
Most failures have focused fixes above; this is not a canonical PASS at the
new source. No CPU/RAM/GPU/FPS percentage or visual parity claim is justified.

**Continue in this order:**
1. Fix remaining focused native failures before another canonical run:
   embedded Settings fixture's >1000x700 assumption fails on private Niri's
   smaller output (`/tmp/hadalis-settings-embedded-private-20261009.log`);
   inspect actual host/card/output geometry rather than weakening layout.
   Editor runtime has delayed callbacks invoking destroyed StyledPopup
   methods; IPC corner's top join assertion also failed. Preserve workloads.
2. Run canonical validation on a clean clone of the new exact SHA after
   focused repairs. Keep owner cold boot, normal/edit/family switches,
   click-through/focus, multi-output and fractional scaling acceptance open.
3. Finish package qualification/source pin/update only after source qualifies.
   Continue Alis-Companion canonical TODOs while preserving concurrent
   `scripts/companion-export-cowork-native.py` edits. G0 dc4d5ecfe118 remains
   INCONCLUSIVE_CAPTURE_VARIANCE: offline receipt/PNG analysis only, no replay
   and no relaxed RGBA. Five varying states' changed pixels are translucent;
   cause remains unestablished. Do not modify shader tiers on this hypothesis.
4. Continue highest-value strict-lossless work from the optimization audit;
   avoid speculative cumulative quality trades. Do not modify unrelated
   `docs/evidence/megaqml/` or owner Companion preference.

Only five-hour remaining below 3% may stop work and schedule this thread
after that window's reset +3 minutes. Weekly usage never triggers a timer.

## 2026-10-09 — Native cold-start pointer loss narrowed to full AbyssPerimeter construction

**Owner evidence:** `hadalis-abyss-perimeter-remount-20261009-212258.tar.gz`
collected at exact `e8dab310f6145b3aa8a447f10c464b905fa8154b`.
Installed QML matched source; before remount the 16 hover samples showed
`barHover=false`, `fieldReady=true`, `barVisible=true`,
`barInputRegionCount=12`. `abyssHostProbe.remountPerimeter` returned
`skipped=false`, and the diagnostic critical-host Loader was re-created
450 ms later with `shellEntryReady=true` and `deferredPanelsReady=true`.
After remount, `barHover=true`, and owner confirmed popup was visible,
**without switching to Waffle**.

Previous owner-controlled experiments on the same class of failure:
`Region.changed()`, equivalent `PanelWindow.mask` identity swap, and
`PanelWindow.visible` unmap/remap did **not** restore hover. These
experiments reject superficial mask refresh and simple visibility toggles;
they do *not* prove a particular Quickshell/Niri internal defect.

- [x] Source remedy on `dev`: gate initial production Perimeter Loader until
  `GlobalStates.deferredPanelsReady` plus a one-shot 150 ms settle. Avoid
  unnecessary destroy/recreate and preserve all current geometry/input masks.
- [x] Source contract asserts post-deferred gate and critical IO import.
- [ ] **Required live cold boot:** install exact SHA, restart into Abyss (do not
  switch family), hover Clock/Weather; record `abyssHostProbe.status` and
  `abyssHoverProbe.snapshot`. Repeat across a second clean restart.
- [ ] If still broken, compare first mounted Perimeter native layer order to
  re-created Perimeter, then test a native creation dependency in a full host
  fixture. Do not claim a generic Wayland or Qt bug without tracing.
- [ ] Do not call the hover bug DONE or promote `stable` before owner native PASS.

### 2026-10-09 — Cold-start delayed-first-mount native FAIL and proven subtree-remount remedy

Owner's exact-source `hadalis-abyss-cold-acceptance-20261009-213449.tar.gz`
on `c17390e2b455`: HEAD and installed source match; host status
`perimeterLoaded=true`, `initialMountReady=true`,
`shellEntryReady=true`, `deferredPanelsReady=true`.
All 24 samples have `fieldReady=true`, valid 12 input regions,
`barHover=false`, and no popup requests. The deferred+150ms initial-mount
change is **not sufficient** and must not be called a successful fix.

The distinct owner controlled experiment
`hadalis-abyss-perimeter-remount-20261009-212258.tar.gz` showed that
destroying/recreating **only the entire AbyssPerimeter subtree** (without
Waffle) changed native hover and popup presentation from 0/16 to 16/16.
RefreshMask, equivalent mask identity swap, and PanelWindow visibility
remap all failed independently. This supports a first-native-generation
lifecycle issue, not the internal cause of that lifecycle bug.

- [x] Candidate exact-known-remedy: once at a cold direct-Abyss Niri boot,
  wait for actual frame readiness on the presented output(s), let it settle
  600 ms, then reuse the existing 450ms host destruction/recreation path.
  Root records cold family and clears pending on family switch; warm Waffle
  switches, other compositors and non-presented outputs must not loop.
- [x] Extend source regression contract for gate/one-shot and proper imports.
- [ ] **Owner real Niri acceptance**: restart on exact updated SHA directly
  into Abyss at least two times, hover Clock/Weather without switching family,
  capture `abyssHostProbe.status` and `abyssHoverProbe.snapshot`; inspect
  whether coldRecreated becomes true and 24/24 hover+popup requests succeed.
- [ ] Check multi-output/fullscreen and quick family switch lifecycle; do not
  call DONE until owner captures real cold input success. No claim about
  Quickshell or Niri upstream root cause without protocol-level trace.

### 2026-10-09 — Direct Abyss cold-start native acceptance #1: PASS (408e4df2)

**Owner artifact:** `hadalis-abyss-cold-acceptance-20261009-215143.tar.gz`.
Repo and installed runtime match exact `408e4df281469ee0bd314d3f6e95c108ec0ac34b`.
Shell log states `[Abyss] Cold Niri perimeter re-created after first native frame`.
Native critical host: `coldRecreated=true`,
`coldRecreatePending=false`, `perimeterLoaded=true`,
`perimeterActive=true`, `diagnosticUnmounted=false`,
`nativeFirstFramesReady=true`, `shellEntryReady=true`,
`deferredPanelsReady=true`.

During the owner's 24 consecutive Clock hover samples (~6.5 seconds), all
24/24 had `barHover=true`, the Clock module's `hovered=true`,
`popup.requestedVisible=true`, `popup.presentationActive=true`,
`fieldReady=true`, and 12 positive bar input regions.
Owner answered `cold_hover_popupSeen=true`; no script exceptions.
Abyss worked **without a Waffle family switch** in this boot.

**Status: two owner-submitted native cold-start acceptances PASS
(2/2), not a 100% cure / not DONE.**
- [x] Exact-SHA owner cold restart #1: 24/24 hover, requested and presented
  (`408e4df281469ee0bd314d3f6e95c108ec0ac34b`).
- [x] Owner cold-start acceptance #2: 24/24 hover, requested and presented
  (`5e5cf274d05bf30730836dfce1b7dcd22b7372dc`, same QML as #1).
  Two separate capture archives; the scripts record host flags and timestamps,
  not native process identity, so treat the restart itself as guided owner
  execution rather than independently authenticated process evidence.
- [ ] Multiple independent cold logins, quick family changes, multi-output,
  fullscreen/hotplug/suspend-resume, if applicable, before production claim.
- [ ] Long-term: investigate upstream first native generation loss and whether
  the guarded one-time subtree rebuild can eventually be removed. It is an
  evidenced workaround; protocol-level cause is still unknown.

**CI check on SHA `408e4df2`:** Documentation and Nix succeeded;
canonical CI reports 300 PASS / 20 FAIL / 2 SKIP. One failure in
`scripts/test-abyss-niri-hover-layer-contract.py` was a stale static mask
expression assertion left behind by the earlier diagnostic `swapMask`
addition, not a native hover rejection. Update this test to require both
input branches to retain the shaped mask. Other observed failures are largely
unavailable native Quickshell/Niri, Python Pillow, or ImageMagick in the CI
runner; do not describe the entire run as green.

### 2026-10-09 — Direct Abyss cold-start native acceptance #2: PASS (5e5cf274)

**Owner artifact:** `hadalis-abyss-cold-acceptance-20261009-220221.tar.gz`.
On exact repository SHA `5e5cf274d05bf30730836dfce1b7dcd22b7372dc`,
installed source matched all 3 tested QML files:
`ShellAbyssCriticalPanels.qml`, `AbyssPerimeter.qml`, `AbyssBar.qml`.
This commit differs from `408e4df2` only in regression test/TODO files.

`abyssHostProbe.status` confirmed:
`family=abyss`, `perimeterLoaded=true`, `perimeterActive=true`,
`diagnosticUnmounted=false`, `shellEntryReady=true`,
`deferredPanelsReady=true`, `initialMountReady=true`,
`nativeFirstFramesReady=true`, `coldRecreatePending=false`,
`coldRecreated=true`. In 24/24 samples of live Clock hover
(2026-10-09 22:02:27–22:02:33 local UTC+7), **all** had
`barHover=true`, Clock module `hovered=true`,
`popup.requestedVisible=true`, `popup.presentationActive=true`,
`liquidPopupsOpen=true`, `fieldReady=true`,
and the normal 12 bar input regions. Owner confirmed
`cold_hover_popupSeen=true`; diagnostic script errors `[]`.

**Native acceptance tally:** 2/2 separate owner capture sessions PASS.
Owner was instructed to use distinct `inir restart` cold boot sessions
without switching Waffle; the reports do not independently encode the
previous Quickshell PID/boot identity. It is fair to call 2/2 owner-driven
acceptance samples PASS; it is **not** proof of all startup sequences or of
the underlying Wayland root cause.

**CI on `5e5cf274`:** Nix PASS, canonical validator
321 checks = 301 PASS / 19 FAIL / 2 SKIP. The previously stale
`test-abyss-niri-hover-layer-contract.py` now **PASSES**.
Remaining observed CI failures include unavailable `qs`/private Niri,
Pillow, and ImageMagick in the runner, not a reported regression in
the cold hover static contract. Full CI is not green.

- [x] User-visible original Clock hover/popup regression: mitigated across
  2 owner-run cold acceptance sessions on Niri without family switching.
- [ ] Before closure as broadly stable: run extended normal/edit/family
  transitions; multiple outputs and focus/fullscreen if applicable;
  avoid startup flicker and timing races. Do not merge to `stable`.
- [ ] Longer-term replace the one-shot full Perimeter recreation with an
  upstream-correct native input lifecycle solution when protocol evidence
  identifies it. The workaround is evidence-backed, the root cause unknown.

### 2026-10-09 — Active Window footprint + desktop context menu in retracted Edge gaps

Owner request on `dev`:
1. Active Window must bound its horizontal natural span and expose a
   configurable maximum like Media. Prior `AbyssBarModule.naturalSpan` had
   fixed `Math.min(220, Math.max(60, titleWidth))`; the classic bar also
   hardcoded 220.
2. When `Width affects modules = OFF`, right-clicking the *bare desktop*
   in gaps of the retracted Screen Edge can produce a context popup that
   briefly appears then vanishes.

- [x] Add `bar.activeWindow.width` (default 220 px; range 120–420) to
  typed config, defaults, Settings > Bar > Modules, and shared ActiveWindow
  maxContentWidth, consumed by classic and Abyss. Do not change vertical
  Active Window footprint. Text still elides and natural width never exceeds cap.
- [x] Guard desktop ContextMenu's `closeOnHoverLostAfterEntered` against
  transient hover during its entrance animation. Only a genuine hovered
  settled menu arms its existing 700ms auto-close timer. Preserve
  outside-desktop left-click, item selection and Escape paths. This is a
  source-grounded candidate, NOT yet owner-native validated.
- [x] Add focused source/contract regression tests.
- [ ] Native acceptance (owner, after `dev` install): test multiple long active
  titles at 120/220/420 px in Abyss; adjust config in Bar Modules without
  changing family; ensure classic bar still fits.
- [ ] Native menu acceptance: test right-click *in Edge gaps* with each of
  top/left/bottom/right `Width affects modules OFF`; verify no transient
  disappearance, selectable items, Escape, desktop left-click close, and
  normal mode with width affecting modules ON. If still reproducible, trace
  `popupWasHovered`, `entranceSettled`, and LayerWindow ordering, rather
  than speculating about compositor focus.
- [ ] Keep stable untouched; no DONE until live menu verification.


### 2026-10-09 — Follow-up: stable desktop right-click lifecycle

The source-only entrance-hover guard in `3a3d806acca` is not
sufficient to guarantee the menu persists: even after animation settles,
an animated popup can intersect the stationary cursor, then report
hover-loss 700ms later. Unlike preview menus, the desktop menu is
**right-click-initiated** and should remain until explicit dismissal.

- [x] On `dev`, set `closeOnHoverLost: false` only on bare desktop
  `desktopContextMenu` and `desktopItemContextMenu`.
  Existing left-click on desktop, selecting any action and Escape remain
  dismissal paths. Shared `ContextMenu` default hover behavior is unchanged.
- [x] Focused source regression asserts both menu instances opt out,
  shared timer still available to other consumers, and dismissal actions.
- [ ] Live Niri acceptance at retracted Screen Edge gaps with
  `Width affects modules OFF`: top/bottom/left/right where applicable;
  verify menu stays visible at least 2s without mouse movement, menu
  items remain clickable, Escape and desktop left-click dismiss.
- [ ] Native Active Window setting: validate max width 120/220/420 and
  ordinary text elision on Abyss and classic Bar. No stable branch changes.


## 2026-10-10 — Hadalird extraction: source/package qualification complete

The maintainer prioritized completing Hadalird before other product work.
**This extraction milestone is complete at source/package scope; the broader
Hadalis/Alis-Companion task remains NOT_COMPLETE.**

- [x] Hadalird `642ba4e`, `1e4496e`, `4186832` own the remaining Classic and
  Waffle TLP row/editor implementations, Obsidian Todo/Quick Notes settings,
  and Thinkfan per-profile settings. Version 0.2.0 retains host API 1 and
  includes every settings entrypoint in the immutable hashed package.
  Shared Core widgets/configuration/services remain in Hadalis.
- [x] Hadalis `8ca68efe423223bdf40059155748c53b38200de2` retains only selected
  loaders, stable navigation/input contracts, service facades and generic
  Battery/internal Todo fallback. Missing/incomplete/disabled packages do
  not construct owned controls. Closing and reopening Waffle preserves its
  category/filter. Removing Obsidian leaves a user action to restore the
  preserved internal Todo store without clearing saved source paths.
- [x] Implementation guards moved to Hadalird; Core keeps host/interface,
  shared UI and lifecycle coverage. Owned deferred worker/editor callbacks
  stop when their disposable QML context retires. Native unload previously
  exposed invalid-context/editor creation warnings and a delayed refresh
  TypeError; the same workload now passes. Owned task fields also avoid the
  observed Material TextField implicit-width loop.
- [x] Clean source-pair qualification: Hadalird
  `418683285d28c5b2a673ffc387f96047aca4306b` with Hadalis `8ca68efe4` passes
  all 19 `make test` entries, including 16-file Qt 6.12 parsing, actual
  Classic/Waffle/Obsidian/Thinkfan settings lifecycle, synthetic vault actions
  and injected status-only helper receipts. Test host discovery works from
  sibling checkouts without a maintainer-specific absolute path.
  Receipt/log: `~/.local/state/hadalis-validation/20261009/hadalird-ui-pair.json`
  and `hadalird-ui-pair-tests.log` in the same directory.
- [x] Actual committed-package upgrade from Hadalird `d4bad57` to `1e4496e`:
  27 payload files match source, Core accepts the complete 0.2 package,
  reinstall is idempotent, older release bytes are retained, and uninstall
  removes only the owned link while preserving release/user fixture data.
  `4186832` changes test-host discovery/documentation only; runtime payload
  bytes are unchanged. Receipt: `hadalird-exact-upgrade-receipt.json` in the
  same validation directory. Default install/uninstall does not install
  privileged helpers or alter system services/policies.
- [x] Canonical maintainer validator on a clean clone of **exact `8ca68efe4`**:
  **323 PASS, 0 FAIL, 1 SKIP** (Nix deferred/non-blocking), Qt 6.12 parser PASS.
  Log: `~/.local/state/hadalis-validation/20261009/8ca68efe4-canonical.log`.
  This is local canonical evidence, not GitHub CI or owner hardware acceptance.
- [x] Non-VCS Arch metadata now pins the qualified `8ca68efe4` payload
  (`pkgrel=14`); regenerated `.SRCINFO` also includes already-declared Fcitx
  dependencies. Packaging/update/metadata and actual private stable/git
  package/removal-hook contracts pass. No actual Arch build was claimed.
- [ ] Owner desktop/hardware acceptance for selected TLP/Thinkfan/Obsidian
  remains open. No package was installed into the owner session, no vault,
  fan/charge policy or system service was changed, and `stable` is untouched.

Other fixes qualified before this milestone: guarded StyledPopup retirement
(`8f8fcc60c`), private IPC corner fixture (`48d01a54b`), exact embedded Settings
host geometry (`ccc6c4308`), and Edge Editor intrinsic toolbar depth with small
viewport scrolling (`53af215df`). The real private four-edge editor input
workload and a 360px-high logical host pass; the prior source fails the full
control clipping oracle. Canonical `53af215df` separately passed 323 checks.
Owner layout/normal-hover/multi-output/focus acceptance remains separate.

Next: continue Alis-Companion canonical TODOs and strict-lossless work. Keep owner
Companion disabled, preserve concurrent work and unrelated
`docs/evidence/megaqml/`, and keep G0 `dc4d5ecfe118` offline-only:
INCONCLUSIVE_CAPTURE_VARIANCE, no replay or weaker RGBA. Only five-hour
remaining below 3% triggers a stop/checkpoint/push and a one-shot resume at
that window's reset +3 minutes; weekly limits never trigger scheduling.


## Hadalird UX — Hadalis-managed optional package (2026-10-10)

**Maintainer requirement:** Users must not need to clone Hadalird or run its
installer manually. Hadalis owns installation, update checks, version status,
uninstall and rollback from Settings > Integrations. The opt-in package is
still owned by Hadalird; Hadalis retains the verified discovery and loader.
No stable branch or running user system is modified by source work.

**Source implementation for qualification (not owner desktop acceptance):**

- Hadalis `scripts/hadalird-manager.py` fetches only the official
  `llocphann/Hadalird` revision when a user clicks a package action.
  Source identity is an immutable 40-digit Git SHA, downloaded archive entries
  are bounded and explicitly allowlisted, and host API/entrypoint compatibility
  and payload hashes are verified before an atomic user-owned release switch.
  No fetched installer script executes, and there is no idle network polling.
- `services/Hadalird.qml` owns explicit package actions and unloads disposable
  integration workers before changing the release link. It reads the result,
  refreshes package discovery, reports errors and preserves stored selection
  preferences. It does not auto-enable integrations.
- `modules/settings/IntegrationsConfig.qml` supplies Install, Check updates,
  Update, Restore previous and confirm-Remove controls. Removal retains
  user data and previous versions. `scripts/test-hadalird-manager.py` proves
  the bounded offline package lifecycle with synthetic archive fixtures.
- **System-helper boundary now implemented for Arch packaging (native
  acceptance pending):** Hadalis owns the root-installed
  `/usr/libexec/inir-hadalird-system-provision` gateway and its dedicated
  `auth_admin` Polkit action, installed only by Hadalis' trusted distro
  package. The unprivileged Settings action requests Polkit authorization
  explicitly, then the gateway copies **only** five approved Hadalird 0.2
  helper/policy/schema payloads whose SHA-256 values are pinned in the trusted
  gateway. It verifies the exact content from a single buffered read, rejects
  unrelated system files or symlinks, and tracks root-owned installation
  state to permit owner-safe uninstall. No downloaded script runs as root.
  No TLP/Thinkfan service, charge policy, fan state or owner config is modified.
  New Hadalird helper versions require an audited Hadalis trust-pin update,
  not silent privileged auto-upgrade. Nothing is enabled without explicit
  user choice.
- `scripts/test-hadalird-system-provision.py` uses private filesystem
  fixtures to test byte pins, foreign files, symlink refusal, Polkit policy
  and remove safety. It performs no real privileged operation. The manager
  regression exercises status/install/remove with injected synthetic receipts.
  Other distro packaging remains open beyond Arch; do not imply that the
  root gateway is already present on every installation.

**Acceptance still required:** current-source Python offline test, Qt/QML
parse, canonical validator, actual Settings install/check/update/reopen/
rollback/uninstall on an installed compatible Hadalis and exact Hadalird SHA,
disconnected/offline error handling, input/focus and retained-user-data proof.
No automatic background update, no owner/hardware test, and no stable
promotion should be claimed before those receipts are recorded.

## 2026-10-10 — Owner video: Music, popup connections and remaining follow-up

Owner reference: `/home/llocphann/Videos/2026-10-10_00.19.58.mp4`
(24.9 seconds). Read the recording offline; private Niri tests stayed
unfocused. **Overall NOT_COMPLETE; source fixes below are not owner desktop
or audio-output acceptance.**

- [x] `b373d0f4a`: Queue playback in Dashboard used nonexistent
  `LocalMusic.playTrackAt`; both Results and the secondary Queue now use the
  actual `jumpTo` API. The previous test double invented that missing method;
  its corrected API reproduced the old TypeError and filtered-queue failure,
  then passed the same navigation/queue/selection/volume workload after repair.
  Receipts: `/tmp/hadalis-music-queue-api-{red,green}-20261010.log`.
- [x] `4c1acc088`: Queue is bottom-anchored and follows one Player-height
  animation clock, expanding upwards without moving its bottom or Player
  origin. Genre/Folders support single, Ctrl toggle and Shift range selection;
  unions retain track identity/order and avoid duplicate playback. Lightweight
  browser state retains multi selection across UI unload/recreation and imports
  older single-selection state. Pure model and real private Dashboard tests
  passed, including opening/closing frame samples, both source lists, Play All,
  empty selection and cold restoration. Receipt:
  `/tmp/hadalis-music-bottom-multi-20261010.log`.
- [x] `be8902259598d60f74945f19d0eb0b5d6adf2430`: Styled and generic Abyss
  hover popups include their tangent-bounded connection to the owning inner
  Edge in input/hover, measured from current clipped geometry. Other bodies
  retain the content-only input contract. Four-rim private Qt pointer dwell,
  handoff, exit, explicit dismissal, disabled source and click-only policy passed;
  SDF/geometry and pyramid motion regressions passed. Source `4c1acc088` fails
  the connection dwell oracle with equivalent module-clearance geometry.
  Receipts: `/tmp/hadalis-popup-connection-green-20261010.log` and
  `/tmp/hadalis-popup-connection-old-source-red-20261010.log`. The earlier
  fixed-coordinate trial used an incorrect requested window extent; retain it
  as harness evidence, not the old-source regression authority. Actual owner
  mask/focus/click-through and multi-output acceptance remain open.

Fresh sync preserved concurrent Hadalird package-management source `4737960f5`
and merged it with these fixes as `9ebaa5e0c6e959850ecf1cf2989983251708a714`,
then pushed `dev`. Its offline manager fixture passed; actual optional UI
qualification is tracked separately. Alis-Companion `main` documentation commit
`732136ef65bb3c84d9339207210c955759a85b76` was reviewed and pushed without
staging its concurrent native-authoring edits. Hadalird source/package extraction
remains qualified at `418683285d28c5b2a673ffc387f96047aca4306b`; do not redo it.

Canonical validation launched on the clean exact pre-merge source **be8902259**:
`/home/llocphann/.local/state/hadalis-validation/20261010/abyss-connection-canonical.log`
and `/tmp/hadalis-current-canonical-20261010-console.log`. It was explicitly
stopped at the five-hour budget threshold (exit 143): 217 completed checks
reported PASS, check 218 did not finish and no aggregate result was emitted.
**STOPPED / NOT_COMPLETE**, never canonical PASS. The maintainer subsequently
stopped local work, then explicitly resumed all Hadalis tasks. Run canonical on
a clean clone of the final runtime SHA after affected-source qualification.

Remaining owner requirements, in this same active list:

- [ ] Reproduce Clock/other module → Weather rapid hover and the overlapping
  visual tail seen near 5–8 seconds. Use actual Weather content and the production
  popup slots/pyramid/clips; distinguish overlapping close/reveal geometry from
  a stale semantic/input lease. The installed Weather content matches source,
  but installed Dashboard Music and Perimeter bytes differ; no owner installation,
  reload or preference change was performed by this repair.
- [x] Add persistent images to generic Quick Notes (paste/import and visible
  preview), retaining existing note/editor/tab autosave. Optional **Hadalird**
  owns Obsidian attachment placement/export, using the vault's configured auto
  attachment location. Transfer referenced images with notes, preserve originals
  until successful completion and qualify Unicode/collisions/failure/restart with
  synthetic notes/vaults; do not read personal note stores as test fixtures.
- [x] Source and focused fixture: rework Recording popup/controls for Abyss surface presentation, reusing
  RecorderStatus and existing stop/audio/drag/auto-hide behavior with one owner.
  Keep ii/Waffle supported. Test injected recording state; do not stop an owner
  recording as a fixture action.
- [ ] Qualify Music on actual MPD/audio. Read-only status observed stopped,
  empty queue and enabled PipeWire output; MPD logs also contain FLAC decoding
  failures and Bad song index. These are separate evidence from the repaired
  QML API; do not claim audible playback PASS or alter music files. Surface
  backend failures in Dashboard and diagnose queue/decoder races with a bounded
  synthetic MPD fixture before another runtime repair.
- [ ] Qualify the merged Hadalird Settings install/check/update/rollback/remove
  lifecycle and exact final Core SHA; do not infer its native acceptance from
  offline manager PASS or from be8902259's canonical run.

Continue Alis-Companion's two canonical TODOs and strict-lossless work after these
owner defects. Preserve `docs/evidence/megaqml/` and Alis-Companion's concurrent files;
Companion stays disabled, G0 `dc4d5ecfe118` remains offline-only. Only the
five-hour window remaining **below** 3% triggers checkpoint/push and a one-shot
resume at that window's reset +3 minutes; weekly usage never triggers it.

### Remaining Hadalis-only acceptance (no Alis-Companion work)

- [x] Focused GitHub Actions offline qualification for exact
  `a570d13f993cfd07d5fff68d528598e6c034963d`: the standalone
  `Hadalird offline contracts` workflow run
  https://github.com/llocphann/Hadalis/actions/runs/37975587559 completed
  **SUCCESS** on user-package manager, private-root Polkit helper simulator,
  existing host removal safety and Arch PKGBUILD shell syntax. The earlier
  `9be1e9c1402055bb16b2aba97a6fa140a5b3a314` focused run also passed.
  The latest `a570d13` additionally bounds ignored tar archive entries.
- [ ] Run canonical maintainer validation and strict Qt 6/QML parser on an
  exact committed `dev` SHA, then owner-native Niri Settings/Polkit testing.
  GitHub-hosted canonical CI may still fail required private Qt/Niri or
  missing-runner-dependency checks; an offline PASS is not native acceptance.
- [ ] Real Arch install/update to deploy the root-owned Polkit gateway and
  policy. Then exercise Settings > Integrations install/update/rollback/remove,
  popup focus, offline/GitHub errors, and root helper consent/cancellation.
  Do not perform a privileged helper install without the owner's consent.
- [ ] Qualify actual selected TLP/Thinkfan/Obsidian behavior with the owner
  desktop after the user explicitly enables it. Preserve TLP/Thinkfan hardware
  defaults, charging config, running services and Obsidian vault data.
- [ ] Add trusted system-package provisioning for supported non-Arch
  distributions rather than using `sudo` on a user-owned checkout. No
  cross-distro support claim before packaging/Polkit checks.
- [ ] Continue unrelated outstanding Hadalis `dev` fixes and strict-lossless
  parity/measurement gates separately; leave Alis-Companion and `stable` untouched.


## 2026-10-10 — Owner Hadalird installed: Obsidian wrapper width and CPU probes

Owner screenshots confirm Hadalird **0.2.0** installed at source SHA
`418683285d28c5b2a673ffc387f96047aca4306b` through
Hadalis Settings; Niri/Quickshell no longer reports `page 38` load
failure. This is real owner **package-install discovery evidence**, not
endorsement of the settings UI or privileged helper functionality.

- [x] Hadalis `bcbccaf43f2823217848ab3f26a3d5fcd22e24c7`: fix
  `modules/settings/ObsidianThemeSettings.qml` wrapper missing
  `QtQuick.Layouts` / `Layout.fillWidth: true`; in the Settings
  `ColumnLayout` the wrapper could have zero width yet preserve a large
  deferred card implicit height, consistent with the almost-empty owner
  Obsidian panel. Add focused offline regression; focused GitHub Actions
  workflow **PASS** at
  https://github.com/llocphann/Hadalis/actions/runs/37979594747 .
  Disable the **Install system helpers** button until the root-owned
  Hadalis provisioner exists. The missing provisioner is not a missing
  Hadalird user package, and source updates alone cannot install it.
- [x] External owner Hadalird package `aa49d0556e62db5f7358db96abac9d1626e5135e`
  resolves the owner log's repeated missing Intel pstate status reads on
  a non-Intel driver; gate both Intel/AMD `FileView.path` reads by the
  active CPU scaling driver, preserve passive-mode detection, unload on
  driver change and preserve capability-clearing behavior. Exact
  source-level contract GitHub Actions **PASS**:
  https://github.com/llocphann/Hadalird/actions/runs/37979900616 .
  The Hadalird package SHA changed; it must be updated through Hadalis'
  own **Check updates → Update** UI to load the fix.
- [ ] Owner Niri live acceptance: refresh Hadalis `dev` at least
  `bcbccaf`, open **Settings → Integrations → Obsidian**, ensure
  visible normal-width vault/path/theme controls and no blank/overlapping
  panel; update Hadalird through Settings; confirm no repeated Intel
  sysfs FileView warning after reload. Record exact Hadalis and
  Hadalird SHAs. No vault writes, TLP/Thinkfan changes or automatic
  helper provision requested.
- [ ] The trusted root-owned Arch **system provisioner** remains absent
  in this owner session. Resolve through an audited Hadalis distro
  package install/upgrade with explicit authentication, and test
  Polkit cancellation/consent. Never copy user-downloaded helpers as root
  or equate an active preference toggle with working hardware access.
- [ ] Unrelated `qt.svg` warning is not diagnosed by these logs; obtain
  its source before applying unrelated asset changes.

## 2026-10-10 — Hadalird helper gateway missing on owner system

Owner Settings screenshot confirms that Hadalird 0.2.0 is installed and
"Check helper status" reports the **Hadalis system Polkit gateway missing**.
The inactive "Install system helpers" button is an intentional fail-closed
safeguard, not an uninstall failure. The available screenshot does not
prove whether an Arch shell package is installed on the owner machine.

**Source/package parity repair:** frozen `inir-shell` PKGBUILD and
`.SRCINFO` previously pinned `8ca68ef`, predating the gateway. Pin an
immutable source commit that contains the trusted gateway and policy; advance
`pkgrel` to force a package rebuild. Keep the `inir-shell-git` recipe
and `.SRCINFO` in sync. Extend release/package contracts to verify the
pinned source contains both root files, not just that current `dev` does.
No other repository or `stable` branch is changed.

- [ ] Owner acceptance: determine whether `pacman -Q inir-shell` or
  `inir-shell-git` owns the shell on this machine. `inir update` alone
  cannot install root-owned package files.
- [ ] Install/rebuild only a trusted, reviewed Hadalis system package with
  explicit administrator consent. Verify root gateway/policy are package
  owned and read-only to the regular user, then check status in Settings.
  Do not auto-run a remote installer as root or self-elevate during QML
  startup. Hardware actions remain opt-in.
- [ ] Keep Obsidian and user-level Hadalird functional if the gateway is
  absent. Integration toggles describe stored preferences, not verified
  availability of a hardware backend. No fan/charge policy changed by
  this package metadata repair.

## 2026-10-10 — Arch repo-copy gateway distribution

Owner `inir status`: installed version 2.29.3; `dev` source
`fb84c8f`; install mode `repo-copy`, update strategy `repo-setup`.
Neither `inir-shell` nor `inir-shell-git` is installed, which explains
why package-owned Polkit files are absent. The source-install flow must
remain supported; do not require switching shell install methods.

Hadalis adds a standalone gateway package action from Settings,
separate from the user-space Hadalird release. It prepares an Arch package
from fixed-digest Hadalis system files, verifies its contents, and only
requests administrator authorization after explicit user confirmation.
Gateway registration does not automatically start TLP, change fan policy,
alter charge limits, or install the remaining hardware helpers.

- [ ] Obtain focused offline CI receipts for package build simulation,
  modified-file rejection, Settings layout and manager action routing.
- [ ] Verify actual build, native authentication, installed package
  ownership, package removal and error/cancel flows on the owner's Arch
  desktop. No claim of root/package installation without owner evidence.
- [ ] Keep existing `repo-copy` shell and Obsidian user package intact.

### 2026-10-10 — Owner gateway install reported missing receipt

Owner Settings reported `System gateway package did not return an operation receipt` after an explicit Arch standalone package install request. Source inspection found a definite post-transaction exception in `scripts/hadalird-system-package.py`: `system_state()` referenced unbound variable `p` in the root-file inventory. It could crash **after** successful `pacman -U`, losing the JSON receipt and leaving user-visible state stale. Fixed state reconciliation; failures now surface bounded child stderr/exit status. Offline CI: https://github.com/llocphann/Hadalis/actions/runs/37985086814 **PASS** for `66425869`. UI adds a read-only **Check Arch gateway status** action so a package already installed can be rediscovered without rerunning a privileged installer.

- [ ] Owner native read-only check `pacman -Q inir-hadalird-gateway` or Settings gateway status, record installed/not-installed and file ownership. **Do not automatically retry installation:** earlier pacman transaction may have succeeded despite missing receipt.
- [ ] Only if package is missing, user explicitly retries via Settings after updating Hadalis. Capture stdout/stderr/exit status on failure, distinguish makepkg, Polkit authentication, and pacman errors. Never auto-modify TLP/Thinkfan hardware state.

### 2026-10-10 — Hadalird Settings simplification and Polkit foreground

Owner confirms Hadalird 0.2.0 and the system helpers are ready but the
Settings card is text-heavy, privileged reinstallation is confusing, and
the Polkit dialog can be hidden behind the Abyss Settings surface.

Hadalis `dev` repair scope only (Alis-Companion and stable untouched):
- Keep only short Gateway/Helpers status and primary `Install helpers`
  or `Reinstall helpers` (same explicit, integrity-checked, idempotent
  helper install), plus Update/Refresh. Move destructive package/helper
  controls and gateway maintenance into collapsed Advanced.
- A single explicit `helpers-ensure` action checks a valid Hadalird
  install, installs the trusted Arch gateway if absent, then performs
  a verified privileged helper install; each Polkit operation retains
  independent authorization. Do not remove existing helpers or change
  TLP/Thinkfan behavior during reinstall. Refusal of gateway auth blocks
  subsequent helper installation.
- Native rail/focus Settings surfaces yield to Polkit by using
  `WlrLayer.Bottom` instead of `WlrLayer.Top` while authentication
  is pending. Abyss embedded Settings temporarily closes before auth
  and reopens on completion; standalone Settings lowers its toplevel.
  The Settings surface must never hold exclusive keyboard focus
  while the authorization dialog is active.
- [ ] Record exact-SHA offline CI, Qt native parse and live Niri Polkit
  focused-front authentication, cancellation, double-auth initial install,
  idempotent reinstall and restored Settings page, including any standalone
  or Waffle Settings host variants. Do not claim native acceptance based
  solely on offline checks.


### 2026-10-10 — Hadalird package/helper state reconciliation

The owner confirmed the system-helper UI displayed **ready** and offered
`Remove system helpers` before the Settings simplification. This screenshot
is status evidence; it does not by itself prove native Polkit layering,
hardware behavior, individual file ownership or per-operation rollback.

Continuation after `3729ca5a5`:
- [x] Add a read-only `system-status` operation to the Hadalis manager,
  combining independent trusted gateway availability and helper status.
  Handle systems where a full distro package owns the gateway but the
  standalone Arch package does not exist; non-Arch package-query failure
  does not break the passive helper status.
- [x] Refresh the local status once on Hadalis service startup, from the
  compact Settings **Refresh** action and after any completed/failed/
  cancelled privileged operation; never infer final state from a missing
  receipt or require the user to retry an indeterminate installation.
  The status collector ignores results while an explicit package manager
  action is busy, preventing an old read from overwriting the new state.
- [x] Make the QML operation deadline exceed the maximum serialized
  gateway build/authorization and helper-authorization budgets; do not
  label an authorized second stage timed out while the child continues.
  Focused synthetic test covers normal and full-package-provisioner
  discovery, non-Arch gateway query, startup status wiring, and absence
  of implicit privileged installs.
- [ ] Owner-native Niri/Quickshell confirmation that Polkit appears above
  all Settings presentations and returns focus after success/cancel,
  and that gateway/helper state is accurate after restart and rollback.
- [ ] Canonical maintainer validation on an exact `dev` SHA with native
  Qt/QML runtime parser and user-session acceptance remains separately open.

### 2026-10-10 — Dashboard MPD error visibility

Owner's prior read-only MPD diagnostics mentioned a stopped/empty queue,
FLAC decoder errors and `Bad song index`. The existing `LocalMusic`
reducer erroneously cleared its `error` field whenever the socket was
connected, even when MPD `status.error` reported a decoder failure.

- [x] Feed the MPD server's `status.error` into the existing `LocalMusic.error`
  signal, preserving its state and removing it only on a later healthy
  status response. Dashboard Music displays a slim error banner using
  that same backend and offers a read-only status retry, rather than
  introducing a second MPD owner. Hidden/no-error UI retains the original
  full-size Music columns.
- [x] Add a simulated MPD error/healthy/disconnect fixture exercising the
  real QML payload reducer via a JS VM, and a native Dashboard fixture with
  injected decoder error, expected banner visibility and unchanged queue.
- [ ] **Not audio/decoder acceptance:** Confirm the actual owner MPD logs,
  queue mutation race, codec/output capabilities and audible playback
  without altering music files, queue or output routing during tests.
  A DISPLAYED decoder error is a diagnosis surface, not a codec fix.

### 2026-10-10 — Continued owner follow-ups: Weather and Quick Notes images

The maintainer explicitly resumed all Hadalis work. The earlier local resume
automation was deleted on the stop request; it was not restarted on resumption.
The established five-hour-only below-3% checkpoint policy still applies to a
future budget exhaustion. Keep Alis-Companion and unrelated native-authoring files
untouched while completing the current Hadalis requirements.

- **Weather qualification:** `test-weather-popup-handoff-runtime.py` exercises
  actual ClockCalendarPopup and WeatherPopup with stable slots, pyramid motion,
  source/body pointer ownership and connection input on top/bottom/left/right.
  Rapid hover reversal, content transfer and final exit passed: 1,148 sampled
  geometry states in `/tmp/hadalis-weather-handoff-bounded-20261010.log`.
  Weather production code was unchanged by this test; do not claim a new
  source fix or owner-session visual PASS. Early fixture attempts lacked
  unfocused frame synchronization and used an exit point inside a side popup;
  those are not authoritative product RED receipts. The corrected workload
  preserves the owner's non-focus debug policy. The video overlap gate remains
  open until installation identity and first/repeated visual handoff agree.
- **Hadalis `add29d6f8`:** shared Notepad paste, Ctrl+V and context-menu Paste
  route binary images through a bounded helper; image import and a virtualized
  preview strip are shared by Quick Notes hosts. Save original image bytes in
  the state attachment store and persist local Markdown links through the
  existing note autosave. Resolve asynchronous receipts against the original
  note ID; selection replacement preserves changes made after the snapshot.
  Generic Notes work without Hadalird. An older package reports an explicit
  update requirement for image export.
- **Hadalird `b0c975a7f40bdf531012be326bc728f5c014b696` (0.2.1):** optional
  Obsidian owns image export for both capture and Notepad migration. Read the
  chosen vault-config `app.json` attachment location (vault root, current note
  folder, a subfolder or specified vault folder), copy and verify bytes, replace
  source links with vault-relative links, preserve collisions and all drafts.
  The folder behavior follows [Obsidian attachment settings](https://obsidian.md/help/attachments).
  Package installation remains opt-in; no owner vault/hardware state changed.
- **Focused receipts:** six synthetic Core filesystem/clipboard tests, eight
  optional image-export tests and nine existing Zettelkasten tests passed.
  Actual shared Notes QML preview/import, delayed tab-switch receipt, selection,
  saved restart and existing Notes/Timers pin tests passed. The actual optional
  worker and Core facade captured one synthetic image into a custom-config
  Unicode vault and preserved the source/draft. Logs:
  `/tmp/hadalis-notes-image-selection-20261010.log`,
  `/tmp/hadalis-notes-pin-images-20261010.log`,
  `/tmp/hadalird-note-image-host-20261010.log`.
  Qt 6 parsed all 16 Hadalird QML files; scoped package installation contract
  passed. Clipboard data in these new tests was injected, not read from the
  owner's clipboard. Canonical and owner-native acceptance remain separate.

Next: connected Recording controls using the existing field/RecorderStatus,
then actual MPD queue/decoder qualification and the latest exact-SHA canonical
validator. Continue strict-lossless parity and measured resource work; retain
G0 `dc4d5ecfe118` as offline-only INCONCLUSIVE_CAPTURE_VARIANCE and make no
CPU/RAM/GPU percentage claim from these functional tests.

### 2026-10-10 — Connected Recording controls

- [x] Recording controls now participate in the existing Abyss field, allocator
  and input mask. Share the timer, Stop, microphone/system mute and collapse
  controls with the retained ii/Waffle native presenter. The primary output
  owns one control set; idle Recording allocates neither controls nor a window.
  The Abyss path creates no additional native Recording window. Drag/release
  selects the nearest edge; timer width stays stable across minute boundaries.
- [x] Keep pointer ownership on the drawn connection. Auto-hide removes body
  input after two seconds and retains only a 36-by-12-pixel edge recovery target
  while recording. Lock/unmapped output removes that target. Hidden controls
  stop their pulse animation. Existing `recordingOsd` IPC actions remain intact.
- [x] Actual native QML fixture passed on all four edges, including audio-mode
  visibility, real pointer controls, connection dwell, auto-hide/recovery, drag,
  Stop callback, idle/secondary-output allocation and retained ii/Waffle snap.
  Receipt: `/tmp/hadalis-recording-ipc-20261010.log`. Six affected QML files
  parsed with Qt 6; IPC registry check passed (64 targets). Private Niri stayed
  unfocused; the fixture injected recorder/audio callbacks and did not start an
  owner recording or alter system mute state.
- [ ] Owner desktop appearance and an actual recording/stop remain separate
  acceptance. Canonical validation must apply to the final committed source.

### 2026-10-10 — MPD mutation ordering and identical-payload recovery

- [x] Serialize queue writes, single/bulk enqueue, saved-playlist writes and
  transport commands in the order requested. Previously detached Play could
  overtake a pending queue's Clear/Add, producing `Bad song index` or letting
  the queue's initial Play override the newer selection. Idle MPRIS transport
  remains available; while a mutation is pending, transport joins the same FIFO.
- [x] Surface command ACK failures without disconnecting a healthy MPD server.
  Reusing an identical queue/bulk/playlist payload no longer waits forever for a
  FileView `saved` signal that a no-op write does not emit. Reuse only confirmed
  disk writes; reset failed-write cache so an identical retry really persists
  the payload. A failed write preserves the MPD queue and releases the FIFO.
- [x] Actual LocalMusic QML/Process/FileView test passed against an isolated MPD
  protocol server with both Python and the existing local Rust compatibility
  backend. It covers delayed Clear/Add versus Play, visible ACK, healthy
  connection, action ordering, repeated queue/bulk/playlist payloads and failed
  payload/identical retry. Receipt: `/tmp/hadalis-music-all-mutations-20261010.log`.
  The Rust binary is an existing build, not a new source-build qualification.
- [x] A separate real private MPD decoded generated WAV/FLAC, then passed Queue,
  Stop/idle/Play, Pause, Shuffle/Repeat and recovery from an indexed track whose
  header was deliberately corrupted. Receipt:
  `/tmp/hadalis-music-private-open-error-20261010.log`. It used only a null audio
  output and synthetic files. Real QML demand events, MPD/source contracts,
  Dashboard diagnostic reducer/model and Qt 6 parse also passed.
- [ ] Owner audible PipeWire playback and the owner's previously reported FLAC
  files remain separate. No owner queue, output routing or music bytes were
  changed by these tests. Validate the final exact SHA canonically.
