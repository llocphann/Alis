# POP-I01: first native protocol diagnostic, 2026-10-12

**Diagnostic only. No product patch, no claim that POP-I01 is fixed.**
Source `cfc852beef19d33de51f84520cf3eb26d9b485af`. One private nested Niri
output; real virtual-pointer protocol absolute motion reaches Quickshell's
native pointer path. No explicit parent focus, screenshots, button/key input,
owner install or preference changes. Test processes were cleaned up.

Scope: Clock on Top, animations reduced, source -> middle connection -> body
-> outside, one-second dwell per point. Source sets anchor hover and opens one
slot; connection/body report content hover and retain requested visibility;
outside clears all slots. This case did NOT reproduce the owner's failure.
Capability receipt is earlier manager binding only; source.json's NOT YET RUN
status is the immutable pre-run build receipt, superseded by pointer-trace.json
for this diagnostic only. Trace records actual snapshots, not synthetic QML
hover setters. This is not physical owner pointer or all-family acceptance.

Prototype client/probe and protocol XML are preserved. XML retains its upstream
MIT license and source URL/hash. Generated bindings/binary remain local under
.git/maintainer-validation/pop-native. The prototype assumes the parent was
wayland-1; before reuse, validate the current parent/private displays and do
not permit owner-display injection. Build bindings with wayland-scanner
client-header/private-code from pointer.xml; compile client.c + generated
pointer.c using pkg-config wayland-client. probe.py expects the prototype files
under the local .git directory and imports scripts/native_test_session.py.

NEXT: expand this collector to all four edges and relevant generic/StyledPopup
families (Weather, launcher, notifications), actual animations, auto-hide,
stationary body dwell, fast reversal and leave. Correlate real pointer events,
input mask/paint and requested/anchor/content lifetime BEFORE changing product
code. Preserve the two owner-rejected approaches; do not reapply them or infer
all-family correctness from this successful Clock case. Keep POP-I01 open.
