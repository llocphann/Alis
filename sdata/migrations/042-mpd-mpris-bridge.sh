#!/usr/bin/env bash
# Ensure existing repo-managed Arch installs gain the MPD→MPRIS bridge added
# after initial installation. Package-managed installs own dependencies through
# pacman/AUR package metadata and are intentionally not mutated here.

MIGRATION_ID="042-mpd-mpris-bridge"
MIGRATION_TITLE="Install MPD MPRIS bridge"
MIGRATION_DESCRIPTION="Installs mpd-mpris on repo-managed Arch systems so MPD/rmpc playback is visible to Hadalis Media controls."
MIGRATION_TARGET_FILE="system package: mpd-mpris"
MIGRATION_REQUIRED=true

_mpd_mpris_package_managed() {
  [[ "$(get_installed_update_strategy 2>/dev/null || true)" == "package-manager" ]]
}

_mpd_mpris_arch_host() {
  command -v pacman >/dev/null 2>&1
}

migration_check() {
  _mpd_mpris_package_managed && return 1
  _mpd_mpris_arch_host || return 1
  command -v mpd-mpris >/dev/null 2>&1 && return 1
  return 0
}

migration_preview() {
  echo -e "${STY_GREEN}+ install mpd-mpris${STY_RST}"
  echo "  MPD and rmpc remain unchanged; this only adds the MPRIS bridge used by Hadalis Media."
}

migration_diff() {
  if command -v mpd-mpris >/dev/null 2>&1; then
    echo "mpd-mpris is already available."
  elif _mpd_mpris_package_managed; then
    echo "Package-managed install: dependency ownership remains with the package manager."
  elif _mpd_mpris_arch_host; then
    echo "mpd-mpris is missing from this repo-managed Arch installation."
  else
    echo "mpd-mpris automatic migration is only defined for Arch; no system package will be changed."
  fi
}

migration_apply() {
  if ! migration_check; then
    return 0
  fi

  echo "Installing mpd-mpris for MPD/rmpc Media integration..."
  pkg_sudo pacman -S --needed --noconfirm mpd-mpris || {
    echo -e "${STY_YELLOW}Could not auto-install mpd-mpris.${STY_RST}"
    echo -e "${STY_YELLOW}Install manually: sudo pacman -S mpd-mpris${STY_RST}"
    return 1
  }

  command -v mpd-mpris >/dev/null 2>&1 || {
    echo -e "${STY_YELLOW}mpd-mpris is still unavailable after package installation.${STY_RST}"
    return 1
  }

  # Do not start MPD or change its configuration here. MprisController starts
  # mpd-mpris.service only when a local MPD session actually exists.
  echo "mpd-mpris installed; Hadalis will start the user bridge when MPD is active."
}
