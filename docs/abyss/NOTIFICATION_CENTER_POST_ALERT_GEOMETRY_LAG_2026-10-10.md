# Notification Center: post-notification Popup size/placement jump and lag

**Status:** OPEN — owner-reported, visually confirmed, native cause undetermined.  
**Date:** 2026-10-10, owner recording named \`2026-10-10_21.55.09.mp4\`.  
**Scope:** Alis / Niri / Abyss connected Notification Center Popup, on \`dev\` only.  
**Task authority:** [ISSUES.md](../../to-do/cloud-bot/ISSUES.md); this is technical research, not a separate checklist.  
**Related but distinct:** [Unresolved Screen Edge hover issue](POPUP_EDGE_HOVER_UNRESOLVED_2026-10-10.md). Do not conflate premature hover dismissal with incorrect popup geometry.

## Owner report and direct video evidence

Owner: after a notification arrives, opening the Notification Edgebar causes the Popup to **lag and display at the wrong size**.

Source: user-supplied video \`2026-10-10_21.55.09.mp4\`, 1920 × 1200, 30 fps, 263 frames, ~8.73 seconds. **The source video was shared in ChatGPT and is not a committed repository fixture.** Local agent should request the original recording if it is not available locally. The following is a visual reading of sampled frames, NOT Qt timestamps/IPC diagnostics:

| Relative video time | Observable |
| --- | --- |
| ~0.7–1.5 s | A small new notification/recording toast is visible at the top area. |
| ~1.7–2.5 s | The Notification Center's black connected surface appears unusually tall and narrow on the right, spanning from very near the top of the display almost to its bottom. Notification content is arranged at the top of this elongated panel. |
| ~2.7–2.9 s | The surface changes shape/extent noticeably; the Popup presentation shifts toward the bottom-right. |
| ~2.9–4.1 s | The Notifications/Activity tabbed Popup is now in a much shorter bottom-right footprint, distinctly different from the earlier tall one. The apparent snap/change is visually significant, not merely a slow moving pointer. |
| ~4.3–4.7 s | Notification items are cleared (the Popup displays an empty-state indicator) while the Popup remains visible. Do not assume this content action is the initiating cause of the earlier geometry jump. |
| ~5–5.6 s | The Notification Center closes; other popup interactions occur later in the recording. |

Exact pixel edges, Qt frame rate, memory/CPU/GPU utilization, effective user config and pointer route were NOT measured from this recording. In particular, **do not call this a proven 420×560 → other-size regression**: those are the repository defaults, not independently verified current user settings.

## What the checked-in source supports (not a root-cause finding)

Examined \`dev\` HEAD \`2a830cc22a364dc284fe780db9ddf1fda9f42d3a\` after the user's previously requested hover-experiment revert.

- \`modules/notificationCenter/NotificationCenterPopup.qml\`: requested width \`max(320,min(760, popupWidth ?? 420))\`; requested height \`max(260,min(900,popupHeight ?? 560))\`. \`contentRoot.implicitWidth/implicitHeight\` subtract twice \`_contentPadding\`, and its notification \`Loader\` is conditional on \`presentationActive && selectedTab === 0\`.
- \`modules/abyss/AbyssPerimeter.qml\`: \`styledPopupHosts\` uses \`embeddedItem: hostedPopup?.contentItem\`, derives \`span\` and \`depth\` from the embedded item's implicit dimensions and the current \`edge\`, uses \`stackPolicy: "pyramid"\`, \`animatePresentation: true\`, \`externalProgress\`, \`joinedEdge\`, \`positionAlong\` and a computed \`anchorBounds\`. On \`popupEntryChanged\`, it resets retained placement and pyramid motion.
- \`modules/abyss/AbyssBodyHost.qml\`: placement and visual placement are separate. By default \`placementCanResize\` and \`animatePlacementChanges\` are enabled for normal bodies; \`minimumSpan/minimumDepth\` can be smaller than requested; it uses \`retainedPlacement\`, \`pyramid\` origin/reveal and its \`contentFrame\` clips contents. These are valid features, not demonstrated bugs.
- \`modules/abyss/looks/AbyssBodyPlacement.js\`: allocator can shrink, stack inward or evict participants based on conflicts. Possible peer occupancy includes toast or other surface participants, but **no evidence yet** identifies an actual participant collision during the video.
- \`modules/abyss/looks/AbyssGeometry.js\`: \`joinCorner\` can extend the visual union to an adjacent physical edge if within a bounded gap. Incorrect \`edge\`/\`joinedEdge\` input could alter the silhouette; the video does not establish this.
- \`modules/notificationCenter/NotificationCenterContent.qml\`: actual notification list, compact mode, tabs, placeholder and conditional search; asynchronous changes may affect child layout, although the parent declares requested implicit dimensions.

The video therefore indicates a **size/placement transition defect that requires native tracing**. It does NOT prove that the notification toast, list Loader, SDF shader, geometry allocator, pyramid motion or hover bridge is the causal component. Avoid applying another speculative source patch.

## 2026-10-10 Cloud AI source fix: toast-to-center role conflict

**State: implemented on dev, focused source regression PASS, native Niri and owner acceptance PENDING.**

Deeper source analysis established a deterministic conflict in `modules/abyss/AbyssPerimeter.qml`: there are **two distinct hosts**, the transient `notification` AbyssBodyHost and the dedicated `NotificationCenterPopup` rehosted in the `styledPopupHosts` Repeater. In the original code, opening the dedicated Center set `GlobalStates.notificationCenterOpen=true`. This **closed** the transient `notification` host (`open` has an explicit negative condition on that global), but simultaneously changed this closing host's `centerOnOutput` expression to true, forcing new `presentationKind`, `edge`, `contentKind`, `along`, `obstacles` and nearly full-output `contentHeight`. The old `AbyssBodyHost.visualResident` keeps its closing record visible until reveal progress reaches zero. Therefore a closing banner could visibly change into an oversized Center-shaped right column while the separately-owned actual Center was opening.

For reproducible arithmetic only: executing the **original source expression** with 1200px output height, 16px top/bottom insets, 14px padding and 130px banner content gave height **158px** before `notificationCenterOpen`, versus **1096px** immediately after it. These are illustrative inputs, not the owner's verified configuration. The real user video is consistent with this branch switch, but without per-frame native receipts it does not independently establish it as the sole cause of all observed lag.

**Runtime corrections committed:**

- `6f0321dec1c688d25cddcd5728ee0f2a2276f8b0` — make the transient `notification` host strictly own **only banner content**. Fix its kind to `notifications`, and its `contentKind` to `popup`. Continue deriving its own width, height, location and obstacles from banner settings alone. Preserve the existing `!GlobalStates.notificationCenterOpen` close predicate and the separately-owned `NotificationCenterPopup`. No new input mask, hover bridge, edge policy or global timer.
- `98415d0c43d3145920265f8f6ccdccdf79368273` — turn on existing `AbyssBodyHost.stableContentSize` for this banner, keeping icon/text layout at target dimensions behind its reveal clip during retract. This is targeted at reflow/jitter during the closing visual transition, **not proof of frame pacing improvement**.
- `63952a5be606e5db1cdb5c581da76856d8bd5127` and `644da2ae9d870e33b9cb3fe98013bba1adfbb1cb` — add and correct the focused `scripts/test-abyss-notification-transition.mjs` behavioral source regression, evaluating actual committed QML expressions across a new banner, Center opening, no/multiple banners, alternative Edge positions and customized Center dimensions. The latest test passes **32/32** in an isolated JavaScript execution using mocked QML dependencies.
- `279fc68bca020d853a4f6011b9810f3ea08a3e96` — make this test an explicit gate in the canonical `scripts/validate-maintainer-local.sh`.

The disappearance of the center Loader from the banner codepath also prevents that host from instantiating a second history content and calling `Notifications.markAllRead()` because of banner-to-center role switching. The Center's own history and explicit/hover semantics remain unchanged.

**What is NOT yet proven:** full maintainer validator, true Qt/QML loading, Niri multi-output/reveal correctness, absence of input glitches, and actual reduction of Qt heartbeat/frameSwapped slow gaps on owner hardware. The targeted patch removes an evidenced layout conflict; other sources of lag may remain. Do not mark the three owner outcomes accepted until an exact-SHA native reproduction matches the video steps and the owner confirms them.

## Owner follow-up: recording-stop `Recording saved` notification lag

**Owner observation (2026-10-10):** previous Notification Center size/position
problem is now acceptable in native use. A distinct remaining case happens
after stopping screen recording: the system announces completion and the
transient notification popup still lags. Keep its desktop acceptance OPEN.

**Source path confirmed:**

1. `scripts/videos/record.sh` sends `notify-send "Recording saved"`
   with the full absolute saved-video path after successful recording
   and file verification. Optional Discord compression defaults OFF; do
   not attribute a runtime stall to ffmpeg without local configuration evidence.
2. `services/Notifications.qml` appends the accepted notification into
   `Notifications.popupList`, rendered in the transient
   `NotificationListView` with grouped cards.
3. `modules/abyss/content/AbyssNotificationsContent.qml` previously
   bound the desired Popup height directly to
   `popupLoader.item?.contentHeight`. Immediately after a new notification,
   delegates and a potentially wrapping saved-file path may take several
   Qt layout passes, so the requested span/depth can change more than once
   during reveal and trigger further allocator/field updates.
4. `modules/abyss/AbyssRecordingBody.qml` also closes as
   `RecorderStatus.isRecording` changes. It may overlap the notification
   transition. Existing evidence does NOT establish which Qt/RHI/compositor
   frame is late or that the file body alone causes the stall.

**Narrow source remedy on dev; Niri validation still pending:**

- `98d0b387881c1d94b75dff5a78aee312bf830da5` adds
  `settledPopupHeight` / `popupLayoutReady` to the notification
  adapter. A one-shot, event-driven 75ms Timer batches positive
  `NotificationListView.contentHeight` updates. It does not publish
  zero or intermediate card sizes; later list changes are also batched.
- `df86dca7278f680d2c9d555c62ac7b1be8f9943e` makes the
  transient Abyss host load content offscreen via `residentContent`
  while a notification is pending; `open` waits for
  `contentItem.item?.popupLayoutReady`, avoiding a Loader/open
  chicken-and-egg dependency. The separate Center,
  input masks, hover/bridge and recording-save action remain unchanged.
- `a57020f20da369baf8db183a2164cb1dbc1cc927` extends
  `scripts/test-abyss-notification-transition.mjs`: the real
  committed QML expressions and measurement functions are checked
  against zero/provisional/settled ListView height, a synthetic
  `Recording saved` path, later notifications, empty history and
  existing Center/placement invariants. **46/46** isolated JS tests
  passed. The canonical validator already calls this script; the
  full validator has NOT been run on this SHA.

**Native acceptance still needed:** stop a short recording with
`screenRecord.showNotifications=true`, verify exactly one properly
sized, promptly revealed `Recording saved` banner with no
mid-animation resize, open the Notifications/Activity center while
that banner is still up, and repeat with long paths and multiple
notifications. If the visible lag persists, collect the exact same
phase's Qt heartbeat/frameSwapped timestamps alongside
`notification.contentHeight`, `settledPopupHeight`,
`popupLayoutReady`, `notification.record`, and
`recording.progress`. No source-only test proves a GPU or Niri
performance gain; keep the task OPEN until owner confirmation.

## Local chatbot's next steps

1. Follow \`AGENTS.md\`, \`to-do/README.md\` and \`to-do/cloud-bot/README.md\`. Refetch \`dev\` and verify the installed/running QML matches the exact checkout. Never edit \`stable\`. This issue is independently OPEN even if Screen Edge hover becomes stable.
2. Reproduce **twice on the same physical output** using the owner's exact \`notificationCenter.popupWidth\`, \`popupHeight\`, DPI/output scale and existing Screen Edge position: (a) clean/empty notification history, open/close; (b) deliver a new notification/recording toast and open immediately or as its toast exits. Repeat after all toast surfaces are gone. Mark whether the bug is cold-only, recent-notification-only or any open.
3. Collect bounded, timestamped measurements during **the actual 1.7–2.9 s transition**. Capture \`hostedPopup\` identity, requestedVisible, presentationActive, revealProgress, explicit/hover ownership; actual configured width/height, \`contentItem.implicitWidth/implicitHeight\`, content Loader status; host \`edge\`, \`joinedEdge\`, \`anchorBounds\`, \`along\`, \`span\`, \`depth\`, \`requestedRecord\`, \`placement\` (\`shrunk\`/\`evicted\`), \`visualPlacement\`, \`record.content/surface\`, \`targetRecord\`, \`inputBounds\` and pyramid/retained-placement states; simultaneous toast/other Popup ownership.
4. For lag: correlate Qt \`frameSwapped\` and the opt-in 50 ms heartbeat with **actual Notification Center reveal and placement changes**. Existing \`scripts/collect-abyss-hover-frames.sh\` separates frame and hover phases; a new bounded **same-phase** capture may be required for correlation. Snapshot-only/synthetic test green is not GPU compositor evidence.
5. Distinguish whether the long right-side silhouette is a genuine layout height, wrong initial edge, temporary \`joinCorner\` extension, allocator \`shrunk\`/relocation, an intermediate pyramid frame or a stale visual rendering artifact. Inspect the state **before** changing clipping/motion/size.
6. Once a root cause is confirmed, make the smallest source correction. Preserve source-anchor and corner ownership, popup connection geometry, visual color/shadow, other Popup slots, notification history actions, Quick Notes/keyboard focus, desktop click-through and the previously owner-accepted fullscreen fix. Add regression cases for a new notification vs no notification and for opening while a toast is visible.
7. Execute targeted tests and \`bash scripts/validate-maintainer-local.sh\` on the exact SHA; then seek independent local Niri reproduction and owner approval. **Do not mark fixed solely from source-level tests.**

## Acceptance

- [ ] Default and customized Notification Center sizes are correct from the **first visible frame**, without transient full-height side bars or a jump between edges.
- [ ] No perceptible stall, sudden relocation or mid-reveal resize when opening immediately after a new notification arrives.
- [ ] Empty history, one notification, multiple notifications, and clearing notification history do not break size or placement.
- [ ] Same behavior on repeated warm opens and after restart, with correct corner/Screen Edge and output scaling.
- [ ] No regressions to hover ownership, click-through, keyboard focus, other Popup kinds, multiple output layouts or fullscreen handling.
- [ ] Native Niri evidence and **owner-confirmed acceptance**. Until then: OPEN.

**Work boundary:** This record now includes a bounded source-level fix for the actual toast-to-Center geometry branch; it does NOT undo the earlier exact hover revert. Native performance and owner acceptance still need independent confirmation.
