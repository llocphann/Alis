#!/usr/bin/env bash
# Install the local Music backend for existing repo-managed Arch installs.
# Do not start/enable MPD or create/overwrite user mpd.conf.

MIGRATION_ID="043-local-music-mpd-backend"
MIGRATION_TITLE="Install MPD local Music backend"
MIGRATION_DESCRIPTION="Installs MPD for the Left Sidebar local Music library/player while preserving existing MPD configuration and service state."
MIGRATION_TARGET_FILE="system package: mpd"
MIGRATION_REQUIRED=true

_local_music_package_managed() {
  [[ "$(get_installed_update_strategy 2>/dev/null || true)" == "package-manager" ]]
}

_local_music_arch_host() {
  command -v pacman >/dev/null 2>&1
}

migration_check() {
  _local_music_package_managed && return 1
  _local_music_arch_host || return 1
  command -v mpd >/dev/null 2>&1 && return 1
  return 0
}

migration_preview() {
  echo -e "${STY_GREEN}+ install mpd${STY_RST}"
  echo "  Does not start MPD, enable a service, or write mpd.conf."
}

migration_diff() {
  if command -v mpd >/dev/null 2>&1; then
    echo "mpd is already available."
  elif _local_music_package_managed; then
    echo "Package-managed install: dependency ownership remains with the package manager."
  elif _local_music_arch_host; then
    echo "mpd is missing from this repo-managed Arch installation."
  else
    echo "MPD automatic migration is only defined for Arch; no system package will be changed."
  fi
}

migration_apply() {
  if ! migration_check; then
    return 0
  fi

  echo "Installing MPD for Hadalis local Music..."
  pkg_sudo pacman -S --needed --noconfirm mpd || {
    echo -e "${STY_YELLOW}Could not auto-install mpd.${STY_RST}"
    echo -e "${STY_YELLOW}Install it manually and configure your MPD music_directory.${STY_RST}"
    return 1
  }

  command -v mpd >/dev/null 2>&1 || {
    echo -e "${STY_YELLOW}mpd is still unavailable after package installation.${STY_RST}"
    return 1
  }

  echo "MPD installed. Existing configuration/service state was not changed."
}
