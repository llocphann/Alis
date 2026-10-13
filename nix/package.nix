{ pkgs }:

let
  lib = pkgs.lib;
  packageVersion = lib.removeSuffix "\n" (builtins.readFile ../VERSION);
  nativeBackend = pkgs.rustPlatform.buildRustPackage {
    pname = "alis-native-backend";
    version = packageVersion;
    src = lib.cleanSource ../native;
    cargoLock.lockFile = ../native/Cargo.lock;
    cargoBuildFlags = [ "--workspace" ];
    doCheck = false;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin"
      native_bin="$(find target -type f -path '*/release/alis-native' -perm -0100 -print -quit)"
      test -n "$native_bin"
      release="$(dirname "$native_bin")"
      for binary in alis-inputd alis-mpdd alis-native alis-theme; do
        test -x "$release/$binary"
        install -m0755 "$release/$binary" "$out/bin/$binary"
      done
      runHook postInstall
    '';
  };
  optionalTop = name:
    lib.optional (builtins.hasAttr name pkgs) (builtins.getAttr name pkgs);

  optionalKde = name:
    lib.optional
      (builtins.hasAttr "kdePackages" pkgs && builtins.hasAttr name pkgs.kdePackages)
      (builtins.getAttr name pkgs.kdePackages);

  optionalQt6 = name:
    lib.optional
      (builtins.hasAttr "qt6" pkgs && builtins.hasAttr name pkgs.qt6)
      (builtins.getAttr name pkgs.qt6);

  colorPython = with pkgs;
    (python3.withPackages (pythonPackages: with pythonPackages; [
      materialyoucolor
      numpy
      pillow
    ]));

  runtimeDeps =
    with pkgs; [
      bash
      bc
      coreutils
      curl
      findutils
      gawk
      git
      gnugrep
      gnused
      jq
      procps
      colorPython
      ripgrep
      rsync
      systemd
      wget
      xdg-user-dirs
      xdg-utils

      quickshell
      wl-clipboard
      cliphist
      grim
      slurp
      playerctl
      libnotify
      glib
      pipewire
      pulseaudio
      wireplumber
    ]
    ++ optionalTop "util-linux"
    ++ optionalTop "awww"
    ++ optionalTop "blueman"
    ++ optionalTop "brightnessctl"
    ++ optionalTop "cava"
    ++ optionalTop "ddcutil"
    ++ optionalTop "ffmpeg"
    ++ optionalTop "fish"
    ++ optionalTop "foot"
    ++ optionalTop "fuzzel"
    ++ optionalTop "geoclue2"
    ++ optionalTop "hyprland"
    ++ optionalTop "hyprpicker"
    ++ optionalTop "gum"
    ++ optionalTop "imagemagick"
    ++ optionalTop "kitty"
    ++ optionalTop "libqalculate"
    ++ optionalTop "mission-center"
    ++ optionalTop "mpv"
    ++ optionalTop "nautilus"
    ++ optionalTop "networkmanager"
    ++ optionalTop "networkmanagerapplet"
    ++ optionalTop "pavucontrol"
    ++ optionalTop "songrec"
    ++ optionalTop "swappy"
    ++ optionalTop "tesseract"
    ++ optionalTop "translate-shell"
    ++ optionalTop "upower"
    ++ optionalTop "wf-recorder"
    ++ optionalTop "wlsunset"
    ++ optionalTop "wtype"
    ++ optionalTop "xwayland-satellite"
    ++ optionalTop "ydotool"
    ++ optionalKde "breeze-icons"
    ++ optionalKde "kdialog"
    ++ optionalKde "kirigami"
    ++ optionalKde "kconfig"
    ++ optionalKde "plasma-integration"
    ++ optionalKde "syntax-highlighting"
    ++ optionalKde "xembedsniproxy"
    ++ optionalQt6 "qt5compat"
    ++ optionalQt6 "qtbase"
    ++ optionalQt6 "qtdeclarative"
    ++ optionalQt6 "qtimageformats"
    ++ optionalQt6 "qtmultimedia"
    ++ optionalQt6 "qtpositioning"
    ++ optionalQt6 "qtquicktimeline"
    ++ optionalQt6 "qtsensors"
    ++ optionalQt6 "qtsvg"
    ++ optionalQt6 "qttools"
    ++ optionalQt6 "qttranslations"
    ++ optionalQt6 "qtvirtualkeyboard"
    ++ optionalQt6 "qtwayland";

  materialSymbolsFont =
    if builtins.hasAttr "material-symbols" pkgs
    then pkgs.makeFontsConf { fontDirectories = [ pkgs.material-symbols ]; }
    else null;
  materialSymbolsWrapperArg =
    lib.optionalString (materialSymbolsFont != null)
      "--set FONTCONFIG_FILE \"${materialSymbolsFont}\"";

  qmlDeps =
    # kirigami-wrapped ships no QML files, use the unwrapped version.
    (lib.optional
      (builtins.hasAttr "kdePackages" pkgs && builtins.hasAttr "kirigami" pkgs.kdePackages)
      pkgs.kdePackages.kirigami.passthru.unwrapped)
    ++ optionalKde "syntax-highlighting"
    ++ optionalQt6 "qt5compat"
    ++ optionalQt6 "qtdeclarative"
    ++ optionalQt6 "qtimageformats"
    ++ optionalQt6 "qtmultimedia"
    ++ optionalQt6 "qtpositioning"
    ++ optionalQt6 "qtquicktimeline"
    ++ optionalQt6 "qtsensors"
    ++ optionalQt6 "qtsvg"
    ++ optionalQt6 "qtvirtualkeyboard"
    ++ optionalQt6 "qtwayland";
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "alis";
  version = packageVersion;
  src = lib.cleanSource ../.;

  nativeBuildInputs = [ pkgs.makeWrapper pkgs.python3 pkgs.rsync ];

  # Prevent patchShebangs from attempting to rewrite Python scripts;
  # non-executable files are skipped during fixupPhase.
  preFixup = ''
    find "$out/share/quickshell/alis" -type f -name '*.py' -exec chmod -x {} +
  '';

  postFixup = ''
    find "$out/share/quickshell/alis" -type f -name '*.py' -exec chmod +x {} +
  '';

  installPhase = ''
    runHook preInstall

    runtime="$out/share/quickshell/alis"
    docs="$out/share/doc/alis"
    mkdir -p \
      "$runtime" \
      "$docs" \
      "$out/bin" \
      "$out/share/applications" \
      "$out/share/icons/hicolor/scalable/apps"

    python3 sdata/lib/runtime-payload.py copy --root . --target "$runtime"

    mkdir -p "$runtime/native/bin"
    for binary in alis-inputd alis-mpdd alis-native alis-theme; do
      install -m0755 "${nativeBackend}/bin/$binary" "$runtime/native/bin/$binary"
    done

    chmod +x "$runtime/setup" "$runtime/scripts/alis" "$runtime/scripts/alis"
    find "$runtime/scripts" -type f \( -name '*.sh' -o -name '*.fish' -o -name '*.py' \) -exec chmod +x {} +

    # The source tree intentionally targets Arch, where helpers live under
    # /usr/bin. NixOS does not provide that layout. Patch only the packaged
    # copy and keep shebang lines intact.
    find "$runtime/modules" "$runtime/services" "$runtime/defaults" "$runtime/scripts" \
      -type f \( -name '*.qml' -o -name '*.js' -o -name '*.sh' -o -name '*.py' \) \
      -exec sed -i '1!s#/usr/bin/##g' {} +

    # Keep direct runtime entrypoints package-aware even when they are invoked
    # outside $out/bin/alis and therefore do not inherit makeWrapper variables.
    # Package-managed maintenance must also never copy the raw launcher into
    # ~/.local/bin, where it would shadow the Nix wrapper on later invocations.
    # NixOS/Home Manager own alis.service declaratively, so the packaged CLI
    # must not materialize or delete mutable user units/wants links either.
    python3 - \
      "$runtime/setup" \
      "$runtime/scripts/alis" \
      "$runtime/sdata/lib/versioning.sh" \
      "$runtime" <<'PY'
from pathlib import Path
import sys

setup_path = Path(sys.argv[1])
launcher_path = Path(sys.argv[2])
versioning_path = Path(sys.argv[3])
runtime = sys.argv[4]

setup = setup_path.read_text()
marker = "sync_launcher_from_repo() {\n"
guard = """sync_launcher_from_repo() {
    if [[ "$(get_installed_update_strategy 2>/dev/null || true)" == "package-manager" ]]; then
        return 0
    fi
"""
if setup.count(marker) != 1:
    raise SystemExit("expected exactly one sync_launcher_from_repo definition")
setup_path.write_text(setup.replace(marker, guard, 1))

launcher = launcher_path.read_text()
launcher_default = 'system_config_dir="$' + '{ALIS_SYSTEM_RUNTIME_DIR:-/usr/local/share/quickshell/alis}"'
launcher_value = 'system_config_dir="$' + '{ALIS_SYSTEM_RUNTIME_DIR:-' + runtime + '}"'
count = launcher.count(launcher_default)
if count != 1:
    raise SystemExit("expected exactly one launcher runtime default")
launcher = launcher.replace(launcher_default, launcher_value, 1)

ensure_marker = """ensure_service_unit_available() {
    # Always reinstall the service template to pick up improvements (e.g. KillMode,
"""
ensure_guard = """ensure_service_unit_available() {
    require_command systemctl
    if ! systemctl --user cat alis.service >/dev/null 2>&1; then
        echo "alis.service is not provisioned by Nix; enable programs.alis.service in NixOS or Home Manager" >&2
        return 1
    fi
    return 0

    # Always reinstall the service template to pick up improvements (e.g. KillMode,
"""
if launcher.count(ensure_marker) != 1:
    raise SystemExit("expected exactly one ensure_service_unit_available definition")
launcher = launcher.replace(ensure_marker, ensure_guard, 1)

service_marker = (
    'run_service_command() {\n'
    '    local action="$' + '{1:-status}"\n'
    '    shift || true\n\n'
    '    case "$action" in\n'
)
service_guard = (
    'run_service_command() {\n'
    '    local action="$' + '{1:-status}"\n'
    '    shift || true\n\n'
    '    case "$action" in\n'
    '        install|uninstall|remove|enable|disable)\n'
    '            echo "Nix-managed installations keep alis.service declarative; configure programs.alis.service and rebuild." >&2\n'
    '            return 1\n'
    '            ;;\n'
    '    esac\n\n'
    '    case "$action" in\n'
)
if launcher.count(service_marker) != 1:
    raise SystemExit("expected exactly one run_service_command definition")
launcher = launcher.replace(service_marker, service_guard, 1)
launcher_path.write_text(launcher)

versioning = versioning_path.read_text()
versioning_default = 'RUNTIME_DIR_SYSTEM_LOCAL="$' + '{ALIS_SYSTEM_RUNTIME_DIR_LOCAL:-/usr/local/share/quickshell/alis}"'
versioning_value = 'RUNTIME_DIR_SYSTEM_LOCAL="$' + '{ALIS_SYSTEM_RUNTIME_DIR_LOCAL:-' + runtime + '}"'
count = versioning.count(versioning_default)
if count != 1:
    raise SystemExit("expected exactly one versioning runtime default")
versioning_path.write_text(versioning.replace(versioning_default, versioning_value, 1))

PY
    grep -Fq 'get_installed_update_strategy 2>/dev/null || true' "$runtime/setup"
    grep -Fq "$runtime" "$runtime/scripts/alis"
    grep -Fq 'Nix-managed installations keep alis.service declarative' "$runtime/scripts/alis"
    grep -Fq 'systemctl --user cat alis.service' "$runtime/scripts/alis"
    grep -Fq "$runtime" "$runtime/sdata/lib/versioning.sh"

    cat > "$runtime/version.json" <<'EOF'
{
  "version": "${packageVersion}",
  "commit": "nix-package",
  "installed_at": "nix-store",
  "installedAt": "nix-store",
  "source": "nix",
  "repo_path": "",
  "repoPath": "",
  "install_mode": "package-managed",
  "installMode": "package-managed",
  "update_strategy": "package-manager",
  "updateStrategy": "package-manager",
  "package_manager": "nix",
  "packageManager": "nix",
  "package_name": "alis",
  "packageName": "alis",
  "package_update_hint": "update the Alis source/input and rebuild your NixOS or Home Manager configuration",
  "packageUpdateHint": "update the Alis source/input and rebuild your NixOS or Home Manager configuration"
}
EOF

    makeWrapper "$runtime/scripts/alis" "$out/bin/alis" \
      --prefix PATH : "${lib.makeBinPath runtimeDeps}" \
      --prefix QML2_IMPORT_PATH : "${lib.makeSearchPath "lib/qt-6/qml" qmlDeps}" \
      --prefix QT_PLUGIN_PATH : "${lib.makeSearchPath "lib/qt-6/plugins" qmlDeps}" \
      ${materialSymbolsWrapperArg} \
      --set-default ALIS_SYSTEM_RUNTIME_DIR "$runtime" \
      --set-default ALIS_FALLBACK_SYSTEM_RUNTIME_DIR "$runtime"

    sed "s|^Exec=alis|Exec=$out/bin/alis|" \
      assets/applications/alis.desktop > "$out/share/applications/alis.desktop"
    sed "s|^Exec=alis|Exec=$out/bin/alis|" \
      assets/applications/alis-settings.desktop > "$out/share/applications/alis-settings.desktop"
    chmod 0644 \
      "$out/share/applications/alis.desktop" \
      "$out/share/applications/alis-settings.desktop" \
      "$out/share/applications/alis-settings.desktop"
    install -Dm644 assets/icons/desktop-symbolic.svg \
      "$out/share/icons/hicolor/scalable/apps/alis.svg"

    install -Dm644 README.md "$docs/README.md"
    for doc in docs/*.md; do
      install -Dm644 "$doc" "$docs/''${doc##*/}"
    done
    install -Dm644 LICENSE "$out/share/licenses/alis/LICENSE"

    runHook postInstall
  '';

  passthru = {
    runtimeDependencies = runtimeDeps;
    qmlDependencies = qmlDeps;
  };

  meta = {
    description = "Alis desktop shell runtime built on Quickshell";
    homepage = "https://github.com/llocphann/Alis";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "alis";
  };
}
