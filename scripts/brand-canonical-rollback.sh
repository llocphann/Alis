#!/usr/bin/env bash
# Explicit post-success BRAND-R01 owner rollback. Never run without consent.
# The old unit is archived outside systemd's search path while Alis owns the bus.
set -euo pipefail
mode=dry-run; approved=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) mode=dry-run ;;
    --apply) mode=apply ;;
    --owner-approved) approved=true ;;
    -h|--help) echo 'Usage: brand-canonical-rollback.sh [--dry-run | --apply --owner-approved]'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done
[[ "$EUID" -ne 0 ]] || { echo 'Do not run as root' >&2; exit 2; }
[[ "$mode" != apply || "$approved" == true ]] ||
  { echo 'Rollback needs --apply --owner-approved' >&2; exit 2; }
command -v systemctl >/dev/null || exit 2
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
units="$cfg/systemd/user"
legacy="$units/inir.service"
canonical="$units/alis.service"
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/alis-cutover-backups"
retired="$backup_root/retired-inir.service"
# A normal on-disk old unit conflicts with Alis's singleton BusName, even
# if the old process was stopped. Only the mask + verified archive is valid.
[[ -L "$legacy" && "$(readlink -- "$legacy")" == /dev/null ]] ||
  { echo "Original unit not safely masked: $legacy" >&2; exit 2; }
[[ -f "$retired" && ! -L "$retired" && -f "$canonical" && ! -L "$canonical" ]] ||
  { echo 'Missing or unsafe unit/archive; review canonical cutover receipt' >&2; exit 2; }
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' "$canonical" ||
  { echo 'Alis unit missing singleton tray watcher' >&2; exit 2; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/scripts/brand-recovery-cli.sh"
brand_verify_recovery_cli "$retired" "$cfg"
old_active="$(systemctl --user is-active inir.service 2>/dev/null || true)"
new_active="$(systemctl --user is-active alis.service 2>/dev/null || true)"
[[ "$new_active" == active && "$old_active" != active ]] ||
  { echo "Expected sole Alis owner (old=$old_active new=$new_active)" >&2; exit 2; }
old_load="$(systemctl --user show inir.service -p LoadState --value --no-pager 2>/dev/null || true)"
[[ "$old_load" == masked ]] ||
  { echo "Legacy unit is not masked in systemd (state=$old_load)" >&2; exit 2; }
old_links=(); new_links=()
while IFS= read -r -d '' dir; do
  new="$dir/alis.service"; old="$dir/inir.service"
  [[ -L "$new" ]] || continue
  [[ "$(readlink -f -- "$new")" == "$(readlink -f -- "$canonical")" ]] ||
    { echo "Foreign Alis wants symlink: $new" >&2; exit 2; }
  [[ ! -e "$old" && ! -L "$old" ]] ||
    { echo "Foreign original wants entry: $old" >&2; exit 2; }
  new_links+=("$new"); old_links+=("$old")
done < <(find "$units" -maxdepth 1 -type d -name '*.wants' -print0)
printf 'Previous=%s Canonical=%s Rewire=%d; legacy unit archived=%s\n' \
  "$old_active" "$new_active" "${#new_links[@]}" "$retired"
if [[ "$mode" == dry-run ]]; then
  echo 'DRY-RUN: no writes; owner-authorized desktop recovery needed for apply.'
  exit 0
fi
backup="$backup_root/rollback-backup-$(date +%Y%m%d%H%M%S)-${BASHPID}"
mkdir -p "$backup"
cp -p -- "$retired" "$backup/inir.service"
cmp -s -- "$retired" "$backup/inir.service" ||
  { echo 'Recovery archive changed during backup' >&2; exit 2; }
success=false; swapped=0; new_parked=false; legacy_unmasked=false; old_restored=false
recover() {
  rc=$?
  trap - EXIT
  if [[ "$success" != true ]]; then
    systemctl --user stop inir.service >/dev/null 2>&1 || true
    for ((i=0; i<swapped; i++)); do
      if [[ -L "${old_links[i]}" &&
            "$(readlink -f -- "${old_links[i]}")" == "$(readlink -f -- "$legacy")" ]]; then
        rm -- "${old_links[i]}" || true
      fi
      if [[ ! -e "${new_links[i]}" && ! -L "${new_links[i]}" ]]; then
        ln -s -- "$canonical" "${new_links[i]}" || true
      fi
    done
    if [[ "$old_restored" == true && -f "$legacy" && ! -L "$legacy" &&
          ! -e "$retired" && ! -L "$retired" ]] &&
       cmp -s -- "$legacy" "$backup/inir.service"; then
      mv -- "$legacy" "$retired" ||
        echo 'BLOCKER: cannot return original unit to archive' >&2
    fi
    if [[ "$legacy_unmasked" == true && ! -e "$legacy" && ! -L "$legacy" ]]; then
      ln -s /dev/null "$legacy" ||
        echo 'BLOCKER: cannot re-mask original unit' >&2
    fi
    if [[ "$new_parked" == true && ! -e "$canonical" && ! -L "$canonical" &&
          -f "$backup/alis.service" ]]; then
      mv -- "$backup/alis.service" "$canonical" ||
        echo 'BLOCKER: cannot restore canonical unit' >&2
    fi
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user start alis.service >/dev/null 2>&1 ||
      echo "BLOCKER: manual canonical owner recovery needed; receipt $backup" >&2
    echo "Original-owner rollback failed ($rc); data was not removed; receipt $backup" >&2
  fi
  exit "$rc"
}
trap recover EXIT
systemctl --user stop alis.service
[[ "$(systemctl --user is-active alis.service 2>/dev/null || true)" != active ]] ||
  { echo 'Alis remained active; refusing original owner' >&2; exit 1; }
# Remove Alis's singleton allocation BEFORE reintroducing the old unit.
mv -- "$canonical" "$backup/alis.service"
new_parked=true
rm -- "$legacy"
legacy_unmasked=true
mv -- "$retired" "$legacy"
old_restored=true
cmp -s -- "$legacy" "$backup/inir.service" ||
  { echo 'Restored original unit differs from archive' >&2; exit 1; }
for i in "${!new_links[@]}"; do
  rm -- "${new_links[i]}"
  swapped=$((i + 1))
  ln -s -- "$legacy" "${old_links[i]}"
done
systemctl --user daemon-reload
old_load="$(systemctl --user show inir.service -p LoadState --value --no-pager 2>/dev/null || true)"
new_load="$(systemctl --user show alis.service -p LoadState --value --no-pager 2>/dev/null || true)"
[[ "$old_load" == loaded && "$new_load" == not-found ]] ||
  { echo "Original-owner bus allocation not exclusive (old=$old_load Alis=$new_load)" >&2; exit 1; }
systemctl --user start inir.service
[[ "$(systemctl --user is-active inir.service 2>/dev/null || true)" == active &&
   "$(systemctl --user is-active alis.service 2>/dev/null || true)" != active ]] ||
  { echo 'Original service not exclusively restored' >&2; exit 1; }
success=true
echo 'SUCCESS: original inir.service is sole owner; Alis unit archived for recovery.'
echo "Canonical service unit backup: $backup/alis.service"
echo 'Neither canonical nor historical XDG data roots were changed.'
