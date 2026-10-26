#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

# Uninstall path arrays are populated from already-expanded environment paths.
# A literal shell fragment inside an XDG path must remain path data: older code
# fed these values back through eval, which could execute command substitutions
# while merely deciding which files to remove.
sentinel="$stage/eval-ran"
export HOME="$stage/home"
export XDG_CONFIG_HOME="$stage/config \$(touch $sentinel)"
export XDG_STATE_HOME="$stage/state"
export XDG_CACHE_HOME="$stage/cache"
export XDG_BIN_HOME="$stage/bin"
export XDG_DATA_HOME="$stage/data"
export DOTS_CORE_CONFDIR="$XDG_CONFIG_HOME/alis"

mkdir -p "$XDG_CONFIG_HOME/quickshell/alis"

STY_FAINT=''
STY_RST=''
STY_RED=''
tui_info() { :; }
tui_success() { :; }

# shellcheck source=/dev/null
source "$repo_root/sdata/lib/uninstall.sh"

if grep -Fq 'eval echo "$path"' "$repo_root/sdata/lib/uninstall.sh"; then
    fail 'uninstall path handling still re-evaluates expanded paths as shell code'
fi

grep -Fq '"$script_dir/test-uninstall-path-safety.sh"' "$repo_root/scripts/release.sh" \
    || fail 'release helper no longer requires the uninstall path-safety contract'

# Some uninstall counters intentionally use post-increment expressions whose
# status is 1 at zero, so run the helper without inheriting this test's errexit.
set +e
uninstall_remove_alis_only >/dev/null
rc=$?
set -e
[[ "$rc" -eq 0 ]] || fail 'exclusive-file cleanup returned nonzero'

[[ ! -e "$sentinel" ]] \
    || fail 'uninstall executed shell syntax embedded in an XDG path'
[[ ! -e "$XDG_CONFIG_HOME/quickshell/alis" ]] \
    || fail 'uninstall did not remove the literal Alis runtime path'

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - uninstall treats expanded XDG/HOME paths as literal data'
