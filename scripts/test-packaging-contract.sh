#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

recipe_value() {
  local file="$1"
  local key="$2"
  grep -m1 "^${key}=" "$file" | cut -d= -f2-
}

srcinfo_value() {
  local file="$1"
  local key="$2"
  sed -n "s/^[[:space:]]*${key} = //p" "$file" | head -1
}

repo_version="$(tr -d '[:space:]' < VERSION)"
stable_pkg="distro/arch/alis-shell/PKGBUILD"
stable_srcinfo="distro/arch/alis-shell/.SRCINFO"
git_pkg="distro/arch/alis-shell-git/PKGBUILD"
git_srcinfo="distro/arch/alis-shell-git/.SRCINFO"
meta_pkg="distro/arch/alis-meta/PKGBUILD"
meta_srcinfo="distro/arch/alis-meta/.SRCINFO"
stable_hook="distro/arch/alis-shell/alis-shell.install"
git_hook="distro/arch/alis-shell-git/alis-shell-git.install"
makefile="Makefile"
release_script="scripts/release.sh"
packaging_workflow=".github/workflows/packaging.yml"
audio_doc="docs/AUDIO_MEDIA.md"
uninstall_doc="docs/UNINSTALL.md"

for file in "$stable_pkg" "$stable_srcinfo" "$git_pkg" "$git_srcinfo" "$meta_pkg" "$meta_srcinfo" "$stable_hook" "$git_hook" "$makefile" "$release_script" "$packaging_workflow" "$audio_doc" "$uninstall_doc"; do
  [[ -f "$file" ]] || fail "missing packaging file: $file"
done

payload_list="$(python3 sdata/lib/runtime-payload.py list --root .)"
for test_script in scripts/test-*.sh; do
  [[ -e "$test_script" ]] || continue
  if grep -Fqx "$test_script" <<<"$payload_list"; then
    fail "runtime payload includes repository test script: $test_script"
  fi
done

# Production StyledPopup resolves the exact iRiS shader relative to its runtime
# QML module. The standalone G2 test already caught how a missing local QSB can
# leave structure green while rendering no field, so packaging must fail closed.
for iris_asset in \
  modules/common/perimeter/IrisField.frag \
  modules/common/perimeter/IrisField.frag.qsb; do
  grep -Fqx "$iris_asset" <<<"$payload_list" \
    || fail "runtime payload omits production iRiS shader asset: $iris_asset"
done

for pair in \
  "$stable_pkg:$stable_srcinfo" \
  "$git_pkg:$git_srcinfo" \
  "$meta_pkg:$meta_srcinfo"; do
  recipe="${pair%%:*}"
  srcinfo="${pair#*:}"
  recipe_ver="$(recipe_value "$recipe" pkgver)"
  recipe_rel="$(recipe_value "$recipe" pkgrel)"
  srcinfo_ver="$(srcinfo_value "$srcinfo" pkgver)"
  srcinfo_rel="$(srcinfo_value "$srcinfo" pkgrel)"
  [[ "$recipe_ver" == "$srcinfo_ver" ]] || fail "$recipe pkgver differs from $srcinfo"
  [[ "$recipe_rel" == "$srcinfo_rel" ]] || fail "$recipe pkgrel differs from $srcinfo"
done

[[ "$(recipe_value "$stable_pkg" pkgver)" == "$repo_version" ]] \
  || fail 'alis-shell pkgver does not match VERSION'
[[ "$(recipe_value "$meta_pkg" pkgver)" == "$repo_version" ]] \
  || fail 'alis-meta pkgver does not match VERSION'

git_version="$(recipe_value "$git_pkg" pkgver)"
case "$git_version" in
  "$repo_version".r*) ;;
  *) fail "alis-shell-git pkgver seed does not follow VERSION: $git_version" ;;
esac

source_ref="$(sed -n 's/^_source_ref="${ALIS_SOURCE_REF:-\([^}]*\)}"$/\1/p' "$stable_pkg")"
[[ -n "$source_ref" ]] || fail 'cannot read alis-shell default _source_ref'
git cat-file -e "${source_ref}^{commit}" 2>/dev/null \
  || fail "alis-shell source ref is not a local commit: $source_ref"
git merge-base --is-ancestor "$source_ref" HEAD \
  || fail "alis-shell source ref is not an ancestor of HEAD: $source_ref"
source_version="$(git show "$source_ref:VERSION" | tr -d '[:space:]')"
[[ "$source_version" == "$repo_version" ]] \
  || fail "alis-shell source snapshot VERSION=$source_version, repository VERSION=$repo_version"
for required_path in \
  shell.qml \
  qmldir \
  sdata/lib/runtime-payload.py \
  docs/AUDIO_MEDIA.md \
  docs/INSTALL.md \
  docs/PACKAGES.md \
  docs/RELEASING.md \
  native/Cargo.toml \
  native/Cargo.lock \
  assets/helpers/alis-hadalird-system-provision \
  assets/polkit/org.alis.hadalird-system-provision.policy; do
  git cat-file -e "$source_ref:$required_path" 2>/dev/null \
    || fail "alis-shell source snapshot lacks $required_path"
done

source_root_manifest="$(git show "$source_ref:sdata/runtime-root-files.txt")"
if ! grep -Fxq 'qmldir' <<<"$source_root_manifest"; then
  grep -Fq 'install -Dm644 "$srcroot/qmldir" "$shellroot/qmldir"' "$stable_pkg" \
    || fail 'alis-shell pinned snapshot omits qmldir and the package compatibility copy is missing'
fi

srcinfo_source="$(srcinfo_value "$stable_srcinfo" source)"
[[ "$srcinfo_source" == *"/archive/${source_ref}.tar.gz" ]] \
  || fail 'alis-shell .SRCINFO source archive drifted from _source_ref'

# The frozen Arch source must ship the root-owned Hadalird Polkit gateway;
# checking the current checkout alone missed a stale pre-gateway source pin.
for recipe in "$stable_pkg" "$git_pkg"; do
  grep -Fq 'install -Dm755 "$srcroot/assets/helpers/alis-hadalird-system-provision"' "$recipe" \
    || fail "$recipe does not ship the trusted Hadalird system provisioner"
  grep -Fq 'install -Dm644 "$srcroot/assets/polkit/org.alis.hadalird-system-provision.policy"' "$recipe" \
    || fail "$recipe does not ship the Hadalird Polkit policy"
done

# The packaged color pipeline runs without the source installer's managed venv.
# Both direct Arch shell packages therefore need the generator's Python imports
# as package dependencies, with committed .SRCINFO kept in lockstep.
arch_python_required=(python-materialyoucolor python-numpy python-pillow)
for pair in \
  "$stable_pkg:$stable_srcinfo" \
  "$git_pkg:$git_srcinfo"; do
  recipe="${pair%%:*}"
  srcinfo="${pair#*:}"
  for package in "${arch_python_required[@]}"; do
    grep -Eq "^[[:space:]]+${package}$" "$recipe" \
      || fail "$recipe is missing color generator Python dependency: $package"
    grep -Fqx $'\tdepends = '"$package" "$srcinfo" \
      || fail "$srcinfo is missing color generator Python dependency: $package"
  done
done

# Rust is now part of the shipped runtime. Direct shell packages therefore
# need Cargo at build time, must be architecture-specific, and must install all
# four baseline helpers under the selector-owned runtime directory. The optional
# Companion is separately installed from its pinned package.
arch_native_bins=(alis-inputd alis-mpdd alis-native alis-theme)
for pair in \
  "$stable_pkg:$stable_srcinfo" \
  "$git_pkg:$git_srcinfo"; do
  recipe="${pair%%:*}"
  srcinfo="${pair#*:}"
  grep -Eq '^makedepends=\([^)]*cargo' "$recipe" \
    || fail "$recipe is missing Cargo build dependency"
  grep -Fqx $'\tmakedepends = cargo' "$srcinfo" \
    || fail "$srcinfo is missing Cargo build dependency"
  if grep -Eq '^arch=\(any\)$' "$recipe"; then
    fail "$recipe still declares architecture-independent output while shipping Rust binaries"
  fi
  grep -Fq 'native/bin' "$recipe" \
    || fail "$recipe does not install native helpers under runtime native/bin"
  for binary in "${arch_native_bins[@]}"; do
    grep -Fq "$binary" "$recipe" \
      || fail "$recipe does not package native binary: $binary"
  done
done


# The primary local aggregate should exercise the same fast release-boundary
# contracts even when hosted CI cannot start a runner. Target membership is the
# invariant; dependency ordering may change as independent gates are added.
test_local_rule="$(grep -m1 '^test-local:' "$makefile")"
for target in test-optional-audio-deps test-news-contract test-equalizer-contracts test-docs; do
  [[ " $test_local_rule " == *" $target "* ]] \
    || fail "make test-local no longer includes required gate: $target"
done
grep -Fq '@bash scripts/test-equalizer-boundary-contract.sh' "$makefile" \
  || fail 'make test-local no longer runs the Equalizer architecture boundary contract'
grep -Fq '@bash scripts/test-equalizer-service-contract.sh' "$makefile" \
  || fail 'make test-local no longer runs the Equalizer lifecycle/protocol contract'
grep -Fq '@bash scripts/verify-docs.sh' "$makefile" \
  || fail 'make test-local no longer runs documentation verification'

# Release publication is fail-closed for the required non-Nix lane: after
# tag/source identity checks and before draft creation, the helper must verify
# hosted publication prerequisites and all required packaging/dependency contracts.
grep -Fq 'require_release_host_features() {' "$release_script" \
  || fail 'release helper no longer defines hosted publication preflight'
grep -Fq '.has_wiki' "$release_script" \
  || fail 'release hosted preflight no longer verifies GitHub Wiki availability'
grep -Fq 'GitHub Wiki is disabled' "$release_script" \
  || fail 'release hosted preflight no longer fails clearly when Wiki is disabled'
grep -Fq 'GIT_TERMINAL_PROMPT=0 git ls-remote "$wiki_url" HEAD' "$release_script" \
  || fail 'release hosted preflight no longer verifies non-interactive Wiki Git access'
grep -Fq 'GitHub Wiki repository is not initialized' "$release_script" \
  || fail 'release hosted preflight no longer detects an uninitialized Wiki repository'
grep -Fq 'git user.name and user.email must be configured' "$release_script" \
  || fail 'release hosted preflight no longer verifies Wiki commit author identity'
grep -Fq '"$script_dir/test-packaging-contract.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes the packaging contract'
grep -Fq 'contract="$script_dir/test-nix-module-contract.sh"' "$release_script" \
  || fail 'release helper no longer retains the deferred Nix diagnostic'
grep -Fq 'deferred Nix diagnostic failed and is non-blocking' "$release_script" \
  || fail 'release helper no longer marks the Nix diagnostic non-blocking'
grep -Fq '"$script_dir/test-doctor-dependency-routing.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes the doctor dependency contract'
grep -Fq '"$script_dir/test-equalizer-boundary-contract.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes the Equalizer architecture boundary contract'
grep -Fq '"$script_dir/test-equalizer-service-contract.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes the Equalizer lifecycle/protocol contract'
grep -Fq '"$script_dir/test-optional-audio-deps-contract.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes the optional audio dependency contract'
grep -Fq '"$script_dir/test-hadalird-install-lifecycle.py"' "$release_script" \
  || fail 'release publish preflight no longer includes the optional lifecycle contract'
grep -Fq '"$script_dir/test-hadalird-arch-package.py"' "$release_script" \
  || fail 'release publish preflight no longer includes the optional Arch package contract'
grep -Fq '"$script_dir/test-make-install-lifecycle.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes the make install lifecycle contract'
grep -Fq '"$script_dir/verify-docs.sh"' "$release_script" \
  || fail 'release publish preflight no longer includes documentation verification'

host_line="$(grep -nF '  require_release_host_features' "$release_script" | tail -1 | cut -d: -f1)"
contract_line="$(grep -nF '  require_release_contracts' "$release_script" | tail -1 | cut -d: -f1)"
draft_line="$(grep -nF '  stage_release_draft "$tag" "$notes_file"' "$release_script" | tail -1 | cut -d: -f1)"
[[ -n "$host_line" && -n "$contract_line" && -n "$draft_line" \
    && "$host_line" -lt "$contract_line" && "$contract_line" -lt "$draft_line" ]] \
  || fail 'release publish path no longer completes host/contracts preflight before draft creation'

wiki_trigger_count="$(grep -F -c -e "- 'scripts/wiki-sync.sh'" "$packaging_workflow")"
[[ "$wiki_trigger_count" -eq 2 ]] \
  || fail 'Packaging workflow must watch scripts/wiki-sync.sh for both push and pull_request'

# alis-meta promises the full desktop experience. These packages represent
# default source-installer supplements across shell utilities, visuals, login,
# wallpaper tooling, task management, and critical fonts.
meta_required=(
  adwaita-icon-theme
  eza
  frameworkintegration
  gowall-bin
  hicolor-icon-theme
  kdecoration
  mission-center
  mpd-mpris
  papirus-icon-theme
  qt6-avif-image-plugin
  sddm
  starship
  ttf-gabarito-git
)
for package in "${meta_required[@]}"; do
  grep -Eq "^[[:space:]]+${package}$" "$meta_pkg" \
    || fail "$meta_pkg is missing default full-experience dependency: $package"
  grep -Fqx $'\tdepends = '"$package" "$meta_srcinfo" \
    || fail "$meta_srcinfo is missing dependency: $package"
done

cmp -s "$stable_hook" "$git_hook" || fail 'stable/git Arch lifecycle hooks differ'
for hook in "$stable_hook" "$git_hook"; do
  grep -Fq 'post_remove() {' "$hook" \
    || fail "$hook no longer explains per-user service cleanup after package removal"
  grep -Fq -- "-path '*.wants/alis.service' -type l -delete" "$hook" \
    || fail "$hook no longer provides dangling service-link cleanup"
  grep -Fq "run 'alis service disable' as each affected user" "$hook" \
    || fail "$hook no longer documents the safe pre-removal service step"
done

# Pacman owns the canonical user unit under /usr/lib/systemd/user. Both Arch
# recipes must patch their packaged launchers so compositor wiring targets that
# unit directly, legacy identical user copies are migrated away, custom user
# overrides are never silently deleted, and service uninstall stays package-owned.
for pkg in "$stable_pkg" "$git_pkg"; do
  grep -Fq 'local package_unit="/usr/lib/systemd/user/alis.service"' "$pkg" \
    || fail "$pkg no longer binds service lifecycle to the package-owned unit"
  grep -Fq 'cmp -s "$user_unit" "$package_unit"' "$pkg" \
    || fail "$pkg no longer safely migrates identical legacy user units"
  grep -Fq 'custom user alis.service shadows the package unit' "$pkg" \
    || fail "$pkg no longer preserves custom user service overrides"
  grep -Fq 'ln -sf "$package_unit" "$correct_link"' "$pkg" \
    || fail "$pkg no longer retargets existing enabled wiring during legacy-unit migration"
  grep -Fq 'ln -sf "/usr/lib/systemd/user/alis.service"' "$pkg" \
    || fail "$pkg no longer wires compositor startup to the package-owned unit"
  grep -Fq 'alis.service is owned by the pacman package' "$pkg" \
    || fail "$pkg can again uninstall package-owned service state through the launcher"
  grep -Fq 'install_end = text.find(install_next_marker, install_start)' "$pkg" \
    || fail "$pkg no longer replaces the complete install_user_service function"
  grep -Fq 'text = text[:install_start] + install_guard + text[install_end:]' "$pkg" \
    || fail "$pkg no longer slices out the legacy install_user_service body"
  grep -Fq 'bash -n "$launcher" || return' "$pkg" \
    || fail "$pkg no longer syntax-checks the transformed launcher"
  if grep -Fq 'text = text.replace(install_marker, install_guard, 1)' "$pkg"; then
    fail "$pkg again replaces only the install_user_service opening marker"
  fi
done

# Audio/media docs must preserve the Phase 1 optional-backend boundary.
grep -Fq 'The Equalizer Phase 1 capability is disabled by default and is separate from normal Media playback.' "$audio_doc" \
  || fail 'audio/media docs no longer state that Equalizer Phase 1 is disabled by default'
grep -Fq 'EasyEffects is its first optional backend, while `socat` is used only as an optional transport' "$audio_doc" \
  || fail 'audio/media docs no longer distinguish the optional Equalizer backend and transport'
grep -Fq 'If either the backend or transport is unavailable, the Equalizer capability remains unavailable and playback continues normally.' "$audio_doc" \
  || fail 'audio/media docs no longer preserve graceful degradation without Equalizer backend tools'
grep -Fq 'Package-managed installs therefore do not need to hard-depend on EasyEffects or `socat`' "$audio_doc" \
  || fail 'audio/media docs no longer preserve the package optional-dependency contract'

# Teardown docs must preserve the ownership boundary across all install modes.
grep -Fq 'alis service disable' "$uninstall_doc" \
  || fail 'uninstall docs no longer remove per-user service wiring before manual/package removal'
grep -Fq 'alis service uninstall' "$uninstall_doc" \
  || fail 'uninstall docs no longer remove the manual make-install user unit before launcher removal'
grep -Fq 'sudo make uninstall' "$uninstall_doc" \
  || fail 'uninstall docs no longer document Makefile teardown'
grep -Fq '/usr/lib/systemd/user/alis.service' "$uninstall_doc" \
  || fail 'uninstall docs no longer identify pacman service ownership'
grep -Fq 'NixOS/Home Manager modules own `alis.service` declaratively' "$uninstall_doc" \
  || fail 'uninstall docs no longer preserve declarative Nix service ownership'
grep -Fq 'Run it as the user whose Alis service was configured' "$uninstall_doc" \
  || fail 'uninstall docs no longer warn against root cross-home cleanup'
grep -Fq -- "-type l -path '*.wants/alis.service' -delete" "$uninstall_doc" \
  || fail 'uninstall docs no longer use the working stale wants-link cleanup glob'

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - packaging metadata and distribution contracts are coherent'
