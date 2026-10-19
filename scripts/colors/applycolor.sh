#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/module-runtime.sh"
# shellcheck source=scripts/colors/lib/theme-profile.sh
source "$SCRIPT_DIR/lib/theme-profile.sh"

main() {
  local _perf_total=""
  if [[ "${ALIS_THEME_PROFILE:-}" == "1" ]]; then
    _perf_total="$(date +%s%N)"
  fi
  ensure_generated_dirs

  # Every pipeline log is append-only with no cap of its own; a long-lived
  # install accumulates tens of MB under XDG_STATE_HOME. Trim here, before the
  # modules that write them are spawned.
  local log_name
  for log_name in theming_modules terminal_colors code_editor_themes; do
    rotate_log "$STATE_DIR/user/generated/$log_name.log"
  done

  local manifests=()
  while IFS= read -r manifest_path; do
    [[ -n "$manifest_path" ]] || continue
    manifests+=("$manifest_path")
  done < <(list_theming_target_manifests)

  local modules=()
  local enabled_targets=0
  local manifest_path target_id module_path module_name enabled

  if (( ${#manifests[@]} > 0 )) && command -v jq >/dev/null 2>&1; then
    # Parse every target manifest in one jq process. When config exists, load
    # it once as well instead of spawning jq separately for every configKey.
    local jq_program='
      . as $manifest
      | ($manifest.configKey // "") as $key
      | (if $key == "" then true
         elif ($config | length) == 0 then true
         else ($config[0] | getpath($key | split("."))) as $value
           | if $value == null then true else $value end
         end) as $enabled
      | [($enabled | tostring), ($manifest.module // "")] | @tsv
    '
    local jq_rows=""
    local jq_ok=1
    if [[ -f "$CONFIG_FILE" ]]; then
      if ! jq_rows="$(jq -r --slurpfile config "$CONFIG_FILE" "$jq_program" "${manifests[@]}" 2>/dev/null)"; then
        jq_ok=0
      fi
    elif ! jq_rows="$(jq -r --argjson config '[]' "$jq_program" "${manifests[@]}" 2>/dev/null)"; then
      jq_ok=0
    fi

    if (( jq_ok == 1 )); then
      while IFS=$'\t' read -r enabled module_name; do
        [[ -n "$enabled" ]] || continue
        [[ "$enabled" != "false" ]] || continue
        enabled_targets=$((enabled_targets + 1))
        [[ -n "$module_name" ]] || continue
        module_path="$MODULES_DIR/$module_name"
        [[ -f "$module_path" ]] || continue
        modules+=("$module_path")
      done <<< "$jq_rows"
    else
      for manifest_path in "${manifests[@]}"; do
        target_manifest_enabled "$manifest_path" || continue
        enabled_targets=$((enabled_targets + 1))
        target_id="$(basename "$manifest_path" .json)"
        module_path="$(resolve_target_module_path "$target_id" || true)"
        [[ -n "$module_path" ]] || continue
        modules+=("$module_path")
      done
    fi
  else
    # Compatibility fallback for minimal installations without jq.
    for manifest_path in "${manifests[@]}"; do
      target_manifest_enabled "$manifest_path" || continue
      enabled_targets=$((enabled_targets + 1))
      target_id="$(basename "$manifest_path" .json)"
      module_path="$(resolve_target_module_path "$target_id" || true)"
      [[ -n "$module_path" ]] || continue
      modules+=("$module_path")
    done
  fi
  if [[ ${#modules[@]} -eq 0 && ${#manifests[@]} -eq 0 ]]; then
    while IFS= read -r module_path; do
      [[ -n "$module_path" ]] || continue
      modules+=("$module_path")
    done < <(list_theming_modules)
  fi

  if [[ ${#modules[@]} -eq 0 && ${#manifests[@]} -gt 0 && "$enabled_targets" -eq 0 ]]; then
    printf 'No enabled theming targets found in %s\n' "$SCRIPT_DIR/targets" >&2
    exit 0
  fi

  if [[ ${#modules[@]} -eq 0 ]]; then
    printf 'No theming modules found for enabled targets in %s\n' "$SCRIPT_DIR/modules" >&2
    exit 1
  fi

  local cpu_count max_jobs running failed
  cpu_count="$(nproc 2>/dev/null || printf '4')"
  max_jobs="${ALIS_THEME_MAX_JOBS:-$((cpu_count / 2))}"
  [[ "$max_jobs" =~ ^[0-9]+$ ]] || max_jobs=2
  (( max_jobs < 2 )) && max_jobs=2
  (( max_jobs > 4 )) && max_jobs=4

  run_one_module() {
    local module_path="$1" _perf_module="" result=0
    if [[ "${ALIS_THEME_PROFILE:-}" == "1" ]]; then
      _perf_module="$(date +%s%N)"
    fi
    if command -v ionice >/dev/null 2>&1; then
      ionice -c 3 nice -n 10 bash "$module_path" || result=$?
    else
      nice -n 10 bash "$module_path" || result=$?
    fi
    if [[ -n "$_perf_module" ]]; then
      theme_perf_stage applycolor "$(basename "$module_path" .sh)" "$_perf_module"
    fi
    return "$result"
  }

  running=0
  failed=0
  for module_path in "${modules[@]}"; do
    run_one_module "$module_path" &
    running=$((running + 1))
    if (( running >= max_jobs )); then
      if ! wait -n; then
        failed=1
      fi
      running=$((running - 1))
    fi
  done

  while (( running > 0 )); do
    if ! wait -n; then
      failed=1
    fi
    running=$((running - 1))
  done

  theme_perf_stage applycolor total "$_perf_total"
  exit "$failed"
}

main "$@"
