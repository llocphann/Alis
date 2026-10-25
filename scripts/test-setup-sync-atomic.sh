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
bash -n "$repo/scripts/alis" || fail 'committed source alis launcher itself is invalid'

# Verify that already-up-to-date update path also repairs runtime setup via safe-setup-sync.sh
python3 - "$repo/setup" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
marker = 'elif [[ "$installed_commit" == "$repo_commit" ]]; then'
block = text.split(marker, 1)[1].split('# Local repo ahead of installed - create snapshot', 1)[0]
if 'safe-setup-sync.sh' not in block:
    raise SystemExit('FAIL: setup atomic sync: already-up-to-date update branch does not repair runtime setup via safe-setup-sync.sh')
PY

# Verify resolve_setup_dir recovery from legacy version.json and preflight refusal on malformed setup
sandbox="$root/sandbox"
mkdir -p "$sandbox/bin" "$sandbox/config/quickshell/alis/scripts/lib" "$sandbox/config/illogical-impulse" "$sandbox/repo/.git"
cp "$repo/scripts/alis" "$sandbox/bin/alis"
chmod +x "$sandbox/bin/alis"
cp "$repo/scripts/lib/config-path.sh" "$sandbox/config/quickshell/alis/scripts/lib/config-path.sh"
cp "$repo/scripts/lib/brand-env-compat.sh" "$sandbox/config/quickshell/alis/scripts/lib/brand-env-compat.sh"
printf 'Item {}\n' > "$sandbox/config/quickshell/alis/shell.qml"
cat > "$sandbox/config/quickshell/alis/setup" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -q|--quiet) quiet=true ;;
;;
esac
EOF
chmod +x "$sandbox/config/quickshell/alis/setup"

# 1. Without a valid repoPath, both `alis update` (run_setup_command) and `alis repair` (run_setup_inline)
# must preflight-refuse the malformed setup with exit code 2 and recovery guidance.
set +e
err_update="$(XDG_CONFIG_HOME="$sandbox/config" HOME="$sandbox" "$sandbox/bin/alis" update -c "$sandbox/config/quickshell/alis" 2>&1)"
rc_update=$?
err_repair="$(XDG_CONFIG_HOME="$sandbox/config" HOME="$sandbox" "$sandbox/bin/alis" repair -c "$sandbox/config/quickshell/alis" 2>&1)"
rc_repair=$?
set -e
[[ "$rc_update" -eq 2 ]] || fail "expected exit 2 from run_setup_command on malformed setup, got $rc_update ($err_update)"
grep -Fq 'refusing syntax-invalid setup' <<<"$err_update" || fail 'missing preflight diagnostic on update'
[[ "$rc_repair" -eq 2 ]] || fail "expected exit 2 from run_setup_inline on malformed setup, got $rc_repair ($err_repair)"
grep -Fq 'refusing syntax-invalid setup' <<<"$err_repair" || fail 'missing preflight diagnostic on repair'

# 2. When a valid repo checkout is recorded in legacy illogical-impulse/version.json (even if ~/.config/alis exists),
# resolve_setup_dir must recover and execute the healthy checkout setup instead of the broken runtime copy.
mkdir -p "$sandbox/config/alis"
printf '{\n  "repoPath": "%s"\n}\n' "$sandbox/repo" > "$sandbox/config/illogical-impulse/version.json"
printf 'Item {}\n' > "$sandbox/repo/shell.qml"
cat > "$sandbox/repo/setup" <<'EOF'
#!/usr/bin/env bash
echo "RECOVERED_FROM_VALID_REPO:$*"
EOF
chmod +x "$sandbox/repo/setup"
out_recovered="$(XDG_CONFIG_HOME="$sandbox/config" HOME="$sandbox" "$sandbox/bin/alis" update --local)"
grep -Fq 'RECOVERED_FROM_VALID_REPO:update --local' <<<"$out_recovered" ||
    fail "resolve_setup_dir did not recover via legacy version.json repoPath ($out_recovered)"

printf 'PASS: atomic setup recovery, invalid source refusal, no partial writes, repo-link and foreign symlink preservation\n'
