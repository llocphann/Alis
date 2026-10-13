#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf "FAIL: %s\n" "$*" >&2; exit 1; }
bash -n "$repo/scripts/alis" || fail "Alis launcher syntax"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cp "$repo/scripts/alis" "$tmp/alis"
cat > "$tmp/inir" <<'LEGACY'
#!/usr/bin/env bash
printf "<%s>\n" "$@"
LEGACY
output="$(bash "$tmp/alis" status --example "arg with spaces")"
[[ "$output" == $'<status>\n<--example>\n<arg with spaces>' ]] || fail "argument passthrough"
for shell in bash fish zsh; do
    output="$(bash "$repo/scripts/alis" completions "$shell")" || fail "$shell completion lookup"
    case "$shell" in
        bash) grep -Fq "complete -F _inir_completions alis" <<<"$output" || fail "bash registration" ;;
        fish) grep -Fq "complete -c alis " <<<"$output" || fail "fish registration" ;;
        zsh) grep -Fxq "#compdef alis" <<<"$output" || fail "zsh registration" ;;
    esac
done
grep -Fq "Name=Alis Shell" "$repo/assets/applications/inir.desktop" || fail "desktop entry"
grep -Fq "Name=Alis Settings" "$repo/assets/applications/inir-settings.desktop" || fail "settings desktop entry"
grep -Fq 'Translation.tr("Welcome to Alis")' "$repo/welcome.qml" || fail "wizard"
grep -Fq "first_run.txt" "$repo/services/FirstRunExperience.qml" || fail "first-run marker"
grep -Fq "welcomeWizard.completed" "$repo/welcome.qml" || fail "wizard completion marker"
for package in "$repo/distro/arch/inir-shell/PKGBUILD" "$repo/distro/arch/inir-shell-git/PKGBUILD"; do
    grep -Fq 'install -Dm755 "$srcroot/scripts/alis" "$pkgdir/usr/bin/alis"' "$package" || fail "Arch Alis launcher missing"
done
grep -Fq 'makeWrapper "$runtime/scripts/alis" "$out/bin/alis"' "$repo/nix/package.nix" || fail "Nix Alis launcher missing"
grep -Fq 'install -m755 scripts/alis "$(DESTDIR)$(BINDIR)/alis"' "$repo/Makefile" || fail "Makefile Alis launcher missing"
stage="$tmp/make-stage"
make -s install-bin "DESTDIR=$stage" "PREFIX=/usr" || fail "Make Alis launcher installation"
[[ -x "$stage/usr/bin/alis" ]] || fail "installed Alis launcher not executable"
make -s uninstall-bin "DESTDIR=$stage" "PREFIX=/usr" || fail "Make Alis launcher uninstall"
[[ ! -e "$stage/usr/bin/alis" ]] || fail "managed Alis launcher was not removed"
printf "foreign user command\n" > "$stage/usr/bin/alis"
if make -s install-bin "DESTDIR=$stage" "PREFIX=/usr" >/dev/null 2>&1; then
    fail "Make install overwrote foreign Alis launcher"
fi
[[ "$(cat "$stage/usr/bin/alis")" == "foreign user command" ]] || fail "foreign Alis launcher was modified"
make -s uninstall-bin "DESTDIR=$stage" "PREFIX=/usr" || fail "Make uninstall with foreign command"
[[ "$(cat "$stage/usr/bin/alis")" == "foreign user command" ]] || fail "Make uninstall removed foreign Alis launcher"
printf "PASS: Alis alias, completions, first-run and install ownership contracts\n"
