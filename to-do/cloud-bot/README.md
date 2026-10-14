# Local and Cloud AI — issue-first task workflow

**Three owning issue trackers:** [Alis](https://github.com/llocphann/Alis/issues) (`dev`, shell/host), [Alis-Companion](https://github.com/llocphann/Alis-Companion/issues) (`main`, Companion), [Alis-Intergration](https://github.com/llocphann/Alis-Intergration/issues) (`main`, integration workers/UI). Create/update in the owning repository, not one central Alis backlog. Historical Alis MOVED Issues are redirects, not active tasks. No Markdown task checklists or status ledgers.

1. **Intake:** select the owning repository, search open **and closed** Issues there by code/behavior and follow any historical Alis MOVED redirect. Merge changes or reopen existing work; create an Issue only for a distinct task. Keep the stable `[DOMAIN-F##]` (feature), `[DOMAIN-R##]` (rework) or `[DOMAIN-I##]` (bug) prefix. Choose an unused code.
2. **Describe and label briefly:** **Goal**, **Constraints** (if relevant), **Done when**. Reuse built-in `bug` / `enhancement` / `documentation` according to the task, and one primary `area:*`. Add colored `complexity:high` only for genuinely complex engineering; use `status:deferred`, `status:blocked` or `status:awaiting-owner` only when grounded. Do not use old `type:*`, speculative priorities, duplicate labels or long logs.
3. **Work and report:** implement on the owning source branch, then update the existing Issue directly. Change the body for new scope; post one concise comment for a meaningful implementation/test milestone with actual SHA and PASS/FAIL/SKIP/exit status or evidence link. Don't append task progress to `to-do/`, `docs/` or README files.
4. **Verify/close:** unfinished → **open**; bot finished → **open / Awaiting Owner verification**; explicit Owner approval → **closed / completed**; canceled → **closed / not planned**. Technical validation remains separate from Owner acceptance.

**Priority:** owner's latest instruction first; otherwise actionable non-deferred features with related rework/bugs. `PERF-F01` and `AC-F01`–`AC-F10` are final-phase; `SYS-F01` is very last unless reprioritized. Respect data/privacy/privileged-operation gates.

See [AGENTS.md](../../AGENTS.md). This directory is retained only for historical links and redirects.
