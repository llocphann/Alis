# Local and Cloud AI — issue-first task workflow

**One backlog:** [Alis GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue) for Alis `dev`, Alis-Companion `main` and Alis-Intergration `main`. No Markdown task checklists or status ledgers.

1. **Intake:** search open **and closed** Issues by task code/behavior. Merge changes or reopen existing work; create an Issue only for a distinct task. Keep the stable `[DOMAIN-F##]` (feature), `[DOMAIN-R##]` (rework) or `[DOMAIN-I##]` (bug) prefix. Choose an unused code.
2. **Describe briefly:** **Goal**, **Constraints** (if any), **Done when**. Mention external repo/ref and risks only if they matter. Avoid copied conversations, long research dumps and duplicate issues.
3. **Work and report:** implement on the owning source branch, then update the existing Issue directly. Change the body for new scope; post one concise comment for a meaningful implementation/test milestone with actual SHA and PASS/FAIL/SKIP/exit status or evidence link. Don't append task progress to `to-do/`, `docs/` or README files.
4. **Verify/close:** unfinished → **open**; bot finished → **open / Awaiting Owner verification**; explicit Owner approval → **closed / completed**; canceled → **closed / not planned**. Technical validation remains separate from Owner acceptance.

**Priority:** owner's latest instruction first; otherwise actionable non-deferred features with related rework/bugs. `PERF-F01` and `AC-F01`–`AC-F10` are final-phase; `SYS-F01` is very last unless reprioritized. Respect data/privacy/privileged-operation gates.

See [AGENTS.md](../../AGENTS.md). This directory is retained only for historical links and redirects.
