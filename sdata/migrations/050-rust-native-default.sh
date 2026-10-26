#!/usr/bin/env bash
MIGRATION_ID="050-rust-native-default"
MIGRATION_TITLE="Activate qualified Rust backend"
MIGRATION_DESCRIPTION="Promotes the qualified Rust helpers to production while retaining Python as an explicit fallback."
MIGRATION_TARGET_FILE=""
MIGRATION_REQUIRED=true
migration_check() { local d="${XDG_STATE_HOME:-$HOME/.local/state}/inir" m=""; m="$(head -n 1 "$d/native-backend" 2>/dev/null || true)"; [[ "$m" != rust ]]; }
migration_preview() { echo "Persist Rust backend; clear benchmark-only binary path and systemd selector overrides"; }
migration_apply() { local d="${XDG_STATE_HOME:-$HOME/.local/state}/inir"; mkdir -p "$d"; printf '%s\n' rust > "$d/native-backend"; rm -f "$d/native-bin-dir"; command -v systemctl >/dev/null 2>&1 && systemctl --user unset-environment INIR_NATIVE_BACKEND INIR_NATIVE_BIN_DIR INIR_NATIVE_STRICT >/dev/null 2>&1 || true; }
