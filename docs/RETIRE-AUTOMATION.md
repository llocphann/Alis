# AUTO-R02 — Automation retirement

Owner decision **2026-10-18**; canonical tracking: [Alis #118](https://github.com/llocphann/Alis/issues/118). Applies to `dev`; `stable` and old releases are unchanged. AUTO-F01 / AUTO-R01 were withdrawn, not Owner verified. Earlier queue, dispatch and auto-approval instructions are revoked. Never use the retired worker to perform its removal.

## Removed runtime

The manager, worker, privilege broker, Chat Bridge, scheduler, taskflow, credential helpers, installer and dedicated command scripts are removed from source. Dedicated Automation tests and CI jobs are removed. Settings page 35 remains a null migration slot; saved navigation safely redirects to Panels. Other Settings pages, Companion, Integrations and the core shell remain connected.

Four historical JSON files remain under `automation/queue/pending/` and `automation/results/`. They are inert provenance, including an unresolved request; their retention grants no permission to execute them. Public evidence under `docs/evidence/automation/` is also retained. The reference scan rejects executable backend files, retired entrypoints and new live imports.

New runtime payloads exclude the retired paths. Generic updates still protect old installed Automation paths from orphan cleanup and `rsync --delete`: another machine's live worker must not lose its source before an independent idle/ownership audit. A source update cannot substitute for host decommission.

## Owner-host decommission

On 2026-10-18, the owner explicitly authorized safe local removal and cancellation of the 22 October resume schedule. The schedule was deleted through Codex. Independent systemd/process inspection found the worker, bridge and broker inactive, zero running/publishing worker jobs, and all manager profiles requesting stopped. Uncertain manager requests remain unresolved and are preserved.

A private, owner-only backup was verified before changing units or launchers. It includes the XDG config/state/data, receipts and symlinks, unit files/drop-ins/enabled links, Desktop override and removed source. Its local pointer is `$XDG_STATE_HOME/alis-retirement/latest-auto-r02` (default `~/.local/state/alis-retirement/latest-auto-r02`). No backup content or credentials are uploaded.

The exclusively owned `hadalis-worker.service`, `hadalis-chat-bridge.service`, `hadalis-privilege.service` and `hadalis-chatgpt.service` were disabled, stopped and removed, with their enabled links/drop-in, then user systemd was reloaded. The last unit contained only its Python supervisor; the actual ChatGPT application was outside that cgroup and remained open. The local Desktop entry's installer-generated main Exec was restored from the ordinary upstream entry, preserving all other metadata. Alis and Niri kept the same active PIDs. Nothing was sent, approved, replayed or restarted through Automation.

A supplemental 109-file installed-tree backup was verified before removing 105 Automation source/cache files from `quickshell/alis` and the legacy `quickshell/inir` runtime. Four installed historical JSON files remain byte-identical; no retired executable remains in either tree. This was targeted cleanup, without redeploying the shell or rewriting its version metadata. The existing ChatGPT process retains its original debugging flags until it exits naturally; future ordinary launches no longer add those flags.

All 2,137 backed-up private file/link entries were checked unchanged after host removal. Secret Service was neither read nor cleared. Keep private XDG state, credentials, pending requests, uncertain receipts and temporary evidence until a separate Owner-supervised retention decision; do not mark them reconciled merely because the runtime is absent.

Read-only reinspection: `python3 scripts/audit-retired-services.py`. Its `automation_units_and_processes_absent` field reports removal independently of historical retention. Exit **2** still means investigation/retention review is required; it does not authorize deletion. The utility never imports the backend or changes services/state.

## Compatibility and release limits

Historical Companion evidence-publication scripts still contain lazy imports of the old credential API. They are not runtime dependencies of the shell or Companion presentation. Those legacy publication modes must not be replayed or supplied a replacement credential transport as part of this retirement; the removed backend is unavailable. No Companion execution or acceptance is claimed here.

`distro/arch/alis-shell/PKGBUILD` still pins `c74d8a2336a311699ced1a00898bc4b2527a3a45`. That historical versioned package can contain Automation and must not be promoted as Automation-free. Its source pin requires a separately tested release cutover and Owner acceptance. `alis-shell-git` follows `dev`; Nix builds its checkout.

Exact-SHA source, Settings, audit and payload tests plus the canonical maintainer validator remain separate from native desktop/installed-package acceptance. Actual receipts are linked in #118. Keep the Issue open until its remaining verification gates are met; removal does not turn earlier failed, stopped or unrun tests into PASS.
