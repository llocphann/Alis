#!/usr/bin/env bash
# Validate the actual immutable source Arch packages, not just local filenames.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
fail() { printf 'FAIL: canonical Arch source: %s\n' "$*" >&2; exit 1; }
pkg="distro/arch/alis-shell/PKGBUILD"
srcinfo="distro/arch/alis-shell/.SRCINFO"
ref="$(sed -n 's/^_source_ref="${ALIS_SOURCE_REF:-\([^}]*\)}"$/\1/p' "$pkg")"
[[ "$ref" =~ ^[0-9a-f]{40}$ ]] || fail 'Arch default source is not an immutable SHA'
git cat-file -e "$ref^{commit}" || fail 'pinned source commit absent'
git merge-base --is-ancestor "$ref" HEAD || fail 'package points to unrelated source'
git show "$ref:shell.qml" | grep -Fxq '//@ pragma ShellId alis' ||
    fail 'pinned source retains legacy Quickshell ShellId'
git show "$ref:assets/systemd/alis.service" |
    grep -Fq 'ExecStart=/usr/bin/alis run --session' ||
    fail 'pinned archive lacks canonical Alis user service'
git cat-file -e "$ref:scripts/alis" || fail 'pinned archive lacks canonical CLI'
if git cat-file -e "$ref:scripts/inir" 2>/dev/null; then
    fail 'pinned archive still carries retired public inir CLI'
fi
for binary in alis-inputd alis-mpdd alis-native alis-theme; do
    git show "$ref:native/scripts/install-runtime.sh" |
        grep -Fq "$binary" || fail "pinned native archive lacks $binary"
done
grep -Fq "https://github.com/llocphann/Alis/archive/$ref.tar.gz" "$srcinfo" ||
    fail '.SRCINFO is not in sync with canonical pinned archive'
for token in 'install -Dm755 "$srcroot/scripts/alis" "$pkgdir/usr/bin/alis"' \
             'install -Dm644 "$srcroot/assets/systemd/alis.service" "$pkgdir/usr/lib/systemd/user/alis.service"'; do
    grep -Fq "$token" "$pkg" || fail "Arch installation contract missing: $token"
done
[[ "$(grep -Fc 'install -Dm755 "$srcroot/scripts/alis" "$pkgdir/usr/bin/alis"' "$pkg")" -eq 1 ]] ||
    fail 'duplicate public CLI installation commands'
echo "PASS: canonical Arch snapshot $ref contains Alis ShellId, unit, CLI and native binaries"
