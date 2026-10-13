# Security Policy

## Supported versions

`stable` is the supported user-facing branch. Security fixes may land on `dev` first while they are being integrated and validated, but `dev` is not a stable release line.

## Reporting a vulnerability

Please report security vulnerabilities privately rather than opening a public issue with exploit details.

1. Prefer GitHub private vulnerability reporting for this repository: <https://github.com/llocphann/Alis/security/advisories/new>.
2. Include the affected revision/version, reproduction steps, impact, and any relevant logs with secrets removed.
3. If private vulnerability reporting is unavailable, contact the repository maintainer privately before publishing technical details.

Do not include passwords, API tokens, private configuration values, or other credentials in a report.

## Privilege model

The main Alis shell (compatible with Alis runtime IDs) runs as the logged-in user. However, the repository also ships narrowly scoped privileged helpers for operations that require system-level access.

Current privileged integration surfaces include:

- `/usr/libexec/alis-battery-charge-limit`, authorized through the `org.alis.battery-charge-limit` polkit action for managed TLP/power settings.
- `/usr/libexec/alis-thinkfan`, authorized through the `org.alis.thinkfan` polkit action for managed ThinkFan service ownership/control integration.

The corresponding polkit policies authorize these exact root-owned helper paths without an authentication prompt **only for the active local session**. Inactive and non-local subjects are denied by default. The helpers remain the privilege boundary: their accepted arguments, file writes and service operations must stay narrowly validated, and packaging must keep the helper/policy files root-owned and non-writable by ordinary users. Treat these helpers and policy definitions as security-sensitive code; do not broaden the promptless actions beyond the existing validated operations.

## Scope

Relevant security concerns include, but are not limited to:

- **Command/config injection** — untrusted or persisted values reaching shell commands, subprocesses, or generated configuration without appropriate validation.
- **IPC abuse** — external processes invoking IPC handlers with crafted arguments or accessing data beyond the intended contract.
- **Privilege-boundary mistakes** — unsafe privileged-helper arguments, writable trusted files, overly broad polkit authorization, or user-controlled data crossing into authenticated operations.
- **Credential exposure** — API keys, tokens, or private user data leaking through logs, IPC, generated files, crash output, or UI state.
- **Unsafe update/install behavior** — repository, package, migration, or install flows overwriting user/system state outside their documented ownership.
- **Optional integration handling** — missing services, permissions, hardware, or binaries leading to unsafe fallbacks rather than graceful failure.

Upstream vulnerabilities in Niri/Hyprland, Qt, Quickshell, systemd, polkit, TLP, ThinkFan, or other dependencies should normally be reported upstream. An Alis-specific misuse, unsafe configuration, packaging error, or privilege-boundary issue involving those dependencies remains in scope here.

## Security-sensitive changes

Changes that touch privileged helpers, polkit policies, command construction, IPC inputs, update/install paths, migrations, credential handling, or service ownership should receive focused review and validation. Avoid weakening authentication or permission checks merely to make an integration work on one local machine.
