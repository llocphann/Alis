#!/usr/bin/env bash
# Explicit, one-owner service migration for developer/repo-copy installations.
# No actions are taken without --apply --owner-approved.
set -euo pipefail
mode=dry-run; approved=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) mode=dry-run ;;
    --apply) mode=apply ;;
    --owner-approved) approved=true ;;
    -h|--help) echo 'Usage: brand-canonical-cutover.sh [--dry-run | --apply --owner-approved]'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
[[ $EUID -ne 0 ]] || { echo 'Do not run as root' >&2; exit 2; }
[[ "$mode" != apply || "$approved" == true ]] || {
  echo 'Apply requires explicit --owner-approved.' >&2; exit 2;
}
command -v systemctl >/dev/null || exit 2
command -v alis >/dev/null || { echo 'Canonical alis executable missing' >&2; exit 2; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
user_units="$cfg/systemd/user"
old_unit="$user_units/inir.service"
new_unit="$user_units/alis.service"
template="$repo/assets/systemd/alis.service"
launcher="$(command -v alis)"
[[ -f "$template" ]] || { echo 'Missing new service template' >&2; exit 2; }
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' "$template" ||
  { echo 'Template is missing tray D-Bus singleton ownership' >&2; exit 2; }
[[ -f "$cfg/quickshell/alis/shell.qml" ]] &&
grep -Fxq '//@ pragma ShellId alis' "$cfg/quickshell/alis/shell.qml" ||
  { echo 'Canonical Alis runtime is not staged' >&2; exit 2; }
[[ ! -e "$new_unit" && ! -L "$new_unit" ]] ||
  { echo "Existing Alis service is user-owned: $new_unit" >&2; exit 2; }
old_active="$(systemctl --user is-active inir.service 2>/dev/null || true)"
new_active="$(systemctl --user is-active alis.service 2>/dev/null || true)"
[[ "$new_active" != active ]] || { echo 'Alis already active; refusing cutover' >&2; exit 2; }
[[ -f "$old_unit" ]] || { echo 'No existing inir.service; fresh installs use normal setup' >&2; exit 2; }
# Package-managed upgrades must be performed declaratively by their manager.
version="$cfg/inir/version.json"
if [[ -f "$version" ]] && grep -Eq '"update[_S]trategy"[[:space:]]*:[[:space:]]*"package-manager"' "$version"; then
  echo 'Package-managed installation: upgrade using Arch or Nix; no mutable unit edits.' >&2
  exit 2
fi
roots=("${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CACHE_HOME:-$HOME/.cache}"
       "${XDG_DATA_HOME:-$HOME/.local/share}" "${XDG_STATE_HOME:-$HOME/.local/state}")
sources=(); destinations=(); aliases=()
for root in "${roots[@]}"; do
  old="$root/inir"; new="$root/alis"
  [[ -d "$old" && ! -L "$old" ]] || continue
  alias=false
  if [[ -L "$new" && "$(readlink -f -- "$new")" == "$(readlink -f -- "$old")" ]]; then
    alias=true
  elif [[ -e "$new" || -L "$new" ]]; then
    echo "Foreign Alis data root, refusing overwrite: $new" >&2; exit 2
  fi
  sources+=("$old"); destinations+=("$new"); aliases+=("$alias")
done
old_wants=(); new_wants=()
while IFS= read -r -d '' dir; do
  p="$dir/inir.service"
  [[ -L "$p" ]] || continue
  [[ "$(readlink -f -- "$p")" == "$(readlink -f -- "$old_unit")" ]] ||
    { echo "Foreign service link: $p" >&2; exit 2; }
  [[ ! -e "$dir/alis.service" && ! -L "$dir/alis.service" ]] ||
    { echo "Foreign Alis wants link: $dir/alis.service" >&2; exit 2; }
  old_wants+=("$p"); new_wants+=("$dir/alis.service")
done < <(find "$user_units" -maxdepth 1 -type d -name '*.wants' -print0)
printf 'Old service: %s | New service: %s | data roots: %d | wants links: %d\n' \
  "$old_active" "$new_active" "${#sources[@]}" "${#old_wants[@]}"
if [[ "$mode" == dry-run ]]; then
  for i in "${!sources[@]}"; do printf 'COPY %s -> %s\n' "${sources[i]}" "${destinations[i]}"; done
  echo 'DRY-RUN: no modifications.'
  exit 0
fi
backup="${XDG_STATE_HOME:-$HOME/.local/state}/alis/cutover-backup-$(date +%Y%m%d%H%M%S)-$$"
mkdir -p "$backup"
copied=(); moved_aliases=(); new_links=(); unit_created=false; stopped=false; success=false
rollback() {
  rc=$?
  trap - EXIT
  if [[ "$success" != true ]]; then
    systemctl --user stop alis.service >/dev/null 2>&1 || true
    for link in "${new_links[@]}"; do rm -f -- "$link"; done
    for old in "${old_wants[@]}"; do
      [[ -e "$old" || -L "$old" ]] || ln -s "$old_unit" "$old" || true
    done
    if [[ "$unit_created" == true ]]; then rm -f -- "$new_unit"; fi
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    if [[ "$stopped" == true && "$old_active" == active ]]; then
      systemctl --user start inir.service >/dev/null 2>&1 ||
        echo 'WARNING: old service restart failed; owner recovery needed' >&2
    fi
    echo "Cutover failed (exit $rc). New user data copies retained at original destinations." >&2
    echo "Recovery backups: $backup" >&2
  fi
  exit "$rc"
}
trap rollback EXIT
for i in "${!sources[@]}"; do
  dst="${destinations[i]}"
  if [[ "${aliases[i]}" == true ]]; then
    mv -- "$dst" "$backup/alias-$i"
    moved_aliases+=("$dst")
  fi
  cp -a -- "${sources[i]}" "$dst"
  copied+=("$dst")
done
systemctl --user stop inir.service
stopped=true
[[ "$(systemctl --user is-active inir.service 2>/dev/null || true)" != active ]] ||
  { echo 'Legacy process owner did not stop' >&2; exit 1; }
mkdir -p "$user_units"
escaped="${launcher//&/\\&}"
sed -e "s|^ExecStart=.*|ExecStart=$escaped run --session|" \
    -e "s|^ExecStopPost=-.*|ExecStopPost=-$escaped cleanup-orphans|" \
    "$template" > "$new_unit"
unit_created=true
for i in "${!old_wants[@]}"; do
  rm -- "${old_wants[i]}"
  ln -s -- "$new_unit" "${new_wants[i]}"
  new_links+=("${new_wants[i]}")
done
systemctl --user daemon-reload
systemctl --user start alis.service
[[ "$(systemctl --user is-active alis.service 2>/dev/null || true)" == active ]] ||
  { echo 'New Alis service did not start successfully' >&2; exit 1; }
[[ "$(systemctl --user is-active inir.service 2>/dev/null || true)" != active ]] ||
  { echo 'Legacy owner reactivated unexpectedly' >&2; exit 1; }
success=true
echo 'SUCCESS: alis.service is the sole active systemd shell owner.'
echo 'Legacy user data and service unit retained for explicit rollback.'
