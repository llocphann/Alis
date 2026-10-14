#!/usr/bin/env bash
# BRAND-R01: safely prepare canonical runtime without starting or stopping services.
# Requires owner approval for file staging; live cutover remains a separate action.
set -euo pipefail
mode=dry-run; approved=false
for arg in "$@"; do
    case "$arg" in
        --dry-run) mode=dry-run ;;
        --apply) mode=apply ;;
        --owner-approved) approved=true ;;
        -h|--help) echo 'Usage: brand-canonical-stage.sh [--dry-run | --apply --owner-approved]'; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done
[[ $EUID -ne 0 ]] || { echo 'Do not stage as root' >&2; exit 2; }
[[ "$mode" != apply || "$approved" == true ]] ||
    { echo 'Staging requires explicit --apply --owner-approved' >&2; exit 2; }
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
target="$cfg/quickshell/alis"
parent="$cfg/quickshell"
old_service='in''ir.service'
for path in "$repo/shell.qml" "$repo/scripts/alis" \
    "$repo/assets/systemd/alis.service" "$repo/sdata/lib/runtime-payload.py" \
    "$repo/native/scripts/install-runtime.sh"; do
    [[ -f "$path" && ! -L "$path" ]] ||
        { echo "Missing or symlinked source artifact: $path" >&2; exit 2; }
done
grep -Fxq '//@ pragma ShellId alis' "$repo/shell.qml" &&
grep -Fq '# Canonical CLI and runtime name is Alis.' "$repo/scripts/alis" ||
    { echo 'Source checkout is not canonical Alis' >&2; exit 2; }
for cmd in python3 rsync systemctl; do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 2; }
done
launcher="$(command -v alis || true)"
[[ -n "$launcher" && -f "$launcher" && ! -L "$launcher" ]] &&
grep -Fq '# Canonical CLI and runtime name is Alis.' "$launcher" ||
    { echo 'A trusted canonical Alis CLI must be installed separately' >&2; exit 2; }
# Only repo-copy installations; packages must be upgraded by their manager.
for version in "$cfg/inir/version.json" "$cfg/illogical-impulse/version.json" "$cfg/alis/version.json"; do
    if [[ -f "$version" ]] &&
       grep -Eq '"(installMode|install_mode|updateStrategy|update_strategy|packageManager|package_manager)"[[:space:]]*:[[:space:]]*"(package-managed|package-manager|nix|pacman|aur|arch)"' "$version"; then
        echo "Package-managed install detected: $version" >&2; exit 2
    fi
done
[[ ! -L "$parent" && ! -L "$target" ]] ||
    { echo 'Symlinked installed runtime requires manual review' >&2; exit 2; }
if [[ -e "$target" ]]; then
    if [[ -d "$target" && -f "$target/shell.qml" ]] &&
       grep -Fxq '//@ pragma ShellId alis' "$target/shell.qml" &&
       [[ -f "$target/qmldir" && -f "$target/setup" && -f "$target/modules/common/Config.qml" ]]; then
        complete=true
        for bin in alis-inputd alis-mpdd alis-native alis-theme; do
            [[ -x "$target/native/bin/$bin" ]] || complete=false
        done
        if [[ "$complete" == true ]]; then
            echo "ALREADY STAGED: $target (no modifications)"
            echo 'Next: inspect brand-canonical-cutover.sh --dry-run; service ownership remains unchanged.'
            exit 0
        fi
    fi
    echo "Existing/partial Alis runtime is user-owned; refuse overwrite: $target" >&2
    exit 2
fi
[[ ! -e "$target" && ! -L "$target" ]] || exit 2
[[ -f "$cfg/systemd/user/$old_service" && ! -L "$cfg/systemd/user/$old_service" ]] ||
    { echo 'No old repo-copy user service; package-managed upgrades need a different path' >&2; exit 2; }
old_active="$(systemctl --user is-active "$old_service" 2>/dev/null || true)"
new_active="$(systemctl --user is-active alis.service 2>/dev/null || true)"
[[ "$new_active" != active ]] ||
    { echo 'Alis service already running; refuse to stage into a live session' >&2; exit 2; }
printf 'Source: %s\nNew runtime: %s\nOld owner: %s; new owner: %s\n' \
    "$repo" "$target" "$old_active" "$new_active"
if [[ "$mode" == dry-run ]]; then
    echo 'DRY-RUN: no files or services changed.'
    exit 0
fi
command -v cargo >/dev/null ||
    { echo 'Cargo is required to prepare the native Alis binaries' >&2; exit 2; }
mkdir -p -- "$parent"
stage="$(mktemp -d "$parent/.alis-brand-stage.XXXXXXXX")"
cleanup() { [[ -z "${stage:-}" || ! -d "$stage" ]] || rm -rf -- "$stage"; }
trap cleanup EXIT
# Copy the existing signed-off payload policy; no data directories are merged.
python3 "$repo/sdata/lib/runtime-payload.py" copy --root "$repo" --target "$stage"
CARGO_TARGET_DIR="$stage/.native-build" \
    bash "$repo/native/scripts/install-runtime.sh" --dest "$stage/native/bin"
rm -rf -- "$stage/.native-build"
for bin in alis-inputd alis-mpdd alis-native alis-theme; do
    [[ -x "$stage/native/bin/$bin" ]] ||
        { echo "Missing staged binary: $bin" >&2; exit 1; }
done
[[ -f "$stage/shell.qml" && -f "$stage/qmldir" && -f "$stage/setup" ]] ||
    { echo 'Incomplete staged QML payload' >&2; exit 1; }
grep -Fxq '//@ pragma ShellId alis' "$stage/shell.qml" || exit 1
[[ ! -e "$target" && ! -L "$target" ]] ||
    { echo 'Concurrent Alis runtime appeared; refusing overwrite' >&2; exit 2; }
mv -T -- "$stage" "$target"
stage=''
echo "STAGED: $target"
echo 'No service, Niri keybind, preferences, cache, state or first-run marker was modified.'
echo 'Review brand-canonical-cutover.sh --dry-run before any owner-approved service switch.'
