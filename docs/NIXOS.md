# NixOS

> Experimental. The Arch installer remains the primary supported installation path.

Alis ships Nix packaging with public `alis` CLI and compatibility `alis` runtime identity. The current flake supports `x86_64-linux` and `aarch64-linux` and exports:

| Output | Purpose |
|---|---|
| `packages.<system>.default` / `packages.<system>.alis` | Alis package with `alis` CLI and legacy `alis` support |
| `packages.<system>.alis` | Legacy alias of the same package |
| `nixosModules.default` / `nixosModules.alis` / `nixosModules.alis` | NixOS module for the same single user service |
| `homeModules.default` / `homeModules.alis` / `homeModules.alis` | Home Manager module |
| `homeManagerModules.default` / `homeManagerModules.alis` / `homeManagerModules.alis` | Conventional Home Manager aliases |
| `formatter.<system>` | `nixpkgs-fmt` |

The flake does **not** run `./setup install` or `./setup update`. Nix owns the packaged files and the shell runs from the immutable store path.

The package and modules are ordinary expressions under `nix/`, so flakes are optional. Both flake and non-flake consumers use the same `package.nix`, NixOS module, and Home Manager module.

The repository does not currently commit a `flake.lock`. A direct `nix build .#alis` or `nix flake check` from this checkout therefore resolves the `nixos-unstable` input at evaluation time rather than providing a repository-owned nixpkgs snapshot. Consumer configurations that add Alis as an input normally get reproducibility from their own committed lock file. For a standalone/release build that must be reproducible, pin or lock the outer Nix configuration instead of assuming this checkout has a fixed nixpkgs revision.

The package installs visible Alis desktop entries and icon with hidden legacy Alis entries. Public `Exec` commands point to wrapped `$out/bin/alis`, so application-menu launches receive the same runtime dependency and QML environment as terminal/service launches.

The packaged README and the complete Markdown reference set from `docs/` are available under `$out/share/doc/alis/`. This keeps installation, configuration, module, troubleshooting, and maintainer references available even when the immutable package is used without a source checkout.

**Public configuration:** New setups should use `programs.alis`, which aliases to `programs.alis`. Existing configs remain supported; both map to one `alis.service` during compatibility. Configure one prefix at a time.

## Without flakes

Point a source variable at an Alis checkout or a pinned source:

```nix
{ pkgs, ... }:
let
  alisSrc = /path/to/Alis;
in
{
  imports = [
    (import (alisSrc + "/nix/nixos-module.nix"))
  ];

  programs.alis = {
    enable = true;
    package = pkgs.callPackage (alisSrc + "/nix/package.nix") { inherit pkgs; };
    service.compositor = "niri";
  };
}
```

For Home Manager, import `nix/home-module.nix` instead. `programs.alis.package` can be overridden when you need a custom build.


## With flakes and niri-flake

Add Alis and niri-flake as inputs:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    niri.url = "github:sodiboo/niri-flake";
    alis.url = "github:llocphann/Alis";
  };
}
```

The unqualified Alis input follows this repository's default `stable` branch. To test the active development branch explicitly:

```nix
alis.url = "github:llocphann/Alis/dev";
```

Import the NixOS module together with niri-flake:

```nix
{ config, inputs, ... }: {
  imports = [
    inputs.niri.nixosModules.niri
    inputs.alis.nixosModules.alis
  ];

  programs.niri.enable = true;

  programs.alis = {
    enable = true;
    service.compositor = "niri";
    extraPackages = [ config.programs.niri.package ];
  };
}
```

`extraPackages = [ config.programs.niri.package ];` puts the same `niri` client used by your compositor on the shell service `PATH`, so integrations that call `niri msg` use the matching package.

## Service wiring

`programs.alis.service.enable` defaults to `true`.

`programs.alis.service.compositor = "niri"` makes `niri.service` want `alis.service`. The generated user service participates in the graphical-session lifecycle and starts early enough to claim the StatusNotifierWatcher bus name before the main graphical session target:

- `Type=dbus`
- `BusName=org.kde.StatusNotifierWatcher`
- `Wants=graphical-session-pre.target`
- `After=graphical-session-pre.target`
- `Before=graphical-session.target`
- `PartOf=graphical-session.target`

This ordering mirrors the canonical packaged user service and avoids the cold-login tray ownership race.

When the NixOS or Home Manager module owns `alis.service`, keep service installation and enablement declarative. Do **not** run `alis service install` or `alis service enable`: those launcher commands are intended for source/manual installs and materialize a mutable unit/wants link under the user's XDG systemd directory, which can shadow the module-generated unit. Change `programs.alis.service.*` options and rebuild instead. For ad-hoc start/stop/restart operations, use `systemctl --user <action> alis.service` so the declarative unit remains authoritative.

For Hyprland/UWSM:

```nix
programs.alis.service.compositor = "hyprland";
```

That wires the service under `wayland-wm@Hyprland.service`.

To create the service without compositor auto-start wiring:

```nix
programs.alis.service.compositor = null;
```

Then start it manually when needed:

```bash
systemctl --user start alis.service
```

## Home Manager

Import the Home Manager module from the same Alis input:

```nix
{ inputs, ... }: {
  imports = [
    inputs.alis.homeModules.alis
  ];

  programs.alis = {
    enable = true;
    service.compositor = "niri";
  };
}
```

The Home Manager module can optionally expose the packaged runtime at the traditional Quickshell path:

```nix
programs.alis.configSymlink.enable = true;
```

This creates a symlink at:

```text
~/.config/quickshell/alis
```

Do not enable it when that path is already occupied by a repo-managed checkout.

## Runtime dependencies

The Nix package wraps `alis` with the runtime dependencies declared in `nix/package.nix`. Core tools include Quickshell, clipboard/screenshot/audio tooling, systemd utilities, and the shell's command-line dependencies. Optional packages are added when they exist in the selected nixpkgs set.

EasyEffects and its `socat` control transport are intentionally **not** part of the default Nix runtime closure. The Equalizer Phase 1 backend is optional and degrades to an unavailable capability when these tools are absent; Media playback does not depend on them. To opt into the native EasyEffects backend and its control transport, add both explicitly to the module service `PATH`:

```nix
programs.alis.extraPackages = [
  pkgs.easyeffects
  pkgs.socat
];
```

This can be combined with other entries already supplied through `extraPackages`. The existing EasyEffects service also detects a Flatpak installation at runtime, so the Alis package itself does not need to make the native package or its control transport hard dependencies.

The package also sets the runtime location through `ALIS_SYSTEM_RUNTIME_DIR` / `ALIS_FALLBACK_SYSTEM_RUNTIME_DIR`, so package-managed runs do not depend on a mutable source checkout.

## Privileged integration limitation

The current Nix package installs the shell runtime and launcher into the Nix store. It does **not** provision the system-level privileged helper/polkit installation used by the source/Arch paths for:

- `/usr/libexec/alis-battery-charge-limit`
- `/usr/libexec/alis-thinkfan`

As a result, do not assume battery charge-limit or ThinkFan privileged controls are available merely because the Nix package/module is enabled. Those integrations require separate system-level provisioning until Alis gains a Nix-native privileged-helper/polkit path.

This limitation is specific to privileged system integration; the shell should continue to degrade gracefully when those helpers are unavailable.

For ThinkFan-specific service/config prerequisites and helper behavior, see [ThinkFan Integration](THINKFAN.md).

## Updating

For Nix-managed installations, `alis update` is not the package update path. Update the Alis flake/source pin and rebuild your NixOS or Home Manager configuration.

For example, with a flake lock:

```bash
nix flake update alis
sudo nixos-rebuild switch --flake .#<host>
```

Use the equivalent Home Manager rebuild command when the package is managed there.

## Troubleshooting

- Use `alis logs` (or your normal user-service journal workflow) for runtime errors.
- Check `systemctl --user status alis.service` when startup ordering or DBus ownership is in question.
- Keep `programs.alis.extraPackages` for compositor/runtime tools that are intentionally supplied by your configuration rather than duplicating packages already wrapped by `nix/package.nix`.
- User preferences continue to live in the normal Alis/Alis config/state locations; the packaged QML payload itself is immutable.
