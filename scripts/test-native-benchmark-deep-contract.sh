#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$repo_root/scripts/benchmark-python-vs-rust.sh"
harness="$repo_root/scripts/native-cutover-benchmark.sh"

fail() {
    printf 'FAIL: native deep benchmark contract: %s\n' "$1" >&2
    exit 1
}

bash -n "$wrapper" || fail "benchmark wrapper has invalid shell syntax"
bash -n "$harness" || fail "native cutover harness has invalid shell syntax"

grep -Fq -- '--deep) DEEP=1' "$wrapper"     || fail "wrapper no longer exposes --deep"
grep -Fq -- '--final) FINAL=1; DEEP=1' "$wrapper"     || fail "wrapper no longer exposes --final with deep parity"
grep -Fq -- 'LIVE_AB_RUNS="${LIVE_AB_RUNS:-3}"' "$wrapper"     || fail "final qualification no longer defaults to three live A/B rounds"
grep -Fq -- 'LIVE_SETTLE_SECONDS="${LIVE_SETTLE_SECONDS:-8}"' "$wrapper"     || fail "final qualification no longer gives the shell a settle window"
grep -Fq -- 'LIVE_WINDOW_SECONDS="${LIVE_WINDOW_SECONDS:-10}"' "$wrapper"     || fail "final qualification no longer samples a meaningful live window"
grep -Fq -- '--restore) RESTORE_ONLY=1' "$wrapper"     || fail "wrapper no longer exposes --restore"
grep -Fq -- 'exec bash "$HARNESS" --restore' "$wrapper"     || fail "wrapper no longer delegates restore through the canonical harness"
grep -Fq -- 'verify_python_restore()' "$harness"     || fail "harness no longer verifies Python rollback"
grep -Fq -- "grep -Fxq 'mode=python'" "$harness"     || fail "rollback no longer verifies installed selector mode"
grep -Fq -- "grep -Fxq 'ALIS_NATIVE_BACKEND=python'" "$harness"     || fail "rollback no longer verifies user-manager backend environment"
grep -Fq -- "grep -Eq '^ALIS_NATIVE_(BIN_DIR|STRICT)='" "$harness"     || fail "rollback no longer checks stale Rust selector environment"
grep -Fq -- 'systemctl --user is-active --quiet alis.service' "$harness"     || fail "rollback no longer verifies alis.service activity"
grep -Fq -- 'bash $ROOT_DIR/scripts/benchmark-python-vs-rust.sh --restore' "$harness"     || fail "report no longer points users at the single canonical restore entrypoint"
grep -Fq -- 'ALIS_BENCH_MPD_SNAPSHOT=1' "$wrapper"     || fail "wrapper no longer enables isolated MPD snapshot mode"
grep -Fq -- 'Deep MPD snapshot:' "$wrapper"     || fail "full report no longer records whether deep mode ran"

grep -Fq -- '--niri-validate' "$harness"     || fail "live Niri validate parity must ignore successful human-readable output"
grep -Fq -- 'live queue churn tolerated' "$harness"     || fail "live MPD parity must tolerate queue advancement by stable queue IDs"
grep -Fq -- '[[ "$mpd_parity" == PASS* ]]' "$harness"     || fail "annotated live MPD parity PASS must remain activation-safe"
grep -Fq -- 'LIVE_AB_RUNS:-1' "$harness"     || fail "harness no longer supports repeated live A/B rounds"
grep -Fq -- 'Round order alternates to reduce warm-cache/order bias' "$harness"     || fail "live A/B no longer alternates backend order"
grep -Fq -- 'summarize_live_ab()' "$harness"     || fail "harness no longer summarizes repeated live samples"
grep -Fq -- 'live rust-vs-python median delta' "$harness"     || fail "live A/B report no longer includes median Rust/Python deltas"
grep -Fq -- 'service PID changed during sample' "$harness"     || fail "live A/B no longer detects service restarts during a sample"

grep -Fq -- 'MPD FULL SNAPSHOT DEEP BENCHMARK' "$harness"     || fail "harness no longer contains the full snapshot benchmark"
grep -Fq -- 'keys = ["connected", "musicRoot", "tracks", "playlists", "folders"]' "$harness"     || fail "snapshot parity must stay limited to stable library fields"
grep -Fq -- 'snapshot_parity_cache="$TMP_ROOT/mpd-snapshot-parity-cache"' "$harness"     || fail "snapshot parity must remain isolated from the user cache"
grep -Fq -- 'snapshot_python_cache="$TMP_ROOT/mpd-snapshot-python-cache"' "$harness"     || fail "Python snapshot benchmark must keep its own isolated cache"
grep -Fq -- 'snapshot_rust_cache="$TMP_ROOT/mpd-snapshot-rust-cache"' "$harness"     || fail "Rust snapshot benchmark must keep its own isolated cache"
grep -Fq -- 'XDG_CACHE_HOME="$snapshot_parity_cache"' "$harness"     || fail "snapshot parity command no longer uses the isolated cache"
grep -Fq -- 'XDG_CACHE_HOME="$snapshot_python_cache"' "$harness"     || fail "Python snapshot benchmark no longer uses its isolated cache"
grep -Fq -- 'XDG_CACHE_HOME="$snapshot_rust_cache"' "$harness"     || fail "Rust snapshot benchmark no longer uses its isolated cache"
grep -Fq -- 'MPD_SNAPSHOT_RUNS:-1' "$harness"     || fail "deep snapshot default must remain one run"
grep -Fq -- 'SKIP (use benchmark wrapper --deep)' "$harness"     || fail "full snapshot benchmark must remain opt-in by default"

printf '%s\n' 'PASS: native benchmark entrypoint keeps deep isolation and restore support'
