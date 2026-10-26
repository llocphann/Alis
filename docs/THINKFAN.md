# ThinkFan Integration

Alis can expose ThinkFan status and switch between firmware-owned and ThinkFan-managed fan control. This integration is optional: the shell continues to run when ThinkFan, the helper, the service, or hardware telemetry is unavailable.

## Components

The integration has three pieces:

- `services/ThinkFanService.qml` is the Alis host facade.
  - delegates to the enabled optional Alis-Intergration worker;
  - exposes status/control to existing Settings and System Monitor consumers;
  - returns unavailable state when the package or integration is absent. The
    Alis-Intergration worker owns polling, helper execution and timeout handling.
- `/usr/libexec/alis-thinkfan`
  - reports ThinkFan/service/hardware state as JSON with `--status`;
  - applies `managed` or `firmware` ownership when invoked as root;
  - on supported ThinkPad ACPI hardware, applies an explicit `auto` or fixed fan level 1–7 through `--set-level` without rewriting the machine's ThinkFan configuration.
- `org.alis.thinkfan.policy`
  - authorizes the exact installed helper through Polkit;
  - allows it without a password prompt only for the active local session, while inactive/non-local subjects remain denied.

[Alis-Intergration](https://github.com/llocphann/Alis-Intergration) owns the optional worker, helper and policy. Alis source/Make/Arch installation does not install, reset or remove them. Use Settings → Integrations to explicitly install Alis-Intergration, and `./setup integrations install` for its system helpers, then enable Thinkfan. Helper provisioning uses the trusted system gateway and native authorization; it does not enable fan control. The current Nix package does not provision these privileged system-level files; see [NixOS / Home Manager](NIXOS.md#privileged-integration-limitation).

## Prerequisites

To use managed fan control, the machine must provide all of the following:

1. the `thinkfan` executable;
2. a system `thinkfan.service` visible to `systemctl`;
3. a valid ThinkFan configuration, normally `/etc/thinkfan.yaml` or `/etc/thinkfan.conf`;
4. the Alis-Intergration helper at `/usr/libexec/alis-thinkfan`;
5. the Alis-Intergration Polkit policy for privileged profile changes;
6. an active local desktop session recognized by Polkit. The shipped policy does not prompt that active session for these narrowly scoped helper operations.

The Arch `alis-shell` packages treat `thinkfan` as an optional dependency. Installing Alis therefore does not by itself guarantee that `thinkfan.service` or a machine-specific ThinkFan configuration exists.

ThinkFan configuration is hardware-specific. Alis does not invent fan curves or sensor mappings automatically; configure and validate ThinkFan for the machine before enabling managed mode.

## Status contract

Status is intentionally unprivileged:

```bash
/usr/libexec/alis-thinkfan --status
```

The helper reports JSON containing:

- whether the `thinkfan` executable is available;
- whether `thinkfan.service` is installed;
- whether the service is active and enabled;
- the effective profile (`managed` while the service is active, `manual` for a detected fixed ThinkPad ACPI level, otherwise `firmware`);
- whether direct ThinkPad ACPI fan-level control is available;
- the detected ThinkFan config path;
- fan RPM/level when the kernel exposes compatible ThinkPad ACPI telemetry;
- a machine-readable reason when the integration is unavailable or under firmware control.

Alis treats malformed output, an unsupported schema, helper launch failures, and status timeouts as unavailable state rather than assuming fan control succeeded.

## Switching profiles

The shell uses the privileged helper through `pkexec`. The equivalent commands are:

```bash
pkexec /usr/libexec/alis-thinkfan --apply managed
pkexec /usr/libexec/alis-thinkfan --apply firmware
```

`managed` performs the following checks/actions:

- requires the `thinkfan` executable;
- requires `thinkfan.service` to exist;
- runs `systemctl enable --now thinkfan.service`;
- verifies that the service became both active and enabled.

`firmware` runs `systemctl disable --now thinkfan.service` and verifies that the service is no longer active or enabled.

The helper returns failure when these postconditions are not met. After every apply attempt, the shell re-reads status through the unprivileged path instead of trusting the privileged command blindly.

## Per-power-profile fan levels

The Fan Control settings can store one fan level for each desktop power profile: **Power Saver**, **Balanced**, and **Performance**. The stored values are intentionally conservative:

- `0` means **Auto** and is the default for every profile;
- fixed values are limited to levels **1–7**;
- level `0` as a fixed fan-off command is not exposed;
- profile following is opt-in and disabled by default;
- fixed levels are refused while `thinkfan.service` is actively managing the fan;
- the shell does not perform a privileged write during startup/profile restoration; profile following becomes active only after startup settles.

Direct profile levels are exposed only when both `/proc/acpi/ibm/fan` and the ThinkPad ACPI `fan_control=1` capability are detected. Applying a level uses:

```bash
pkexec /usr/libexec/alis-thinkfan --set-level auto
pkexec /usr/libexec/alis-thinkfan --set-level 3
```

**Safety:** a fixed level bypasses temperature-based fan curves. Use **Auto** unless the machine's thermal behavior is understood and monitored. Alis deliberately does not edit `/etc/thinkfan.yaml` or `/etc/thinkfan.conf`, because sensor mappings and safe temperature thresholds are machine-specific.

## Hardware telemetry

Fan RPM and fan level are read only when `/proc/acpi/ibm/fan` is readable. This interface is hardware/kernel-specific. Direct writes additionally require `/sys/module/thinkpad_acpi/parameters/fan_control` to report an enabled state. A missing RPM, level, or direct-control capability does not by itself mean ThinkFan service control is broken; the service state remains authoritative for managed ownership.

On systems without that interface, Alis can still report whether ThinkFan is installed, active and enabled, but RPM/level may remain unavailable.

## Troubleshooting

Check the helper and service independently before debugging the UI:

```bash
/usr/libexec/alis-thinkfan --status
systemctl status thinkfan.service
systemctl is-enabled thinkfan.service
command -v thinkfan
```

If the helper is unavailable, check Gateway/Helpers status in Settings →
Integrations, then explicitly select Install helpers or Reinstall helpers.
Provisioning requires the trusted root-owned gateway; follow the current
[Alis-Intergration installation guide](https://github.com/llocphann/Alis-Intergration) if it is
missing. Core `alis-shell` updates do not repair independently owned optional
helpers. Preserve package-manager ownership when repairing system files.

Then verify the bridge directly with `/usr/libexec/alis-thinkfan --status` and
refresh the integration. A successful helper install does not configure or start
`thinkfan.service`; enabling managed control is a separate user action.

If `--status` reports `thinkfan-unavailable`, install ThinkFan and ensure `thinkfan` is in the system `PATH`.

If it reports `service-unavailable`, install or provide a valid `thinkfan.service` unit before requesting managed mode.

If managed mode fails to start, inspect the system service journal:

```bash
journalctl -u thinkfan.service -b
```

If the shell reports an apply-start failure, verify that `/usr/bin/pkexec`, the Alis-Intergration helper and the current Polkit policy are installed, and that the desktop session is recognized as active. A stale pre-update policy can still request administrator authentication until the packaged/system policy is refreshed.

If the shell reports an apply timeout, inspect ThinkFan/systemd directly before retrying. The UI intentionally times out privileged apply operations instead of leaving its state permanently busy.

For ThinkFan configuration or sensor/fan-curve errors, validate ThinkFan outside Alis first. Alis never rewrites ThinkFan's machine-specific sensors or temperature curve. Its optional per-power-profile control is a separate guarded ThinkPad ACPI level override and should remain on Auto unless the hardware's cooling behavior is understood.

## Packaging notes

- Core source/Make/Arch install and removal preserve the independently installed optional package, helpers, profiles and system services.
- Alis-Intergration installs user-scoped immutable releases separately; its explicit `install-helpers` target stages helper/policy/schema paths without writing hardware profiles.
- `alis-shell`/`alis-shell-git` advertise ThinkFan as optional. Configure and enable the integration separately.
- Nix currently packages the shell/runtime but does not install the privileged helper/policy into `/usr/libexec` and `/usr/share/polkit-1/actions`.

The integration should therefore be treated as an optional capability whose availability is discovered at runtime rather than a shell startup requirement.
