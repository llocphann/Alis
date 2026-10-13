# Shared Local / Cloud task policy — GitHub Issues

**The only live task system is [Alis GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen)** for Alis, Alis-Companion and Alis-Intergration. The `cloud-bot/` directory is a historical compatibility entry point, **not a task list**.

On an actionable request:
1. Refetch Alis `dev` and search Issues for the same stable code/outcome. Merge corrections into the existing Issue; create a new `[DOMAIN-F##]`, `[DOMAIN-R##]`, or `[DOMAIN-I##]` Issue only for a distinct task.
2. Record the outcome, critical constraints, current implementation/owner status, remaining acceptance and evidence succinctly. Keep comments bounded; pin repo/ref/source SHA and real exit status for technical claims.
3. Follow the owner's latest priorities, then non-deferred features with related rework/bugs. `PERF-F01` and `AC-F01`–`AC-F10` are final-phase; `SYS-F01` is very last unless reprioritized.
4. Keep an Issue open when unfinished or finished by bot but awaiting Owner verification. Only explicit Owner approval closes it as completed. Preserve any independent failed/unknown validation.

**Never add task checkboxes, task progress, verification or parallel TODO lists to Markdown.** Follow [AGENTS.md](../../AGENTS.md) and the canonical local validator; documentation/evidence archives remain historical and may be referenced from Issues.
