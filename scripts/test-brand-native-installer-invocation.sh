#!/usr/bin/env bash
# BRAND-R01: the updater must run the Rust installer as Bash source, because
# native/scripts/install-runtime.sh is not tracked as an executable in Git.
# Everything below runs in a private temporary tree and does not compile Rust.
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: native installer invocation: %s\n' "$*" >&2; exit 1; }
grep -Fq 'if ! bash "$II_SOURCE/native/scripts/install-runtime.sh" --dest "$native_dest"; then' "$repo/setup" ||
  fail 'update invokes a non-executable native helper directly'
grep -Fq 'if ! bash "${REPO_ROOT}/native/scripts/install-runtime.sh" --dest "$native_dest"; then' "$repo/sdata/subcmd-install/3.files.sh" ||
  fail 'install source helper invocation unexpectedly changed'
grep -Fq '@bash native/scripts/install-runtime.sh --dest' "$repo/Makefile" ||
  fail 'package native helper invocation unexpectedly changed'
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/native/scripts"
cp -- "$repo/native/scripts/install-runtime.sh" "$tmp/native/scripts/install-runtime.sh"
chmod 0644 "$tmp/native/scripts/install-runtime.sh"
[[ -f "$tmp/native/scripts/install-runtime.sh" && ! -x "$tmp/native/scripts/install-runtime.sh" ]] ||
  fail 'fixture is executable; permission error not reproduced'
if "$tmp/native/scripts/install-runtime.sh" --help >/dev/null 2>&1; then
  fail 'direct invocation incorrectly worked without execute permission'
fi
bash -n "$tmp/native/scripts/install-runtime.sh" ||
  fail 'installer syntax is not valid Bash'
help="$(bash "$tmp/native/scripts/install-runtime.sh" --help)" ||
  fail 'Bash invocation failed for a non-executable installer'
[[ "$help" == *'--build-only'* && "$help" == *'--dest DIR'* ]] ||
  fail 'Bash invocation did not execute the real installer argument parser'
printf 'PASS: repo-copy update invokes 0644 Rust installer safely via bash; no Rust build or desktop mutation\n'
