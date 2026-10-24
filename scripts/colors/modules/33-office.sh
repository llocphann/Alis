#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/module-runtime.sh"
COLOR_MODULE_ID="office"
# Run even when disabled: the adapter must release only its own preferences.
# It is opt-in, user-scoped and never starts/restarts an office application.
if output="$("$(venv_python)" "$SCRIPT_DIR/office_theme.py" --config "$CONFIG_FILE")"; then
    log_module "$output"
else
    log_module "$output"
    exit 1
fi
