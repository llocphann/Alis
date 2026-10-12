# AGENDA-F01 — Retired feature (owner direction, 2026-10-13)

**Status:** Withdrawn from active New Features; do not mark Owner verified or reuse this stable task code.
**Reason:** Owner explicitly removed automatic Agenda → To-do linking. Agenda and To-do are now independent. Historical per-event `todoLink` and stored `todoUnlinks` should be preserved without mutating a user's saved events/tasks; live linking/reconciliation must remain disabled.
**Follow-up:** Audit any remaining unused UI/policy, obsolete tests, disabled APIs, integration provider and stale docs independently; do not reintroduce automatic linking. Archive keeps the original task history and evidence references.

## Original task entry (historical, superseded)

- [x] **AGENDA-F01 — Creating an Agenda automatically creates one linked To-do (not vice versa) — owner request 2026-10-11:**
  [Owner: Alis dev; New Feature] **Local Agenda/Event creation
  ⇒ exactly one corresponding Todo item**, automatically after
  durable event creation. **Independent Todo creation ⇒ no Agenda**,
  no calendar reservation, no implied reminder. The linked task
  shares sensible title/date/time/details but keeps its own
  completed/pending state; completing Todo must NOT cancel the
  scheduled Agenda or vice versa. Show a clear linked relationship
  across Calendar Popup, Dashboard Agenda/Todo and Weekly Planner,
  without rendering the same event twice or sending duplicate alarms.

  Data design must live at the canonical `services/Events.qml`
  + `services/Todo.qml` mutation/adapter boundary, not in
  separate popup forms. Events persist numeric IDs and Todo
  can use internal JSON/txt or opt-in Obsidian Markdown backend;
  specify stable event→task ID / occurrence link schema,
  versioned migration, idempotent reconciliation on failed/
  delayed writes, retries and process restart. **CAL-I01**
  separately tracks Event disk persistence: do not create
  phantom Todos from events that were not durably saved.
  If Todo is not ready/busy/unsupported, show a pending-link
  warning and bounded safe retry, not silent loss or creation
  of duplicates. Respect user-chosen Obsidian backend/privacy,
  permissions and existing external Markdown task edits.

  Define owned-field sync for title/date/time changes while
  preserving independent Todo notes and completion; explicit
  non-destructive delete/unlink policy and safe recurrence
  semantics (one item per eligible created occurrence, no
  runaway duplication). Existing historical Agenda/Todo data
  preserved; any backfill must be opt-in and previewable.
  Imported external `CalendarSync`/ICS events are read-only
  and should NOT auto-generate tasks merely due to sync.

  Acceptance: create via Calendar Popup, Dashboard and Planner
  yields one linked Todo; Todo-only creates none; edit/delete,
  recurrence, completion, repeated save/retry, crash between
  stores, cancel/undo, internal vs Obsidian and package absent,
  restart and cross-surface updates are deterministic and
  preserve user files. Add source/fixture and owner native QA.
  State: SOURCE IMPLEMENTED / focused PASS — 2026-10-12, after
  `DASH-F01`/`DASH-F02` source milestones. Versioned per-created-occurrence
  keys and a durable unlink/delete outbox live in Events; Todo consumes actual
  event/task acknowledgements. Provider/source-date are pinned before mutation;
  no historical/imported-event backfill, inverse Todo→Agenda or task resurrection.
  Title/date/time/details update while task completion/notes remain independent.
  Event deletion/unlink retains task; explicit task deletion detaches durably
  first. Pending feedback and three bounded optional-worker retries replace
  indefinite polling; explicit retry restores failed actual writes.
  Shared Calendar/Planner/Dashboard relationship UI includes Retry/Unlink with
  Enter/Space/pointer control; virtual recurrence projection carries no false
  saved-task badge. Optional workers belong to Alis-Intergration main
  `4d0aa3f508fdd6bd953696d92bf529f1fb9f4b32` (package0.2.2), without owner install.
  Focused PASS: pure142; internal8 processes/24checks; Events-only bootstrap3
  actual processes/disk readbacks; internal persistence6/77 and Events6/59;
  optional bridge16 processes/48checks across both note modes; UI28checks/
  8captures with actual shared stores and private compositor allocation.
  [Source hashes, raw failures/fix-forwards, readbacks and acceptance limits](../../docs/evidence/abyss-product/20261012-agenda-internal/README.md).
  First data prerequisite: Events exposes only acknowledged, cloned durable
  snapshots and save failure/busy feedback; Agenda→Todo must consume that
  boundary, never `eventAdded` or an optimistic FileView cache. Actual headless
  PASS6 startup/restart processes, 45 QML checks and 6 independent JSON
  readbacks: coalescing, deferred refresh, denied save, explicit/cached retry
  and no phantom acknowledgements. [Pinned prerequisite evidence](../../docs/evidence/abyss-product/20261012-events-durable-boundary/README.md).
  Stopped canonical `f94de0535` predates this feature. Fresh committed exact-SHA
  full qualification, source-switch/midnight and older-package retry cases,
  installed identity, owner Calendar/Dashboard/Planner creation and actual
  external-vault acceptance remain OPEN. Continue ABYSS-F01 while preserving
  these gates; source/focused evidence alone does not complete the feature.
  **Completion classification (2026-10-12, maintainer rule): Hoàn thành (bot báo xong) — Owner chưa verified.** The reported implementation/fix is counted as done; existing exact-SHA canonical, environment, installed, hardware and owner acceptance gates retain their real PASS/FAIL/SKIP or pending state. This notation does not claim a fresh validation PASS.
