# Screen Edge multi-selection — focused source qualification

Implementation: Alis dev, parent e88417f65. `source-sha256.json` pins the final
working bytes, committed atomically with the feature. No owner installation or
full canonical PASS is implied; latest completed canonical0465 FAIL359/7/1
predates all lock/multi-selection changes.

The explicit editor-only checkbox creates a transient selection set/primary
module. Click adds/preserves; Ctrl-click or Space toggles; Ctrl+A selects every
module on this output; Clear removes the set. Handle glyph/state/count include
locks. The module selector can select disabled/invisible modules. Disable,
Enable, Remove, Lock/Unlock, custom size/size and alignment act atomically on
exact IDs. Stale IDs, mixed locked placement edits and invalid corner batches
reject the whole action. Explicit disable/remove of locked targets is permitted.
Custom size inherits each target's own Edge. Selection state is never persisted.

Same-Edge group drag preserves visible gaps, clamps the whole group and snaps
the group bounds to start/center/end/neighbors. A group can cross Edges while
retaining order and adapting each span to its destination orientation. The
existing production solver validates the complete proposal: blocked/distorted
or infeasible groups reject without moving locks or partial mutation. Mixed-
Edge selection supports batch controls but explicitly rejects dragging as one
row. The source glyph's mature renderer is retained. A gesture snapshots source
records: new destination measurements trigger at most3 coalesced reflows per
pointer event and3 finite release turns; there is no idle polling/timer/worker.
Cancel/Reset/Undo invalidate queued work. 64-step Undo restores exact placements
and target selection. Saved global/output-only placement uses the existing
concurrency guard and four-owned-field map adapter.

Evidence:

- `policy/multi.log`: PASS1588 transaction/property checks, four Edges/three
  viewport sizes, locked/stale batches, hidden targets, cross-Edge custom sizes,
  coherent translations/orientation/gaps, original single-item move equivalence,
  JSON profile roundtrip, another output preserved, full locked Edge and120
  generated layouts (both accepted/rejected groups, bounds, overlaps, anchors).
- `policy/locks.log`: PASS7044 lock/no-lock invariants, including192 pre-feature
  paint/input geometry comparisons, on final source bytes.
- `final/`: actual QV4/private-Niri55checks over2processes,13foreground captures,
  pointer checkbox/add/Ctrl-toggle/group drag through4Edges, unchanged gap/order,
  Space/Enter/Ctrl+A/Ctrl+Z, lock guards, cross-Edge batch size, Disable/Enable,
  Remove/Undo, Clear/Reset/Undo, pending reflow canceled by Reset/Cancel,
  actual global/output-only JSON readback and process restart. Other output and
  saved global baseline are preserved. Selection does not survive restart.
- Existing placement test, adaptive toolbar/relocation contracts and parser
  PASS on final source. `editor-regression.log` preserves the existing native
  four-Edge/small-output/full-click bounds proof before the final queue guards.
  `locks-regression/` preserves62 native checks/26foreground captures before
  the later group-only queue guards.

Failures remain intact. `initial/` supplied ControlModifier in QtTest's *button*
argument; corrected explicit LeftButton+ControlModifier passes actual toggling.
`gap-oracle/` records the real orientation bug: after the first group move the
mature clock changed span, which changed the visible gap after release. No oracle
was weakened. Origin geometry snapshots, bounded reflow and final release
settling pass the same gap assertions in `orientation-reflow/`, `bounded-final/`
and the final queued-cancellation fixture. Earlier successes are scoped; final
source hashes apply to `final/` only.

Images are foreground-only QML geometry/control evidence (software backend).
They do not include the complete Abyss perimeter/material painter or prove
light-palette/material fidelity. Actual wl_pointer/owner input, installed
identity, normal Popup actions, hotplug/multi-output, full material and fresh
committed-SHA canonical gates remain OPEN. No resource percentage is claimed.
