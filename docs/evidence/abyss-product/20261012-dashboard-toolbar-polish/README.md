# Standalone Dashboard toolbar: bounded rendering diagnosis

Runtime code from6538e165c; subsequently fast-forwarded cowork task/status-only
b91a20211/da68922e3. Source bytes pinned here. No product or primary fixture
change is made by this diagnostic. Frozen593 STOPPED remains318completed
311PASS/7FAIL/0SKIP; its separate toolbar footprint119,-376,782,395 overlaps the
canvas by19px. This captured ancestor failure is not relabeled as PASS.

One initial private, unfocused probe cannot grab the special QQuickWindow root
item (DASHBOARD_EDIT_FAIL toolbar frame refused); retained under diagnostic/.
The follow-up inserts a full-size visual Item with the same allocated906x1070
viewport and waits for its one actual frame before the original step5 assertions.
No numeric bounds, workspace/Add/resize/hide/restore/packing oracles change.
Rendered probe PASS both Dashboard and Overview hosts, expected timeout124
owns cleanup after success,2 saved images, no explicit parent focus requested.
Before and after render in BOTH hosts: toolbar782x115, y=-129 relative to body
content,14px gap. The old395px footprint was NOT reproduced in these probes.
This is focused positive evidence, not proof of the old failure's cause or a
primary full-script/canonical PASS. Do not patch runtime based on this alone.

Source-native/owner field appearance, direct pointer, installed identity and
multi-output acceptance remain separate. Raw originals stay locally under
.git/maintainer-validation/dashboard-toolbar-polish-raw with their SHA256;
public copies only redact Weather location lines, preserving test failures and
geometry. Raw G0 was not used, modified or replayed.

A final bounded check executes the EXACT original QML producer bytes,
without the added scene/frame probe, and passes both hosts under private,
unfocused Niri (expected timeout124 after success, no runtime errors).
This closes the current source/focused Dashboard control milestone alongside
the composed16-case/211motion/48PNG capture result. It does not identify the
ancestor395px failure cause or convert that frozen failure/full canonical.

Latest owner priority now selects ABYSS-R05 -> R03/R01 -> R02 -> R06/R07,
then STOP. Weekly Planner inline Events remains unfinished/deferred; preserve
this standalone canonical failure for later exact-source qualification.
