# R03: native source-input ownership during layout editing

**Partial repair; ABYSS-R03 and POP-I01 remain OPEN.** Base `05ad9ccc2` plus
source-variant.json's exact pending bytes; separate receipt classification is
focused, not full canonical or installed/owner verification.

Real virtual-pointer protocol input against the production critical host,
using a private copy of the owner's 12-module layout, observes source module
`enabled=false` during Edit, while its mature feature / HoverHandler still
reports source hover and keeps Resources popup requested. The original run
r03-native-window records 91 sent motion commands, 11 observed MouseArea
notifications and 16 frameSwapped samples, including long intervals. These
samples are private-session observations, not physical input latency,
compositor-present FPS or a matched whole-shell benchmark. The observer maps
MouseArea coordinates after the production handler moves the item; those
mapped points must not be used as physical pointer coordinates.

Repair: source hover eligibility separately checks the real owning module's
visibility/input state, and explicitly disables the source HoverHandler.
Presentation readiness, body hover and explicit opening retain their separate
contracts. Actual editor module handles also keep source priority inside the
body's containment predicate; no native input rectangle or blank-workspace
catcher is added, and no global popup suppression or timer extension occurs.
The candidate protocol run r03-native-source-owner ends without a popup slot.
The final split-readiness protocol run r03-native-pin-split keeps an explicit
Resources request presented while both source hover flags are false; its
start/end source digests match. This does not finish general hover diagnosis
or dense drag tracking/frame pacing.

Focused checks: new native ownership fixture **150 checks / 57 frames** across
four edges, ordinary source/body handoff, stale flag rejection and explicit
requests; NotificationCenter **28 assertions**; cold source contract and cold
mount/remount native PASS; original four-edge body/padding/bridge/shoulder,
interactive content, auto-hide/reentry/focus fixture **PASS when run serially**.
An earlier parallel private-Niri invocation failed the padding probe; retain
its raw FAIL. Concurrent private compositor creation can resize another nested
window, invalidating cached points; no definitive attribution is claimed from
that FAIL. Do not run geometry-sensitive private Niri fixtures concurrently.

Rejected intermediate variants and failed fixture development are retained.
The initial fixture incorrectly expected body presentation to survive an
invalid hoverTarget (existing presentationActive requires _anchorReady).
Final source-input eligibility is separate from that unchanged presentation
condition; the corrected fixture tests normal body ownership and independent
explicit request semantics. The protocol body-retention attempt changed Edit
layout/allocator while retaining the pre-edit pointer point and then failed;
it is NOT a PASS for body retention after reflow. A further current-geometry
protocol check is still needed. Native pin success is a different case.

NEXT: finish R03 native drag/neighbor/reflow and popup cost diagnosis; collect
bounded hot-path timing without interpreting frameSwapped as presented FPS.
Keep original owner video, all-source canonical FAIL/STOPPED and installed/
owner/multi-output gates factual. No CPU/GPU/RAM improvement percentage claimed.
