# Installation

> **Native runtime:** Rust is the production backend. Current source installs compile the locked Rust 1.95+ workspace and install `inir-inputd`, `inir-mpdd`, `inir-native`, `inir-theme`, and the dedicated `inir-mega` Cloud Storage adapter. Python remains available as an explicit fallback for older compatibility routes through `scripts/native-backend status|rust|python`; Cloud Storage itself has no Python fallback. The pinned non-VCS Arch package gains `inir-mega` only when its reviewed source snapshot advances to a commit that contains the adapter.


> **Primary path: Arch Linux.** `./setup install` also has distro-specific dependency routing for mutable Fedora systems and Debian/Ubuntu. Fedora Atomic/immutable systems and other distributions fall back to generic/manual guidance, so expect more manual intervention outside the primary Arch path.
>
> **NixOS:** there is an experimental flake path. See [NixOS](NIXOS.md).

---

## The Easy Way

```bash
git clone https://github.com/llocphann/Alis.git
cd Alis
./setup install
```

Add `-y` if you don't want to answer questions:

```bash
./setup install -y
```

When it's done:

```bash
niri msg action load-config-file
```

Log out and back in, or just restart Niri. Done.

---

## The Hard Way (Manual)

Use this for unsupported distributions, packaging-style source installs, or when a distro-specific dependency installer needs manual recovery.

### 1. Get dependencies

The manual source-install path itself needs these tools before `sudo make install` can work:

| Package | Why |
|---------|-----|
| `git` | Clones the Alis source tree. |
| `make` | Runs the source install targets. |
| `python3` | Executes the runtime-payload installer. |
| `rsync` | Copies the filtered shell runtime payload into the install prefix. |

The bare minimum runtime packages to not crash immediately:

| Package | Why |
|---------|-----|
| `niri` | The compositor. Obviously. |
| `quickshell` | The shell runtime (official repos). Chosen intentionally for faster and more reliable installs. |
| `syntax-highlighting` | Provides QML module `org.kde.syntaxhighlighting` (required by AiChat code blocks). |
| `kirigami` | KDE QML components used by shell modules. |
| `kdialog` | KDE runtime helper used by some dialogs/integrations. |
| `wl-clipboard` | Copy/paste. |
| `cliphist` | Clipboard history. |
| `pipewire` + `wireplumber` | Audio. |
| `grim` + `slurp` | Screenshots. |
| `materialyoucolor` | Material You colors from wallpaper (Python, installed via venv). |
| `plasma-browser-integration` | Browser MPRIS sessions, controls, and artwork. |
| `plasma-integration` | KDE platform theme plugin (reads kdeglobals for Qt app colors). |
| `darkly-bin` (AUR) | Darkly Qt style (Material You widget rendering). |

For everything else, check [PACKAGES.md](PACKAGES.md). It's organized by category so you can skip what you don't need.

> **Note on quickshell package:** Alis intentionally uses `quickshell` from official repos to avoid long AUR compile times and update-time build failures.
>
> **Runtime extras used by features:**
> - `socat` for YTMusic IPC fallback control and, when available, optional EasyEffects Equalizer transport
> - `fprintd` for fingerprint lockscreen support
>
> EasyEffects itself is optional. The Equalizer capability stays unavailable when its backend/transport is absent; normal Media playback and volume controls continue to work.
>
> **Optional content packs** (`./setup` → Extras): the iNiR-Walls wallpaper
> pack, the ii-pixel-sddm login theme, and YAMIS icons.
>
> **Important for minimal installs (Arch base / netinstall):**
> If shell startup fails with `module "org.kde.syntaxhighlighting" is not installed`, install:
> `syntax-highlighting kirigami kdialog`

### 2. Clone the source

```bash
git clone https://github.com/llocphann/Alis.git ~/Alis
cd ~/Alis
```

### 3. Install the packaged runtime assets

```bash
sudo make install
```

With the default Makefile paths, this installs:

- both `alis` (public) and `inir` (compatibility) launchers, Quickshell runtime payload, generated runtime metadata, the existing `inir.service`, Alis desktop IDs/icons with hidden legacy entries, docs, and license under `/usr/local`;
- the battery/TLP and ThinkFan privileged helpers under `/usr/libexec`;
- their polkit policies, plus the TLP settings schema, under `/usr/share`.

Those system locations can be changed through the Makefile install variables when packaging. The target does **not** install distro dependencies, install ThinkFan/TLP themselves, or enable the compatibility inir user service for you.

The ThinkFan helper is only the Alis control bridge; managed fan control still requires the `thinkfan` executable, a working `thinkfan.service`, and a machine-specific ThinkFan configuration. See [ThinkFan Integration](THINKFAN.md) before enabling managed fan control.

### 4. Copy the configs

```bash
cp -r dots/.config/* ~/.config/
```

This gives you:
- Niri config wired to the `inir` launcher
- Theming templates for Material You colors
- GTK settings
- Fuzzel config

### 5. Apply per-user migrations and enable the compatibility inir user service

Run the required config migrations as the user who will run Alis, not through `sudo`:

```bash
inir migrate
```

Migration 019 establishes `~/.config/inir` as the canonical config directory while keeping the live QML compatibility path `~/.config/illogical-impulse` linked to it. `sudo make install` deliberately does not mutate user home directories, so this per-user step is separate from the system payload installation.

Migration 019 is intentionally fail-closed when the legacy path cannot be reconciled without risking user data. If both `~/.config/inir` and `~/.config/illogical-impulse` are real directories, or if the legacy path is an unexpected file or points somewhere else, the migration stops and preserves both states unchanged. Reconcile the paths manually, keep any data you still need, then rerun `inir migrate`.

Then create and enable the manual-install user service state:

```bash
inir service install
inir service enable
inir service start
```

For a manual `make install`, those service commands create per-user systemd state. When uninstalling, tear that state down **before** `sudo make uninstall` removes the launcher. See [Uninstall and Service Teardown](UNINSTALL.md#manual-package-style-installation-sudo-make-install).

### 6. Restart Niri

```bash
niri msg action load-config-file
```

Or log out and back in.

---

## Did it work?

Check the logs:

```bash
inir logs
```

If everything went well, you should see:
- Classic Bar on the configured edge (with the clock and system indicators)
- Background/wallpaper (hopefully not a black screen)
- `Mod+Tab` opens the Niri overview (native)
- `Mod+Space` (`Super+Space`) toggles the ii overview
- `Alt+Tab` cycles windows using Niri's native bindings
- `Super+V` opens the clipboard panel
- `Super+Shift+S` takes a region screenshot

If something's broken, the logs will probably tell you which package is missing. Probably.

---

## What now?

- [KEYBINDS.md](KEYBINDS.md) - Learn the shortcuts
- [IPC.md](IPC.md) - Make your own keybindings
- [SETUP.md](SETUP.md) - Updating, uninstalling, how configs are handled
- [UNINSTALL.md](UNINSTALL.md) - Ownership-aware teardown for repo, Makefile, Arch package, and Nix installs
- [PACKAGES.md](PACKAGES.md) - Full package list if something's missing
- [THINKFAN.md](THINKFAN.md) - ThinkFan prerequisites, service ownership, and troubleshooting
