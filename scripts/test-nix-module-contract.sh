#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

common="nix/module-common.nix"
nixos="nix/nixos-module.nix"
home="nix/home-module.nix"
package="nix/package.nix"
flake="flake.nix"
nix_workflow=".github/workflows/nix.yml"
switchwall="scripts/colors/switchwall.sh"
native_dispatch="scripts/native-dispatch"
color_generator="scripts/colors/generate_colors_material.py"
zed_module="scripts/colors/modules/31-zed.sh"
easyeffects_service="services/deferred/EasyEffects.qml"
default_config="defaults/config.json"
awww_service="services/AwwwBackend.qml"

for file in "$common" "$nixos" "$home" "$package" "$flake" "$nix_workflow" "$switchwall" "$native_dispatch" "$color_generator" "$zed_module" "$easyeffects_service" "$default_config" "$awww_service"; do
  [[ -f "$file" ]] || fail "missing Nix/runtime contract file: $file"
done

grep -Fq 'cfg = config.programs.alis;' "$home" \
  || fail 'Home Manager module no longer reads canonical programs.alis options'
grep -Fq 'cfg = config.programs.alis;' "$nixos" \
  || fail 'NixOS module no longer reads canonical programs.alis options'
grep -Fq 'extraPackages = lib.mkOption {' "$common" \
  || fail 'programs.alis.extraPackages option is missing'
grep -Fq 'description = "Extra runtime packages made available to the Alis shell service.";' "$common" \
  || fail 'extraPackages no longer documents its service PATH contract'

grep -Fq 'path = [ cfg.package ] ++ cfg.extraPackages;' "$nixos" \
  || fail 'NixOS service no longer exposes extraPackages on PATH'

grep -Fq 'lib.optionalAttrs (cfg.extraPackages != [ ])' "$home" \
  || fail 'Home Manager no longer guards the extraPackages PATH override'
grep -Fq 'PATH = lib.makeBinPath ([ cfg.package ] ++ cfg.extraPackages);' "$home" \
  || fail 'Home Manager service no longer exposes extraPackages on PATH'

while IFS= read -r runtime_dir; do
  [[ -n "$runtime_dir" && "$runtime_dir" != \#* ]] || continue
  [[ "$(grep -Fxc "      - '${runtime_dir}/**'" "$nix_workflow" || true)" == "2" ]] \
    || fail "Nix workflow does not watch canonical runtime directory: $runtime_dir"
done < sdata/runtime-payload-dirs.txt

while IFS= read -r runtime_file; do
  [[ -n "$runtime_file" && "$runtime_file" != \#* ]] || continue
  [[ "$(grep -Fxc "      - '${runtime_file}'" "$nix_workflow" || true)" == "2" ]] \
    || fail "Nix workflow does not watch canonical runtime root file: $runtime_file"
done < sdata/runtime-root-files.txt
[[ "$(grep -Fxc "      - '*.qml'" "$nix_workflow" || true)" == "2" ]] \
  || fail 'Nix workflow no longer watches automatically included root QML files'

# Nix-specific packaging/install ownership belongs in this deferred lane rather
# than the required non-Nix packaging contract.
grep -Fq 'for doc in docs/*.md; do' "$package" \
  || fail 'Nix package no longer installs repository documentation'
if grep -Fq '"$docs/${doc##*/}"' "$package"; then
  fail 'Nix package docs loop contains an unescaped Bash parameter expansion inside an indented string'
fi
grep -Fq 'install -Dm644 LICENSE "$out/share/licenses/alis/LICENSE"' "$package" \
  || fail 'Nix package no longer installs the project license'

grep -Fq 'nativeBackend = pkgs.rustPlatform.buildRustPackage {' "$package" \
  || fail 'Nix package no longer builds the qualified Rust backend'
grep -Fq 'cargoLock.lockFile = ../native/Cargo.lock;' "$package" \
  || fail 'Nix native backend no longer uses the committed Cargo.lock'
grep -Fq 'mkdir -p "$runtime/native/bin"' "$package" \
  || fail 'Nix package no longer installs native binaries into the runtime'

grep -Fq 'nixosModules.alis = nixosModule;' "$flake" \
  || fail 'public NixOS module alias missing'
grep -Fq 'homeModules.alis = homeModule;' "$flake" \
  || fail 'public Home Manager module alias missing'
grep -Fq '          alis = package;' "$flake" \
  || fail 'public Alis flake package alias missing'
grep -Fq 'Nix-managed installations keep alis.service declarative' "$package" \
  || fail 'Nix package no longer blocks mutable service ownership commands'
grep -Fq 'systemctl --user cat alis.service' "$package" \
  || fail 'Nix package no longer validates the declarative alis.service before start/restart'
grep -Fq 'install|uninstall|remove|enable|disable)' "$package" \
  || fail 'Nix service ownership guard no longer covers all mutating service commands'
grep -Fqx '      ${materialSymbolsWrapperArg} \' "$package" \
  || fail 'Nix optional font wrapper argument no longer preserves makeWrapper continuation when empty'

grep -Fq 'flock -w 5 200' "$switchwall" \
  || fail 'switchwall no longer exercises the flock runtime dependency contract'
grep -Fq '++ optionalTop "util-linux"' "$package" \
  || fail 'Nix runtime no longer provides util-linux for switchwall flock locking'

grep -Fq 'bundledFonts = pkgs.runCommand "alis-bundled-fonts"' "$package" \
  || fail 'Nix runtime no longer bundles local Alis fonts'
grep -Fq 'for binary in alis-inputd alis-mpdd alis-native alis-theme; do' "$package" \
  || fail 'Nix native backend no longer packages all four Rust helpers'
grep -Fq 'elif command -v python3 >/dev/null 2>&1; then' "$native_dispatch" \
  || fail 'native selector no longer honors the Nix-wrapped Python PATH'
if grep -Fq '_ii_python=' "$switchwall" || grep -Fq 'source "$_ii_venv/bin/activate"' "$switchwall"; then
  fail 'switchwall must not eagerly select or activate Python before native-dispatch'
fi

grep -Fq 'Quickshell.execDetached(["/usr/bin/env", "easyeffects", "--service-mode"])' "$easyeffects_service" \
  || fail 'EasyEffects service no longer exercises the PATH-resolved native runtime contract'
if grep -Fq '++ optionalTop "easyeffects"' "$package"; then
  fail 'Nix runtime hard-wires optional EasyEffects backend; provide it through programs.alis.extraPackages when desired'
fi
if grep -Fq '++ optionalTop "socat"' "$package"; then
  fail 'Nix runtime hard-wires optional EasyEffects transport; provide it through programs.alis.extraPackages when desired'
fi

python3 -c 'import json, sys; data=json.load(open(sys.argv[1], encoding="utf-8")); assert data["background"]["backend"]["provider"] == "internal"' "$default_config" \
  || fail 'fresh-install wallpaper backend is no longer internal'
grep -Fq 'readonly property string provider: Config.options?.background?.backend?.provider ?? "internal"' "$awww_service" \
  || fail 'Awww backend no longer reads configured provider'
grep -Fq 'let command = "awww img"' "$awww_service" \
  || fail 'Awww backend no longer exercises the opt-in awww client runtime contract'

python3 -c 'import json, sys; data=json.load(open(sys.argv[1], encoding="utf-8")); assert data["apps"]["volumeMixer"] == "pavucontrol"' "$default_config" \
  || fail 'fresh-install volume mixer is no longer pavucontrol; update the Nix runtime contract deliberately'
grep -Fq '++ optionalTop "pavucontrol"' "$package" \
  || fail 'Nix runtime no longer provides the fresh-install volume mixer'

python3 -c 'import json, sys; data=json.load(open(sys.argv[1], encoding="utf-8")); assert data["apps"]["taskManager"] == "missioncenter"' "$default_config" \
  || fail 'fresh-install task manager is no longer missioncenter; update the Nix runtime contract deliberately'
grep -Fq '++ optionalTop "mission-center"' "$package" \
  || fail 'Nix runtime no longer provides the fresh-install task manager'

python3 -c 'import json, sys; data=json.load(open(sys.argv[1], encoding="utf-8")); assert data["apps"]["bluetooth"] == "blueman-manager"' "$default_config" \
  || fail 'fresh-install Bluetooth manager is no longer blueman-manager; update the Nix runtime contract deliberately'
grep -Fq '++ optionalTop "blueman"' "$package" \
  || fail 'Nix runtime no longer provides the fresh-install Bluetooth manager'

python3 -c 'import json, sys; data=json.load(open(sys.argv[1], encoding="utf-8")); assert data["apps"]["network"] == "nm-connection-editor" and data["apps"]["networkEthernet"] == "nm-connection-editor"' "$default_config" \
  || fail 'fresh-install network settings no longer use nm-connection-editor; update the Nix runtime contract deliberately'
grep -Fq '++ optionalTop "networkmanagerapplet"' "$package" \
  || fail 'Nix runtime no longer provides the fresh-install network settings editor'

bash -n "$zed_module" || fail 'Zed theming module has invalid Bash syntax'
grep -Fq 'python_cmd="$(venv_python)"' "$zed_module" \
  || fail 'packaged Zed theming no longer resolves the managed/package Python runtime'
grep -Fq '"$python_cmd" "$SCRIPT_DIR/generate_terminal_configs.py"' "$zed_module" \
  || fail 'packaged Zed theming no longer falls back to the shipped Python generator'
grep -Fq -- '--zed >> "$ZED_THEMEGEN_LOG" 2>&1' "$zed_module" \
  || fail 'packaged Zed Python fallback no longer requests Zed theme generation'

printf '%s\n' '1..1'
printf '%s\n' 'ok 1 - NixOS, Home Manager, and packaged runtime contracts are coherent'
