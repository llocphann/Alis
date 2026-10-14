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
# The previous public Alis wrapper delegates into iNiR and is owned by this
# project's compatibility installer. Never require the canonical launcher to
# preexist: this is the very bootstrap stage that installs it.
bin_dir="${XDG_BIN_HOME:-$HOME/.local/bin}"
launcher="$bin_dir/alis"
visible_launcher="$(command -v alis || true)"
[[ -z "$visible_launcher" || "$visible_launcher" == "$launcher" ]] ||
    { echo "A different Alis executable shadows the user launcher: $visible_launcher" >&2; exit 2; }
[[ ! -L "$bin_dir" && ! -L "$launcher" ]] ||
    { echo "Symlinked launcher target requires owner review: $launcher" >&2; exit 2; }
launcher_kind=missing
launcher_hash=''
if [[ -e "$launcher" ]]; then
    [[ -f "$launcher" && -x "$launcher" ]] ||
        { echo "Non-executable/foreign launcher: $launcher" >&2; exit 2; }
    if grep -Fq '# Canonical CLI and runtime name is Alis.' "$launcher"; then
        if cmp -s -- "$launcher" "$repo/scripts/alis"; then
            launcher_kind=canonical
        else
            launcher_kind=canonical-stale
        fi
    elif { grep -Fq '# Alis is the public command while the proven iNiR runtime owns the session.' "$launcher" ||
           grep -Fq '# Alis is the public command while the proven Alis runtime owns the session.' "$launcher"; } &&
         grep -Fq 'export ALIS_INTERNAL_CLI=1' "$launcher" &&
         { grep -Fq 'exec bash "$script_dir/inir" "$@"' "$launcher" ||
           grep -Fq 'exec inir "$@"' "$launcher"; }; then
        launcher_kind=managed-compatibility
    else
        echo "Refusing to overwrite foreign/unknown Alis executable: $launcher" >&2
        exit 2
    fi
    bash -n "$launcher" ||
        { echo "Invalid installed Alis shell launcher: $launcher" >&2; exit 2; }
    launcher_hash="$(sha256sum -- "$launcher" | cut -d ' ' -f1)"
fi
bash -n "$repo/scripts/alis" ||
    { echo 'Canonical source CLI fails shell syntax check' >&2; exit 2; }
# Only repo-copy installations; packages must be upgraded by their manager.
for version in "$cfg/inir/version.json" "$cfg/illogical-impulse/version.json" "$cfg/alis/version.json"; do
    if [[ -f "$version" ]] &&
       grep -Eq '"(installMode|install_mode|updateStrategy|update_strategy|packageManager|package_manager)"[[:space:]]*:[[:space:]]*"(package-managed|package-manager|nix|pacman|aur|arch)"' "$version"; then
        echo "Package-managed install detected: $version" >&2; exit 2
    fi
done
[[ ! -L "$parent" && ! -L "$target" ]] ||
    { echo 'Symlinked installed runtime requires manual review' >&2; exit 2; }
runtime_complete=false
if [[ -e "$target" ]]; then
    if [[ -d "$target" && -f "$target/shell.qml" ]] &&
       grep -Fxq '//@ pragma ShellId alis' "$target/shell.qml" &&
       [[ -f "$target/qmldir" && -f "$target/setup" && -f "$target/modules/common/Config.qml" ]]; then
        complete=true
        for bin in alis-inputd alis-mpdd alis-native alis-theme; do
            [[ -x "$target/native/bin/$bin" ]] || complete=false
        done
        if [[ "$complete" == true ]]; then
            runtime_complete=true
        fi
    fi
    if [[ "$runtime_complete" != true ]]; then
        echo "Existing/partial Alis runtime is user-owned; refuse overwrite: $target" >&2
        exit 2
    fi
fi
# A complete installed Alis runtime is allowed: bootstrap may only need to
# replace the old managed public CLI. Partial/foreign paths were rejected above.
[[ "$runtime_complete" == true || ( ! -e "$target" && ! -L "$target" ) ]] || exit 2
[[ -f "$cfg/systemd/user/$old_service" && ! -L "$cfg/systemd/user/$old_service" ]] ||
    { echo 'No old repo-copy user service; package-managed upgrades need a different path' >&2; exit 2; }
old_active="$(systemctl --user is-active "$old_service" 2>/dev/null || true)"
new_active="$(systemctl --user is-active alis.service 2>/dev/null || true)"
[[ "$new_active" != active ]] ||
    { echo 'Alis service already running; refuse to stage into a live session' >&2; exit 2; }
printf 'Source: %s\nRuntime: %s\nOld owner: %s; new owner: %s\n' \
    "$repo" "$target" "$old_active" "$new_active"
if [[ "$runtime_complete" == true ]]; then
    printf 'ALREADY STAGED: %s (existing runtime untouched)\n' "$target"
else
    printf 'PLAN: stage a new canonical Alis runtime at %s\n' "$target"
fi
printf 'Alis CLI: %s (%s)\n' "$launcher" "$launcher_kind"
if [[ "$launcher_kind" == managed-compatibility || "$launcher_kind" == canonical-stale ]]; then
    echo 'PLAN: back up managed Alis launcher byte-for-byte and refresh source CLI.'
elif [[ "$launcher_kind" == missing ]]; then
    echo 'PLAN: install missing public canonical Alis CLI.'
fi
if [[ "$mode" == dry-run ]]; then
    echo 'DRY-RUN: no files or services changed.'
    exit 0
fi
stage=''
staged_launcher=''
cleanup() {
    [[ -z "$stage" || ! -d "$stage" ]] || rm -rf -- "$stage"
    [[ -z "$staged_launcher" || ! -e "$staged_launcher" ]] || rm -f -- "$staged_launcher"
}
trap cleanup EXIT
if [[ "$runtime_complete" != true ]]; then
    command -v cargo >/dev/null ||
        { echo 'Cargo is required to prepare the native Alis binaries' >&2; exit 2; }
    mkdir -p -- "$parent"
    stage="$(mktemp -d "$parent/.alis-brand-stage.XXXXXXXX")"
    # Copy managed runtime payload into an isolated sibling; no existing
    # installation or personal data is changed until the entire payload passes.
    python3 "$repo/sdata/lib/runtime-payload.py" copy --root "$repo" --target "$stage"
    CARGO_TARGET_DIR="$stage/.native-build" \
        bash "$repo/native/scripts/install-runtime.sh" --dest "$stage/native/bin"
    rm -rf -- "$stage/.native-build"
    for bin in alis-inputd alis-mpdd alis-native alis-theme; do
        [[ -x "$stage/native/bin/$bin" ]] ||
            { echo "Missing staged binary: $bin" >&2; exit 1; }
    done
    [[ -f "$stage/shell.qml" && -f "$stage/qmldir" && -f "$stage/setup" &&
       -f "$stage/modules/common/Config.qml" ]] ||
        { echo 'Incomplete staged QML payload' >&2; exit 1; }
    grep -Fxq '//@ pragma ShellId alis' "$stage/shell.qml" || exit 1
fi

if [[ "$launcher_kind" != canonical ]]; then
    mkdir -p -- "$bin_dir"
    [[ ! -L "$bin_dir" ]] || { echo "User bin directory became a symlink" >&2; exit 2; }
    staged_launcher="$(mktemp "$bin_dir/.alis-cli-stage.XXXXXXXX")"
    install -m755 -- "$repo/scripts/alis" "$staged_launcher"
    bash -n "$staged_launcher" || exit 1
    if [[ "$launcher_kind" == managed-compatibility || "$launcher_kind" == canonical-stale ]]; then
        [[ -f "$launcher" && ! -L "$launcher" &&
           "$(sha256sum -- "$launcher" | cut -d ' ' -f1)" == "$launcher_hash" ]] ||
            { echo 'Installed compatibility launcher changed during staging' >&2; exit 2; }
        backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/alis-cutover-backups"
        mkdir -p -- "$backup_root"
        backup_dir="$(mktemp -d "$backup_root/launcher-XXXXXXXX")"
        cp -p -- "$launcher" "$backup_dir/alis"
        cmp -s -- "$launcher" "$backup_dir/alis" ||
            { echo "Legacy launcher backup failed: $backup_dir" >&2; exit 1; }
        echo "BACKUP: previous managed Alis launcher -> $backup_dir/alis"
    else
        [[ ! -e "$launcher" && ! -L "$launcher" ]] ||
            { echo 'Foreign launcher appeared; refusing overwrite' >&2; exit 2; }
    fi
fi

if [[ "$runtime_complete" != true ]]; then
    [[ ! -e "$target" && ! -L "$target" ]] ||
        { echo 'Concurrent Alis runtime appeared; refusing overwrite' >&2; exit 2; }
    mv -T -- "$stage" "$target"
    stage=''
    echo "STAGED: $target"
fi
if [[ -n "$staged_launcher" ]]; then
    # Never replace a user-created executable or a launcher modified during
    # staging; this only advances an explicitly recognized Alis-owned wrapper.
    if [[ "$launcher_kind" == managed-compatibility || "$launcher_kind" == canonical-stale ]]; then
        [[ -f "$launcher" && ! -L "$launcher" &&
           "$(sha256sum -- "$launcher" | cut -d ' ' -f1)" == "$launcher_hash" ]] ||
            { echo 'Launcher changed after backup; refusing replacement' >&2; exit 2; }
    else
        [[ ! -e "$launcher" && ! -L "$launcher" ]] ||
            { echo 'Unexpected launcher collision before canonical install' >&2; exit 2; }
    fi
    mv -T -- "$staged_launcher" "$launcher"
    staged_launcher=''
    echo "INSTALLED: canonical public CLI -> $launcher"
fi
echo 'No shell service was stopped/started; Niri shortcuts, preferences, data and first-run marker are unchanged.'
echo 'If the old shell is active, public Alis commands now target the staged canonical runtime.'
echo 'Inspect brand-canonical-cutover.sh --dry-run before a separate owner-approved service switch.'
