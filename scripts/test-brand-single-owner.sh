#!/usr/bin/env bash
# BRAND-R01 R5: static, non-destructive session ownership contract.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
fail() { printf 'FAIL: BRAND-R01 single-owner: %s\n' "$*" >&2; exit 1; }
identity=alis
[[ "$(grep -cFx '//@ pragma ShellId alis' shell.qml)" -eq 1 ]] || fail 'canonical Quickshell selector missing or duplicated'
[[ ! -e assets/systemd/inir.service && ! -L assets/systemd/inir.service ]] || fail 'two shipped owner templates'
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' assets/systemd/alis.service || fail 'tray watcher ownership changed'
grep -Fxq 'ExecStart=/usr/bin/alis run --session' assets/systemd/alis.service || fail 'session does not use canonical CLI'
grep -Fxq 'ExecStopPost=-/usr/bin/alis cleanup-orphans' assets/systemd/alis.service || fail 'canonical cleanup owner missing'
for package in Makefile distro/arch/alis-shell/PKGBUILD distro/arch/alis-shell-git/PKGBUILD; do
    grep -Fq 'assets/systemd/alis.service' "$package" || fail "canonical owner missing in $package"
done
grep -Fq 'alis.service' nix/package.nix || fail 'Nix owner missing'
grep -Fq '# Canonical CLI and runtime name is Alis.' scripts/alis || fail 'canonical CLI identity missing'
[[ ! -e scripts/inir ]] || fail 'fresh install ships a second public engine'
grep -Fq 'first_run.txt' services/FirstRunExperience.qml ||
    fail 'First Run identity was reset'
grep -Fq 'welcomeWizard.completed' welcome.qml ||
    fail 'welcome completion marker was changed'
printf 'PASS: one Quickshell selector and systemd owner; canonical Alis engine with retained original first-run markers\n'
