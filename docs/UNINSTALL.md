# Uninstall and Service Teardown

Alis has multiple installation modes. Remove the runtime with the same ownership model that installed it; do not mix repo-managed, manual `make install`, pacman, and Nix teardown commands.

## Repo-managed installation (`./setup install`)

Use the setup-owned uninstall path:

```bash
./setup uninstall
```

This path can identify the active user and safely stop `inir.service`, remove Alis-owned user service wiring, back up user state, and preserve shared resources according to the interactive choices. See [Setup & Updates](SETUP.md#uninstall) for the complete repo-managed behavior.

For a repo-managed install, uninstall also removes the Hadalis-owned ThinkFan bridge files (`/usr/libexec/inir-thinkfan` and `org.inir.thinkfan.policy`). If the installed metadata reports package-manager ownership, those system files are preserved for the package manager instead. This cleanup never removes the upstream `thinkfan` package, disables/stops `thinkfan.service`, or deletes `/etc/thinkfan.yaml` / `/etc/thinkfan.conf`.

## Manual package-style installation (`sudo make install`)

A Makefile install places the system payload under the selected install prefix, but `inir service install` and `inir service enable` create per-user systemd state under `${XDG_CONFIG_HOME:-~/.config}/systemd/user/`. A root `make uninstall` must not guess which user's home directory owns that state.

Tear the user service down **before** removing the launcher:

```bash
inir service disable
inir service uninstall
sudo make uninstall
```

If non-default Makefile variables were used for installation, pass the same values to `make uninstall` so the same system paths are removed.

The ordering matters: after `make uninstall` removes the launcher, the normal `inir service ...` cleanup commands are no longer available. `make uninstall` removes the installed system payload, service template, desktop metadata, privileged helpers/policies, and TLP files that it owns; it intentionally does not recursively alter arbitrary user home directories.

If the system payload was already removed first, clean only the affected user's stale service state:

```bash
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/inir.service"
find "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user" -maxdepth 2 \
  -type l -path '*.wants/inir.service' -delete
systemctl --user daemon-reload
```

Do not run that cleanup as root for every home directory. Run it as the user whose iNiR service was configured.

## Arch packages (`inir-shell` / `inir-shell-git`)

The canonical unit is package-owned at:

```text
/usr/lib/systemd/user/inir.service
```

The packaged launcher wires compositor startup directly to that unit. Before removing the package, remove the current user's compositor wants link:

```bash
inir service disable
```

Then remove the package with pacman or the AUR helper that owns it. The packaged `inir service uninstall` command intentionally refuses to delete package-owned service state; pacman owns the unit itself.

During upgrades, an old per-user `inir.service` copy is removed automatically only when it is byte-identical to the packaged unit. A different user unit is treated as an intentional override and is never silently deleted.

If a package was removed before `inir service disable`, remove the affected user's dangling `*.wants/inir.service` link and run `systemctl --user daemon-reload`.

## NixOS and Home Manager

NixOS/Home Manager modules own `inir.service` declaratively. Do not use:

```text
inir service install
inir service uninstall
inir service enable
inir service disable
```

with a Nix-managed installation. The packaged launcher rejects those ownership-changing commands so a mutable XDG user unit cannot shadow the generated Nix unit.

Disable or remove the module in configuration and rebuild. Operational commands such as `systemctl --user stop inir.service`, `inir service start`, `inir service restart`, `inir service status`, and log viewing can still act on an already provisioned unit.

## User data

Removing a package-style system payload is intentionally separate from deleting user preferences and state. Depending on the install history, user data may remain under locations such as:

- `${XDG_CONFIG_HOME:-~/.config}/illogical-impulse/`
- `${XDG_CONFIG_HOME:-~/.config}/quickshell/inir/`
- `${XDG_STATE_HOME:-~/.local/state}/quickshell/`
- `${XDG_CACHE_HOME:-~/.cache}/quickshell/`

Use `./setup uninstall` when the installation is repo-managed and you want the interactive backup/preservation workflow. For externally managed installations, remove user data separately only when you are certain it is no longer needed.
