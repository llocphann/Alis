# Setup & Updates

## Interactive Menu

```bash
./setup
```

Running `./setup` without arguments launches an interactive menu with all available commands. The menu provides:

- Visual command selection
- Current version, install mode, and update status
- Pending migrations indicator
- Health checks (shell running, Niri detected)
- Snapshot availability

This is the recommended way to use the setup script if you're unsure which command to run.

## How the pieces fit together

There are now three complementary entry points (the public `alis` command forwards to the existing `alis` runtime without creating a second session):

- `./setup`
  - authoritative installer and maintenance entry point
  - owns install, update, doctor, status, migrate, rollback, my-changes, uninstall
- `alis` (legacy alias: `alis`)
  - daily launcher and operator CLI
  - owns runtime actions like `run`, `start`, `restart`, `settings`, `logs`, `repair`, `terminal`, and IPC calls
  - forwards maintenance commands like `install`, `update`, `doctor`, `status`, `migrate`, `rollback`, `my-changes`, and `uninstall` back to `setup`
- `make install`
  - packaging-style local install for packagers, testers, or source installs that should behave like a packaged shell payload

Use them like this:

- install once:
  - `./setup install`
- maintenance via launcher wrapper:
  - `alis update`
  - `alis doctor`
  - `alis status`
- runtime operation:
  - `alis run`
  - `alis settings`
  - `alis logs`
  - `alis repair`
- local distribution validation:
  - `make test-local`
  - `alis test-local`
  - `alis test-local --with-runtime`

## Install

```bash
git clone https://github.com/llocphann/Alis.git
cd Alis
./setup install
alis run
```

Add `-y` for non-interactive mode.

If you want a packaging-style local install surface instead of the repo-sync installer:

```bash
sudo make install
```

With the default Makefile paths, that installs:

- the `alis` public launcher plus `alis` compatibility launcher, Quickshell runtime payload, package-managed metadata, the existing `alis.service`, public `alis.desktop` and `alis-settings.desktop` IDs/icons, hidden legacy desktop IDs, docs, and license under `/usr/local`;
- the battery/TLP and ThinkFan privileged helpers under `/usr/libexec`;
- their polkit policies, plus the TLP settings schema, under `/usr/share`.

Those system locations can be changed through the Makefile install variables when packaging. `make install` does **not** install distro dependencies, install ThinkFan/TLP themselves, or enable the existing `alis.service` user service for you. See [ThinkFan Integration](THINKFAN.md) for ThinkFan service/config prerequisites and troubleshooting.

## Update

```bash
alis update
```

`alis update` and `./setup update` run the same update engine. `alis update` is the convenient launcher-facing entry point; `./setup update` is the underlying maintenance command and the better choice when you also want the interactive TUI nearby.

What happens:

1. Checks remote for new commits
2. Creates snapshot (for rollback)
3. Pulls changes
4. Syncs QML code, scripts, assets
5. Syncs Vesktop themes (if present)
6. Applies required migrations automatically
7. Offers optional migrations
8. Restarts shell
9. Checks for missing system packages
10. Updates Python venv packages

The runtime sync does not overwrite your user configs directly. If a release needs config changes, required or optional migrations may update `config.json` or `config.kdl` with backup/rollback coverage.

For legacy monolithic Niri configs, required migrations can now convert `~/.config/niri/config.kdl` into the modular `config.d/` layout automatically during update. The current config is preserved section-by-section, unknown top-level blocks are kept in `config.d/90-user-extra.kdl`, and the normal migration backup/rollback flow still applies.

If `setup` detects that the active Alis installation is externally managed, `alis update` does **not** pull or sync repo files into the runtime. In that case it:

- Shows the detected install mode
- Shows the package update command when metadata provides one
- Leaves the shell payload unchanged
- Still applies required migrations if any are pending

## Doctor

```bash
alis doctor
```

`alis doctor` is a wrapper around `./setup doctor`.

Diagnoses and **automatically fixes** common issues:

- Missing directories
- Script permissions
- Python packages (via uv)
- Version tracking
- File manifest

For externally managed installs, `doctor` can rebuild `~/.config/illogical-impulse/version.json` from the runtime metadata already present under `~/.config/quickshell/alis/version.json`. It also skips the repo-sync manifest requirement when the install is package-managed.

If you want the same repair flow plus restart and filtered logs:

```bash
alis repair
```

## Rollback

```bash
./setup rollback
```

Restore a previous snapshot if something breaks after an update. Shows available snapshots with dates and lets you choose which one to restore.

For externally managed installs, `rollback` does not try to restore repo-managed snapshots or reset the checkout. It stops early and points you back to the package manager for shell payload changes.

## Migrate

```bash
./setup migrate
```

Review and apply pending config migrations. Migrations are changes to user configs (keybinds, layer rules, etc.) required by new features.

The opt-in `061-alis-namespace-alias` is a special non-destructive compatibility migration. It provides optional `alis` directory aliases for pre-existing `alis` XDG roots, after preflight collision checks; it does not move configs, rewrite state or start a second service. Use `alis migrate` to review it, or skip it and continue using `alis` paths normally. See [the namespace audit](BRANDING_MIGRATION.md#optional-namespace-aliases-r6-compatibility-milestone).

What happens:

- Shows list of pending migrations
- Displays exactly what each migration will change
- Creates automatic backup before applying
- Lets you choose which migrations to apply
- Required migrations are applied automatically during `update`
- Optional migrations can be applied manually

When the installer detects an older unified Niri config, the required migration path can split it into:

- `config.kdl` include root
- `config.d/10-80-*.kdl` standard sections
- `config.d/90-user-extra.kdl` for preserved non-standard top-level content

### Modular Niri config at a glance

For new installs and migrated setups, `~/.config/niri/config.kdl` becomes a small include root and the real sections live in `config.d/`:

- `10-input-and-cursor.kdl`
  - keyboard, mouse, touchpad, cursor basics
- `20-layout-and-overview.kdl`
  - column layout, overview-related compositor behavior
- `30-window-rules.kdl`
  - per-app window rules and matching
- `40-environment.kdl`
  - environment variables exported into the session
- `50-startup.kdl`
  - startup programs and session bootstrap
- `60-animations.kdl`
  - compositor animation tuning
- `70-binds.kdl`
  - keybinds and launcher shortcuts
- `80-layer-rules.kdl`
  - layer-shell and overlay rules
- `90-user-extra.kdl`
  - preserved custom blocks that do not map to the standard split

If you want to change which apps Alis launches, edit `~/.config/illogical-impulse/config.json` instead of hardcoding new executables into the distributed binds:

- `apps.terminal`
  - used by `alis terminal`
- `apps.browser`
  - used by `alis browser` and the default `Super+W` bind
- `sidebar.quickLaunch`
  - custom quick-launch entries shown by the shell UI

## My Changes

```bash
./setup my-changes
```

View and manage your modifications to distributed files. The setup script tracks which files you've customized.

What it shows:

- List of files you've modified from defaults
- Option to view differences
- Option to restore original versions
- Option to keep your modifications

Useful when you want to see what you've changed or restore defaults after customization.

## Commands

| Command              | Description                                                 |
| -------------------- | ----------------------------------------------------------- |
| `./setup`            | Interactive menu                                            |
| `./setup install`    | Full installation                                           |
| `alis update`        | Wrapper around `./setup update`                             |
| `./setup status`     | Show install mode, update strategy, and health              |
| `./setup migrate`    | Review and apply config migrations                          |
| `./setup doctor`     | Diagnose and auto-fix                                       |
| `./setup rollback`   | Restore previous snapshot                                   |
| `./setup my-changes` | View and restore user modifications                         |
| `./setup uninstall`  | Remove Alis from system                                     |
| `alis install`       | Wrapper around `./setup install` from the repo/runtime root |
| `alis start`         | Start Alis (uses the compatibility alis.service when enabled)                 |
| `alis stop`          | Stop the active runtime                                     |
| `alis run`           | Launch Alis from the active runtime                         |
| `alis restart`       | Restart the active runtime                                  |
| `alis settings`      | Open settings via IPC                                       |
| `alis terminal`      | Launch the configured terminal from `apps.terminal`         |
| `alis browser`       | Launch the configured browser from `apps.browser`           |
| `alis doctor`        | Wrapper around `./setup doctor`                             |
| `alis logs`          | Show recent runtime logs                                    |
| `alis repair`        | Doctor + restart + filtered log check                       |
| `alis status`        | Wrapper around `./setup status`                             |
| `alis test-local`    | Run local distribution checks                               |

Options: `-y` (skip prompts), `-q` (quiet), `-h` (help)

## Status

```bash
./setup status
```

Shows:

- Installed version and commit
- Install mode
- Update strategy
- Repo path when relevant
- Health checks and snapshot availability

For externally managed installs, `status` also shows the detected package update command and makes it explicit that repo-sync updates are disabled for that installation mode.

It also reports:

- resolved runtime path
- launcher availability
- runtime metadata availability

You can reach the same status through:

```bash
alis status
```

`alis status` is a wrapper around `./setup status`.

## Local validation

For distribution, launcher, or install-flow changes, test locally with:

```bash
make test-local
alis test-local
alis test-local --with-runtime
```

These checks cover:

- shell syntax for setup/launcher, release/docs/wiki/translation tooling, installer libraries/migrations, and helper regression scripts
- PKGBUILD syntax for the Arch package roots
- local `make install` dry-run
- launcher path and status resolution
- optional runtime restart and filtered log/error smoke test

## What Gets Installed

### Core Files

| Source                                    | Destination                                                          |
| ----------------------------------------- | -------------------------------------------------------------------- |
| QML code (`./setup install`)              | `~/.config/quickshell/alis/`                                         |
| QML code (`make install` / package style) | `/usr/share/quickshell/alis/` or `/usr/local/share/quickshell/alis/` |
| User config                               | `~/.config/illogical-impulse/config.json`                            |
| State files                               | `~/.local/state/quickshell/user/`                                    |
| Cache                                     | `${XDG_CACHE_HOME:-~/.cache}/quickshell/alis/`                       |
| Launcher (`./setup install`)              | `${XDG_BIN_HOME:-~/.local/bin}/alis`                                 |
| Launcher (`make install` / package style) | `alis` in the install prefix                                         |
| User service (`./setup install`)          | `${XDG_CONFIG_HOME:-~/.config}/systemd/user/alis.service`            |
| Super daemon                              | `~/.local/bin/alis_super_overview_daemon.py`                         |
| Daemon service                            | `~/.config/systemd/user/alis-super-overview.service`                 |

For `make install`, the package-style system payload also includes the user service unit, desktop entries/icon, docs/license, battery/TLP and ThinkFan helpers, matching polkit policies, and the TLP settings schema. See [Installation](INSTALL.md#3-install-the-packaged-runtime-assets) for the default paths and packaging overrides.

### Compositor & Themes

| Source          | Destination                                                                        |
| --------------- | ---------------------------------------------------------------------------------- |
| Niri config     | `~/.config/niri/config.kdl`                                                        |
| GTK themes      | `~/.config/gtk-3.0/`, `~/.config/gtk-4.0/`                                         |
| Qt themes       | `~/.config/kdeglobals`, `~/.config/Kvantum/`                                       |
| Color schemes   | `~/.local/share/color-schemes/`                                                    |
| Color templates | `~/.config/matugen/` _(legacy directory name, matugen binary no longer required)_ |
| Fuzzel config   | `~/.config/fuzzel/`                                                                |
| Vesktop themes  | `~/.config/vesktop/themes/`                                                        |

### Behavior

- First install: Existing configs are backed up to `~/alis-backup/`
- Updates: Your configs are never touched, only QML code is synced
- Shell ownership: `alis.service` is the canonical startup path; do not also add `spawn-at-startup "alis" "start"` in Niri
- Package-managed installs: `alis update` defers shell payload updates to the package manager instead of syncing from the current repo checkout
- Shared configs: Only installed if they don't exist or you approve overwrite

## Migrations

Some features need config changes (new keybinds, layer rules, etc). After `update`, you're asked if you want to apply pending migrations. Each shows exactly what will change, with automatic backup.

Migration scripts are append-only. Old migration numbers are not renamed or deleted, even when a migration is later disabled.

Current example: `028-bar-modular-layout` exists but never runs. The modular bar can fall back to the classic layout at runtime, so existing users do not need their config rewritten during update. That is intentional, not a missing step.

## Backups

- Install backups: `~/alis-backup/`
- Update backups: `~/.local/state/quickshell/backups/`

## Uninstall

### Automated Uninstall (Recommended)

```bash
./setup uninstall
```

The uninstall script intelligently removes Alis while preserving shared resources and user data:

**What it does:**

- Creates automatic backup before removal
- Removes Alis-exclusive files and directories
- Stops `alis.service` and removes Alis-owned user-service wants links
- Asks before removing shared configs (Niri, GTK, themes)
- Detects if you're in a Niri session (preserves compositor config)
- Detects other Quickshell configs (preserves shared resources)
- Detects externally managed shell payloads and warns that package removal is separate
- Lists installed packages with removal recommendations
- Shows commands to revert system changes (groups, modules)

**Interactive mode:**

```bash
./setup uninstall
```

Asks before removing each shared config. Recommended for most users.

**Quick mode:**

```bash
./setup uninstall -y
```

Removes only Alis-exclusive files, keeps all shared configs and packages.

If the shell payload is externally managed, `uninstall` removes the user-side Alis config/data it owns but does **not** remove the package-managed payload itself. The command warns about that explicitly.

### Files Removed Automatically

The following are removed without prompting (Alis-exclusive). XDG variables below use their normal home-directory defaults when unset:

```
${XDG_CONFIG_HOME:-~/.config}/quickshell/alis/                  # Shell configuration
${XDG_CONFIG_HOME:-~/.config}/illogical-impulse/                # User preferences
${XDG_STATE_HOME:-~/.local/state}/quickshell/user/              # Notifications, todo
${XDG_CACHE_HOME:-~/.cache}/quickshell/alis/                    # Cache
${XDG_BIN_HOME:-~/.local/bin}/alis                              # User launcher
~/.local/bin/alis_super_overview_daemon.py                      # Super daemon
${XDG_CONFIG_HOME:-~/.config}/systemd/user/alis.service         # Canonical user service
${XDG_CONFIG_HOME:-~/.config}/systemd/user/alis-super-overview.service # Daemon service
${XDG_DATA_HOME:-~/.local/share}/applications/alis.desktop      # Desktop entry
${XDG_DATA_HOME:-~/.local/share}/applications/alis-settings.desktop # Settings desktop entry
${XDG_DATA_HOME:-~/.local/share}/icons/hicolor/scalable/apps/alis.svg # Desktop icon
~/.local/bin/sync-pixel-sddm.py                                 # SDDM theme sync helper
~/.config/vesktop/themes/system24.theme.css                     # Vesktop Material theme
~/.config/vesktop/themes/alis-tui.theme.css                     # Vesktop TUI theme
~/.config/vesktop/themes/alis-midnight.theme.css                # Vesktop Midnight theme
~/.config/vesktop/themes/ii-colors.css                          # Vesktop colors
```

The uninstall service phase also removes `alis.service` links from user `*.wants` directories before reloading the user systemd manager.

### Shared Configs (Asked Before Removal)

These may be used by other applications. The script asks before removing:

| Path                                                           | Type         | Default Action                                                                                          |
| -------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------------------- |
| `~/.config/niri/config.kdl`                                    | Essential    | Keep (especially if in Niri session)                                                                    |
| `~/.config/matugen/`                                           | Optional     | Ask (remove if you do not want to keep Alis color templates; legacy path, matugen binary not required) |
| `~/.config/fuzzel/`                                            | Optional     | Ask (remove if fuzzel not installed)                                                                    |
| `~/.config/Kvantum/`                                           | Optional     | Ask (remove if Kvantum not installed)                                                                   |
| `~/.config/kdeglobals`                                         | Optional     | Ask                                                                                                     |
| `~/.config/dolphinrc`                                          | Optional     | Ask (remove if not using Dolphin)                                                                       |
| `~/.config/gtk-3.0/gtk.css`                                    | Optional     | Ask                                                                                                     |
| `~/.config/gtk-4.0/gtk.css`                                    | Optional     | Ask                                                                                                     |
| `~/.config/fontconfig/`                                        | Essential    | Keep                                                                                                    |
| `${XDG_DATA_HOME:-~/.local/share}/color-schemes/Darkly.colors` | Alis default | Remove                                                                                                  |

### Installed Packages

The script lists packages installed by Alis but does not remove them automatically. Review the output and remove manually if not needed by other applications.

**Core packages:**

- `quickshell` - Shell framework (safe to remove if no other QS configs)
- `niri` - Wayland compositor (keep if using Niri)

**System tools:**

- `cliphist`, `fuzzel`, `swaylock`, `grim`, `slurp`
- `wl-clipboard`, `brightnessctl`, `playerctl`, `dunst`

**Optional tools:**

- `cava`, `easyeffects`

The script provides distro-specific removal commands (pacman, dnf, apt) with safety recommendations.

### System Changes Not Reverted

The following system changes are not automatically reverted. The script shows commands to revert them manually if desired:

- User groups: `video`, `i2c`, `input`
- i2c-dev module: `/etc/modules-load.d/i2c-dev.conf`
- ydotool service

### Backup Location

Backups are saved to:

```
~/.local/share/alis-uninstall-backup-YYYYMMDD-HHMMSS/
```

To restore from backup:

```bash
cp -r ~/.local/share/alis-uninstall-backup-*/quickshell-alis ~/.config/quickshell/alis
cp -r ~/.local/share/alis-uninstall-backup-*/illogical-impulse ~/.config/illogical-impulse
```

### Manual Uninstall (Fallback)

If the automated script fails or is unavailable:

```bash
# Stop/disable services and remove compositor wants links
systemctl --user disable --now alis.service 2>/dev/null || true
systemctl --user disable --now alis-super-overview.service 2>/dev/null || true
for wants_dir in "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"/*.wants; do
    [ -d "$wants_dir" ] || continue
    rm -f "$wants_dir/alis.service"
done
qs -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/alis" kill 2>/dev/null || true

# Remove Alis-exclusive files
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/alis"
rm -rf "${XDG_CONFIG_HOME:-$HOME/.config}/illogical-impulse"
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user"
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/alis"
rm -f "${XDG_BIN_HOME:-$HOME/.local/bin}/alis"
rm -f ~/.local/bin/alis_super_overview_daemon.py
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/alis.service"
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/alis-super-overview.service"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/alis.desktop"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/applications/alis-settings.desktop"
rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps/alis.svg"
rm -f ~/.local/bin/sync-pixel-sddm.py
rm -f ~/.config/vesktop/themes/system24.theme.css
rm -f ~/.config/vesktop/themes/alis-tui.theme.css
rm -f ~/.config/vesktop/themes/alis-midnight.theme.css
rm -f ~/.config/vesktop/themes/ii-colors.css
rm -f ~/.config/Vesktop/themes/system24.theme.css
rm -f ~/.config/Vesktop/themes/alis-tui.theme.css
rm -f ~/.config/Vesktop/themes/alis-midnight.theme.css
rm -f ~/.config/Vesktop/themes/ii-colors.css
systemctl --user daemon-reload 2>/dev/null || true

# Remove shared configs (review before running)
# rm -rf ~/.config/niri/config.kdl  # Only if not using Niri
# rm -rf ~/.config/matugen          # Optional: Alis color templates (legacy path, matugen binary not required)
# rm -rf ~/.config/fuzzel
# rm -rf ~/.config/Kvantum
# rm -f ~/.config/kdeglobals
# rm -f ~/.config/dolphinrc
# rm -f ~/.config/gtk-3.0/gtk.css
# rm -f ~/.config/gtk-4.0/gtk.css
# rm -f ${XDG_DATA_HOME:-~/.local/share}/color-schemes/Darkly.colors

# Remove Quickshell shared resources (only if no other QS configs)
# rm -rf ~/.local/state/quickshell/.venv
# rm -rf ~/.local/state/quickshell/themes

# Comment out spawn-at-startup in ~/.config/niri/config.kdl:
# spawn-at-startup "alis" "start"
```

For package-managed installs, use the package manager to remove the system payload separately; the manual commands above only target user-side state owned by the source/setup lifecycle.

### Reinstalling

To reinstall Alis after uninstalling:

```bash
git clone https://github.com/llocphann/Alis.git
cd Alis
./setup install
alis run
```
