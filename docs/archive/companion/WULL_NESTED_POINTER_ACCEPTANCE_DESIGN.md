> Historical snapshot archived on 2026-10-10 from Hadalis `8b2ed6f0a1fccddade206f0060ed19d19337a5da`. This document does not assign active work or prove that pending acceptance is complete. Use [the current categorized tasks](../../../to-do/README.md).

> Companion implementation and remaining product tasks belong to [Hadanion](https://github.com/llocphann/Hadanion). Original Hadalis receipts keep their original scope.

<!-- hadalis-doc-kind: research -->

# Wull — nested Niri real pointer acceptance design

Status: **underlay fixture and inert target contract staged; no physical pointer test executed**.
Scope: the existing actual `AbyssPerimeter` PanelWindow with production
`AbyssCompanion`, not a synthetic standalone mascot or an offscreen rectangle.

## Existing evidence and boundary

The October 1 production geometry receipts on `336726d7...` and
`fca39532...` both recorded four-edge containment of the actual centered
production QML. Focused native/perimeter qualification recorded 8/8 PASS
on `c10b669f...`. The new nested-Niri receipts
`docs/archive/companion/receipts/2026-10-01/wull-nested-niri-20261001T152505Z-d938e783-24af1766f3eb.json`
and
`docs/archive/companion/receipts/2026-10-01/wull-production-layer-20261001T152511Z-c5413658-24af1766f3eb.json`
both recorded PASS on exact source
`24af1766f3eb7fc7abb2a381efba962ea51ed42d`.
Those nested receipts established an owned private compositor, one active
output, real production layer mapping, default-off isolation, single owned
Rust backend when enabled, keyboard-focus constraints and full cleanup.
**They did not send a mouse event or qualify any compositor hit region.**

The existing production input mask deliberately includes the entire
`AbyssCompanion` host. The smaller rotated body is the click receiver. A
source-level rectangle is not proof that a Wayland compositor will route
an actual pointer event as intended. Do not change production mask yet.

## Staged groundwork (safe, no live run)

- `scripts/wull-fixtures/pointer-underlay/shell.qml` is a separate,
  full-output `WlrLayer.Bottom` PanelWindow with namespace
  `hadalis:wull-pointer-underlay`, no keyboard focus and a click witness.
  It has no production loader, Wull enablement or virtual input capability.
  Its `WULL_POINTER_UNDERLAY_PRESS` coordinates appear only in private
  test logs. It must be launched only inside an owned nested Niri socket.
- `scripts/wull-pointer-targets.py` computes **candidate** top-edge
  production bounds and three points from the reviewed default
  configuration, real shared host-policy placement equation and
  production mapped body dimensions: a body center, an empty host margin
  and an exterior control. It enforces a bounded output/geometry and
  avoids the default bar's top 40 logical pixels. Estimates do not
  constitute a hit-test or a screenshot-based visual acceptance.
- `scripts/test-wull-pointer-underlay-contract.py` is an inert automated
  regression: fixture layering and marker contracts, default-off and
  unchanged whole-host mask, actual production click wiring, and
  deterministic target calculations across small and large viewports.
  Its new code still requires execution evidence on an exact source SHA.

## Implementation gate for a controlled real click runner

1. **Isolation**: from a clean, fast-forward-only `dev`, verify permitted
   origin, owner-created private diagnostics outside the repository and
   audited production/fixture blobs. Start one nested Niri inside the
   host's regular Wayland window with a private empty `NIRI_CONFIG`.
   Verify *distinct* nested `WAYLAND_DISPLAY` and `NIRI_SOCKET` and
   zero preexisting production/underlay namespace collisions. Abort
   before launching any pointer actor if identity cannot be proved.
2. **Underlay**: start only the dedicated private underlay on the nested
   display. Confirm its explicit QML-ready marker AND compositor layer
   inventory (one bottom layer on the expected nested output).
   Never run underlay on the real host display.
3. **Production**: run the real unchanged Abyss production fixture with
   its own isolated XDG directories and D-Bus, pinned private release
   `inir-companiond`, default-off and temporarily enabled phases.
   For pointer tests only, explicitly set
   `abyss.companion.interactive=true`, `edge=top`, `along=.72`,
   `size=1`, and a known nested output. Do not persist any user config.
   Verify compositor-visible layer ownership and exact private daemon
   count. The prior production probe uses `interactive=false` and
   therefore cannot qualify click reception on its own.
4. **Input provenance**: permit only a Wayland-native virtual-pointer
   client bound to the **verified nested socket**. A native
   `wlr-virtual-pointer` backend may be used if installed and shown to
   work on the exact local nested Niri instance. Do not use host-global
   `ydotool`/`uinput`, root input, uncontrolled desktop tools or any
   fallback that can inject into the live compositor. Do not silently
   download or install an input tool as a test side effect. Missing
   backend or unavailable protocol => **INCONCLUSIVE**, not PASS.
5. **Acceptance matrix**: require an *observed* underlay click at the
   body-center candidate with Wull disabled (negative control), then
   an observed underlay click outside the host when enabled (pass-through
   control). With Wull enabled, click the actual body center: require
   the underlay receives **no** click **and** independent private evidence
   that production Wull's click was delivered to its real Rust bridge.
   Absence of an underlay click alone is not enough: an unrelated top
   UI region or absent input could yield the same result. Measure the
   host-empty-margin point separately; the current whole-host mask may
   capture it, and that is an **observation** rather than a reason to
   call pass-through successful. Count clicks using distinct bounded
   time windows, exclude startup/animation settle windows, and check
   the current top bar is not covering any test point.
6. **No conflation**: the first controlled top-edge matrix is separate
   from four-edge *physical* input behavior; later extend the validated
   approach to bottom/left/right, and then test pointer passthrough
   before/after any proposed inner-body-only Region change. Niri
   layer inventory does not report per-pixel input masks. A screenshot
   command succeeding does not prove visual quality.
7. **Cleanup/publication**: bound each process and whole milestone;
   terminate only owned live process groups and the exact private
   daemon binary, verify underlay and production layers unmap, verify
   nested socket disappearance and unchanged host-output inventory.
   Log raw QML events and coordinates locally only. Publish a unique
   SHA-pinned allowlisted JSON receipt with per-case status, preflight
   reason, exact source blobs and cleanup evidence; no raw screenshots,
   device names, host sockets, paths or logs. If publication is blocked,
   retain local evidence and print a short STOP; never rewrite shared
   Git history or fall back to an active desktop test.

## Decision after evidence

Only consider replacing the whole-host Wull `Region` after the real
underlay/body matrix, followed by a separate candidate-mask test
on the same compositor with unchanged click/hover behavior. Keep
`abyss.companion.enabled=false` by default. Canonical-wide validation,
physical multi-output/hotplug, long-run **whole-shell** resources,
session reload/suspend and maintainer visual/motion approval remain
independent outstanding gates.


## Private click-delivery relay prepared

The source-only fixture `scripts/wull-fixtures/pointer-underlay/companion-relay.py`
was staged in `f8116f4000b40265648e8a20f0d6f29fa16b1012`. A future nested
runner may explicitly point the real production bridge's private
`INIR_COMPANIOND` override to this narrowly guarded executable while the
relay itself starts the **real exact-source private Rust binary**. It
preserves newline JSON stdio, records only bounded private
`real_bridge_click_received` markers for v1 click events, and observes
the associated happy/pulse reaction produced by the real Rust core.
It refuses invocation without the private nested-session opt-in, distinct
nested/parent display and Niri socket names, absolute executable path
and out-of-checkout private trace. This is an observational fixture;
it cannot fake a production click or change the production source.

`scripts/test-wull-private-relay-contract.py`, committed as
`1a3e7a7d837e7bcfc82bf2bb8f702355d5475891`, is an **inert**
fake-backend unit smoke for relay line forwarding, private marker
creation and refusal of equal host/nested display identity. A fake
backend is used ONLY by that inert contract, never as evidence of a
real production click. These source files have no exact-source local
execution receipt yet.

A real pointer PASS additionally requires that observed private
underlay click controls bracket an enabled Wull center click and that
the relay's click marker plus a subsequent real backend reaction
belong to that phase. The marker/reaction alone cannot establish the
true pointer target without the independent underlay controls.


## Staged real nested pointer runner

The controlled real pointer implementation is staged in `dev`:
`scripts/wull-manual-pointer-child.py` launches the dedicated bottom
underlay and the unchanged actual `AbyssPerimeter` production fixture in
separate private Quickshell/XDG/D-Bus sessions on a **parent-verified single
nested Niri output**. Its disabled-center negative control must click the
underlay, enabled-outside-host control must click the underlay, and enabled
body-center must instead produce both a real production bridge click
and a subsequent state reaction from the private exact-source Rust daemon.
The empty whole-host margin is diagnostic only.

`scripts/wull-manual-nested-pointer.py` creates the owned nested compositor
from the live compositor's ordinary Wayland window and verifies distinct
nested Wayland/Niri socket identity, no namespace collision, output topology,
the private child's sanitized evidence and cleanup. It never injects pointer
events itself. The child forces an already-installed `wdotool` to the
`wlr-protocols` backend for `mousemove` and `click`, rechecking the
nested Wayland socket before each input operation. It **never** falls
back to portal permissions or host-global `/dev/uinput`. Missing `wdotool`,
unsupported native protocol, incomplete nested identity or unavailable
prerequisites yield **INCONCLUSIVE** without claiming input acceptance.
No automatic package installation or live-user-session test is permitted.

`scripts/test-wull-nested-pointer-contract.py` is an inert parser, isolation,
source-provenance and private fixture test. The existing
`scripts/test-wull-pointer-underlay-contract.py` and
`scripts/test-wull-private-relay-contract.py` remain prerequisites.
The coordinator source guard pins reviewed Wull production, native dependency
continuity, prior Niri helper, underlay, real relay, target estimator, and
the new child source blob. Their addition does **not** certify successful
runtime execution: no `docs/wull-pointer-acceptance-*.json` receipt yet.

The first coordinated manual gate must run all three inert contracts on
one clean `dev` SHA before explicitly invoking
`python3 scripts/wull-manual-nested-pointer.py --acknowledge-nested-pointer`.
The opt-in runner keeps bounded raw logs/coordinates in private state outside
the checkout and publishes only per-case classifications and exact source SHA.
A forced SIGTERM or timeout may terminate only its owned processes; no
real shell settings are read or written. A PASS on a single top-edge nested
output must not be interpreted as the other three edges, visual quality,
whole-shell resources or permission to narrow the production input mask.


## Missing wdotool: reviewed native-only wlrctl alternative

The first opt-in pointer receipt
`docs/archive/companion/receipts/2026-10-01/wull-pointer-acceptance-20261001T155651Z-c552449b-304d6ab601b1.json`
on source `304d6ab601b130c11756de2f4ac7059cdda5507b`
is `INCONCLUSIVE` with `native_wdotool_missing_no_input_injected`.
The parent refused to start the nested pointer trial, and its
`observation` is null: **no physical input event was measured**.
The previously accepted geometry, native/perimeter, and owned nested
production host reports are unaffected.

Reviewed alternative: the external `wlrctl` CLI directly uses the
Wayland wlroots virtual-pointer protocol, without portal or uinput.
It is **relative-motion only**, unlike `wdotool mousemove X Y`.
The new fallback is accepted only when `wdotool` is absent and
`wlrctl` is already available in `PATH`. On the verified private
one-output nested socket the child issues a far-negative relative
move as a **candidate** origin reset, then a target-relative move
and native left click; it re-verifies the distinct nested Wayland
and Niri endpoints before **every** command. This origin reset
is deliberately NOT treated as proven positioning. Independent actual
underlay controls and the real production bridge-to-Rust reaction
must all pass to accept body hit-testing. For the relative-only
backend, failed controls/ambiguous targets are `INCONCLUSIVE`,
not evidence of a Wull product defect. `wdotool` remains the preferred
absolute native-only test backend; there is NO portal, host-global
input or automatic package-install fallback.

Source-only commits:
- `666d6d18d206a92a5d6b28d2800eb9e0e7156898`: alternative
  child backend command planner and per-command isolation check.
- `5f3b777457091bab8ed8c47be31512c1f915fd97`:
  coordinator selection and first reviewed-child pin.
- `0f22292de807744af0220356c96e66c71010fc33`:
  cautious relative-only inconclusive classifications.
- `97c2a4e5577759fcfb731890792e6a99135fbc66`:
  coordinator pins that final child and its seventh self revision.
- `0b716fa8f5011a29051aae2d4486869f2633351f`:
  inert command-plan/identity, pin and conservative classification
  assertions. **None of these source commits supplies new local
  acceptance evidence.**

The next user-owned local milestone is the three inert contracts
followed by one explicitly opted-in nested test ONLY if `wdotool`
or `wlrctl` is already installed. If neither executable exists,
report that missing prerequisite and do not automatically install
or rerun the pointer probe. Should the relative backend prove
unstable despite controls, keep `INCONCLUSIVE` and consider a
maintainer-installed, verified `wdotool` binary instead. All other
edge input, actual popup noninterference, visual and global release
gates remain separate; never shrink the production input Region
on a tool-availability failure.


## First real nested click failure and target-coordinate diagnostic

The maintainer's first real native input run published
`docs/archive/companion/receipts/2026-10-01/wull-pointer-acceptance-20261001T161301Z-8af536c9-115ab32a9825.json`
on exact source `115ab32a98251453edc76c84bdc8558068186aab`.
It is **FAILED**, not accepted: nested Niri and private endpoint identity
passed, disabled-center underlay control passed, enabled-outside-host
underlay control passed, and all owned cleanup passed. In the enabled
body-center phase, the underlay still received a click and neither
the real production bridge nor the real private Rust daemon recorded
the required click/reaction. That narrows the problem to actual pointer
target placement, production host activation/visibility, or the
compositor-visible input mask. It does **not** yet prove that the
production Region is incorrect: the original two full-output underlay
positive controls counted clicks but never checked their coordinates.
The prior `rust_present` relay event proves real backend state, not
that the actual per-output host is active and correctly hit-tested.

Two guarded source-only diagnostic updates on dev:
- `a83f630f7f4bdc73953bc75b7b14b888e6544219` adds
  `underlay_target_status` to the private child. It parses the
  *actual* recorded mouse coordinates from the existing **private**
  full-output underlay witness. Both disabled body-center and enabled
  exterior control now require **exactly one** matched left-click
  within six logical pixels of each predicted requested point;
  missing, multiple, malformed or off-target clicks are
  `INCONCLUSIVE` on either backend, not Wull defects.
  For the enabled body phase, any underlay click is separately
  compared with the candidate body point. An off-target or ambiguous
  underlay event is likewise `INCONCLUSIVE`; a matched underlay
  click at the expected candidate, with no real bridge/Rust event,
  is the narrower failure warranting host/mask investigation.
  Raw coordinates remain exclusively in local private logs:
  the sanitized public per-case receipt publishes only
  `matched`, `off_target`, `no_click`, or bounded ambiguity
  classifications and the independent real-bridge/Rust booleans.
- `a784b3db6157d4c05368fee0ec79925a1a51f468`
  reviews/pins that exact new child blob in the coordinator and
  advances its guarded self-revision count to eight.
  `03d237620ada9dd170d31163ef6081bd40a66042`
  adds synthetic *inert* witness-parser cases, bounded-target
  rejection and the updated exact child blob requirement.
  These are NOT new live pointer results.

Run the three inert prerequisites before the next optional
single-command isolated nested probe from clean fast-forward-only
`dev`, now that a native pointer CLI is available. Evaluate
`target_alignment` on both controls and
`underlay_target_alignment` on the enabled body before attributing
the failure. If both controls and body-underlay alignment match
but the daemon did not react, design a **separate test-only**
production-host visibility/input-mask diagnostic without changing
the production mask. Do not shrink the mask, disable default-off
behavior, infer visual qualification or modify `stable`.


Diagnostic receipt backend provenance follow-up: source-only commit `6670066439c8899b42ba528e5cf81f9b71ce9ee4`
also projects the private child's bounded `injection_backend` classification
into the sanitized top-level `native_pointer_backend` field. This
distinguishes `forced_wlr_protocols_wdotool` from
`native_relative_wlrctl_unverified` when analyzing alignment, without
publishing the user's executable path or environment. The coordinator
self-review count advances from eight to **nine** reviewed commits.
`1de19ca38f1738e0167b01a169c63f67d43cf1a4` adds an
inert contract assertion for the allowlisted provenance field.
The new coordinate-verified pointer run still needs local execution.


## Coordinate-qualified real top-edge PASS; private candidate A/B staged

The new exact-source real production receipt
`docs/archive/companion/receipts/2026-10-01/wull-pointer-acceptance-20261001T161911Z-4d87f846-391d8e81d461.json`
was published on source
`391d8e81d4617a6dbdb1199d009db4e0970ce073` and is **PASS**.
The separately owned one-output nested Niri had distinct verified
Wayland and IPC sockets, zero preexisting witness/production namespaces,
and a privately built REAL Rust `inir-companiond`. The precise
native backend was `forced_wlr_protocols_wdotool`.
The underlay separately confirmed *correct requested actual coordinates*
for both the Wull-disabled body-center control and Wull-enabled exterior
pass-through control. At Wull's enabled body center, the underlay saw
no click and the actual production bridge emitted exactly one real
click with the private native Rust daemon subsequently recording its
happy/pulse reaction. All owned production/underlay layers, private
daemon and nested compositor were cleaned; host output count was
unchanged. The earlier count-only FAILED receipt does not override
this newer coordinate-qualified test. This PASS applies ONLY to the
unchanged full-host input mask, one top edge on one nested output:
it is not proof of a narrower mask, all four edges, popup
noninterference, live host visual quality, canonical-wide validation,
suspend/reload/multioutput, or long-run whole-shell resources.

That PASS also observed **no underlay click at an empty location
inside the current full 112x98 Wull host**, and no accidental
body activation there. Although this is consistent with the current
full-host production mask, the empty-margin negative result alone
cannot independently attest precise pointer coordinates. A follow-up
private A/B comparison MUST show the *positive* correct-coordinate
underlay margin click for the candidate.

Source-only follow-up for the explicit separate A/B gate:

- `scripts/wull-private-mask-candidate.py` (created
  `e3da0c57264cb44f26045e285f14b22a301a06ba`) verifies
  the EXACT real production `Region` and centered top-edge
  76x92 `AbyssCompanion` source. It replaces precisely that
  one input-mask Region in a PRIVATE copy of
  `modules/abyss/AbyssPerimeter.qml`, shadowing only the Abyss
  module directory in an isolated test shell. Every other
  module remains an unchanged symlink to the pinned checkout.
  The test-only candidate uses a rectangular top-edge size=1
  centered 76x92 body footprint; this does not establish
  a curved silhouette mask or multi-edge fitness.
- `11ecc21ad115fd0c683f3c7ce0c2e003e58f256d`
  and `975482cd8a49475d9eb622d7b38c49aa601ec2bf`
  add private candidate staging and **same-owned-nested-Niri**
  baseline/candidate sequential comparison inside the child.
  The baseline full-host mask must qualify FIRST (disabled
  body, enabled exterior, real bridge/Rust body), and then
  show its expected no-underlay empty-margin observation.
  The child stops and unmaps that actual baseline source
  before launching a NEW private candidate fixture with
  separate real Rust trace. Candidate must independently
  confirm enabled exterior underlay alignment, body bridge
  click+real Rust response with no underlay click, and
  positive exact-coordinate underlay reception at the
  otherwise-empty Wull host margin without an extra body
  activation. A candidate requiring a different toolkit,
  ambiguous pointer result or unable to unmap its baseline
  must NOT claim PASS.
- `244b6a95a485ff669506614958832e2715cb3e3c`
  adds an explicit opt-in to the existing guarded parent:
  `--acknowledge-nested-pointer-candidate`. Only this mode
  passes the private candidate flag; the old
  `--acknowledge-nested-pointer` path continues to use
  the unchanged production source. The coordinator pins
  exact candidate-generator and child blobs and has
  ten guarded revisions; a production or dependency edit
  cannot silently pass the old source audit. It requires
  the native **absolute** Wayland protocol backend
  `wdotool` for the initial A/B geometry gate.
  Its sanitized result uses a DIFFERENT unique prefix
  `docs/wull-mask-candidate-*.json`; all private mouse
  coordinates and raw logs stay outside the checkout.
- `scripts/test-wull-private-mask-candidate-contract.py`,
  created in `b705c2b224ff432e06e4268b25fb8ba7d84626f3`,
  exercises exact single-marker replacement, refusal
  of changed production source, shell-private-only
  module staging and anti-overwrite constraints with NO
  compositor or input. `55e191bb119be6e7f7d47150dff8876db0fb6fe8`
  re-anchors the existing nested-pointer inert source
  contract. All four current inert pointer contracts must
  PASS on one clean checked-out `dev` SHA before an
  opt-in private A/B execution.

**Status: new candidate gate STAGED IN SOURCE ONLY, not locally
executed.** Do not edit the production Region based solely on
the current top-edge full-host PASS. Next review the unique
candidate report (including BOTH stage check sets, matched
witnesses, real bridge/Rust and owned cleanup) before considering
a minimal real production integration, which would still need
four-edge, hover/popup and live-host qualification. `stable`
and shipped default-off Wull have not been changed.


## Private top-edge A/B PASS; bottom-edge qualification staged

The new maintainer-owned real comparison receipt
`docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T165308Z-a3bc585f-124f02155679.json`
on exact source `124f02155679949e60a810e54a9c216fbfd2fabe`
has overall **PASS** on one top edge with scale=1 and a single
privately owned nested Niri output. The original production full
mask qualified in the SAME private compositor first: actual disabled
body-center and enabled exterior clicks had `target_alignment=matched`,
the enabled body click reached the real production bridge and private
Rust happy/pulse without touching underlay, and the old full-host
empty margin remained blocked (no body click). The candidate copied
ONLY the guarded `AbyssPerimeter.qml` input region outside the
checkout; it separately demonstrated an aligned exterior underlay
click, a real body bridge/Rust click with no underlay click, AND a
positive `target_alignment=matched` underlay click at the formerly
blocked empty host margin with no accidental body activation.
Nested identity, process/layer cleanup and host-output count passed.
The backend was native `wdotool --backend wlr-protocols`. This is
**positive evidence for the private rectangular candidate at top,
scale=1, one nested output**, not proof of full deployment safety
or a reason to edit production already. Production Wull and
`stable` remain unchanged.

Next source-only staged gate: a guarded private **bottom edge**
A/B trial. A prior exact-source postchange offscreen production
geometry receipt
`docs/archive/companion/receipts/2026-10-01/wull-production-geometry-20261001T151838Z-fd6d4452-fca3953264b1.json`
observed the centered Wull body on all four edges:
top/bottom full host 112x98, body BBOX (18,3,76,92);
left/right full host 98x112, rotated body BBOX (3,18,92,76).
This is geometry only, NOT actual four-edge pointer acceptance.
`scripts/wull-pointer-targets.py` (commit
`62c483451d91c7b0e5e1f1184fd84f8b04443c14`)
now proposes conservative four-edge body center, host empty margin
and exterior candidate points, with pure bounds validation; its
original `top_edge_targets` still drives the exact same top path.
`scripts/wull-private-mask-candidate.py` (commit
`5b928b852664e8369f74fa17243e78cc92a402c8`)
generates a PRIVATE body BBOX Region that selects 76x92 on
horizontal edges and 92x76 on vertical edges, conditioned on
reviewed interactive host state, allowed edge and size=1. It
guards exact centered production body/rotation source and replaces
only one old mask Region. Despite generating all four variants,
ONLY the top variant has the independent real pointer evidence.

`4e32eaa1f874540b5f71ceca34c5a4b697734568`
adds an allowlisted `candidate-mask-bottom` child mode with the
correct bottom production config and target geometry; the default
legacy production and original top candidate modes continue to
select top. `3309b00ac035ff5944283073aef8e181382339e8`
pins those reviewed child/candidate/geometry blobs and adds a
DIFFERENT explicitly opt-in coordinator argument
`--acknowledge-nested-pointer-candidate-bottom`.
Bottom reports have a distinct unique
`docs/wull-mask-bottom-*.json` prefix and a bottom-specific
scope, while top uses its original distinct report prefix.
The coordinator's reviewed self-revision guard advances to 11.
`4d5080b87951885e40b920d6e603a5e064f35cb9`
extends the all-private inert mask contract with the four
offscreen-measured BBOX relationships and top-path equivalence;
`6b210355f794d2490059f5de46251ece32f313ea`
updates the original nested pointer source-pinning and
bottom-only opt-in assertions. The next LOCAL trial must execute
four inert pointer tests first, followed by a fresh top candidate
regression (because the private mask generator is now dynamic),
and only if that returns an explicitly observed PASS, run the
bottom candidate mode on its own private owned nested compositor.
The bottom run independently re-verifies old production full
host controls and then private candidate controls.

The bottom-stage source is reviewed but **NOT locally executed**
as of this checkpoint. Do not promote this provisional BBOX
to shipped production while bottom/right/left live pointer,
hover/popup, host visual quality, true multioutput/lifecycle
and canonical-wide gates remain outstanding.


## Follow-up: new top A/B run is INCONCLUSIVE on first candidate exterior witness

The temporary-clone run has produced a new real,
unique exact-source report
`docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T170950Z-105fd7a8-1518db798d10.json`,
source `1518db798d1012592cdbceb29115cceb72cffd9b`,
overall **INCONCLUSIVE**. The full-host production
disabled-center and enabled-exterior controls both aligned
with the requested coordinates, and its enabled body
click reached both the production bridge and the real
private Rust daemon. The old full-host empty margin
remained blocked. After destroying the old production
stage and remapping the private BBOX candidate in the
SAME nested output, the FIRST candidate enabled-exterior
underlay click occurred at an **off-target** location.
No candidate body, margin or bottom-edge measurements
were performed in this new run. All private layers,
Rust processes and nested Niri were cleaned, and host
output count remained unchanged.

This outcome does NOT overturn the separately
source-pinned top-edge private-mask PASS from
`124f02155679949e60a810e54a9c216fbfd2fabe`,
but does require investigation of physical pointer
repeatability across stage remapping before using
the newer dynamic BBOX generator to qualify bottom.
Do not label an off-target *underlay* click a Wull
mask defect. Do not increase positional tolerance
or silently retry until a flaky first event disappears
and then mark the run PASS.

New read-only, source-only retrospective helper
`scripts/wull-private-pointer-drift-diagnostic.py`
(created `55907217e8e1a18d9ae74cc5b129578db45f1aa8`,
receipt-symlink check fixed
`a0f1e06f2f934298312e19a2df74563e604bc395`)
takes that ONE sanitized report and finds its
private exact-run underlay log by the report's
random session ID in the current user's
`XDG_STATE_HOME/hadalis/wull-pointer-<id>`
(or `~/.local/state`). It requires the exact
five-check observed sequence, exactly three
real left-click underlay witnesses, valid
same-source suffix and the forced native wdotool
backend. It compares the first production exterior
witness and the candidate exterior witness,
which deliberately share the **same** requested
coordinates, and returns only horizontal/vertical
direction categories and a coarse maximum-offset
bucket. It also checks whether the candidate
event landed near the earlier disabled-center
witness, a possible stale-event indicator.
No absolute mouse coordinates, raw log or private
environment data enter GitHub. The helper does
NOT move the pointer, run Quickshell or change
the checkout. Independent synthetic/parser tests
were added in
`06c640e1ee1385e75524c6c3eb2a3650c2ffa031`.

NEXT: obtain this read-only categorical
diagnostic from the maintainer's **existing**
private log. If the log is missing or the
witness count is ambiguous, keep the result
INCONCLUSIVE and design a new explicit
bounded isolated pointer instrumentation,
not a blind repeated full-suite retry.
Avoid speculative timing or driver workarounds
until that evidence exists. The existing
bottom-edge candidate source remains STAGED,
not physically qualified. Production region,
default-off and `stable` remain unchanged.


## Retrospective old-log classification can now publish sanitized evidence from isolated clone

The earlier dynamic private top candidate report
`docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T170950Z-105fd7a8-1518db798d10.json`
is still **INCONCLUSIVE** on its first candidate exterior coordinate
witness. No second real top pass and no bottom real receipt have been
published as of the source-only next gate. The old private underlay log
may still hold a precise explanation about whether the candidate first
exterior hit deviated horizontally, vertically or possibly reflected
a stale previous position. Without that private observation, it is
incorrect to choose a timing adjustment, increase tolerance, rewrite
production, or assert a virtual-pointer backend fault.

`scripts/wull-private-pointer-drift-publish.py` (source-only commit
`dc06dd36aabc688f1945205bb4a814c58f91d90e`) is a separate
**explicit opt-in retrospective** publisher. It requires a fresh,
clean, permission-private `dev` clone under
`${XDG_STATE_HOME:-~/.local/state}/hadalis/wull-drift-publish.*/repo`,
verifies the trusted GitHub origin/push URLs, exact old public
report blob, exact reviewed read-only diagnostic script blob and
ancestry of the original source SHA, and reads ONLY the original
run's existing private underlay log. It requires exactly the known
off-target receipt sequence and exactly three left-button underlay
witness records. It constructs a strict public schema consisting of
pre-reviewed classification enums, a single boolean for proximity
to the old disabled-center witness, Git source provenance and
explicit no-input/no-production-change annotations. It never
publishes or prints raw screen coordinates, raw logs, usernames,
session paths, screenshots or private runtime endpoints.
Its distinct fixed-name JSON report is
`docs/archive/companion/receipts/2026-10-01/wull-pointer-drift-20261001T170950Z-105fd7a8-1518db798d10.json`.
It refuses to overwrite an existing report.

The clone-only publisher synchronizes by **fast-forward** on fresh
`dev`, creates only its own sanitized report commit, pushes
non-forced, and, if another Cloud Bot publishes concurrently, may
rebase ONLY its own single unpublished sanitized report after
verifying the old parent is an ancestor, current exact source pins
still hold, and the changed path is exclusively its own report.
It does not fetch/merge/rebase/reset the maintainer's original
potentially diverged checkout. If the private prior-run log has
been deleted or cannot prove an unambiguous three-event
sequence, publishing stops **INCONCLUSIVE**, and no new
cursor action is taken.

`scripts/test-wull-private-pointer-drift-publish-contract.py`
(added `fbd1e709b0b64046afa9e619426e409973dce59b`)
provides an inert payload sanitization and explicit-action
safety contract. This new helper and contract are source-staged;
their run result and old-log classifications must not be
represented as successful before a real local invocation.

An independently researched possible future discriminator,
NOT an identified cause: the external `wdotool`
documentation confirms the `wlr-protocols` backend issues
absolute `motion_absolute` using an enumerated output
and documents `wdotool prime` for maintaining virtual
input devices between commands. Upstream testing notes
the importance of compositor roundtrips for dispatch
reliability:
https://github.com/cushycush/wdotool and
https://github.com/cushycush/wdotool/blob/main/docs/testing.md .
The existing Wull child currently invokes `mousemove`
and `click` in separate short-lived CLI processes.
This makes persistent-input-session behavior a
**hypothesis to test only after** the existing private
log classification has been received. Do not introduce
`prime`, host-global input or a new backend on assumption.


## Retrospective drift verified; new pre-candidate witness and output-geometry guard

New real read-only retrospective evidence was published on `dev`:
`docs/archive/companion/receipts/2026-10-01/wull-pointer-drift-20261001T170950Z-105fd7a8-1518db798d10.json`
at publisher source `5164395aea401bcfcd79fa8e74622d34fe5fceb5`.
The source-verified classifier consumed exactly three old, previously
private, underlay left-button witnesses from the
`1518db798d1012592cdbceb29115cceb72cffd9b` A/B session.
The candidate's first exterior event, versus the earlier
production exterior event at the **same requested location**,
was classified `offset_bucket=ninety_six_or_more`,
`offset_axes=both`, negative horizontal and positive vertical.
It was NOT near the old disabled-center witness. These are
categorical results only: maximum-axis magnitude at least 96
logical pixels; exact x/y remain private, and no extra pointer
injection was performed by the classifier. Thus a simple replay
of the old disabled-center coordinate is not supported. This
still does NOT identify whether the transient position originated
from the virtual pointer's device lifecycle, Niri remapping,
underlay geometry, race/order or a changed output mode. The
candidate's input mask should not be altered on this evidence.

A source-only, explicitly opted-in **differential** follow-up
was added in `scripts/wull-manual-pointer-child.py` commit
`5b79c09aabb2f5b50895d0d4c0b38c86cffe4248`.
The same one-output/private Rust/Niri source-verified pointer
runner now uses `output_geometry_signature` to require that
the one live nested output retains its initial logical x/y,
width/height, scale and current mode **before every native
motion/click command**. Unknown/changing geometry stops
the test inconclusively; it is not accepted as a valid mask
failure. After the full production baseline controls PASS
and its original layer and private daemon have fully
stopped/unmapped, but BEFORE mapping the candidate, the
child now injects ONE independent real exterior left-click
on the unchanged full-output underlay, with the **exact same
target** used in both other exterior controls.
This `after_baseline_unmap_exterior_underlay_control` must
report `target_alignment=matched`. If already off-target,
the run is **INCONCLUSIVE** with reason
`post_baseline_unmap_pointer_target_unverified`, assigning
investigation to the intermediate stage rather than the
candidate mask. If matched, only then does it map the
temporary candidate, require a new true Rust-present signal,
and perform its already-existing separate first candidate
exterior coordinate check. A later candidate-only
`off_target` narrows the investigation to the interval
after the new private layer remap (but STILL is not
proof that candidate QML mask itself is faulty).
All events remain solely in owned nested Niri with
`wdotool --backend wlr-protocols`; no host-global
input, new dependency, auto-retry, loosened tolerance,
raw coordinate publication or production source edit.
The old top-size1 and both new top/bottom options
remain explicit separate modes, with the bottom gate
requiring a fresh independent top PASS on the CURRENT
dynamic generator first.

Coordinator commit
`3ede937c9b70284de76dcb5fc1724abe0da09500`
re-pins that exact reviewed child and advances its
self-revision guard from 11 to 12.
`7a4a935afa99a1712bbeba7e4e7d0928de0b01c4`
adds inert pure logical-geometry drift, invalid topology
and child source marker checks to the existing pointer
contract; `485cc1ec307980c9cc07af1ecccc7ea5ad75462a`
re-pins the candidate-mask contract and requires
the intermediate control. These updated inert tests
are SOURCE-STAGED, **not yet executed on local Niri**.
The next grouped local execution needs all four original
inert pointer contracts followed by **one** full
exact-source top-edge differential probe. Only if the
new top probe produces a complete independently verified
PASS is a subsequent bottom-edge probe authorized.
Neither the prior old-generator top PASS nor the
current old-run classifier means that the new dynamic
four-edge candidate has been physically accepted.

Upstream documentation: wdotool's native
`wlr-protocols` backend implements absolute
`motion_absolute` in output pixel coordinates; its
`prime` command can keep virtual devices alive between
CLI invocations. This is a plausible *alternative
hypothesis*, NOT independently validated as the cause,
and is deliberately not enabled by this differential
probe. See https://github.com/cushycush/wdotool .


## New exact-source dynamic TOP A/B PASS with pre-remap discrimination; BOTTOM next

The new real independently owned single-output nested-Niri report
`docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T173129Z-ce33db3c-8efa0b7d7341.json`
has `source_sha=8efa0b7d73418af9fc52b117199e2a691e0158ac`,
`status=pass`, and
`native_pointer_backend=forced_wlr_protocols_wdotool`.
Unlike the previous `INCONCLUSIVE` dynamic-generator probe, this
run includes the NEW discriminating
`after_baseline_unmap_exterior_underlay_control`: the old
full-host production stage was stopped and all its private
layers/Rust processes were unmapped before an independent
exterior underlay click confirmed **matched** coordinates.
The baseline itself had correctly aligned disabled-center and
enabled-exterior control clicks, a genuine enabled body bridge
click and a real private Rust happy/pulse reaction with no
underlay body click, plus an observed blocked empty
full-host margin without accidental body activation.

After the intermediate control PASS, the PRIVATE dynamic
four-edge BBOX generator was instantiated on **TOP, scale=1**
only. It independently confirmed a correctly aligned
exterior underlay click, exactly its expected actual
body bridge/Rust click without underlay click, and a
positive **matched** formerly blocked empty-margin
underlay click without activating the body. Nested
Wayland/Niri endpoint isolation, a single clean output,
owned private layers/Rust daemon/compositor cleanup, no
private strays and unchanged host outputs ALL passed.
No shipped production QML mask, default-off behavior
or host user configuration was changed.

The earlier dynamic-generator
`docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T170950Z-105fd7a8-1518db798d10.json`
remains **INCONCLUSIVE** after a first candidate exterior
off-target click, and its old-log retrospective diagnosis
documents large two-axis drift. The new independent
PASS is positive TOP evidence, NOT proof that the
earlier transient was cured or that all pointer events
are deterministic. The new intermediary witness
bounds WHERE future repeat drift may begin, but an
all-PASS trial cannot establish WHY the earlier
drift occurred.

**Next independent real gate:** run ONLY
`python3 scripts/wull-manual-nested-pointer.py
--acknowledge-nested-pointer-candidate-bottom`
from a fresh clean permission-private `dev` clone
after the four inert pointer contracts succeed.
The bottom trial must qualify its own existing
production full-host controls first, then the
post-baseline-unmap exact-target witness, then
the independently mapped bottom private dynamic
mask exterior/body/margin witnesses with real
Rust and full owned cleanup. Publish under distinct
`docs/wull-mask-bottom-*.json` and inspect that
unique exact-source report before any side-edge
expansion. Do not interpret off-target underlay
coordinates as a Wull production-mask failure.
Bottom/left/right live pointer, hover/popup,
true multioutput and scaling, real visual quality,
long-run/lifecycle and canonical wide validation
remain unqualified. Keep production Region and
`stable` unchanged.


## REAL bottom private A/B PASS; standalone right candidate next

The NEW independently verified actual Niri pointer receipt is
`docs/archive/companion/receipts/2026-10-01/wull-mask-bottom-20261001T173542Z-10d599c4-9ac701f650dc.json`,
`source_sha=9ac701f650dce381487fa00a56f24520c5c83289`,
`status=pass`,
`scope=owned_single_output_nested_niri_bottom_candidate_mask_A_B`,
`native_pointer_backend=forced_wlr_protocols_wdotool`.
All eight existing phase checks succeeded with actual
source-pinned bottom position and one newly owned private
Niri output: correct-coordinate old-production
disabled-center and enabled exterior underlay controls,
the real production Wull bridge/Rust happy-pulse body click
without underlay penetration, observed full-host
empty margin blocked with no false Wull activation,
the new exact-target exterior underlay click AFTER
baseline fully unmapped but BEFORE candidate mapped,
then the newly mapped bottom **private** dynamic BBOX
candidate's independently correct-coordinate exterior,
genuine Wull body bridge/Rust click without underlay
penetration, and positive matched empty-margin underlay
pass-through without accidental body activation.
Original host output count and all distinct nested
endpoints, owned-layer/daemon/compositor cleanup and
private stray checks passed. Nothing changed the real
production input Region, user host config or `stable`.

This adds independent real evidence for the BOTTOM
horizontal mask, in addition to the separately source-
pinned latest dynamic TOP private candidate PASS
`docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T173129Z-ce33db3c-8efa0b7d7341.json`.
The older top trial's categorically proven transient
off-target wdotool underlay click remains an unresolved
reliability observation; later PASS trials do NOT prove
the transient root cause was corrected. The two horizontal
edge PASSes are bounded one-output, size=1,
private-shadow BBOX results, NOT global or production
input-mask acceptance.

The NEXT independently qualified physical orientation
is **RIGHT**. Existing reviewed
`scripts/wull-pointer-targets.py` already computes
the side-edge host 98x112 and the rotated mapped body
BBOX x=3,y=18,width=92,height=76, using exact prior
postchange source-measured geometry. The reviewed
dynamic shadow candidate already branches to
a 92x76 centered BBOX on left/right with correct
input state and scale=1 guards. Those source and
geometry results have not yet proved right/left
physical pointer routing.

The child-only mode `candidate-mask-right`
is newly explicit and separately allowlisted
(`scripts/wull-manual-pointer-child.py`
commit `555d735f2a99fd18b7588d757810c009e5ebfea2`).
The unchanged production/full-host, intermediate
after-unmap witness, and candidate body/exterior/
margin checks now select the reviewed **RIGHT**
geometry/config only if that mode was explicitly
set by the same nested-only parent. Parent
`scripts/wull-manual-nested-pointer.py`
commit `a86e2284907207bb0811a820298e5bd57bcfd3ed`
pins the new exact child blob, advances its
reviewed self-history guard to 13 and adds
`--acknowledge-nested-pointer-candidate-right`.
It reports only
`owned_single_output_nested_niri_right_candidate_mask_A_B`
with a unique `docs/wull-mask-right-*.json`
prefix. Existing top, bottom and original production
explicit opt-ins are otherwise unchanged. The two
separate inert source contracts re-pin the new child
and right-only permission/receipt markers in
`ef65b9483b78cba5b6f0c7bcbff55593cd7078dc`
and `b627e658fb4e4a53dc07a967c0d19a96c96d45f1`.

The next one-command local gate from a NEW clean,
permission-restricted temporary `dev` clone should
run all four existing inert pointer contracts and
ONLY the explicit new RIGHT physical private A/B test.
It must publish a new unique sanitized exact-source
right receipt regardless of PASS/FAILED/INCONCLUSIVE
and stop without automatically testing LEFT or
altering production. Inspect every witness, exact
forced native backend, private Rust response and
owned cleanup in that receipt first. Do not
promote a private rectangle to shipped production
on only three edges. LEFT, popup/hover, live
visuals, actual multioutput/hotplug/fractional
scaling, canonical-wide and long-running lifecycle
gates remain separate and pending.


## REAL right private A/B PASS; independent left-side candidate staged

New exact-source sanitized real pointer report:
`docs/archive/companion/receipts/2026-10-01/wull-mask-right-20261001T174248Z-cd6a3010-cdbe02bbcd61.json`,
`source_sha=cdbe02bbcd61720f07852fd7eb62929d14004188`,
`status=pass`, scoped ONLY to
`owned_single_output_nested_niri_right_candidate_mask_A_B`
with forced native absolute `wdotool --backend wlr-protocols`.
On one newly owned verified single-output nested Niri,
the unchanged production full-host mask passed
disabled-center and enabled-exterior matched underlay
controls, genuine body bridge plus private real Rust
happy/pulse with NO body click to underlay, and
observed blocked full-host empty margin without
accidental Wull activation. Full-production layer
and private Rust cleanup completed; the new distinct
`after_baseline_unmap_exterior_underlay_control`
passed before the private side-edge candidate was
mapped. The private RIGHT dynamic side BBOX passed
independently correctly aligned exterior, real
body bridge/Rust without underlay click, and
positive matched previously blocked empty-margin
underlay pass-through without false body activation.
One-output nested isolation, all owned process/
layer/compositor cleanup, no strays and unchanged
host outputs also passed. Shipped production, user
configuration and `stable` were unchanged.

This is real bounded private RIGHT evidence alongside
the independently source-pinned new TOP and BOTTOM
private A/B PASS reports; it is NOT evidence that
the existing production mask was changed, accepted
outside scale=1 or qualified visually. The earlier
large two-axis first-candidate exterior off-target
TOP observation remains a genuine unresolved
repeatability finding, regardless of later PASSes.

A separate explicit private LEFT physical gate
is SOURCE-STAGED, NOT YET RUN. The old-reviewed
production postchange geometry measured vertical
host 98x112 and rotated body BBOX (3,18,92,76)
on both side edges; the existing private shadow
generator already branches to the centered
92x76 side-edge Region, guarded by input policy
and size=1. Updated child
`scripts/wull-manual-pointer-child.py` commit
`57d81d35e1e0f6543f61195f275eba5cd5f0a982`
adds exactly `candidate-mask-left` as a
separate opt-in mode, selects the existing
left-side production config and source-pinned
four-edge pointer target helper, and otherwise
preserves actual production/full-host, post-unmap
and private candidate controls. Coordinator
`scripts/wull-manual-nested-pointer.py` commit
`5e2ca4470c04926b7200df89b730bded154eed7b`
pins that reviewed child blob, advances its
self-history count 13 -> 14, and permits the
independent explicit
`--acknowledge-nested-pointer-candidate-left`
argument. LEFT has its own receipt scope
`owned_single_output_nested_niri_left_candidate_mask_A_B`
and distinct `docs/wull-mask-left-*.json`
prefix. Original production/top/bottom/right
opt-ins and prefix/scope identity are retained.
The inert source contracts were re-pinned and
strengthened to require the new separate left
opt-in and scope, plus independent left-side
private vertical QML staging in commits
`db97e763d244a98ba6a351b3568658255749b7fa`
and `ccfbe7e947e82c3865651f6aeaf90dbbd1a07c20`.
Source inspection confirms the new helper,
coordinator, test pins and unchanged production
blobs; local execution of the revised inert
contracts and real LEFT probe are still pending.

NEXT LOCAL GATE: from a clean temporary
private `dev` clone ONLY, first run the
four inert Wull pointer/source contracts,
then perform a single independently
owned nested Niri LEFT private A/B test
using the new left-only argument. Publish
a distinct exact-source
`docs/wull-mask-left-*.json` receipt even
when FAILED or INCONCLUSIVE; inspect ALL
control target alignment, genuine bridge/
Rust response and owned cleanup before
any release decision. Do not auto-run
canonical/global and do NOT promote
the rectangular candidate into the real
production Region based merely on four
single-output pointer runs. The
nonrectangular curved body silhouette,
hover/popup interaction, visual fit,
multioutput/fractional scale/hotplug,
suspend/reload/long-running resources
and canonical validation remain separate.


## First real LEFT run INCONCLUSIVE at final empty margin; five-witness no-input gate

Independent LEFT private-side mask report
`docs/archive/companion/receipts/2026-10-01/wull-mask-left-20261001T175020Z-5a11aa42-5b72e0e3294c.json`
was actually published on `dev` from exact
`source_sha=5b72e0e3294c32276c306b3c6911fd9fa4e79fb1`
with `status=inconclusive`, NOT PASS,
`child_reason=candidate_margin_target_unverified`,
`native_pointer_backend=forced_wlr_protocols_wdotool`.
Its first SEVEN separate real witnesses passed:
disabled full-host body-center underlay alignment,
enabled production exterior alignment,
genuine production body bridge/real Rust
happy-pulse without underlay penetration,
observed blocked full-host empty margin with
no false Wull activation, separately
matched post-baseline-unmap exterior click
BEFORE the candidate mapped, independently
matched exterior click AFTER the new private
LEFT candidate mapped, and genuine candidate
body bridge/real Rust response without
underlay penetration. The eighth real check
`candidate_empty_margin_pass_through`
did produce an actual underlay event and did
NOT falsely activate the Wull body, but its
recorded location was `target_alignment=off_target`.
The runner therefore correctly stopped
`INCONCLUSIVE` instead of classifying the
side-edge BBOX as a failed input mask or
claiming pass-through acceptance. Separate
private Niri, owned-layer/daemon cleanup,
no strays and unchanged host outputs passed;
production mask, user config and stable
were untouched.

Before asking the maintainer for another
real pointer trial, the original exact-session
PRIVATE underlay log can discriminate a
final-stage pointer position discrepancy.
The source-pinned previous LEFT child and
pure target code have fixed logical left
body-center and inside-empty-margin targets:
`body=(round(x+49),round(y+56))`, margin
`inside=(body[0],round(y+9))`. Thus their
REQUESTED x is identical and the requested
margin y is 47 logical pixels above the
body center, within at most 1 px of
round-half-to-even ambiguity. The old
disabled-body-center underlay control
was explicitly `matched` (max 6 px
error); exterior underlay controls before/
after baseline cleanup and after private
candidate mapping all request the EXACT
same separate exterior location and are
individually `matched`. No real underlay
events were observed in production
empty margin or either enabled body click.
Therefore the old log should contain
exactly FIVE, unambiguously ordered,
real left-button underlay clicks:
disabled body center, enabled exterior,
post-unmap exterior, candidate exterior,
and the final off-target candidate margin.

`scripts/wull-private-left-margin-diagnostic.py`
(created `5b09ca99107ea1c7107c3d32d3e1e40eabc1077e`)
is a read-only, no-compositor/no-pointer
tool for ONLY this exact old public report.
It requires its original SHA, exact
eight-check order, actual real Rust/bridge
body responses, cleanup, forced native
backend, five correctly shaped private
left-button log witnesses and repeatability
of the three previously matched same
exterior targets (max 12 px relative).
The candidate's final observed underlay
point is compared categorically against
the earlier actual aligned disabled
body-center witness shifted vertically
by -47, allowing 7 px uncertainty from
the previous witness and source rounding.
It returns ONLY coarse magnitude
bucket, evidence-supported axis and
sign, and booleans for proximity to
previous disabled-body and candidate
exterior positions. It cannot
recover the precise requested or
observed x/y from the public report;
it never outputs actual private
coordinates, private paths or full logs,
and cannot establish causality. If
its five-event sequence is ambiguous,
the correct outcome remains INCONCLUSIVE.

`scripts/wull-private-left-margin-publish.py`
(created `008cd132c79dd657b361e76b8a8ef64aea5bac02`)
is an optional separate EXPLICIT
publisher of its allowlisted categorical
result in a permission-private fresh
`dev` clone only. It pins the exact
diagnostic and original public LEFT
report blobs, and the original
test child and target source blobs
at the report source commit. It
verifies a trusted fetch/push origin,
original source ancestry, user-owned
original private log, no untracked
files, and the exact public enum/boolean
schema, and publishes exactly one
uniquely named new redacted result to
`docs/archive/companion/receipts/2026-10-01/wull-pointer-left-margin-drift-20261001T175020Z-5a11aa42-5b72e0e3294c.json`.
Its non-forced concurrent Git retry
may rebase ONLY its own single
unpublished redacted receipt commit
within the private clone, with
post-fetch source/ancestry and
changed-path audits. It never
merges/rebases/resets the user's
original divergent checkout, starts
new Niri, Rust or wdotool, or
modifies real QML. Both independently
inert parser/negative-case and
redacted-payload/clone contract tests
are staged as
`scripts/test-wull-private-left-margin-diagnostic.py`
(created `778d5fa5ad42666bdb6a5d1c8ba7af5cdf65b1e3`,
corrected `f4024d971c7971b38472f3fd93cd6e4ab16ccdf2`)
and
`scripts/test-wull-private-left-margin-publish-contract.py`
(created `cfb24dc8fc9f58fe9dc1ccbbd0ebf7b8e1b2c68e`).
These additions are source-staged,
NOT YET locally run and no new
retrospective LEFT report has been
published at this checkpoint.

NEXT LOCAL GATE: run both strictly
inert retrospective contracts in
an entirely fresh permission-private
dev clone, then ONLY explicitly
classify the prior LEFT five private
underlay witnesses and publish the
redacted categorical receipt if valid.
If the old private log is absent or
source-pinned witness count is
ambiguous, STOP INCONCLUSIVE,
do not silently repeat the LEFT
physical pointer test. If evidence
is valid, use relative axis/direction
and stale-position booleans to
design a BOUNDED new independent
pointer instrumentation, if needed,
before an isolated new LEFT trial.
The existing TOP, BOTTOM and RIGHT
separately source-pinned private
A/B PASS reports remain valid within
their one-output, size=1 scopes;
production Region, default-off
and stable remain unchanged.
Even after all four private
BBOX edges eventually PASS,
curved-silhouette hit region,
hover/popup, visuals, multioutput/
hotplug/fractional scaling,
suspend/reload/lifecycle and
canonical wide validation must
remain separately unqualified.


## Existing left margin drift classified; guarded before-body differential now staged

The old single-output LEFT edge source-pinned A/B receipt remains
`docs/archive/companion/receipts/2026-10-01/wull-mask-left-20261001T175020Z-5a11aa42-5b72e0e3294c.json`
(`5b72e0e3294c32276c306b3c6911fd9fa4e79fb1`),
**INCONCLUSIVE** only at final empty-host-margin coordinate witness;
the first seven real controls and complete owned cleanup passed.
The actual old-log categorical report has NOW been independently
published as
`docs/archive/companion/receipts/2026-10-01/wull-pointer-left-margin-drift-20261001T175020Z-5a11aa42-5b72e0e3294c.json`.
It confirms five prior private left-button underlay witnesses
with source-pinned geometry relationships and a final margin event
offset `ninety_six_or_more` pixels in maximum relative axis,
`relative_axes=both`, horizontal `positive`, vertical
`negative`. The final point was near neither the earlier
actual disabled-body-center underlay event nor the candidate
exterior underlay event. This was read-only private-log analysis
and does NOT explain the underlying input-device/compositor/QML
cause. The old real top dynamic A/B also had a distinct transient
off-target event; top, bottom and right have separately verified
later private size=1 single-output real PASS trials. Do not
interpret a single off-target underlay coordinate as a
LEFT candidate mask defect, nor treat later successes as
a reliability cure.

**NEW source-only bounded LEFT differential gate:** child
`scripts/wull-manual-pointer-child.py` commit
`3e9f843906edf1654ef3b150bad9de2413e61826`
adds exactly ONE extra left-only
`candidate_left_margin_before_body_control`
between the already-matched candidate exterior witness
and the existing candidate real-body click. It injects
the SAME pinned left empty-host-margin point as the
original final after-body candidate margin witness.
Both underlay coordinates must align independently
(unchanged original 6-pixel tolerance), and no private
body bridge or Rust response may accompany a
margin control. Its pure
`left_pre_body_margin_decision()`
returns INCONCLUSIVE on ANY non-matched coordinate
or missing/ambiguous underlay event; returns FAILED
on a matched margin event that unexpectedly
activates the real Wull body/Rust; accepts PASS
only on an actual matched underlay left-button
event with zero accidental activation. A non-PASS
stops immediately, without a hidden retry.

If this pre-body margin witness PASSes, the child then
performs its **original unchanged adjacent**
`candidate_body_real_bridge_and_rust` and final
`candidate_empty_margin_pass_through` steps;
it does NOT insert a new intervening exterior
action or change backend, target coordinates,
mouse sleeps, retry policy, tolerance or mask source.
Thus, if pre-body margin aligns but the last
direct body→margin event again misses, the
new receipt will isolate the discrepancy to
a later phase following actual Wull interaction,
without asserting its root cause. If pre-body
margin itself misses despite a matched
candidate exterior control, the discrepancy
is already observable in the earlier
exterior→margin transition, before touching
the candidate body. If ALL checks PASS,
this is one fresh independently observed
left-only single-output private BBOX capability
result, not proof the two historical transient
drifts are permanently fixed.

The runner retains explicit
`--acknowledge-nested-pointer-candidate-left`;
all other mode behavior (original production
and top/bottom/right) is unchanged. Parent
`scripts/wull-manual-nested-pointer.py`
commit `9c36779c39d08cdc95c9882fe79973c02b8622e6`
pins the exact revised child source blob
`8dd65a0d10d5a8d1475be0939dbb78a0f977dd35`
and increments its strict reviewed
self-history count from 14 to 15;
it still publishes under a unique
`docs/wull-mask-left-*.json` name,
without exporting actual screen coordinates.
The original inert pointer contract
`scripts/test-wull-nested-pointer-contract.py`
(commit `c1f274ecc8fe44ec663cdd7a3984dbc81db4ef85`)
now tests the differential decision
for aligned, missing, off-target,
ambiguous and unexpected-activation cases,
including invalid-input rejection.
The original all-private mask contract
`scripts/test-wull-private-mask-candidate-contract.py`
(commit `ddf0f55afbd28ea3dab93986ab3a27952a11c5c5`)
re-pins the changed child and requires
the new LEFT-only witness source marker.
No production QML/Rust, source-measured
four-edge target code, body shape or
current private rectangle generator
changed. These tests are source-staged
and their local PASS has not yet been
observed at this checkpoint.

**NEXT independent local gate:** use a NEW
permission-private temporary clean
`dev` clone, run the same four inert
Wull pointer tests first, then execute
ONLY one explicit left real nested
Niri A/B trial using the same left opt-in.
Allow the coordinator to publish the
unique left result regardless of outcome.
Inspect the intermediate pre-body witness,
original final direct body→margin witness,
real bridge/Rust, forced native wdotool
backend, geometric isolation and full
owned cleanup before deciding further
work. If another off-target event occurs,
stop with INCONCLUSIVE and investigate
the *phase* indicated by the new witness,
not a speculative mask defect or blind
wdotool timing change. Do NOT automatically
promote to production after one bounded
four-edge private PASS. Exact curved
shape input Region, hover/popup,
visuals, multioutput/fractional scale,
hotplug/suspend/reload/lifecycle,
reproducibility and canonical-wide
validation remain separate.


## Full four-edge size=1 private BBOX pointer coverage verified; curved silhouette qualification separated

The NEW exact-source real LEFT differential A/B receipt
`docs/archive/companion/receipts/2026-10-01/wull-mask-left-20261001T180740Z-22d0c52b-df1cb0eef52e.json`
has `source_sha=df1cb0eef52e4089833704c32510d65239c5ae41`,
`status=pass`, verified
`native_pointer_backend=forced_wlr_protocols_wdotool`,
and scope ONLY
`owned_single_output_nested_niri_left_candidate_mask_A_B`.
All nine independent phase witnesses qualify:
the unchanged production disabled body-center and
enabled exterior exact-coordinate underlay controls,
real bridge/private Rust happy-pulse body event without
underlay penetration, observed full-host empty margin
blocked with zero false body activation,
the new pre-candidate-remap exact exterior underlay
witness, and after-remap candidate exterior.
The added LEFT-only
`candidate_left_margin_before_body_control`
measured the SAME empty-host-margin target
**before** touching the candidate body, with one
correctly aligned underlay event and NO accidental
body click. The very next real candidate body click
triggered the actual bridge and private Rust
without an underlay click; the original final
body→margin click ALSO produced a correctly aligned
underlay event with no false body activation.
Single-output nested endpoints, complete owned
Niri/layer/daemon cleanup, zero private strays
and host output invariants all passed; no host
configuration or real production mask was changed.

The four separately published latest source-pinned
real PRIVATE dynamic BBOX trials now cover
TOP `docs/archive/companion/receipts/2026-10-01/wull-mask-candidate-20261001T173129Z-ce33db3c-8efa0b7d7341.json`,
BOTTOM `docs/archive/companion/receipts/2026-10-01/wull-mask-bottom-20261001T173542Z-10d599c4-9ac701f650dc.json`,
RIGHT `docs/archive/companion/receipts/2026-10-01/wull-mask-right-20261001T174248Z-cd6a3010-cdbe02bbcd61.json`,
and the latest LEFT receipt above. This is
**one independent single-output Niri, size=1
PASS per edge** for a PRIVATE source-shadow
RECTANGULAR body BBOX and genuine Rust events,
not a production rollout or statistical
reliability result. Keep the historical
TOP dynamic candidate first-exterior
off-target `INCONCLUSIVE` and the historical
LEFT direct body→margin off-target
`INCONCLUSIVE` together with both categorical
old-log drift receipts. The later successful
LEFT before-body/after-body differential
does NOT explain or cure either historical
transient and does not make unlimited
pointer targeting repeatable.

**NEXT DESIGN GATE: exact shape versus bounded hit region.**
The shipped Wull currently contributes
`Region { item: ... ? companion : emptyInput }`,
which covers the whole companion host footprint.
The tested private generator instead uses the
source-measured static body BBOX, 76x92
(horizontal) / 92x76 (vertical), centered in
the 112x98 / 98x112 host. The actual
`WaterDropletBody.qml` visual outline is
FOUR curved `PathCubic` sections beginning
near its top center, NOT the full rectangle.
Further, the actual droplet has a pulse
halo, state-driven squash/stretch/tilt,
continuous bob/sway and four-edge rotation,
while `AbyssCompanion.qml` supports a
0.65–1.5 host scale. Thus the physical
four-edge scale=1 body BBOX successes do
NOT establish that a static, narrower
silhouette region would capture all
visible/animated body clicks and hover.
Do not remove the host mask in production
based on pointer BBOX results alone.

Quickshell's documented
`Region` API combines nested
Rect/Ellipse regions, allows item-bound
rectangles, and supports subtraction;
`Region.item` uses item geometry,
not alpha or a Qt Quick `ShapePath`
Bézier alpha mask. No documented
portable arbitrary-Bézier clickthrough
`RegionShape` is established for the
repository's target Quickshell version.
The lowest-risk research path is a
separate **INERT, source-pinned static
four-cubic silhouette scanline prototype**:
derive interior bands from the exact
reviewed 76x92 shape, rotate/center
them against already source-measured
four-edge BBOXes, and count conservatively
enclosed hit area, tip coverage and
runtime region budget without touching
any QML or generating a live mask.
Only after the static geometry and
Quickshell version compatibility are
verified should a separately staged
PRIVATE additive Region prototype
be tested with real body/tip/corner,
hover and pass-through witnesses on
new owned Niri runs, then motion
envelopes and size/scale variants.
Rectangle BBOX remains only the
qualified private baseline, not an
approved exact-curve mask.


## Static source-pinned four-cubic silhouette band prototype — inert feasibility only

Source-only research now stages the NO-INPUT, NO-QML-MASK
pure Python `scripts/wull-silhouette-band-prototype.py`
(commit `d9d5ab6d4b80fb1fbf22292c693a66e5464bded3`).
It pins the exact actual `WaterDropletBody.qml` Git blob
`fc5b1c227026786ab553685bc170daff74e82517`
and models **only** the original authored static, 76x92
four-cubic outer droplet outline. It samples each cubic
at 400 subdivisions, intersects the static outline
with each integer pixel scan row at three in-row sample
heights, excludes an additional conservative 1.7px
interior side margin, and coalesces consecutive
rows with identical spans into small integer
rectangles. Each strip is independently mapped
to top, bottom (+180°), left (+90°) and
right (−90°), retaining the previously reviewed
centered 112x98 horizontal / 98x112 vertical
Wull host footprint. Neither helper nor
its companion inert test writes any QML,
runs an input tool, launches a compositor,
edits production or publishes raw cursor coordinates.

An independent source-formula calculation indicates
approximately 43 merged narrow static regions with
3,006 conservatively interior logical pixels,
compared with 6,992 body-BBOX logical pixels
(roughly **43%** of that rectangle), for this exact
pose and inset. This is a **model estimate**,
NOT a run of the new Python contract on the
maintainer host, an interaction-area ergonomic
recommendation, a QML runtime budget benchmark,
or physical compositor proof. The conservative
interior omits tip/stroke and the animated
pulse halo, demonstrating why replacing
the tested BBOX with a tight static
visual intersection could miss genuine
visible user-target clicks. It cannot
derive dynamic transform/halo coverage
from a single shape frame.

The new `scripts/test-wull-silhouette-band-prototype.py`
(source commit `0ebb52dfbf724a9171f71ef26cd664b8ee7f33a8`,
redaction assertion fix `d7465907230d047c0ff647da6b884000f121856a`)
is STRICTLY INERT. It verifies the
exact reviewed body source blob, pure
cubic endpoints and closure,
three-sample per-row geometry and
positive inward margins, disjoint
rectangles on ALL four rotations,
host bounds, area preservation,
invalid input rejection, a bounded
per-edge region count, and an
output summary with NO raw cursor
positions or live approval. Local
execution of this new contract is
not yet observed.

The official Quickshell Region API
supports composition of nested
rectangle/ellipse regions and
`Region.item` geometry, but
does not establish a portable
arbitrary alpha/PathCubic region.
A 43-region scanline representation
is a FEASIBILITY PROTOTYPE only:
possible QML Region creation and
per-frame geometry update cost,
actual Qt transform propagation,
static-inset tip clicks, halo,
motion deformation, hover across
the curved boundary, tiny or
fractionally scaled outputs,
compositor-specific mask resolution
and version compatibility are
UNTESTED. Neither the static
silhouette interior nor the
previously proven static body BBOX
can be promoted to production
without first deciding the
user-visible accessible target
(including halo/squash/motion)
and validating it across
visual, actual nested Niri pointer,
multioutput, scaling and lifecycle
conditions. The tested source-shadow
BBOX remains the existing
single-output, scale=1 physical
baseline. Historical transients
remain open reliability evidence;
the newly verified real LEFT
differential PASS does not make
every mouse event reliable.


## Nominal motion/scale source budget: static 76x92 cannot be certified as an animated hit mask

After FOUR independent real private scale=1, single-output
body-BBOX click PASSes, the next distinct question is whether
a narrower mask remains inside or outside the MOVING clickable
visual. Those earlier test receipts do not answer it.

A new strictly inert,
`scripts/wull-motion-footprint-feasibility.py`
(created in `cf700d32453b20742b4a32882a1b7516d22d0a32`,
corrected actual body-size source marker in
`6a9aeeb9d4738e3fc11ebfaaf5c6a603bb45b3c7`)
pins Git blobs for the exact
`WaterDropletBody.qml`,
`CompanionBridge.qml`,
`AbyssCompanion.qml` and
`AbyssPerimeter.qml` production
files before analyzing source formulas;
it never rewrites or shadows any QML, runs
Niri/Rust/wdotool or reads private pointer logs.
An inert contract
`scripts/test-wull-motion-footprint-feasibility.py`
(source commit
`8786afdbbebb037812f37d8dd27e4fad734321ca`)
covers source pins, negative trust tests,
exact declared baseline values, pure
arithmetical stress counterexample,
all scale-edge source dimensions,
exclusion of spring and exact Qt geometry
claims and a cross-check against the
existing static 4-cubic scanline study.
Neither new Python program has yet been
executed on the maintainer host;
all current findings below are *source
arithmetic*, not actual animated
compositor events.

Specifically the public bridge CLAMPS
incoming body `squash`, `stretch`,
`lean` and `tip` individually to
[-1, 1] and `energy`/`pulse`
to [0, 1]. The real body has a
separate state-specific bottom-origin
`Scale`: `xScale = 1 +
stateSquash*0.05 - stateStretch*0.025`
and `yScale = 1 -
stateSquash*0.035 + stateStretch*0.06`.
Under those nominal incoming
clamps only (NOT measured
`SpringAnimation` extrema) the
axis-scale ranges are [0.925,
1.075] and [0.905, 1.095].
The explicit root tap squash
`scale = 1 + squash*0.035`
has scripted targets 1 and
-0.35 (nominal [.98775,
1.035], not a proven bound
through OutBack overshoot).
The root nominal angle
`2.2*sway + 5*lean + 2.4*tip`
could cover roughly -9.6 to
+10.59 degrees at independent
bridge-clamped input targets
and nominal sway endpoints,
before the separately authored
four-edge 0/90/180/-90 parent
rotation. Nominal bob animation
target values depend on energy:
[-3.6, +1.8] logical px.
These are isolated formula
endpoints, not validated
simultaneous real Rust
states or actual Qt runtime
bounds. `SpringAnimation`
can overshoot, and Qt
anchor vs animated y,
transform composition/order
and item geometry-to-Region
mapping remain unqualified.

There is an important
**possible counterexample to
a static body-BBOX input mask**:
even setting all unrelated
state transforms to identity
and using the otherwise
bridge-permitted target
`stateSquash=0,
stateStretch=1`, the
explicit bottom-origin
body yScale is 1.06.
The authored upper outline
point is at local y=2, and
under ONLY that yScale it
maps to local y=-3.4:
`92 + (2 - 92)*1.06`.
At the centered TOP body
offset y=3 in the
source-measured host,
that nominal tip would
lie at host y=-0.4,
outside both the tested
private static BBOX's
top y=3 and the nominal
host boundary y=0.
This is a source-level
admissible pose calculation,
not evidence that the Rust
backend actually reaches
and sustains that exact pose,
nor a rendered frame
or a conclusion about
Wayland clipping. Even this
single admissible target
invalidates treating a
fixed static rectangle as
a guaranteed animation-
aware hit region without
additional live evidence.

Source configuration further
allows parent scale
[0.65, 1.5]; the default
one-output physical A/B
tests exercised only
scale=1. At nominal 1.5,
the unanimated 76x92
body item scales to
114x138 on horizontal
orientations, which already
exceeds the source-measured
112x98 host footprint
in both axes; its
90-degree rotation
produces a 138x114
body BBOX against
98x112 vertical host.
These simple item-size
comparisons do not
establish actual Qt
transformed hit geometry
or screen clipping:
they establish that
the exact scale/mapping
relationship MUST
be checked before
a runtime mask change.

The static body has
an independent visual
pulse rectangle centered
within the body whose
peak local extents are
76x90.16, and a separate
companion ripple at the
edge. Whether these
decorative effects are
included in the intended
ACCESSIBLE hit target
is a product/UX
decision, not implied
by a tight Bézier path.
An interior-only static
scanline proposal that
covers ~43% of the
76x92 item BBOX
would exclude many
visible border/halo
pixels already at
the unanimated pose.
At maximum motion,
even the static
rectangle can fail
to contain part of
the potential moving
outline. Consequently
do not promote the
43-band static
interior or 76x92
static BBOX into
production. Preserve
the existing full
host input Region
until a new private,
source-guarded
motion/hover
acceptance candidate
has passed its own
physical gates.

**NEXT REQUIRED DESIGN/QA PATH:**
First run both inert
`scripts/test-wull-silhouette-band-prototype.py`
and
`scripts/test-wull-motion-footprint-feasibility.py`
on one new private clean
`dev` clone, optionally
printing their redacted
arithmetic summaries
without starting a
desktop compositor.
Then specify the
desired interactive
contract distinctly for
the visible moving core,
stroke/tip, soft halo
and decorative
edge ripple. Prefer
an intentionally
forgiving moving-body
hit area over a
tightly eroded
visual-only scanline
unless real hover
and tap accessibility
tests support it.
Source-pin the actual
Qt/Quickshell build;
probe runtime
`mapToItem`/
`mapToGlobal`
transforms and
compositor Region
updates, with scale
0.65, 1, 1.5,
four output edges,
animated/rust
state extrema and
fractional/rotated
output cases
separately on
isolated Niri.
Require center,
edge, tip, animated
boundary, empty
host margin and
hover transition
witnesses, real
bridge/Rust response,
output isolation,
low CPU/memory,
popup/keyboard,
hide/reveal, daemon
loss/recovery and
complete process
cleanup before
touching production.
The existing
source-pinned top/left
old-log pointer drift
remains a distinct
reproducibility
blocker for broad
conclusions.


## One-command source-pinned inert geometry+motion evidence publication — not live

The previous standalone static four-cubic
and nominal motion/scale model scripts
intentionally produced no Git receipt,
so a subsequent assistant could NOT
infer the maintainer had run them from
the presence of source files alone.
A new separate explicit
`scripts/wull-motion-inert-publish.py`
(created commit
`d28f85553cec359aca1c66399b636eaae07813bd`)
now provides an auditable
manual evidence publication
gate without touching an
existing checkout or desktop.
It runs ONLY the exact
`scripts/test-wull-silhouette-band-prototype.py`
and
`scripts/test-wull-motion-footprint-feasibility.py`
inert contracts, and
the two source-model
summary commands.
It requires a clean
`dev` clone under a
current-user-owned,
mode-0700, specifically
named `XDG_STATE_HOME/
hadalis/wull-motion-inert.*`
scratch directory.
It accepts only verified
fetch AND exactly one
push remote for the known
Hadalis GitHub repository,
checks the reviewed parent
commit is an ancestor,
pins Git BLOB hashes
of both models,
both inert contracts,
and all four original
Wull production source
dependencies. It
fails closed if any
input test, original
source, parser output
or remote dependency
changes.

Only if BOTH actual
local test processes
exit successfully with
their exact expected
PASS tokens and model
JSON is in the reviewed
inert source-only range
does it publish one
sanitized, uniquely
named
`docs/wull-motion-inert-*.json`
report recording the
exact source SHA, the
two independent local
inert PASS assertions,
coarse static area/band
count, and the precise
source-level nominal
scale/tip risk scalars.
It explicitly records
that actual animated
Rust frames, Qt transform
order, Quickshell/Niri
pointer and hover, and
canonical validation
were NOT run.
It never reads or
exports real screen
coordinates, screenshots,
actual desktop logs,
host settings or
private QML paths.
It never starts Niri,
Quickshell, Rust or
wdotool and does not
generate a runtime
mask.

If the remote `dev`
advances concurrently,
the publisher may
rebase ONLY its own
single unpublished
receipt commit inside
the temporary private
clone, after reauditing
the exact current
source pins and
fast-forward ancestry.
It NEVER rebases,
merges, resets or
force-pushes the
maintainer's original
potentially divergent
checkout. A separate
`scripts/test-wull-motion-inert-publish-contract.py`
(created commit
`f7bf4d6eebbcd43344503f7cbaf717a4e64e9c66`)
purely tests the
allowlisted redacted
result, misuse rejection,
source pins, no backend
input commands and
exclusive-receipt
publication scope.
This contract too is
SOURCE STAGED and NOT
a local observed PASS
until the maintainer's
fresh clone executes it.

NEXT SINGLE LOCAL ACTION:
use a fresh mode-0700
temporary `dev` clone,
run the publisher
inert schema contract,
then explicitly opt in
to the publisher's
other two self-run
inert tests via
`python3 scripts/wull-motion-inert-publish.py
--acknowledge-inert-motion-receipt`.
Only a published exact
new source-pinned
`wull-motion-inert-*.json`
with both PASS
tokens qualifies
actual host-local
source arithmetic
execution. This
does NOT upgrade
four-edge one-output
static BBOX pointer
evidence to animated
hit-shape acceptance.
Separate runtime
Qt transform and
target contract
must precede any
private live shape
probe or production
mask edit.


## Observed inert motion/curve PASS; actual-QML offscreen 24-pose geometry gate staged

The EXACT published, independently source-pinned host-local
INERT evidence
`docs/archive/companion/receipts/2026-10-01/wull-motion-inert-20261001T182922Z-d5584c0e-3e27fdeb5c43.json`
(Git blob
`7a7b9f3024a8eba8523551b84a1e79a4f7caaf5a`,
`source_sha=3e27fdeb5c43b0a0cbad6c09f02c979bcaa4da07`)
records PASS for BOTH real execution of the standalone
four-cubic scanline and nominal-motion source
Python contracts. Its observed inert static
interior is 3,006 of 6,992 body-box pixels
in 43 bands on each edge. It separately
records the SOURCE-FORMULA stretch=1
counterexample's nominal top-tip coordinate
as -0.4 in top host space; source nominal
body dimensions at scale1.5 were 114x138
horizontal / 138x114 vertical. Both programs
were actual locally executed and their
allowlisted results pushed from a verified
throwaway dev clone. Their receipt explicitly
says no live Qt/Quickshell geometry, no actual
Rust animation, no Niri Region/pointer/hover,
no canonical acceptance and no production edit.
Do NOT turn a source arithmetic PASS into
an actual observed Qt transform/pass-through PASS.

The next evidence gate is the TRUE source-pinned
original QML transformation in a PRIVATE
`QT_QPA_PLATFORM=offscreen` local Quickshell
instance. The former offscreen centered four-edge
prototype tested only the idle body at
scale=1 and did not qualify time-varying
source geometry. New source-staged fixture
`scripts/wull-fixtures/motion-geometry/shell.qml`
(commit
`07c81fef4217f634a8a8910a1903a7d9007c878a`,
blob
`548daff91ca9a1d7961bedd098fd314159cb520d`)
imports the real unmodified
`AbyssCompanion`/
`WaterDropletBody` from the
reviewed module source in a
detached private offscreen
`ShellRoot`; it does NOT
copy or replace the live
companion module.
It constructs all 4 edges
times 3 parent scales
0.65,1.0,1.5,
then measures both the
true neutral geometry
and the SOURCE-ADMISSIBLE,
deliberately frozen
`stateStretch=1` target
geometry = 24 independent
QML `mapToItem`
samples. Only the private
fixture assigns the
original body instance's
`motionEnabled=false`,
`bob/sway/squash/lean/tip=0`
so these samples
isolate actual Qt
single-transform mapping,
NOT animation
interpolation/overshoot,
real daemon state or
real screen
pointer events.
The source-pinned
runner
`scripts/wull-manual-offscreen-motion-geometry.py`
(created
`b12c5db4b4fac4609997d4eb544ec2054f9fe073`,
redaction tightened
`9364ab83497111f4b02041f2657c1021ea56171b`)
enforces a new
current-user-owned
mode-0700 fresh
temporary `dev`
clone, trusted
fetch/push origin,
exact Git blob pins
for the fixture,
unmodified Wull
body and wrapper,
source style, Config,
defaults and
production perimeter,
and a distinct
private D-Bus
session. It explicitly
clears inherited
Wayland/Niri socket
and QML override
variables, launches
Quickshell offscreen
only, bounds
time/log size,
requires an
exact 24-unique-pose
QML marker and
checks true numeric
bounds and
parent scale
mapping for
each source
host edge/size.
The pass/fail
classification
will report if
all NEUTRAL
source-scale
static body boxes
still map inside
the measured
original host;
all nominal
stretch tip/body
outside static
bbox/host flags
are reported
categorically
PER EDGE AND
PER SCALE. A
source-model
counterexample
does NOT
pre-fill
observed Qt
flags: the
fixture's actual
Qt geometry
determines them.
If runtime
neutral geometry
or host parent
scaling differs,
the resulting
private offscreen
evidence stays
INCONCLUSIVE
rather than
approving the
static mask.

A separate
`scripts/test-wull-offscreen-motion-geometry-contract.py`
(commit
`a71f105cc0420baff4b7cb808a6d4f3cd549d6aa`)
tests the
no-input runner,
fixture and
original source
pins, synthetic
unique-pose/geometry
parser, negative
malformed or
fabricated body
bounds and
sanitized
published report
schema without
launching Qt.
The runner can
non-force publish
only ONE
uniquely named
`docs/wull-qt-motion-*.json`
containing
source SHA,
24-pose
QML geometry
classification,
optional short
numeric sanitized
local Quickshell/
Qt versions and
boolean/edge-scale
categories, NEVER
the actual
private measured
coordinates, log,
host sockets
or screenshots.
If concurrent
Git publication
requires a retry,
ONLY the
runner's own
single unpublished
redacted receipt
commit is rebased
inside the
disposable clone,
never the
maintainer's
original worktree.
The fixture,
runner and
test are
SOURCE STAGED,
not yet
executed locally.

IMPORTANT: host's QML
`scale` property
also scales the
PARENT in
stage coordinates,
so the old
unscaled dimensional
comparison at
scale=1.5
(114x138 body vs
112x98 unscaled
host) alone CANNOT
demonstrate actual
Qt clipping.
The new two-frame
actual-QML
offscreen gate
compares BOTH the
measured host
and body in
the SAME parent/
stage coordinate
systems. Only
actual measured
edge/scale
QML rows can
resolve those
specific geometry
relations.
The separate
nominal source
tip-at--0.4
prediction
likewise must
be confirmed
in actual
frozen Qt/QML
before treating
that position
as rendered geometry.
Even a 24/24
clean offscreen
fixture does
NOT establish
a moving
SpringAnimation
envelope,
hover or
Wayland Region
behavior.

NEXT LOCAL GATE:
on a clean
owned private
temporary dev
clone, run the
INERT standalone
offscreen parser
contract first;
then ONLY explicitly
launch the
offscreen fixture
via
`python3
scripts/wull-manual-offscreen-motion-geometry.py
--acknowledge-private-offscreen-qt-motion`.
Inspect the
unique exact
source-pinned
redacted
`docs/wull-qt-motion-*.json`
whether it
reports PASS
or INCONCLUSIVE,
and plan
a separately
guarded
real nested
Niri dynamic
hover/tap/shape
probe only after
actual Qt
transform mapping
is established.
No production
input mask, Rust
or stable ref
may change
during this
research gate.


### Guard refinement: require observed frozen stretch pose before geometry classification

The first offscreen fixture staging has an additional
critical non-spoofable phase predicate. Revision
`d114a768a26ec6956bfd1f83d14a2aebb6a82e54`
updated the private original-QML fixture
to record `pose_state_verified` per
sample. It asserts the ACTUAL
`WaterDropletBody` component is
in `motionEnabled=false`,
`bob/sway/squash/stateSquash/stateLean/
stateTip=0`, and
`stateStretch=0` for the neutral
phase or `stateStretch=1` for
the isolated stretch target. The
exact revised fixture blob is
`11df91496a8bb9b18d79498e86d1f734d78dc574`.
The runner revision
`82f6f078282dc7a73dd727f1cd003c91dea5391b`
pins this reviewed blob and
REJECTS ANY of the 24 actual
QML measurements if the
intended frozen transform
state was not observed.
The inert contract revision
`17632a74eb9b472e39684f44c0eb088314c8c0c3`
re-pins the fixture and checks
a missing frozen-state
observation fails closed.
Do not rely on the
earlier staged fixture
SHA after these
safety amendments.
No live QML result
has yet been
published at this
checkpoint.


## Observed actual-QML frozen 24-pose acceptance and next dynamic sampling boundary (2026-10-02)

The maintainer reran the repaired inert contract, then the explicit private offscreen Quickshell runner in a fresh clean owned dev clone. Unique published receipt:
\`docs/archive/companion/receipts/2026-10-01/wull-qt-motion-20261001T185752Z-53e5c5cc-72ac0580b12e.json\` (Git blob \`dc2f36b525ef7e412869f155153dc4e48720f898\`), exact pre-publication source \`72ac0580b12e08c88e74f69ac919e30a93f481f4\`; report-only publication commit \`dae62a2e74a2ba2df86c98d62fea9f73db8efc74\`. It states \`status=pass\`, 24 unique verified frozen QML poses, all 12 neutral source-static BBOXes inside their corresponding host, and real Qt parent scaling consistent at all three scales. Local Quickshell version was \`0.3.1\`; the Qt library version was not recorded. The fail-closed phase predicate requires \`motionEnabled=false\`, zero bob/sway/squash/lean/tip perturbations and explicit \`stateStretch=0\` (neutral) or \`1\` (target) per sample. This is actual Qt \`mapToItem\` evidence, not replay of the earlier Python transform formula.

All three tested parent scales 0.65, 1 and 1.5 reported the SAME categorical stretched result: path-tip point OUTSIDE the static body region and the host on TOP; transformed body-item axis-aligned BBOX OUTSIDE the initial static body BBOX on ALL FOUR edges; transformed body-item BBOX OUTSIDE the host on TOP and BOTTOM. The transformed item BBOX is an overapproximation of the painted Bézier silhouette; neither a BOTTOM visible-path clipping claim nor an exact body-shaped click region follows from these box flags. Comparing scaled host and body in the same Qt coordinate system resolves the former invalid *unscaled* scale=1.5 arithmetic comparison. Parent scale consistency does not certify fractional-output rendering, compositor placement or input Region refresh.

This frozen-pose PASS DISPROVES treating the existing static body-BBOX candidate as a guaranteed envelope even for authored stretch=1, but DOES NOT quantify a moving SpringAnimation envelope or certify clipping of rendered pixels. Production continues to use its full original host Region; Wull remains default-off and Rust/production QML unchanged. Old TOP/LEFT off-target private-pointer transients remain unclassified.

NEXT PRIVATE RESEARCH GATE, not yet developed or run: source-pinned, bounded offscreen actual-QML **dynamic frame sampling**, preserving the actual WaterDropletBody and AbyssCompanion modules without patching their runtime. The private fixture should instantiate 4 edge × 3 scale cases and record real mapped body-item AABB, authentic path tip (not only box corners), host-relative scaling and animation-state witnesses over controlled neutral-to-stretch and stretch-to-neutral transitions. Require positive per-case evidence that \`motionEnabled=true\` and actual \`stateStretch\` changes, and separately sample autonomous bob/sway. Record frame counts and whether sampled frames exceed the frozen-pose BBOX/host categories; reject absent phases, missing samples, unchanged stretch, nonfinite geometry, unreviewed parent scale, missing process cleanup, oversized logs, or changed source blobs. Keep private numeric frame coordinates, animation values and process logs LOCAL; publish only source-pinned redacted edge/scale/category flags and explicit **sampled frames, not provable global extrema** semantics. Tests must cover synthetic malformed/truncated/false-witness cases before launching Qt. Stop on INCONCLUSIVE rather than misreport absence of overshoot. Test normal production-mapped Rust traces and later guarded nested Niri real input hover/click as separate gates: the offscreen fixture's authored transitions are not observed daemon traffic. The hover/click contract should distinguish visible Bézier core, stroke/tip, decorative halo/ripple and forgiving accessibility margins BEFORE testing any private input Region or changing production.

NO NEW POINTER OR PRODUCTION MASK TEST is authorized merely by this 24/24 frozen result. Long-run shell resource use, multimonitor, fractional scaling, hotplug/suspend/reload, visual review and canonical maintainer validation remain independently open.


## Sampled dynamic actual-QML motion fixture: staged, NOT yet run (2026-10-02)

A separate new frozen-pose report has appeared: \`docs/archive/companion/receipts/2026-10-01/wull-qt-motion-20261001T190302Z-a0fcad4b-5f5331d7fb6d.json\` at exact source \`5f5331d7fb6d1b689f245e630e0eebfe56fb8b4d\`, status PASS, 24/24, Quickshell 0.3.1 and the SAME per-edge/per-scale categorical findings as the earlier published frozen baseline (\`72ac0580b12e08c88e74f69ac919e30a93f481f4\`). A source comparison from the first frozen source to the second source shows documentation, first receipt and the new **offscreen-only** dynamic fixture added; the original Wull renderer/host/bridge were unchanged. This is one additional matching frozen-pose run, not dynamic motion repeatability evidence.

The next separately qualified gate has been SOURCE STAGED only; no local dynamic report exists yet:
- \`scripts/wull-fixtures/motion-envelope/shell.qml\` exact blob \`0fede26c2dc370234ae1b1702afdca3ea05e33e0\`. It instantiates the existing unmodified \`AbyssCompanion\` and \`WaterDropletBody\` QML on four edges at parent scales 0.65/1.0/1.5, first confirms neutral and frozen stretch=1 reference coordinates while motion is disabled, then enables motion only on these PRIVATE fixture instances. Over controlled stretch and release phases, a 40 ms Qt timer samples actual transformed body-item four-corner bounding boxes, the transformed Bézier tip and host scale mapping. Each phase requires observed motion enabled, intermediate and near-target stretch samples, and independent nonzero bob/sway witnesses for EACH of 12 hosts. It records categories for the sampled body box/tip outside host and sampled body-box extension past that host's frozen target. The latter may arise from any of the sampled animated transforms: do not label it proven spring-only overshoot.
- \`scripts/wull-manual-offscreen-dynamic-geometry.py\` exact blob \`71262816d9d64c97061c90e03bed9acee76bdc18\` reuses the reviewed private-clone/source/remote safety guard of the frozen runner and additionally pins this dynamic fixture plus the first exact frozen receipt. The current local Quickshell MUST report version 0.3.1 to match that receipt; original Qt library version remains unrecorded and must not be inferred. A separate private D-Bus session launches \`QT_QPA_PLATFORM=offscreen\` Quickshell with inherited Wayland/Niri/display variables stripped. The child process has a 512 KiB file-size limit for its PRIVATE log; wait is bounded, surviving owned process-group children are terminated, and raw measurements stay local. A fresh unique \`docs/wull-qt-dynamic-*.json\` may be pushed without force only after a fully parsed allowlisted 12-host sample matrix, with sanitized categorical results and source SHA. PASS certifies only the controlled, observed sampled frames and required per-host motion witnesses; missing/ambiguous witnesses yield INCONCLUSIVE or stop. It does NOT prove the global spring extrema, visually painted Bézier pixels, Rust-sourced state traces, actual Wayland Region/hover/click, multi-output/fractional scaling, or long-run quality.
- \`scripts/test-wull-offscreen-dynamic-geometry-contract.py\` exact blob \`08ca436a007d5d78831655644bee455d77f4cd28\` is an independent inert/synthetic contract. It pins the dynamic runner/fixture and original frozen dependencies, checks the strict reporting schema and redaction, tests the expected 12-host cross-product and intentionally malformed, absent and false-witness cases, and statically guards private offscreen execution/no pointer tooling/non-force receipt-only publication. It has NOT been observed running on the maintainer's computer. No first-run FAIL/PASS claim should be inferred from source staging.

**NEXT SINGLE LOCAL GATE**: use ONE new clean current-user-owned private \`dev\` clone, distinct from prior runs, rooted in a mode-0700 \`XDG_STATE_HOME/hadalis/wull-qt-motion.*\` scratch. Run ONLY \`python3 scripts/test-wull-offscreen-dynamic-geometry-contract.py\` first. Require its exact \`WULL_OFFSCREEN_DYNAMIC_INERT_CONTRACT_PASS\` output. Only then invoke the acknowledged existing \`python3 scripts/wull-manual-offscreen-dynamic-geometry.py --acknowledge-private-offscreen-dynamic-motion\` on that same clone; it fetches and guards latest source itself. Inspect the exact new sanitized report on GitHub before another experiment. A local contract failure is NOT permission to edit the pinned fixture or blindly rerun. Production full-host Region, default-off Wull, original Rust backend and \`stable\` are unchanged. No real pointer input or original user shell may be started at this stage.


## Motion-aware input target acceptance hypothesis (DESIGN ONLY; 2026-10-02)

Following two actual frozen 24-pose reports, a static 76×92 body box is NOT a sufficient dynamic input-boundary assumption. This section specifies a falsifiable PRIVATE acceptance target; it does NOT select a runtime mask or approve production QML changes.

**Observed geometric constraints at each parent scale (0.65, 1, 1.5)**:
- In authored frozen stretch=1, the actual Qt **transformed item AABB** extends beyond the untransformed static body BBOX on ALL FOUR output edges; it also extends beyond the original host AABB on TOP and BOTTOM. The sampled path-tip point extends past the host on TOP only. Neither AABB nor a single path tip proves painted pixel extent, Qt scene-graph clipping, pointer dispatch beyond the host, or the whole spring envelope.
- The four private Niri single-output scale=1 BBOX A/B pointer successes establish only a **separate** body-box candidate for their tested positions. Old TOP and LEFT off-target mouse-coordinate incidents remain reliability concerns. They do not permit publishing a curved or animated production mask.

**Provisional interaction contract for a later separate nested-Niri fixture**:
1. Distinguish the genuine body silhouette and stroke/tip (intended accessible hover/click target), interior taps, decorative soft halo and detached edge ripple (not automatically interactive). Any chosen accessibility margin must be explicit and tested, not inferred from the earlier ~43-band eroded silhouette.
2. Measure the **same coordinate space** for each candidate Region and host/body under every tested edge/scale. If a painted core or accessible tip is outside the host even at a permitted frozen pose, simply shrinking its input Region cannot preserve click there. Test a source-shadow host expansion or conservative fallback ONLY inside an independent private fixture; first quantify its impact on adjacent bar/popup input.
3. For each edge and the three scale settings: validate idle center, both curved shoulders, extreme painted/tip-adjacent targets, animated/interpolated locations, intentional empty host margins and neighbouring underlay, while checking **real bridge/Rust** click/hover counts in a separately authorized physical input experiment. Unrelated decorative halo pixels are separately observed rather than silently accepted or rejected as target area. Preserve popup and keyboard interaction and ensure no activation through empty margins.
4. Explicitly separate controlled offscreen **sampled** frame observations (neither guaranteed global spring extrema nor real backend traces), replayed source-permitted Rust states, physical hover enter/leave and clickable movement in a private nested Niri, then repeatability and user-facing visual acceptance. One observed PASS does not erase rare old TOP/LEFT off-target trials or qualify other scales/multioutput.
5. Require strict source SHA and Quickshell/Qt build identity, bounded complete owned cleanup, negative/failed-witness cases and allowlisted no-coordinate public receipts at every private stage. Even a perfect offscreen dynamic sample must NOT trigger production mask cutover. Keep the current full host input mask/default-off backend until the remaining live/popup/resource/canonical acceptance gates are independently satisfied.

For any candidate tight shape, record separately (a) reachability of intended moving body/tip targets, (b) absence of empty-margin interception, (c) adjacent popup/underlay non-interference, (d) output+scale+state coverage, (e) reproducibility against old off-target incidents, and (f) actual paint/host boundaries. Failure or absent evidence in ANY dimension preserves the current production full-host Region. The experimental narrow BBOX and ~43-band curve studies are reference prototypes, not selected release designs.


### Private sampled animation: require mapped motion, not state-only movement

Post-staging source review exposed a possible false-positive: the test's previous positive values for real `stateStretch`, `bob` and `sway` alone do NOT establish that Qt's actual transformed item occupies different host-relative coordinates across rendered sampled frames, especially in the presence of parent centering and anchors. Separately measured `mapToItem` body geometry must change.

The revised PRIVATE fixture (`scripts/wull-fixtures/motion-envelope/shell.qml`, Git blob `221c07d0a451ba918e3e2074aeafe389e588f594`) keeps a private four-corner mapped AABB snapshot per host and resets it at EACH controlled stretch and release boundary. For each of the 12 host edge/scale combinations in EACH phase, adjacent sampled Qt AABBs must differ by at least 0.12 units on some boundary in order to establish `mapped_frame_change_witness`. It separately requires previous numeric stretch transition/target and bob/sway witnesses; the frame-difference witness cannot attribute movement to any particular numeric component without a separately isolated probe.

The source-pinned runner blob is `12ade72c22912c44aa3e66a2b5aef62c9e8b58f3`, and the reviewed inert negative/receipt contract blob is `1598ab0730667254e0a0bcf0f64393ff2d50fbcd`. The latter checks the new pin and falsifies the mapped witness in a synthetic release case. Both snapshots and any numerical frame coordinates stay private; the allowlisted receipt may contain ONLY categorical witness/result fields, source metadata, bounded sample-count summary and explicitly unqualified scopes. The strict original production-code blob pins and private process-group bounds remain.

These revisions have SOURCE-AGREEMENT inspection only; there is NO published `docs/wull-qt-dynamic-*.json` actual-QML result. An absent mapped frame change or missing/incorrect phase witness makes that host/phase INCONCLUSIVE; it is neither a negative claim about the product's real animations nor permission to update the production Region. A passing observed mapped change still is NOT global spring-extrema proof, nor separate proof of bob/sway-induced mapped displacement, painted pixel coverage, pointer dispatch or Rust state replay.

## Retained actual dynamic Qt PASS published; paint/host boundary must precede any dynamic mask candidate

Source-verified checkpoint 2026-10-02: the original offscreen dynamic Qt fixture completed all eight stages at source `4caccd2058f1b3089ec398a131241f800eaae890`. The old parser's JavaScript JSON `1.0` → `1` / Python `str(1)` frozen-reference bug was corrected only in the private runner (blob `9cab00fca46212c819ac7308cfc0d6923d1139d3`), with new regression tests. The owner actually ran both inert contracts and read-only, source-pinned reclassification of the retained old log, producing `MODEL_STATUS=pass`. A separate exact-origin retrospective receipt was then published in `docs/archive/companion/receipts/2026-10-01/wull-qt-dynamic-retained-4caccd2058f1-scale-parser.json`, commit `556e7643bca1f672feef6ed5d879ffff73f861c4`, blob `54a153d717b10056d156e4724d80cb759cf5941d`. The owner's next clean clone already observed that commit and correctly stopped with `GATE=RECEIPT_ALREADY_EXISTS`; no second run, duplicate receipt or overwrite is required.

ACTUAL receipt scope: four edges × scales 0.65, 1.0, 1.5 × controlled stretch/release sampled phases; 80 samples PER case PER phase, no missing categorical witnesses. At each scale, the OBSERVED transformed *body-item AABB* reaches beyond the host for TOP and BOTTOM placement in both phases, and beyond that host's frozen-pose bounds for ALL FOUR placements in both phases. The sampled mapped path-tip point is outside the host for TOP in stretch, but no such release-phase tip category is recorded. These are **OR-ed sampled category flags**, NOT synchronized geometry snapshots, pixel paint bounds, compositor clipping/visibility observations, quantitative overshoot magnitudes or guaranteed extrema. `global_spring_extrema_proven=false`, `native_backend_traces=not_run`, `wayland_pointer_hover=not_run`, `canonical_validation=not_run`; original Quickshell was 0.3.1 and original Qt patch version was not recorded. The retrospective publication explicitly preserves the old source SHA and says no Qt rerun occurred.

SOURCE ALIGNMENT: the real `WaterDropletBody.qml` remains a 76×92 transformed Qt Quick `Item` with a 4-cubic `ShapePath`, 1.2-wide stroke, separate specular face highlights and pulse halo; the parent `AbyssCompanion.qml` still contains a separate ripple rectangle and edge-dependent whole-body rotation. The original offscreen dynamic fixture obtains the mapped AABB from the four BODY ITEM corners and checks the nominal tip `body.mapToItem(host, body.width * 0.5, 2)`. Therefore even the verified beyond-host AABB at TOP/BOTTOM cannot by itself establish whether PAINTED core pixels, stroke, face or only blank item corners cross the host or are visually clipped. The single tip point is authored path geometry, not a photographed pixel, and does not demonstrate click delivery. The original production `AbyssPerimeter.qml` still uses the guarded full `companion` host `Region`, not an animated body mask. The previous static four-edge scale=1 BBOX nested click tests are NOT transferable to animated frames.

**NEXT SINGLE RESEARCH MILESTONE, not yet staged or executed:** a new independently source-pinned PRIVATE offscreen painted-core-versus-host boundary probe. Preserve the actual production renderer, companion host, configuration and source blobs; never patch the shipped runtime to meet the test. An expanded isolated transparent Qt stage MUST capture beyond each test host's nominal rectangle so any observed off-host paint is not cropped by the capture itself. For all four edges, three scales and BOTH controlled phases, correlate bounded frame sampling with host-mapped body geometry while testing distinct evidence classes: (a) sampled body-item AABB; (b) nominal Qt mapped Bézier path/tip and stroke-near path targets; (c) genuinely observed nonzero painted core/stroke pixels inside versus outside the original host; (d) separately sampled halo and ripple, never conflated with intended body hit targets; (e) actual clipping/reachability at the full layer in a LATER nested-compositor stage. If a capture cannot reliably distinguish the core from decorations without modifying the source renderer, classify it INCONCLUSIVE or give it a separate explicitly shadow-only isolation scope; don't label altered source as exact production rendering. Do not publish raw screenshots, pixels, coordinates, desktop contents, unbounded logs or source-private paths. Include negative tests for all-transparent snapshots, missing phase/frame, impossible/unaligned scale transforms, capture canvas truncation, dependency drift and incomplete cleanup before any local Qt execution.

Only after private painted coverage is established should a separate owned nested-Niri pointer experiment test an expanded-host OR a conservative fallback candidate (if genuinely necessary), underlay-empty-margin delivery and clickable moving core/tip, plus neighbouring bar/popup non-interference. A separate source-authorized Rust/bridge replay must qualify real backend-driven movement. Even positive outcomes are sampled/one-output limits, not global motion extrema, fractional-scale/multioutput/long-run qualification, nor permission to change the shipped input mask. Leave original production full-host Region, Wull default-off and `stable` unchanged.

## Private painted-alpha classification core source-staged; no Qt capture yet

Following the published retrospective dynamic sampled-QML receipt, a NEW entirely inert pixel-classification foundation is staged on `dev`:
- `scripts/wull-private-painted-alpha-model.py`, Git blob `fa9e7c2af87ee830336988fa7060e2720e816ed0`. This does not capture images, open private paths, run Qt or write a public result. It parses only bounded RGBA8, noninterlaced PNG: strict signature, CRC and chunk order, supported filter types 0–4, 512×512 dimension cap, 1 MiB PNG/IDAT cap, bounded zlib output, alpha threshold and a two-pixel transparent canvas safety margin. It rejects absent interior painted pixels, host rectangles reaching canvas margins and capture-edge paint (possible truncation). Every frame must carry a complete allowlisted edge/scale/phase/variant contract, finite in-canvas host rectangle and explicit phase/mapped-change witnesses.
- `scripts/test-wull-private-painted-alpha-model.py`, Git blob `f673e062669d5b03f7af5bd74c20c5126b37e9be`, generates only fake RGBA PNGs locally and tests all five PNG row filters, visible interior vs exterior alpha, forged/duplicate/missing metadata, all-transparent, crop-boundary, CRC/truncation/oversized/non-RGBA/invalid-filter and strict 48-case aggregation. Both are SOURCE STAGED, **not yet owner-local executed**.
- The 48-slot intended future capture matrix is 4 edges × 3 scales × 2 controlled phases × two separately named variants: `production_composite` (unchanged original `AbyssCompanion`, including halo/ripple) and `body_only_shadow` (a separate explicitly SHADOW-only assembly built around the unmodified original `WaterDropletBody`, removing its external companion ripple, with original transformed-body settings source guarded). It must **not** assume the two captures represent identical live frames or subtract one from the other. A composite exterior alpha pixel might belong to halo/ripple, while the shadow is NOT exact production. There is no production-body click-target or painted-extrema claim.
- Inert categorical output aggregates only edge/scale/phase exterior-alpha booleans, not PNG bytes, private capture paths, exact host coordinates, raw pixels or desktop information. If the future Qt capture saves another PNG encoding, exceeds the bounded budget, clips the canvas, lacks verified mapped motion or cannot isolate body and decor, fail closed and classify INCONCLUSIVE; do not weaken source identity or promote a shadow probe to full-production proof.

**NEXT**: run the new fake-only contract in ONE clean, source-pinned ephemeral `dev` clone. Upon owner-confirmed inert PASS, source-stage a one-case PRIVATE offscreen Qt `grabToImage` feasibility canary that uses the actual unchanged companion inside a transparent expanded capture surface. Validate capture initialization, actual alpha and boundary padding, Qt save format and complete private process-group cleanup **before** creating or running the full 48-slot dynamic capture. Only a later separately tested full-QML dynamic capture may produce observed categorical painted coverage. Keep the current full-host production mask, disabled-by-default Wull, original production renderer and `stable` untouched.

## Single-case source-pinned offscreen Qt grab canary staged; runtime not yet executed

The maintainer ran the preceding alpha model's exact source-pinned fake-only contract on a fresh `dev` checkout (`DEV_HEAD=19408521c6927de57ba74163a3001fc67e6f2dc1`): `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`, `QT_EXECUTED=NO`, `PRODUCTION_CHANGED=NO`, `GATE=PAINTED_ALPHA_INERT_VERIFIED`. Since that checkpoint, unrelated MegaQML commits advanced `dev` without modifying the alpha model or Wull production QML.

New source-only staging for ONE FEASIBILITY capture before any 48-case production/shadow matrix:
- `scripts/wull-fixtures/paint-alpha-canary/shell.qml` exact Git blob `4ed1c92b81870197927b449cfe60cd2c57859b30`: original unmodified `AbyssCompanion` with original unmodified `WaterDropletBody` at TOP, scale 1.0, privately frozen stateStretch=1. One transparent `FloatingWindow` is CREATED HIDDEN and shown only after transparent window initialization under a PRIVATE `QT_QPA_PLATFORM=offscreen` process; it contains a 320×300 item larger than the test's 112×98 host rectangle. The only capture method is `captureStage.grabToImage` on that self-owned stage, never the monitor or desktop. Only fixed stage/failure tokens are logged. PNG capture path is injected by the private runner; async failure/timeout terminate without exporting the path or image.
- `scripts/wull-manual-private-paint-canary.py` exact blob `5ce5155303913b9eda49590ba017c074b8e176fc`: explicit one-shot owner-local opt-in; mode0700 ephemeral `dev` clone with clean branch, trusted origin and current remote HEAD verification; exact reviewed Wull production/QML/style/config/frozen runner/alpha model/fixture Git blob pins. Isolated private XDG, D-Bus session and offscreen Qt platform with Wayland/Niri/display/user-session-bus variables removed. Quickshell must be v0.3.1. Private subprocess runs in its own process group, with core dumps disabled, 8MiB inherited file cap, 256KiB log cap, one 13-second bounded capture, strict group cleanup. Original PNG remains only in the private temporary scratch; decoder requires canonical 320×300 RGBA8, interior painted alpha and transparent canvas margins. Only categorical `STATIC_TOP_SCALE1_PNG` and `OUTSIDE_HOST_COMPOSITE_ALPHA` can be printed. This is NOT a moving-frame witness, body-specific painted extent, animated tip reach, Qt screenshot of real compositor clipping, runtime backend trace or mask acceptance. No report is pushed on either PASS or failure.
- `scripts/test-wull-private-paint-canary-contract.py` exact Git blob `2c4a98c61c42e21634d568e68d10d8ac452f21f1`: fake-only test pins both new files and the pre-existing alpha model, statically forbids screen-capture/pointer-process invocations, verifies private env display/session scrubbing, safe fixed stage classifications, and decodes synthetic 320×300 PNGs for inside-host/exterior/empty/canvas-edge and malformed-image controls. It does not run Qt or read a private PNG. All THREE new files are now source-staged, not yet owner-local contract-verified or actually Qt-executed.

NEXT ONE OWNER ACTION: issue one ephemeral `dev` clone command with exact blob guards. Re-run the existing alpha fake contract and require `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`; run the NEW fake-only one-case canary contract and require `WULL_PRIVATE_PAINT_CANARY_INERT_PASS`. Only if both PASS may the explicit, strictly offscreen, source-pinned one-case canary run in that same already-isolated clone with `--acknowledge-private-one-case-capture`. Print only bounded categorical outputs. Any Qt capture failure is a CANARY INCONCLUSIVE diagnostic, not authority to run 48 cases or modify production. Preserve `stable`, existing full-host input Region and Wull default-off state. Future work after an actual canary PASS: design separately synchronized dynamic frames and body-only-shadow methodology while clearly separating exact unchanged full-companion composite from any intentionally non-production shadow.

## Actual top-scale1 composite PNG canary PASS; unmodified-body shadow isolation staged

OWNER LOCAL ACTUAL RESULT from private clean `dev` source `63eb572bdf324f1fd437df6f87617a2b9a81cbaa` (original Qt canary fixture blob `4ed1c92b81870197927b449cfe60cd2c57859b30`, guarded runner blob `5ce5155303913b9eda49590ba017c074b8e176fc`): `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`, `WULL_PRIVATE_PAINT_CANARY_INERT_PASS`, `ACTUAL_UNMODIFIED_COMPANION=YES`, `STATIC_TOP_SCALE1_PNG=VALID`, `OUTSIDE_HOST_COMPOSITE_ALPHA=YES`, `BODY_SPECIFIC_PAINT_OUTSIDE_HOST=UNPROVEN`, `DYNAMIC_WITNESS=NOT_RUN`, `PRODUCTION_MASK_CHANGED=NO`, `GATE=PRIVATE_OFFSCREEN_ONE_CASE_CAPTURE_VERIFIED`. It proves actual offscreen Qt captured at least one thresholded pixel of the unchanged full `AbyssCompanion` outside its nominal host in a bounded 320×300 self-owned transparent stage. It does NOT identify whether that pixel was painted by the original clickable body, attached cradle, decorative ripple or halo; no original screenshots, coordinates or private log may be published.

NEW independently source-pinned SINGLE-CASE SHADOW control (SOURCE-STAGED ONLY, owner-local contract NOT yet run):
- `scripts/wull-fixtures/paint-alpha-shadow/shell.qml` Git blob `feea498f8b75c24cdd93fe116bac0dd6b36b1d01` instantiates the actual UNMODIFIED `WaterDropletBody` with the source-matched TOP rotation 0, `Item.Center` transform origin, 76×92 body anchored in a 112×98 private shadow host at stage position (100,100), scale=1, `stateStretch=1`, bob/sway 0, pulse/ripple 0, and motion disabled before screenshot. This DELIBERATELY omits `AbyssCompanion` and its external cradle. The original WaterDropletBody still includes its own shape/stroke, face, highlights and internal decorations. An exterior shadow pixel therefore cannot be uncritically relabeled an isolated Bézier core pixel. It is an altered PRIVATE assembly, NOT exact unchanged production and not time-synchronized with the earlier production-composite snapshot.
- `scripts/wull-manual-private-paint-shadow.py` Git blob `08670b15307115adf8432614bdb13b36071effe0` reuses the reviewed original one-case canary isolation, private 320×300 offscreen `grabToImage` capture budget, bounded file/log/time and source pin guards, and additionally pins the original canary runner+fixture. Runs in a distinct ephemeral mode0700 clone and self-owned process group. Only outputs `STATIC_TOP_SCALE1_SHADOW_PNG`, `SHADOW_OUTSIDE_HOST_ALPHA` and strict scope limitations. No raw PNG, coordinates, Qt log, host window or Git publication.
- `scripts/test-wull-private-paint-shadow-contract.py` Git blob `c52562657920f7c0a2bfd88f5dbe8974aa590261`: separate fake-only inert contract pins the exact shadow fixture/runner/alpha model; prohibits full companion construction in the shadow and desktop capture/pointer tooling, verifies safe offscreen-only environment and process-group cleanup, categorical log acceptance and synthetic 320×300 PNG interior/exterior/blank/edge/invalid handling. NOT YET OWNER-LOCAL RUN. Production QML, full-host input Region, Rust backend and Wull default-off unchanged.

NEXT OWNER GATE: ONE source/blob-pinned clean ephemeral `dev` clone, run BOTH existing alpha model and NEW shadow inert contract first. Only on two PASS should the explicit `--acknowledge-private-one-case-shadow` execute once on the same private clone. Do NOT rerun the previous composite Qt canary or treat separate snapshots as a pixel-by-pixel difference. If the shadow reports exterior alpha YES, the standalone unchanged body under this source-matched shadow setup paints outside the nominal host; further capture must still isolate its Bézier core/stroke from internal child shapes and test actual compositor clipping/click delivery. If shadow reports NO, do NOT attribute the earlier composite exterior alpha to the omitted cradle without a synchronized source-identical paired experiment. In either case, actual dynamic paint and full 48-case coverage remain untested; no production mask changes.

## Owner body-shadow alpha PASS; original Bézier ShapePath-only shadow canary staged

OWNER ACTUAL RESULT: in a fresh private clean `dev` clone at `SOURCE_SHA=81daf8f7e64d1a7521d18f831d4db30044a10c74`, both old synthetic PNG and NEW shadow inert contracts passed (`WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`, `WULL_PRIVATE_PAINT_SHADOW_INERT_PASS`). The owned offscreen Qt body-shadow canary captured the original, unchanged `WaterDropletBody` directly instantiated without the external `AbyssCompanion` cradle at TOP/scale1, static stretch=1: `UNMODIFIED_WATER_DROPLET_BODY=YES`, `PRODUCTION_COMPOSITE=NO`, `EXTERNAL_CRADLE_INCLUDED=NO`, `STATIC_TOP_SCALE1_SHADOW_PNG=VALID`, `SHADOW_OUTSIDE_HOST_ALPHA=YES`, `PRODUCTION_BODY_PAINT_OUTSIDE_HOST=UNPROVEN`, `BODY_SHAPE_VS_INTERNAL_CHILDREN=UNRESOLVED`, `DYNAMIC_WITNESS=NOT_RUN`, `PRODUCTION_MASK_CHANGED=NO`, `GATE=PRIVATE_ONE_CASE_SHADOW_CLASSIFIED`. This directly rules out the external cradle as a *necessary* cause of outside-host alpha in this shadow scenario; it does not identify which painted internal element caused it or prove the live unchanged composite has the same pixel there. Neither previous PNG was kept or exported.

NEW PRIVATE ORIGINAL SHAPEPATH-ONLY CANARY (SOURCE STAGED, NOT YET OWNER-LOCAL TESTED OR QT-EXECUTED):
- `scripts/wull-fixtures/paint-alpha-core/shell.qml`, blob `eb35bd8366a0d2b274302a02eff089b5507bf3db`, follows the exact original body-shadow stage and preserves production `WaterDropletBody.qml` entirely unchanged, its original transforms, static TOP/scale1 stretch=1 pose, larger transparent 320×300 window and nominal 112×98 host. PRIVATE fixture introspects the **exact source-reviewed** five direct visual children (halo rectangle, full-size Bézier `Shape`, highlight rectangle, eyes `Row`, mouth `Shape`) and requires exactly ONE full-size 76×92 child at (0,0). It hides the other four VISUAL sibling items ONLY on this private instance, asserts only that child remains visible, schedules `grabToImage` after a Qt event-loop boundary and prints categorical stages only. The retained child is the original four-cubic Bézier `ShapePath` with its original gradient and 1.2 px stroke. Any changed hierarchy, missing/ambiguous full-size child, visibility isolation failure, invalid PNG, missing clean captured canvas or failed cleanup FAILS CLOSED. This is an intentionally altered child-visibility shadow assembly; neither its pixels nor the prior body-shadow pixels may be treated as a synchronized pixel-difference or exact original composite.
- `scripts/wull-manual-private-paint-core.py`, blob `1fbc0e8e0c8c361a706ff31af1b0a138ec9b841c`, reuses isolated private Qt offscreen mode0700 clean current-`dev` clone constraints, exact Wull production/style/defaults/frozen source pins, private bus and XDG, disabled host display variables, QS v0.3.1 verification, 8MiB inherited child file cap, 256KiB retained private log cap, 13s process timeout, group-only cleanup and bounded strict RGBA PNG alpha checker. It also pins the earlier full-composite and body-shadow fixtures and runners and the isolated original ShapePath fixture. A runtime PASS prints only `CORE_OUTSIDE_HOST_ALPHA=YES|NO` plus provenance, **not** PNG bytes, exact coordinates, private paths, Qt logging or a pushed report.
- `scripts/test-wull-private-paint-core-contract.py`, blob `2f0a7dd88076900d8dec2ce08766a6a6b1dd83ee`, is a separate fake-only regression derived from the previous real-PASS shadow contract. It pins exact new fixture+runner+PNG decoder, tests fixed identities and requirements to have precisely five original visual children and one full-size visible child, private-only window capture, offscreen XDG/display scrub, bounded child cleanup, allowlisted stage parser, fake 320×300 PNG interior/exterior/blank/edge/malformed cases. Its pass does NOT prove exact runtime child discovery until the owner runs the approved Qt canary.

NEXT GATE: single new 0700 clean ephemeral current-`dev` clone, pin these three NEW blobs and original PNG analyzer, previously accepted shadow runner/fixture, production body/perimeter. Run existing `test-wull-private-painted-alpha-model.py` then NEW `test-wull-private-paint-core-contract.py` FAKE-ONLY. If both actually PASS, explicit opt-in allows ONLY `scripts/wull-manual-private-paint-core.py --acknowledge-private-one-case-core` ONCE in the same owned offscreen clone. Expected output categorizes whether original static Bézier `ShapePath` with original stroke has detected alpha beyond the private host. Regardless of YES/NO, full original production composite, actual compositor clip/visible pixels, click/hover, dynamic/replayed Rust state, all 4 edges × scales, spring global extrema and canonical validation remain separate gates. No production mask edits, new default-on behavior or `stable` changes.

## Owner original ShapePath exterior alpha PASS; same-session paired composite/core overlap gate staged

At owner-local `SOURCE_SHA=be781816c44177ffce279c32edf052ae38105243`, the source-pinned prior model, shadow and NEW original ShapePath inert tests all returned exact PASS. The one-case private offscreen Qt core fixture then reported `UNMODIFIED_WATER_DROPLET_BODY=YES`, `PRODUCTION_COMPOSITE=NO`, `EXTERNAL_CRADLE_INCLUDED=NO`, `OTHER_BODY_VISUAL_CHILDREN=HIDDEN`, `ORIGINAL_SHAPEPATH_CHILD=SOURCE_PINNED`, `SHAPE_STROKE_INCLUDED=YES`, `STATIC_TOP_SCALE1_CORE_PNG=VALID`, `CORE_OUTSIDE_HOST_ALPHA=YES`, `PRODUCTION_CORE_PAINT_OUTSIDE_HOST=UNPROVEN`, `DYNAMIC_WITNESS=NOT_RUN`, `PRODUCTION_MASK_CHANGED=NO`, `GATE=PRIVATE_ONE_CASE_CORE_CLASSIFIED`. This observes actual offscreen-painted exterior alpha from the original four-cubic Bézier `ShapePath` including the original stroke ONLY in the private sibling-hidden scene. It DOES NOT imply external full-composite paint at that exact exterior pixel, real production visual clipping, clickable hit regions or animation envelope.

NEW SEPARATE PRIVATE A/B FEASIBILITY (SOURCE STAGED ONLY, NOT YET OWNER EXECUTED):
- `scripts/wull-fixtures/paint-alpha-paired/shell.qml` exact blob `83326999c8363420fabb5bbb5022d100ab1a64c6`, commit `11adf02e23226d3fffe0db8555cf561d4b5ad209`. Uses a SINGLE unchanged original `AbyssCompanion` with its original `WaterDropletBody` at TOP/scale1 and `stateStretch=1` in ONE 320×300 transparent, private offscreen Qt window. It freezes the tested PRIVATE state before capturing original full composite, snapshots host-mapped actual body corners and tip plus state and parent geometry, and checks the full original five visual children visible. ONLY AFTER the full PNG has been saved does it hide the four non-core visual siblings ON THIS SAME Qt INSTANCE (not in the source QML), verify the mapped coordinates remain within 0.05 Qt units of the saved original snapshot, and grab the source-pinned original `ShapePath`/stroke-only PNG. Stages/failures are fixed allowlisted labels. Any missing/ambiguous original core, motion/geometry drift, capture error or timeout aborts. The second screenshot has INTENTIONALLY ALTERED sibling visibility, so even within one session these are ordered, NON-simultaneous frames, not an exact reproduction of dynamic compositing.
- `scripts/wull-manual-private-paint-paired.py` exact blob `c30279f99fbb05ff6e67d30c690b091851dfc4e5`, commit `b77987f78dcfdf1d986d793f9a8bca02c47fb54b`. Reuses the previously vetted source-pinned owner-owned clean current-`dev` private clone guard, original Wull production/config/style/fixture/alpha model pins, isolated per-run XDG and D-Bus, stripped host desktop connection and offscreen Qt 0.3.1, bounded own process-group cleanup, 8MiB inherited file limit, 256KiB private log and 14s Qt timeout. Two distinct private PNGs MUST each be canonical 320×300 RGBA8 with interior paint and transparent outer canvas bounds. Only privately count alpha pixels at threshold 24 OUTSIDE the 112×98 nominal host, separately for full composite and isolated original core, and whether ANY exterior pixel is above threshold IN BOTH captures at the EXACT SAME pixel location. No screenshots, coordinates, pixel count, raw logs, local paths, host display data or Git publication ever escape. Result flags distinguish full/core exterior alpha and exact-pixel exterior-overlap; a negative overlap is a tested non-observation at this one frozen pose, not a proof of impossibility.
- `scripts/test-wull-private-paint-paired-contract.py` exact blob `98562ba6098eaf5d1e26b9697910fbc1f44ddc48`, commit `c18886a5b526921a45f9fc5da7ba710bf38c0463`. Fake-only source/fixture/runner/hash, stage/privacy/process/timeout guard; generates independent 320×300 synthetic full/core RGBA8 pairs with shared exterior pixel, disjoint exterior pixels, one-sided exterior, all-transparent and canvas-cropped/malformed inputs. Requires no Qt. Source staged but NOT yet owner-local run.

NEXT SINGLE OWNER GATE: create a fresh mode0700 private clean `dev` checkout, verify exact paired fixture/runner/test and original alpha model/previous core/production blobs. Re-run fake-only alpha model contract and the NEW paired fake-only contract first. Only if BOTH actually PASS, opt in to ONE owned private offscreen run of `scripts/wull-manual-private-paint-paired.py --acknowledge-private-paired-static-core`. Return ONLY fixed `COMPOSITE_OUTSIDE_HOST_ALPHA`, `CORE_OUTSIDE_HOST_ALPHA`, `SAME_PIXEL_EXTERIOR_OVERLAP` and gate markers. This is not 48-case motion sampling, synchronous pixel causation, actual Wayland compositor visibility/clipping, pointer hover/click, production mask acceptance, backend replay or global spring extrema. Keep production mask full, Wull default-off, original QML and `stable` unchanged.

## Owner paired TOP core/composite overlap PASS, cradle-confound correction, and twelve-case static matrix staging

At source `27430b931de91ef63eec1caddc6f6c9822158f7a`, the owner verified both pinned `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS` and `WULL_PRIVATE_PAIRED_CORE_INERT_PASS`. The bounded original-QML same-session TOP scale1 fixed-pose private Qt pair reported `ACTUAL_UNMODIFIED_COMPANION=YES`, `SAME_QT_SESSION=YES`, `FIXED_MAPPED_POSE=YES`, `PRIVATE_CORE_CHILDREN_HIDDEN=YES`, `COMPOSITE_OUTSIDE_HOST_ALPHA=YES`, `CORE_OUTSIDE_HOST_ALPHA=YES`, `SAME_PIXEL_EXTERIOR_OVERLAP=YES`, `EXACT_PRODUCTION_PAINT_AND_CLICK=NOT_PROVEN`, `DYNAMIC_WITNESS=NOT_RUN`, `PRODUCTION_MASK_CHANGED=NO`, `GATE=PRIVATE_PAIRED_STATIC_CORE_CLASSIFIED`. This verifies SAME-exterior-pixel categorical overlap between sequential snapshots of the full original composite and its private body-sibling-hidden state in one Qt session; no raw PNG or coordinates were exported.

IMPORTANT SOURCE-REVIEW CORRECTION: the prior `scripts/wull-fixtures/paint-alpha-paired/shell.qml` hid only the FOUR non-core `WaterDropletBody` visual siblings on the second frame, but did NOT hide the SEPARATE decorative cradle `Rectangle` that is a direct sibling of the original body in `AbyssCompanion`. Therefore the old `SAME_PIXEL_EXTERIOR_OVERLAP=YES` cannot be attributed EXCLUSIVELY to the original Bézier `ShapePath` even though the completely separate previous body-only and source-original ShapePath shadow canaries both independently observed outside-host alpha. Do not retrofit a causal or exact-production conclusion to the old paired result.

NEXT SOURCE-STAGED PRIVATE CORRECTED 12-case static pair, NOT YET OWNER-LOCAL TESTED OR EXECUTED:
- `scripts/wull-private-static-paired-matrix-model.py`, exact Git blob `b8870420db8d1e6cc08f1f5b0f792c4ab186be61`, commit `b9bb995633781f9285fb2bde7199169cd088734a`. Pure-data alpha/host-boundary classifier for four edges × scales .65/1.0/1.5 using 320×300 independent fixed-origin canvases and the reviewed original strict RGBA8 PNG decoder (blob `fa9e7c2af87ee830336988fa7060e2720e816ed0`). Explicit edge-dependent 112×98 or 98×112 host geometry, source-center Qt scale origin and pixel-center comparison. Each case requires positive interior paint in BOTH captures, complete private RGBA8 bounds and empty two-pixel canvas margin. It classifies full-composite exterior alpha, original-core-shadow exterior alpha and SAME pixel-location exterior overlap as three distinct booleans. Its strict twelve-case summary allows ONLY finite categorical edge/scale and boolean result fields, no pixel values, locations, raw PNG, private path or source desktop context. Even full twelve-case success would remain STATIC sampled proof, not global rendered extrema or dynamic/input acceptance.
- `scripts/test-wull-private-paired-static-matrix-contract.py`, blob `280a921232bfc3295c1cf8c06e3bf8eac4f8be2b`, commit `160036dacb9737b7129edbf2205981f13eeb7d1f`, is FAKE-ONLY independent synthetic 320×300 RGBA PNG coverage of ALL twelve test slots, overlapping, disjoint and one-sided exterior paint, positive clean interior, invalid PNG, missing paint, capture-edge truncation, invalid index/parser provenance, duplicate/missing case and forged/private leaked fields. Source-staged, no local PASS yet.
- `scripts/wull-fixtures/paint-static-matrix/shell.qml` updated Git blob `4860f504cff167e806afe8217d73201012b7d278` in correction commit `27913f7aba1dcca6e08c77220232f6372e4486e0`. ONE actual unmodified `AbyssCompanion`/original `WaterDropletBody` in ONE 320×300 privately isolated transparent offscreen Qt stage is reused sequentially for the twelve TOP/RIGHT/BOTTOM/LEFT × three-scale FIXED-stretch cases. Each case verifies expected orientation-specific host dimensions, scale-centered host map-to-stage corners, the body’s source-mapped corners+tip and state, its five exact source-reviewed visual children and the presence of exactly ONE original external cradle direct sibling. Capture original full composite FIRST with both body and cradle visible; THEN private fixture hides the four non-core body visual siblings AND the external cradle, verifies only original full-size four-cubic `ShapePath`/stroke child remains and mapped pose is unchanged to within .05 Qt units, captures second PNG, restores original visibility before advancing to the next edge/scale. Any ambiguous child/cradle identity, drift, incomplete matrix or async save error aborts. The core-scene visibility is intentionally altered ONLY in the disposable fixture, not in production code; sequential pair images are NOT simultaneous pixels.
- `scripts/wull-manual-private-paired-static-matrix.py` blob `fee5944e8fe9fb40a38da24edd104ef78ef32496`, post-correction commit `c2f2eaa8d165ad460c3cbccd2ec54d5ef22b362d`, recursively reuses the earlier owner-owned clean current-`dev` source pins and private process/XDG/D-Bus/Quickshell-v0.3.1 precautions; additionally pins corrected twelve-case fixture/model and the earlier paired runner. Strict 75-second owned child-group process timeout (fixture self-timeout 65 seconds), inherited 8 MiB per-file cap and 256 KiB log cap, exact 62-stage allowlisted sequence, exactly 24 private owner-owned 0600 PNGs each under 1 MiB, complete cleanup, ZERO Git publishing. Outputs only `CASE_XX_{EDGE}_S{SCALE}=F{0|1}C{0|1}O{0|1}`, exact 12-case count, provenance and explicit not-tested dynamic/real-compositor labels.
- `scripts/test-wull-private-static-matrix-runner-contract.py` exact blob `181137e7f1cc96e76bd695df3cc4c2e235678ae1`, post-correction commit `6934dcf5b9c2d5a60569f63bc34b5449e97c372d`: FAKE-ONLY fixture/cradle-visibility contract and strict source-pin, no desktop screenshot/pointer tooling, private group-cleanup/time resource constraints, fixed 62-stage synthetic log categories and negative duplicate/unknown failure tokens, all 24 synthetic owner-owned PNGs, unexpected/missing/corrupt/unsafe-permission image negatives. The new test and runner are SOURCE STAGED only; do not imply an actual 12-case Qt run or that full painted contact necessarily lies outside host at every edge/scale.

NEXT ONE OWNER GATE: use ONE fresh owned mode0700 clean source-pinned `dev` clone to run both NEW fake-only matrix tests (plus the pre-existing original PNG-model inert regression) BEFORE any Qt. Only after exact PASS markers authorize the explicit `scripts/wull-manual-private-paired-static-matrix.py --acknowledge-private-static-paired-matrix` ONCE on that already private clone. Stop on any synthetic/source/cleanup/runtime failure with category ONLY. Interpret measured 12 rows case-by-case, NEVER substitute OR-ed category flags or inferred body-item AABBs for production painted-pixel clipping or clickable input. Original production full-host `Region`, Wull default OFF, Rust backend and `stable` are unchanged; later independent dynamic-frame, compositor input/underlay and native backend gates remain.

## Owner twelve-case corrected static original-core matrix PASSED; dynamic paint pilot is NEXT

**ACTUAL OWNER-LOCAL EVIDENCE**: trusted clean `dev` `SOURCE_SHA=d4d06e053c5cceb21a0fb72ba12d0245334d9f87`. All three new synthetic gates passed: `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`, `WULL_PRIVATE_PAIRED_STATIC_MATRIX_INERT_PASS`, `WULL_PRIVATE_STATIC_MATRIX_RUNNER_INERT_PASS`. Actual original-QML `GATE=PRIVATE_STATIC_PAIRED_MATRIX_CLASSIFIED`, `PAIRED_STATIC_HOST_CASES=12`, `SAME_QT_SESSION=YES`, `SAME_POSE_WITHIN_EACH_PAIR=YES`, `SEQUENTIAL_ALTERED_CORE_SCENE=YES`, `PRODUCTION_MASK_CHANGED=NO`. Exactly twelve full-F/core-C/same-exterior-pixel-O booleans, at frozen stretch=1 only:

| Edge | 0.65 FCO | 1.00 FCO | 1.50 FCO |
|---|---|---|---|
| TOP | 000 | 111 | 111 |
| RIGHT | 000 | 000 | 000 |
| BOTTOM | 000 | 000 | 100 |
| LEFT | 000 | 000 | 000 |

The corrected second frame hides the original external cradle AND all four non-core `WaterDropletBody` visual siblings; only the original source-pinned full-size four-cubic Bézier `ShapePath` and original stroke render. In TOP ×1/1.5 there is one or more same-coordinate thresholded exterior pixels in full companion and deliberately altered true-core-only second captures on the same Qt instance. At BOTTOM ×1.5 the full composite has exterior alpha whereas the isolated core does not (F1 C0 O0); this does **not** prove which non-core element painted the pixel, because independent images are non-simultaneous, and does not prove permanently absent core reach under motion. The nine other zeros are non-observations at this SINGLE frozen stretch pose only, not evidence of bounded motion, offscreen compositor clipping or click/hit reach. Original Qt production source and full-host input Region unchanged.

**NEXT RESEARCH GATE**: prioritize a **small source-pinned private real-Qt dynamic COMPOSITE-only painted-alpha pilot** for TOP ×1 (previous frozen F1/C1/O1) and BOTTOM ×1.5 (frozen F1/C0/O0). Sample the unchanged full companion during REAL authored spring stretch and release phases in its own private 320×300 transparent offscreen capture windows. Strictly distinguish Qt state transition/mapped-geometry observations from actual sampled RGBA8 pixels; require phase/stage and bounded capture count rather than retrofitting static flags. Keep every raw PNG/log inside private mode0700 temp, publish categorical case/phase exterior alpha only, no raw coordinates or pixel counts. A single full-composite dynamic probe still cannot attribute pixels to Bézier vs cradle/halo and is NOT native backend replay or compositor masking. Do NOT immediately launch 48-case paired moving-body exposure, use live screens, enable Wull, modify the full-host input mask or edit `stable`. Subsequent moving **core-only** pilot needs separate safe synchronized frame methodology and controls for sibling/cradle visibility state; dynamic transition and global spring-extrema proof remain independent.

## First active real-Qt FULL-composite painted-alpha PILOT staged after 12-case static matrix

The previous checkpoint's **owner-verified** corrected static 12-case results still apply ONLY to one frozen stretch=1 pose (TOP 1.0/1.5 F1C1O1; BOTTOM 1.5 F1C0O0; all others F0C0O0). The earlier 12×2-phase real dynamic QML geometry receipt sampled original unmodified QML AABBs and nominal tip, **not actual pixels**. Its source witnesses justify prioritizing an actual moving PNG pilot rather than generalizing the static zeros into bounds.

SOURCE-STAGED NEXT OWNER-LOCAL PILOT, **no Qt or inert tests of these new files have yet been run**:
- `scripts/wull-private-dynamic-paint-pilot-model.py` exact Git blob `9ecde49a0d2f77e8fcb6f2d9309978945ef33d8c`: pure Python bounded original RGBAlpha8 decoder interface. TWO ORIGINAL FULL-COMPOSITE cases with independent 320×300 private canvas: TOP scale1 host rect (100,100,112,98) and BOTTOM scale1.5 center-scaled rect (72,75.5,168,147). Exactly 8 separately grabbed frames per case during authored `stretch` and 8 during `release` → exactly **32** independently validated original-composite PNGs, no core visibility mutation. Every frame must contain eight or more inside-host thresholded pixels and empty 2px capture-canvas margin, reject unsupported PNG, invalid or incomplete phase/case/frame order, forged metadata, missing all-true bounded phase/mapped-motion/target-reaching witness. Output only whether **any actually sampled full-composite frame** in each case/phase painted exterior alpha, not raw pixels/counts/frame coordinates or max-spring bounds.
- `scripts/wull-fixtures/paint-dynamic-pilot/shell.qml`, exact Git blob `1f840534e93ff46deb401e52a3eb56cda09a807c`: one private offscreen Quickshell process with TWO transparent self-owned `FloatingWindow`s, each containing exactly ONE unchanged original `AbyssCompanion` (TOP scale1, BOTTOM scale1.5). It normalizes only each private instance to neutral stretch=0, activates its ORIGINAL `WaterDropletBody` authored spring `motionEnabled`, requests stretch=1, then release=0. 8 per-phase 350ms-spaced sequential canvas grabs for each case (32 PNGs); checks active real-QML state, original edge/scale geometry and mapped body corners at capture requests, keeps private per-case sample-to-sample body geometry displacement witnesses and validates stretch/release target reaching. Prints fixed allowlisted stage labels only; abort if either private window/canvas/state/motion/capture path/save fails or self-timeout 38s. Each `grabToImage` captures only its own 320×300 offscreen Item, NEVER host screen/compositor. The two case images are **sequential**, not frame-synchronized; this pilot does NOT capture a source-isolated core or prove painted core vs cradle/halo or native Rust motion.
- `scripts/wull-manual-private-dynamic-paint-pilot.py` exact Git blob `fbab844181f308019287ce06f61c106f4e5bf35c`: separate EXPLICIT opt-in `--acknowledge-private-actual-dynamic-composite-pilot`; reuses and pins earlier clean owned mode0700 current-`dev` source-QML/alpha/classifier/Quickshell-v0.3.1/offscreen Qt guard. One 48s isolated private process-group, private XDG and D-Bus, stripped host Wayland/display/Niri/session bus; inherited 8MiB per-child-file cap, private 256KiB Qt log cap, exactly 32 private owner-owned 0600 PNGs each under 1MiB. Requires exact 38-stage sequence (with source-gated active sampled motion and stretch/release target reach) and returns only `TOP_100_STRETCH_OUTSIDE_HOST`, `TOP_100_RELEASE_OUTSIDE_HOST`, `BOTTOM_150_STRETCH_OUTSIDE_HOST`, `BOTTOM_150_RELEASE_OUTSIDE_HOST` and explicit provenance/gate. No raw screenshot, pixel counts, host coordinates, private filenames or Git publication.
- `scripts/test-wull-private-dynamic-paint-pilot-contract.py` Git blob `517a4986e452bffc0115708cf0fb62f4424c69dc`: synthetic-only exact source/blob pins, two Qt windows only/canvas grabs only, original motion state and timed sampling static contract; validates exact stage sequence and duplicate/unknown-failure rejection, synthetic PNG per-capture and case/phase aggregation (one-sided exterior observations, no paint, canvas edge crop, invalid PNG, bad permissions, missing/extra capture, forged frame fields and missing motion witness). This test neither opens nor mutates any real Qt screenshot.

**NEXT**: ONE owner-owned clean source-pinned `dev` ephemeral clone, run the previous fake-only alpha regression and new dynamic pilot synthetic-only contract. Only on BOTH exact PASS should ONE explicit source-pinned real-Qt two-case dynamic composite pilot run. On any failure stop and report the fixed `GATE` category. Even if all 32 actual frame captures succeed, sampled full-composite alpha cannot be attributed specifically to source-original Bézier paint; it does not prove actual Wayland compositor host clipping, input hit/hover, popup, native backend replay or worst-case spring extrema. The production full-host input `Region`, Wull default-off, native Rust and `stable` remain unchanged.

## Actual dynamic painted pilot INCONCLUSIVE; private allowlisted Qt failure diagnosis staged

Owner-local one fresh clean `dev` at `SOURCE_SHA=8ec15920c9a0c2b952ea6116e8bcc2fb81bf6540`: both `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS` and `WULL_PRIVATE_DYNAMIC_COMPOSITE_PILOT_INERT_PASS`, then actual unmodified-composite active-spring QT runner returned only `GATE=PRIVATE_QT_STAGE_OR_MOTION_INCONCLUSIVE`. This gate originates **after** bounded private child-run, cleanup, exit code zero, private log size/ownership check and allowlisted parser, but **before** the exactly 38-stage success check and BEFORE validation/classification of any of the 32 actual private captured PNGs. There are NO qualified actual dynamic painted pixels or state/phase evidence from this failed pilot; no implication about which failure category, amount of motion, or sampled alpha follows from this one aggregate code. The prior qualified 12-case **STATIC** 4edge×3scale painted matrix remains the latest accepted evidence. The owner shell auto-deleted its disposable clone/private log, so the precise failure reason cannot be reconstructed from the old run.

Source-staged SAFE DIAGNOSTIC ONLY (NEW fake-only test and Qt diagnostic NOT YET owner executed): `scripts/wull-private-dynamic-pilot-diagnose.py`, exact Git blob `e62e2a9df17af75168b5f26f0bd77f47e1035b37`, commit `eea441bfea2eeb6cb36d9e90b5d734d4cf64ce5c`. When and ONLY when the same original source-pinned dynamic runner reproduces EXACTLY `GATE=PRIVATE_QT_STAGE_OR_MOTION_INCONCLUSIVE` in a FRESH private clone, run this diagnostic immediately before clone cleanup, with explicit opt-in. The diagnostic **does not run or modify Qt**, screenshots, production, Git or host desktop. It source-audits the exact old runner, original-QML safety guards/current owned 0700 clean `dev` clone, verifies previous failure log under the known private directory is an owner-owned 0600 regular file with size <=256KiB, and parses **only existing fixed allowlisted** `WULL_DYNAMIC_PILOT_STAGE` and `WULL_DYNAMIC_PILOT_FAILURE` tokens. Requires original stage-order prefix, no duplicates/unknown labels, at most ONE reviewed category, no stage after failure; outputs ONLY categorical `LAST_REVIEWED_STAGE`, `OBSERVED_STAGE_COUNT`, `KNOWN_QML_FAILURE` and an unambiguously *FAILED or incomplete* `GATE`. No raw log, QString diagnostic, source username/path, coordinates, captures, QML stack traces or pixel data may be printed.
`scripts/test-wull-private-dynamic-pilot-diagnostic-contract.py`, exact Git blob `b8ccbf7860d1d2289f5c9d4b84a2ee531666dda5`, commit `ec73dc60a516654faf6540ef85378672bac02de5`, is NEW fake-only source/hash, log-prefix/order, fixed known QML failure and stage-incomplete classification, duplicate/reordered/unknown/suspicious failure marker rejection, before/after complete stage negative cases and read-only/privacy checks. NOT YET OWNER TESTED. It does not start Qt.

NEXT ONE OWNER ACTION: one NEW source-pinned clean private mode0700 ephemeral `dev` clone: require previous alpha fake PASS, previous pilot fake PASS and NEW diagnostic fake PASS, no source drift. Then ONE explicit original dynamic pilot run again. If the actual runner now fully qualifies, report ONLY the standard four case/phase categorical outputs. If and ONLY if it returns the exact prior ambiguous `PRIVATE_QT_STAGE_OR_MOTION_INCONCLUSIVE`, run the new read-only diagnostic immediately on its retained private log IN THE SAME CLONE, returning fixed category and last reviewed stage without private data. On other fixed failure gates, report exactly that gate without diagnosis. Stop; do NOT automatically rerun Qt yet again or relax stage/motion conditions, and do NOT promote the failed attempt to acceptance. No production full-host mask, Wull default-off, original QML, native backend or `stable` changes.

## Owner dynamic failure identified: original 16 stretch captures completed; independent moving-body witness missing

Owner-local at `SOURCE_SHA=91c36628c08b44435591774f28e495290d1726d8`: all existing painted-alpha, original dynamic pilot and new diagnostic fake-only inert tests PASS. Actual original-QML private Qt dynamic pilot still FAILS CLOSED with `GATE=PRIVATE_QT_STAGE_OR_MOTION_INCONCLUSIVE`. Read-only **same-run** fixed-token diagnosis of owner-private retained log before automatic cleanup returned `OBSERVED_STAGE_COUNT=19`, `LAST_REVIEWED_STAGE=STRETCH_7_BOTTOM`, `KNOWN_QML_FAILURE=SAMPLED_MAPPED_MOTION_NOT_OBSERVED`, `GATE=PRIVATE_DYNAMIC_QML_FAILURE_IDENTIFIED`. These 19 markers comprise the three successful startup/neutral/start markers and 16 success markers for all eight sequential TOP/BOTTOM stretch PNG saves. The source QML checks `moved.every(true)` at end of stretch; at least one case did not demonstrate mapped motion at the eight *PNG-request points*. This old failure does **not** distinguish TOP from BOTTOM, prove spring was not moving earlier, or validate any saved PNG; release did not execute. Actual moving painted-alpha remains UNQUALIFIED, while the previously owner-qualified frozen 12-case full/core painted-alpha matrix remains valid.

Source review confirms original, UNMODIFIED `WaterDropletBody.qml` blob `fc5b1c227026786ab553685bc170daff74e82517` contains `Behavior on stateStretch { enabled: root.motionEnabled; SpringAnimation { spring: 2.8; damping: 0.36 } }` and independent bob/sway animations. Original private dynamic pilot tested mapped geometry only at sequential PNG-grab starts, each separated by a 350ms timer **AFTER** asynchronous two-window PNG saves. Thus sampling alias/settling is a plausible source-based explanation, NOT a verified root cause. Never bypass motion witness or label a saved PNG as a true moving-frame observation without independent evidence.

NEXT SOURCE-STAGED STRICT EXPERIMENT (new source files have NOT yet run owner-local synthetic tests nor actual Qt):
- `scripts/wull-fixtures/paint-dynamic-observed/shell.qml` exact blob `bc3686ce54ea1bb1b5fc8f73955f714720306124`, commit `7aa50d907211b4fb436d421723e708ad0820b707`. Reuses unchanged original production-QML full composites at TOP×1.0 and BOTTOM×1.5 in two separate 320×300 **owned private offscreen canvas** windows in the same Qt process. Preserves the existing 8 sequential actual PNG `grabToImage` per case per stretch/release phase (32 total), the former 350ms image tick and no sibling/core visibility mutation. Adds an INDEPENDENT 40ms `motionWatch` QML timer started immediately after original authored spring stretch/release target changes and BEFORE first delayed screenshot; continuously measures the source-mapped original body corners and source `stateStretch` for BOTH cases. Per case/phase, require at least 4 observer samples, >0.10 actual source `stateStretch` movement, an intermediate sampled original `stateStretch` (0.12–0.88), mapped corner displacement >0.12 Qt units, all active original geometry/source/host-scale checks and original phase target reaching; exact 38 valid image/stage sequence must still pass. An empty or too-late image-sampling window cannot silently qualify. Each of 16 categorical fixture error names distinguishes TOP/BOTTOM × stretch/release × missing observer, missing spring, missing transition or missing mapped motion, plus fixed private geometry/baseline/save error codes. It prints no pixel/coordinate/log/path data.
- `scripts/wull-manual-private-dynamic-paint-observed.py` exact blob `fd3935d5be76bfd6014cc4990df07f62c5231503`, commit `78c144ebb003e50ecf2deb4ea59937b310554fbd`. Copies and pins previously source-reviewed owner-private clean current-`dev` clone, original production renderer/style/config/PNG model and Quickshell 0.3.1 isolated offscreen environment, private XDG+D-Bus; one 48-second dedicated child group with full cleanup, inherited 8MiB child file limit, <=256KiB private log, exactly 32 owner 0600 PNG each <=1MiB, source immutability, 38 ordered stage labels and original strict RGBA8+canvas-truncation/inside-paint classification. Only after source QML independent spring and mapped-motion witnesses on BOTH cases in BOTH phases does successful runner report four case+phase actual full-composite painted-alpha exterior categorical flags. For known reviewed QML failure, requires authentic stage prefix and returns ONLY `KNOWN_QML_FAILURE`, `LAST_REVIEWED_STAGE`, `GATE=PRIVATE_OBSERVED_DYNAMIC_QML_FAILURE_IDENTIFIED`; unexpected failure remains fixed GATE without raw output. Does not open the host desktop, publish image/log or alter original Wull QML, input Region or Rust.
- `scripts/test-wull-private-dynamic-paint-observed-contract.py` exact blob `c445d3c7761b1bc16ce33b8c6f0f88462d6fd889`, commit `ad92241fed727422f4bdfcc2b2d1d800c1204d0f`. NEW fake-only source pin, separately timed movement/source-state/intermediate/both-case/both-phase contract, strict stage/failure categorization and synthetic full 32-frame RGBA PNG matrix negative tests for truncation, malformed/missing/private permission, forged frame metadata and absent witness. Its source stage is verified on `dev` but fake-only contract itself NOT owner-local executed yet.

NEXT ONE OWNER ACTION: new private owner-mode0700 clean source-pinned `dev` clone, old PNG fake and NEW observed fake tests first. Only on both exact PASS run ONE original-QML independent-observer dynamic composite Qt pilot `scripts/wull-manual-private-dynamic-paint-observed.py --acknowledge-private-actual-dynamic-composite-pilot`. On failure STOP and report explicit new source-gated category/stage; do not rerun the old confounded source pilot or weaken movement thresholds. Static 12-case exterior painted-alpha findings persist. A possible new dynamic painted composite success would still NOT prove painted Bézier-core source attribution, real compositor clipping, production pointer input, native backend replay, spring global extrema or all-edge/scale coverage. Keep full-host production input Region, Wull default OFF, original QML/Rust and `stable` untouched.

## Owner real moving full-composite Qt PASS; original-core moving-paint pilot staged

At owner-local `SOURCE_SHA=2717ce9a683aa1eca69db4720454f1bdb343384a`, NEW independent 40ms-observer source-pin synthetic regression `WULL_PRIVATE_DYNAMIC_OBSERVED_INERT_PASS` and original bounded alpha regression `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS` both PASSED; ONE private actual Quickshell 0.3.1 original-full-composite two-case dynamic Qt pilot then returned `GATE=PRIVATE_DYNAMIC_COMPOSITE_PILOT_CLASSIFIED`, `QT_DYNAMIC_FRAMES=32`, `INDEPENDENT_40MS_QT_MOTION_WITNESSES=YES`, `ACTUAL_PNG_FRAMES_SEQUENTIALLY_CAPTURED=YES`, original unchanged `AbyssCompanion`, and `PRODUCTION_MASK_CHANGED=NO`. Actual observed painted exterior-alpha flags across the eight *sampled* PNG frames per case/phase:

| Case | Stretch exterior alpha | Release exterior alpha |
|---|---|---|
| TOP scale1.0 | YES | NO observed |
| BOTTOM scale1.5 | YES | YES |

The real original spring and mapped corner changes were separately sampled at 40ms for BOTH cases in BOTH phases and enforced at the source before successful PNG classification. These are actual offscreen painted RGBA8 observations of the unmodified full composite; they do NOT determine painted origin (original core vs separate cradle/internal children), prove every animation instant or maximum spring envelope, test all 12 edge-scale cases, or test live compositor clipping or pointer input. In particular TOP/release NO is *non-observation in eight sampled captures*, not a global absence statement. Previous corrected source-isolated static TOP ×1/×1.5 alpha overlap and BOTTOM ×1.5 F1/C0/O0 are separate FROZEN evidence; combining separately run snapshots never qualifies instantaneous source-specific pixel causation.

NEXT carefully bounded SOURCE-STAGED private **moving ORIGINAL Bézier ShapePath/stroke-only pilot**, not yet owner-local inert or Qt executed:
- `scripts/wull-private-dynamic-core-model.py`, exact blob `ec4ba1af10cabbb1f645ea94af7f5fca0ac5e731`, commit `91e7b3aa8d244656e8d039c7e62ebd2601c30d17`: pure source-specific classification using the prior unmodified strict 320×300 PNG alpha parser, identical center-scaled TOP×1 and BOTTOM×1.5 host rects, 8 PNG samples per original spring phase/case (32 total), strict two-pixel transparent canvas border and interior paint, phase+mapped-geometry+transition/target-reaching witnesses. Model output and phase flags explicitly say PRIVATE `original_core_only_altered_private_scene` and `source_core_outside_host_alpha`, never mislabel the altered image as the full production composite or manufacture frame-paired overlap with a previous run.
- `scripts/wull-fixtures/paint-dynamic-core/shell.qml`, final blob `d10da7216afef1ba579775a87505b2d649e4fe65`, corrected commit `a502377ef308e552c28e22b7fcb138355cea72c6`: two separate owner-owned transparent offscreen 320×300 Qt windows, original exact `AbyssCompanion`/original `WaterDropletBody` source unchanged at TOP×1 / BOTTOM×1.5. Only BEFORE the original real spring animation begins, verify each source component has EXACTLY two direct children (original WaterDropletBody and one original external cradle), EXACTLY five original body visual children, ONE uniquely identifiable untransformed 76×92 full-size original Bézier `Shape` among them and all five initially visible. Hide external cradle and four non-core body siblings **only on the private instantiated originals**, ensure original full-size Bézier/stroke remains visible and verify the isolation persists before every observer geometry tick and PNG grab. On topology or visibility mismatch fail closed. Preserve previously owner-PASS 40ms INDEPENDENT actual stateStretch + mapped-body motion observer, strict per-case/phase >=4 / >.10 spring change / intermediate state / >.12 mapped displacement / original target reach, and original 350ms 8-capture cycle per phase; abort rather than silently accept motionless PNGs. Fixed categorical `CORE_ISOLATION_INVALID`, `CORE_ISOLATION_DRIFT` and original 16 per-case motion failure labels only.
- `scripts/wull-manual-private-dynamic-core.py`, final blob `50e351a3ec2775f02d92d76e63d09727e008cf71`, correction commit `a735d0b8aed71b0951feceea813645e8f80b7913`: pins new fixture and core-only classifier plus original unchanged approved QML/old owner private safety guard/PNG decoder. Reuses previously owner-PASS one 48s owned isolated Qt group/private XDG+D-Bus and offscreen-only Quickshell 0.3.1, 8MiB file/256KiB owner-only log/32 exact 0600 original-core PNG constraints and post-run current clean `dev` guard. Success now needs exactly **39 fixed ordered stage markers**, including `CORE_ISOLATION_VERIFIED` BEFORE transition witness and every original-motion+PNG stage, plus strict classification of all 32 actual original-Bézier-only PNGs. Returns only four `TOP_100_CORE_*` / `BOTTOM_150_CORE_*` phase-specific yes/no flags; explicit `FULL_SCENE_PIXEL_MATCH=NOT_TESTED`, unchanged mask and no live compositor claim. Every known isolation/motion failure returns categorical `KNOWN_QML_FAILURE` / `LAST_REVIEWED_STAGE` / failed gate only; never prints private source paths/raw PNG/raw log/coordinates nor publishes Git evidence.
- `scripts/test-wull-private-dynamic-core-contract.py`, final blob `388112cab3aef026795ba40de0d6990cc4d32257`, commit `1896f6e786fb0e907cb2c5401a2fdb3c6497dc4d`: derived independent fake-only source pins and private visual-source isolation assertions, independent 40ms original spring+mapped motion, 39 exact success stage labels, known fixed failure handling and 32 synthetic RGBA8 core-only capture validity/negative permission, missing, forged frame metadata/missing witness, edge crop and invalid PNG. New test is staged NOT yet owner-executed; synthetic PASS cannot substitute for real Qt.

NEXT ONE OWNER ACTION: fresh clean owner-mode0700 current `dev` ephemeral clone, pin exactly four new files plus the original unchanged QML/PNG decoder/borrowed trusted guard; run previous owner-PASS `scripts/test-wull-private-painted-alpha-model.py` and **new** `scripts/test-wull-private-dynamic-core-contract.py` fake-only. Only if both return their EXACT distinct PASS markers, run ONE opt-in private original-core moving alpha pilot `scripts/wull-manual-private-dynamic-core.py --acknowledge-private-actual-dynamic-composite-pilot` on the SAME clone; report strict four categorical original-core phase outcomes or a fixed fail-closed QML-specific category and stage. Never compare raw coordinates/pixels across independently captured previous full and current core runs; this stage establishes source-specific exterior alpha **existence** in moving core-only PRIVATE scenes, not same-frame production core causality, compositor clipping, hitboxes or Rust-native backend motion replay. No modification of production QML, full-host input Region/default-off Wull, Rust or `stable`.

## Moving original-core inert gate diagnosed: stale composite environment-string assertion

Owner's FIRST new-core attempt returned ONLY `GATE=DYNAMIC_CORE_INERT_FAILED` before emitting `DEV_HEAD` or running Qt. Thus original moving core-only Qt images, 40ms movement witnesses, source-specific exterior-alpha flags, and any full/core moving comparison remain UNTESTED. The earlier owner-qualified 32-frame unchanged-full-composite dynamic Qt pilot at `SOURCE_SHA=2717ce9a683aa1eca69db4720454f1bdb343384a` remains valid (TOP×1 stretch YES, release NO observed; BOTTOM×1.5 stretch YES, release YES). Static corrected 12-case evidence remains valid.

Source review found a concrete stale synthetic assertion in first `scripts/test-wull-private-dynamic-core-contract.py` blob `388112cab3aef026795ba40de0d6990cc4d32257`: the derived inert test incorrectly required the old full-composite runner environment `env["WULL_DYNAMIC_PILOT_DIR"]`, although the intentionally distinct new core-only runner/fixture both correctly use `WULL_DYNAMIC_CORE_DIR`. No source-core classification, security controls, real Qt or production change is warranted by this mismatch alone. The one-line exact source-audited fix is CURRENT fake-only contract blob `6d141b02aecd1929ae9c197dffaa1112aff87b06`, commit `74399693ed87a4a3f03f328fd0aaeb696fc63601`. Review of every source spelling/marker checked by the derived static fixture and runner assertions found no further mismatches at this commit. No new owner-local test run has occurred since the edit; do NOT claim inert PASS or actual core-only Qt acceptance yet.

Next owner action: ONE new owner-owned mode0700 disposable current-`dev` clean clone with unchanged reviewed source pins and CORRECTED synthetic-test blob. Run previous original RGBA8 fake gate then corrected moving-original-core fake gate BEFORE invoking Qt. If and only if both exact markers PASS, opt in ONCE to the same source-pinned 32-frame original-core-only moving Qt pilot. Its second-state scene is deliberately PRIVATE modified visibility (external cradle and four non-core body children hidden) on original-QML component instances only; it is not an exact production scene or simultaneous same-pixel comparison against the previous unmodified full scene. A test failure is not consent to relax visual-isolation/motion/source/pixel/ownership or mask gates. Keep original QML, full-host production Region, default-off Wull, Rust and `stable` untouched.

## Owner-qualified original moving Bézier-only pilot: TOP stretch YES, BOTTOM moving core NO

At actual OWNER-LOCAL clean `dev` `SOURCE_SHA=1d7778b16863ac0bde433e23f08e36ac099f8f36`, previous `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS` and corrected `WULL_PRIVATE_DYNAMIC_CORE_INERT_PASS` both qualified BEFORE one owned-private real-Qt original-ShapePath/stroke-only spring experiment. Source-pinned ORIGINAL `AbyssCompanion` and `WaterDropletBody` in two private altered 320×300 isolated instances, four source-reviewed non-core body visuals and the original external cradle hidden in fixture ONLY: `QT_DYNAMIC_CORE_FRAMES=32`, `INDEPENDENT_40MS_QT_MOTION_WITNESSES=YES`, `CORE_ONLY_PRIVATE_VISIBILITY=YES`, `GATE=PRIVATE_DYNAMIC_CORE_PILOT_CLASSIFIED`, `PRODUCTION_MASK_CHANGED=NO`. Core-only actual sampled painted exterior alpha (eight rendered frames per case/phase):

| Case | Core-only stretch | Core-only release | Prior independent actual ORIGINAL FULL-COMPOSITE stretch | Prior full release |
|---|---|---|---|---|
| TOP ×1.0 | YES | NO observed | YES | NO observed |
| BOTTOM ×1.5 | NO observed | NO observed | YES | YES |

The full-composite evidence was owner qualified separately at `SOURCE_SHA=2717ce9a683aa1eca69db4720454f1bdb343384a`; despite original source being unchanged and same authored phase/case, original full and new private altered core-only image streams were **NOT synchronized or pixel-paired**. Hence BOTTOM's full-positive/core-negative contrast motivates testing the original external cradle or four non-core body visual siblings as candidate paint contributors, but does NOT prove which painted a given exterior pixel or that core exterior paint is globally impossible during animation. Existing corrected SINGLE-SAME-Qt-PROCESS static 12-case proof at frozen stretch1 also shows TOP ×1/×1.5 F1C1O1 and BOTTOM ×1.5 F1C0O0. Thus target high-value NEXT narrow source-pinned private BOTTOM ×1.5 FROZEN same-instance, same-pose full vs individual external cradle, original core Bézier/stroke, internal glow/halo, specular highlight, eyes and mouth: independently check original component topology and paint bounding coordinates before attribution. Each isolated image is a deliberately altered private visibility state, captured sequentially; anti-aliasing, occlusion and compositing may make full scene DIFFERENT from the union of individually isolated layers. Output only flags/within-pose same-pixel exterior overlaps for each individual vs original full if actual observed; never subtract alpha, assign exact full pixels solely from independently sampled animation, infer native Wayland compositor clipping/hits, or relax full-host production Region. No production or `stable` edits.

## Bottom ×1.5 targeted static original paint-source partition staged after actual moving-core PASS

Previous full-vs-core actual owner results retained without interpretation drift: source-unmodified ORIGINAL full composite real-spring 32-frame pilot at `SOURCE_SHA=2717ce9a683aa1eca69db4720454f1bdb343384a`: TOP×1 stretch YES / release NO-observed, BOTTOM×1.5 stretch YES / release YES. Separately owner-qualified original Bézier `ShapePath`/stroke-only real-spring 32-frame original private sibling/cradle-hidden pilot at `SOURCE_SHA=1d7778b16863ac0bde433e23f08e36ac099f8f36`: TOP×1 stretch YES / release NO-observed, BOTTOM×1.5 stretch NO-observed / release NO-observed. Both campaigns required independent real Qt spring `stateStretch` transition + mapped-body geometry observations at 40ms for both cases and both phases. They are **different-source-instance independently timed runs**: this contrast is NOT simultaneous pixel overlap or proof that BOTTOM's moving core can NEVER paint outside host. Prior original actual same-Qt same-pose corrected static 12-case matrix measured BOTTOM×1.5 full F1/core C0/overlap O0, again without identifying which other element is responsible.

NEXT narrow static attribution experiment now **SOURCE STAGED ONLY**: four captures at BOTTOM×1.5 frozen original `stateStretch=1`, exactly ONE original unchanged `AbyssCompanion` and original `WaterDropletBody` instance in ONE owned-private 320×300 transparent offscreen Qt session; image 1 actual original **FULL** scene, image 2 only original 76×92 four-cubic Bézier **CORE** and stroke (external cradle and four body detail visuals hidden), image 3 only the **DETAILS** group (the four source non-core body visual siblings with Bézier core and external cradle hidden), image 4 only the original external **CRADLE** (all five body visual children hidden). All captures sequential and **same frozen mapped 24-coordinate pose within .05 Qt units**; original component source child count exactly two (body and one external cradle), body original five visual children with uniquely identified full-size core; source-pinned exact original source and scale-mapped host rect `(72,75.5,168,147)`; new disposable fixture restores original full visibility and checks identity before completing. This first GROUP partition distinguishes potential external cradle vs internal details without prematurely singling out glow/eyes/mouth; ONLY if details-group exterior is positive is a finer internal decomposition warranted.

- New pure INERT `scripts/wull-private-bottom-static-source-model.py`, Git blob `3eb60d0b7222c12f6d07a772f3bbf94e0cadb3f3`, creation commit `cf87a56790dd4fea47ca2ebc99aefdf1472933d9`, source-pins the prior strict RGBAlpha8 PNG decoder, exact four 320×300 own capture slots, 2px canvas-edge privacy margin, >=8 inside thresholded pixels for full/core; permits genuinely zero-alpha DETAILS/CRADLE rather than incorrectly inventing their paint. Returns boolean actual exterior paint per each isolated scene and strict **same-pixel exterior overlap** of each separate source-isolated static image with the original FULL earlier sequential image at the same frozen mapped pose. Same coordinate overlap is **not** formal attribution/causality: separately isolated layers can occlude, anti-alias or blend differently.
- New source fixture `scripts/wull-fixtures/paint-bottom-source/shell.qml`, Git blob `3838ac82c70263324fa50185d75a60478363f7c1`, creation commit `f1c2b31a25c5d47d085b4a13b1df291bb9f60a0b`, uses only one unmodified original component and four private visibility states, exact source topology and mapped pose, no host screen, pointer injection, compositor access, native backend or production QML changes. Exact fixed 11-category stage sequence includes `BOOT`, `PREPARED`, four sequential REQUESTED/SAVED pairs and `DONE`; no private coordinates/screenshots in public log.
- New guarded `scripts/wull-manual-private-bottom-source.py`, Git blob `5130e0dcf14e987291f828fc4ce6baaf8429af2f`, commit `7962444f7fe9e42343293f32f7ee581fd7516f41`, borrows previously owner-PASSED source recursion/proven original QML, clean exact `dev`, private process/XDG/D-Bus/offscreen Quickshell 0.3.1 and safety guard. ONE 34-second owned private child group/cleanup, fixture self-timeout 24s, <=256KiB private owner log, 8MiB inherited child-file ceiling, exactly FOUR owner-owned 0600 PNGs each <=1MiB, strict all-stages/four-capture classification. Outputs only four source-isolated exterior boolean flags and three with FULL same-pixel exterior-overlap flags, provenance/limitations, or a fixed known source/QML category; never publishes raw pixels/log/screenshots or edits Git during probing.
- New **FAKE-ONLY** `scripts/test-wull-private-bottom-static-source-contract.py`, Git blob `a8822ac52b8c92d14c34176ff462e90808a1cd5a`, creation commit `c10a9bfac83ef991aaa0d1327f1bbd077eefe84c`, verifies exact four new/source-borrowed blobs, original isolated first full component in one private 320×300 Qt window, exact source child topology and mapped-pose guards, source visibility group partition, fixed strict stage/error/resource/capture contracts, synthetic alpha classifications for both cradle-only and DETAILS-only exterior, same-vs-disjoint overlap, transparent noncore isolation, corrupt/incomplete/canvas-edge/unsafe/missing/extra PNGs. **Neither new inert contract nor actual Qt four-image probe has been owner-local executed**. Previous moving 32-frame qualifications remain independently accepted.

NEXT: ONE clean owner-only mode0700 disposable current-`dev` exact-blob-pinned private clone; FIRST previous original PNG model fake and new bottom source-layer synthetic contract. ONLY on both exact PASS, launch one explicitly acknowledged source-isolated original BOTTOM×1.5 four-image static actual Qt probe. Return only source SHA and fixed categorical result or fail-closed gate; DO NOT invent instant dynamic attribution, make production mask narrower, enable Wull by default, affect native Rust/`stable`, or claim actual live Wayland pointer clipping/hit testing.

## Owner-qualified BOTTOM source partition: static cradle exterior paint; private cradle-inset candidate staged

OWNER-LOCAL at clean `SOURCE_SHA=bfd8f82c56ed33567ed17eb7e95013a7860d0402`: original bounded RGBA8 fake `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`, four-scene original-bottom original-layer fake `WULL_PRIVATE_BOTTOM_STATIC_SOURCE_INERT_PASS`, then one actual Qt 0.3.1 owned-private SAME-original-instance/SAME-frozen-pose original BOTTOM×scale1.5 full/core/details/cradle probe PASS: `FOUR_SEQUENTIAL_PRIVATE_CAPTURES=YES`, `FULL_EXTERIOR=YES`, `CORE_EXTERIOR=NO`, `DETAILS_EXTERIOR=NO`, `CRADLE_EXTERIOR=YES`; sampled exterior pixel overlaps with actual unmodified full prior same-pose image: CORE NO, DETAILS NO, CRADLE YES; `GATE=PRIVATE_BOTTOM_STATIC_SOURCE_CLASSIFIED`. Source provenance and original body+cradle topology/pose were explicitly gated and private alternate visibility restored at completion. This is strong STATIC fixed-pose localization: the ORIGINAL external cradle alone has pixels outside BOTTOM host that share image coordinates with pixels outside the original FULL companion. Still NOT proof of exact production pixel causality, all animation extrema, alpha compositing under occlusion, native Wayland compositor clipping/click or other edges/scales. Earlier independent actual full moving and original-core-only moving Qt 32-frame results remain valid but unpaired; BOTTOM full STRETCH/RELEASE YES while original-core-only sampled STRETCH/RELEASE NO, suggesting testing the static source-localized cradle's boundary geometry before production mutation.

Exact source review of unchanged `modules/abyss/companion/AbyssCompanion.qml` blob `b5b01835a282458eba0d0268396ae2c350d919d2` confirms the external cradle is an original rectangular visual sibling of original `WaterDropletBody`, anchors `bottom: parent.bottom` with width58 and height10 on horizontal BOTTOM, rounded radius/border, and `scale:1+root.ripple*0.16`. For the already owner-reviewed `ripple=0, pulse=0` fixed source fixture, the cradle scale remains 1 and its host-anchor geometry does not depend on body `stateStretch`. Thus next isolate an adjustable, *nonproduction candidate cradle inset* rather than repeating the same static identity test under a changing body spring without paired causality.

NEW four-file **SOURCE-STAGED ONLY, NOT owner-local synthetic PASS or real Qt executed**:
- Pure model `scripts/wull-private-bottom-cradle-inset-model.py` git blob `77c89bd49771992b2618ba656768840592aaa594` commit `646ec1fbfc841ec98257fc2a9761ea4c4e30fdf5`: four original full-composite RGBA8 PNGs at fixed BOTTOM×1.5 host logical center-scaled rect `(72,75.5,168,147)`, trial original cradle bottom anchor margin 0/1/2/3 logical QML pixels, same 2px no-paint-on-canvas-margin and >=8 original interior alpha threshold. Margin0 ORIGINAL-SOURCE full scene exterior alpha must be **YES** or the run fails closed as `ORIGINAL_ZERO_MARGIN_BASELINE_NOT_REPRODUCED`. Reports strictly fixed per-trial exterior alpha boolean and smallest zero-exterior **among tested margins ONLY** or NONE. Does NOT infer a universal minimum, preservation of appearance, dynamic spring safety, original popup connection or actual compositor/hitboxes.
- NEW fixture `scripts/wull-fixtures/paint-bottom-inset/shell.qml` blob `45fc03e743d08a996c763c491e0d2b42d22f75ba`, commit `04d971901612ff71870f37b91de33c72533e7ab1`: EXACT ONE unchanged original `AbyssCompanion` and original `WaterDropletBody` instance in ONE owned-private 320×300 offscreen Qt window, original BOTTOM scale1.5, original frozen stateStretch1 and ripple/pulse0, same 24-number mapped body/host pose tolerance .05 across all images and all five original body visuals intact/visible. Sequentially render four ORIGINAL FULL sibling scenes, changing only `root.sourceCradle.anchors.bottomMargin` on the disposable cradle instance from 0→1→2→3; verify exact cradle mapped position for each (original logical bottom-margin increment × Qt host scale1.5), original host rect, original painted source topology, then RESTORE 0 and verify before completing. The baseline image is actual unmodified production *component state* in this private frozen scene, while inset variants are intentionally altered private candidate states. NO host compositor access, pointer injection, native backend, source QML or original mask edit.
- NEW guarded `scripts/wull-manual-private-bottom-inset.py` blob `75f923b104c8409b3532a809c3ba62cfd5998e03`, commit `0716db5c6fa131c26752dbf8630d2980479cecad`, reuses recursively PINNED previous actually owner-qualified `scripts/wull-manual-private-bottom-source.py` (blob `5130e0dcf14e987291f828fc4ce6baaf8429af2f`) and its reviewed original QML/pair/clean-current-`dev` trusted remote private setup. Original Quickshell0.3.1 offscreen private XDG+D-Bus; one 34s isolated owned Qt child group, mandatory group kill+reap, inherited 8MiB file-size limit, 256KiB private owned bounded log, exact 11 fixed source-reviewed stage markers, EXACT four owner-owned 0600 PNG each <=1MiB and source unchanged after run. Prints ONLY fixed categorical four-margin sample evidence, numeric smallest TESTED inset (1/2/3/NONE), explicit provenance and untested caveats; on failure only allowlisted QML stage/name or fixed GATE, no private path, screenshot, pixels or Qt log printed.
- NEW FAKE-ONLY `scripts/test-wull-private-bottom-inset-contract.py` blob `83df8635e1cede5040f0c2ec520a76ea5588af4c`, commit `7c8031989b02e653e172b9d22288f1676e7e05b9`: immutable source/blob pins, explicit candidate-only margin mutations and frozen pose/cradle map validation, exact stage/resource/one original source-instance Qt structure, synthetic 4×320×300 RGBA8 PNGs for baseline+margin1 exterior and margin2/3 absent (minimum tested2), all-positive NONE, first-candidate1, negative baseline NOT reproduced, illegal capture/missing/extra/insecure/canvas-edge/interior absence, synthetic fixed log injection rejection. It does not launch real Qt or publish private data. New files source-string checked together with unchanged production QML and one-original-instance fixture; **owner local fake and actual Qt have NOT executed yet**.

NEXT ONE OWNER ACTION: one fresh owner-owned mode0700 clean source-pinned current-`dev` ephemeral clone. Run previously owner-PASSED `test-wull-private-painted-alpha-model.py` and NEW fake-only `test-wull-private-bottom-inset-contract.py` first. Only on both exact PASS launch ONE acknowledged offscreen actual original bottom cradle inset pilot `scripts/wull-manual-private-bottom-inset.py --acknowledge-private-bottom-cradle-inset`; report four strict categorical baseline+inset observations, smallest *tested* static margin or fixed failure. If any inset removes the sampled static exterior alpha, **do NOT patch production yet**; next verify all four edges/scales and actual moving full-composite spring phases in private candidate configuration, preserve cradle's intended visual panel connection and ultimately test actual Wayland compositor real pointer/clip before changing production input Region or default Wull behavior. If none works, preserve all fail evidence and investigate source opacity/border/rasterization. Never touch `stable`.

## Owner-qualified BOTTOM×1.5 original cradle inset candidate: 1 logical px static sample

OWNER ACTUAL at `SOURCE_SHA=8fb4d2ebb7453030562b6906621c594cbfdaa330`: both existing bounded RGBA8 and NEW cradle-margin fake contracts PASSED, then ONE actual source-pinned Qt 0.3.1 owner-private BOTTOM scale1.5 ONE original full-companion same-frozen-body-pose four sequential private screenshots at bottomMargin original0 and candidate1/2/3 PASSED. Actual private RGBA8 `BASELINE_M0_OUTSIDE_HOST=YES`, `M1_OUTSIDE_HOST=NO`, `M2_OUTSIDE_HOST=NO`, `M3_OUTSIDE_HOST=NO`; `SMALLEST_TESTED_NO_EXTERIOR_MARGIN=1`, `GATE=PRIVATE_BOTTOM_INSET_CANDIDATE_CLASSIFIED`, `PRODUCTION_MASK_CHANGED=NO`. This result establishes that changing ONLY the disposable original cradle's `anchors.bottomMargin` from 0 to **1 original host logical Qt pixel** eliminated thresholded painted exterior alpha in that ONE exact frozen BOTTOM×1.5 scene. The renderer source, input Region, original Wull default-off, native Rust and `stable` remain untouched. This is the minimum **among 1/2/3 TESTED**, not a fractional/global minimum nor a styling, dynamic/Wayland pointer/clipping guarantee. The previous owner-qualified exact original static BOTTOM layer partition showed FULL YES, CORE NO, DETAILS NO, CRADLE YES with CRADLE sharing sampled FULL exterior pixel coordinates; it does not prove dynamic full pixel causality.

NEXT private experimental gate, NOT yet owner accepted: TWO ORIGINAL full companion instances simultaneously in ONE isolated offscreen Qt process at BOTTOM×1.5, one unchanged original cradle margin0 as dynamic positive CONTROL, other privately inset exactly margin1. Both original source-pinned `WaterDropletBody` springs must independently transition neutral→stretch→release, with independent 40ms original stateStretch/intermediate and mapped-body displacement witnesses, exact source/cradle mapped geometry (host rect and margin location), and eight sequential original FULL rendered RGBA8 images for each of two phases in each private case (32 total). Baseline margin0 MUST reproduce original exterior painted alpha in BOTH sampled phases, otherwise STOP as not a reproducible dynamic A/B rather than infer candidate success from a failed baseline. Record per-case/per-phase boolean exterior alpha, categorical only; even when inset1 reports NO in all eight sampled images it does NOT prove no alpha across continuous spring extrema or native compositor clipping/pointer input, nor prove unchanged connection to desktop edge/panel or all edges/scales. Do NOT edit production as a result of this one static candidate.

### BOTTOM dynamic original full margin0 versus private margin1 candidate — strict dual-phase control source-staged

Following the actual owner-qualified clean `dev` BOTTOM×1.5 original-full **FROZEN** cradle inset experiment at `SOURCE_SHA=8fb4d2ebb7453030562b6906621c594cbfdaa330` (baseline margin0 actual thresholded exterior YES; candidate margin1/2/3 NO; minimum AMONG TRIED=1), the next strictly scoped REAL spring candidate comparison is now SOURCE STAGED ONLY; it has NOT YET passed its new fake-only owner test and has NOT YET run actual Qt.

- New pure `scripts/wull-private-dynamic-bottom-inset-model.py` blob `834dc0e861bf2b06821a3f4399833201841e7d0e`, commit `880b2b18ef50c5d046200a7e0f3eff355b6b6811`. Reuses prior original owner-qualified bounded RGBA8 alpha parser / same fixed BOTTOM×1.5 center-scaled host rectangle `(72,75.5,168,147)`, 2px canvas-edge crop reject, >=8 original interior painted pixels, exactly 8 samples for each phase of both cohorts (32 exact ordered actual images). Unlike previous full-composite-only model, validates same-session original `M0_150` unmodified original cradle margin0 exterior YES in BOTH observed stretch AND release phase; absent either baseline positive it FAILS CLOSED as `ORIGINAL_DYNAMIC_BASELINE_NOT_REPRODUCED` instead of crediting candidate `M1_150` negative. Returns only four categorical sampled phase booleans, no extrapolation to all continuous spring phases.
- New original-QML source-pinned fixture `scripts/wull-fixtures/paint-moving-bottom-inset/shell.qml` blob `26133a295433f7f61ce64f94a2ece3d14015a57b`, commit `71ec11039d8a4888539a8790a1397ab9489009c1`: EXACT TWO unchanged original `AbyssCompanion` source instances (both BOTTOM×1.5) in TWO owned offscreen private 320×300 transparent windows in ONE Qt0.3.1 process. Cohort `M0` original cradle anchor margin0 remains immutable baseline; cohort `M1` starts as same original cradle, ONLY the disposable instance gets `anchors.bottomMargin=1` after uniquely reviewing original body+external cradle and initial zero-margin state. At EACH independent 40ms original stateStretch+mappable body-corner observer sample AND EACH real grabbed image, asserts all 5 original body visuals visible (no core isolation), exactly two original host direct children, original cradle width58,height10, original margin0 vs margin1 and actual mapped cradle rect x112.5→199.5 and y207.5/206→222.5/221 (Qt scale1.5). Preserves exact previously owner-PASS 40ms independent >=4 spring/mapped/intermediate original motion witness and actual stretch/release endpoint tests for BOTH. Eight original FULL transparent RGBA8 sequential owned-image exposures per cohort per authored spring phase, same Qt process but NOT simultaneous or per-pixel synchronized; 39 fixed staged labels including `CRADLE_MARGIN_PAIR_VERIFIED`, 38s private Qt fixture abort.
- New owner-only `scripts/wull-manual-private-moving-bottom-inset.py` FINAL blob `d58e8c4720573de94e0992f35d3a2b6e4dd65a7e`, updated commit `c58b11ef189133d2267ad8a03c5d137f865092fb`, borrows prior owner-PASS immutable exact original QML full-composite dynamic private guard and source pins, clean owner-owned mode0700 current remote `dev`, private offscreen XDG/D-Bus/Quickshell0.3.1, single bounded 48s owned Qt child process group kill/reap, inherited child file cap8MiB, owner-only <=256KiB private log, EXACT 32 mode0600 <=1MiB captured PNGs, immutable postrun source and strict exact 39 stage markers. Reports only baseline+candidate original sampled categorical exterior flags, or explicitly `GATE=MOVING_BASELINE_NOT_REPRODUCED` if either original M0 dynamic phase fails to establish actual exterior painted alpha despite verified original springs and 32 valid PNGs, or fixed categorized source/QML errors. No raw pixel paths, screenshot, Qt logs, Git publication, production `stable`/QML/Region changes.
- New `scripts/test-wull-private-moving-bottom-inset-contract.py` FINAL fake-only blob `3d49bae020ff9f860ae7189a974045167ece74aa`, updated commit `d21aa0d1445572111dd7e21d41dd8f67014af805`. Pins exact new fixture/runner/model and previously proven original guard+alpha decoder, source-strings original two Bottom/zero vs one margin, 40ms exact spring+mapped+intermediate witnesses per phase per cohort, private environment/process/security controls, exact 39 ordered stage markers. Synthetic 32 RGBAlpha8 images exercise original dual-phase positive baseline and candidate zero exterior, absent original release control MUST fail, forged/missing/extra/unsafe/canvas-edge/invalid PNG, fake forged stage/failure and missing per-phase witness. Fake-only source reviewed, not yet OWNER executed, not real Qt acceptance.

NEXT ONE OWNER ACTION: fresh single owner-owned mode0700 remote-current-`dev` shallow disposable clean clone, exact source pin all four newly staged files and original unchanged production QML/private guard/PNG decoder. Run owner-known original `test-wull-private-painted-alpha-model.py` and new moving inset fake-only contract first; ON exact two PASS launch ONE explicitly consented `scripts/wull-manual-private-moving-bottom-inset.py --acknowledge-private-moving-bottom-cradle-inset` actual offscreen original full-composite moving A/B. Return only exact fixed category values/known QML failure+last reviewed stage; STOP and do not loop/retry or modify candidate if failure. Even a candidate m1=NO in 8 samples of both phases and original m0=YES in both is ONLY sampled one-process two-instance candidate evidence, not pixel-synchronous proof or all spring extrema, no side/panel visual connection test, no live compositor clipping/click/hover or production Region change. Later validate all four edges/scales and actual Wayland compositor only after separate approved gates.

### Moving BOTTOM private inset pre-Qt inert failure: derived runner stage ordering fixed

OWNER's first local A/B dynamic-margin attempt at exact clean `SOURCE_SHA=890f998bebd00ba7afae39dd55c98a1b53d6d79b` returned previous bounded RGBA8 `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS` then `INERT_TEST_LINE=132`, `INERT_FAILURE_TYPE=ASSERTION`, `GATE=MOVING_INSET_INERT_FAILED` **BEFORE launching any Qt capture**. This did NOT test dynamic margin0/1 exterior alpha, and earlier owner-qualified STATIC margin0/1/2/3 single-original FULL Qt proof at `8fb4d2ebb7453030562b6906621c594cbfdaa330` remains unchanged: sampled original margin0 YES, margins1/2/3 NO; smallest AMONG tested=1.

Source review identified a real STRICTness defect in the derived NEW moving-inset runner rather than removing the inert test. Original NEW runner `private_stages` accepted ANY nonduplicate marker from the predefined 39-stage set WITHOUT checking correct position. Fake negative calls to `denied` in the new derived test therefore correctly rejected the implementation: a bogus log consisting solely of `WULL_MOVING_INSET_STAGE=RELEASE_START` was accepted despite no prior BOOT, verified cradle pair, neutral motion or stretch samples. Corrected `scripts/wull-manual-private-moving-bottom-inset.py` git blob `9a4e75b444720b2cee4b0c9629db5c59d50dada0`, commit `81adec4bd555e3f0d6e53495697b4aa2b9643bad`, now requires each parsed stage to match EXACT next element of `stages()` ordered prefix, rejects stage after a logged fixed QML failure, and continues to reject duplicate/unrecognized fixed failure tokens. Never weakens source topology, actual 40ms spring/intermediate/mapped pose witnesses, original margin0 BOTH-PHASE positive baseline requirement, fixed 32 original full-scene PNG validation or owner-only private process guards. Updated fake-only `scripts/test-wull-private-moving-bottom-inset-contract.py` blob `e9311f2998b584613386b2e37e7b9175a02ca9a7`, commit `caca3112e22dfafc72372d55312ee91521bb6ad5`, exact-pins corrected runner and **ADDS** explicit missing intermediate stage and stage-after-failure negative tests beyond existing release-only, duplicate and fabricated failure tests. Source-only inspection verifies corrected runner/fixture/model/fake pins and matched literal static assertions, but this new fake contract and REAL moving A/B remain NOT owner-executed since the fix.

NEXT ONE OWNER ACTION: fresh trusted owner-owned mode0700 clean current-`dev` ephemeral clone pin corrected runner/test and unmodified original QML/alpha/guard. Run previous `test-wull-private-painted-alpha-model.py` then corrected `test-wull-private-moving-bottom-inset-contract.py` fake ONLY first. Only when BOTH return exact PASS perform ONE explicitly acknowledged 32-image REAL original full-companion BOTTOM×1.5 margin0 versus private margin1 spring A/B Qt in one offscreen owner session. Fail closed on any source, stage, image, motion or positive control error; preserve sanitized inert failing source line/type and optional synthetic-only failed `Unsafe synthetic state accepted: <fixed code>` if another inert test fails, NEVER dump raw Qt private logs, screenshot bytes, mapped geometry/coordinates or production mask. Even if margin1 sampled NO in BOTH phases with margin0 YES, defer production edits until display connectivity, all edge/scales, Wayland compositor clipping and live pointer-input acceptance are separately verified. No `stable` or original QML changes.

### Owner-qualified same-process moving original BOTTOM×1.5 margin0 vs 1: positive control both phases

OWNER real private offscreen Quickshell0.3.1 at clean `dev SOURCE_SHA=152a82995875aaa29d6445b10cacfeb406fecfc4` returned `WULL_PRIVATE_PAINTED_ALPHA_INERT_PASS`, corrected `WULL_PRIVATE_MOVING_BOTTOM_INSET_INERT_PASS`, `GATE=PRIVATE_MOVING_INSET_CANDIDATE_CLASSIFIED`. Exactly TWO original unchanged-source `AbyssCompanion` full-companion BOTTOM×1.5 instances in ONE owner-private process: original cradle bottomMargin0 M0 *strict positive control* and privately inset original cradle bottomMargin1 M1. Real Qt `QT_DYNAMIC_INSET_FRAMES=32` (8 each cohort×phase), independent 40ms observed real spring stateStretch transition/intermediate and mapped body-corner change EACH cohort×phase, verified exact source-original cradle/host geometry each actual 40ms tick/PNG, and `TWO_INDEPENDENT_SPRINGS_SEQUENTIALLY_CAPTURED=YES`. Observed sampled full-composite exterior paint flags:
- `M0_150_STRETCH_OUTSIDE_HOST=YES`, `M0_150_RELEASE_OUTSIDE_HOST=YES`: original LIVE SAME-SESSION positive control reproduced in BOTH required phases.
- `M1_150_STRETCH_OUTSIDE_HOST=NO`, `M1_150_RELEASE_OUTSIDE_HOST=NO`: on this exact original full-composite two-cohort private scene the 1-original-logical-pixel inward cradle-anchor candidate had NO thresholded exterior pixels in any of eight sampled original Qt frames per active spring phase.
- `SAME_INSTANT_PIXEL_COMPARISON=NOT_TESTED`, `COMPOSITOR_AND_POINTER=UNTESTED`, `PRODUCTION_MASK_CHANGED=NO`. Dual 320×300 private floating windows were exposed SEQUENTIALLY, not synchronously pixel-paired. NO means absence in sampled frames ONLY (does NOT establish continuous animation extrema, other edges/scales, different fractional scales, compositor clipping/input, or native backend production animation). Original QML, full-host production input Region/default-off Wull, native Rust, `stable` remain unchanged.

This is **owner-qualified private BOTTOM×1.5 moving paint reduction candidate evidence** and improves substantially over earlier independent full and core runs and static one-instance margin experiment. It is NOT sufficient to mutate production without separately checking **visual geometry/connection** to the screen-edge panel: moving the original bottom-anchored cradle 1 original host px inward has a plausible visual-seam risk, and any apparent alpha absence could come at the cost of visible disconnection. A private synthetic horizontal panel boundary/contact diagnostic with original alpha on the already source-proven four frozen original margin0/1/2/3 same-instance captures may identify a gap *in that private sampled geometry*; it must not be mislabeled as actual desktop image/compositor/popup appearance acceptance. For a production proposal, also qualify related BOTTOM fractional scales, original full composite animated phases, actual compositor visual clipping, live pointer/input and popup/panel interconnection under real desktop conditions as their own later explicitly approved gates.

### Next original private virtual-panel edge-band gate staged: possible visual gap at BOTTOM×1.5 margin1

Owner-qualified actual independently moving original full-companion BOTTOM×1.5 margin0/1 one-process sampled 32-frame source result (original margin0 exterior YES in BOTH real spring phases and private margin1 exterior NO observed in BOTH) is documented above. This qualifies only a PRIVATE painted-bounds *candidate*, NOT satisfactory visual connectivity to the real bar/desktop edge. Shifting an originally bottom-anchored cradle inward by 1 original host logical Qt px might create a perceived gap even when margin1 removes exterior alpha. Do not patch original QML or production full-host Region until visual continuity and live compositor/pointer checks are separately performed.

New **purely private virtual-panel edge-band diagnostic, SOURCE-STAGED ONLY** reuses the *unchanged* owner-real-PASS static ORIGINAL BOTTOM×1.5 full original instance four-margin one-Qt-session fixture `scripts/wull-fixtures/paint-bottom-inset/shell.qml` blob `45fc03e743d08a996c763c491e0d2b42d22f75ba` via immutable previous runner `scripts/wull-manual-private-bottom-inset.py` blob `75f923b104c8409b3532a809c3ba62cfd5998e03`. No new QML scene, no new source geometry behavior, and all previously owner-real qualified exact clean current-`dev`, original unchanged QML, strict 11-stage Qt source/pose/margin0/1/2/3 geometry checks, private XDG/DBus/offscreen Quickshell0.3.1, owned 0700 clone and exact four mode0600 320×300 RGBA8 captures remain inherited, with source restoration to original margin0 at end.

- New pure `scripts/wull-private-bottom-edge-band-model.py` exact Git blob `dbfb226a4fa5f53154df25a6bd69d90674372a0f`, commit `ba77ee9e529229ccd8d4aa21df439ac3e54cdf2f`: strict bounded old alpha threshold24 + 2px private canvas privacy-edge reject, exact original centered scaled host box `(72,75.5,168,147)`, original FULL interior paint threshold minimum8, math-derived strictly last INSIDE host image row y221 (pixel center221.5 vs host bottom222.5), immediate inner support row y220, central ORIGINAL cradle horizontal ROI x119..192 only. Defines `INNER_EDGE_BAND` when >=3 consecutive x positions are thresholded on BOTH rows; no raw pixel count, colors, geometry or PNG published. Exact original original margin0 exterior positive and margin1 zero-exterior reproduction REQUIRED. Original original margin0 edge band POSITIVE REQUIRED for a meaningful matched-private-scene contact comparison (otherwise FAIL closed with `ORIGINAL_MARGIN0_EDGE_BAND_CONTACT_UNESTABLISHED`). Evaluates all 4 original FULL margin0/1/2/3 image row-contact flags, explicit `M1_POTENTIAL_PIXEL_BAND_GAP_SIGNAL=YES` when baseline has 3px boundary contact but candidate does not. Note: this signal is only private FULL-composite raster contact near an ABSTRACT mathematical host/panel boundary, not source-specific cradle isolation, real panel pixels, visual taste, desktop edge appearance, actual compositing/antialias under Wayland or click routing. M1 band-contact YES only weakens one suspected gap signature, does NOT qualify actual product visual connection.
- New guarded source-pinned `scripts/wull-manual-private-bottom-edge-band.py` Git blob `a629324e7107882475dcf4cedbff208945c7eddf`, commit `fa001c233e82e6d59909cb8130eac8ada411a4f0`: recursively reuses the exact previously owner-real-PASS source-pinned `wull-manual-private-bottom-inset.py` private actual Qt runner once and the SAME four owned/private actual PNG captures (does not alter runner or QML), verifies old original margin0 exterior YES + new candidate margin1 exterior NO on SAME source/session, loads original alpha parser and four securely owned <=1MiB mode0600 private PNGs, executes only extra pure raster edge-band classifier, checks immutable exact current `dev` clean source after Qt. Prints only 4 boolean edge-band observations, one categorical potential gap signal, explicit `REAL_PANEL_VISUAL_CONNECTION=UNTESTED`, and fixed safety/provenance markers. Any old fixture failure becomes fixed `REUSED_ORIGINAL_PRIVATE_QT_UNQUALIFIED`, new baseline/contact failure fixed `EDGE_BAND_ALPHA_INCONCLUSIVE`; NO raw owner-private Qt logs/screenshots/pixels/paths are printed.
- New `scripts/test-wull-private-bottom-edge-band-contract.py` fake-only exact Git blob `a52e3de94240e1daee89fc2835cb8b316267da34`, commit `d604f9a01e617b1ea75505007f7c162ee8310fb4`: immutable new+old source+fixture alpha pins, original immutable stage/QML and old owner-only private dependency delegation, source geometry row math, synthetic fixed alpha positive original and candidate absent vs candidate positive, exact original margin0 missing exterior/contact and margin1 exterior regression failures, corrupt/truncated/canvas-border/transparent original negative tests, spoofed extra/untrusted 0644/invalid 0600 private FAKE PNG file tests. Source-only string and blob review matched at staging but **new fake-only test and actual edge-band private Qt have NOT YET been owner-executed**.

NEXT owner action: one disposable owner-only exact source-pinned clean current-`dev` 0700 clone, old owner-PASS RGBA8 FAKE and new edge-band FAKE before exactly one explicit `scripts/wull-manual-private-bottom-edge-band.py --acknowledge-private-original-bottom-edge-band` private STATIC original Qt four-image replay. Report only safe categorical result or fixed failure; no raw real screenshots/paths/Qt logs. If M1 edge-band NO, flag likely raster seam and investigate alternate connection-preserving shapes/alpha and actual desktop/panel visual test; if M1 edge-band YES, still require a separate actual live Wayland panel visual connection/real input and further all-edges/scales testing before any original production change. `stable` untouched.
