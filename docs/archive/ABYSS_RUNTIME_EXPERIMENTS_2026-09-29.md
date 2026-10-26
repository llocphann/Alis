# Archived Abyss runtime experiments — 2026-09-29

> **Status: RETIRED FROM RUNTIME**
>
> These experiments were removed from the active Alis/Abyss runtime after live use did not deliver the intended behavior, despite source contracts and synthetic Wayland checks passing. This document is historical reference only and must not be treated as an active runtime contract.

## 2026-09-30 Method A reintroduction — retired again

The maintainer tested a narrow Confirmation-in-Abyss retry and reported that it
**had no effect**. Its active runtime/test changes were reverted forward on
`dev`; sources remain accessible at `f502d8754127` and `73d44691330c`.
The later, unrelated `dialogBody.vacancyRole` forwarding was retained.

For the specific attempted behavior, exact source commits, recorded outcome, and
rollback boundary, see [Method A archive](ABYSS_CONFIRMATION_METHOD_A_2026-09-30.md).

## Retired scope

### Confirmation-in-Abyss
- Runtime request/anchor foundation.
- Abyss confirmation presenter/content.
- Prompt-host registry, output routing, fallback/handoff logic.
- Bar, tray and Dock anchor registration used by that routing.
- Dedicated Confirmation source/runtime/Wayland CI harnesses.

### Polkit-in-Abyss
- The Abyss-specific Polkit presenter/routing experiment had already been reverted.
- Legacy Polkit remains the supported runtime path.
- Historical source remains available in Git.

### Elastic Fill / semantic vacancy borrowing
- Hover Elastic Fill experimentation.
- Semantic vacancy borrowing and automatic borrowing.
- Vacancy geometry/controller hooks and dedicated runtime/contracts.
- Active runtime is restored to the pre-experiment allocator behavior.

## Preserved unrelated fixes

The retirement intentionally keeps:
- Dock physical-edge locking from `5710497e7631`.
- Attached-popup Dock hold from `c52e0cf839b4`.
- Bar auto-hide popup lease behavior from `6350ba770f4a`.
- Concurrent Dock/settings/performance work unrelated to these experiments.

## Historical commit map

### Confirmation / prompt routing
- `c82776b0aa86` — runtime request and anchor foundation.
- `0957ba29f596` — rehost close confirmations in the popup field.
- Subsequent `confirmation`, `close-confirm`, prompt-host and Confirmation CI commits refined the experiment.
- `c7c2d9423050` — restored legacy Polkit and isolated Confirmation before final retirement.

### Polkit-in-Abyss
- `5bc3bbac237f` — expose AuthFlow prompt semantics.
- `36803f838fe3` — add Abyss Polkit presenter.
- `8bb2b7afe069` — wire Polkit into connected popup field.
- `c7c2d9423050` — retire the Abyss-specific Polkit runtime path.

### Elastic Fill / vacancy borrowing
- `f907a07daf59` — initial hover Elastic Fill.
- `ad9eddbb940c`, `09305eb8f31d`, `4ff1e2dbbc67` — Elastic Fill revisions.
- `badd86b23fbc` — remove the Elastic Fill experiment.
- `a4ac98bb164b` — semantic perimeter vacancy borrowing.
- `a03a17c091e8`, `95d5729e0678`, `3728bef41e70`, `ea8c93466db0` — vacancy/hover/automatic-borrow follow-ups.
- Latest archived experiment commit message: **fix(abyss): auto-expand newest semantic surface**.

## Reintroduction rule

Do not copy individual retired files back into active runtime. If this area is revisited:
1. reproduce the live failure first;
2. define a physical Wayland acceptance case before coding;
3. reintroduce one mechanism at a time;
4. require live behavior to pass before adding synthetic CI claims.

Git history is the source of truth for the retired implementation.

---

## Retired Confirmation design notes

The section below preserves the final active Confirmation design document for future reference.

# Abyss confirmation popup architecture

Status: Confirmation source/contracts and automated synthetic Wayland acceptance are complete on `dev`; physical monitor hotplug/focus acceptance remains target-hardware work. Polkit has been restored to its legacy path and is outside this document's implementation scope.

## Goal

Confirmation prompts use the existing Abyss connected-surface field instead of introducing another detached dialog renderer. Placement is source-owned when Alis can resolve a live Bar/System Tray/Dock anchor; otherwise the request uses a top-center fallback on the target output.

The intended flow is:

```text
request/backend
    -> runtime request state
    -> source/anchor resolver
       -> live source Item (Tray/Bar/Dock), or
       -> top-center fallback Item
    -> StyledPopup
    -> AbyssSurfaceController popup slot
    -> AbyssBodyHost / Pyramid placement + motion
```

This deliberately reuses `StyledPopup`, the stable popup slots in `AbyssSurfaceController`, and `AbyssBodyHost`'s Pyramid contract. Confirmation does not need a second placement or animation system.

## Source audit

### Alis close confirmation

`modules/closeConfirm/CloseConfirm.qml` is a Alis-owned confirmation path. It receives `closeConfirm` IPC, snapshots the focused Niri window and, after approval, performs the real close action through `niri msg action close-window --id ...` (with the existing Spotify minimize exception). This path is safe to rehost because Alis owns both the confirmation semantics and the final action.

The existing Material implementation is a fullscreen layer-shell window with a centered `WindowDialog`. Waffle has a separate supported renderer and must remain independent.

### Application-native dialogs

A compositor-visible transient window is not, by itself, an interceptable confirmation protocol. Alis can observe/focus/close windows, but that does not provide a reliable API for extracting button roles, invoking the application's original action, or suppressing the application's own dialog without changing behavior.

Accordingly, arbitrary application-native confirmations are **not** to be recreated from window title/text heuristics. In particular, a ChatGPT tray menu entry labelled `Quit` can be invoked through the StatusNotifier/DBusMenu surface, but that menu surface does not expose a standard semantic contract saying whether the application will subsequently create its own native confirmation. Triggering it and drawing a second Alis confirmation would risk duplicate prompts; replacing it by label matching would risk bypassing application semantics.

ChatGPT Quit therefore remains a runtime target for a future reliable app/native bridge, not a source-only claim of completed interception.

### StatusNotifier / DBusMenu

Quickshell exposes tray menu entries with presentation/action fields such as text, icon, enabled/check state, children and `triggered()`. There is no generic confirmation/action-role contract sufficient to classify every `Quit`-like item as a safely interceptable application confirmation.

The useful part for this project is the **live tray anchor** itself. A request that already has trustworthy backend semantics can resolve its source app to that anchor and let `StyledPopup` inherit the correct output and attachment Edge.

### Native dispatch / desktop portal audit

The current `scripts/native-dispatch` surface routes keyboard/input helpers, Niri configuration, clipboard filtering, MPD/lyrics, theme generation and desktop-icon synchronization. It exposes no dialog interception, transient-window action bridge, portal request broker or generic app-confirmation transport.

The Niri portal configuration delegates portal implementations to GNOME/GTK, including `org.freedesktop.impl.portal.Access = gtk`. Alis is therefore not currently the portal backend that owns those confirmation semantics. Rehosting portal confirmations would require an explicit portal/backend integration rather than observing a GTK dialog after it appears.

Likewise, the shared System Tray menu renderer ultimately sends `QsMenuEntry.triggered()` for a selected menu row. The menu entry surface contains presentation state such as text/icon/enabled/check/children, but the repository has no additional action-role or confirmation-response channel layered on top of it.

These findings reinforce the safe boundary: current native-dispatch, portal and tray-menu paths can provide identity/anchor context or invoke an existing menu action, but they cannot generically replace an application's subsequent native confirmation while preserving its original semantics.

### Dock

Abyss Dock app buttons are real Items under the Dock's `AbyssBodyHost`. They already carry application identity and are valid fallback source anchors when no matching visible tray item exists.

Resolver precedence is explicit source Item, then live System Tray/Bar source, then Dock, then the top-center output fallback. When the same app identity is visible on more than one output, source/output affinity is evaluated before surface-kind priority so a remote Tray icon cannot steal a request from a same-output Bar/Dock anchor. Matching remains conservative and identity-based; UI label matching must not become an action interceptor.

Abyss Dock content is resident even while the Dock is visually closed. The resolver therefore rejects retained-but-not-presented Dock items. Conversely, once an attached popup legitimately opens from a live Dock app, the Dock is held open through the popup/retract lifecycle so its source icon does not disappear underneath the confirmation merely because pointer hover ended.

### Top-center fallback

Abyss OSDs already use the output field and `AbyssBodyHost`. Confirmation can use the same output geometry model without masquerading as an OSD: a tiny non-painted source Item at the top-center of the selected output can expose that output's `liquidController` and `attachedEdge: "top"`. Feeding it to `StyledPopup` keeps fallback prompts in the same placement/Pyramid machinery as attached prompts.

### Pyramid / motion

No Pyramid architecture change is required. A `StyledPopup` rehosted by `AbyssSurfaceController.presentPopup()` already receives:

- an anchor-derived Top/Bottom/Left/Right attachment Edge;
- anchor-preserving tangent placement;
- optional adjacent-Edge joining from the existing presentation contract;
- stable popup slots;
- immediate semantic input revocation on close;
- Pyramid entry origins, reversible close/reopen transactions and concurrent survivor reflow;
- the existing slide-under/clip content reveal rather than a confirmation-only fade/scale.

A confirmation presenter should therefore be an ordinary focused `StyledPopup`, not a new window type.

## Scope boundary

Polkit remains on the legacy renderer/service path that existed before this Confirmation project. This document does not define Polkit routing, source anchoring, password handling, failover, or Abyss presentation behavior.

## Implementation status

### Phase B — foundation

Implemented:

- `ConfirmationService` owns runtime-only confirmation requests and callback closures; it does not serialize request state through Config, GlobalStates or generic IPC.
- `PopupAnchorRegistry` resolves only live Items that already belong to an Abyss connected surface.
- Implicit matching uses stable machine identities only. Human-facing app names, tray titles and tooltips are deliberately excluded from routing.
- Precedence is explicit source Item, then System Tray, then Bar taskbar, then Dock, then top-center fallback.
- Source removal cancels the attached request instead of switching anchors mid-flight. A source that remains registered but becomes non-presented is also treated as source loss; lifecycle cancellation is forced so a disabled/hidden UI cancel action cannot strand a request on stale geometry.
- Retained-but-closed Abyss source trees are excluded from initial routing.
- Requests resolve their output before implicit app-anchor lookup, so duplicated app surfaces prefer the source/request output while preserving Tray > Bar > Dock priority within that output.
- Equal-strength implicit anchor ties are treated as ambiguous and fall back instead of using registration order to guess which app instance owns a semantic prompt.
- If a top-center fallback output is hot-unplugged, the same request is retargeted to a remaining valid output. If the request had a real attached source on the removed output, it is cancelled instead of teleporting.
- The active request is retained until its visual retract tail is released, so queued requests cannot inherit the previous geometry. Owning-presenter teardown also releases an already-closing request so output/family removal cannot strand the queue.
- Renderer handoff can add a second semantic release gate on top of the visual-tail gate. A transferred request is hidden from the connected presenter without being semantically resolved; the standalone fail-safe later resolves/cancels that same `ConfirmationService` request, so `requestResolved` and the original action callback reflect the user's real choice. The queue slot remains held until both the old `StyledPopup` tail and the standalone semantic resolution are complete.
- Owner teardown uses forced lifecycle cancellation, so a disabled/hidden user cancel action cannot strand an owned request when its renderer disappears.
- Generic action semantics preserve enabled/visible state. Enter selects only a usable default/non-cancel action, user cancel does not invoke a disabled/hidden cancel action, and empty/duplicate action IDs are normalized so one visible button cannot resolve a different callback.
- `AbyssPromptHostRegistry` tracks concrete per-output prompt hosts only after their Abyss field has presented a usable frame. Configuration alone, or a mapped perimeter whose field/shader is not ready, never counts as a usable confirmation renderer.
- If `abyssPerimeter` is disabled or no frame-ready prompt host exists, the previous standalone confirmation renderer remain available as a fail-safe rather than creating an invisible request.

### Phase C — normal confirmation

Implemented for the Alis-owned `closeConfirm` backend:

- the request is presented through a focused `StyledPopup`;
- source app IDs can attach the popup to a matching Tray/Bar/Dock anchor;
- same-app anchors on multiple outputs prefer the request/window output;
- a Dock source remains presented while its attached confirmation is active/retracting;
- unresolved or retained-but-closed sources use the output top-center anchor;
- top-center fallback ownership survives output hotplug by moving only to a remaining valid output, while attached-source loss still cancels;
- critical confirmation presentation keeps the popup field available over fullscreen and is not demoted beneath a native settings dialog;
- the real close callback still executes the existing Niri close/minimize path;
- repeated close triggers for the same window are deduplicated across visible, queued and retracting ownership, while different windows may still queue normally;
- all Abyss-family close confirmations enter the same semantic queue even when the connected host is temporarily unavailable; activation either uses the live connected host or transfers that exact request to the standalone renderer without dropping queued successors;
- renderer loss during an already-visible prompt transfers the same captured window identity and unresolved action transaction to standalone; accepting there invokes the original queued `close` callback rather than a second direct-close path, cancelling reports the original cancel action, and stale transferred prompts use lifecycle cancellation if their captured Niri window disappears;
- cancel, close/reopen, long content and long action labels use the same Abyss primitives and popup geometry; Details/Hide details labels follow the translation catalog.

This does **not** claim generic interception of application-native confirmations. ChatGPT Quit remains blocked on a trustworthy backend/native bridge that can expose the application's real confirmation semantics and suppress the original dialog without bypassing or duplicating it.

### Phase D — runtime acceptance

A synthetic Wayland/Quickshell harness now exists at `scripts/test-abyss-confirmation-runtime.sh`. When run in a real Wayland session with Quickshell available, it exercises real `StyledPopup`/Abyss popup slots and real confirmation callbacks for:

- Top/Bottom/Left/Right source attachment and Join Edge inheritance;
- Tray-over-Dock identity precedence and Dock-only fallback;
- top-center fallback when no source resolves;
- long content width capping;
- source removal without teleport;
- coexistence with another popup and survival while that peer retracts;
- queued requests activating only after the predecessor's visual tail releases;
- close/reopen on the same source;
- retained-but-closed source rejection to top-center fallback;
- a still-registered source becoming non-presented while open, which cancels rather than teleporting;
- equal-strength duplicate source anchors falling back rather than choosing registration order;
- duplicate action IDs normalizing deterministically and invoking only the intended callback;
- renderer-handoff action semantics and queue gating: presentation transfer emits no fake cancel resolution; resolving the standalone handoff invokes exactly the original action callback/resolution, and its queued successor cannot activate until the old popup tail plus semantic handoff completion have both released ownership.

The script intentionally skips when Quickshell/Wayland is unavailable during ordinary local/static validation. The dedicated `.github/workflows/confirmation-runtime.yml` lane removes that ambiguity. Its runtime chain now validates: real Quickshell on headless Weston; a nested Weston compositor exposing two distinct Wayland outputs with layer-shell carriers bound to their real `ShellScreen`s; and the same single-output harness inside nested Niri on an Xvfb software-EGL parent. Source contracts, headless Wayland, two-output Wayland and nested-Niri jobs have all completed successfully on `dev`, including same-output Tray/Dock affinity, requested-output fallback, renderer-handoff and queue-gating cases.

This establishes automated Quickshell acceptance for source/output routing across two virtual Wayland outputs and automated Niri acceptance for the synthetic confirmation presenter. It is still not equivalent to physical monitor hotplug/focus changes on target hardware.

## Acceptance status

Source/contract coverage is complete for the currently trustworthy backends: request ownership, conservative identity/output anchor resolution, ambiguous-source fallback, live-source validity, Dock/Bar source hold, popup/Pyramid reuse, frame-ready prompt-host detection, fail-safe renderer handoff with preserved action semantics, two-gate visual/semantic queue release, fullscreen/native-dialog critical-prompt visibility, Join Edge inheritance, action availability/ID/callback safety, queue/reopen ownership, same-window close deduplication, stale-window rejection, output-hotplug policy.

Automated confirmation runtime acceptance is now recorded on real Quickshell + headless Wayland, a two-output nested-Weston topology, and the same single-output harness inside nested Niri. Still requiring physical/system acceptance:

- physical monitor focus/output-hotplug behavior on target hardware (two-output routing itself is covered virtually);
- lock/unlock interaction with the actual login/lock stack;
- ChatGPT Quit or any other application-native confirmation only after a reliable native/backend interception path exists.

Do not mark the entire feature `production runtime complete` until those target-environment checks are recorded.

