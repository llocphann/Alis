#!/usr/bin/env bash
# Read-only proof that the retained unit can run its original private engine.
brand_verify_recovery_cli() {
    local unit="$1" cfg="$2" executable internal runtime
    executable="$(sed -n 's/^ExecStart=//p' "$unit" | head -n1)"
    executable="${executable%% *}"
    [[ "$executable" == /* && -f "$executable" && -x "$executable" && ! -L "$executable" ]] || {
        echo "Previous runtime CLI unavailable: $executable" >&2; return 2;
    }
    if "$executable" help >/dev/null 2>&1; then return 0; fi
    # The shipped compatibility engine denies public help, while allowing
    # systemd's private run/cleanup actions. A generic disabled stub is unsafe.
    runtime="$cfg/quickshell/inir"
    internal="$runtime/scripts/inir"
    [[ -d "$runtime" && ! -L "$runtime" && -f "$internal" && ! -L "$internal" && -x "$internal" ]] &&
    grep -Fxq '//@ pragma ShellId inir' "$runtime/shell.qml" &&
    cmp -s -- "$executable" "$internal" &&
    grep -Fq '# BRAND-R01: keep the established scripts/inir engine' "$internal" &&
    grep -Fq '[[ -n "${INVOCATION_ID:-}" ]]' "$internal" &&
    grep -Fq '"${1:-}" == run && "${2:-}" == --session' "$internal" &&
    grep -Fq '"${1:-}" == cleanup-orphans' "$internal" &&
    "$internal" help >/dev/null 2>&1 || {
        echo 'Original runtime CLI failed read-only help; restore a verified engine' >&2; return 2;
    }
    echo 'VERIFIED: byte-identical managed legacy engine supports private service recovery.'
}
