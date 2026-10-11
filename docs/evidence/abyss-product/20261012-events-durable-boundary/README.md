# Acknowledged Agenda boundary — 2026-10-12

First `AGENDA-F01` prerequisite: canonical Events now provides `eventsPersisted`
and `getDurableEvents()` from the exact completed write snapshot. Consumers get
clones and cannot mutate the saved source. `eventAdded` remains an immediate
in-memory notification, never proof of persistence. No automatic Todo creation,
link metadata/backfill, vault write or second backend is added by this milestone.

Save failure keeps pending edits in memory with error/busy feedback and emits
no durability notification. Refresh defers while writes are pending. No-op
decisions use acknowledged bytes; a failed optimistic cache can retry through
an actual fresh write-only FileView. Existing save/recovery paths remain bounded.

Actual headless/private-XDG/D-Bus Quickshell PASS **6 startup/restart processes,
45 QML checks, 6 independent JSON readbacks, exit 0**. Rapid add/update saves
prove the first acknowledgement contains the first snapshot and the later one
the coalesced edits. Real private-file chmod denial proves no phantom event is
published and explicit retry retains all edits. A separate cached-byte fault
injection exercises the actual fresh writer and one acknowledgement. Every
case restarts and reads the real private JSON. No owner data or GUI is used.

Next `AGENDA-F01` work: define a versioned stable occurrence link; create exactly
one task only for an acknowledged eligible local event still present in the
current canonical list. Persist/reconcile task identity across both stores and
restart; preserve independently edited task notes/completion; define safe
delete/unlink behavior, user-selected internal/optional Obsidian mutation and
pending-link UI. Historical backfill stays opt-in and imports never generate
tasks. This boundary alone does **not** complete that feature.

`receipt.json` pins the focused bytes. Running full canonical `f94de0535` has
the preceding Events implementation and cannot qualify this new source. Final
committed-source canonical and installed/owner acceptance remain OPEN.
