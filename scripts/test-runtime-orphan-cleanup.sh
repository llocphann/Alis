#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

export REPO_ROOT="$repo_root"
export XDG_CONFIG_HOME="$stage/config"
export XDG_STATE_HOME="$stage/state"

# robust-update.sh is a sourced library; provide the logging hooks used by the
# cleanup helper so this regression can exercise it without the setup TUI.
log_info() { :; }
log_warning() { :; }
log_error() { :; }
log_success() { :; }
log_header() { :; }

# shellcheck source=/dev/null
source "$repo_root/sdata/lib/robust-update.sh"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

runtime="$stage/runtime"
manifest="$runtime/.alis-manifest"
retired_module_dir="$runtime/modules/retired-orphan-fixture"
live_module_dir="$runtime/modules/dock"
mkdir -p "$retired_module_dir" "$live_module_dir" "$runtime/scripts"

# Build the expected installed manifest from the same canonical payload policy
# used by setup, then add files representing an older mixed runtime tree. Use a
# deliberately nonexistent module name for the retired fixture. Pair it with
# the canonical Dock module so the survival half of this test exercises active
# runtime code rather than depending on a retired compatibility bridge.
generate_manifest "$repo_root" "$manifest" \
    || fail 'could not generate runtime manifest fixture'
grep -Fxq '# alis-manifest v2' "$manifest" \
    || fail 'generated installed manifest does not identify the canonical Alis format'
printf '%s\n' 'import QtQuick' > "$runtime/RetiredRoot.qml"
printf '%s\n' 'import QtQuick' > "$retired_module_dir/Stale.qml"
printf '%s\n' '# retired source-only contract' > "$runtime/scripts/test-packaging-contract.sh"
printf '%s\n' '# private excluded artifact' > "$runtime/scripts/test-local-private.sh"
cp "$repo_root/modules/dock/DockButton.qml" "$live_module_dir/DockButton.qml"
cp "$repo_root/modules/dock/qmldir" "$live_module_dir/qmldir"

cleanup_orphans "$runtime" "$manifest" \
    || fail 'runtime orphan cleanup helper failed'

for stale_path in \
    "$runtime/RetiredRoot.qml" \
    "$retired_module_dir/Stale.qml" \
    "$runtime/scripts/test-packaging-contract.sh"; do
    if [[ -e "$stale_path" || -L "$stale_path" ]]; then
        fail "runtime orphan cleanup preserved stale managed path: ${stale_path#$runtime/}"
    fi
done

[[ -f "$runtime/scripts/test-local-private.sh" ]] \
    || fail 'runtime orphan cleanup deleted an excluded private/test artifact'
[[ ! -d "$retired_module_dir" ]] \
    || fail 'runtime orphan cleanup left the retired empty module directory'
cmp -s "$repo_root/modules/dock/DockButton.qml" "$live_module_dir/DockButton.qml" \
    || fail 'runtime orphan cleanup changed or removed the live Dock module'
cmp -s "$repo_root/modules/dock/qmldir" "$live_module_dir/qmldir" \
    || fail 'runtime orphan cleanup changed or removed the live Dock qmldir'

# The source-install refresh path must run the same managed-orphan cleanup even
# when setup is recovering an existing/partial runtime through `install` rather
# than entering the explicit update branch. Backup and runtime verification may
# remain update-only, but cleanup after manifest finalization must not be gated.
python3 - "$repo_root/sdata/subcmd-install/3.files.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
start_marker = '    # Finalize manifest\n'
end_marker = '    # Fix script permissions\n'
cleanup_call = '    cleanup_orphans "$II_TARGET" "${II_TARGET}/.alis-manifest"\n'

if text.count(start_marker) != 1 or text.count(end_marker) != 1:
    raise SystemExit("install stage lost the manifest-finalization/permission markers")
start = text.index(start_marker)
end = text.index(end_marker, start)
segment = text[start:end]
if segment.count(cleanup_call) != 1:
    raise SystemExit("install stage must run exactly one orphan cleanup after manifest finalization")
if 'IS_UPDATE' in segment:
    raise SystemExit("install-stage orphan cleanup is still gated by IS_UPDATE")
PY

grep -Fq 'generate_manifest "$II_SOURCE" "${II_TARGET}/.alis-manifest"' "$repo_root/setup" \
    || fail 'setup update no longer generates the canonical installed manifest'
grep -Fq 'cleanup_orphans "$II_TARGET" "${II_TARGET}/.alis-manifest"' "$repo_root/setup" \
    || fail 'setup update no longer invokes runtime orphan cleanup'
grep -Fq '"$script_dir/test-runtime-orphan-cleanup.sh"' "$repo_root/scripts/release.sh" \
    || fail 'release helper no longer requires the runtime orphan cleanup contract'

# Both Arch package variants must build their shell tree through the canonical
# full-payload helper. Bypassing it would reintroduce mixed-runtime risk even if
# make install and repo-copy update remain correct.
for package_recipe in \
    "$repo_root/distro/arch/alis-shell/PKGBUILD" \
    "$repo_root/distro/arch/alis-shell-git/PKGBUILD"; do
    grep -Fq 'runtime-payload.py" copy --root "$srcroot" --target "$shellroot"' "$package_recipe" \
        || fail "Arch recipe bypasses canonical runtime payload copy: ${package_recipe#$repo_root/}"
done

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - runtime cleanup removes retired managed/source-only files without deleting live or private payloads'
