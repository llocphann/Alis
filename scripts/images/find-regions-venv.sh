#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DISPATCH="$SCRIPT_DIR/../native-dispatch"

if [[ -x "$NATIVE_DISPATCH" ]]; then
    exec "$NATIVE_DISPATCH" find-regions "$@"
fi

if [[ -n "${ALIS_VENV:-}" ]]; then
    _ii_venv="$(eval echo "$ALIS_VENV")"
elif [[ -n "${ILLOGICAL_IMPULSE_VIRTUAL_ENV:-}" ]]; then
    _ii_venv="$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")"
else
    _ii_venv="$HOME/.local/state/quickshell/.venv"
fi
source "$_ii_venv/bin/activate" 2>/dev/null || true
"$_ii_venv/bin/python3" "$SCRIPT_DIR/find_regions.py" "$@"
deactivate 2>/dev/null || true
