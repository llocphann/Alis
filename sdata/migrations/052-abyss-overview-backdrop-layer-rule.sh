#!/usr/bin/env bash
# Migration: ensure Niri can render Hadalis wallpaper inside its built-in
# Overview backdrop. The original optional migration could be skipped, while
# Abyss now deliberately reuses the stable quickshell:iiBackdrop namespace.

MIGRATION_ID="052-abyss-overview-backdrop-layer-rule"
MIGRATION_TITLE="Restore wallpaper in Niri Overview"
MIGRATION_DESCRIPTION="Ensures Hadalis backdrop wallpaper surfaces are placed inside Niri's built-in Overview backdrop, including hot-corner activation."
MIGRATION_REQUIRED=true

_overview_backdrop_niri_dir() {
  printf '%s/niri' "${XDG_CONFIG_HOME:-$HOME/.config}"
}

_overview_backdrop_target_file() {
  local niri_dir
  niri_dir="$(_overview_backdrop_niri_dir)"
  if [[ -f "$niri_dir/config.d/80-layer-rules.kdl" ]]; then
    printf '%s' "$niri_dir/config.d/80-layer-rules.kdl"
  else
    printf '%s' "$niri_dir/config.kdl"
  fi
}

MIGRATION_TARGET_FILE="$(_overview_backdrop_target_file)"

_overview_backdrop_has_rule() {
  local namespace="$1"
  local niri_dir
  niri_dir="$(_overview_backdrop_niri_dir)"

  python3 - "$niri_dir" "$namespace" <<'PY'
from pathlib import Path
import re
import sys

niri_dir = Path(sys.argv[1])
namespace = sys.argv[2]
paths = []
root = niri_dir / "config.kdl"
if root.is_file():
    paths.append(root)
config_d = niri_dir / "config.d"
if config_d.is_dir():
    paths.extend(sorted(config_d.glob("*.kdl")))

needle = re.compile(r'\bmatch\s+namespace\s*=\s*"' + re.escape(namespace) + r'"')
for path in paths:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        continue
    # Ignore commented examples so a dormant rule cannot suppress repair.
    active = "\n".join(
        line.split("//", 1)[0]
        for line in lines
        if not line.lstrip().startswith("//")
    )
    if needle.search(active):
        raise SystemExit(0)
raise SystemExit(1)
PY
}

migration_check() {
  local niri_dir
  niri_dir="$(_overview_backdrop_niri_dir)"
  [[ -f "$niri_dir/config.kdl" || -f "$niri_dir/config.d/80-layer-rules.kdl" ]] || return 1

  if ! _overview_backdrop_has_rule "quickshell:iiBackdrop"; then
    return 0
  fi
  if ! _overview_backdrop_has_rule "quickshell:wBackdrop"; then
    return 0
  fi
  return 1
}

migration_preview() {
  echo -e "${STY_GREEN:-}+ Niri place-within-backdrop rule for Abyss/Material wallpaper${STY_RST:-}"
  echo -e "${STY_GREEN:-}+ Niri place-within-backdrop rule for Waffle wallpaper${STY_RST:-}"
}

migration_diff() {
  cat <<'DIFF'
Missing rules are appended to the active Niri layer-rule file:

layer-rule {
    match namespace="quickshell:iiBackdrop"
    place-within-backdrop true
    opacity 1.0
}

layer-rule {
    match namespace="quickshell:wBackdrop"
    place-within-backdrop true
    opacity 1.0
}
DIFF
}

migration_apply() {
  local niri_dir target need_ii=false need_waffle=false
  niri_dir="$(_overview_backdrop_niri_dir)"
  target="$(_overview_backdrop_target_file)"

  [[ -f "$niri_dir/config.kdl" || -f "$niri_dir/config.d/80-layer-rules.kdl" ]] || return 0

  _overview_backdrop_has_rule "quickshell:iiBackdrop" || need_ii=true
  _overview_backdrop_has_rule "quickshell:wBackdrop" || need_waffle=true

  if [[ "$need_ii" != true && "$need_waffle" != true ]]; then
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  {
    printf '\n// Hadalis wallpaper surfaces inside Niri Overview/hot-corner backdrop.\n'
    if [[ "$need_ii" == true ]]; then
      cat <<'RULE'

layer-rule {
    match namespace="quickshell:iiBackdrop"
    place-within-backdrop true
    opacity 1.0
}
RULE
    fi
    if [[ "$need_waffle" == true ]]; then
      cat <<'RULE'

layer-rule {
    match namespace="quickshell:wBackdrop"
    place-within-backdrop true
    opacity 1.0
}
RULE
    fi
  } >> "$target"

  if migration_check; then
    return 1
  fi
  return 0
}
