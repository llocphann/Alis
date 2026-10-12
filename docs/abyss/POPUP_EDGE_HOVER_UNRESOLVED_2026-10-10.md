# Abyss Popup / Screen Edge hover — unresolved native regression

**Status:** OPEN — owner confirms the 2026-10-10 cloud fixes did not work.  
**Next executor:** local development chatbot with the actual Niri/Quickshell desktop.  
**Authoritative task:** [POP-I01 — Screen Edge / Popup Bridge Hover Continuity](../../to-do/cloud-bot/ISSUES.md). This document is technical evidence, not a second task board.  
**Repository branch:** dev only; NEVER modify stable.

## Source baseline and complete rollback

The user asked to revert the failed bridge/hover changes in full, then give the local chatbot a record of the unresolved defect.

- Exact pre-experiment baseline: a7e76b509075ba1a3f2bc9d0c16b6a5e76672ba1.
- The two unsuccessful source-level attempts began with 6c00e25da9b5b508ead66990b8a42722f965bb21 and proceeded through 96a9772019456bd1b3607008320e47e0ca7cc02c.
- All modified runtime QML/JavaScript, the affected old tests and canonical validator were subsequently restored **byte-for-byte** to the pre-experiment Git blob SHA, and the newly created test-popup-edge-body-hover-policy.mjs was deleted.
- The final source-and-tests restoration commit was eb3f9d35133e41e7ad343b94c74671fc7fe5e9ac. At that point the GitHub comparison of a7e76b5... to eb3f9d3... returned **zero differing repository files**, even though dev correctly retained revert commits in its history. Do not cherry-pick the unsuccessful commits.
- This note and a brief link in the existing issue are the only intended post-revert additions. They do not reapply any runtime workaround.

To verify the baseline relative to the current docs-only head:

~~~bash
git switch dev
git pull --ff-only
git diff --name-status a7e76b509075ba1a3f2bc9d0c16b6a5e76672ba1 -- \
    modules scripts
~~~

Expected: **no runtime/test file diff** until the local agent begins a separately justified repair. Preserve any unrelated new work by other contributors.

## Owner's desired behavior

The owner wants a hover-opened Popup to stay open whenever the pointer is **within its owning Screen Edge/source anchor OR within the Popup**, including the visibly connected edge-to-popup passage as perceived on screen. It should only begin a hover dismissal once the pointer has **left both owned surfaces**. Distinguish actual pointer-hover ownership from keyboard focus: editors, pinned Quick Notes, click-open or explicit Notification Center, menus and other deliberate focus modes have independent lifetime rules.

Acceptance must address **source → visible connection → Popup body**, reverse travel, holding the pointer stationary, slow and fast movement, and leaving both surfaces. Do not give a blank region of the workspace an invisible hover catcher; do not let a neighboring unrelated Screen Edge hold the wrong Popup.

The user supplied reference screenshots of bottom-right Notification Center and later the video named **2026-10-10_21.21.26.mp4** in the ChatGPT conversation. **The video is not committed to the repository**. The local agent should request/access the owner's original video on the desktop if needed, rather than assuming the ChatGPT upload's container path is visible locally. The owner explicitly reported **still no improvement** after both attempted patches.

## Evidence: what is and is not known

Native owner archives from 2026-10-10 were recorded at several earlier dev SHAs: 17:33, 17:44, 17:58, 18:07, 18:31 and 19:03 local. See the existing issue entry for exact snapshots and separate source SHA descriptions. They show, at various times:

- Real Notification Center input was registered, and actual hovered points could appear in native connector/shoulder strips outside the rectangular body inputBounds.
- Some source → connector → body transfers **succeeded**; some loss-of-hover samples were recovered by existing grace. Stationary hover inside the body could hold for many samples without an automatic close.
- Other visits lost all sampled hover flags, then retracted when semantic and grace state expired. Snapshots did **not** report global pointer coordinates after hover was lost. Consequently these samples alone cannot prove that every dismissal happened while the pointer remained on painted and input-enabled pixels.
- Qt frameSwapped slow gaps and Qt heartbeat lateness were measured separately; that is not proof of the Popup hover root cause and must not be conflated with this defect.
- The latest user video and direct feedback refute both proposed fixes as **product solutions**. The clip alone cannot identify the exact Qt signal, underlying input region, or Niri pointer delivery that failed.

### Why the 2026-10-10 patches were reverted

**Attempt A (source/body-only ownership):** the source-level change made hosted Popup hover depend only on the rectangular inputBounds, dropping hover while moving across a real painted/native input connectionRects strip. Notification Center and Quick Notes also lost their independent entry bridge hold. Source-only tests passed but the user saw **no improvement**. This mismatch between the chosen ownership predicate and existing native input geometry was a concrete design flaw in the attempted patch, not proof of the full original bug cause.

**Attempt B (exact body + native connectionRects union):** the follow-up Geometry.popupConnectedHover predicate admitted the existing connector strips and excluded source overlap and blank space. It was wired into hosted StyledPopups and generic Abyss popup idle-dismiss. Source-equivalent tests passed (42/42 policy, 31/31 Notification Center), **but the user again reported no improvement**. Passing JS expressions was not evidence of correct Niri/Qt pointer delivery, input region behavior, or full popup lifecycle. This attempt is also **fully reverted**.

Do not reinstate Attempt A, Attempt B, blanket input-mask extensions, perpetual timer leases or other speculative workarounds without fresh native evidence.

## Starting points in the restored code

- modules/bar/StyledPopup.qml — hoverTarget, source HoverHandler, humanVisibleRequest, requestedVisible, _liquidSemanticHold, 90ms hoverTransferTimer, semantic vs visual retract.
- modules/notificationCenter/NotificationCenterPopup.qml — dwell-gated corner, _anchorHovered, hoverLeaseRequested, entryBridgeHeld, exitGraceHeld, explicit and keyboard paths, owner-output publication.
- modules/screenCorners/ScreenCorners.qml and modules/abyss/AbyssCorners.qml — real source anchors, dwell, which layer surface actually owns the corner, Niri overview priority.
- modules/abyss/AbyssBodyHost.qml — inputFrame.containmentMask, inputBounds, connectionRects, connectionRegions and nativeInputRegion, acceptsInput and semanticOpen, contentCanvas and visual reveal.
- modules/abyss/AbyssPerimeter.qml — hosted StyledPopup HoverHandler, Perimeter PanelWindow.mask, output-local geometry, sourceInputRegions and hoverProbe snapshot.
- modules/abyss/AbyssSurfaceController.qml — popupSlots, presentation/eviction, dismissPopups, body registration and edge/source input ownership.
- modules/abyss/content/AbyssPopupContent.qml and modules/abyss/AbyssGenericPopupPresenter.qml — generic Popup trigger, HoverHandler, idle-dismiss clock and lifecycle.
- modules/abyss/looks/AbyssGeometry.js — native popupInput, popupShoulders, rectContains and joined geometry. Painted SDF union is not automatically an input region.

Do not assume all those codepaths are active for the owner's chosen Popup. Resolve the actual running host/slot/output first. Do not conflate Quick Notes editor focus, input-method focus, active layer-shell surface, cursor hover and semantic Popup lifetime.

## Requested local-agent diagnostic workflow

1. Read AGENTS.md, to-do/README.md, to-do/cloud-bot/README.md and the existing OPEN Popup/Edgebar issue. Work only on dev; refetch HEAD and installed/runtime identity before applying any candidate fix.
2. Reproduce on the owner's Niri desktop using the current **restored baseline runtime**, installed via the normal ./setup update --local path. Verify the installed shell.qml, AbyssPerimeter.qml and AbyssGeometry.js against checkout and ensure the relevant live IPC handler is actually mounted.
3. Capture the exact sequence: hover owning edge/corner until open; hold on source; cross slowly over the **visible connector**; hold at its middle; enter body; hold; return to source; finally move outside both. Repeat for a generic Popup. Record exact timestamps and full state around **actual unwanted dismissal**. If collector uses phases, move during the hover phase, not merely the frame phase.
4. Existing bounded starting instrument: bash scripts/collect-abyss-hover-frames.sh. Inspect readiness-trace, identity, hover-snapshots, native input registration, source anchor hover, hosted body/content hover, requestedVisible, semanticHold, exitGrace and Popup slot changes. The existing scripts/test-popup-anchor-hover-runtime.py can supplement, but a source/mock PASS is NOT an owner-native PASS.
5. Specifically distinguish (a) loss of native/Qt hover event before reaching the next surface, (b) a visually painted connector pixel not in the native input mask, (c) input intercepted by another layer/participant/source region, and (d) semantic timeout or host replacement **despite a real pointer owner**. Probe one candidate mechanism at a time; inspect mask and event ordering before changing geometry.
6. If snapshots still lack evidence for pointer position **after** hover loss, add a minimal, bounded, opt-in native diagnostic permitted in the local environment. Use coordinates in the correct QQuickWindow/output space; never silently compare corner-window-local and Perimeter-window-local scenePosition values. Avoid persistent global grabs or full-screen invisible pointer catchers.
7. Once a cause is **demonstrated**, implement the smallest change preserving the existing visual join, Niri overview hot-corner ownership, source priorities, multiple simultaneous Popup slots, desktop click-through, keyboard focus, pinned Notes and closed-popup release. Add behavioral regression checks for four edges and the proved failure.
8. Run focused regression and then bash scripts/validate-maintainer-local.sh on the **exact changed SHA**, preserving exit codes and logs. Distinguish independently: code tests, Niri native reproduction, full validation and **owner confirmation**. Keep the task OPEN until the owner accepts the repaired pointer behavior.

## Acceptance checklist for the local desktop

- [ ] Notification Center: no dismiss during edge → connector → Popup body.
- [ ] No dismiss while stationary on an actually interactive, visibly connected Popup surface.
- [ ] No dismiss during the reverse Popup body → connector → owning edge path.
- [ ] The Popup can close after exiting both the owning edge and Popup; no stuck-open lease.
- [ ] Other edges, multiple simultaneous Popup slots, generic Wi-Fi/Bluetooth/Utilities and Quick Notes do not become hover-owned by unrelated regions.
- [ ] Desktop background still receives clicks outside native popup input masks.
- [ ] Quick Notes pin/editor and explicit Notification Center keyboard modes are preserved.
- [ ] Native reproduction and owner approval obtained. Until then: **OPEN**.

**Important:** The failed fix branches/commits remain in Git history only to preserve diagnosis. Do not treat them as implementation candidates or tests that must stay green. No new runtime patch has been applied as part of this revert-and-document task.
