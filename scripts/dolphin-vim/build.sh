#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$HOME/.local/lib"
g++ -shared -fPIC -O2 $(pkg-config --cflags Qt6Widgets Qt6Gui Qt6Core) \
    "$HOME/.local/share/dolphin-vim/dolphin_vim_keys.cpp" \
    -o "$HOME/.local/lib/libdolphin_vim_keys.so" \
    $(pkg-config --libs Qt6Widgets Qt6Gui Qt6Core)
