# Uninstall and Service Teardown

Alis has multiple installation modes. Remove the runtime with the same ownership model that installed it; do not mix repo-managed, manual `make install`, pacman, and Nix teardown commands.

## Repo-managed installation (`./setup install`)

Use the setup-owned uninstall path:

```bash
./setup uninstall
```

This path can identify the active user and safely stop `alis.service`, remove Alis-owned user service wiring, back up user state, and preserve shared resources according to the interactive choices. See [Setup & Updates](SETUP.md#uninstall) for the complete repo-managed behavior.

Repo-managed uninstall preserves optional Hadalird ThinkFan and TLP integration helpers, profiles and running system services. Remove those separately through Hadalird or their package manager when explicitly intended. Core cleanup never removes the upstream `thinkfan` package, disables/stops `thinkfan.service`, or deletes `/etc/thinkfan.yaml` / `/etc/thinkfan.conf`.

## Manual package-style installation (`sudo make install`)

A Makefile install places the system payload under the selected install prefix, but `alis service install` and `alis service enable` create per-user systemd state under `${XDG_CONFIG_HOME:-~/.config}/systemd/user/`. A root `make uninstall` must not guess which user's home directory owns that state.

Tear the user service down **before** removing the launcher:

```bash
alis service disable
alis service uninstall
sudo make uninstall
```

If non-default Makefile variables were used for installation, pass the same values to `make uninstall` so the same system paths are removed.

The ordering matters: after `make uninstall` removes the launcher, the normal `alis service ...` cleanup commands are no longer available. `make uninstall` removes the installed system payload, service template, and desktop metadata that it owns; it intentionally does not recursively alter arbitrary user home directories. The core Make install/uninstall does not manage optional privileged ThinkFan, battery, Hadalird or TLP integration files. Remove those separately through their installer or package manager.

If the system payload was already removed first, clean only the affected user's stale service state:

```bash
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/alis.service"
find "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" -maxdepth 2 \
  -type l -path '*.wants/alis.service' -delete
systemctl --user daemon-reload
```

Do not run that cleanup as root for every home directory. Run it as the user whose Alis service was configured. A retained masked `inir.service` and the original unit archive in `alis-cutover-backups` belong to the separate [canonical cutover recovery protocol](BRAND_R01_CANONICAL_CUTOVER.md); preserve them until the owner no longer needs rollback.

## Arch packages (`alis-shell` / `alis-shell-git`)

The canonical unit is package-owned at:

```text
/usr/lib/systemd/user/alis.service
```

The packaged launcher wires compositor startup directly to that unit. Before removing the package, remove the current user's compositor wants link:

```bash
alis service disable
```

Then remove the package with pacman or the AUR helper that owns it. The packaged `alis service uninstall` command intentionally refuses to delete package-owned service state; pacman owns the unit itself.

During upgrades, a per-user `alis.service` copy is removed automatically only when it is byte-identical to the packaged unit. A different user unit is treated as an intentional override and is never silently deleted. An earlier iNiR installation still requires the separately qualified one-owner handoff; a package transaction does not migrate arbitrary user data or retire its service automatically.

If a package was removed before `alis service disable`, remove the affected user's dangling `*.wants/alis.service` link and run `systemctl --user daemon-reload`.

## NixOS and Home Manager

NixOS/Home Manager modules own `alis.service` declaratively. Do not use:

```text
alis service install
alis service uninstall
alis service enable
alis service disable
```

with a Nix-managed installation. The packaged launcher rejects those ownership-changing commands so a mutable XDG user unit cannot shadow the generated Nix unit.

Disable or remove the module in configuration and rebuild. Operational commands such as `systemctl --user stop alis.service`, `alis service start`, `alis service restart`, `alis service status`, and log viewing can still act on an already provisioned unit. Public `programs.inir` remains an alias for existing declarative configurations.

## User data

Removing a package-style system payload is intentionally separate from deleting user preferences and state. Depending on the install history, user data may remain under locations such as:

- `${XDG_CONFIG_HOME:-~/.config}/alis/`
- `${XDG_CONFIG_HOME:-~/.config}/inir/` and `illogical-impulse/` from earlier installations
- `${XDG_CONFIG_HOME:-~/.config}/quickshell/alis/`
- `${XDG_CONFIG_HOME:-~/.config}/quickshell/inir/`
- `${XDG_STATE_HOME:-~/.local/state}/quickshell/`
- `${XDG_CACHE_HOME:-~/.cache}/quickshell/`
- Alis config/cache/data/state copies and their original iNiR trees retained by cutover

Use `./setup uninstall` when the installation is repo-managed and you want the interactive backup/preservation workflow. For externally managed installations, remove user data separately only when you are certain it is no longer needed.
