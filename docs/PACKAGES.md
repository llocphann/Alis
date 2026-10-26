# Package Reference

## Native Rust runtime

Current-source install/package paths build the committed `native/Cargo.lock` workspace and ship the qualified helpers under `share/quickshell/alis/native/bin/`, including the opt-in Aqua backend `alis-companiond`. The rolling Arch package and Nix build current source; the pinned non-VCS Arch package gains newer helpers when its source snapshot advances. Python remains only for explicitly retained fallback paths.


This page documents the Arch-based source install dependency model used by `./setup install`, plus the separate Arch package recipes that distribute the Alis runtime (with Alis compatibility) itself.

## Packaging layers

Alis has two different Arch packaging trees with different responsibilities:

| Path | Purpose |
|---|---|
| `sdata/dist-arch/` | Dependency-group recipes consumed by the source installer, plus the `alis-deps` orphan-protection tracker. |
| `distro/arch/` | Distributable packages: `alis-shell`, `alis-shell-git`, and the `alis-meta` full-experience meta-package. |

The source installer reads the `depends` arrays from the dependency-group PKGBUILDs under `sdata/dist-arch/`; those group recipes are dependency declarations, not the packaged Alis shell payload.

`alis-deps` is different from the dependency groups. It is excluded from the dependency-install loop and is built only after dependency installation finishes. The installer stages its PKGBUILD in a temporary directory, filters its `depends` array to packages that are actually installed, and reinstalls the tracker so changes to `--no-*` choices are reflected in pacman's dependency metadata. The tracker contains no files of its own and exists to keep installed Alis dependencies from being removed by orphan cleanup.

The committed `sdata/dist-arch/alis-deps/PKGBUILD` version follows the repository `VERSION`; release publication checks this invariant.

---

## Core (`alis-core`)

Essential compositor, desktop, portal, and command-line dependencies declared by `sdata/dist-arch/alis-core/PKGBUILD`.

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

## Quickshell (`alis-quickshell`)

Quickshell, Qt 6, and QML/KDE runtime dependencies declared by `sdata/dist-arch/alis-quickshell/PKGBUILD`.

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

## Audio (`alis-audio`)

Core audio stack and media dependencies declared by `sdata/dist-arch/alis-audio/PKGBUILD`. This group is enabled by default and can be disabled with the installer's audio option.

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
| `mpd-mpris` | MPRIS bridge for MPD/rmpc/Alis Music sessions |
| `yt-dlp` | YouTube extraction backend |

Equalizer Phase 1 keeps its backend and control transport optional. The group advertises these through `optdepends`, so the source install remains usable without them:

| Optional package | Purpose |
|------------------|---------|
| `easyeffects` | Optional audio-effects and Equalizer backend |
| `socat` | Optional EasyEffects control transport for Equalizer |

Missing either optional package must not make Media playback or shell startup fail. Equalizer capability should degrade to unavailable/error state instead.

The installer separately ensures `plasma-browser-integration` is present for browser media sessions and artwork.

Alis Music and MPD clients such as `rmpc` share one MPD session. The Arch audio bundle installs both `mpd` and `mpd-mpris`; LocalMusic uses MPD protocol only for library/database/queue operations that MPRIS does not expose, while normal transport stays on the MPRIS boundary. The default bridge service targets MPD at `localhost:6600`.

---

## Screenshots & Recording (`alis-screencapture`)

Screenshot, OCR, and recording dependencies declared by `sdata/dist-arch/alis-screencapture/PKGBUILD`.

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

## Input Toolkit (`alis-toolkit`)

Input simulation, hardware control, idle handling, screenshot helpers, and utility dependencies declared by `sdata/dist-arch/alis-toolkit/PKGBUILD`.

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

## Fonts & Theming (`alis-fonts`)

Base font/theming dependencies declared by `sdata/dist-arch/alis-fonts/PKGBUILD`:

| Package | Purpose |
|---------|---------|
| `fontconfig` | Font configuration |
| `noto-fonts-emoji` | Emoji font fallback |
| `ttf-dejavu` | DejaVu fonts |
| `ttf-liberation` | Liberation fonts |
| `ttf-roboto` | Roboto font family |
| `ttf-roboto-mono` | Roboto Mono |
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

`cava`, `yt-dlp`, and `mpv` remain required members of the `alis-audio` dependency group. `easyeffects` and `socat` are advertised by the audio group and dependency tracker as optional feature dependencies; their absence should leave Equalizer unavailable/degraded without breaking Media playback.

---

## Distributable Arch packages (`distro/arch`)

The package recipes under `distro/arch/` distribute Alis itself rather than serving as source-installer dependency groups:

| Package | Purpose |
|---------|---------|
| `alis-shell` | Versioned non-VCS Alis shell/runtime package. Before release tags exist, the committed recipe may pin an immutable reviewed commit snapshot; release preparation switches the default source identity to the immutable `vX.Y.Z` tag. |
| `alis-shell-git` | Development/VCS package following `dev`. |
| `alis-meta` | Full Alis desktop-experience meta-package depending on `alis-shell` plus the wider integration set. |

The pre-release commit pin is a reproducible development/package snapshot, not evidence that current `dev` has passed package acceptance. Published release preparation must replace that default `_source_ref` with the release tag and regenerate `.SRCINFO`; `RELEASING.md` and the publication preflight own that invariant.

`alis-meta` also keeps `easyeffects` and `socat` in `optdepends`, not `depends`. Installing the distributable shell or meta-package therefore does not make the Equalizer backend a hard requirement.

`alis-shell` and `alis-shell-git` install the runtime payload, `alis` launcher, user service, desktop entries, icon, privileged helper/polkit assets, docs, and package-managed version metadata. Their packaged `setup migrate` path preserves package-manager launcher ownership rather than materializing a stale user-local launcher.

For pacman installs, `/usr/lib/systemd/user/alis.service` remains the authoritative unit. The packaged launcher does not copy that unit into `~/.config/systemd/user`; `alis service enable` creates only the compositor-specific wants link and points it directly at the package unit. On upgrade, a legacy user unit is removed automatically only when it is byte-identical to the package unit. A different user unit is treated as an intentional override and causes the package-managed service command to stop with a warning instead of overwriting it.

Run `alis service disable` as each affected user before removing `alis-shell` or `alis-shell-git`. Pacman package hooks deliberately do not mutate users' home directories. If a package is removed while compositor wiring is still enabled, the removal message explains how to delete the resulting dangling `*.wants/alis.service` symlink and reload the user systemd manager.

For release-specific version/source invariants, see [RELEASING.md](RELEASING.md).

## Alis-Intergration optional system gateway on Arch

The regular optional package is user-owned and managed through Settings →
Integrations → Management. It can run Obsidian integration without the
optional TLP/Thinkfan system helpers. Workers remain disabled until selected.

Use `./setup integrations install --dry-run` to review the explicit package
and system-helper stages, then `./setup integrations install` to confirm
them. `reinstall`, `update`, `rollback`, `remove` and `status` use the same
supported lifecycle. Default core setup and passive Settings never provision
helpers; the core `--integration-helpers` flag is an explicit opt-in.

Full Arch packages (`alis-shell` / `alis-shell-git`) own the trusted gateway
at `/usr/libexec/alis-intergration-system-provision` and its policy at
`/usr/share/polkit-1/actions/org.alis.intergration-system-provision.policy`.
These installed names are security compatibility contracts. On Arch repo-copy
installs, explicit setup can build the reviewed `alis-intergration-gateway`
package as the regular user and request normal administrator authorization
for installation. A source checkout does not prove any package is installed.

The gateway checks fixed approved helper/policy/schema hashes. Its existing
authorization IDs, native policy wording and permissions remain compatible;
UI rebranding never silently replaces security payloads. Native installed
ownership, authorization and Owner acceptance remain separate from fixture
tests. Do not bootstrap a root gateway by copying downloaded files as root.

`./setup integrations status` reconciles package and system receipts. Inspect
uncertain effects before explicit `status --acknowledge-uncertain` and retry;
the lifecycle does not replay uncertain actions. No default action starts a
service, changes TLP policy, alters charging thresholds or changes fan speed.
User configs, existing releases, notes and vaults survive removal/rollback.
