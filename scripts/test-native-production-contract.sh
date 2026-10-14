#!/usr/bin/env bash
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$root"
fail(){ echo "FAIL: $*" >&2; exit 1; }
grep -Fq 'MODE="${MODE:-rust}"' scripts/native-dispatch || fail "Rust default missing"
grep -Fq 'DEFAULT_BIN_DIR="$ROOT_DIR/native/bin"' scripts/native-dispatch || fail "packaged bin discovery missing"
grep -Fq 'falling back to Python' scripts/native-dispatch || fail "Python fallback missing"
grep -Fq 'cargo build --locked --release --workspace' native/scripts/install-runtime.sh || fail "locked native build missing"
for b in alis-inputd alis-mpdd alis-native alis-theme; do grep -Fq "$b" native/scripts/install-runtime.sh || fail "installer omits $b"; done
grep -Fq 'MIGRATION_REQUIRED=true' sdata/migrations/050-rust-native-default.sh || fail "required cutover migration missing"
grep -Fq 'rust|python)' scripts/native-backend || fail "backend switch missing"
grep -Fq 'native/scripts/install-runtime.sh" --dest "$native_dest"' sdata/subcmd-install/3.files.sh || fail "source install native build missing"
grep -Fq 'native/scripts/install-runtime.sh" --dest "$native_dest"' setup || fail "source update native build missing"
echo "PASS: Rust production cutover contract"
