#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/module-runtime.sh"
COLOR_MODULE_ID="chrome"

main() {
  local enable_chrome
  enable_chrome=$(config_bool '.appearance.wallpaperTheming.enableChrome' true)
  if [[ "$enable_chrome" != 'true' ]]; then
    "$SCRIPT_DIR/apply-chrome-theme.sh" --disable || true
    exit 0
  fi
  "$SCRIPT_DIR/apply-chrome-theme.sh"
}

main "$@"
