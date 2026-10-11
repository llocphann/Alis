# Hidden Dashboard actions must not resize widget canvas

Source: Alis dev, working bytes pinned in source-sha256.json. Canonical0465
FAIL remains immutable; the currently running frozen593368c15 predates this fix.

The preserved0465 ancestor trace keeps body content932.8×590 throughout Edit
but the header/column implicit height changes44→50, canvas933×546→933×540.
The field fixture explicitly uses showHeader=false; page dots stay visible
with Planner/Music, while actions are hidden. After a child toggle the hidden
RowLayout still reports38px, changing Math.max(32,actions.implicitHeight).
The header now reads action height only when showActions is true.

standard-budget: actual QV4/private-Niri PASS36 checks/30 rendered frames,
12 saved header-only images, three allocated widths900/600/300, both power-
action visibility values, Edit/Cancel, show/hide actions and exact canvas/header
height restoration. Original runtime dimensions assertions remain unchanged.
The new dimensions fixture's process budget follows the existing editor45s;
its initial arbitrary30s timeout is preserved (12 images saved, no final PASS).
This budget is not an animation/frame-time performance oracle.

native.log preserves the original full-field fix-forward result: FAIL in its
slide probe. The first Dashboard/top1280×900 case reaches the slide phase after
the original dimensions/Add/Undo/Cancel/Done assertions; reveal signals progress
0→1 over309ms, while grab returns after1881ms and cannot observe the requested
partial interval. This is a separate capture/sampling limitation, not a full
field PASS. No sampling range, deadline or workload was weakened or replayed
from consumed G0. Full original field/slide qualification under a suitable
native capture state, installed/owner, material and multi-output gates stay OPEN.
No resource percentage is claimed.
