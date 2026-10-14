#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bash -n "$ROOT/setup"
bash -n "$ROOT/scripts/alis"

stage="$(mktemp -d)"
trap 'rm -rf -- "$stage"' EXIT
mkdir -p "$stage/runtime" "$stage/repo"
touch "$stage/runtime/shell.qml" "$stage/repo/shell.qml"
# A linked git worktree uses a .git FILE, unlike a regular checkout.
printf 'gitdir: /fixture/git/worktrees/repo\n' > "$stage/repo/.git"
cat > "$stage/repo/setup" <<'SCRIPT'
#!/usr/bin/env bash
printf 'healthy:%s\n' "$*"
SCRIPT
chmod +x "$stage/repo/setup"
cat > "$stage/runtime/setup" <<'SCRIPT'
#!/usr/bin/env bash
case missing_esac in
    -q|--quiet) echo broken ;;
SCRIPT
chmod +x "$stage/runtime/setup"

# Only extract the production helpers, never source the full launcher (which
# launches Quickshell and resolves live services).
awk '
    /^read_version_field\(\) \{/ {active=1}
    /^resolve_live_version_context\(\) \{/ {active=0}
    active {print}
    /^resolve_setup_dir\(\) \{/ {helpers=1}
    /^run_setup_inline\(\) \{/ {helpers=0}
    helpers {print}
' "$ROOT/scripts/alis" > "$stage/helpers.sh"
# shellcheck source=/dev/null
source "$stage/helpers.sh"
launcher_root="$stage/runtime"
config_dir="$stage/runtime"
resolve_config_dir() { :; }
alis_version_file() { printf '%s' "$stage/version.json"; }
printf '{"repoPath":"%s"}\n' "$stage/repo" > "$stage/version.json"

selected="$(resolve_setup_dir)"
[[ "$selected" == "$stage/repo" ]] || {
    echo 'FAIL: invalid installed setup was selected ahead of valid worktree checkout' >&2
    exit 1
}
output="$(run_setup_command "$selected" update --quiet)"
[[ "$output" == 'healthy:update --quiet' ]] || {
    echo "FAIL: unexpected setup dispatch: $output" >&2
    exit 1
}

# If every candidate is damaged, the launcher must refuse execution and
# explain the syntax error, not run a potentially partial update.
cat > "$stage/repo/setup" <<'SCRIPT'
#!/usr/bin/env bash
case missing_esac in
    -q|--quiet) echo broken ;;
SCRIPT
set +e
output="$(run_setup_command "$stage/runtime" update 2>&1)"
status=$?
set -e
[[ "$status" -eq 2 && "$output" == *'refusing syntax-invalid setup'* ]] || {
    echo "FAIL: corrupt runtime setup did not fail closed: [$status] $output" >&2
    exit 1
}

echo 'SETUP_ENTRYPOINT_SYNTAX_RECOVERY_PASS canonical setup/launcher parse, damaged runtime, worktree rescue, fail-closed'
