# ABYSS-F01 — immutable position reservations

Source implementation belongs to Alis dev. The appended source-hashes pin
working bytes qualified by these focused tests; no full exact-SHA result for
this milestone or owner installation/acceptance is implied.

Locking captures the displayed center normalized by that output's edge length
and its current compression ratio. Requested alignment/position remain intact;
locked geometry no longer depends on later aligned-group packing. There is no
absolute pixel promise across output resolution or font/width changes. Feasible
neighbor edits keep locked along/span exactly. A bounded ordered interval solver
packs only unlocked groups between reservations, retaining the existing minimum
compression floor. Preferred gap yields to already approved locked spacing.

Infeasible moves/additions are rejected with feedback. A mathematically invalid
output/font/width emits visible conflict and deterministic ordinary packing
instead of overlapping controls. Saved lock flags/anchors stay untouched, return
to the previous output restores them, and editor Done refuses this fallback.
Normal Popup operations are not locked. Per-output/global maps keep other
profiles, disabled/zero-span records, custom size and corner preferences.

Focus results:

- Pure/property7044 PASS: four edges/three sizes/four alignments, neighbor moves,
  insertion/deletion/resize/edge crossing, full edge rejection, output shrink,
  hidden/zero-width modules and actual profile round trip. 180 deterministic
  generated layouts verify immutable reservations, bounded/nonoverlapping
  controls. 192 cases compare unlocked paint/input geometry against committed
  pre-feature0465ffc5a code; no CPU/RAM/GPU percentage measurement is claimed.
- `adaptive-grid/`: actual QV4/private-Niri62checks across2processes and
  26foreground-only captures. Pointer/keyboard lock, denied drag, neighbor snap/
  resize, mature module identity, explicit Unlock, Undo size/Reset, Cancel,
  output-only/global saves, independent FileView/disk readbacks, actual process
  restart and refused concurrent Done after Undo Reset.
- `editor-grid-fix/raw.log`: unchanged existing native editor click/input oracle
  PASS, including all four edges, small-output scrolling, module identity,
  Popup/IPC draft, Cancel/save and preservation of another output.
- Existing placement policy, four editor contracts and two parser probes PASS.

Failures are retained. `initial/` assumed scale1.8 always made a lock infeasible;
the revised fixture anchors at Start so its resize conflict is deterministic.
`anchored-fixture/` found real global save failure assigning Qt read-only
objectNameChanged after per-output save/Undo. Edge adapters now copy only four
owned values instead of QObject signal members. `edge-map-fix/` and final-source
retain that fix-forward and later concurrency-guard qualification.
`editor-diagnostic/raw.log` then exposes real horizontal target overflow:
corner x625+189 exceeds794px clip. Adaptive selected controls repair the grid;
the existing clip assertions and pointer actions stay unchanged.

These are synthetic Qt input and foreground geometry captures. Full Abyss
perimeter/material rendering, actual wl_pointer/owner Popup behavior, installed
identity, multi-output/hotplug and fresh committed canonical remain OPEN.
The concurrent frozen full canonical is0465ffc5a, which predates all locks.
