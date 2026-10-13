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
printf "PASS: Alis alias, completions, and first-run identity contracts\n"
