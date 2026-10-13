# Install dependencies for Alis on Arch-based systems
# This script is meant to be sourced, not run directly.

# shellcheck shell=bash

#####################################################################################
# Verify we're on Arch
#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found. This script is for Arch-based systems only.${STY_RST}\n"
  exit 1
fi

#####################################################################################
# Optional: install only a specific list of missing deps
#####################################################################################
if [[ -n "${ONLY_MISSING_DEPS:-}" ]]; then
  tui_info "Installing missing dependencies only..."

  # doctor reports command IDs; map them to Arch package names. Keep command
  # aliases explicit when the executable name differs from the package name so
  # setup update never asks an AUR helper for a package that cannot exist.
  declare -A cmd_to_pkg=(
    [qs]="quickshell"
    [niri]="niri"
    [nmcli]="networkmanager"
    [wpctl]="wireplumber"
    [jq]="jq"
    [rsync]="rsync"
    [curl]="curl"
    [git]="git"
    [python3]="python"
    [fish]="fish"
    [magick]="imagemagick"
    [grim]="grim"
    [cliphist]="cliphist"
    [wl-copy]="wl-clipboard"
    [wl-paste]="wl-clipboard"
    [fuzzel]="fuzzel"
    [awww]="awww"
    [awww-daemon]="awww"
    [hyprpicker]="hyprpicker"
    [playerctl]="playerctl"
    [notify-send]="libnotify"
    [flock]="util-linux"
    [go]="go"
    [wlsunset]="wlsunset"
    [easyeffects]="easyeffects"
    [uv]="uv"
    [cava]="cava"
    [qalc]="libqalculate"
    [yt-dlp]="yt-dlp"
    [socat]="socat"
    [brightnessctl]="brightnessctl"
    [slurp]="slurp"
    [wf-recorder]="wf-recorder"
    [ffmpeg]="ffmpeg"
    [swappy]="swappy"
    [tesseract]="tesseract"
    [blueman-manager]="blueman"
    [gowall]="gowall-bin"
    [kwriteconfig6]="kconfig"
    [checkupdates]="pacman-contrib"
    [ddcutil]="ddcutil"
    [missioncenter]="mission-center"
    [nm-connection-editor]="nm-connection-editor"
    [xdg-settings]="xdg-utils"
    [mpv]="mpv"
    [swaylock]="swaylock"
    [swayidle]="swayidle"
    [songrec]="songrec"
    [trans]="translate-shell"
    # Legacy/package-level checks with no direct command binary.
    [dunstify]="dunst"
    [syntax-highlighting]="syntax-highlighting"
    [kirigami]="kirigami"
    [kdialog]="kdialog"
    [millennium]="millennium-bin"
  )

  _miss_installflags="--needed"
  $ask || _miss_installflags="$_miss_installflags --noconfirm"

  _miss_pkgs=()
  _miss_cmds=()
  read -r -a _miss_cmds <<<"$ONLY_MISSING_DEPS"
  for cmd in "${_miss_cmds[@]}"; do
    _miss_pkg="${cmd_to_pkg[$cmd]:-$cmd}"
    [[ " ${_miss_pkgs[*]} " == *" ${_miss_pkg} "* ]] || _miss_pkgs+=("$_miss_pkg")
  done

  if [[ ${#_miss_pkgs[@]} -gt 0 ]]; then
    case $SKIP_SYSUPDATE in
      true) sleep 0;;
      *) 
        if $ask; then
          v pkg_sudo pacman -Syu
        else
          v pkg_sudo pacman -Syu --noconfirm
        fi
        ;;
    esac

    if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
      log_warning "No AUR helper found"
      showfun install-yay
      v install-yay
    fi

    if command -v yay >/dev/null 2>&1; then
      AUR_HELPER="yay"
    elif command -v paru >/dev/null 2>&1; then
      AUR_HELPER="paru"
    fi

    v $AUR_HELPER -S $_miss_installflags "${_miss_pkgs[@]}"
  fi

  unset ONLY_MISSING_DEPS
  return 0
fi

#####################################################################################
# System update
#####################################################################################
case $SKIP_SYSUPDATE in
  true) sleep 0;;
  *) 
    if $ask; then
      v pkg_sudo pacman -Syu
    else
      v pkg_sudo pacman -Syu --noconfirm
    fi
    ;;
esac

#####################################################################################
# Ensure AUR helper
#####################################################################################
if ! command -v yay >/dev/null 2>&1 && ! command -v paru >/dev/null 2>&1; then
  log_warning "No AUR helper found"
  showfun install-yay
  v install-yay
fi

# Set AUR helper
if command -v yay >/dev/null 2>&1; then
  AUR_HELPER="yay"
elif command -v paru >/dev/null 2>&1; then
  AUR_HELPER="paru"
fi

#####################################################################################
# Install packages from PKGBUILDs (read depends and install them)
#####################################################################################
tui_info "Installing packages from PKGBUILDs..."

# Function to install deps from a PKGBUILD
install_pkgbuild_deps() {
  local pkgbuild_dir="$1"
  local pkgbuild_file="${pkgbuild_dir}/PKGBUILD"
  
  if [[ ! -f "$pkgbuild_file" ]]; then
    log_warning "PKGBUILD not found: $pkgbuild_file"
    return 1
  fi
  
  log_info "Reading: $pkgbuild_file"
  
  # Source PKGBUILD to get depends array
  local depends=()
  source "$pkgbuild_file"
  
  if [[ ${#depends[@]} -eq 0 ]]; then
    log_warning "No dependencies in $(basename $pkgbuild_file)"
    return 0
  fi
  
  local missing_deps=()
  mapfile -t missing_deps < <(pacman -T "${depends[@]}" 2>/dev/null || true)

  if [[ ${#missing_deps[@]} -eq 0 ]]; then
    log_success "Already satisfied: ${depends[*]}"
    return 0
  fi

  log_info "Installing missing: ${missing_deps[*]}"
  
  local installflags="--needed"
  $ask || installflags="$installflags --noconfirm"
  
  # Install via pacman first (for official repos)
  pkg_sudo pacman -S $installflags "${missing_deps[@]}" 2>/dev/null || {
    # Some packages may be AUR-only, try with AUR helper
    $AUR_HELPER -S $installflags "${missing_deps[@]}"
  }
}

# Install dependency groups. alis-deps is the aggregate tracker built only after
# dependency resolution; running it here would defeat --no-* group choices.
for pkgdir in ./sdata/dist-arch/alis-*/; do
  pkgname=$(basename "$pkgdir")
  case "$pkgname" in
    alis-deps) continue ;;
    alis-audio) $INSTALL_AUDIO || continue ;;
    alis-toolkit) $INSTALL_TOOLKIT || continue ;;
    alis-screencapture) $INSTALL_SCREENCAPTURE || continue ;;
    alis-fonts) $INSTALL_FONTS || continue ;;
  esac
  
  v install_pkgbuild_deps "$pkgdir"
done

#####################################################################################
# Pre-install: resolve quickshell package conflicts
# Source, binary and custom WebEngine builds conflict with quickshell (official extra repo).
# pacman --noconfirm does NOT auto-remove conflicting packages — it aborts instead.
#####################################################################################
for qs_conflict in quickshell-git quickshell-bin quickshell-webengine-git; do
  if pacman -Qi "$qs_conflict" &>/dev/null 2>&1; then
    log_warning "$qs_conflict is installed and conflicts with quickshell (stable, extra repo)"
    if $ask; then
      if tui_confirm "Replace $qs_conflict with quickshell (stable)? (recommended)"; then
        log_info "Removing $qs_conflict..."
        v pkg_sudo pacman -Rdd --noconfirm "$qs_conflict" 2>/dev/null \
          || v pkg_sudo pacman -R --noconfirm "$qs_conflict" \
          || log_warning "Could not remove $qs_conflict — install may fail"
      else
        log_warning "Keeping $qs_conflict — removing quickshell from install list"
        OFFICIAL_PACKAGES=("${OFFICIAL_PACKAGES[@]/quickshell/}")
      fi
    else
      log_info "Non-interactive: replacing $qs_conflict with quickshell (stable)"
      pkg_sudo pacman -Rdd --noconfirm "$qs_conflict" 2>/dev/null \
        || pkg_sudo pacman -R --noconfirm "$qs_conflict" 2>/dev/null \
        || log_warning "Could not remove $qs_conflict — install may fail"
    fi
  fi
done

#####################################################################################
# Pre-install: resolve Quickshell-based shell conflicts
# Other shells ship their own Quickshell fork or own overlapping configs.
# Order matters: meta-packages first, then shells, then runtimes, so pacman
# doesn't complain about dangling dependents.
#####################################################################################
_qs_shell_conflicts=(
  # Noctalia (CachyOS default Niri shell) — meta first, then shell, then runtime
  cachyos-niri-noctalia
  noctalia-shell
  noctalia-qs
  noctalia-qs-git
  # DankMaterialShell
  dms-shell
  dms-shell-git
  # Caelestia
  caelestia-shell
  caelestia-shell-git
  # BMS
  bms-shell-bin
)

_qs_shell_found=false
for _qs_pkg in "${_qs_shell_conflicts[@]}"; do
  if pacman -Qi "$_qs_pkg" &>/dev/null 2>&1; then
    _qs_shell_found=true
    log_warning "$_qs_pkg is installed and conflicts with Alis"

    # Stop related services before removal
    systemctl --user stop "${_qs_pkg}.service" 2>/dev/null || true
    systemctl --user disable "${_qs_pkg}.service" 2>/dev/null || true

    if $ask; then
      if tui_confirm "Remove $_qs_pkg? (required for Alis)"; then
        log_info "Removing $_qs_pkg..."
        v pkg_sudo pacman -Rdd --noconfirm "$_qs_pkg" 2>/dev/null \
          || v pkg_sudo pacman -R --noconfirm "$_qs_pkg" \
          || log_warning "Could not remove $_qs_pkg — install may fail"
      else
        log_warning "Keeping $_qs_pkg — Alis may not work correctly"
      fi
    else
      log_info "Non-interactive: removing $_qs_pkg"
      pkg_sudo pacman -Rdd --noconfirm "$_qs_pkg" 2>/dev/null \
        || pkg_sudo pacman -R --noconfirm "$_qs_pkg" 2>/dev/null \
        || log_warning "Could not remove $_qs_pkg — install may fail"
    fi
  fi
done

# After removing a shell that provides quickshell (e.g. noctalia-qs), the
# quickshell slot is empty. Sync the package db so pacman can install the
# upstream quickshell cleanly.
if $_qs_shell_found; then
  pkg_sudo pacman -Sy 2>/dev/null || true
fi
tui_info "Installing official repo packages..."

# These packages are now in official Arch repos (extra) - NO AUR, NO COMPILATION!
OFFICIAL_PACKAGES=(
  # Quickshell (CRITICAL) - NOW IN EXTRA REPO!
  quickshell

  # Desktop-wide Vietnamese Telex input (Qt/GTK, Niri and XWayland)
  fcitx5
  fcitx5-qt
  fcitx5-gtk
  fcitx5-unikey
  fcitx5-configtool

  # Critical QML/KDE runtime modules (required for shell startup)
  syntax-highlighting
  kirigami
  kdialog
  
  # Already in PKGBUILDs but ensure they're installed
  niri
  cliphist
  gum
  starship
  eza
  xwayland-satellite
  
  # Emoji font (CRITICAL — overview search, notifications, etc.)
  noto-fonts-emoji
  
  # File manager
  nautilus
  
  # Polkit agent (needed for auth dialogs — gnome agent works universally)
  polkit-gnome
  
  # Icon themes - fallbacks from official repos (always available)
  hicolor-icon-theme
  adwaita-icon-theme
  papirus-icon-theme
  breeze-icons

  # Qt theming (works without Plasma desktop)
  qt6ct
  kvantum
  plasma-integration   # Provides QT_QPA_PLATFORMTHEME=kde plugin (reads kdeglobals colors)

  # Browser media integration
  plasma-browser-integration   # Provides browser MPRIS sessions and artwork

  # KDE Frameworks needed by darkly-bin Qt style (lightweight, NOT Plasma)
  frameworkintegration
  kdecoration

  # SDDM login screen (users without another DE need this to log in)
  sddm
  qt6-svg
  qt6-virtualkeyboard
  qt6-multimedia-ffmpeg

  # Video wallpaper support (thumbnail + SDDM background extraction)
  ffmpeg
)

installflags="--needed"
$ask || installflags="$installflags --noconfirm"

log_info "Using precompiled packages from official repos (no compilation)"
v pkg_sudo pacman -S $installflags "${OFFICIAL_PACKAGES[@]}"

#####################################################################################
# Install AUR packages (only those not in official repos)
#####################################################################################
tui_info "Installing AUR packages..."

REQUIRED_AUR_PACKAGES=(
)

AUR_PACKAGES=(
  # Qt6 extras (not in official repos)
  qt6-avif-image-plugin

  # Wallpaper effects editor (used by Gowall integration)
  gowall-bin

  # System monitor (default task manager)
  mission-center
  
  # Note: Python deps are handled via uv + requirements.txt, not AUR packages
)

# Critical fonts (UI breaks without these)
CRITICAL_FONTS=(
  ttf-material-symbols-variable-git
  ttf-jetbrains-mono-nerd
  ttf-roboto-flex
  ttf-oxanium
  ttf-gabarito-git
)

# Optional fonts (have system fallbacks)
OPTIONAL_FONTS=(
  otf-space-grotesk
  ttf-readex-pro
  ttf-rubik-vf
  ttf-twemoji
)

# Direct download URLs for optional fonts (from official GitHub repos)
# These are used as fallback when AUR packages are unavailable
declare -A FONT_FALLBACK_URLS=(
  ["otf-space-grotesk"]="https://github.com/floriankarsten/space-grotesk/raw/master/fonts/ttf/SpaceGrotesk%5Bwght%5D.ttf"
  ["ttf-gabarito-git"]="https://github.com/google/fonts/raw/main/ofl/gabarito/Gabarito%5Bwght%5D.ttf"
  ["ttf-readex-pro"]="https://raw.githubusercontent.com/ThomasJockin/readexpro/master/fonts/variable/Readexpro%5BHEXP%2Cwght%5D.ttf"
  ["ttf-rubik-vf"]="https://github.com/googlefonts/rubik/raw/main/fonts/variable/Rubik%5Bwght%5D.ttf"
  ["ttf-oxanium"]="https://github.com/google/fonts/raw/main/ofl/oxanium/Oxanium%5Bwght%5D.ttf"
)

# Function to install font from direct URL
install_font_fallback() {
  local font_name="$1"
  local url="${FONT_FALLBACK_URLS[$font_name]}"
  
  if [[ -z "$url" ]]; then
    return 1
  fi
  
  local font_dir="$HOME/.local/share/fonts"
  mkdir -p "$font_dir"
  
  log_info "Downloading $font_name from fallback URL..."
  if curl -fsSL -o "$font_dir/${font_name}.ttf" "$url" 2>/dev/null; then
    fc-cache -f "$font_dir" 2>/dev/null
    log_success "Installed $font_name from fallback"
    return 0
  fi
  return 1
}

# Millennium (Steam theming) is opt-in — not installed automatically.
# Users who want Steam Material-Theme can install millennium-bin manually.

# Add other AUR packages based on flags
if $INSTALL_FONTS; then
  AUR_PACKAGES+=(
    adw-gtk-theme         # Official repo version if available, else AUR
    capitaine-cursors
    whitesur-icon-theme   # Try non-git version first
    darkly-bin
  )
fi

if $INSTALL_AUDIO; then
  : # cava moved to alis-audio PKGBUILD
fi

if $INSTALL_TOOLKIT; then
  AUR_PACKAGES+=(uv)
fi

# Reset installflags for AUR helper
installflags="--needed"
$ask || installflags="$installflags --noconfirm"

if [[ ${#REQUIRED_AUR_PACKAGES[@]} -gt 0 ]]; then
  log_info "Installing required AUR packages: ${REQUIRED_AUR_PACKAGES[*]}"
  if ! v $AUR_HELPER -S $installflags "${REQUIRED_AUR_PACKAGES[@]}"; then
    log_error "Failed to install required AUR packages: ${REQUIRED_AUR_PACKAGES[*]}"
    return 1
  fi
fi

# Install main AUR packages (these are the only ones that need AUR)
if [[ ${#AUR_PACKAGES[@]} -gt 0 ]]; then
  log_info "Installing ${#AUR_PACKAGES[@]} AUR packages..."
  v $AUR_HELPER -S $installflags "${AUR_PACKAGES[@]}" || {
    log_warning "Some AUR packages failed — trying individually..."
    for pkg in "${AUR_PACKAGES[@]}"; do
      $AUR_HELPER -S $installflags "$pkg" 2>/dev/null || \
        log_warning "Could not install $pkg (non-critical)"
    done
  }
fi

# Install fonts separately with proper error handling
if $INSTALL_FONTS; then
  tui_info "Installing critical fonts..."
  
  # Critical fonts - must succeed
  for font in "${CRITICAL_FONTS[@]}"; do
    if ! $AUR_HELPER -S $installflags "$font" 2>/dev/null; then
      log_error "CRITICAL: Failed to install $font — UI icons may not work!"
      log_warning "Try: $AUR_HELPER -S $font"
    fi
  done
  
  tui_info "Installing optional fonts..."
  
  # Optional fonts - try AUR first, then fallback
  for font in "${OPTIONAL_FONTS[@]}"; do
    if ! $AUR_HELPER -S $installflags "$font" 2>/dev/null; then
      log_info "$font not in AUR, trying direct download..."
      if ! install_font_fallback "$font"; then
        log_warning "$font unavailable — system will use fallback fonts"
      fi
    fi
  done
fi

#####################################################################################
# Optional: Python environment setup
#####################################################################################
showfun install-python-packages
v install-python-packages

#####################################################################################
# Register dependencies with pacman via meta-package
# This prevents "clean orphans" from removing Alis's installed dependencies.
# The staged meta-package contains no files — only dependency declarations for
# packages that are actually present after this install run.
#####################################################################################
tui_info "Registering dependencies with pacman..."

_meta_dir="./sdata/dist-arch/alis-deps"
if [[ -f "$_meta_dir/PKGBUILD" ]]; then
  _alis_ver="$(cat ./VERSION 2>/dev/null || echo '2.29.3')"
  _meta_build_dir="$(mktemp -d)"

  # Build from a staged recipe so setup never rewrites a tracked PKGBUILD just
  # to inject the current VERSION into the dependency-tracker package.
  if cp -- "$_meta_dir/PKGBUILD" "$_meta_build_dir/PKGBUILD"; then
    sed -i "s/^pkgver=.*/pkgver=${_alis_ver}/" "$_meta_build_dir/PKGBUILD"

    (
      cd "$_meta_build_dir"

      # A user may explicitly disable dependency groups, and optional/AUR
      # packages may be unavailable. Track only dependencies that pacman says
      # are installed so the tracker never needs --nodeps and cannot leave the
      # local package database with intentionally unsatisfied dependencies.
      if source ./PKGBUILD; then
        _meta_installed_deps=()
        for _meta_dep in "${depends[@]}"; do
          _meta_pkg="${_meta_dep%%[<>=]*}"
          if pacman -Q "$_meta_pkg" >/dev/null 2>&1; then
            _meta_installed_deps+=("$_meta_dep")
          fi
        done

        if ! python3 - ./PKGBUILD "${_meta_installed_deps[@]}" <<'PY'
from pathlib import Path
import shlex
import sys

path = Path(sys.argv[1])
deps = sys.argv[2:]
text = path.read_text()
start = text.find("depends=(")
if start < 0:
    raise SystemExit("dependency tracker PKGBUILD has no depends array")
body_start = start + len("depends=(")
end = text.find("\n)\n", body_start)
if end < 0:
    raise SystemExit("dependency tracker PKGBUILD has an unterminated depends array")
replacement = "depends=(\n" + "".join(f"  {shlex.quote(dep)}\n" for dep in deps) + ")"
path.write_text(text[:start] + replacement + text[end + 2:])
PY
        then
          log_warning "Could not filter meta-package dependencies — orphan protection unavailable"
          exit 0
        fi

        log_info "Tracking ${#_meta_installed_deps[@]} installed dependencies with alis-deps"
      else
        log_warning "Could not read staged meta-package recipe — orphan protection unavailable"
        exit 0
      fi

      # -d: dependency installation was already handled above; package metadata
      # itself still contains only dependencies that are currently satisfied.
      # -f: force rebuild if a package archive already exists.
      # -C: clean build dir first.
      if makepkg -dfC 2>/dev/null; then
        local_pkg=(*.pkg.tar.zst)
        if [[ -f "${local_pkg[0]}" ]]; then
          # Reinstall even at the same pkgver/pkgrel so changing --no-* choices
          # refreshes the dependency metadata recorded by pacman.
          if pkg_sudo pacman -U --noconfirm "${local_pkg[0]}" 2>/dev/null; then
            log_success "Meta-package alis-deps registered — orphan cleaner will skip Alis deps"
          else
            log_warning "Could not register meta-package — orphan protection unavailable"
          fi
        fi
      else
        log_warning "Could not build meta-package — orphan protection unavailable"
      fi
    )
  else
    log_warning "Could not stage meta-package recipe — orphan protection unavailable"
  fi

  rm -rf -- "$_meta_build_dir"
else
  log_warning "Meta-package PKGBUILD not found at $_meta_dir"
fi
unset _meta_dir _meta_build_dir _alis_ver

#####################################################################################
# Post-install: Check for Qt/Quickshell ABI mismatch
# pacman -Syu may update Qt while quickshell-git/quickshell-bin (AUR) was built
# against the old Qt. Quickshell uses Qt private APIs, so minor bumps break ABI.
#####################################################################################
if command -v qs >/dev/null 2>&1; then
  qs_abi_output="$(timeout 5 env QT_QPA_PLATFORM=offscreen qs --version 2>&1 || true)"
  if echo "$qs_abi_output" | grep -qiE "built against Qt|Qt.*mismatch|incompatible Qt"; then
    log_warning "Qt/Quickshell ABI mismatch detected!"
    log_warning "Quickshell was built against a different Qt version than what is installed."
    log_warning "The shell will crash until quickshell is rebuilt."

    qs_rebuild_pkg=""
    if pacman -Qi quickshell-git &>/dev/null; then
      qs_rebuild_pkg="quickshell-git"
    elif pacman -Qi quickshell-bin &>/dev/null; then
      qs_rebuild_pkg="quickshell-bin"
    fi

    if [[ -n "$qs_rebuild_pkg" && -n "${AUR_HELPER:-}" ]]; then
      # Determine correct rebuild method:
      # - Foreign/AUR package: --rebuild triggers source compilation
      # - Binary repo (CachyOS, chaotic-aur): -Sa forces AUR source build
      qs_rebuild_cmd=""
      if pacman -Qm "$qs_rebuild_pkg" &>/dev/null; then
        qs_rebuild_cmd="$AUR_HELPER -S --rebuild --noconfirm $qs_rebuild_pkg"
      else
        qs_rebuild_cmd="$AUR_HELPER -Sa --noconfirm $qs_rebuild_pkg"
      fi

      do_rebuild=false
      if ! $ask; then
        do_rebuild=true
      elif tui_confirm "Rebuild $qs_rebuild_pkg for current Qt version?"; then
        do_rebuild=true
      fi

      if $do_rebuild; then
        log_info "Running: $qs_rebuild_cmd"
        if eval "$qs_rebuild_cmd"; then
          log_success "Rebuilt $qs_rebuild_pkg — ABI mismatch resolved"
        else
          log_error "Rebuild failed. Try manually: ${qs_rebuild_cmd/--noconfirm /}"
        fi
      else
        log_warning "To fix: ${qs_rebuild_cmd/--noconfirm /}"
      fi
    elif [[ -n "$qs_rebuild_pkg" ]]; then
      log_warning "To fix: yay -Sa $qs_rebuild_pkg  (forces AUR source build; or use paru)"
    else
      log_warning "Reinstall quickshell from official repos: sudo pacman -S quickshell"
    fi
  fi
fi

log_success "Dependencies installed"
