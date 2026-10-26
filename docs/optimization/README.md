# Alis optimization research

This directory is the **single active home for optimization documentation**.
Do not create new optimization research Markdown elsewhere in `docs/`.

Optimization **tasks** live in [Alis GitHub Issues](https://github.com/llocphann/Alis/issues?q=is%3Aissue+is%3Aopen). This directory contains technical research and evidence, not task status or a parallel backlog.

## Active documents

| Document | Role |
| --- | --- |
| [`STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md`](STRICT_LOSSLESS_GPU_RAM_CPU_AUDIT.md) | **Canonical active research ledger**. New findings, status, proof requirements and research rounds go here. |
| [`GUIDELINES.md`](GUIDELINES.md) | Standing QML/Quickshell optimization and lifecycle guidance. |
| [`ABYSS_STRICT_LOSSLESS_AUDIT_2026-09-30.md`](ABYSS_STRICT_LOSSLESS_AUDIT_2026-09-30.md) | Scoped Abyss audit kept active only because its HOLD/owner-session boundary and bounded candidates are not fully closed. |

## Archive policy

Completed, superseded or handoff-only optimization documents live in
[`docs/archive/optimization/`](../archive/optimization/).

The former cross-repo handoff is a frozen historical research ledger. A
historical candidate is not active merely because it appears there: revalidate
it against current `dev` and promote it into the canonical audit first.

Raw screenshots, hashes, fixture data and validator outputs under
`docs/evidence/` and `docs/aqua-visual/` remain with their owning features;
they are evidence artifacts, not competing optimization ledgers.

## Rules

- Re-fetch current `dev`, read `AGENTS.md` and the relevant open GitHub Issue before each research/write pass.
- Search the canonical audit before promoting a candidate to avoid duplicate,
  ALREADY/CLOSED/SUPERSEDED findings.
- Strict-lossless is the default. Visual substitutions require the audit's
  bounded A/B oracle and visual-error budget.
- Never claim whole-Alis CPU/GPU/RAM/FPS percentages without comparable
  before/after measurement.
