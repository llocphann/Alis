#!/usr/bin/env bash
# Shared JSON read/fallback helpers for Alis color scripts.
# Uses jq when installed and falls back transparently to python3 stdlib json.

alis_json_available() {
  command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1
}

# Read a single dot-path from a JSON file, preserving boolean `false`.
# Falls back to $3 only when the key is missing, null, or file cannot be parsed.
alis_json_get_or() {
  local file="$1"
  local dotpath="${2#.}"
  local fallback="${3:-}"
  [[ -f "$file" ]] || { [[ -n "$fallback" ]] && printf '%s\n' "$fallback"; return 0; }
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg key "$dotpath" --arg def "$fallback" \
      'getpath($key | split(".")) as $v | if $v == null then $def else ($v | tostring) end' \
      "$file" 2>/dev/null || { [[ -n "$fallback" ]] && printf '%s\n' "$fallback"; }
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$dotpath" "$fallback" <<'PY' 2>/dev/null || { [[ -n "$fallback" ]] && printf '%s\n' "$fallback"; }
import json, sys
path, dotpath, fallback = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(path, encoding="utf-8") as fh:
        cur = json.load(fh)
    for part in dotpath.split("."):
        if not part:
            continue
        if isinstance(cur, dict) and part in cur:
            cur = cur[part]
        else:
            cur = None
            break
except Exception:
    cur = None
if cur is None:
    print(fallback)
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif isinstance(cur, (dict, list)):
    print(json.dumps(cur, separators=(",", ":")))
else:
    print(cur)
PY
    return 0
  fi
  printf '%s\n' "$fallback"
}

# Return the first non-null, non-false value among dot-paths (matching jq's `//`).
# Usage: alis_json_pick <file> <default> <path1> [path2 ...]
alis_json_pick() {
  local file="$1"
  local fallback="$2"
  shift 2
  [[ -f "$file" ]] || { [[ -n "$fallback" ]] && printf '%s\n' "$fallback"; return 0; }
  if command -v jq >/dev/null 2>&1; then
    local expr="" p
    for p in "$@"; do
      p="${p#.}"
      expr="${expr:+$expr // }.${p}"
    done
    if [[ -n "$fallback" ]]; then
      jq -r --arg def "$fallback" "($expr) // \$def" "$file" 2>/dev/null || printf '%s\n' "$fallback"
    else
      jq -r "($expr) // empty" "$file" 2>/dev/null || true
    fi
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$fallback" "$@" <<'PY' 2>/dev/null || { [[ -n "$fallback" ]] && printf '%s\n' "$fallback"; }
import json, sys
path, fallback, keys = sys.argv[1], sys.argv[2], sys.argv[3:]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    data = None

found = None
if isinstance(data, dict):
    for raw_key in keys:
        cur = data
        ok = True
        for part in raw_key.lstrip(".").split("."):
            if not part:
                continue
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                ok = False
                break
        if ok and cur is not None and cur is not False:
            found = cur
            break

if found is None:
    if fallback:
        print(fallback)
elif isinstance(found, bool):
    print("true" if found else "false")
elif isinstance(found, (dict, list)):
    print(json.dumps(found, separators=(",", ":")))
else:
    print(found)
PY
    return 0
  fi
  [[ -n "$fallback" ]] && printf '%s\n' "$fallback"
}

# Read element at $2 from a top-level JSON array file.
alis_json_array_item() {
  local file="$1"
  local idx="$2"
  [[ -f "$file" ]] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -r ".[$idx] // empty" "$file" 2>/dev/null
    return $?
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$idx" <<'PY' 2>/dev/null
import json, sys
path, idx = sys.argv[1], int(sys.argv[2])
try:
    with open(path, encoding="utf-8") as fh:
        arr = json.load(fh)
    if isinstance(arr, list) and -len(arr) <= idx < len(arr):
        val = arr[idx]
        if val is not None and val is not False:
            print("true" if val is True else val)
except Exception:
    pass
PY
    return 0
  fi
  return 1
}

# Print non-null, non-empty string values for the given top-level keys, one per line.
alis_json_pick_list() {
  local file="$1"
  shift
  [[ -f "$file" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    local list_expr="" k
    for k in "$@"; do
      k="${k#.}"
      list_expr="${list_expr:+$list_expr, }.${k}"
    done
    jq -r "[$list_expr] | map(select(. != null and . != \"\")) | .[]" "$file" 2>/dev/null || true
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$@" <<'PY' 2>/dev/null || true
import json, sys
path, keys = sys.argv[1], sys.argv[2:]
try:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    for k in keys:
        v = data.get(k.lstrip("."))
        if v is not None and v != "":
            print("true" if v is True else ("false" if v is False else v))
PY
    return 0
  fi
}

# Dump top-level scalar string/number/bool fields of a JSON object as key<TAB>value.
alis_json_kv_dump() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r 'to_entries[] | select(.value != null and (.value | type) != "object" and (.value | type) != "array") | "\(.key)\t\(.value)"' "$file" 2>/dev/null || true
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception:
    sys.exit(0)
if isinstance(data, dict):
    for k, v in data.items():
        if v is None or isinstance(v, (dict, list)):
            continue
        if isinstance(v, bool):
            s = "true" if v else "false"
        else:
            s = str(v)
        s = s.replace("\t", " ").replace("\n", " ")
        print(f"{k}\t{s}")
PY
    return 0
  fi
}
