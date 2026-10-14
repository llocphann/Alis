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
# Do not switch service ownership to a stale public forwarding wrapper or an
# unrelated user-created executable. This cutover is only for repo-copy installs.
[[ -f "$launcher" && ! -L "$launcher" ]] &&
grep -Fq '# Canonical CLI and runtime name is Alis.' "$launcher" ||
  { echo "Installed alis is not the canonical runtime CLI: $launcher" >&2; exit 2; }
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
# Preflight *effective* Niri includes. Previously, owner's 90-user-extra.kdl
# still spawned inir and shadowed 70-binds. Refuse to cut over while any
# active keybind/startup still depends on the retired executable.
niri_root="$cfg/niri/config.kdl"
# Resolve EVERY active include rather than guessing the names of a few KDL
# fragments. An owner override can shadow a safe default under any filename.
# Treat unknown/missing/unreadable includes as blockers, not as safe absence.
if [[ -L "$niri_root" ]]; then
  echo "Niri root is a symlink; review it before cutover: $niri_root" >&2
  exit 2
fi
if [[ -f "$niri_root" ]]; then
  niri_dir="$(realpath -e -- "$cfg/niri")"
  niri_bind_files=("$niri_root")
  declare -A seen_niri_files=()
  for ((index=0; index<${#niri_bind_files[@]}; index++)); do
    path="${niri_bind_files[index]}"
    [[ -f "$path" && ! -L "$path" ]] ||
      { echo "Unsafe/missing Niri config include: $path" >&2; exit 2; }
    [[ -z "${seen_niri_files[$path]:-}" ]] || continue
    seen_niri_files["$path"]=1
    # The actual command may be the first argument to spawn, or be inside
    # a shell -c override. A retired executable cannot survive the handoff.
    if grep -Ev '^[[:space:]]*(//|#)' "$path" |
       grep -Eq 'spawn "([^"]*/)?inir"([[:space:]]|;)|exec ([^[:space:]]*/)?inir([[:space:]]|\\")|spawn "(sh|bash|/bin/sh|/bin/bash)" "[^"]*-c" "[^"]*inir([[:space:]]|\\")'; then
      echo "Active Niri shortcut still invokes disabled inir: $path" >&2
      echo "Repair the bound command to alis, then rerun --dry-run." >&2
      exit 2
    fi
    declared_includes="$(grep -Ec '^[[:space:]]*include[[:space:]]+' "$path" || true)"
    parsed_includes="$(sed -nE 's/^[[:space:]]*include[[:space:]]+"([^"]+)".*$/\1/p' "$path" | wc -l)"
    if [[ "$declared_includes" != "$parsed_includes" ]]; then
      echo "Unrecognized active Niri include syntax: $path" >&2
      exit 2
    fi
    while IFS= read -r fragment; do
      [[ -n "$fragment" ]] || continue
      case "$fragment" in
        /*|../*|*/../*|*/..|*/./*|*/.) echo "Unsafe Niri include path: $fragment" >&2; exit 2 ;;
      esac
      candidate="$cfg/niri/$fragment"
      # A nested include can be resolved relative to its including file on
      # some Niri versions; fail closed if both paths exist and disagree.
      nested="$(dirname -- "$path")/$fragment"
      if [[ "$candidate" != "$nested" && -f "$candidate" && -f "$nested" ]]; then
        if [[ "$(realpath -e -- "$candidate")" != "$(realpath -e -- "$nested")" ]]; then
          echo "Ambiguous Niri include: $fragment (from $path)" >&2
          exit 2
        fi
      elif [[ ! -f "$candidate" && -f "$nested" ]]; then
        candidate="$nested"
      fi
      [[ -f "$candidate" && ! -L "$candidate" ]] ||
        { echo "Unresolved Niri include: $candidate" >&2; exit 2; }
      normalized="$(realpath -e -- "$candidate")"
      [[ "$normalized" == "$niri_dir/"* ]] ||
        { echo "Niri include leaves config root: $candidate" >&2; exit 2; }
      niri_bind_files+=("$normalized")
    done < <(sed -nE 's/^[[:space:]]*include[[:space:]]+"([^"]+)".*$/\1/p' "$path")
  done
fi
# Package ownership may be recorded under any historical config root.
# Checking only /inir can incorrectly treat an Arch/Nix installation as a
# mutable repo-copy install; inspect all previously supported namespaces.
for version in "$cfg/inir/version.json" "$cfg/illogical-impulse/version.json" "$cfg/alis/version.json"; do
  if [[ -f "$version" ]] && grep -Eq '"(update_strategy|updateStrategy|package_manager|packageManager)"[[:space:]]*:[[:space:]]*"(package-manager|nix|pacman|aur|arch)"' "$version"; then
    echo "Package-managed installation metadata detected: $version" >&2
    echo 'Upgrade declaratively using Arch/Nix; no mutable user-unit edits.' >&2
    exit 2
  fi
done
roots=("${XDG_CONFIG_HOME:-$HOME/.config}" "${XDG_CACHE_HOME:-$HOME/.cache}"
       "${XDG_DATA_HOME:-$HOME/.local/share}" "${XDG_STATE_HOME:-$HOME/.local/state}")
sources=(); destinations=(); aliases=()
for root in "${roots[@]}"; do
  # The original upstream config was illogical-impulse; later compatibility
  # installs used inir. Both remain untouched, even after successful cutover.
  # Prefer the actual upstream config.json, but refuse divergent config.json
  # copies instead of guessing which user's edits should win.
  old="$root/inir"
  upstream="$root/illogical-impulse"
  new="$root/alis"
  if [[ "$root" == "$cfg" && -f "$upstream/config.json" && ! -L "$upstream" ]]; then
    if [[ -f "$old/config.json" ]] &&
       ! cmp -s -- "$upstream/config.json" "$old/config.json"; then
      echo "Conflicting iNiR/illogical-impulse configs; review before cutover: $upstream and $old" >&2
      exit 2
    fi
    old="$upstream"
  elif [[ ! -d "$old" && -d "$upstream" && ! -L "$upstream" ]]; then
    old="$upstream"
  fi
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
# Backups must NOT create XDG_STATE_HOME/alis before the canonical state
# directory is copied; otherwise cp -a nests inir *inside* alis.
backup="${XDG_STATE_HOME:-$HOME/.local/state}/alis-cutover-backups/cutover-backup-$(date +%Y%m%d%H%M%S)-${BASHPID}"
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
    for i in "${!destinations[@]}"; do
      if [[ "${aliases[i]}" == true && -L "$backup/alias-$i" ]]; then
        if [[ -e "${destinations[i]}" || -L "${destinations[i]}" ]]; then
          mv -- "${destinations[i]}" "$backup/copied-root-$i" || true
        fi
        mv -- "$backup/alias-$i" "${destinations[i]}" || true
      fi
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
