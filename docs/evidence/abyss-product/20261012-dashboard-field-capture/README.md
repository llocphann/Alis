# Dashboard field and slide: capture-enabled focused qualification

Parent Alise73252359, source bytes pinned in source-sha256.json. Product source
DashboardHeader0becc72ab is unchanged in this qualification. The earlier
unfocused full-field FAIL remains retained: the grab returned1881ms after
animation progressed0->1 in309ms and missed its original partial interval.

Explicit ALIS_DASHBOARD_FIELD_CAPTURE_DIR requests image verification. Only
that invocation opts into capture focus. The shared private-Niri helper remains
unfocused by default for all other callers; it identifies its own parent window
by the private process PID, records the previous target, and restores it only
while its own window still has focus. A user's intervening focus choice or
closed previous target is preserved. Five simulated protocol checks PASS.
Actual parent before/after both window488; private capture target665,PID1055547.
Owner shell/preferences were not reloaded or changed.

Actual QV4/private-Niri/OpenGL PASS16 composed Dashboard/Overview routes,
4edges,2field sizes,211 real slide/reversal samples,48 bounded saved PNGs,
exit0. Original dimension, placement, Add/Undo/Cancel/Done/input, monotonic
motion, partial [.20,.85), full-size/no-fade/no-scale, reverse retention,
reduced-motion and frame/deadline/workload assertions remain unchanged.
The opt-in capture stores at most3 intermediate images per case. Four first-
size edge frames1/5/8/11 were visually inspected: actual clipped reveal images
are retained, including blue/black fixture field appearance. These images are
NOT owner palette/material visual parity, installed desktop or multi-output
acceptance. Physical pointer/normal Popups and those product gates stay OPEN.

This PASS demonstrates the composed field route and the dimension fix under a
renderable capture state. It does not erase frozen0465FAIL359/7/1 or frozen593
STOPPED318completed311/7/0, qualify newer full canonical, or diagnose the separate
standalone Dashboard toolbar footprint, Recording, Settings, hover or IPC failures.
No resource percentage is inferred from native frame/capture timing.
