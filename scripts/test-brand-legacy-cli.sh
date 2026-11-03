#!/usr/bin/env bash
# BRAND-R01: block the public legacy CLI without breaking the internal engine.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$tmp/bin" "$tmp/home/.config/alis"
# The real CLI help reads the installed version context; keep this fixture
# self-contained rather than requiring an owner's existing $HOME state.
printf '%s\n' '{"version":"0.0-test","installMode":"repo-copy"}' > "$tmp/home/.config/alis/version.json"
# The immutable pre-integration engine is a migration input, not shipped source.
legacy_engine="$tmp/legacy-engine"
git -C "$repo" show c69d95fef30d0ce24c28959fed2311a7da6819df^1:scripts/alis > "$legacy_engine"
cp "$legacy_engine" "$tmp/bin/alis"
cp "$repo/scripts/alis" "$tmp/bin/alis"
ln -s "$repo/scripts/lib" "$tmp/bin/lib"
bash -n "$tmp/bin/alis" "$tmp/bin/alis" || fail 'CLI syntax'
for args in help status settings 'run' 'service restart' 'completions bash' 'overview toggle'; do
    read -r -a argv <<< "$args"
    set +e
    output="$(HOME="$tmp/home" bash "$tmp/bin/alis" "${argv[@]}" 2>&1)"
    rc=$?
    set -e
    [[ $rc -eq 64 ]] || fail "legacy public command '$args' unexpectedly exited $rc"
    [[ "$output" == *"temporarily disabled"* && "$output" == *"'alis'"* ]] || fail "missing Alis guidance for $args"
done
# A non-standard XDG_BIN_HOME must not accidentally reactivate the old CLI.
mkdir -p "$tmp/custom-launchers"
cp "$legacy_engine" "$tmp/custom-launchers/alis"
set +e
custom_output="$(HOME="$tmp/home" bash "$tmp/custom-launchers/alis" status 2>&1)"
custom_rc=$?
set -e
[[ $custom_rc -eq 64 && "$custom_output" == *"Use 'alis' instead."* ]] || fail "custom XDG_BIN_HOME legacy executable remains enabled"
# Environment from Alis should only bypass the public check for delegation.
set +e
help_output="$(HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" ALIS_RUNTIME_DIR="$repo" bash "$tmp/bin/alis" help 2>&1)"
help_rc=$?
set -e
if [[ $help_rc -ne 0 ]]; then
    printf 'Alis help diagnostic (exit %s):\\n%s\\n' "$help_rc" "$help_output" >&2
    HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" ALIS_RUNTIME_DIR="$repo" bash -x "$tmp/bin/alis" help 2>&1 | tail -50 >&2 || true
    fail 'Alis help through installed bin'
fi
[[ "$help_output" == *'Usage: alis <command>'* ]] || fail 'Alis public help missing'
[[ "$help_output" == *'  alis status'* ]] || fail 'Alis help targets wrong command'
[[ "$help_output" == *'IPC targets (alis '* ]] || fail 'Alis IPC help missing'
# The retained private engine remains readable without reintroducing it as
# the current product. Test the same bytes under its original private path.
mkdir -p "$tmp/private/scripts"
cp "$legacy_engine" "$tmp/private/scripts/alis"
git -C "$repo" archive c69d95fef30d0ce24c28959fed2311a7da6819df^1 scripts/lib | tar -x -C "$tmp/private"
source_help="$(HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" ALIS_RUNTIME_DIR="$repo" bash "$tmp/private/scripts/alis" help)" || fail 'retained private engine stopped working'
[[ "$source_help" == *'Usage: alis <command>'* ]] || fail 'retained original CLI semantics changed'
[[ ! -e "$repo/scripts/alis" && ! -e "$repo/assets/systemd/alis.service" ]] || fail 'new product ships legacy owner'
grep -Fxq '//@ pragma ShellId alis' "$repo/shell.qml" || fail 'canonical runtime selector missing'
grep -Fxq 'ExecStart=/usr/bin/alis run --session' "$repo/assets/systemd/alis.service" || fail 'canonical service missing'
printf '%s\n' 'PASS: retired public CLI stays disabled; retained private engine and independent canonical Alis help work'
