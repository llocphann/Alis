#!/usr/bin/env bash
# Execute a test command inside an invisible, zero-focus virtual Wayland session.
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
need_niri=0
if [[ "${1:-}" == "--need-niri" ]]; then
    need_niri=1
    shift
fi
if [[ "${1:-}" == "--" ]]; then
    shift
fi
extra_args=(--keep-xdg)
if (( need_niri == 1 )); then
    extra_args+=(--need-niri)
fi
exec python3 "$script_dir/../native_test_session.py" "${extra_args[@]}" -- "$@"
