#!/usr/bin/env bash
# Canonical Alis-only runtime and staging contracts (no desktop required).
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

bash -n scripts/alis scripts/brand-canonical-cutover.sh setup
bash -n sdata/subcmd-install/3.files.sh
[[ ! -e scripts/inir ]] || fail 'legacy launcher still shipped'
[[ ! -e assets/systemd/inir.service ]] || fail 'legacy user unit still shipped'
[[ -f assets/systemd/alis.service ]] || fail 'canonical service missing'
grep -Fxq '//@ pragma ShellId alis' shell.qml || fail 'ShellId did not migrate'
grep -Fxq 'BusName=org.kde.StatusNotifierWatcher' assets/systemd/alis.service || fail 'tray owner changed'
grep -Fxq 'ExecStart=/usr/bin/alis run --session' assets/systemd/alis.service || fail 'unit still uses prior launcher'
grep -Fxq 'ExecStopPost=-/usr/bin/alis cleanup-orphans' assets/systemd/alis.service || fail 'unit cleanup incompatible'
grep -Fq 'scripts/brand-canonical-cutover.sh --dry-run' setup || fail 'unsafe update without cutover warning'
grep -Fq "legacy_owner='in''ir.service'" scripts/alis || fail 'no double-shell guard'
grep -Fq "_legacy_owner='in''ir.service'" sdata/subcmd-install/3.files.sh || fail 'new unit could start beside old owner'
[[ -f native/alis-native/Cargo.toml && -f native/alis-inputd/Cargo.toml
   && -f native/alis-theme/Cargo.toml && -f native/alis-mpdd/Cargo.toml
   && -f native/crates/alis-protocol/Cargo.toml ]] || fail 'native crate paths incomplete'
[[ ! -d native/inir-native && ! -d native/inir-inputd && ! -d native/inir-theme
   && ! -d native/inir-mpdd && ! -d native/crates/inir-protocol ]] || fail 'old Cargo crate still present'
grep -Fq 'options.programs.alis' nix/module-common.nix || fail 'Nix program option old'
grep -Fq 'systemd.user.services.alis' nix/nixos-module.nix || fail 'NixOS service old'
grep -Fq 'systemd.user.services.alis' nix/home-module.nix || fail 'Home Manager service old'
grep -Fq 'packages = forAllSystems' flake.nix || fail 'flake package export missing'
[[ "$(grep -c 'makeWrapper "$runtime/scripts/alis" "$out/bin/alis"' nix/package.nix)" -eq 1 ]] || fail 'Nix installs duplicate Alis entrypoint'
[[ -f distro/arch/alis-shell/PKGBUILD && -f distro/arch/alis-shell-git/PKGBUILD ]] || fail 'Arch package rename incomplete'
[[ ! -d distro/arch/inir-shell && ! -d distro/arch/inir-shell-git ]] || fail 'old Arch package path still present'
grep -Fxq 'NoDisplay=true' assets/applications/alis-settings.desktop && fail 'new Settings is hidden'
python3 scripts/brand-canonical-audit.py --strict --limit 1 > "$tmp/identifiers.json" || fail 'active legacy identifiers remain'
make -s install-bin "DESTDIR=$tmp/stage" "PREFIX=/usr" || fail 'Make stage Alis binary'
[[ -x "$tmp/stage/usr/bin/alis" ]] || fail 'Make did not stage Alis CLI'
[[ ! -e "$tmp/stage/usr/bin/inir" ]] || fail 'Make staged retired inir CLI'
make -s uninstall-bin "DESTDIR=$tmp/stage" "PREFIX=/usr" || fail 'Make uninstaller'
[[ ! -e "$tmp/stage/usr/bin/alis" ]] || fail 'Make did not uninstall managed Alis CLI'
printf 'unrelated user-owned command\n' > "$tmp/stage/usr/bin/alis"
make -s uninstall-bin "DESTDIR=$tmp/stage" "PREFIX=/usr" || fail 'Make uninstaller with foreign file'
grep -Fxq 'unrelated user-owned command' "$tmp/stage/usr/bin/alis" || fail 'Make removed foreign executable'
echo 'PASS: Canonical Alis ShellId, singleton unit, Cargo, Nix, Arch, install and safety audit'
