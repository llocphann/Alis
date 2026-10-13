#!/usr/bin/env bash
set -euo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$repo/sdata/lib/safe-setup-sync.sh"
root="$(mktemp -d)"
trap 'rm -rf -- "$root"' EXIT
fail() { printf 'FAIL: setup atomic sync: %s\n' "$*" >&2; exit 1; }
mkdir -p "$root/source dir" "$root/runtime dir"
source="$root/source dir/setup"
target="$root/runtime dir/setup"
printf '#!/usr/bin/env bash\ncase "$1" in\n  ok) echo valid ;;\nesac\n' > "$source"
printf '#!/usr/bin/env bash\ne ;;\n' > "$target"
bash "$helper" "$source" "$target" || fail 'valid recovery copy was rejected'
bash -n "$target" || fail 'copied setup still has a syntax error'
[[ -x "$target" ]] || fail 'installed setup is not executable'
grep -Fq 'echo valid' "$target" || fail 'expected good script content missing'
before="$(sha256sum "$target" | cut -d' ' -f1)"
printf '#!/usr/bin/env bash\ne ;;\n' > "$source"
if bash "$helper" "$source" "$target" >/dev/null 2>&1; then
    fail 'invalid source overwrote healthy setup'
fi
[[ "$(sha256sum "$target" | cut -d' ' -f1)" == "$before" ]] ||
    fail 'invalid source changed installed setup bytes'
if find "$root/runtime dir" -maxdepth 1 -name '.setup-sync.*' | grep -q .; then
    fail 'aborted staging left temporary files'
fi
# Source and target same file is always an idempotent no-op.
bash "$helper" "$target" "$target" || fail 'repo-link source-target identity failed'
mkdir -p "$root/foreign"
printf 'user secret\n' > "$root/foreign/source"
ln -s "$root/foreign/source" "$root/runtime dir/foreign-setup"
printf '#!/usr/bin/env bash\ntrue\n' > "$source"
if bash "$helper" "$source" "$root/runtime dir/foreign-setup" >/dev/null 2>&1; then
    fail 'foreign symlink was overwritten'
fi
[[ "$(cat "$root/foreign/source")" == 'user secret' ]] ||
    fail 'foreign user data was changed'
[[ -L "$root/runtime dir/foreign-setup" ]] || fail 'foreign link was removed'
grep -Fq 'safe-setup-sync.sh' "$repo/setup" ||
    fail 'update path bypasses safe setup synchronizer'
grep -Fq 'safe-setup-sync.sh' "$repo/sdata/subcmd-install/3.files.sh" ||
    fail 'install path bypasses safe setup synchronizer'
bash -n "$repo/setup" || fail 'committed source setup itself is invalid'
printf 'PASS: atomic setup recovery, invalid source refusal, no partial writes, repo-link and foreign symlink preservation\n'
