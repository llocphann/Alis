#!/usr/bin/env bash
# Read-only compatibility inputs. Canonical values, including explicit empty
# opt-outs, win; imported values are exported for QML and helper subprocesses.
alis_import_legacy_environment() {
    local suffix canonical legacy legacy_prefix='IN''IR_'
    for suffix in RUNTIME_DIR SYSTEM_RUNTIME_DIR FALLBACK_SYSTEM_RUNTIME_DIR \
        SYSTEM_RUNTIME_DIR_LOCAL LEGACY_SYSTEM_RUNTIME_DIR_LOCAL LEGACY_SYSTEM_RUNTIME_DIR \
        RESTART_POLL_DELAY RESTART_MAX_POLLS MAX_RAPID_RESTARTS RESTART_WINDOW \
        DISABLE_HOT_RELOAD GPU_FORCE_DEFAULT QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE \
        LAUNCHER_PATH VENV NATIVE_BACKEND NATIVE_BIN_DIR NATIVE_STRICT MPD_SOCKET \
        SHELL_ROOT THEME_SKIP_SDDM_SYNC INSTALL_MODE UPDATE_STRATEGY REPO_PATH \
        PACKAGE_MANAGER PACKAGE_NAME PACKAGE_UPDATE_HINT FCITX5_DATA_DIR; do
        canonical="ALIS_$suffix"; legacy="$legacy_prefix$suffix"
        if [[ ! -v "$canonical" && -v "$legacy" ]]; then
            printf -v "$canonical" '%s' "${!legacy}"
            export "$canonical"
        fi
    done
}
alis_import_legacy_environment
