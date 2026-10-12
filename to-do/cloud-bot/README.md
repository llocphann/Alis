# Shared Local and Cloud AI task policy

Work directly on `dev` in one agent context. Refetch before audits, writes and
ref updates, preserve concurrent work, and push atomic milestones.

This policy is mandatory for **Local and Cloud development AI**. The folder name
is historical; both environments read/write the same three lists through
[to-do/README.md](../README.md). Apply it when receiving a request, starting or
resuming work, and finishing a milestone. Execution location does not change
classification, priority or acceptance requirements.

**Maintainer priority, effective 2026-10-12:** continue the current work;
prioritize New features, with related Rework/optimization and Issues/bugs
handled alongside the selected feature. The three categories still classify
outcomes; their position is not an instruction to finish every Issue first.
"Alongside" means coordinated work in this single-agent context, not separate
agents or task boards.

**Maintainer scheduling override (2026-10-12, authoritative 27-item
New Features numbering in NEW_FEATURES.md):**
- **Owner verified / completed:** #13 (Power-profile render quality)
  and #24–27 (Integration TLP/Battery, Thinkfan, Obsidian, package
  lifecycle). Mark those [x] with **Owner verified**, not
  "Owner chưa verified"; this is owner-reported product acceptance,
  not evidence that unrelated canonical/hardware/release tests passed.
- **FINAL-PHASE / DEFERRED:** #1 (Deep Performance Profiler) and
  #14–23 (all AC-F01..AC-F10 Companion features) are postponed
  until **all other non-deferred** actionable New Features, Rework
  and Issues are finished. Do not take their research, source
  implementation or optional integration work as the next task
  just because they are first in the file. Keep consent gates.
- **VERY LAST / DEFERRED:** #12 (Non-Arch optional gateway) should
  be done almost last, **after the final-phase group above** and
  every other outstanding task, unless the maintainer explicitly
  changes priority.
- The **immediate active New Features** are #5 DASH-F01
  Weekly Planner, #9 Quick Notes Markdown, #10 Quick Notes image
  delivery and #11 Utilities delivery. Follow normal impact and
  dependencies for their related Rework/Issues. New incoming work
  remains ahead of all deferred items until completed. This overrides
  generic feature-first sequencing without deleting any tasks.

| Priority | Category | Scope |
| --- | --- | --- |
| First | [New features](NEW_FEATURES.md) | Capabilities that the product does not yet provide, including feature delivery still awaiting acceptance. Follow explicit feature sequences. |
| Alongside the selected feature | [Rework/optimization](REWORK_OPTIMIZATION.md) | Related redesign, UI simplification, CPU/RAM/GPU reduction and responsiveness improvements. |
| Alongside the selected feature | [Issues/bugs](ISSUES.md) | Related broken behavior, regressions, actionable warnings and correctness/release checks. |

## Stable task codes

Every **top-level** checkbox item in the three active Cloud/Local AI task
lists has one stable, globally unique code `DOMAIN-I##` (Issues),
`DOMAIN-R##` (Rework/optimization), or `DOMAIN-F##` (New features).
Keep existing identifiers and historic evidence unchanged. Assign a new,
unused code on intake; merge duplicate reports into the existing coded
item instead of creating another ID. Never renumber when reordering,
changing priority, reopening, completing, owner-verifying or archiving.
Keep severity markers such as `P0` as part of the original title,
not as replacement identifiers. Existing nested `P1–P13` under
`PERF-F01` and `R1–R10` under `BRAND-R01` are scoped substep
labels (e.g. `PERF-F01/P1`); they are not unnumbered top-level tasks.
Cross-reference tasks by their stable codes even if headings change.

## Every incoming request

1. Read the latest instruction and current task lists before implementing.
   Automatically record actionable requests on receipt, even when the maintainer
   does not mention TODO or a category. A plain question/status query needs an
   answer; create/update a task only when it adds work, a defect or a constraint.
2. Classify by the requested outcome: restore broken behavior in Issues/bugs;
   improve existing behavior/design/resources in Rework/optimization; add a
   capability in New features. For example, Music cannot play → Issues; Queue
   animation/layout changes → Rework; adding image support to Notes → New features.
   A bug in an unfinished feature still belongs in Issues, linked to its feature.
3. Split mixed requests into distinct outcomes. Search for matching active items
   and archived history, merge repeats/corrections, and retain the latest scope
   and supplied image/video/log references. Reopen a completed task only when
   new work or a regression is reported; reference its prior evidence.
4. Record the outcome, received/updated date, current state, next action,
   remaining acceptance and useful evidence in the existing category item.
   Use plain inline states such as ready, in progress or waiting for a named
   dependency. Do not append the conversation or create another task ledger.
5. Re-evaluate the selection rules below and act within authorized scope. Do not
   ask the maintainer which category to use or which routine task to do next.

Use concise items describing the required result, current state, remaining
acceptance and a useful evidence/source link. **Maintainer status rule
(2026-10-12): when the bot explicitly reports the entire requested task
finished, mark it [x] "Hoàn thành (bot báo xong) — Owner chưa verified",
even when owner visual/native acceptance is still pending.** A known
completed source implementation is not "unfinished" merely because its
owner has not tested it. Keep evidence gates separate: report exact-SHA
PASS/FAIL/SKIP and installed/owner validation factually; never convert
an unrun or failing test to PASS. Distinguish a completed task from a
completed *milestone* inside an unfinished larger request: do not check
off the whole task if a named requested function or follow-up is still
not implemented. Reopen a completed task only for newly requested
unfinished scope or a demonstrated regression, citing previous evidence.

## Select the next task autonomously

The maintainer's explicit immediate priority, stop or deferral comes first.
**Exclude every FINAL-PHASE / VERY-LAST deferred feature above from autonomous
selection until its prerequisites (all other work) have been satisfied.**
Otherwise select an actionable, unresolved non-deferred New feature, then address
its related Rework and Issues as part of delivering and qualifying that feature:

| Category | Selection within the category |
| --- | --- |
| New features | Follow the maintainer's explicit sequence. Otherwise choose requested capabilities with clear scope and available dependencies; favor broad user value and work that unblocks other requested outcomes. |
| Related Rework/optimization | Work sharing the selected feature's UI, data or input path, or needed for its acceptance; prioritize strict-lossless, evidenced resource/responsiveness gains. Preserve the audit's proof/measurement gates. |
| Related Issues/bugs | Repair defects in the selected feature or its shared paths. Within those repairs, prioritize data/config integrity and crashes, then broken functions/input, then visual correctness and actionable warnings. Use actual impact/evidence, not an alarming log label alone. |

Within comparable impact, prefer work that unblocks other tasks, then the older
unresolved request. File position and message recency alone do not determine
priority. Group closely related repairs only when they share a technical purpose.
Record linked tasks in their own categories and group related changes only when
they share a technical purpose. Do the minimum prerequisite needed for the
selected feature, then return to it; do not expand a dependency into unrelated
backlog work. Unrelated Rework/Issues remain open without preempting actionable
features solely because they are bugs or older requests.

A task is actionable when its next meaningful step can be performed with current
access, dependencies and authorization. A task with genuinely unfinished requested implementation remains open.
A task the bot reported finished is [x] with owner verification still
unconfirmed; such validation is tracked as a separate gate, not
"implementation unfinished". Continue the next actionable feature in
the explicit sequence. If no feature
can advance, continue related Rework/Issues, then other actionable Rework/Issues
using impact, dependencies and existing evidence; neither of those categories
has a blanket precedence over the other. Recheck waiting items on relevant new
evidence. Never mistake an unfinished implementation for completion, or
use a status change to bypass task priority.

If a new request arrives during work, classify/update it immediately and reassess.
Switch promptly for an explicit priority; resolve a failure that blocks the
selected feature as its prerequisite. Otherwise finish a
safe atomic milestone before switching. After each milestone, update the affected
item with its result and remaining gate, then select the next authorized task.
A generic "continue" resumes this process without asking for a task choice or
stopping at a plan/offer while actionable authorized work remains.

Ask only for genuinely missing information or required authorization that blocks
the chosen step; continue independent authorized work while waiting. If all
remaining work depends on external input, report the precise dependency rather
than inventing new scope or claiming completion.

## Completion and archives

Use two separate status dimensions:
- **Implementation:** `[ ]` not finished / `[x]` bot-reported task complete.
  Checked entries must say **"Hoàn thành (bot báo xong) — Owner chưa verified"**
  until owner verification is explicitly received. State what was actually
  delivered and, where known, its source SHA. A partial milestone in a still
  incomplete task is not a reason to check the parent.
- **Verification:** `Owner chưa verified` / `Owner verified`, plus factual
  test evidence (source, focused native, exact-SHA canonical, installed or
  hardware acceptance). A failed or skipped validation remains a FAIL/SKIP
  regardless of implementation status, and related open regression issues
  stay available for continued diagnosis.

When both implementation and owner verification are complete, record the
actual owner confirmation date. Retain a recently owner-verified completed
item in its category for seven days, then archive under
`docs/archive/chatbot/`. Keep completed-but-owner-unverified entries
visible in the active category until verified, so they can be reviewed
without being counted as unfinished implementation. Archive
superseded duplicates or retired plans only after preserving outstanding
requested work and independent failure evidence. Never invent a completion
or owner-verification date from a source commit.

Preserve valid maintainer/concurrent status edits. A checked item without a known
completion date is not yet eligible for age-based archiving; retain it until the
date can be established instead of inventing a date from a source commit.

[Archive index](../../docs/archive/README.md) holds historical task snapshots,
retired designs and completed migration notes. Existing evidence, screenshots,
source pins and consumed receipts keep their original paths and status. Old
ABYSS/OPTIMIZATION/RELEASE files are short link-compatibility pointers only.

## Cross-repository task management — effective 2026-10-11

**Alis dev is the only canonical task tracker for Alis, Alis-Companion and
Alis-Intergration.** Use the SAME Issues/bugs, Rework/optimization and
New features files for every repository. The old Companion visual/AI TODOs
and the former Hadanion/Hadalird task routing are source snapshots,
not authorization to keep updating separate task lists. Integration has
no active TODO of its own at intake; its package delivery and release
tasks have been captured from manifest, source and host requirements.
All future incoming requests, bug reports, progress and completion for
either satellite must be classified here; do not add a fourth backlog.

**Source ownership is separate from task ownership:** core host/shared AI,
perimeter, desktop UI and generic Notes/Todo belong to Alis dev; optional
Companion actor, renderer, movement/persona and client behavior belong to
[Alis-Companion](https://github.com/llocphann/Alis-Companion) main;
optional TLP/Thinkfan/Obsidian workers and helpers belong to
[Alis-Intergration](https://github.com/llocphann/Alis-Intergration) main.
Those names/refs reflect discovery on 2026-10-11; refetch the actual
target branch before work and never assume an Alis dev branch exists there.
Never mutate Alis stable or rewrite cross-repository Git history.
Implementation in a satellite repo is permitted only under its own
current authority; preserve unrelated concurrent work.

For each implementation step record selected Alis task ID, owning source
repository and branch, source/host Git SHAs, installed release identity
if applicable, commands, PASS/FAIL/SKIP and exit codes, owner permission,
native/local dependencies and remaining release gates. A source-only test
or a mock is not hardware/visual/real-model acceptance. Do not reexecute
indeterminate privileged or deployment work. User data access, device
policy changes, local agent hooks, memory capture or background inference
require the original explicit consent; task migration grants none.

No new agent, bot-number, parallel management board, Automation or MegaQML
runtime is created. Source docs and old checklists can be read as evidence,
but any status change is written **only here in Alis**.

## Research and external repositories

[Optimization research](../../docs/optimization/README.md) remains technical
reference, separate from task status. Resumed product work authorizes the
requested strict-lossless implementations after parity/measurement gates;
research-only findings are not automatically approved runtime changes.

Alis-Intergration owns optional TLP, Thinkfan and Obsidian implementation,
while Alis-Companion owns optional Companion animation and AI behavior.
Alis owns shared host APIs. **All task/status/priority decisions happen in
the Alis lists above**, regardless of which source repository carries the
code. Historical satellite TODO pages must not be treated as live queues.

Only the **five-hour** limit remaining below 3% triggers checkpoint/push and
a single continuation at that window's reset plus three minutes. Weekly usage
does not trigger stopping or scheduling. Do not use reset credits.
