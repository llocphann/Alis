#!/usr/bin/env bash
# BRAND-R01 repo-copy post-success service rollback; data namespaces untouched.
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
[[ -f "$legacy" && ! -L "$legacy" && -f "$canonical" && ! -L "$canonical" ]] ||
  { echo 'Missing or symlinked user unit: review the original install mode' >&2; exit 2; }
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' "$canonical" ||
  { echo 'Alis unit missing singleton tray watcher' >&2; exit 2; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo/scripts/brand-recovery-cli.sh"
brand_verify_recovery_cli "$legacy" "$cfg"
old_active="$(systemctl --user is-active inir.service 2>/dev/null || true)"
new_active="$(systemctl --user is-active alis.service 2>/dev/null || true)"
[[ "$new_active" == active && "$old_active" != active ]] ||
  { echo "Expected one Alis owner (old=$old_active new=$new_active)" >&2; exit 2; }
old_links=(); new_links=()
while IFS= read -r -d '' dir; do
  new="$dir/alis.service"; old="$dir/inir.service"
  [[ -L "$new" ]] || continue
  [[ "$(readlink -f -- "$new")" == "$(readlink -f -- "$canonical")" ]] ||
    { echo "Foreign Alis wants symlink: $new" >&2; exit 2; }
  [[ ! -e "$old" && ! -L "$old" ]] ||
    { echo "Foreign legacy wants entry: $old" >&2; exit 2; }
  new_links+=("$new"); old_links+=("$old")
done < <(find "$units" -maxdepth 1 -type d -name '*.wants' -print0)
printf 'Previous=%s Canonical=%s Rewire=%d\n' "$old_active" "$new_active" "${#new_links[@]}"
if [[ "$mode" == dry-run ]]; then
  echo 'DRY-RUN: no writes; live Niri still requires owner approval.'
  exit 0
fi
success=false; swapped=0
recover() {
  rc=$?
  trap - EXIT
  if [[ "$success" != true ]]; then
    systemctl --user stop inir.service >/dev/null 2>&1 || true
    for ((i=0; i<swapped; i++)); do
      if [[ -L "${old_links[i]}" ]] &&
         [[ "$(readlink -f -- "${old_links[i]}")" == "$(readlink -f -- "$legacy")" ]]; then
        rm -- "${old_links[i]}" || true
      fi
      if [[ ! -e "${new_links[i]}" && ! -L "${new_links[i]}" ]]; then
        ln -s -- "$canonical" "${new_links[i]}" || true
      fi
    done
    systemctl --user daemon-reload >/dev/null 2>&1 || true
    systemctl --user start alis.service >/dev/null 2>&1 ||
      echo 'BLOCKER: manual Alis recovery required' >&2
    echo "Previous service rollback failed ($rc); no data was removed" >&2
  fi
  exit "$rc"
}
trap recover EXIT
systemctl --user stop alis.service
[[ "$(systemctl --user is-active alis.service 2>/dev/null || true)" != active ]] ||
  { echo 'Alis remained active; refusing to start old service' >&2; exit 1; }
for i in "${!new_links[@]}"; do
  rm -- "${new_links[i]}"
  swapped=$((i + 1))
  ln -s -- "$legacy" "${old_links[i]}"
done
systemctl --user daemon-reload
systemctl --user start inir.service
[[ "$(systemctl --user is-active inir.service 2>/dev/null || true)" == active &&
   "$(systemctl --user is-active alis.service 2>/dev/null || true)" != active ]] ||
  { echo 'Original service was not exclusively restored' >&2; exit 1; }
success=true
echo 'SUCCESS: previous inir.service is the sole owner; original and Alis data unchanged.'
