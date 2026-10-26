#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

directories="modules/common/Directories.qml"
migration="sdata/migrations/019-config-dir-rename-compat.sh"
config_doc="docs/CONFIG_SYSTEM.md"
stable_hook="distro/arch/alis-shell/alis-shell.install"
git_hook="distro/arch/alis-shell-git/alis-shell-git.install"

for file in "$directories" "$migration" "$config_doc" "$stable_hook" "$git_hook"; do
  [[ -f "$file" ]] || fail "missing config namespace contract file: $file"
done

# Canonical QML and maintenance tooling use Alis after the explicit cutover.
# Historical migration 019 retains its original input/output contract for
# pre-cutover recovery; it must not be rewritten to move canonical user data.
grep -Fq 'property string shellConfig: `${Directories.configPath}/alis`' "$directories" \
  || fail 'live QML config path no longer matches the canonical Alis namespace'
grep -Fq 'MIGRATION_REQUIRED=true' "$migration" \
  || fail 'config directory compatibility migration is no longer required'
grep -Fq 'local config_new="${xdg_config_home}/alis"' "$migration" \
  || fail 'migration 019 no longer names ~/.config/alis as the canonical directory'
grep -Fq 'local config_legacy="${xdg_config_home}/illogical-impulse"' "$migration" \
  || fail 'migration 019 no longer recognizes the live QML compatibility directory'
grep -Fq 'ln -s "$config_new" "$config_legacy"' "$migration" \
  || fail 'migration 019 no longer links the QML compatibility path to the canonical directory'

# Documentation must identify the current QML path and preserve the explicit
# per-user migration/ownership boundary for package/manual installs.
grep -Fq 'The canonical config file used by live QML is:' "$config_doc" \
  || fail 'config docs no longer identify the canonical live QML file'
grep -Fxq '~/.config/alis/config.json' "$config_doc" \
  || fail 'config docs no longer name the canonical Alis config file'
grep -Fq 'Migration 019 is historical' "$config_doc" \
  || fail 'config docs no longer distinguish the historical migration from the Alis cutover'
grep -Fq 'Package managers and manual `make install` deliberately do not mutate arbitrary user home directories' "$config_doc" \
  || fail 'config docs no longer preserve package/manual user-home ownership'
grep -Fq 'single-service handoff before running `alis migrate`' "$config_doc" \
  || fail 'config docs no longer gate canonical migrations on a safe service handoff'

# Stable and VCS Arch packages must give the same ownership-safe lifecycle
# guidance. Pacman cannot apply a per-user migration from a root transaction.
cmp -s "$stable_hook" "$git_hook" \
  || fail 'stable/git Arch install hooks drifted'
for hook in "$stable_hook" "$git_hook"; do
  grep -Fq "before running 'alis migrate'" "$hook" \
    || fail "$hook no longer gates canonical migration on the owner-approved handoff"
  grep -Fq 'Pacman deliberately does not modify or migrate anyone' "$hook" \
    || fail "$hook no longer explains the per-user migration ownership boundary"
  grep -Fq 'do not enable a second service or run old migration 019' "$hook" \
    || fail "$hook no longer protects upgrades from a second shell owner or historical config move"
  if grep -Fq 'Runtime migrations, when needed, are applied by Alis' "$hook"; then
    fail "$hook again implies the package transaction mutates per-user config"
  fi
done

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - config namespace migration and package ownership contracts are coherent'
