#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT

source_fingerprint() {
  {
    git status --porcelain=v1 --untracked-files=all
    git diff --no-ext-diff --binary -- .
  } | sha256sum | awk '{print $1}'
}

source_before="$(source_fingerprint)"

prefix=/opt/inir
systemd_user_dir="$prefix/lib/systemd/user"
libexecdir="$prefix/libexec"
polkit_actions_dir="$prefix/share/polkit-1/actions"
tlp_confdir="$prefix/etc/tlp.d"
system_share="$prefix/share/inir"

make_args=(
  "DESTDIR=$stage"
  "PREFIX=$prefix"
  "SYSTEMD_USER_DIR=$systemd_user_dir"
  "LIBEXECDIR=$libexecdir"
  "POLKIT_ACTIONS_DIR=$polkit_actions_dir"
  "TLP_CONFDIR=$tlp_confdir"
  "INIR_SYSTEM_SHAREDIR=$system_share"
)

make -s install "${make_args[@]}"

source_after_install="$(source_fingerprint)"
if [[ "$source_after_install" != "$source_before" ]]; then
  printf 'FAIL: make install mutated the source checkout\n' >&2
  git status --short --untracked-files=all >&2 || true
  git diff --summary -- . >&2 || true
  exit 1
fi

expected_files=(
  "$stage$prefix/bin/inir"
  "$stage$prefix/bin/alis"
  "$stage$prefix/share/quickshell/inir/scripts/alis"
  "$stage$prefix/share/quickshell/inir/shell.qml"
  "$stage$prefix/share/quickshell/inir/qmldir"
  "$stage$prefix/share/quickshell/inir/version.json"
  "$stage$prefix/share/quickshell/inir/native/bin/inir-inputd"
  "$stage$prefix/share/quickshell/inir/native/bin/inir-mpdd"
  "$stage$prefix/share/quickshell/inir/native/bin/inir-native"
  "$stage$prefix/share/quickshell/inir/native/bin/inir-theme"
  "$stage$systemd_user_dir/inir.service"
  "$stage$prefix/share/applications/inir.desktop"
  "$stage$prefix/share/applications/inir-settings.desktop"
  "$stage$prefix/share/icons/hicolor/scalable/apps/inir.svg"
  "$stage$prefix/share/doc/inir-shell/README.md"
  "$stage$prefix/share/doc/inir-shell/AUDIO_MEDIA.md"
  "$stage$prefix/share/doc/inir-shell/INSTALL.md"
  "$stage$prefix/share/doc/inir-shell/PACKAGES.md"
  "$stage$prefix/share/doc/inir-shell/RELEASING.md"
  "$stage$prefix/share/doc/inir-shell/UNINSTALL.md"
  "$stage$prefix/share/licenses/inir-shell/LICENSE"
)

optional_files=(
  "$stage$libexecdir/inir-battery-charge-limit"
  "$stage$libexecdir/inir-thinkfan"
  "$stage$polkit_actions_dir/org.inir.battery-charge-limit.policy"
  "$stage$polkit_actions_dir/org.inir.thinkfan.policy"
  "$stage$system_share/tlp-settings-schema.json"
  "$stage$tlp_confdir/99-inir-battery-charge-limit.conf"
  "$stage$tlp_confdir/99-inir-tlp-settings.conf"
  "$stage$prefix/share/hadalird/current/manifest.json"
)
for path in "${optional_files[@]}"; do
  [[ ! -e "$path" ]] || { printf 'FAIL: core installed optional integration %s\n' "$path" >&2; exit 1; }
  mkdir -p "$(dirname "$path")"
  printf '%s\n' 'preserve optional package and owner state' > "$path"
done
optional_before="$(sha256sum "${optional_files[@]}")"

for path in "${expected_files[@]}"; do
  [[ -e "$path" ]] || {
    printf 'FAIL: staged install missing %s\n' "$path" >&2
    exit 1
  }
done

runtime_dir="$stage$prefix/share/quickshell/inir"
retired_integrations=(
  assets/helpers/inir-battery-charge-limit
  assets/helpers/inir-thinkfan
  assets/polkit/org.inir.battery-charge-limit.policy
  assets/polkit/org.inir.thinkfan.policy
  assets/tlp/tlp-settings-schema.json
  scripts/integrations/obsidian_theme.py
  scripts/notes/zettelkasten.py
  scripts/todo/obsidian_todo.py
  scripts/todo/obsidian_daily_todo.py
  scripts/todo/obsidian_tasks.py
)
for relative in "${retired_integrations[@]}"; do
  [[ ! -e "$runtime_dir/$relative" ]] || { printf 'FAIL: duplicate optional payload installed in core: %s\n' "$relative" >&2; exit 1; }
done
if ! fish "$repo_root/scripts/qml-check.fish" --all --root "$runtime_dir"; then
  printf 'FAIL: fresh staged runtime QML/module resolution is invalid\n' >&2
  exit 1
fi

# An in-place reinstall must mirror the managed runtime tree. Seed the exact
# class of retired module that caused the mixed-runtime startup incident, a
# retired root-level QML file, plus an excluded private/test artifact that the
# payload policy intentionally does not own. Reinstalling must prune managed
# stale QML without deleting the excluded artifact.
stale_module="$runtime_dir/modules/dock/Stale.qml"
stale_root_qml="$runtime_dir/RetiredRoot.qml"
preserved_excluded="$runtime_dir/scripts/test-local-private.sh"
mkdir -p "$(dirname "$stale_module")" "$(dirname "$preserved_excluded")"
printf '%s\n' 'import QtQuick' > "$stale_module"
printf '%s\n' 'import QtQuick' > "$stale_root_qml"
printf '%s\n' '# private excluded artifact' > "$preserved_excluded"
for relative in "${retired_integrations[@]}"; do
  mkdir -p "$(dirname "$runtime_dir/$relative")"
  printf '%s\n' 'retired core duplicate' > "$runtime_dir/$relative"
done
make -s install "${make_args[@]}"
for stale_path in "$stale_module" "$stale_root_qml"; do
  if [[ -e "$stale_path" || -L "$stale_path" ]]; then
    printf 'FAIL: make reinstall left stale managed QML path %s\n' "$stale_path" >&2
    exit 1
  fi
done
for relative in "${retired_integrations[@]}"; do
  [[ ! -e "$runtime_dir/$relative" ]] || { printf 'FAIL: core reinstall retained retired optional payload: %s\n' "$relative" >&2; exit 1; }
done
if [[ ! -f "$preserved_excluded" ]]; then
  printf 'FAIL: make reinstall deleted an excluded private/test runtime artifact\n' >&2
  exit 1
fi
if ! fish "$repo_root/scripts/qml-check.fish" --all --root "$runtime_dir"; then
  printf 'FAIL: reinstalled staged runtime QML/module resolution is invalid\n' >&2
  exit 1
fi

for action in install-battery-helper install-thinkfan-helper uninstall-battery-helper uninstall-thinkfan-helper; do
  if make -s "$action" "${make_args[@]}" >"$stage/retired-helper.log" 2>&1; then
    printf 'FAIL: retired core helper target succeeded: %s\n' "$action" >&2
    exit 1
  fi
  grep -Fq 'optional Hadalird' "$stage/retired-helper.log" || { cat "$stage/retired-helper.log"; exit 1; }
done
rm -f "$stage/retired-helper.log"
[[ "$(sha256sum "${optional_files[@]}")" == "$optional_before" ]] || {
  printf 'FAIL: core reinstall/helper targets modified optional integration state\n' >&2; exit 1;
}

# The staged install must remain entirely inside DESTDIR. This catches install
# targets that accidentally write to the host when packagers use a staging root.
if find "$stage" -mindepth 1 -maxdepth 1 ! -name opt -print -quit | grep -q .; then
  printf 'FAIL: staged install wrote outside the configured /opt prefix\n' >&2
  find "$stage" -mindepth 1 -maxdepth 2 -print >&2
  exit 1
fi

make -s uninstall "${make_args[@]}"

source_after_uninstall="$(source_fingerprint)"
if [[ "$source_after_uninstall" != "$source_before" ]]; then
  printf 'FAIL: make uninstall mutated the source checkout\n' >&2
  git status --short --untracked-files=all >&2 || true
  git diff --summary -- . >&2 || true
  exit 1
fi

for path in "${expected_files[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf 'FAIL: staged uninstall left %s\n' "$path" >&2
    exit 1
  fi
done

[[ "$(sha256sum "${optional_files[@]}")" == "$optional_before" ]] || {
  printf 'FAIL: core uninstall modified optional integration state\n' >&2; exit 1;
}

# Empty parent directories are harmless, but no managed payload file may remain.
# Excluded/private artifacts are intentionally outside reinstall ownership; a
# full uninstall removes the runtime directory and may remove them as collateral.
remaining="$(find "$stage$prefix" \( -type f -o -type l \) -print | sort)"
preserved="$(printf '%s\n' "${optional_files[@]}" | sort)"
if [[ "$remaining" != "$preserved" ]]; then
  printf 'FAIL: staged uninstall left managed files behind\n' >&2
  find "$stage$prefix" \( -type f -o -type l \) -print >&2
  exit 1
fi

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - make install/reinstall/uninstall staging lifecycle is coherent'
