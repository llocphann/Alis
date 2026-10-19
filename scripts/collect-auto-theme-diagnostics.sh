#!/usr/bin/env bash
# One-command, owner-safe Auto Theming diagnostics.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BIN="$ROOT/native/target/release/alis-theme"

# Build checked-out Rust source so sub-stage timing probes are present.
# Build output is local only; no owner desktop service is changed.
if [[ "${ALIS_THEME_DIAG_SKIP_BUILD:-0}" != "1" ]]; then
    command -v cargo >/dev/null 2>&1 || {
        printf 'Rust cargo is required; set ALIS_THEME_DIAG_SKIP_BUILD=1 only if the target binary is current.\n' >&2
        exit 127
    }
    cargo build --release --manifest-path native/Cargo.toml -p alis-theme
fi

[[ -x "$BIN" ]] || {
    printf 'Rust alis-theme binary unavailable; build it first.\n' >&2
    exit 127
}

exec python3 "$ROOT/scripts/collect-auto-theme-diagnostics.py" --binary "$BIN" "$@"
