# ABYSS-R03 + R01 — drag tracking and corner clearance

Implementation complete; Owner chưa verified. Focused source candidate only;
current exact-SHA canonical and installed-owner acceptance remain separate.

The pointer grab offset is retained in full-component coordinates across ±90°
orientation; a small edge hysteresis avoids corner ties. The primary/group
follows its computed constrained position without a tween. Only unlocked
neighbors animate, respecting reduced-motion preferences. Field surfaces,
editor handles and compositor input regions follow actual displayed geometry.
Locking captures the displayed anchor. Measurements coalesce outside the
binding evaluation, fixing startup layout reentrancy discovered by native tests.

Corner content clearance is a 4–12px token derived from existing curvature/type
scale. Only perpendicular controls that would collide allocate additional
space. Decorative corner joins bridge the gap without expanding controls or
hot-corner input. Absolute normalized centers survive save/reopen. Locks reject
infeasible bounds rather than moving. Groups fit one contiguous free band,
retaining internal offsets and outsider placement/lock intents.

| Focused evidence | Result |
| --- | --- |
| Grab/corner geometry | PASS 729 |
| Lock/pin policy | PASS 7166 |
| Multi-selection policy | PASS 1482 |
| Full-design policy | PASS 3772 |
| Updated endpoint/snap/layout tests | PASS |
| Native Qt pointer drag | PASS 78 checks / 17 frames / 4 PNG |
| Native multi-selection and JSON restart | PASS 55 checks / 13 frames / 2 processes |
| Native locks and JSON restart | PASS 62 checks / 26 frames / 2 processes |

The final pointer test exercises actual Qt mouse press/move/release on the
editor handle, off-center grab, 12 samples with zero primary target error,
intermediate neighbor positions, immutable pins, reduced motion, corner bounds,
Done/reopen and Cancel. Its roughly 53–62ms capture sampling is dominated by
explicit grabToImage/waits, **not** measured physical pointer latency, frame
budget or a performance gain. Earlier startup binding-loop, unnormalized fixture
and blocked group-transfer failures remain retained. No original oracle was
silently relabeled PASS. Real wl_pointer, matched owner before/after motion,
fractional/multi-output and final canonical gates remain pending. Private capture
focus is requested only for images; other regression windows do not focus.
