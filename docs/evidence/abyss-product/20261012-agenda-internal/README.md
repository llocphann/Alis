# AGENDA-F01 — durable one-way linking

Core source belongs to Alis dev. Optional Obsidian implementation is committed
and pushed on Alis-Intergration main at
`4d0aa3f508fdd6bd953696d92bf529f1fb9f4b32`, package0.2.2. Source hashes here
pin the host bytes; the integration bridge pins the worker/backend code hashes.
These are focused results, not a full exact-SHA canonical or owner deployment.

New local Events get one versioned opaque key. Only acknowledged saved events
cause task writes; only actual task acknowledgements complete links. Provider
and daily source date are saved before task mutation. Idempotent retries/crash
recovery preserve independent completion/notes. Event unlink/removal keeps the
task; an explicit task removal first saves a durable detached/delete intent.
Malformed Agenda is not an empty list. Existing historical events and imported
ICS stay untouched; recurrence projections create no tasks or false badges.

Final-source focused evidence:

- `final-source/`: 8 headless processes,24checks, actual JSON readbacks;
  create/Todo-only/historical absence, restart between stores, owned-field
  edit, task deletion, event deletion preserving task, denied task/event writes,
  recovery and unavailable optional backend.
- `bootstrap/`: 3 real processes, service-only creation (no Todo UI), durable
  delete-outbox restart and corrupt Agenda retaining actual task bytes.
- `internal-regression/`: unchanged persistence oracle PASS6/77checks,
  6 disk readbacks, including TXT mirror metadata preservation.
- `events-regression/`: original durable-store assertions PASS6/59checks;
  extra acknowledgements reflect new linking. Earlier prerequisite45checks
  applies to its older source, not this implementation.
- `../20261012-agenda-obsidian/final-source/`: 16 real host-adapter/package-QML/
  Python-worker processes,48checks, both note modes, actual note and Event
  bytes at every restart; no note rewrite on already-linked restart; native
  checkbox/external inline notes survive event edit; unlink/delete deterministic.
- `../20261012-agenda-ui/link-controls/`:28checks/8 native captures, shared
  actual stores across EventCard, Calendar row, Weekly Planner and DashTodo.
  Pending Retry via Enter, pointer Unlink without Edit click-through, task
  completion, projected recurring/external events, two font scales/theme-mode
  property toggles, narrow-card target bounds and compositor allocation.

Earlier failures/diagnostics remain recorded. A queued no-op Event save could
strand linking; reconciliation now wakes when that write lease drains. An
optional worker QVariant task sequence cleared the visible task model despite
correct files; typed JSON transport retains it. Native UI initially lacked a
loaded Todo pane, then Enter propagated through the Retry button; pane setup
was corrected and production link controls now consume Enter/Return. The old
fixed-size UI fixture extended beyond compositor allocation; the final fixture
fits the actual native window. None of these failures are erased or attributed
to a PASS of frozen f94de0535.

Pure policy142 and English catalog/source parity5654 PASS. Optional helper9
methods and private package installer PASS are retained in Integration evidence.
No personal vault/preferences, installed package, actor activation or hardware
profile was changed. Full fresh exact-SHA qualification, older API/source switch/
midnight, installed identity, physical/multi-output and owner acceptance OPEN.
