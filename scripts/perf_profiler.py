#!/usr/bin/env python3
""" Opt-in, bounded CPU/RAM/GPU/QML performance profiler for Alis Quickshell (PERF-F01 #27).

Principles:
- Zero idle overhead when inactive (only runs on explicit user CLI invocation).
- Never requires root/sudo or network access.
- Strict attribution truthfulness: every metric and ranking entry carries an
  explicit attribution_level (`direct_measurement`, `instrumented_span`,
  `controlled_ab_estimate`, `correlation`, `unattributable_shared`, `unavailable`).
- Never fabricates per-QML-item CPU, RAM, or GPU numbers from process-wide or
  global device counters.
- Strict privacy redaction ($HOME -> ~, tokens, notification text, clipboard,
  window titles, SSIDs, and vault paths scrubbed before persistence).
"""

from __future__ import annotations

import argparse
import csv
import html
import io
import json
import math
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent

ATTRIBUTION_LEVELS = {
    "direct_measurement": "Direct OS/kernel per-process or per-thread counter (/proc, smaps, DRM fdinfo).",
    "instrumented_span": "Opt-in QML/JS runtime callback or lifecycle span (perfProbe / frameSwapped / heartbeat).",
    "controlled_ab_estimate": "Differential delta between matched baseline and candidate workload traces.",
    "correlation": "Global device or system state overlapping in time (e.g. gpu_busy_percent, power profile); not per-widget.",
    "unattributable_shared": "Process-wide shared resource (scenegraph atlas, glibc heap, shared .so, font tables) that cannot be assigned to one module.",
    "unavailable": "Sensor, driver counter, or probe unavailable or permission denied.",
}

ERROR_CODES = {
    "OK": 0,
    "NO_RUNNING_INSTANCE": 2,
    "WRONG_INSTANCE": 3,
    "STALE_INSTALL": 4,
    "MISSING_IPC": 5,
    "EMPTY_TRACE": 6,
    "INVALID_ARGS": 7,
    "SESSION_ALREADY_ACTIVE": 8,
    "NO_ACTIVE_SESSION": 9,
}

HARD_MAX_DURATION_S = 300.0
HARD_MIN_INTERVAL_MS = 50
HARD_MAX_INTERVAL_MS = 5000
HARD_MAX_SAMPLES = 2400
HARD_MAX_BYTES = 50 * 1024 * 1024
DEFAULT_MAX_BYTES = 10 * 1024 * 1024


def get_cache_dir() -> Path:
    xdg = os.environ.get("XDG_CACHE_HOME", "").strip()
    base = Path(xdg) if xdg else (Path.home() / ".cache")
    out = base / "alis" / "perf-profiler"
    out.mkdir(parents=True, exist_ok=True)
    return out


def get_git_head_sha(repo_dir: Path = REPO_ROOT) -> str:
    try:
        res = subprocess.run(
            ["git", "-C", str(repo_dir), "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        if res.returncode == 0 and res.stdout.strip():
            return res.stdout.strip()
    except Exception:
        pass
    return "unknown"


# ---------------------------------------------------------------------------
# P1: Architecture & Observability Map
# ---------------------------------------------------------------------------

def build_architecture_map(
    config_dir: Path | None = None,
    live_snapshot: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the complete Alis Quickshell architecture & observability inventory (P1)."""
    cfg = str(config_dir or REPO_ROOT)
    return {
        "schemaVersion": 1,
        "featureCode": "PERF-F01",
        "sourceSha": get_git_head_sha(),
        "configDir": redact_string(cfg),
        "attributionDefinitions": ATTRIBUTION_LEVELS,
        "processHierarchy": [
            {
                "id": "quickshell_host",
                "binary": "qs / quickshell",
                "role": "Primary QML/SceneGraph shell process hosting all panels, services, and IPC handlers.",
                "attribution": "direct_measurement",
            },
            {
                "id": "child_helpers",
                "binaries": ["cava", "awww-daemon", "wl-copy", "keyboard_lock_state_daemon.py", "alis-inputd"],
                "role": "External child or cgroup helper processes; measured by their own PIDs so helper cost is never conflated with QML.",
                "attribution": "direct_measurement",
            },
            {
                "id": "niri_compositor",
                "binary": "niri",
                "role": "Wayland compositor process; measured independently by PID to separate compositor compositing from shell rendering.",
                "attribution": "direct_measurement",
            },
        ],
        "threadTaxonomy": [
            {
                "class": "main_gui",
                "match": "Process leader (TID == PID)",
                "role": "Qt main event loop, QML/V4 JS execution, bindings, Loader incubation, IPC dispatch.",
                "attribution": "direct_measurement",
            },
            {
                "class": "qsg_render",
                "match": "QSGRenderThread*",
                "role": "Qt Quick SceneGraph synchronization, batching, RHI command recording, and swap submission.",
                "attribution": "direct_measurement",
            },
            {
                "class": "rhi_driver",
                "match": "qs:vk*, qs:gl*, gallium*, amdgpu*, iris*, nvidia*, disk_cache*",
                "role": "Vulkan/OpenGL driver worker and shader compilation threads.",
                "attribution": "direct_measurement",
            },
            {
                "class": "media_codec",
                "match": "ffmpeg*, mpv*, pipewire*, pulse*, gmain, gdbus",
                "role": "Audio/video decoding, MPRIS/DBus transport, and PipeWire stream threads.",
                "attribution": "direct_measurement",
            },
            {
                "class": "qml_worker",
                "match": "QQmlThread*, Thread (pooled)*, QNetwork*",
                "role": "Asynchronous QML type compilation, image decoding, and network/file workers.",
                "attribution": "direct_measurement",
            },
        ],
        "surfaceHierarchy": [
            {
                "id": "shell_root",
                "entrypoint": "shell.qml",
                "tiers": ["Tier 0 (startup-critical singletons)", "Tier 1-2 (critical panel host)", "Tier 3 (+500ms deferred panels)", "Tier 4 (+1500ms background services)"],
            },
            {
                "id": "family_abyss",
                "hosts": ["modules/abyss/critical/ShellAbyssCriticalPanels.qml", "ShellAbyssPanels.qml", "modules/abyss/AbyssPerimeter.qml"],
                "surfaces": ["abyssPerimeter", "abyssPopup", "abyssNotificationCenter", "abyssDashboard"],
            },
            {
                "id": "family_ii",
                "hosts": ["modules/ii/critical/ShellIiCriticalPanels.qml", "ShellIiPanels.qml"],
                "surfaces": ["iiBar", "iiBackground", "iiDashboard", "iiOverview", "iiControlPanel", "iiSidebarLeft", "iiSidebarRight", "iiNotificationPopup", "iiClipboard"],
            },
            {
                "id": "family_waffle",
                "hosts": ["modules/waffle/critical/ShellWaffleCriticalPanels.qml", "ShellWafflePanels.qml"],
                "surfaces": ["wBar", "wBackground", "wStartMenu", "wActionCenter", "wNotificationCenter", "wWidgets", "wTaskView"],
            },
            {
                "id": "settings_windows",
                "hosts": ["settings.qml", "waffleSettings.qml", "modules/settings/SettingsOverlay.qml", "modules/settings/SettingsFocus.qml"],
                "surfaces": ["settingsWindow", "waffleSettingsWindow", "settingsOverlay"],
            },
        ],
        "observabilityMatrix": [
            {
                "metric": "process_and_thread_cpu",
                "source": "/proc/<pid>/stat & /proc/<pid>/task/<tid>/stat",
                "attribution_level": "direct_measurement",
                "limitations": "Kernel tick resolution (USER_HZ, typically 100Hz = 10ms); short spikes below 10ms require instrumented spans.",
            },
            {
                "metric": "memory_rss_pss_uss",
                "source": "/proc/<pid>/status & /proc/<pid>/smaps_rollup",
                "attribution_level": "direct_measurement",
                "limitations": "Process-wide virtual/physical pages; cannot assign shared heap arenas to individual QML items without A/B isolation.",
            },
            {
                "metric": "memory_smaps_subsystems",
                "source": "/proc/<pid>/smaps",
                "attribution_level": "direct_measurement",
                "limitations": "Separates [anon:JSGCHeap] active vs (deleted), shm/memfd textures, fonts, and .so libraries; remaining anonymous heap is marked unattributable_shared.",
            },
            {
                "metric": "gpu_drm_client_fdinfo",
                "source": "/proc/<pid>/fdinfo/* (drm-engine-*, drm-memory-*)",
                "attribution_level": "direct_measurement",
                "limitations": "Process-level DRM client counters exposed by amdgpu/i915/xe/msm; does not split GPU time per QML Item.",
            },
            {
                "metric": "gpu_device_busy_percent",
                "source": "/sys/class/drm/card*/device/gpu_busy_percent",
                "attribution_level": "correlation",
                "limitations": "Global GPU device busy percentage across all desktop clients and compositor; never reported as shell-exclusive GPU load.",
            },
            {
                "metric": "qml_frame_swapped_and_heartbeat",
                "source": "perfProbe & abyssHoverProbe IPC",
                "attribution_level": "instrumented_span",
                "limitations": "QQuickWindow.frameSwapped is a wall-clock swap callback (includes idle gaps when nothing renders), not a hardware scanout timestamp.",
            },
        ],
        "liveSnapshot": live_snapshot,
    }


# ---------------------------------------------------------------------------
# P9: Reproducible Workload Scenarios
# ---------------------------------------------------------------------------

def get_workload_scenarios() -> list[dict[str, Any]]:
    """Return canonical reproducible workload scenario descriptors (P9)."""
    return [
        {
            "id": "idle-steady-state",
            "title": "Idle Steady-State Baseline",
            "description": "Shell at rest with no transient popups or overlays open. Measures background timer wakeups, steady CPU%, RSS/PSS/USS, and JSGCHeap stability.",
            "recommendedDurationS": 15,
            "recommendedIntervalMs": 250,
            "ipcActions": [],
            "primaryMetrics": ["cpu.qs_single_core_pct", "memory.uss_kb", "memory.js_gc_heap_deleted_kb", "qml.eventLoopHeartbeat.over16msStallCount"],
        },
        {
            "id": "abyss-perimeter-hover-popup",
            "title": "Abyss Screen-Edge Hover & Popup Cycle",
            "description": "Exercises Abyss perimeter popups and frame-swap cadence under opt-in probe capture.",
            "recommendedDurationS": 12,
            "recommendedIntervalMs": 100,
            "ipcActions": ["abyssHoverProbe startFrames", "dashboard toggle", "dashboard close", "abyssHoverProbe stopFrames"],
            "primaryMetrics": ["qml.frameTiming.p95Ms", "qml.frameTiming.over25msCount", "cpu.threads.qsg_render_pct"],
        },
        {
            "id": "dashboard-calendar-weather-cycle",
            "title": "Dashboard Open/Close & Residency Cycle",
            "description": "Toggles Dashboard surface to measure initial Loader incubation, slide frame pacing, and post-close memory residency.",
            "recommendedDurationS": 10,
            "recommendedIntervalMs": 100,
            "ipcActions": ["dashboard open", "dashboard close"],
            "primaryMetrics": ["qml.spans", "memory.uss_delta_kb", "cpu.threads.main_gui_pct"],
        },
        {
            "id": "overview-search-burst",
            "title": "Overview & Launcher Search Burst",
            "description": "Opens and closes Overview/Search to measure fuzzy index preparation and QML delegate allocation.",
            "recommendedDurationS": 10,
            "recommendedIntervalMs": 100,
            "ipcActions": ["overview open", "overview close"],
            "primaryMetrics": ["qml.spans", "cpu.threads.main_gui_pct", "memory.js_gc_heap_active_kb"],
        },
        {
            "id": "notification-center-churn",
            "title": "Notification Center Open/Close Churn",
            "description": "Repeatedly toggles Notification Center to detect list layout stalls and JSGCHeap accumulation.",
            "recommendedDurationS": 12,
            "recommendedIntervalMs": 100,
            "ipcActions": ["notificationCenter open", "notificationCenter close"],
            "primaryMetrics": ["qml.eventLoopHeartbeat.p95Ms", "memory.js_gc_heap_deleted_kb"],
        },
        {
            "id": "family-switch-roundtrip",
            "title": "Panel Family Switch Roundtrip (Abyss <-> Waffle)",
            "description": "Measures full family Loader teardown, recreate latency, and deleted JSGCHeap arena growth across family transitions.",
            "recommendedDurationS": 20,
            "recommendedIntervalMs": 200,
            "ipcActions": ["panelFamily cycle", "panelFamily cycle"],
            "primaryMetrics": ["memory.js_gc_heap_deleted_kb", "memory.pss_delta_kb", "cpu.qs_single_core_pct"],
        },
        {
            "id": "settings-navigation-sweep",
            "title": "Settings Page Navigation Sweep",
            "description": "Steps through Settings pages via settingsNav IPC to profile page Loader instantiation and QML disk cache reuse.",
            "recommendedDurationS": 15,
            "recommendedIntervalMs": 150,
            "ipcActions": ["settingsNav page 0", "settingsNav page 1", "settingsNav page 2", "settingsNav page 39"],
            "primaryMetrics": ["memory.rss_delta_kb", "memory.js_gc_heap_deleted_kb", "cpu.threads.main_gui_pct"],
        },
    ]


# ---------------------------------------------------------------------------
# P11: Privacy & Security Redaction
# ---------------------------------------------------------------------------

_SENSITIVE_KEY_RE = re.compile(
    r"(password|passwd|secret|token|api[_-]?key|authorization|cookie|clipboard|"
    r"notification[_-]?(body|title|summary|text)|window[_-]?title|note[_-]?text|"
    r"ssid|bssid|vault[_-]?path|private[_-]?key)",
    re.IGNORECASE,
)

_INLINE_SECRET_PATTERNS = [
    (re.compile(r"Bearer\s+[A-Za-z0-9._\-+/=]{8,}", re.IGNORECASE), "Bearer [REDACTED]"),
    (re.compile(r"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{16,}\b"), "[REDACTED_GH_TOKEN]"),
    (re.compile(r"\bgithub_pat_[A-Za-z0-9_]{16,}\b"), "[REDACTED_GH_PAT]"),
    (re.compile(r"\bsk-[A-Za-z0-9\-_]{16,}\b"), "[REDACTED_API_KEY]"),
    (re.compile(r"://([^/@:\s]+):([^/@\s]+)@"), "://[REDACTED_USER]:[REDACTED_PASS]@"),
]


def redact_string(value: str, home_dir: str | None = None) -> str:
    """Scrub user home paths, tokens, credentials, and private paths from a string (P11)."""
    if not isinstance(value, str) or not value:
        return value
    text = value
    home = (home_dir or os.environ.get("HOME") or str(Path.home())).rstrip("/")
    if home and len(home) > 1:
        text = text.replace(home, "~")
    # Also scrub generic /home/<user> paths
    text = re.sub(r"/home/[A-Za-z0-9._\-]+", "~", text)
    for pattern, replacement in _INLINE_SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def redact_sensitive_data(obj: Any, home_dir: str | None = None) -> Any:
    """Recursively scrub sensitive keys and inline secrets from a trace structure (P11)."""
    if isinstance(obj, dict):
        cleaned: dict[str, Any] = {}
        for k, v in obj.items():
            key_str = str(k)
            if _SENSITIVE_KEY_RE.search(key_str):
                cleaned[key_str] = "[REDACTED]"
            else:
                cleaned[key_str] = redact_sensitive_data(v, home_dir=home_dir)
        return cleaned
    if isinstance(obj, list):
        return [redact_sensitive_data(item, home_dir=home_dir) for item in obj]
    if isinstance(obj, str):
        return redact_string(obj, home_dir=home_dir)
    return obj


def enforce_trace_budget(trace: dict[str, Any], max_bytes: int = DEFAULT_MAX_BYTES) -> dict[str, Any]:
    """Ensure serialized trace JSON stays within max_bytes without losing summary/metadata (P11)."""
    limit = max(4096, min(int(max_bytes), HARD_MAX_BYTES))
    raw = json.dumps(trace, ensure_ascii=False)
    if len(raw.encode("utf-8")) <= limit:
        trace.setdefault("budget", {})["truncated"] = False
        trace["budget"]["maxBytes"] = limit
        trace["budget"]["actualBytes"] = len(raw.encode("utf-8"))
        return trace

    # Downsample timeseries samples first while preserving first/last and summaries
    samples = list(trace.get("samples", []))
    while len(samples) > 4:
        samples = [samples[0]] + samples[1:-1:2] + [samples[-1]]
        trace["samples"] = samples
        trace.setdefault("budget", {})["truncated"] = True
        trace["budget"]["downsampledSampleCount"] = len(samples)
        raw = json.dumps(trace, ensure_ascii=False)
        if len(raw.encode("utf-8")) <= limit:
            trace["budget"]["maxBytes"] = limit
            trace["budget"]["actualBytes"] = len(raw.encode("utf-8"))
            return trace

    # If still over limit, trim span records while keeping aggregated span stats
    qml_data = trace.get("qmlProbe", {})
    if isinstance(qml_data, dict) and isinstance(qml_data.get("spans"), dict):
        records = list(qml_data["spans"].get("records", []))
        if len(records) > 10:
            qml_data["spans"]["records"] = records[:10]
            qml_data["spans"]["budgetTrimmed"] = True
            trace.setdefault("budget", {})["truncated"] = True

    raw = json.dumps(trace, ensure_ascii=False)
    if len(raw.encode("utf-8")) > limit:
        trace["samples"] = samples[:2]
        trace.setdefault("budget", {})["truncated"] = True
        raw = json.dumps(trace, ensure_ascii=False)

    trace.setdefault("budget", {})["maxBytes"] = limit
    trace["budget"]["actualBytes"] = len(raw.encode("utf-8"))
    return trace


# ---------------------------------------------------------------------------
# P3: CPU, Thread & Scheduler Parsers
# ---------------------------------------------------------------------------

def parse_proc_stat(stat_text: str) -> dict[str, Any] | None:
    """Parse /proc/<pid>/stat or /proc/<pid>/task/<tid>/stat safely (handles spaces/parens in comm)."""
    text = (stat_text or "").strip()
    if not text:
        return None
    open_paren = text.find("(")
    close_paren = text.rfind(")")
    if open_paren < 0 or close_paren <= open_paren:
        return None
    try:
        pid = int(text[:open_paren].strip())
        comm = text[open_paren + 1 : close_paren]
        rest = text[close_paren + 1 :].strip().split()
        # In /proc/pid/stat, rest[0] is field 3 (state), rest[11] is field 14 (utime),
        # rest[12] is field 15 (stime), rest[13] is field 16 (cutime), rest[14] is field 17 (cstime),
        # rest[17] is field 20 (num_threads), rest[19] is field 22 (starttime),
        # rest[20] is field 23 (vsize), rest[21] is field 24 (rss)
        if len(rest) < 22:
            return None
        utime = int(rest[11])
        stime = int(rest[12])
        cutime = int(rest[13])
        cstime = int(rest[14])
        return {
            "pid": pid,
            "comm": comm,
            "state": rest[0],
            "ppid": int(rest[1]),
            "utime": utime,
            "stime": stime,
            "cutime": cutime,
            "cstime": cstime,
            "total_ticks": utime + stime,
            "num_threads": int(rest[17]),
            "starttime": int(rest[19]),
            "vsize_bytes": int(rest[20]),
            "rss_pages": int(rest[21]),
        }
    except (ValueError, IndexError):
        return None


def classify_thread(comm: str, is_leader: bool = False) -> str:
    """Classify a Quickshell thread by its kernel comm name (P3)."""
    if is_leader:
        return "main_gui"
    name = (comm or "").strip().lower()
    if name.startswith("qsgrender") or "renderthread" in name:
        return "qsg_render"
    if (
        name.startswith("qs:vk")
        or name.startswith("qs:gl")
        or name.startswith("gallium")
        or name.startswith("amdgpu")
        or name.startswith("iris")
        or name.startswith("nvidia")
        or "disk_cache" in name
        or "vulkan" in name
    ):
        return "rhi_driver"
    if (
        name.startswith("ffmpeg")
        or name.startswith("mpv")
        or name.startswith("pipewire")
        or name.startswith("pulse")
        or name in ("gmain", "gdbus", "threaded-ml")
    ):
        return "media_codec"
    if (
        name.startswith("qqml")
        or "pooled" in name
        or name.startswith("qnetwork")
        or name.startswith("qdbusthread")
        or name.startswith("qfileinfo")
    ):
        return "qml_worker"
    return "other"


def compute_cpu_delta(
    prev_sample: dict[str, Any],
    curr_sample: dict[str, Any],
    clk_tck: int = 100,
    cpu_count: int = 1,
) -> dict[str, Any]:
    """Compute CPU utilization between two samples with PID-restart, timebase, and wraparound guards (P3, P12)."""
    tck = max(1, int(clk_tck))
    cores = max(1, int(cpu_count))
    prev_stat = prev_sample.get("proc_stat") or {}
    curr_stat = curr_sample.get("proc_stat") or {}

    if not prev_stat or not curr_stat:
        return {"valid": False, "anomaly": "MISSING_STAT", "single_core_pct": 0.0, "normalized_pct": 0.0}

    if prev_stat.get("pid") != curr_stat.get("pid") or prev_stat.get("starttime") != curr_stat.get("starttime"):
        return {
            "valid": False,
            "pid_changed": True,
            "anomaly": "PID_OR_STARTTIME_CHANGED",
            "single_core_pct": 0.0,
            "normalized_pct": 0.0,
        }

    prev_mono = int(prev_sample.get("monotonic_ns", 0))
    curr_mono = int(curr_sample.get("monotonic_ns", 0))
    elapsed_ns = curr_mono - prev_mono
    if elapsed_ns <= 0:
        return {
            "valid": False,
            "anomaly": "NON_MONOTONIC_TIMEBASE",
            "single_core_pct": 0.0,
            "normalized_pct": 0.0,
        }

    elapsed_s = elapsed_ns / 1e9
    delta_ticks = int(curr_stat.get("total_ticks", 0)) - int(prev_stat.get("total_ticks", 0))
    if delta_ticks < 0:
        return {
            "valid": False,
            "counter_wraparound": True,
            "anomaly": "COUNTER_WRAPAROUND",
            "single_core_pct": 0.0,
            "normalized_pct": 0.0,
        }

    single_core_pct = (delta_ticks / (tck * elapsed_s)) * 100.0
    normalized_pct = single_core_pct / cores

    # Per-thread & per-class breakdown
    prev_threads: dict[int, dict[str, Any]] = {
        int(t["pid"]): t for t in (prev_sample.get("threads") or []) if "pid" in t
    }
    curr_threads: list[dict[str, Any]] = curr_sample.get("threads") or []
    class_pct: dict[str, float] = {
        "main_gui": 0.0,
        "qsg_render": 0.0,
        "rhi_driver": 0.0,
        "media_codec": 0.0,
        "qml_worker": 0.0,
        "other": 0.0,
    }
    thread_deltas: list[dict[str, Any]] = []
    leader_pid = int(curr_stat.get("pid", 0))

    for t in curr_threads:
        tid = int(t.get("pid", 0))
        pt = prev_threads.get(tid)
        t_class = t.get("thread_class") or classify_thread(t.get("comm", ""), is_leader=(tid == leader_pid))
        if pt and pt.get("starttime") == t.get("starttime"):
            dt = int(t.get("total_ticks", 0)) - int(pt.get("total_ticks", 0))
            if dt >= 0:
                pct = (dt / (tck * elapsed_s)) * 100.0
                class_pct[t_class] = class_pct.get(t_class, 0.0) + pct
                thread_deltas.append(
                    {
                        "tid": tid,
                        "comm": t.get("comm", ""),
                        "thread_class": t_class,
                        "single_core_pct": round(pct, 3),
                        "normalized_pct": round(pct / cores, 3),
                    }
                )

    thread_deltas.sort(key=lambda x: x["single_core_pct"], reverse=True)
    return {
        "valid": True,
        "pid_changed": False,
        "counter_wraparound": False,
        "anomaly": None,
        "elapsed_s": round(elapsed_s, 4),
        "single_core_pct": round(single_core_pct, 3),
        "normalized_pct": round(normalized_pct, 3),
        "class_single_core_pct": {k: round(v, 3) for k, v in class_pct.items()},
        "top_threads": thread_deltas[:12],
        "attribution": "direct_measurement",
    }


# ---------------------------------------------------------------------------
# P4: Memory & Smaps Parsers
# ---------------------------------------------------------------------------

def parse_proc_status(status_text: str) -> dict[str, Any]:
    """Parse /proc/<pid>/status for VmRSS, VmSize, VmSwap, Threads, and context switches (P4)."""
    out: dict[str, Any] = {
        "vm_rss_kb": 0,
        "vm_size_kb": 0,
        "vm_swap_kb": 0,
        "vm_data_kb": 0,
        "vm_stk_kb": 0,
        "threads": 0,
        "voluntary_ctxt_switches": 0,
        "nonvoluntary_ctxt_switches": 0,
    }
    key_map = {
        "VmRSS:": "vm_rss_kb",
        "VmSize:": "vm_size_kb",
        "VmSwap:": "vm_swap_kb",
        "VmData:": "vm_data_kb",
        "VmStk:": "vm_stk_kb",
        "Threads:": "threads",
        "voluntary_ctxt_switches:": "voluntary_ctxt_switches",
        "nonvoluntary_ctxt_switches:": "nonvoluntary_ctxt_switches",
    }
    for line in (status_text or "").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in key_map:
            try:
                out[key_map[parts[0]]] = int(parts[1])
            except ValueError:
                pass
    return out


def parse_smaps_rollup(rollup_text: str) -> dict[str, Any]:
    """Parse /proc/<pid>/smaps_rollup into RSS, PSS, USS, and Swap (P4)."""
    fields = {
        "Rss:": "rss_kb",
        "Pss:": "pss_kb",
        "Shared_Clean:": "shared_clean_kb",
        "Shared_Dirty:": "shared_dirty_kb",
        "Private_Clean:": "private_clean_kb",
        "Private_Dirty:": "private_dirty_kb",
        "Swap:": "swap_kb",
        "SwapPss:": "swap_pss_kb",
    }
    res = {v: 0 for v in fields.values()}
    found_any = False
    for line in (rollup_text or "").splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in fields:
            try:
                res[fields[parts[0]]] = int(parts[1])
                found_any = True
            except ValueError:
                pass
    res["uss_kb"] = res["private_clean_kb"] + res["private_dirty_kb"]
    res["available"] = found_any
    res["attribution"] = "direct_measurement" if found_any else "unavailable"
    return res


_SMAPS_HEADER_RE = re.compile(
    r"^[0-9a-fA-F]+-[0-9a-fA-F]+\s+\S+\s+[0-9a-fA-F]+\s+\S+\s+\d+\s*(.*)$"
)


def parse_smaps_categories(smaps_text: str, total_rss_kb: int = 0) -> dict[str, Any]:
    """Categorize /proc/<pid>/smaps into JSGCHeap (active vs deleted), textures/shm, fonts, libs, and unattributable_shared (P4, P8)."""
    buckets = {
        "js_gc_heap_active_kb": 0,
        "js_gc_heap_active_count": 0,
        "js_gc_heap_deleted_kb": 0,
        "js_gc_heap_deleted_count": 0,
        "qml_jit_or_anon_kb": 0,
        "shm_memfd_textures_kb": 0,
        "font_icon_caches_kb": 0,
        "shared_libs_kb": 0,
        "heap_brk_kb": 0,
        "stack_kb": 0,
        "unattributable_shared_kb": 0,
    }
    if not smaps_text:
        return {**buckets, "available": False, "attribution": "unavailable"}

    current_name = ""
    current_rss = 0

    def _flush(name: str, rss: int) -> None:
        lname = name.lower()
        if "jsgcheap" in lname:
            if "deleted" in lname:
                buckets["js_gc_heap_deleted_kb"] += rss
                buckets["js_gc_heap_deleted_count"] += 1
            else:
                buckets["js_gc_heap_active_kb"] += rss
                buckets["js_gc_heap_active_count"] += 1
        elif "qv4" in lname or "qml" in lname:
            buckets["qml_jit_or_anon_kb"] += rss
        elif "memfd:" in lname or "/dev/shm" in lname or "dmabuf" in lname or "wayland" in lname:
            buckets["shm_memfd_textures_kb"] += rss
        elif ".ttf" in lname or ".otf" in lname or "/fonts/" in lname or "fontconfig" in lname or "icon-theme.cache" in lname:
            buckets["font_icon_caches_kb"] += rss
        elif ".so" in lname:
            buckets["shared_libs_kb"] += rss
        elif name == "[heap]":
            buckets["heap_brk_kb"] += rss
        elif name.startswith("[stack"):
            buckets["stack_kb"] += rss
        else:
            buckets["unattributable_shared_kb"] += rss

    in_mapping = False
    for line in smaps_text.splitlines():
        m = _SMAPS_HEADER_RE.match(line)
        if m:
            if in_mapping:
                _flush(current_name, current_rss)
            current_name = m.group(1).strip()
            current_rss = 0
            in_mapping = True
        elif in_mapping and line.startswith("Rss:"):
            parts = line.split()
            if len(parts) >= 2:
                try:
                    current_rss += int(parts[1])
                except ValueError:
                    pass

    if in_mapping:
        _flush(current_name, current_rss)

    categorized_sum = sum(
        buckets[k]
        for k in (
            "js_gc_heap_active_kb",
            "js_gc_heap_deleted_kb",
            "qml_jit_or_anon_kb",
            "shm_memfd_textures_kb",
            "font_icon_caches_kb",
            "shared_libs_kb",
            "heap_brk_kb",
            "stack_kb",
        )
    )
    if total_rss_kb > categorized_sum + buckets["unattributable_shared_kb"]:
        buckets["unattributable_shared_kb"] = total_rss_kb - categorized_sum

    buckets["available"] = True
    buckets["attribution"] = "direct_measurement"
    return buckets


# ---------------------------------------------------------------------------
# P5: GPU & VRAM Counter Parsers
# ---------------------------------------------------------------------------

def _parse_size_to_kb(raw_val: str) -> int:
    parts = raw_val.strip().split()
    if not parts:
        return 0
    try:
        num = float(parts[0])
    except ValueError:
        return 0
    unit = parts[1].lower() if len(parts) > 1 else "b"
    if unit in ("kib", "kb"):
        return int(round(num))
    if unit in ("mib", "mb"):
        return int(round(num * 1024))
    if unit in ("gib", "gb"):
        return int(round(num * 1024 * 1024))
    return int(round(num / 1024.0))


def parse_drm_fdinfo(fdinfo_texts: dict[str, str]) -> dict[str, Any]:
    """Parse /proc/<pid>/fdinfo/* for per-process DRM engine ns and VRAM/GTT memory (P5)."""
    clients: dict[str, dict[str, Any]] = {}
    for fd_name, text in (fdinfo_texts or {}).items():
        if "drm-driver:" not in text and "drm-client-id:" not in text:
            continue
        driver = "unknown"
        client_id = f"fd:{fd_name}"
        engines_ns: dict[str, int] = {}
        memory_kb: dict[str, int] = {}
        for line in text.splitlines():
            if ":" not in line:
                continue
            k, v = line.split(":", 1)
            k = k.strip()
            v = v.strip()
            if k == "drm-driver":
                driver = v
            elif k == "drm-client-id":
                client_id = v
            elif k.startswith("drm-engine-") and not k.endswith("-capacity"):
                eng_name = k[len("drm-engine-") :]
                parts = v.split()
                if parts:
                    try:
                        engines_ns[eng_name] = int(parts[0])
                    except ValueError:
                        pass
            elif k.startswith("drm-memory-") or k.startswith("drm-total-"):
                mem_name = k.replace("drm-memory-", "").replace("drm-total-", "")
                memory_kb[mem_name] = max(memory_kb.get(mem_name, 0), _parse_size_to_kb(v))

        dedup_key = f"{driver}:{client_id}"
        clients[dedup_key] = {
            "driver": driver,
            "client_id": client_id,
            "engines_ns": engines_ns,
            "memory_kb": memory_kb,
        }

    if not clients:
        return {
            "available": False,
            "attribution": "unavailable",
            "reason": "NO_DRM_FDINFO_EXPOSED",
            "engines_ns": {},
            "memory_kb": {},
            "client_count": 0,
        }

    total_engines: dict[str, int] = {}
    total_mem: dict[str, int] = {}
    drivers: set[str] = set()
    for c in clients.values():
        drivers.add(c["driver"])
        for eng, ns in c["engines_ns"].items():
            total_engines[eng] = total_engines.get(eng, 0) + ns
        for mem, kb in c["memory_kb"].items():
            total_mem[mem] = total_mem.get(mem, 0) + kb

    return {
        "available": True,
        "attribution": "direct_measurement",
        "scope": "process_drm_client",
        "drivers": sorted(drivers),
        "client_count": len(clients),
        "engines_ns": total_engines,
        "memory_kb": total_mem,
    }


def compute_drm_engine_delta(prev_drm: dict[str, Any], curr_drm: dict[str, Any], elapsed_ns: int) -> dict[str, Any]:
    """Compute per-process GPU engine % from DRM fdinfo ns deltas (P5)."""
    if not prev_drm.get("available") or not curr_drm.get("available") or elapsed_ns <= 0:
        return {"available": False, "attribution": "unavailable", "engine_pct": {}}
    prev_eng = prev_drm.get("engines_ns") or {}
    curr_eng = curr_drm.get("engines_ns") or {}
    engine_pct: dict[str, float] = {}
    for eng, curr_ns in curr_eng.items():
        if eng in prev_eng:
            delta_ns = int(curr_ns) - int(prev_eng[eng])
            if delta_ns >= 0:
                engine_pct[eng] = round(min(100.0, (delta_ns / float(elapsed_ns)) * 100.0), 3)
    return {
        "available": bool(engine_pct),
        "attribution": "direct_measurement" if engine_pct else "unavailable",
        "scope": "process_drm_client",
        "engine_pct": engine_pct,
    }


def sample_gpu_environment(
    sys_drm_root: Path = Path("/sys/class/drm"),
    proc_pid_dir: Path | None = None,
) -> dict[str, Any]:
    """Inventory DRM cards, global device busy counters, and per-process DRM fdinfo (P5, P12)."""
    cards: list[dict[str, Any]] = []
    permission_errors: list[str] = []

    if sys_drm_root.exists():
        for card_dir in sorted(sys_drm_root.glob("card[0-9]*")):
            if "-" in card_dir.name:
                continue
            dev_dir = card_dir / "device"
            card_info: dict[str, Any] = {
                "card": card_dir.name,
                "vendor": None,
                "device": None,
                "runtime_pm_status": None,
                "global_gpu_busy_pct": None,
                "global_vram_used_kb": None,
                "global_vram_total_kb": None,
                "global_counter_attribution": "unavailable",
            }
            for field, rel in (
                ("vendor", "vendor"),
                ("device", "device"),
                ("runtime_pm_status", "power/runtime_status"),
            ):
                p = dev_dir / rel
                try:
                    if p.exists():
                        card_info[field] = p.read_text(errors="replace").strip()
                except PermissionError:
                    permission_errors.append(str(p))
                except OSError:
                    pass

            busy_path = dev_dir / "gpu_busy_percent"
            try:
                if busy_path.exists():
                    card_info["global_gpu_busy_pct"] = float(busy_path.read_text(errors="replace").strip())
                    card_info["global_counter_attribution"] = "correlation"
                    card_info["global_counter_scope"] = "global_device_counter"
            except PermissionError:
                permission_errors.append(str(busy_path))
                card_info["global_counter_reason"] = "PERMISSION_DENIED"
            except (OSError, ValueError):
                pass

            for mem_field, mem_file in (
                ("global_vram_used_kb", "mem_info_vram_used"),
                ("global_vram_total_kb", "mem_info_vram_total"),
            ):
                mp = dev_dir / mem_file
                try:
                    if mp.exists():
                        card_info[mem_field] = int(mp.read_text(errors="replace").strip()) // 1024
                        card_info["global_counter_attribution"] = "correlation"
                except PermissionError:
                    permission_errors.append(str(mp))
                except (OSError, ValueError):
                    pass

            cards.append(card_info)

    fdinfo_map: dict[str, str] = {}
    if proc_pid_dir is not None:
        fdinfo_dir = proc_pid_dir / "fdinfo"
        try:
            if fdinfo_dir.exists():
                for f in fdinfo_dir.iterdir():
                    try:
                        txt = f.read_text(errors="replace")
                        if "drm-" in txt:
                            fdinfo_map[f.name] = txt
                    except PermissionError:
                        permission_errors.append(str(f))
                    except OSError:
                        pass
        except PermissionError:
            permission_errors.append(str(fdinfo_dir))
        except OSError:
            pass

    process_drm = parse_drm_fdinfo(fdinfo_map)
    if permission_errors and not process_drm.get("available"):
        process_drm["reason"] = "PERMISSION_DENIED"

    return {
        "cards_detected": len(cards),
        "cards": cards,
        "process_drm": process_drm,
        "permission_errors": redact_sensitive_data(permission_errors),
        "attribution_note": (
            "process_drm counters come from /proc/<pid>/fdinfo (direct_measurement for the qs process). "
            "global_gpu_busy_pct comes from /sys/class/drm/card*/device/gpu_busy_percent (correlation across the entire GPU device, never per-QML-widget)."
        ),
    }


# ---------------------------------------------------------------------------
# P6, P7, P8: Span Aggregation & Component Cost Ranking
# ---------------------------------------------------------------------------

def analyze_spans(spans: list[dict[str, Any]]) -> dict[str, Any]:
    """Aggregate instrumented spans and compute nested self-time vs inclusive duration (P6, P12)."""
    if not spans:
        return {
            "total_spans": 0,
            "by_module": {},
            "attribution": "instrumented_span",
        }

    # Sort spans by start time (timestampMs - durationMs) to detect nested child spans
    normalized: list[dict[str, Any]] = []
    for idx, sp in enumerate(spans):
        end_ms = float(sp.get("timestampMs", 0.0))
        dur_ms = max(0.0, float(sp.get("durationMs", 0.0)))
        start_ms = float(sp.get("startMs", end_ms - dur_ms))
        normalized.append(
            {
                "index": idx,
                "moduleId": str(sp.get("moduleId", "unknown")),
                "spanName": str(sp.get("spanName", "unknown")),
                "startMs": start_ms,
                "endMs": end_ms,
                "durationMs": dur_ms,
                "selfDurationMs": dur_ms,
            }
        )

    normalized.sort(key=lambda s: (s["startMs"], -s["durationMs"]))

    # Compute exclusive (self) duration when a span properly encloses child spans
    n = len(normalized)
    for i in range(n):
        outer = normalized[i]
        child_sum = 0.0
        covered_until = outer["startMs"]
        for j in range(i + 1, n):
            inner = normalized[j]
            if inner["startMs"] >= outer["endMs"]:
                break
            if inner["endMs"] <= outer["endMs"] and inner["durationMs"] > 0:
                overlap_start = max(inner["startMs"], covered_until)
                if inner["endMs"] > overlap_start:
                    child_sum += inner["endMs"] - overlap_start
                    covered_until = inner["endMs"]
        outer["selfDurationMs"] = max(0.0, round(outer["durationMs"] - child_sum, 3))

    by_module: dict[str, dict[str, Any]] = {}
    for sp in normalized:
        mod = sp["moduleId"]
        entry = by_module.setdefault(
            mod,
            {
                "moduleId": mod,
                "count": 0,
                "inclusiveTotalMs": 0.0,
                "selfTotalMs": 0.0,
                "maxMs": 0.0,
                "durations": [],
                "spansByName": {},
            },
        )
        entry["count"] += 1
        entry["inclusiveTotalMs"] = round(entry["inclusiveTotalMs"] + sp["durationMs"], 3)
        entry["selfTotalMs"] = round(entry["selfTotalMs"] + sp["selfDurationMs"], 3)
        entry["maxMs"] = max(entry["maxMs"], sp["durationMs"])
        entry["durations"].append(sp["durationMs"])
        sname = sp["spanName"]
        entry["spansByName"][sname] = entry["spansByName"].get(sname, 0) + 1

    for mod, entry in by_module.items():
        durs = sorted(entry.pop("durations"))
        cnt = len(durs)
        p95_idx = min(cnt - 1, max(0, math.ceil(cnt * 0.95) - 1))
        entry["p95Ms"] = round(durs[p95_idx], 3) if cnt else 0.0

    return {
        "total_spans": len(normalized),
        "by_module": by_module,
        "attribution": "instrumented_span",
    }


def build_component_ranking(trace: dict[str, Any]) -> list[dict[str, Any]]:
    """Build component cost ranking with explicit attribution level, confidence, and uncertainty (P8)."""
    ranking: list[dict[str, Any]] = []
    summary = trace.get("summary") or {}
    cpu_sum = summary.get("cpu") or {}
    mem_sum = summary.get("memory") or {}
    smaps = mem_sum.get("smaps_categories_end") or {}
    qml_probe = trace.get("qmlProbe") or {}
    span_analysis = analyze_spans((qml_probe.get("spans") or {}).get("records") or [])

    # 1. Thread class CPU entries (direct_measurement)
    class_cpu = cpu_sum.get("mean_class_single_core_pct") or {}
    for t_class, pct in sorted(class_cpu.items(), key=lambda kv: kv[1], reverse=True):
        if pct <= 0.0:
            continue
        ranking.append(
            {
                "component_id": f"thread:{t_class}",
                "category": "thread_class",
                "attribution_level": "direct_measurement",
                "confidence": "high",
                "metrics": {"cpu_single_core_pct": round(float(pct), 3)},
                "uncertainty_note": "Directly measured from /proc/<pid>/task/<tid>/stat kernel ticks.",
            }
        )

    # 2. Memory subsystem entries from smaps (direct_measurement + unattributable_shared)
    if smaps.get("available"):
        for bucket_key, label, attr_level, conf, note in (
            (
                "js_gc_heap_active_kb",
                "memory:v4_js_gc_heap_active",
                "direct_measurement",
                "high",
                "Active Qt V4 JSGCHeap mappings in /proc/<pid>/smaps.",
            ),
            (
                "js_gc_heap_deleted_kb",
                "memory:v4_js_gc_heap_deleted",
                "direct_measurement",
                "high",
                "Retained (deleted) JSGCHeap mappings after Loader teardown.",
            ),
            (
                "shm_memfd_textures_kb",
                "memory:shm_memfd_buffers",
                "direct_measurement",
                "high",
                "Shared memory / memfd / Wayland buffer mappings.",
            ),
            (
                "font_icon_caches_kb",
                "memory:font_and_icon_caches",
                "direct_measurement",
                "high",
                "Mapped font and icon cache pages.",
            ),
            (
                "unattributable_shared_kb",
                "memory:unattributable_shared",
                "unattributable_shared",
                "medium",
                "Process-wide shared heap, scenegraph caches, and anonymous mappings that cannot be truthfully assigned to a single QML module.",
            ),
        ):
            kb = int(smaps.get(bucket_key, 0))
            if kb > 0 or bucket_key == "unattributable_shared_kb":
                ranking.append(
                    {
                        "component_id": label,
                        "category": "unattributable_shared" if attr_level == "unattributable_shared" else "memory_bucket",
                        "attribution_level": attr_level,
                        "confidence": conf,
                        "metrics": {"rss_kb": kb},
                        "uncertainty_note": note,
                    }
                )

    # 3. Instrumented QML surface/module spans (instrumented_span)
    for mod_id, mod_stats in sorted(
        (span_analysis.get("by_module") or {}).items(),
        key=lambda kv: kv[1].get("selfTotalMs", 0.0),
        reverse=True,
    ):
        ranking.append(
            {
                "component_id": f"qml_surface:{mod_id}",
                "category": "qml_surface",
                "attribution_level": "instrumented_span",
                "confidence": "medium",
                "metrics": {
                    "span_count": mod_stats["count"],
                    "inclusive_ms": mod_stats["inclusiveTotalMs"],
                    "self_ms": mod_stats["selfTotalMs"],
                    "p95_ms": mod_stats["p95Ms"],
                },
                "uncertainty_note": "Wall-clock QML lifecycle/interaction span; does not isolate GPU shader execution.",
            }
        )

    # 4. External child helpers & compositor (direct_measurement)
    for helper in summary.get("child_helpers") or []:
        ranking.append(
            {
                "component_id": f"helper:{helper.get('comm', 'unknown')}",
                "category": "child_helper",
                "attribution_level": "direct_measurement",
                "confidence": "high",
                "metrics": {
                    "rss_kb": helper.get("rss_kb", 0),
                    "cpu_single_core_pct": helper.get("cpu_single_core_pct", 0.0),
                },
                "uncertainty_note": "Separate child process PID; excluded from qs process totals.",
            }
        )

    comp = summary.get("compositor")
    if isinstance(comp, dict) and comp.get("pid"):
        ranking.append(
            {
                "component_id": "compositor:niri",
                "category": "compositor",
                "attribution_level": "direct_measurement",
                "confidence": "high",
                "metrics": {
                    "rss_kb": comp.get("rss_kb", 0),
                    "cpu_single_core_pct": comp.get("cpu_single_core_pct", 0.0),
                },
                "uncertainty_note": "Independent Niri compositor process; separate from Quickshell.",
            }
        )

    return ranking


# ---------------------------------------------------------------------------
# P2: Target Instance Validation & IPC Bridge
# ---------------------------------------------------------------------------

def find_running_qs_instances(proc_root: Path = Path("/proc")) -> list[dict[str, Any]]:
    """Scan /proc for running qs / quickshell processes and extract their -p config paths."""
    instances: list[dict[str, Any]] = []
    if not proc_root.exists():
        return instances
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        pid = int(entry.name)
        try:
            comm = (entry / "comm").read_text(errors="replace").strip()
            if comm not in ("qs", "quickshell"):
                continue
            raw_cmd = (entry / "cmdline").read_bytes()
            argv = [arg.decode("utf-8", errors="replace") for arg in raw_cmd.split(b"\x00") if arg]
            cfg_path = None
            for i, arg in enumerate(argv):
                if arg in ("-p", "--path") and i + 1 < len(argv):
                    cfg_path = argv[i + 1]
                    break
            instances.append(
                {
                    "pid": pid,
                    "comm": comm,
                    "argv": argv,
                    "config_path": str(Path(cfg_path).resolve()) if cfg_path else None,
                }
            )
        except (PermissionError, OSError):
            continue
    return instances


def validate_target_instance(
    config_dir: Path,
    proc_root: Path = Path("/proc"),
    expected_pid: int | None = None,
    allow_mismatch: bool = False,
) -> dict[str, Any]:
    """Verify running Quickshell instance matches target config_dir and repo identity (P2, P12)."""
    resolved_cfg = config_dir.resolve()
    instances = find_running_qs_instances(proc_root=proc_root)
    if expected_pid is not None:
        instances = [inst for inst in instances if inst["pid"] == expected_pid]

    if not instances:
        return {
            "ok": False,
            "error_code": "NO_RUNNING_INSTANCE",
            "exit_code": ERROR_CODES["NO_RUNNING_INSTANCE"],
            "message": f"No running Quickshell (qs) process found for {redact_string(str(resolved_cfg))}.",
        }

    # Check if any instance matches resolved_cfg (or its shell.qml)
    matching = []
    for inst in instances:
        cpath = inst.get("config_path")
        if not cpath:
            continue
        cp = Path(cpath)
        if cp.is_file():
            cp = cp.parent
        if cp.resolve() == resolved_cfg:
            matching.append(inst)

    if not matching:
        if not allow_mismatch:
            found_paths = [redact_string(str(i.get("config_path"))) for i in instances]
            return {
                "ok": False,
                "error_code": "WRONG_INSTANCE",
                "exit_code": ERROR_CODES["WRONG_INSTANCE"],
                "message": (
                    f"Running Quickshell instance(s) {found_paths} do not match requested config_dir "
                    f"{redact_string(str(resolved_cfg))}."
                ),
                "instances": instances,
            }
        chosen = instances[0]
    else:
        chosen = matching[0]

    # Check stale install if version.json exists in target config_dir
    version_json = resolved_cfg / "version.json"
    repo_sha = get_git_head_sha(REPO_ROOT)
    installed_sha = None
    if version_json.exists():
        try:
            vdata = json.loads(version_json.read_text(errors="replace"))
            installed_sha = vdata.get("commit") or vdata.get("sha")
        except Exception:
            pass

    if (
        installed_sha
        and repo_sha != "unknown"
        and installed_sha != repo_sha
        and resolved_cfg != REPO_ROOT.resolve()
        and not allow_mismatch
    ):
        return {
            "ok": False,
            "error_code": "STALE_INSTALL",
            "exit_code": ERROR_CODES["STALE_INSTALL"],
            "message": f"Installed config commit ({installed_sha[:12]}) differs from repo HEAD ({repo_sha[:12]}).",
            "pid": chosen["pid"],
        }

    return {
        "ok": True,
        "error_code": "OK",
        "exit_code": 0,
        "pid": chosen["pid"],
        "comm": chosen["comm"],
        "config_path": chosen.get("config_path") or str(resolved_cfg),
        "source_sha": repo_sha,
    }


def call_qs_ipc(
    config_dir: Path,
    target: str,
    func: str,
    *args: str,
    pid: int | None = None,
    timeout_s: float = 4.0,
) -> dict[str, Any]:
    """Call `qs ipc` for a specific PID or config_dir safely."""
    qs_bin = os.environ.get("QS_BIN", "qs")
    if pid is not None and pid > 0:
        cmd = [qs_bin, "ipc", "--pid", str(pid), "call", target, func, *args]
    else:
        cmd = [qs_bin, "-p", str(config_dir), "ipc", "--any-display", "call", target, func, *args]
    try:
        res = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout_s,
            check=False,
        )
        stdout = (res.stdout or "").strip()
        stderr = (res.stderr or "").strip()
        if res.returncode != 0 or "Target not found" in stdout or "Target not found" in stderr:
            return {
                "ok": False,
                "error_code": "MISSING_IPC",
                "raw_stdout": stdout,
                "raw_stderr": stderr,
            }
        # Parse JSON if the response contains a JSON object/array
        parsed = None
        for candidate in (stdout, stdout.splitlines()[-1] if stdout.splitlines() else ""):
            candidate = candidate.strip()
            if candidate.startswith("{") or candidate.startswith("["):
                try:
                    parsed = json.loads(candidate)
                    break
                except Exception:
                    pass
        return {
            "ok": True,
            "error_code": "OK",
            "parsed": parsed,
            "raw_stdout": stdout,
        }
    except Exception as exc:
        return {
            "ok": False,
            "error_code": "MISSING_IPC",
            "message": str(exc),
        }


# ---------------------------------------------------------------------------
# Single-Sample & Bounded Trace Collector (P2, P3, P4, P5)
# ---------------------------------------------------------------------------

def collect_process_sample(
    pid: int,
    proc_root: Path = Path("/proc"),
    sys_drm_root: Path = Path("/sys/class/drm"),
    include_smaps_categories: bool = False,
) -> dict[str, Any]:
    """Collect a single point-in-time OS sample for `pid`."""
    pid_dir = proc_root / str(pid)
    mono_ns = time.monotonic_ns()
    wall_ms = int(time.time() * 1000)

    if not pid_dir.exists():
        return {
            "pid": pid,
            "exists": False,
            "monotonic_ns": mono_ns,
            "timestamp_ms": wall_ms,
        }

    stat_txt = ""
    status_txt = ""
    rollup_txt = ""
    try:
        stat_txt = (pid_dir / "stat").read_text(errors="replace")
    except OSError:
        pass
    try:
        status_txt = (pid_dir / "status").read_text(errors="replace")
    except OSError:
        pass
    try:
        if (pid_dir / "smaps_rollup").exists():
            rollup_txt = (pid_dir / "smaps_rollup").read_text(errors="replace")
    except OSError:
        pass

    proc_stat = parse_proc_stat(stat_txt)
    proc_status = parse_proc_status(status_txt)
    smaps_rollup = parse_smaps_rollup(rollup_txt)

    threads: list[dict[str, Any]] = []
    task_dir = pid_dir / "task"
    if task_dir.exists():
        for t_entry in task_dir.iterdir():
            if not t_entry.name.isdigit():
                continue
            try:
                t_stat = parse_proc_stat((t_entry / "stat").read_text(errors="replace"))
                if t_stat:
                    t_stat["thread_class"] = classify_thread(
                        t_stat.get("comm", ""),
                        is_leader=(int(t_stat["pid"]) == pid),
                    )
                    threads.append(t_stat)
            except OSError:
                continue

    smaps_cats = None
    if include_smaps_categories:
        try:
            smaps_txt = (pid_dir / "smaps").read_text(errors="replace")
            smaps_cats = parse_smaps_categories(smaps_txt, total_rss_kb=proc_status.get("vm_rss_kb", 0))
        except OSError:
            smaps_cats = {"available": False, "attribution": "unavailable"}

    gpu_env = sample_gpu_environment(sys_drm_root=sys_drm_root, proc_pid_dir=pid_dir)

    return {
        "pid": pid,
        "exists": True,
        "monotonic_ns": mono_ns,
        "timestamp_ms": wall_ms,
        "proc_stat": proc_stat,
        "proc_status": proc_status,
        "smaps_rollup": smaps_rollup,
        "smaps_categories": smaps_cats,
        "threads": threads,
        "gpu": gpu_env,
    }


def collect_child_and_compositor_snapshot(
    shell_pid: int,
    proc_root: Path = Path("/proc"),
) -> tuple[list[dict[str, Any]], dict[str, Any] | None]:
    """Collect RSS and ticks for child helpers of shell_pid and independent Niri compositor."""
    children: list[dict[str, Any]] = []
    compositor: dict[str, Any] | None = None
    if not proc_root.exists():
        return children, compositor

    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        p = int(entry.name)
        if p == shell_pid:
            continue
        try:
            st = parse_proc_stat((entry / "stat").read_text(errors="replace"))
            if not st:
                continue
            if st["ppid"] == shell_pid:
                status_info = parse_proc_status((entry / "status").read_text(errors="replace"))
                children.append(
                    {
                        "pid": p,
                        "comm": st["comm"],
                        "rss_kb": status_info.get("vm_rss_kb", 0),
                        "total_ticks": st["total_ticks"],
                    }
                )
            elif st["comm"] == "niri" and compositor is None:
                status_info = parse_proc_status((entry / "status").read_text(errors="replace"))
                compositor = {
                    "pid": p,
                    "comm": "niri",
                    "rss_kb": status_info.get("vm_rss_kb", 0),
                    "total_ticks": st["total_ticks"],
                }
        except OSError:
            continue

    return children, compositor


def detect_power_profile() -> dict[str, Any]:
    """Read system power profile for comparability metadata (P3)."""
    acpi_path = Path("/sys/firmware/acpi/platform_profile")
    try:
        if acpi_path.exists():
            return {
                "profile": acpi_path.read_text(errors="replace").strip(),
                "source": str(acpi_path),
                "attribution": "correlation",
            }
    except OSError:
        pass
    return {"profile": "unknown", "source": "unavailable", "attribution": "unavailable"}


def run_bounded_capture(
    config_dir: Path,
    duration_s: float = 5.0,
    interval_ms: int = 200,
    max_samples: int = 600,
    max_bytes: int = DEFAULT_MAX_BYTES,
    scenario_id: str = "ad-hoc",
    allow_mismatch: bool = False,
    proc_root: Path = Path("/proc"),
    sys_drm_root: Path = Path("/sys/class/drm"),
    expected_pid: int | None = None,
) -> dict[str, Any]:
    """Execute a bounded, opt-in profiling session against a validated Quickshell instance."""
    bounded_duration = max(0.2, min(float(duration_s), HARD_MAX_DURATION_S))
    bounded_interval_ms = max(HARD_MIN_INTERVAL_MS, min(int(interval_ms), HARD_MAX_INTERVAL_MS))
    bounded_max_samples = max(2, min(int(max_samples), HARD_MAX_SAMPLES))

    validation = validate_target_instance(
        config_dir=config_dir,
        proc_root=proc_root,
        expected_pid=expected_pid,
        allow_mismatch=allow_mismatch,
    )
    if not validation.get("ok"):
        return validation

    pid = int(validation["pid"])
    clk_tck = int(os.sysconf("SC_CLK_TCK")) if hasattr(os, "sysconf") else 100
    cpu_count = os.cpu_count() or 1

    # Start QML perfProbe IPC if available
    probe_opts = json.dumps(
        {
            "maxDurationMs": int(bounded_duration * 1000) + 5000,
            "maxFrameSamples": min(2400, bounded_max_samples * 2),
            "maxSpans": 500,
            "scenarioId": scenario_id,
        }
    )
    ipc_start = call_qs_ipc(config_dir, "perfProbe", "start", probe_opts, pid=pid)

    start_wall_ms = int(time.time() * 1000)
    start_mono_ns = time.monotonic_ns()
    children_start, comp_start = collect_child_and_compositor_snapshot(pid, proc_root=proc_root)

    raw_samples: list[dict[str, Any]] = []
    deadline_ns = start_mono_ns + int(bounded_duration * 1e9)

    try:
        while len(raw_samples) < bounded_max_samples:
            is_first = len(raw_samples) == 0
            sample = collect_process_sample(
                pid=pid,
                proc_root=proc_root,
                sys_drm_root=sys_drm_root,
                include_smaps_categories=is_first,
            )
            raw_samples.append(sample)
            if not sample.get("exists"):
                break
            now_ns = time.monotonic_ns()
            if now_ns >= deadline_ns and len(raw_samples) >= 2:
                break
            sleep_s = min(bounded_interval_ms / 1000.0, max(0.01, (deadline_ns - now_ns) / 1e9))
            time.sleep(sleep_s)

        # Ensure final sample includes smaps categories
        if raw_samples and raw_samples[-1].get("exists") and raw_samples[-1].get("smaps_categories") is None:
            raw_samples[-1] = collect_process_sample(
                pid=pid,
                proc_root=proc_root,
                sys_drm_root=sys_drm_root,
                include_smaps_categories=True,
            )
    finally:
        ipc_stop = call_qs_ipc(config_dir, "perfProbe", "stop", pid=pid)

    children_end, comp_end = collect_child_and_compositor_snapshot(pid, proc_root=proc_root)
    stop_wall_ms = int(time.time() * 1000)
    total_elapsed_s = max(0.001, (time.monotonic_ns() - start_mono_ns) / 1e9)

    if not raw_samples or not raw_samples[0].get("exists"):
        return {
            "ok": False,
            "error_code": "EMPTY_TRACE",
            "exit_code": ERROR_CODES["EMPTY_TRACE"],
            "message": "Target process exited before any samples could be collected.",
        }

    # Compute interval deltas
    timeseries: list[dict[str, Any]] = []
    cpu_single_vals: list[float] = []
    cpu_norm_vals: list[float] = []
    class_accum: dict[str, list[float]] = {
        "main_gui": [],
        "qsg_render": [],
        "rhi_driver": [],
        "media_codec": [],
        "qml_worker": [],
        "other": [],
    }
    anomalies: list[str] = []

    for i in range(1, len(raw_samples)):
        prev_s = raw_samples[i - 1]
        curr_s = raw_samples[i]
        if not curr_s.get("exists"):
            anomalies.append("PID_EXITED_DURING_CAPTURE")
            break
        cpu_d = compute_cpu_delta(prev_s, curr_s, clk_tck=clk_tck, cpu_count=cpu_count)
        if not cpu_d.get("valid"):
            if cpu_d.get("anomaly"):
                anomalies.append(str(cpu_d["anomaly"]))
        else:
            cpu_single_vals.append(cpu_d["single_core_pct"])
            cpu_norm_vals.append(cpu_d["normalized_pct"])
            for k, v in (cpu_d.get("class_single_core_pct") or {}).items():
                class_accum.setdefault(k, []).append(v)

        elapsed_ns = int(curr_s["monotonic_ns"]) - int(prev_s["monotonic_ns"])
        drm_d = compute_drm_engine_delta(
            (prev_s.get("gpu") or {}).get("process_drm") or {},
            (curr_s.get("gpu") or {}).get("process_drm") or {},
            elapsed_ns=elapsed_ns,
        )
        timeseries.append(
            {
                "timestamp_ms": curr_s["timestamp_ms"],
                "cpu": cpu_d,
                "memory": {
                    "vm_rss_kb": (curr_s.get("proc_status") or {}).get("vm_rss_kb", 0),
                    "pss_kb": (curr_s.get("smaps_rollup") or {}).get("pss_kb", 0),
                    "uss_kb": (curr_s.get("smaps_rollup") or {}).get("uss_kb", 0),
                    "swap_kb": (curr_s.get("proc_status") or {}).get("vm_swap_kb", 0),
                },
                "gpu_drm_delta": drm_d,
            }
        )

    first_s = raw_samples[0]
    last_s = raw_samples[-1] if raw_samples[-1].get("exists") else raw_samples[0]

    rss_start = (first_s.get("proc_status") or {}).get("vm_rss_kb", 0)
    rss_end = (last_s.get("proc_status") or {}).get("vm_rss_kb", 0)
    pss_start = (first_s.get("smaps_rollup") or {}).get("pss_kb", 0)
    pss_end = (last_s.get("smaps_rollup") or {}).get("pss_kb", 0)
    uss_start = (first_s.get("smaps_rollup") or {}).get("uss_kb", 0)
    uss_end = (last_s.get("smaps_rollup") or {}).get("uss_kb", 0)

    # Compute child helper & compositor CPU %
    start_children_map = {c["pid"]: c for c in children_start}
    child_summaries = []
    for c_end in children_end:
        c_start = start_children_map.get(c_end["pid"])
        c_pct = 0.0
        if c_start:
            dt = max(0, int(c_end["total_ticks"]) - int(c_start["total_ticks"]))
            c_pct = round((dt / (clk_tck * total_elapsed_s)) * 100.0, 3)
        child_summaries.append(
            {
                "pid": c_end["pid"],
                "comm": c_end["comm"],
                "rss_kb": c_end["rss_kb"],
                "cpu_single_core_pct": c_pct,
                "attribution": "direct_measurement",
            }
        )

    comp_summary = None
    if comp_end:
        comp_pct = 0.0
        if comp_start and comp_start["pid"] == comp_end["pid"]:
            dt = max(0, int(comp_end["total_ticks"]) - int(comp_start["total_ticks"]))
            comp_pct = round((dt / (clk_tck * total_elapsed_s)) * 100.0, 3)
        comp_summary = {
            "pid": comp_end["pid"],
            "comm": "niri",
            "rss_kb": comp_end["rss_kb"],
            "cpu_single_core_pct": comp_pct,
            "attribution": "direct_measurement",
        }

    mean_single = round(sum(cpu_single_vals) / len(cpu_single_vals), 3) if cpu_single_vals else 0.0
    max_single = round(max(cpu_single_vals), 3) if cpu_single_vals else 0.0
    mean_norm = round(sum(cpu_norm_vals) / len(cpu_norm_vals), 3) if cpu_norm_vals else 0.0
    mean_class = {
        k: round(sum(vals) / len(vals), 3) if vals else 0.0 for k, vals in class_accum.items()
    }

    qml_payload = ipc_stop.get("parsed") if ipc_stop.get("ok") and isinstance(ipc_stop.get("parsed"), dict) else {
        "ok": False,
        "attribution": "unavailable",
        "reason": ipc_stop.get("error_code", "MISSING_IPC"),
    }

    trace: dict[str, Any] = {
        "ok": True,
        "error_code": "OK",
        "schemaVersion": 1,
        "featureCode": "PERF-F01",
        "scenarioId": scenario_id,
        "sourceSha": validation.get("source_sha", get_git_head_sha()),
        "targetInstance": {
            "pid": pid,
            "comm": validation.get("comm", "qs"),
            "configPath": redact_string(str(validation.get("config_path", config_dir))),
            "clkTck": clk_tck,
            "cpuCount": cpu_count,
            "powerProfile": detect_power_profile(),
        },
        "captureWindow": {
            "startedAtMs": start_wall_ms,
            "stoppedAtMs": stop_wall_ms,
            "durationS": round(total_elapsed_s, 3),
            "intervalMs": bounded_interval_ms,
            "sampleCount": len(raw_samples),
            "anomalies": sorted(set(anomalies)),
        },
        "attributionDefinitions": ATTRIBUTION_LEVELS,
        "summary": {
            "cpu": {
                "attribution": "direct_measurement",
                "mean_single_core_pct": mean_single,
                "max_single_core_pct": max_single,
                "mean_normalized_pct": mean_norm,
                "mean_class_single_core_pct": mean_class,
            },
            "memory": {
                "attribution": "direct_measurement",
                "rss_start_kb": rss_start,
                "rss_end_kb": rss_end,
                "rss_delta_kb": rss_end - rss_start,
                "pss_start_kb": pss_start,
                "pss_end_kb": pss_end,
                "pss_delta_kb": pss_end - pss_start,
                "uss_start_kb": uss_start,
                "uss_end_kb": uss_end,
                "uss_delta_kb": uss_end - uss_start,
                "smaps_categories_start": first_s.get("smaps_categories"),
                "smaps_categories_end": last_s.get("smaps_categories"),
            },
            "gpu": last_s.get("gpu"),
            "child_helpers": child_summaries,
            "compositor": comp_summary,
        },
        "qmlProbe": qml_payload,
        "samples": timeseries,
    }

    trace["componentRanking"] = build_component_ranking(trace)
    trace = redact_sensitive_data(trace)
    trace = enforce_trace_budget(trace, max_bytes=max_bytes)
    return trace


# ---------------------------------------------------------------------------
# P8 & P10: A/B Comparison & Multi-Format Report Generation
# ---------------------------------------------------------------------------

def compare_traces(baseline: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    """Compute a controlled A/B comparison between baseline and candidate traces (P8, P10)."""
    b_sum = baseline.get("summary") or {}
    c_sum = candidate.get("summary") or {}

    b_cpu = (b_sum.get("cpu") or {}).get("mean_single_core_pct", 0.0)
    c_cpu = (c_sum.get("cpu") or {}).get("mean_single_core_pct", 0.0)
    b_gui = ((b_sum.get("cpu") or {}).get("mean_class_single_core_pct") or {}).get("main_gui", 0.0)
    c_gui = ((c_sum.get("cpu") or {}).get("mean_class_single_core_pct") or {}).get("main_gui", 0.0)
    b_qsg = ((b_sum.get("cpu") or {}).get("mean_class_single_core_pct") or {}).get("qsg_render", 0.0)
    c_qsg = ((c_sum.get("cpu") or {}).get("mean_class_single_core_pct") or {}).get("qsg_render", 0.0)

    b_mem = b_sum.get("memory") or {}
    c_mem = c_sum.get("memory") or {}
    b_uss = b_mem.get("uss_end_kb", 0)
    c_uss = c_mem.get("uss_end_kb", 0)
    b_rss = b_mem.get("rss_end_kb", 0)
    c_rss = c_mem.get("rss_end_kb", 0)
    b_del_gc = ((b_mem.get("smaps_categories_end") or {}).get("js_gc_heap_deleted_kb", 0))
    c_del_gc = ((c_mem.get("smaps_categories_end") or {}).get("js_gc_heap_deleted_kb", 0))

    b_frame = (((baseline.get("qmlProbe") or {}).get("frameTiming") or {}).get("stats") or {})
    c_frame = (((candidate.get("qmlProbe") or {}).get("frameTiming") or {}).get("stats") or {})
    b_p95 = b_frame.get("p95Ms")
    c_p95 = c_frame.get("p95Ms")

    b_prof = (((baseline.get("targetInstance") or {}).get("powerProfile") or {}).get("profile", "unknown"))
    c_prof = (((candidate.get("targetInstance") or {}).get("powerProfile") or {}).get("profile", "unknown"))
    comparable = (b_prof == c_prof) and (baseline.get("scenarioId") == candidate.get("scenarioId"))

    return {
        "schemaVersion": 1,
        "attribution": "controlled_ab_estimate",
        "comparableEnvironment": comparable,
        "environmentNotes": {
            "baselineScenario": baseline.get("scenarioId"),
            "candidateScenario": candidate.get("scenarioId"),
            "baselinePowerProfile": b_prof,
            "candidatePowerProfile": c_prof,
            "baselineSha": baseline.get("sourceSha"),
            "candidateSha": candidate.get("sourceSha"),
        },
        "deltas": {
            "cpu_mean_single_core_pct": round(c_cpu - b_cpu, 3),
            "cpu_main_gui_pct": round(c_gui - b_gui, 3),
            "cpu_qsg_render_pct": round(c_qsg - b_qsg, 3),
            "memory_rss_end_kb": int(c_rss - b_rss),
            "memory_uss_end_kb": int(c_uss - b_uss),
            "memory_js_gc_heap_deleted_kb": int(c_del_gc - b_del_gc),
            "frame_p95_ms": round(float(c_p95) - float(b_p95), 3) if (b_p95 is not None and c_p95 is not None) else None,
        },
    }


def format_report(trace: dict[str, Any], fmt: str = "markdown") -> str:
    """Format a trace into JSON, Markdown, CSV, or self-contained HTML (P10)."""
    fmt_norm = (fmt or "markdown").strip().lower()
    if fmt_norm == "json":
        return json.dumps(trace, indent=2, ensure_ascii=False)

    summary = trace.get("summary") or {}
    cpu = summary.get("cpu") or {}
    mem = summary.get("memory") or {}
    qml = trace.get("qmlProbe") or {}
    frame_stats = ((qml.get("frameTiming") or {}).get("stats") or {})
    hb_stats = ((qml.get("eventLoopHeartbeat") or {}).get("stats") or {})
    ranking = trace.get("componentRanking") or []

    if fmt_norm == "csv":
        buf = io.StringIO()
        writer = csv.writer(buf)
        writer.writerow(["component_id", "category", "attribution_level", "confidence", "metrics_json", "uncertainty_note"])
        for row in ranking:
            writer.writerow(
                [
                    row.get("component_id", ""),
                    row.get("category", ""),
                    row.get("attribution_level", ""),
                    row.get("confidence", ""),
                    json.dumps(row.get("metrics", {}), ensure_ascii=False),
                    row.get("uncertainty_note", ""),
                ]
            )
        return buf.getvalue()

    md_lines = [
        f"# Alis Quickshell Performance Profile (`{trace.get('scenarioId', 'ad-hoc')}`)",
        "",
        f"- **Source SHA:** `{trace.get('sourceSha', 'unknown')}`",
        f"- **Target PID:** `{trace.get('targetInstance', {}).get('pid', '?')}` (`{trace.get('targetInstance', {}).get('configPath', '?')}`)",
        f"- **Duration:** `{trace.get('captureWindow', {}).get('durationS', 0)}s` (`{trace.get('captureWindow', {}).get('sampleCount', 0)}` samples @ `{trace.get('captureWindow', {}).get('intervalMs', 0)}ms`)",
        "",
        "## CPU & Thread Breakdown (`direct_measurement`)",
        f"- **Mean CPU (single-core %):** `{cpu.get('mean_single_core_pct', 0.0)}%` (Max: `{cpu.get('max_single_core_pct', 0.0)}%`, Normalized multi-core: `{cpu.get('mean_normalized_pct', 0.0)}%`)",
        f"- **Thread Classes:** `{json.dumps(cpu.get('mean_class_single_core_pct', {}))}`",
        "",
        "## Memory & Object Lifetime (`direct_measurement`)",
        f"- **VmRSS:** `{mem.get('rss_start_kb', 0)} KB` -> `{mem.get('rss_end_kb', 0)} KB` (Delta: `{mem.get('rss_delta_kb', 0)} KB`)",
        f"- **PSS:** `{mem.get('pss_start_kb', 0)} KB` -> `{mem.get('pss_end_kb', 0)} KB` (Delta: `{mem.get('pss_delta_kb', 0)} KB`)",
        f"- **USS:** `{mem.get('uss_start_kb', 0)} KB` -> `{mem.get('uss_end_kb', 0)} KB` (Delta: `{mem.get('uss_delta_kb', 0)} KB`)",
        "",
        "## QML Frame & Event-Loop Timing (`instrumented_span`)",
        f"- **Frame Swapped (`QQuickWindow.frameSwapped`):** count=`{frame_stats.get('count', 0)}`, p50=`{frame_stats.get('p50Ms')}`, p95=`{frame_stats.get('p95Ms')}`, p99=`{frame_stats.get('p99Ms')}`, >25ms=`{frame_stats.get('over25msCount', 0)}`",
        f"- **Main-Thread Heartbeat Jitter:** count=`{hb_stats.get('count', 0)}`, p95=`{hb_stats.get('p95Ms')}`, >16ms stalls=`{(qml.get('eventLoopHeartbeat') or {}).get('over16msStallCount', 0)}`",
        "",
        "## Component Cost Ranking & Attribution Truthfulness",
        "| Component | Category | Attribution Level | Confidence | Metrics | Notes |",
        "|-----------|----------|-------------------|------------|---------|-------|",
    ]
    for item in ranking:
        md_lines.append(
            f"| `{item.get('component_id')}` | `{item.get('category')}` | `{item.get('attribution_level')}` | "
            f"`{item.get('confidence')}` | `{json.dumps(item.get('metrics', {}))}` | {item.get('uncertainty_note', '')} |"
        )
    md_text = "\n".join(md_lines) + "\n"

    if fmt_norm == "html":
        escaped = html.escape(md_text)
        return (
            "<!DOCTYPE html><html><head><meta charset='utf-8'>"
            "<title>Alis Performance Profile</title>"
            "<style>body{font-family:monospace;background:#111;color:#eee;padding:24px;}pre{white-space:pre-wrap;}</style>"
            f"</head><body><pre>{escaped}</pre></body></html>"
        )
    return md_text


# ---------------------------------------------------------------------------
# CLI Entrypoint
# ---------------------------------------------------------------------------

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="alis debug perf",
        description="Opt-in bounded CPU/RAM/GPU/QML performance profiler for Alis Quickshell (PERF-F01).",
    )
    sub = parser.add_subparsers(dest="subcommand")

    p_arch = sub.add_parser("architecture", help="Print the Alis Quickshell architecture & observability map (P1).")
    p_arch.add_argument("--config-dir", default=str(REPO_ROOT))
    p_arch.add_argument("--format", choices=["json", "markdown"], default="json")

    p_scen = sub.add_parser("scenarios", help="List canonical reproducible workload scenarios (P9).")
    p_scen.add_argument("--format", choices=["json", "markdown"], default="json")

    p_start = sub.add_parser("start", help="Run a bounded opt-in profiling capture session (P2-P11).")
    p_start.add_argument("--config-dir", default=str(REPO_ROOT))
    p_start.add_argument("--duration", type=float, default=5.0)
    p_start.add_argument("--interval-ms", type=int, default=200)
    p_start.add_argument("--max-samples", type=int, default=600)
    p_start.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES)
    p_start.add_argument("--scenario", default="ad-hoc")
    p_start.add_argument("--output", default="")
    p_start.add_argument("--allow-mismatch", action="store_true")

    p_status = sub.add_parser("status", help="Query live perfProbe status from running Quickshell.")
    p_status.add_argument("--config-dir", default=str(REPO_ROOT))

    p_stop = sub.add_parser("stop", help="Stop active perfProbe session on running Quickshell.")
    p_stop.add_argument("--config-dir", default=str(REPO_ROOT))

    p_cancel = sub.add_parser("cancel", help="Cancel and discard active perfProbe session.")
    p_cancel.add_argument("--config-dir", default=str(REPO_ROOT))

    p_rep = sub.add_parser("report", help="Render a saved trace file in json, markdown, csv, or html format (P10).")
    p_rep.add_argument("trace_file")
    p_rep.add_argument("--format", choices=["json", "markdown", "csv", "html"], default="markdown")
    p_rep.add_argument("--output", default="")

    p_cmp = sub.add_parser("compare", help="Compare baseline and candidate trace files (P8, P10).")
    p_cmp.add_argument("baseline")
    p_cmp.add_argument("candidate")
    p_cmp.add_argument("--format", choices=["json", "markdown"], default="json")

    p_doc = sub.add_parser("doctor-snapshot", help="Machine-readable single snapshot for `alis doctor --perf --json`.")
    p_doc.add_argument("--config-dir", default=str(REPO_ROOT))
    p_doc.add_argument("--json", action="store_true")

    args = parser.parse_args(argv)
    if not args.subcommand:
        parser.print_help()
        return 0

    if args.subcommand == "architecture":
        cfg_dir = Path(args.config_dir)
        snap_res = call_qs_ipc(cfg_dir, "perfProbe", "snapshot")
        live = snap_res.get("parsed") if snap_res.get("ok") else None
        arch = build_architecture_map(config_dir=cfg_dir, live_snapshot=live)
        if args.format == "json":
            print(json.dumps(arch, indent=2, ensure_ascii=False))
        else:
            print(f"# Alis Architecture & Observability Map (`{arch['sourceSha']}`)\n")
            for m in arch["observabilityMatrix"]:
                print(f"- **{m['metric']}** (`{m['attribution_level']}`): {m['source']} — {m['limitations']}")
        return 0

    if args.subcommand == "scenarios":
        scens = get_workload_scenarios()
        if args.format == "json":
            print(json.dumps(scens, indent=2, ensure_ascii=False))
        else:
            for s in scens:
                print(f"- `{s['id']}` ({s['recommendedDurationS']}s): {s['description']}")
        return 0

    if args.subcommand == "start":
        cfg_dir = Path(args.config_dir)
        trace = run_bounded_capture(
            config_dir=cfg_dir,
            duration_s=args.duration,
            interval_ms=args.interval_ms,
            max_samples=args.max_samples,
            max_bytes=args.max_bytes,
            scenario_id=args.scenario,
            allow_mismatch=args.allow_mismatch,
        )
        if not trace.get("ok"):
            print(json.dumps(trace, indent=2, ensure_ascii=False), file=sys.stderr)
            return int(trace.get("exit_code", 1))
        out_path = Path(args.output) if args.output else (get_cache_dir() / f"trace-{int(time.time())}.json")
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(trace, indent=2, ensure_ascii=False), encoding="utf-8")
        trace["savedTo"] = redact_string(str(out_path))
        print(json.dumps(trace, indent=2, ensure_ascii=False))
        return 0

    if args.subcommand in ("status", "stop", "cancel"):
        cfg_dir = Path(args.config_dir)
        res = call_qs_ipc(cfg_dir, "perfProbe", args.subcommand)
        print(json.dumps(res, indent=2, ensure_ascii=False))
        return 0 if res.get("ok") else ERROR_CODES["MISSING_IPC"]

    if args.subcommand == "report":
        tpath = Path(args.trace_file)
        if not tpath.exists():
            print(f"Error: trace file not found: {tpath}", file=sys.stderr)
            return ERROR_CODES["INVALID_ARGS"]
        data = json.loads(tpath.read_text(encoding="utf-8"))
        rendered = format_report(data, fmt=args.format)
        if args.output:
            Path(args.output).write_text(rendered, encoding="utf-8")
        else:
            print(rendered)
        return 0

    if args.subcommand == "compare":
        bpath = Path(args.baseline)
        cpath = Path(args.candidate)
        if not bpath.exists() or not cpath.exists():
            print("Error: baseline or candidate trace file not found", file=sys.stderr)
            return ERROR_CODES["INVALID_ARGS"]
        bdata = json.loads(bpath.read_text(encoding="utf-8"))
        cdata = json.loads(cpath.read_text(encoding="utf-8"))
        diff = compare_traces(bdata, cdata)
        if args.format == "json":
            print(json.dumps(diff, indent=2, ensure_ascii=False))
        else:
            print("# A/B Performance Comparison (`controlled_ab_estimate`)\n")
            for k, v in diff["deltas"].items():
                print(f"- **{k}:** `{v}`")
        return 0

    if args.subcommand == "doctor-snapshot":
        cfg_dir = Path(args.config_dir)
        trace = run_bounded_capture(
            config_dir=cfg_dir,
            duration_s=0.5,
            interval_ms=150,
            max_samples=5,
            scenario_id="doctor-snapshot",
            allow_mismatch=True,
        )
        print(json.dumps(trace, indent=2, ensure_ascii=False))
        return 0 if trace.get("ok") else int(trace.get("exit_code", 1))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
