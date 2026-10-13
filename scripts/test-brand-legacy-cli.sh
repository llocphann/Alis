#!/usr/bin/env bash
# BRAND-R01: block the public legacy CLI without breaking the internal engine.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
mkdir -p "$tmp/bin" "$tmp/home"
cp "$repo/scripts/inir" "$tmp/bin/inir"
cp "$repo/scripts/alis" "$tmp/bin/alis"
ln -s "$repo/scripts/lib" "$tmp/bin/lib"
bash -n "$tmp/bin/inir" "$tmp/bin/alis" || fail 'CLI syntax'
for args in help status settings 'run' 'service restart' 'completions bash' 'overview toggle'; do
    read -r -a argv <<< "$args"
    set +e
    output="$(HOME="$tmp/home" bash "$tmp/bin/inir" "${argv[@]}" 2>&1)"
    rc=$?
    set -e
    [[ $rc -eq 64 ]] || fail "legacy public command '$args' unexpectedly exited $rc"
    [[ "$output" == *"temporarily disabled"* && "$output" == *"'alis'"* ]] || fail "missing Alis guidance for $args"
done
# Environment from Alis should only bypass the public check for delegation.
set +e
help_output="$(HOME="$tmp/home" INIR_RUNTIME_DIR="$repo" bash "$tmp/bin/alis" help 2>&1)"
help_rc=$?
set -e
if [[ $help_rc -ne 0 ]]; then
    printf 'Alis help diagnostic (exit %s):\\n%s\\n' "$help_rc" "$help_output" >&2
    fail 'Alis help through installed bin'
fi
[[ "$help_output" == *'Usage: alis <command>'* ]] || fail 'Alis public help missing'
[[ "$help_output" == *'  alis status'* ]] || fail 'Alis help targets wrong command'
[[ "$help_output" == *'IPC targets (alis '* ]] || fail 'Alis IPC help missing'
# The source engine is still directly usable by internal QML code.
source_help="$(HOME="$tmp/home" INIR_RUNTIME_DIR="$repo" bash "$repo/scripts/inir" help)" || fail 'internal engine stopped working'
[[ "$source_help" == *'Usage: inir <command>'* ]] || fail 'internal engine semantics changed'
# No second unit, ShellId or persisted names were introduced.
grep -Fxq 'ExecStart=/usr/bin/inir run --session' "$repo/assets/systemd/inir.service" || fail 'service owner changed'
grep -Fxq 'ExecStopPost=-/usr/bin/inir cleanup-orphans' "$repo/assets/systemd/inir.service" || fail 'service cleanup changed'
grep -Fxq '//@ pragma ShellId inir' "$repo/shell.qml" || fail 'runtime selector changed'
grep -Fq -- '--set ALIS_LEGACY_PUBLIC 1' "$repo/nix/package.nix" || fail 'Nix public wrapper bypasses gate'
grep -Fq 'export ALIS_INTERNAL_CLI=1' "$repo/scripts/alis" || fail 'Alis missing delegation'
printf '%s\n' 'PASS: inir public CLI disabled; Alis and internal runtime preserved'
