# AUTO-R02 — Automation retirement runbook

Owner decision **2026-10-18**; canonical tracking: [Alis #118](https://github.com/llocphann/Alis/issues/118). **Scope: `dev` only.** No automation run or service action is authorized by this document.

## Source freeze

- `AUTO-F01` / `AUTO-R01` closed **not planned**, not verified. All earlier automatic dispatch and eight-task queue authorizations are revoked.
- Dedicated GitHub Actions workflow and Automation-only blocks in shared CI removed.
- Settings page **35** remains a null legacy-index marker: no Automation route, navigation category, or search entry. Removed the QML component and its qmldir registration. Both Settings windows and external deep links now resolve retired/missing page indices to the live Panels page; a stale spotlight is discarded.
- Automation installer now refuses to create or start any unit or launcher.
- **Do not use the Automation worker or Chat Bridge to decommission itself.** Existing installed processes do not stop when GitHub source changes.

## Packaging and update isolation

The runtime manifest now **excludes** retired `automation/` and all
Automation-only CLI, credential, native inspection and installer scripts from
new Alis packages and fresh installs. Core `scripts/alis`, `alis.service`,
Settings, Companion, Integrations and the normal shell stay installed.

**Versioned Arch release caveat:** `distro/arch/alis-shell/PKGBUILD`
still defaults to a historical pinned source SHA
`c74d8a2336a311699ced1a00898bc4b2527a3a45`. That old source
does **not** inherit the new runtime exclusion, so this versioned package
must **not** be described or promoted as Automation-free until its source pin
is intentionally updated to a tested retirement commit. By contrast,
`alis-shell-git` follows `dev` and Nix builds its current checkout.
Do not change the reviewed versioned release pin automatically while the
canonical validator is red or the installed-host retirement gate is open.

**Important:** Existing installed Automation modules/scripts are explicitly
protected from generic `filter-installed` orphan deletion and
`rsync --delete` until the worker/manager/bridge on the actual desktop have
been safely stopped and receipts backed up. An ordinary Alis update must
**never** decommission active Automation processes or erase their no-replay
state. Existing installed units and desktop overrides need a separately
verified host migration.

## Installed-host read-only gate (not yet performed)

Run from a normal owner terminal. A read-only summary is also available:
`python3 scripts/audit-retired-services.py` (exit 2 means human investigation
is required). This utility does not read or print credentials, stop units,
send messages, approve jobs or delete files. It cannot replace a human
assessment of in-flight GitHub publication or the user's Desktop launcher.

```bash
units=(hadalis-worker.service hadalis-chat-bridge.service hadalis-privilege.service hadalis-chatgpt.service)
systemctl --user --no-pager --full status "${units[@]}" || true
systemctl --user list-unit-files --type=service | grep -E 'hadalis-(worker|chat-bridge|privilege|chatgpt)\.service' || true
systemctl --user list-units --all --type=service | grep -E 'hadalis-(worker|chat-bridge|privilege|chatgpt)\.service' || true
```

Inspect each installed unit `ExecStart`, path, enablement and process. Establish worker/manager **idle** and no in-flight/unacknowledged chat sends or jobs, including uncertain local receipt or failed publication. Never mistake absent GitHub pending jobs for proof of an idle live process. Preserve durable local receipts and no-replay IDs; unclear state means **stop and investigate without replay**.

Back up (locally with owner-only permissions) relevant existing `$XDG_CONFIG_HOME/hadalis/automation.json`, `$XDG_STATE_HOME/hadalis-automation/`, `$XDG_DATA_HOME/hadalis-automation/`, enabled units, drop-ins and any `automation/queue` / `automation/results` evidence. Inventory keyring references without revealing secrets. Do not delete private state.

## Supervised disable (only once idle/ownership gates pass)

On the **installed owner machine**, not via the worker, stop/disable exclusively Automation-owned units:

```bash
systemctl --user disable --now hadalis-worker.service hadalis-chat-bridge.service hadalis-privilege.service
systemctl --user is-active hadalis-worker.service hadalis-chat-bridge.service hadalis-privilege.service || true
systemctl --user is-enabled hadalis-worker.service hadalis-chat-bridge.service hadalis-privilege.service || true
```

Inspect `hadalis-chatgpt.service` and the Desktop launcher **independently**: disable/remove only if exclusive to Automation. Never stop or disable `alis.service`, `niri.service`, Quickshell or another application's ChatGPT launcher.

## Follow-on removal milestones

1. After live-host preflight, remove retired QML component, remaining UI references, translations and icons; confirm saved-navigation fallback.
2. Remove `automation/manager/`, `automation/worker/`, `automation/chat_bridge/`, associated lifecycle/task/queue/credential code and installer/control commands after dependency scan.
3. Remove all dedicated Automation tests, documentation, CI/package hooks. Retain a compact retirement record and preserve historical receipts or migrate them under explicit retention.
4. Remove unused **installed** automation-only user unit files/drop-ins/aliases/launcher, reload user systemd, verify no enabled/active automation units or residual processes.
5. Delete private XDG state, receipts or keyring records **only** after a separate owner approval and verified backup.

## Acceptance

Exact-SHA source reference scan, QML/package/syntax regression, canonical validator with actual exit codes; independent local `systemctl --user` and no-replay/receipt verification; `alis.service`, Niri, other Settings pages and integrations unaffected; **Owner acceptance separate**. Keep #118 open until all stages are verified.
