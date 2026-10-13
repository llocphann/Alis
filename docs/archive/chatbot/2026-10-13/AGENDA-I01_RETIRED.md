# AGENDA-I01 — Retired linked-task defect (2026-10-13)

**Disposition:** obsolete after owner withdrew `AGENDA-F01` (automatic Agenda → To-do syncing); remove from active Issues rather than pretending the removed feature was owner-verified.

The historical issue and its original source/validation failures are preserved unchanged below. The retained Agenda/To-do durability work unrelated to linking continues under its own task codes; no user-owned Agenda or To-do data should be deleted to retire this defect. The old retry button and link reconciliation runtime must not be restored.

## Historical issue entry

- [x] **AGENDA-I01 — Linked task reconciliation and keyboard retry stalls — discovered 2026-10-12:**
  Related `AGENDA-F01`: queued no-op Event save could hold a stale write lease;
  optional QVariant sequence cleared the UI despite correct task files; Enter
  on Retry propagated into EventCard. Source0465ffc5a consumes idle-lease
  notification and Enter/Return locally; Integration4d0aa3f transports typed
  JSON and releases acknowledged job busy state. Original focused failures and
  actual store/QML bridge/UI fix-forward results remain in
  [Agenda evidence](../../docs/evidence/abyss-product/20261012-agenda-internal/README.md).
  State: SOURCE/FOCUSED FIXED; full0465 FAIL359/7/1 on separate fixtures; owner/installed OPEN.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.
