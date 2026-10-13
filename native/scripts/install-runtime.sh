#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
MANIFEST="$ROOT_DIR/native/Cargo.toml"
TARGET_DIR="${CARGO_TARGET_DIR:-$ROOT_DIR/native/target}"
DEST_DIR=""
BUILD_ONLY=0
BINARIES=(alis-inputd alis-mpdd alis-native alis-theme)
usage() { cat <<'EOF'
Usage: native/scripts/install-runtime.sh [--dest DIR] [--build-only]
Builds the locked release workspace and installs the four production helpers.
EOF
}
while (($#)); do case "$1" in --dest) [[ $# -ge 2 ]] || exit 64; DEST_DIR="$2"; shift 2;; --build-only) BUILD_ONLY=1; shift;; --help|-h) usage; exit 0;; *) usage >&2; exit 64;; esac; done
command -v cargo >/dev/null 2>&1 || { echo "Alis Rust runtime requires Cargo/Rust >= 1.95 for source builds." >&2; exit 2; }
cargo build --locked --release --workspace --manifest-path "$MANIFEST" --target-dir "$TARGET_DIR"
release_dir="$TARGET_DIR/release"
for binary in "${BINARIES[@]}"; do [[ -x "$release_dir/$binary" ]] || { echo "Missing release binary: $binary" >&2; exit 3; }; done
if ((BUILD_ONLY)); then printf 'Native runtime built in %s\n' "$release_dir"; exit 0; fi
[[ -n "$DEST_DIR" ]] || DEST_DIR="$ROOT_DIR/native/bin"
if [[ "$(realpath -m "$release_dir")" == "$(realpath -m "$DEST_DIR")" ]]; then printf 'Native runtime ready in %s\n' "$release_dir"; exit 0; fi
parent="$(dirname -- "$DEST_DIR")"; mkdir -p "$parent"; stage="$(mktemp -d "$parent/.native-bin.XXXXXX")"; trap 'rm -rf -- "$stage"' EXIT
for binary in "${BINARIES[@]}"; do install -m0755 "$release_dir/$binary" "$stage/$binary"; done
rm -rf -- "$DEST_DIR"; mv -- "$stage" "$DEST_DIR"; trap - EXIT
printf 'Installed Alis Rust runtime to %s\n' "$DEST_DIR"
