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
cat > "$tmp/inir" <<'HELP_MOCK'
#!/usr/bin/env bash
if [[ "${1:-}" == help ]]; then
    printf '%s\n' 'Usage: inir <command>' '  inir status' '  ~/.config/inir must stay unchanged'
else
    printf '<%s>\n' "$@"
fi
HELP_MOCK
help_output="$(bash "$tmp/alis" help)"
grep -Fq 'Usage: alis <command>' <<< "$help_output" || fail 'Alis public help still exposes legacy command usage'
grep -Fq '  alis status' <<< "$help_output" || fail 'Alis help command example not converted'
grep -Fq '~/.config/inir must stay unchanged' <<< "$help_output" || fail 'Alis help rewrote internal compatibility paths'
alt_help_output="$(bash "$tmp/alis" --help)"
[[ "$alt_help_output" == "$help_output" ]] || fail 'Alis --help is not equivalent to help'

[[ "$output" == $'<status>\n<--example>\n<arg with spaces>' ]] || fail "argument passthrough"
for shell in bash fish zsh; do
    output="$(bash "$repo/scripts/alis" completions "$shell")" || fail "$shell completion lookup"
    case "$shell" in
        bash) grep -Fq "complete -F _inir_completions alis" <<<"$output" || fail "bash registration" ;;
        fish) grep -Fq "complete -c alis " <<<"$output" || fail "fish registration" ;;
        zsh) grep -Fxq "#compdef alis" <<<"$output" || fail "zsh registration" ;;
    esac
done
grep -Fq 'tui_hero_card "Alis setup"' "$repo/setup" || fail "setup TUI still uses legacy product name"
grep -Fq 'Alis — your niri shell' "$repo/sdata/lib/tui.sh" || fail 'status banner still carries previous public name'
if grep -Fq 'iNiR — your niri shell' "$repo/sdata/lib/tui.sh"; then fail 'legacy status banner was not retired'; fi
grep -Fq 'Pending IDs: $pending_ids' "$repo/setup" || fail 'status fails to identify pending migrations'
if grep -Fq 'Syncing iNiR...' "$repo/setup"; then fail "updater still displays old public name"; fi
grep -Fq "Installed Alis Rust runtime" "$repo/native/scripts/install-runtime.sh" || fail "Rust installer banner still uses previous brand"
grep -Fq "tui_alert \"success\" \"Update complete\"" "$repo/setup" || fail "updater success banner missing"
grep -Fq "Name=Alis Shell" "$repo/assets/applications/inir.desktop" || fail "desktop entry"
grep -Fq "Name=Alis Settings" "$repo/assets/applications/inir-settings.desktop" || fail "settings desktop entry"
grep -Fxq "NoDisplay=true" "$repo/assets/applications/inir-settings.desktop" || fail "legacy settings launcher visible"
grep -Fxq "NoDisplay=true" "$repo/assets/applications/inir.desktop" || fail "legacy shell launcher visible"
grep -Fq "Exec=alis service restart" "$repo/assets/applications/inir.desktop" || fail "legacy pinned shell command must use Alis"
grep -Fq "Exec=alis settings" "$repo/assets/applications/inir-settings.desktop" || fail "legacy pinned settings command must use Alis"
grep -Fxq "X-Alis-Managed=true" "$repo/assets/applications/alis.desktop" || fail "Alis desktop ownership marker missing"
grep -Fq 'title: "Alis"' "$repo/modules/settings/About.qml" || fail "Alis classic About still named iNiR"
grep -Fq 'text: "Alis"' "$repo/modules/waffle/settings/pages/WAboutPage.qml" || fail "Alis Waffle About still named iNiR"
if grep -Fq 'snowarch/inir' "$repo/modules/settings/About.qml" || grep -Fq 'snowarch/inir' "$repo/modules/waffle/settings/pages/WAboutPage.qml"; then fail "About page linked to upstream rather than Alis"; fi
grep -Fq 'nixosModules.alis = nixosModule;' "$repo/flake.nix" || fail "Alis Nix module not exported"
grep -Fq 'homeModules.alis = homeModule;' "$repo/flake.nix" || fail "Alis Home Manager module not exported"
grep -Fq '          alis = package;' "$repo/flake.nix" || fail "Alis package not exported"
grep -Fq 'mkAliasOptionModule [ "programs" "alis" ] [ "programs" "inir" ]' "$repo/nix/module-common.nix" || fail "Alis Nix config option is not mapped to one service"
for hook in "$repo/distro/arch/inir-shell/inir-shell.install" "$repo/distro/arch/inir-shell-git/inir-shell-git.install"; do
    grep -Fq 'Alis has been installed.' "$hook" || fail "Arch install notice still uses old public name"
    grep -Fq 'inir.service' "$hook" || fail "Arch notice lost service compatibility identity"
done
grep -Fq "Exec=alis settings" "$repo/assets/applications/alis-settings.desktop" || fail "Alis settings app ID missing"
grep -Fxq "Icon=alis" "$repo/assets/applications/alis-settings.desktop" || fail "Alis icon ID missing"
grep -Fq 'apps/alis.svg"' "$repo/nix/package.nix" || fail "Nix icon alias not packaged"
grep -Fq "Exec=alis service restart" "$repo/assets/applications/alis.desktop" || fail "Alis shell app ID missing"
grep -Fq 'Translation.tr("Welcome to Alis")' "$repo/welcome.qml" || fail "wizard"
grep -Fq "first_run.txt" "$repo/services/FirstRunExperience.qml" || fail "first-run marker"
grep -Fq "welcomeWizard.completed" "$repo/welcome.qml" || fail "wizard completion marker"
for package in "$repo/distro/arch/inir-shell/PKGBUILD" "$repo/distro/arch/inir-shell-git/PKGBUILD"; do
    grep -Fq 'install -Dm755 "$srcroot/scripts/alis" "$pkgdir/usr/bin/alis"' "$package" || fail "Arch Alis launcher missing"
    grep -Fq 'install -Dm644 "$srcroot/assets/applications/alis-settings.desktop"' "$package" || fail "Arch Alis application ID missing"
done
grep -Fq 'makeWrapper "$runtime/scripts/alis" "$out/bin/alis"' "$repo/nix/package.nix" || fail "Nix Alis launcher missing"
grep -Fq 'assets/applications/alis-settings.desktop > "$out/share/applications/alis-settings.desktop"' "$repo/nix/package.nix" || fail "Nix Alis desktop ID missing"
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
desktop_stage="$tmp/desktop-stage"
make -s install-desktop "DESTDIR=$desktop_stage" "PREFIX=/usr" || fail "Make Alis desktop install"
[[ -f "$desktop_stage/usr/share/applications/alis-settings.desktop" ]] || fail "Alis desktop file missing from Make staging"
make -s uninstall-desktop "DESTDIR=$desktop_stage" "PREFIX=/usr" || fail "Make Alis desktop uninstall"
[[ ! -e "$desktop_stage/usr/share/applications/alis-settings.desktop" ]] || fail "managed Alis desktop entry not removed"
printf "foreign desktop entry\n" > "$desktop_stage/usr/share/applications/alis-settings.desktop"
if make -s install-desktop "DESTDIR=$desktop_stage" "PREFIX=/usr" >/dev/null 2>&1; then fail "Make overwrote foreign desktop entry"; fi
[[ "$(cat "$desktop_stage/usr/share/applications/alis-settings.desktop")" == "foreign desktop entry" ]] || fail "foreign desktop entry mutated"
make -s uninstall-desktop "DESTDIR=$desktop_stage" "PREFIX=/usr" || fail "Make desktop uninstall with foreign entry"
[[ "$(cat "$desktop_stage/usr/share/applications/alis-settings.desktop")" == "foreign desktop entry" ]] || fail "Make desktop uninstall removed foreign entry"
printf "PASS: Alis alias, completions, first-run and install ownership contracts\n"
