#!/usr/bin/env bash
# Opt-in installer for Pocket-Dots Character Outline (`perfil`) AI cutout venv.
# Never run automatically without explicit user action (AGENTS.md Rule 7).
set -euo pipefail

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
VENV_ROOT="${ALIS_WALLFX_VENV_DIR:-$XDG_DATA_HOME/alis/wallfx-venv}"
VENV_PY="$VENV_ROOT/venv/bin/python"

if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: 'uv' is required to install the WallFX AI cutout environment (sudo pacman -S uv)." >&2
    exit 1
fi

mkdir -p "$VENV_ROOT" "$VENV_ROOT/models"
echo "[wallfx] Creating isolated Python environment at $VENV_ROOT/venv..."
uv venv -q "$VENV_ROOT/venv"

echo "[wallfx] Installing rembg + OpenVINO/ONNXRuntime + OpenCV (headless)..."
if ! uv pip install -q --python "$VENV_PY" rembg onnxruntime-openvino opencv-python-headless numpy pillow; then
    echo "[wallfx] Falling back to CPU onnxruntime..."
    uv pip install -q --python "$VENV_PY" rembg onnxruntime opencv-python-headless numpy pillow
fi

echo "[wallfx] Pre-downloading BiRefNet-General-Lite cutout model (~210 MB)..."
U2NET_HOME="$VENV_ROOT/models" "$VENV_PY" -c '
from rembg import new_session
new_session("birefnet-general-lite", providers=["CPUExecutionProvider"])
print("[wallfx] BiRefNet-General-Lite ready.")
'

echo "WALLFX_AI_INSTALL_OK"
