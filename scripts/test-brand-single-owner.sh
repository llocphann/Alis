#!/usr/bin/env bash
# BRAND-R01 R5: static, non-destructive session ownership contract.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
fail() { printf 'FAIL: BRAND-R01 single-owner: %s\n' "$*" >&2; exit 1; }
[[ "$(grep -cFx '//@ pragma ShellId inir' shell.qml)" -eq 1 ]] || fail 'Quickshell selector changed without coordinated cutover'
[[ ! -e assets/systemd/alis.service && ! -L assets/systemd/alis.service ]] ||
    fail 'parallel Alis user service introduced'
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' assets/systemd/inir.service ||
    fail 'tray watcher/DBus ownership changed'
grep -Fxq 'ExecStart=/usr/bin/inir run --session' assets/systemd/inir.service ||
    fail 'legacy inir.service must remain the only session owner until owner cutover'
grep -Fq 'assets/systemd/inir.service' Makefile || fail 'Make no longer installs legacy unit'
grep -Fq 'assets/systemd/inir.service' distro/arch/inir-shell/PKGBUILD ||
    fail 'Arch unit owner drifted'
grep -Fq 'assets/systemd/inir.service' distro/arch/inir-shell-git/PKGBUILD ||
    fail 'Arch-git unit owner drifted'
grep -Fq 'inir.service' nix/package.nix || fail 'Nix service compatibility vanished'
grep -Fq 'exec bash "$script_dir/inir" "$@"' scripts/alis ||
    fail 'Alis must delegate execution to existing inir CLI owner'
grep -Fq 'exec inir "$@"' scripts/alis ||
    fail 'Alis fallback must reuse existing inir CLI owner'
grep -Fq 'first_run.txt' services/FirstRunExperience.qml ||
    fail 'First Run identity was reset'
grep -Fq 'welcomeWizard.completed' welcome.qml ||
    fail 'welcome completion marker was changed'
printf 'PASS: one Quickshell selector and systemd owner; Alis delegates to compatible runtime\n'
