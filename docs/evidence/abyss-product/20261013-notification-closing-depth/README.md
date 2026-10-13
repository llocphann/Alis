# Notification banner closing dimensions

Runtime source: `55570d8b806c6f687dbf1698f10147a42b36ab59`. Probe diagnostics were introduced in `7c1906e66fe915cfd7adfac5f17c4b9c1235384f`.

Opening Notification Center empties the popup list. Previously that immediately zeroed the measured height while the banner remained resident for its closing animation. The production host fell back from119px to100px at progress1 before retracting. The fix retains only the last settled measurement for that existing visual residency. Read state, timeout, reveal readiness and destruction remain unchanged. After destruction a fresh single notification measures100px again.

## Evidence and provenance

The paired local GPU/private Niri probes use actual wl_pointer and isolated D-Bus synthetic notifications. The before probe is7c1906e66; the after probe uses that HEAD plus the content fix in its worktree. Its original driver failed to record dirty state, so its source_sha field is not exact-source provenance. Both are retained as diagnosis; they establish the observed119-to100 snap and its removal, not a CPU/GPU or frame-rate improvement.

The committed fixture on a clean55570d8b8 clone passes9 native geometry/lifecycle checks. The same fixture against a clean7c1906e66 clone fails on the specific closing target-depth assertion. Transition policy46 and collector/probe contract22 also pass at55570. A separate Weather/Clock handoff focused fixture passes1155 checks on the same source; physical-pointer, installed desktop, rapid visual/Pyramid and multi-output acceptance are separate.

The first fixture failure is preserved: it sampled before the existing75ms measurement commit. The revised fixture explicitly waits for the grouped taller measurement before examining close. No product readiness timeout or animation was weakened.

No actual recording encoder, owner audio, or personal notification was captured. Notification-start/saved strings are synthetic presentation events. Idle swap gaps in the diagnostic are not active animation frame drops. Full canonical55570 is not run; the existing broader generic-hover failure from the earlier Round0 qualification remains independent. No whole-task completion or resource percentage is claimed.
