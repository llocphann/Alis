#!/usr/bin/env python3
"""Comprehensive regression and native Wayland runtime test suite for PERF-F01 (#27)."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
sys.path.insert(0, str(SCRIPT_DIR))

import perf_profiler as pp
from native_test_session import private_wayland, run_qs


def assert_true(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(f"FAIL: {msg}")


def test_p1_architecture_and_scenarios() -> None:
    arch = pp.build_architecture_map(config_dir=REPO_ROOT)
    assert_true(arch["featureCode"] == "PERF-F01", "featureCode must be PERF-F01")
    for level in (
        "direct_measurement",
        "instrumented_span",
        "controlled_ab_estimate",
        "correlation",
        "unattributable_shared",
        "unavailable",
    ):
        assert_true(level in arch["attributionDefinitions"], f"missing attribution level {level}")

    matrix_metrics = {m["metric"]: m["attribution_level"] for m in arch["observabilityMatrix"]}
    assert_true(matrix_metrics.get("gpu_device_busy_percent") == "correlation", "gpu_busy_percent must be correlation")
    assert_true(matrix_metrics.get("gpu_drm_client_fdinfo") == "direct_measurement", "drm fdinfo must be direct_measurement")
    assert_true(matrix_metrics.get("qml_frame_swapped_and_heartbeat") == "instrumented_span", "frameSwapped must be instrumented_span")

    scenarios = pp.get_workload_scenarios()
    assert_true(len(scenarios) >= 7, "expected at least 7 canonical workload scenarios")
    scen_ids = {s["id"] for s in scenarios}
    for req in ("idle-steady-state", "abyss-perimeter-hover-popup", "family-switch-roundtrip"):
        assert_true(req in scen_ids, f"missing scenario {req}")


def test_p2_instance_validation_and_errors() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        proc_root = Path(tmp) / "proc"
        proc_root.mkdir()
        cfg_dir = Path(tmp) / "target_cfg"
        cfg_dir.mkdir()

        # 1. No running instance
        res = pp.validate_target_instance(cfg_dir, proc_root=proc_root)
        assert_true(not res["ok"] and res["error_code"] == "NO_RUNNING_INSTANCE", f"expected NO_RUNNING_INSTANCE, got {res}")

        # 2. Wrong instance running against a different path
        pid_dir = proc_root / "4242"
        pid_dir.mkdir()
        (pid_dir / "comm").write_text("qs\n", encoding="utf-8")
        other_cfg = Path(tmp) / "other_cfg"
        other_cfg.mkdir()
        (pid_dir / "cmdline").write_bytes(b"qs\x00-p\x00" + str(other_cfg).encode("utf-8") + b"\x00")

        res_wrong = pp.validate_target_instance(cfg_dir, proc_root=proc_root)
        assert_true(not res_wrong["ok"] and res_wrong["error_code"] == "WRONG_INSTANCE", f"expected WRONG_INSTANCE, got {res_wrong}")

        # 3. Matching instance with stale version.json
        (pid_dir / "cmdline").write_bytes(b"qs\x00-p\x00" + str(cfg_dir).encode("utf-8") + b"\x00")
        (cfg_dir / "version.json").write_text(json.dumps({"commit": "0000000000000000000000000000000000000000"}), encoding="utf-8")
        res_stale = pp.validate_target_instance(cfg_dir, proc_root=proc_root)
        assert_true(not res_stale["ok"] and res_stale["error_code"] == "STALE_INSTALL", f"expected STALE_INSTALL, got {res_stale}")

        # 4. Matching instance with current HEAD SHA
        head_sha = pp.get_git_head_sha()
        (cfg_dir / "version.json").write_text(json.dumps({"commit": head_sha}), encoding="utf-8")
        res_ok = pp.validate_target_instance(cfg_dir, proc_root=proc_root)
        assert_true(res_ok["ok"] and res_ok["pid"] == 4242, f"expected OK for pid 4242, got {res_ok}")


def test_p3_cpu_and_thread_edge_cases() -> None:
    # Thread comm with spaces and parentheses
    stat_line = (
        "1050 (Thread (pooled)) S 1000 1000 1000 0 -1 4194304 120 0 0 0 "
        "150 50 0 0 20 0 8 0 987654 12345678 4096 18446744073709551615"
    )
    parsed = pp.parse_proc_stat(stat_line)
    assert_true(parsed is not None, "failed to parse stat with nested parens")
    assert_true(parsed["pid"] == 1050 and parsed["comm"] == "Thread (pooled)", f"unexpected comm: {parsed}")
    assert_true(parsed["total_ticks"] == 200 and parsed["starttime"] == 987654, f"unexpected ticks: {parsed}")
    assert_true(pp.classify_thread(parsed["comm"], is_leader=False) == "qml_worker", "pooled thread should be qml_worker")
    assert_true(pp.classify_thread("QSGRenderThread", is_leader=False) == "qsg_render", "QSGRenderThread classification failed")
    assert_true(pp.classify_thread("qs:vk-queue", is_leader=False) == "rhi_driver", "qs:vk classification failed")
    assert_true(pp.classify_thread("qs", is_leader=True) == "main_gui", "leader thread should be main_gui")

    # Normal delta: 50 ticks over 1.0s at 100 Hz on 4 cores -> 50% single-core, 12.5% normalized
    s1 = {
        "monotonic_ns": 1_000_000_000,
        "proc_stat": {"pid": 100, "starttime": 555, "total_ticks": 1000},
        "threads": [
            {"pid": 100, "comm": "qs", "starttime": 555, "total_ticks": 600, "thread_class": "main_gui"},
            {"pid": 101, "comm": "QSGRenderThread", "starttime": 556, "total_ticks": 400, "thread_class": "qsg_render"},
        ],
    }
    s2 = {
        "monotonic_ns": 2_000_000_000,
        "proc_stat": {"pid": 100, "starttime": 555, "total_ticks": 1050},
        "threads": [
            {"pid": 100, "comm": "qs", "starttime": 555, "total_ticks": 630, "thread_class": "main_gui"},
            {"pid": 101, "comm": "QSGRenderThread", "starttime": 556, "total_ticks": 420, "thread_class": "qsg_render"},
        ],
    }
    delta = pp.compute_cpu_delta(s1, s2, clk_tck=100, cpu_count=4)
    assert_true(delta["valid"], "expected valid delta")
    assert_true(abs(delta["single_core_pct"] - 50.0) < 0.01, f"expected 50.0%, got {delta['single_core_pct']}")
    assert_true(abs(delta["normalized_pct"] - 12.5) < 0.01, f"expected 12.5%, got {delta['normalized_pct']}")
    assert_true(abs(delta["class_single_core_pct"]["main_gui"] - 30.0) < 0.01, "expected 30% main_gui")
    assert_true(abs(delta["class_single_core_pct"]["qsg_render"] - 20.0) < 0.01, "expected 20% qsg_render")

    # PID / starttime changed mid-run
    s_restarted = {
        "monotonic_ns": 3_000_000_000,
        "proc_stat": {"pid": 100, "starttime": 999, "total_ticks": 10},
        "threads": [],
    }
    d_restart = pp.compute_cpu_delta(s2, s_restarted, clk_tck=100, cpu_count=4)
    assert_true(not d_restart["valid"] and d_restart.get("pid_changed") is True, f"expected pid_changed: {d_restart}")

    # Counter wraparound
    s_wrap = {
        "monotonic_ns": 3_000_000_000,
        "proc_stat": {"pid": 100, "starttime": 555, "total_ticks": 900},
        "threads": [],
    }
    d_wrap = pp.compute_cpu_delta(s2, s_wrap, clk_tck=100, cpu_count=4)
    assert_true(not d_wrap["valid"] and d_wrap.get("counter_wraparound") is True, f"expected counter_wraparound: {d_wrap}")

    # Non-monotonic timebase
    s_backwards = {
        "monotonic_ns": 1_500_000_000,
        "proc_stat": {"pid": 100, "starttime": 555, "total_ticks": 1100},
        "threads": [],
    }
    d_time = pp.compute_cpu_delta(s2, s_backwards, clk_tck=100, cpu_count=4)
    assert_true(not d_time["valid"] and d_time.get("anomaly") == "NON_MONOTONIC_TIMEBASE", f"expected timebase error: {d_time}")


def test_p4_memory_and_smaps_categories() -> None:
    rollup_txt = """555555550000-7ffffffde000 ---p 00000000 00:00 0 [rollup]
Rss:              250000 kB
Pss:              180000 kB
Shared_Clean:      60000 kB
Shared_Dirty:      10000 kB
Private_Clean:     30000 kB
Private_Dirty:    150000 kB
Swap:               4096 kB
SwapPss:            2048 kB
"""
    rollup = pp.parse_smaps_rollup(rollup_txt)
    assert_true(rollup["available"] and rollup["rss_kb"] == 250000, "smaps_rollup rss failed")
    assert_true(rollup["pss_kb"] == 180000 and rollup["uss_kb"] == 180000, "smaps_rollup pss/uss failed")

    smaps_txt = """7f0000000000-7f0000200000 rw-p 00000000 00:00 0 [anon:JSGCHeap]
Size:               2048 kB
Rss:                1536 kB
7f0000200000-7f0000400000 rw-p 00000000 00:00 12345 /memfd:JSGCHeap (deleted)
Size:               2048 kB
Rss:                1024 kB
7f0000400000-7f0000800000 rw-s 00000000 00:01 67890 /memfd:wayland-shm (deleted)
Size:               4096 kB
Rss:                3072 kB
7f0000800000-7f0000900000 r--p 00000000 08:02 111 /usr/share/fonts/TTF/JetBrainsMono.ttf
Size:               1024 kB
Rss:                 512 kB
7f0000900000-7f0001000000 r-xp 00000000 08:02 222 /usr/lib/libQt6Quick.so.6.8.0
Size:               7168 kB
Rss:                4096 kB
7f0001000000-7f0001500000 rw-p 00000000 00:00 0 
Size:               5120 kB
Rss:                2000 kB
"""
    cats = pp.parse_smaps_categories(smaps_txt, total_rss_kb=15000)
    assert_true(cats["js_gc_heap_active_kb"] == 1536 and cats["js_gc_heap_active_count"] == 1, f"active JSGCHeap mismatch: {cats}")
    assert_true(cats["js_gc_heap_deleted_kb"] == 1024 and cats["js_gc_heap_deleted_count"] == 1, f"deleted JSGCHeap mismatch: {cats}")
    assert_true(cats["shm_memfd_textures_kb"] == 3072, f"shm textures mismatch: {cats}")
    assert_true(cats["font_icon_caches_kb"] == 512, f"font cache mismatch: {cats}")
    assert_true(cats["shared_libs_kb"] == 4096, f"shared libs mismatch: {cats}")
    # Unattributable shared must capture the unnamed anon mapping + any uncategorized remainder up to total_rss_kb
    assert_true(cats["unattributable_shared_kb"] == 15000 - (1536 + 1024 + 3072 + 512 + 4096), f"unattributable_shared mismatch: {cats}")


def test_p5_gpu_and_drm_fdinfo() -> None:
    # Duplicate fds for the same drm-client-id must be deduplicated
    fdinfo_sample = {
        "12": "pos: 0\ndrm-driver: amdgpu\ndrm-client-id: 77\ndrm-engine-gfx: 50000000 ns\ndrm-memory-vram: 64 MiB\ndrm-memory-gtt: 32768 KiB\n",
        "13": "pos: 0\ndrm-driver: amdgpu\ndrm-client-id: 77\ndrm-engine-gfx: 50000000 ns\ndrm-memory-vram: 64 MiB\ndrm-memory-gtt: 32768 KiB\n",
    }
    drm1 = pp.parse_drm_fdinfo(fdinfo_sample)
    assert_true(drm1["available"] and drm1["attribution"] == "direct_measurement", f"drm1 failed: {drm1}")
    assert_true(drm1["client_count"] == 1, "dup'd fds with same drm-client-id must be deduplicated")
    assert_true(drm1["memory_kb"]["vram"] == 64 * 1024 and drm1["memory_kb"]["gtt"] == 32768, f"drm memory mismatch: {drm1}")

    fdinfo_sample_2 = {
        "12": "pos: 0\ndrm-driver: amdgpu\ndrm-client-id: 77\ndrm-engine-gfx: 150000000 ns\ndrm-memory-vram: 64 MiB\n",
    }
    drm2 = pp.parse_drm_fdinfo(fdinfo_sample_2)
    # 100,000,000 ns over 1,000,000,000 ns (1s) = 10.0%
    eng_delta = pp.compute_drm_engine_delta(drm1, drm2, elapsed_ns=1_000_000_000)
    assert_true(eng_delta["available"] and abs(eng_delta["engine_pct"]["gfx"] - 10.0) < 0.01, f"drm engine pct mismatch: {eng_delta}")

    # Test absent GPU sensors & global device counter correlation
    with tempfile.TemporaryDirectory() as tmp:
        drm_root = Path(tmp) / "drm"
        drm_root.mkdir()
        card0 = drm_root / "card0" / "device"
        (card0 / "power").mkdir(parents=True)
        (card0 / "vendor").write_text("0x1002\n", encoding="utf-8")
        (card0 / "gpu_busy_percent").write_text("42\n", encoding="utf-8")
        (card0 / "power" / "runtime_status").write_text("active\n", encoding="utf-8")

        env = pp.sample_gpu_environment(sys_drm_root=drm_root, proc_pid_dir=Path(tmp) / "no_pid")
        assert_true(env["cards_detected"] == 1, "expected 1 DRM card")
        c0 = env["cards"][0]
        assert_true(c0["global_gpu_busy_pct"] == 42.0, "expected global_gpu_busy_pct 42.0")
        assert_true(c0["global_counter_attribution"] == "correlation", "global gpu_busy_percent must be labeled correlation")
        assert_true(env["process_drm"]["attribution"] == "unavailable", "missing fdinfo must be unavailable")


def test_p6_p8_nested_spans_and_ranking_and_redaction() -> None:
    # Outer span [1000..1100] (100ms) enclosing inner span [1020..1050] (30ms)
    spans = [
        {"timestampMs": 1100, "durationMs": 100.0, "moduleId": "dashboard", "spanName": "open_sequence"},
        {"timestampMs": 1050, "durationMs": 30.0, "moduleId": "weather", "spanName": "bind_forecast"},
    ]
    analyzed = pp.analyze_spans(spans)
    dash_mod = analyzed["by_module"]["dashboard"]
    weath_mod = analyzed["by_module"]["weather"]
    assert_true(dash_mod["inclusiveTotalMs"] == 100.0 and dash_mod["selfTotalMs"] == 70.0, f"nested span self-time failed: {dash_mod}")
    assert_true(weath_mod["inclusiveTotalMs"] == 30.0 and weath_mod["selfTotalMs"] == 30.0, f"inner span self-time failed: {weath_mod}")

    # Privacy redaction
    raw_payload = {
        "configPath": "/home/alice/.config/alis",
        "notification_body": "Secret OTP 998877",
        "clipboard": "my-bank-password",
        "window_title": "Private Document - Obsidian",
        "ssid": "HomeWiFi-5G",
        "authHeader": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9",
        "ghToken": "ghp_1234567890abcdefghijklmnopqrstuv",
        "openAiKey": "sk-proj1234567890abcdefghijklmnop",
    }
    redacted = pp.redact_sensitive_data(raw_payload, home_dir="/home/alice")
    dumped = json.dumps(redacted)
    assert_true("/home/alice" not in dumped and "~/.config/alis" in dumped, f"home path not redacted: {dumped}")
    for forbidden in ("998877", "my-bank-password", "Private Document", "HomeWiFi-5G", "eyJhbGci", "ghp_123", "sk-proj"):
        assert_true(forbidden not in dumped, f"sensitive value {forbidden} leaked in {dumped}")


def test_p13_native_wayland_quickshell_runtime() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-perf-f01-") as tmpdir:
        folder = Path(tmpdir)
        for rel in ("modules", "services", "defaults", "translations", "scripts", "assets", "GlobalStates.qml", "qmldir"):
            src = REPO_ROOT / rel
            dst = folder / rel
            if src.exists() and not dst.exists():
                dst.symlink_to(src)

        (folder / "shell.qml").write_text(
            """//@ pragma UseQApplication
import QtQuick
import Quickshell
import qs.modules.common
import qs.services

ShellRoot {
    id: root
    property string activePanelFamily: "abyss"
    property string mountedPanelFamily: "abyss"
    property bool familyMountReady: true
    property real _bootCompletedAt: Date.now() - 500
    property real _bootConfigReadyAt: Date.now() - 400
    property real _bootShellEntryAt: Date.now() - 300
    property real _bootDeferredAt: Date.now() - 100
    property real _bootLateFeaturesAt: Date.now()

    Component.onCompleted: {
        PerfProbeService.registerShellRoot(root)
    }
}
""",
            encoding="utf-8",
        )

        with private_wayland(folder, capture_focus=False) as env:
            if env is None:
                print("PERF_F01_RUNTIME_SKIPPED (no private_wayland)")
                return

            env["QT_QUICK_BACKEND"] = "software"
            env["QT_NO_XDG_DESKTOP_PORTAL"] = "1"
            qs_log = folder / "native-test-qs.log"
            with qs_log.open("wb") as stream:
                qs_proc = subprocess.Popen(
                    ["qs", "-p", str(folder), "--no-color"],
                    env=env,
                    stdout=stream,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
            try:
                ready_status = None
                last_ipc_out = ""
                for _ in range(60):
                    if qs_proc.poll() is not None:
                        raise AssertionError("Quickshell exited prematurely: " + qs_log.read_text(errors="replace")[-2000:])
                    res = subprocess.run(
                        ["qs", "ipc", "--pid", str(qs_proc.pid), "call", "perfProbe", "status"],
                        env=env,
                        capture_output=True,
                        text=True,
                        timeout=4,
                        check=False,
                    )
                    last_ipc_out = (res.stdout or "") + " | " + (res.stderr or "")
                    if res.returncode == 0 and "active" in res.stdout:
                        lines = [ln.strip() for ln in res.stdout.splitlines() if ln.strip().startswith("{")]
                        if lines:
                            ready_status = json.loads(lines[-1])
                            break
                    time.sleep(0.2)

                if ready_status is None:
                    raise AssertionError(
                        f"perfProbe IPC never became ready. last_ipc={last_ipc_out!r} qs_log={qs_log.read_text(errors='replace')[-2000:]!r}"
                    )
                assert_true(ready_status.get("ok") is True, f"perfProbe IPC invalid status: {ready_status}")
                assert_true(ready_status["active"] is False, "perfProbe must be inactive by default (zero idle overhead)")
                assert_true(ready_status["frameSampleCount"] == 0 and ready_status["spanCount"] == 0, "inactive perfProbe must not collect samples")

                # Start probe session via IPC
                start_res = subprocess.run(
                    [
                        "qs",
                        "ipc",
                        "--pid",
                        str(qs_proc.pid),
                        "call",
                        "perfProbe",
                        "start",
                        json.dumps({"maxDurationMs": 15000, "scenarioId": "native-wayland-test"}),
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=4,
                    check=True,
                )
                start_json = json.loads([ln.strip() for ln in start_res.stdout.splitlines() if ln.strip().startswith("{")][-1])
                assert_true(start_json["ok"] and start_json["active"], f"perfProbe start failed: {start_json}")

                # Record custom instrumented span and wait for heartbeat ticks
                subprocess.run(
                    ["qs", "ipc", "--pid", str(qs_proc.pid), "call", "perfProbe", "recordSpan", "testModule", "syntheticWork", "14.5"],
                    env=env,
                    capture_output=True,
                    timeout=4,
                    check=True,
                )
                time.sleep(0.35)

                stop_res = subprocess.run(
                    ["qs", "ipc", "--pid", str(qs_proc.pid), "call", "perfProbe", "stop"],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=4,
                    check=True,
                )
                stop_json = json.loads([ln.strip() for ln in stop_res.stdout.splitlines() if ln.strip().startswith("{")][-1])
                assert_true(stop_json["ok"] and stop_json["wasActive"], f"perfProbe stop failed: {stop_json}")
                assert_true(stop_json["spans"]["count"] >= 1, f"expected recorded spans, got {stop_json['spans']}")
                assert_true(stop_json["eventLoopHeartbeat"]["stats"]["count"] >= 2, f"expected heartbeat samples, got {stop_json['eventLoopHeartbeat']}")

                # Test end-to-end CLI `alis debug perf start` against this isolated instance
                trace_out = folder / "cli-trace.json"
                cli_res = subprocess.run(
                    [
                        "bash",
                        str(REPO_ROOT / "scripts" / "alis"),
                        "debug",
                        "perf",
                        "start",
                        "--config-dir",
                        str(folder),
                        "--duration",
                        "0.6",
                        "--interval-ms",
                        "150",
                        "--scenario",
                        "idle-steady-state",
                        "--output",
                        str(trace_out),
                        "--allow-mismatch",
                    ],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=15,
                    check=True,
                )
                assert_true(trace_out.exists(), f"CLI trace file not written: {cli_res.stderr}")
                trace_data = json.loads(trace_out.read_text(encoding="utf-8"))
                assert_true(trace_data["ok"] and trace_data["featureCode"] == "PERF-F01", "invalid CLI trace payload")
                assert_true(len(trace_data["componentRanking"]) >= 1, "expected non-empty componentRanking")

                # Test report (markdown, csv, html) and compare CLI commands
                for fmt, needle in (
                    ("markdown", "Component Cost Ranking & Attribution Truthfulness"),
                    ("csv", "component_id,category,attribution_level"),
                    ("html", "<!DOCTYPE html>"),
                ):
                    rep_res = subprocess.run(
                        ["bash", str(REPO_ROOT / "scripts" / "alis"), "debug", "perf", "report", str(trace_out), "--format", fmt],
                        env=env,
                        capture_output=True,
                        text=True,
                        timeout=5,
                        check=True,
                    )
                    assert_true(needle in rep_res.stdout, f"{fmt} report missing {needle}")

                cmp_res = subprocess.run(
                    ["bash", str(REPO_ROOT / "scripts" / "alis"), "debug", "perf", "compare", str(trace_out), str(trace_out)],
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=5,
                    check=True,
                )
                cmp_data = json.loads(cmp_res.stdout)
                assert_true(cmp_data["attribution"] == "controlled_ab_estimate", "compare must use controlled_ab_estimate")
                assert_true(cmp_data["deltas"]["cpu_mean_single_core_pct"] == 0.0, "self-comparison delta must be 0.0")
            finally:
                if qs_proc.poll() is None:
                    try:
                        os.killpg(qs_proc.pid, subprocess.signal.SIGTERM)
                        qs_proc.wait(timeout=3)
                    except Exception:
                        try:
                            os.killpg(qs_proc.pid, subprocess.signal.SIGKILL)
                        except Exception:
                            pass


def main() -> int:
    test_p1_architecture_and_scenarios()
    test_p2_instance_validation_and_errors()
    test_p3_cpu_and_thread_edge_cases()
    test_p4_memory_and_smaps_categories()
    test_p5_gpu_and_drm_fdinfo()
    test_p6_p8_nested_spans_and_ranking_and_redaction()
    test_p13_native_wayland_quickshell_runtime()
    print("PERF_F01_PASS architecture, samplers, attribution truthfulness, redaction, and live Wayland perfProbe verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
