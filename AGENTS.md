# Alis agent workflow — GitHub Issues

These rules apply to both Local and Cloud development AI. ChatGPT is the reasoning agent; tools, tests and workers execute the requested work.

## Source and safety
1. Work on **Alis `dev`**, refetch its HEAD and affected files before every edit, preserve concurrent changes, and do not change `stable` unless the owner explicitly requests it. Do not create a branch/PR by default.
2. Treat **[Alis GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue)** as the **only active task tracker**, including Alis-Companion and Alis-Intergration tasks. Never append tasks, status or checkboxes to `to-do/`, `AGENTS.md`, `docs/` or other Markdown ledgers. Existing Markdown archives and technical evidence are historical references, not live task boards.
3. On each actionable owner request, **search Issues first**. Update an existing matching issue or create one only for a genuinely distinct outcome. Prefix the issue title with its stable code: `[DOMAIN-F##]` for new features, `[DOMAIN-R##]` for rework/optimization, `[DOMAIN-I##]` for bugs/correctness. Never renumber or reuse codes; cite related Issues.
4. Issue bodies should be **short but complete**: expected result, important constraints/edge cases, any observed evidence and the next acceptance gate. Expand only for security, data durability, compatibility or complex interactions. Add progress as concise issue comments; don't dump raw logs. Source SHAs and actual PASS/FAIL/SKIP/exit results belong in comments or evidence links.
5. **Status:** Keep an Issue open while implementation is incomplete **or** bot-reported complete but **awaiting Owner verification**. Mark those two dimensions explicitly in its description/comment; a reported source fix does not imply test PASS or owner acceptance. Close with `completed` only after the owner verifies. For a withdrawn request, close with `not planned` and retain its history. Reopen only on new scope or a confirmed regression.
6. For work in **Alis-Companion** (`main`) or **Alis-Intergration** (`main`), the Issue stays in Alis. Preserve actual implementation repo/ref, matching host/package SHA, consent/permissions, and package-local tests. Do not create separate trackers.

## Selection and priorities
- Explicit latest owner priority takes precedence. Otherwise work first on actionable **non-deferred New Features**, address related Rework and Issues alongside them, then remaining high-impact Rework/Issues. Within a group, prioritize crashes/data loss, regressions and unblocking dependencies.
- **Final phase:** `PERF-F01` and `AC-F01`–`AC-F10` are deferred until all other non-deferred tasks are done. **Very last:** `SYS-F01` after that deferred group, unless owner reprioritizes. Preserve their consent and native quality gates.
- Continue one safe atomic milestone at a time. A partial source milestone is not whole-task completion. Don't recreate features already Owner verified.

## Product and validation boundaries
- Prefer the existing connected Abyss/Quickshell presentation and faithful Caelestia-like UI. Waffle remains supported; do not classify Waffle as obsolete.
- Ship English-only UI (`translations/en_US.json`); preserve legacy config aliases, user files, source identity, test coverage, and optional package boundaries. No automatic privileged installs, model downloads or vault mutations.
- Validate through scoped regression tests and `bash scripts/validate-maintainer-local.sh` at an exact committed SHA. Physical Niri/Quickshell, installed-package, multi-output and owner visual/input acceptance are separate; never turn a STOPPED, FAIL or unrun check into PASS.

[Task entry point](to-do/README.md) · [Historical archives](docs/archive/README.md) · [Open Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen).
