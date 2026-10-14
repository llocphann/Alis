#!/usr/bin/env bash

MIGRATION_ID="051-cliphist-single-watchers"
MIGRATION_TITLE="Deduplicate clipboard history watchers"
MIGRATION_DESCRIPTION="Normalizes Niri clipboard history startup to exactly one text watcher and one image watcher, removing legacy duplicate wl-paste writers that can store one copy multiple times."
MIGRATION_TARGET_FILE="~/.config/niri/config.d/50-startup.kdl"
MIGRATION_REQUIRED=true

migration_check() {
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  # BRAND-R01: a masked original unit and canonical user service mean the
  # handoff is complete. Historic iNiR migrations are ALREADY superseded;
  # never suggest re-enabling the retired owner or rewriting Alis Niri paths.
  if [[ -L "$xdg_config_home/systemd/user/inir.service" &&
        "$(readlink -- "$xdg_config_home/systemd/user/inir.service")" == /dev/null &&
        -f "$xdg_config_home/systemd/user/alis.service" ]]; then
    return 1
  fi
  local startup_cfg="${xdg_config_home}/niri/config.d/50-startup.kdl"
  local monolithic_cfg="${xdg_config_home}/niri/config.kdl"

  python3 - "$startup_cfg" "$monolithic_cfg" <<'PY'
from pathlib import Path
import re
import sys

startup = Path(sys.argv[1])
monolithic = Path(sys.argv[2])
text_line = 'spawn-at-startup "bash" "-c" "exec wl-paste --no-newline --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store"'
image_line = 'spawn-at-startup "bash" "-c" "exec wl-paste --type image --watch cliphist store"'
watcher = re.compile(
    r'^(?![ \t]*//)[ \t]*(?:spawn-at-startup|spawn-sh-at-startup)\b'
    r'.*\bwl-paste\b.*(?:cliphist[ \t]+store|native-dispatch[ \t]+clipboard-store|clipboard-store\.py).*$'
)

def active_watchers(path: Path):
    if not path.is_file():
        return []
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if watcher.match(line)
    ]

destination = startup if startup.is_file() else monolithic
if not destination.is_file():
    raise SystemExit(1)

startup_watchers = active_watchers(startup)
monolithic_watchers = active_watchers(monolithic)
all_watchers = startup_watchers + monolithic_watchers
if not all_watchers:
    # Respect a setup where clipboard-history startup was intentionally disabled.
    raise SystemExit(1)

dest_watchers = startup_watchers if destination == startup else monolithic_watchers
other_watchers = monolithic_watchers if destination == startup else startup_watchers
canonical = (
    len(dest_watchers) == 2
    and dest_watchers.count(text_line) == 1
    and dest_watchers.count(image_line) == 1
    and not other_watchers
)
raise SystemExit(1 if canonical else 0)
PY
}

migration_preview() {
  echo -e "${STY_RED}- duplicate/legacy wl-paste clipboard watchers${STY_RST}"
  echo -e "${STY_GREEN}+ exactly one text watcher + one image watcher${STY_RST}"
  echo -e "${STY_GREEN}+ Niri owns each watcher directly via exec (no nested background '&')${STY_RST}"
}

migration_apply() {
  local xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
  # A directly invoked historical apply must be harmless after the Alis
  # singleton handoff, even when the original unit archive is unavailable.
  if [[ -L "$xdg_config_home/systemd/user/inir.service" &&
        "$(readlink -- "$xdg_config_home/systemd/user/inir.service")" == /dev/null &&
        -f "$xdg_config_home/systemd/user/alis.service" ]]; then
    printf 'SKIP: retired 051 historical clipboard writer migration; Alis owns the session.\n'
    return 0
  fi
  local startup_cfg="${xdg_config_home}/niri/config.d/50-startup.kdl"
  local monolithic_cfg="${xdg_config_home}/niri/config.kdl"

  python3 - "$startup_cfg" "$monolithic_cfg" <<'PY' || return 1
from pathlib import Path
import re
import sys

startup = Path(sys.argv[1])
monolithic = Path(sys.argv[2])
text_line = 'spawn-at-startup "bash" "-c" "exec wl-paste --no-newline --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store"'
image_line = 'spawn-at-startup "bash" "-c" "exec wl-paste --type image --watch cliphist store"'
watcher = re.compile(
    r'^(?![ \t]*//)[ \t]*(?:spawn-at-startup|spawn-sh-at-startup)\b'
    r'.*\bwl-paste\b.*(?:cliphist[ \t]+store|native-dispatch[ \t]+clipboard-store|clipboard-store\.py).*$'
)

destination = startup if startup.is_file() else monolithic
if not destination.is_file():
    raise SystemExit("no Niri config found")

paths = [path for path in (startup, monolithic) if path.is_file()]
found = False
cleaned = {}
insert_index = None

for path in paths:
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
    kept = []
    first_removed = None
    for line in lines:
        if watcher.match(line.rstrip("\r\n")):
            found = True
            if first_removed is None:
                first_removed = len(kept)
            continue
        kept.append(line)
    cleaned[path] = kept
    if path == destination:
        insert_index = first_removed

if not found:
    raise SystemExit(0)

dest_lines = cleaned[destination]
canonical_lines = [text_line + "\n", image_line + "\n"]
if insert_index is None:
    if dest_lines and not dest_lines[-1].endswith("\n"):
        dest_lines[-1] += "\n"
    if dest_lines and dest_lines[-1].strip():
        dest_lines.append("\n")
    dest_lines.extend([
        "// Clipboard history: one text writer and one image writer.\n",
        *canonical_lines,
    ])
else:
    dest_lines[insert_index:insert_index] = canonical_lines

for path, lines in cleaned.items():
    path.write_text("".join(lines), encoding="utf-8")
PY

  if migration_check; then
    return 1
  fi
  return 0
}
