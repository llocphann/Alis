# Package Reference

## Native Rust runtime

Current-source install/package paths build the committed `native/Cargo.lock` workspace and ship the qualified helpers under `share/quickshell/inir/native/bin/`, including the opt-in Wull backend `inir-companiond`. The rolling Arch package and Nix build current source; the pinned non-VCS Arch package gains newer helpers when its source snapshot advances. Python remains only for explicitly retained fallback paths.


This page documents the Arch-based source install dependency model used by `./setup install`, plus the separate Arch package recipes that distribute the Alis runtime (with iNiR compatibility) itself.

## Packaging layers

Alis has two different Arch packaging trees with different responsibilities:

| Path | Purpose |
|---|---|
| `sdata/dist-arch/` | Dependency-group recipes consumed by the source installer, plus the `inir-deps` orphan-protection tracker. |
| `distro/arch/` | Distributable packages: `inir-shell`, `inir-shell-git`, and the `inir-meta` full-experience meta-package. |

The source installer reads the `depends` arrays from the dependency-group PKGBUILDs under `sdata/dist-arch/`; those group recipes are dependency declarations, not the packaged Hadalis shell payload.

`inir-deps` is different from the dependency groups. It is excluded from the dependency-install loop and is built only after dependency installation finishes. The installer stages its PKGBUILD in a temporary directory, filters its `depends` array to packages that are actually installed, and reinstalls the tracker so changes to `--no-*` choices are reflected in pacman's dependency metadata. The tracker contains no files of its own and exists to keep installed Hadalis dependencies from being removed by orphan cleanup.

The committed `sdata/dist-arch/inir-deps/PKGBUILD` version follows the repository `VERSION`; release publication checks this invariant.

---

## Core (`inir-core`)

Essential compositor, desktop, portal, and command-line dependencies declared by `sdata/dist-arch/inir-core/PKGBUILD`.

| Package | Purpose |
|---------|---------|
| `niri` | Compositor |
| `awww` | Wallpaper daemon |
| `bc` | Math in scripts |
| `coreutils` | Basic utilities |
| `cliphist` | Clipboard history |
| `curl` | HTTP requests |
| `wget` | Downloads |
| `ripgrep` | Fast search |
| `jq` | JSON parsing |
| `python` | Python interpreter |
| `xdg-user-dirs` | User directories |
| `xdg-utils` | `xdg-open` and related utilities |
| `rsync` | File synchronization |
| `git` | Version control |
| `wl-clipboard` | Wayland clipboard (`wl-copy`, `wl-paste`) |
| `libnotify` | Notification CLI integration |
| `pacman-contrib` | `checkupdates` for update notifications |
| `wlsunset` | Night-light control |
| `xdg-desktop-portal` | XDG portal base |
| `xdg-desktop-portal-gtk` | GTK portal backend |
| `xdg-desktop-portal-gnome` | GNOME portal backend |
| `polkit` | Privilege elevation framework |
| `polkit-gnome` | Polkit authentication agent |
| `networkmanager` | Network management |
| `gnome-keyring` | Secret storage |
| `nautilus` | Default file manager integration |
| `kitty` | Default terminal integration |
| `fish` | Fish shell used by project scripts |
| `gum` | Setup TUI helper |
| `xwayland-satellite` | X11 compatibility under Wayland |

---

## Quickshell (`inir-quickshell`)

Quickshell, Qt 6, and QML/KDE runtime dependencies declared by `sdata/dist-arch/inir-quickshell/PKGBUILD`.

| Package | Purpose |
|---------|---------|
| `quickshell` | Shell runtime |
| `qt6-declarative` | QML engine |
| `qt6-base` | Qt core |
| `qt6-svg` | SVG support |
| `qt6-wayland` | Wayland integration |
| `qt6-5compat` | Qt 5 compatibility APIs |
| `qt6-imageformats` | Additional image formats |
| `qt6-multimedia` | Media APIs |
| `qt6-positioning` | Geolocation APIs |
| `qt6-quicktimeline` | Timeline animations |
| `qt6-sensors` | Sensor APIs |
| `qt6-tools` | Qt tools |
| `qt6-translations` | Qt translations |
| `qt6-virtualkeyboard` | Virtual keyboard |
| `jemalloc` | Memory allocator |
| `libpipewire` | PipeWire integration |
| `libxcb` | X11 bridge |
| `wayland` | Wayland libraries |
| `libdrm` | DRM/display support |
| `mesa` | Graphics/OpenGL stack |
| `kirigami` | KDE/QML components |
| `kdialog` | KDE dialogs |
| `syntax-highlighting` | KDE syntax-highlighting QML support |
| `qt6ct` | Qt 6 configuration tool |
| `breeze-icons` | Breeze icon fallback |

`plasma-integration` is installed separately by the source installer as a Qt platform-theme integration; `qt6-avif-image-plugin` is attempted through the AUR helper for AVIF image support.

---

## Audio (`inir-audio`)

Core audio stack and media dependencies declared by `sdata/dist-arch/inir-audio/PKGBUILD`. This group is enabled by default and can be disabled with the installer's audio option.

| Package | Purpose |
|---------|---------|
| `pipewire` | Audio server |
| `pipewire-pulse` | PulseAudio compatibility |
| `pipewire-alsa` | ALSA compatibility |
| `wireplumber` | PipeWire session manager |
| `playerctl` | Media-player control |
| `libdbusmenu-gtk3` | Tray/menu integration |
| `pavucontrol` | Advanced volume-control GUI |
| `cava` | Audio visualizer |
| `mpv` | Media playback backend |
| `mpv-mpris` | MPRIS bridge for mpv |
| `mpd` | Local Music library, saved-playlist and queue backend |
| `mpd-mpris` | MPRIS bridge for MPD/rmpc/Hadalis Music sessions |
| `yt-dlp` | YouTube extraction backend |

Equalizer Phase 1 keeps its backend and control transport optional. The group advertises these through `optdepends`, so the source install remains usable without them:

| Optional package | Purpose |
|------------------|---------|
| `easyeffects` | Optional audio-effects and Equalizer backend |
| `socat` | Optional EasyEffects control transport for Equalizer |

Missing either optional package must not make Media playback or shell startup fail. Equalizer capability should degrade to unavailable/error state instead.

The installer separately ensures `plasma-browser-integration` is present for browser media sessions and artwork.

Hadalis Music and MPD clients such as `rmpc` share one MPD session. The Arch audio bundle installs both `mpd` and `mpd-mpris`; LocalMusic uses MPD protocol only for library/database/queue operations that MPRIS does not expose, while normal transport stays on the MPRIS boundary. The default bridge service targets MPD at `localhost:6600`.

---

## Screenshots & Recording (`inir-screencapture`)

Screenshot, OCR, and recording dependencies declared by `sdata/dist-arch/inir-screencapture/PKGBUILD`.

| Package | Purpose |
|---------|---------|
| `grim` | Screenshots |
| `slurp` | Region selection |
| `swappy` | Screenshot annotation |
| `tesseract` | OCR engine |
| `tesseract-data-eng` | English OCR data |
| `wf-recorder` | Screen recording |
| `imagemagick` | Image processing |
| `ffmpeg` | Video processing |

---

## Input Toolkit (`inir-toolkit`)

Input simulation, hardware control, idle handling, screenshot helpers, and utility dependencies declared by `sdata/dist-arch/inir-toolkit/PKGBUILD`.

| Package | Purpose |
|---------|---------|
| `upower` | Power/battery information |
| `wtype` | Wayland text injection |
| `ydotool` | Virtual input |
| `python-evdev` | Evdev bindings |
| `python-pillow` | Python image processing |
| `hyprpicker` | Color picker |
| `translate-shell` | Translation CLI |
| `fprintd` | Fingerprint authentication |
| `brightnessctl` | Backlight control |
| `ddcutil` | DDC/CI monitor control |
| `geoclue` | Geolocation |
| `swayidle` | Idle management |
| `swaylock` | Screen locker |
| `grim` | Screenshot capture |
| `slurp` | Region selection |
| `imagemagick` | Image processing |
| `libqalculate` | Calculator backend |
| `blueman` | Bluetooth manager GUI |
| `kconfig` | KDE configuration tools such as `kwriteconfig6` |
| `tesseract` | OCR engine |
| `tesseract-data-eng` | English OCR data |
| `tesseract-data-spa` | Spanish OCR data |

When the toolkit option is enabled, the installer also adds `uv` through the AUR helper for the packaged Python environment workflow.

---

## Fonts & Theming (`inir-fonts`)

Base font/theming dependencies declared by `sdata/dist-arch/inir-fonts/PKGBUILD`:

| Package | Purpose |
|---------|---------|
| `fontconfig` | Font configuration |
| `noto-fonts-emoji` | Emoji font fallback |
| `ttf-dejavu` | DejaVu fonts |
| `ttf-liberation` | Liberation fonts |
| `ttf-roboto` | Roboto font family |
| `ttf-roboto-mono` | Roboto Mono |
| `songrec` | Music recognition integration |
| `translate-shell` | Translation CLI |
| `fuzzel` | Application launcher |
| `glib2` | GLib utilities |
| `kvantum` | Qt style engine |
| `plasma-integration` | Qt/KDE platform-theme integration |

When the fonts/theming option is enabled, the installer additionally attempts these theme assets through the AUR helper:

| Package | Role |
|---------|------|
| `adw-gtk-theme` | GTK theme |
| `capitaine-cursors` | Cursor theme |
| `whitesur-icon-theme` | Additional icon theme |
| `darkly-bin` | Qt style |

Critical font installs attempted separately are `ttf-material-symbols-variable-git`, `ttf-jetbrains-mono-nerd`, `ttf-roboto-flex`, `ttf-oxanium`, and `ttf-gabarito-git`.

Optional font installs are `otf-space-grotesk`, `ttf-readex-pro`, `ttf-rubik-vf`, and `ttf-twemoji`. For optional fonts with configured fallback URLs, setup attempts a direct font download when the AUR package is unavailable; complete failure falls back to system fonts.

---

## Installer supplements

The source installer intentionally ensures several packages outside the group PKGBUILDs. This list can overlap the groups; the duplicate installation requests use `--needed`.

Always ensured from configured repositories include:

- `quickshell`, `syntax-highlighting`, `kirigami`, `kdialog`
- `niri`, `cliphist`, `gum`, `starship`, `eza`, `xwayland-satellite`
- `noto-fonts-emoji`, `nautilus`, `polkit-gnome`
- `hicolor-icon-theme`, `adwaita-icon-theme`, `papirus-icon-theme`, `breeze-icons`
- `qt6ct`, `kvantum`, `plasma-integration`, `plasma-browser-integration`
- `frameworkintegration`, `kdecoration`
- `sddm`, `qt6-svg`, `qt6-virtualkeyboard`, `qt6-multimedia-ffmpeg`
- `ffmpeg`

The default AUR-helper pass attempts `qt6-avif-image-plugin`, `gowall-bin`, and `mission-center`. Theme/font and toolkit-specific AUR additions are controlled by their corresponding install options as described above.

Python dependencies are handled by the installer's Python-environment setup rather than being represented as Arch packages merely for the sake of this page.

---

## Runtime integrations not guaranteed by setup

These integrations are useful when their corresponding feature is desired, but the source installer does not guarantee that they are present in every installation:

| Package | Purpose | Used by |
|---------|---------|---------|
| `easyeffects` | Optional audio-effects backend | Equalizer capability |
| `socat` | Optional EasyEffects control transport | Equalizer capability |
| `warp-cli` | Cloudflare WARP VPN toggle | Quick toggles |
| `ollama` | Local LLM backend | AI integrations |
| `whisper-cpp` | Local speech-to-text | Voice input/search |
| `deno` / `node` / `bun` | JavaScript runtime for yt-dlp | YouTube media extraction when a JS runtime is required |

`cava`, `yt-dlp`, and `mpv` remain required members of the `inir-audio` dependency group. `easyeffects` and `socat` are advertised by the audio group and dependency tracker as optional feature dependencies; their absence should leave Equalizer unavailable/degraded without breaking Media playback.

---

## Distributable Arch packages (`distro/arch`)

The package recipes under `distro/arch/` distribute Alis itself rather than serving as source-installer dependency groups:

| Package | Purpose |
|---------|---------|
| `inir-shell` | Versioned non-VCS Alis shell/runtime package. Before release tags exist, the committed recipe may pin an immutable reviewed commit snapshot; release preparation switches the default source identity to the immutable `vX.Y.Z` tag. |
| `inir-shell-git` | Development/VCS package following `dev`. |
| `inir-meta` | Full Alis desktop-experience meta-package depending on `inir-shell` plus the wider integration set. |

The pre-release commit pin is a reproducible development/package snapshot, not evidence that current `dev` has passed package acceptance. Published release preparation must replace that default `_source_ref` with the release tag and regenerate `.SRCINFO`; `RELEASING.md` and the publication preflight own that invariant.

`inir-meta` also keeps `easyeffects` and `socat` in `optdepends`, not `depends`. Installing the distributable shell or meta-package therefore does not make the Equalizer backend a hard requirement.

`inir-shell` and `inir-shell-git` install the runtime payload, `inir` launcher, user service, desktop entries, icon, privileged helper/polkit assets, docs, and package-managed version metadata. Their packaged `setup migrate` path preserves package-manager launcher ownership rather than materializing a stale user-local launcher.

For pacman installs, `/usr/lib/systemd/user/inir.service` remains the authoritative unit. The packaged launcher does not copy that unit into `~/.config/systemd/user`; `inir service enable` creates only the compositor-specific wants link and points it directly at the package unit. On upgrade, a legacy user unit is removed automatically only when it is byte-identical to the package unit. A different user unit is treated as an intentional override and causes the package-managed service command to stop with a warning instead of overwriting it.

Run `inir service disable` as each affected user before removing `inir-shell` or `inir-shell-git`. Pacman package hooks deliberately do not mutate users' home directories. If a package is removed while compositor wiring is still enabled, the removal message explains how to delete the resulting dangling `*.wants/inir.service` symlink and reload the user systemd manager.

For release-specific version/source invariants, see [RELEASING.md](RELEASING.md).

## Hadalird optional system gateway on Arch

Hadalird's regular package, downloaded through **Hadalis → Settings →
Integrations**, is user-owned. It does not need root and can be used for
Obsidian without the optional TLP/Thinkfan system helpers.

For TLP/Thinkfan system helper management, the trusted **Hadalis Arch system
package** (`inir-shell` or `inir-shell-git`) additionally owns
`/usr/libexec/inir-hadalird-system-provision` and
`/usr/share/polkit-1/actions/org.inir.hadalird-system-provision.policy`.
These two root-owned files must arrive through the system package manager;
`inir update`, `./setup update`, and installing Hadalird from Settings
update *user-mode shell files* only. They cannot safely bootstrap the
system-side Polkit gateway from user-writable source files.

The non-VCS Arch recipe's reviewed pre-release source snapshot has been
advanced to include these files; both Arch recipes declare them and keep
their `.SRCINFO` metadata synchronized. A source checkout does not imply
either package is actually installed. After a trusted package
install/upgrade, use **Check helper status**, then explicitly consent to
**Install system helpers** if needed. This is separate from enabling any
integration. No default action starts a service, changes a TLP policy, alters
battery charge thresholds, or changes fan speed.

If a machine is running only a `repo-setup` installation, the optional
user-package UI remains usable, but the *privileged* helper controls remain
unavailable until the maintainer has installed a supported system package.
Do not use an ad-hoc `sudo cp` of downloaded helpers or run the downloaded
installer as root.

## Repo-copy optional integrations on Arch

Hadalis supports the existing repo-copy/repo-setup shell without requiring
`inir-shell` or `inir-shell-git`. The separate user-level Hadalird package
is managed in Settings. On Arch, the optional system gateway can also be
packaged separately as `inir-hadalird-gateway`, preserving the shell install.

The small standalone package ships the audited gateway and policy only.
The package build and integrity checks happen as the regular user. System
installation requires an explicit confirmation and normal administrator
authentication through the Arch package manager. The separate hardware
helper install remains opt-in. No fan, battery charging or TLP configuration
is changed by installing the gateway alone.

Remove the standalone gateway package before switching to a full
`inir-shell` package to avoid overlapping file ownership. Native system
authorization and rollback still require owner-machine acceptance.
