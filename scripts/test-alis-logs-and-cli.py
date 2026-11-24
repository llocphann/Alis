#!/usr/bin/env python3
"""Silent headless tests for scripts/lib/alis-logs.py, scripts/alis CLI, and shell completions."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
LOGS_PY = ROOT / "scripts/lib/alis-logs.py"
ALIS_CLI = ROOT / "scripts/alis"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")

SAMPLE_LOGS = "\n".join([
    "2026-11-23T14:00:01+0700 host quickshell[1234]:   INFO: Configuration Loaded",
    "2026-11-23T14:00:02+0700 host quickshell[1234]:   WARN scene: @services/LocalMusic.qml[259:5]: Unable to assign [undefined] to double",
    "2026-11-23T14:00:02+0700 host quickshell[1234]:   WARN scene: @services/LocalMusic.qml[259:5]: Unable to assign [undefined] to double",
    "2026-11-23T14:00:03+0700 host quickshell[1234]:   WARN scene: @services/LocalMusic.qml[259:5]: Unable to assign [undefined] to double",
    "2026-11-23T14:00:05+0700 host quickshell[1234]:  ERROR qml: [Weather] Forecast request timed out",
    "2026-11-23T14:00:06+0700 host quickshell[1234]:  DEBUG qml: [ShellUpdates] Cache hit for version index",
    "2026-11-23T14:00:07+0700 host systemd[1000]: CRITICAL: fatal segfault simulated check",
])


def _clean_env() -> dict[str, str]:
    env = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "DISPLAY", "NO_COLOR")}
    env["QT_QPA_PLATFORM"] = "offscreen"
    env["PYTHONDONTWRITEBYTECODE"] = "1"
    return env


def run_logs(args: list[str], stdin_text: str = SAMPLE_LOGS) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        [sys.executable, str(LOGS_PY), "--stdin", *args],
        input=stdin_text,
        capture_output=True,
        text=True,
        env=_clean_env(),
        timeout=20,
    )
    assert proc.returncode == 0, f"alis-logs {args} failed ({proc.returncode}): {proc.stdout}\n{proc.stderr}"
    return proc


def run_alis(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(ALIS_CLI), *args],
        capture_output=True,
        text=True,
        env=_clean_env(),
        timeout=20,
    )


def test_logs_parsing_filtering_and_formats() -> None:
    # 1. Default batch formatting + consecutive collapse + no ANSI when --no-color
    p_plain = run_logs(["--no-color"])
    assert not ANSI_RE.search(p_plain.stdout), "--no-color must not emit ANSI escapes"
    assert "Configuration Loaded" in p_plain.stdout
    assert "×3" in p_plain.stdout, f"expected repeat collapse marker ×3 in:\n{p_plain.stdout}"
    assert "Forecast request timed out" in p_plain.stdout

    # 2. --color emits ANSI escapes even on pipe
    p_col = run_logs(["--color"])
    assert ANSI_RE.search(p_col.stdout), "--color must emit ANSI sequences"

    # 3. --errors hides INFO and DEBUG, keeps WARN/ERROR/CRIT
    p_err = run_logs(["--errors", "--json"])
    rows_err = json.loads(p_err.stdout)
    assert isinstance(rows_err, list) and len(rows_err) == 5, rows_err
    assert all(r["level"] in ("WARN", "ERROR", "CRIT") for r in rows_err), rows_err

    # 4. --level error hides WARN; --level crit keeps only CRIT
    p_lvl = run_logs(["-l", "error", "--json"])
    rows_lvl = json.loads(p_lvl.stdout)
    assert len(rows_lvl) == 2 and all(r["level"] in ("ERROR", "CRIT") for r in rows_lvl), rows_lvl

    p_crit = run_logs(["-l", "crit", "--json"])
    rows_crit = json.loads(p_crit.stdout)
    assert len(rows_crit) == 1 and rows_crit[0]["level"] == "CRIT", rows_crit

    # 5. Component & category & grep filters
    p_comp = run_logs(["-m", "Weather", "--json"])
    rows_comp = json.loads(p_comp.stdout)
    assert len(rows_comp) == 1 and rows_comp[0]["component"] == "Weather", rows_comp

    p_cat = run_logs(["--category", "scene", "--json"])
    rows_cat = json.loads(p_cat.stdout)
    assert len(rows_cat) == 3 and all(r["category"] == "scene" for r in rows_cat), rows_cat

    p_grep = run_logs(["-g", "localmusic\\.qml", "--json"])
    rows_grep = json.loads(p_grep.stdout)
    assert len(rows_grep) == 3, rows_grep

    # 6. --ndjson produces one valid JSON object per line with schema keys
    p_nd = run_logs(["--ndjson"])
    nd_lines = [ln for ln in p_nd.stdout.splitlines() if ln.strip()]
    assert len(nd_lines) == 7, nd_lines
    for ln in nd_lines:
        obj = json.loads(ln)
        for key in ("date", "time", "level", "category", "component", "unit", "pid", "message", "count", "raw"):
            assert key in obj, f"missing {key} in ndjson row {obj}"

    # 7. --summary renders breakdown
    p_sum = run_logs(["--summary", "--no-color"])
    assert "Summary" in p_sum.stdout or "SUMMARY" in p_sum.stdout.upper(), p_sum.stdout
    assert "ERROR" in p_sum.stdout and "WARN" in p_sum.stdout, p_sum.stdout

    # 8. --raw emits unmodified plain lines without headers
    p_raw = run_logs(["--raw", "-n", "2"])
    assert not ANSI_RE.search(p_raw.stdout)
    raw_lines = p_raw.stdout.strip().splitlines()
    assert len(raw_lines) == 2 and "Cache hit" in raw_lines[0], raw_lines


def test_modern_parsers_and_diagnose() -> None:
    mixed_logs = "\n".join([
        # ANSI color codes in `qs log` output should be stripped & category parsed
        "2026-11-24T07:14:28+0700 host quickshell[1596]: \x1b[33m  WARN\x1b[97m qt.svg\x1b[0m: <input>:1:5634: Could not resolve property: a",
        # Known portal registration duplicate warning classified as noise
        "2026-11-24T07:14:29+0700 host quickshell[1596]:   WARN qt.qpa.services: Failed to register with host portal QDBusError(\"org.freedesktop.portal.Error.Failed\", \"Connection already associated with an application ID\")",
        # Double-prefixed xwayland-satellite non-fatal xkbcomp message must NOT become CRIT
        "2026-11-24T07:14:30+0700 host niri[1400]: thinkpadt14 xwayland-satellite[2482]: Errors from xkbcomp are not fatal to the X server",
        # Rust tracing line from Niri
        "2026-11-24T07:14:31+0700 host niri[1400]: 2026-11-24T00:54:41.891605Z  INFO niri::niri: unlocking session",
        # Actionable runtime warning with component & no-category QML FileView warning
        "2026-11-24T07:14:48+0700 host quickshell[1596]:   WARN qml: [WindowPreviewService] capture process failed 1 0",
        "2026-11-24T07:54:43+0700 host quickshell[1596]:   WARN: @services/ScreenTime.qml[529:5]: Read of /tmp/2026-11-24.json failed: File does not exist",
        # Repeated QML warning should group cleanly in diagnose
        "2026-11-24T08:00:01+0700 host quickshell[1596]:   WARN scene: @modules/nexus/NexusWorkspace.qml[1608:13]: Window.window only supports types derived from Item",
        "2026-11-24T08:00:02+0700 host quickshell[1596]:   WARN scene: @modules/nexus/NexusWorkspace.qml[1608:13]: Window.window only supports types derived from Item",
    ])

    rows = json.loads(run_logs(["--json", "--no-collapse"], stdin_text=mixed_logs).stdout)
    assert len(rows) == 8, f"expected 8 parsed entries, got {len(rows)}: {rows}"
    assert rows[0]["level"] == "WARN" and rows[0]["category"] == "qt.svg", rows[0]
    assert not ANSI_RE.search(rows[0]["message"]), rows[0]
    assert rows[2]["unit"] == "xwayland-satellite" and rows[2]["level"] != "CRIT", rows[2]
    assert rows[3]["component"] == "niri::niri" and rows[3]["level"] == "INFO", rows[3]
    assert rows[5]["level"] == "WARN" and "@services/ScreenTime.qml[529:5]" in rows[5]["message"], rows[5]

    # --hide-noise removes noisy WARN entries (qt.svg / qt.qpa.services) while keeping INFO & actionable lines
    filtered_rows = json.loads(run_logs(["--hide-noise", "--json", "--no-collapse"], stdin_text=mixed_logs).stdout)
    assert len(filtered_rows) == 6, f"expected 6 non-noise entries, got {len(filtered_rows)}: {filtered_rows}"

    # --diagnose --json separates actionable issues (with hints & grouped counts) from noise
    diag = json.loads(run_logs(["--diagnose", "--json"], stdin_text=mixed_logs).stdout)
    assert diag["actionableCount"] == 4, diag
    assert diag["actionableGroups"] == 3, diag
    assert diag["noiseCount"] == 2, diag
    assert diag["healthy"] is False, diag
    nexus_group = next((g for g in diag["actionable"] if "NexusWorkspace" in g.get("sourceLoc", "")), None)
    assert nexus_group is not None and nexus_group["count"] == 2, diag

    # --fail-on-error exits 1 whenever actionable warnings or errors exist, exits 0 when only INFO/noise remain
    p_warn_fail = subprocess.run(
        [sys.executable, str(LOGS_PY), "--stdin", "--diagnose", "--fail-on-error", "--no-color"],
        input=mixed_logs,
        capture_output=True,
        text=True,
        env=_clean_env(),
        timeout=20,
    )
    assert p_warn_fail.returncode == 1 and "ACTIONABLE" in p_warn_fail.stdout, (p_warn_fail.returncode, p_warn_fail.stdout)

    noise_only_log = "\n".join([
        "2026-11-24T08:02:00+0700 host quickshell[1596]:   INFO: Configuration Loaded",
        "2026-11-24T08:02:01+0700 host quickshell[1596]:   WARN qt.svg: <input>:1:1: Could not resolve property: a",
        "2026-11-24T08:02:02+0700 host quickshell[1596]:   WARN quickshell.service.sni.item: Failed to load tray item \":1.539/StatusNotifierItem/org.kde.StatusNotifierItem\"",
    ]) + "\n"
    p_noise_ok = run_logs(["--diagnose", "--fail-on-error", "--no-color"], stdin_text=noise_only_log)
    assert "HEALTHY" in p_noise_ok.stdout, p_noise_ok.stdout

    # Healthy clean log exits 0 with healthy: true
    p_clean = run_logs(["--diagnose", "--json"], stdin_text="2026-11-24T08:02:00+0700 host quickshell[1596]:   INFO: Configuration Loaded\n")
    clean_diag = json.loads(p_clean.stdout)
    assert clean_diag["healthy"] is True and clean_diag["actionableCount"] == 0, clean_diag


def test_alis_cli_subcommands() -> None:
    # 1. Per-subcommand --help
    for sub in ("start", "stop", "run", "restart", "kill", "logs", "doctor", "status", "test", "test-local", "ipc"):
        p = run_alis(sub, "--help")
        combined = (p.stdout + "\n" + p.stderr).lower()
        assert p.returncode == 0, f"alis {sub} --help exited {p.returncode}: {p.stdout}\n{p.stderr}"
        assert sub.split("-")[0] in combined or "usage" in combined, combined

    # 2. Global help sanity (no dead docs/IPC.md link, mentions new commands)
    p_help = run_alis("help")
    assert p_help.returncode == 0
    assert "docs/IPC.md" not in p_help.stdout, "alis help still references dead docs/IPC.md"
    for needle in ("status", "test", "logs", "service"):
        assert needle in p_help.stdout, f"alis help missing {needle}"

    # 3. alis status --json
    p_status = run_alis("status", "--json")
    assert p_status.returncode == 0, f"alis status --json failed: {p_status.stdout}\n{p_status.stderr}"
    st = json.loads(p_status.stdout)
    for key in ("version", "commit", "branch", "installMode", "serviceActive", "panelFamily", "companion", "integration"):
        assert key in st, f"alis status --json missing key {key!r}: {st}"

    # 4. alis status --short
    p_short = run_alis("status", "--short")
    assert p_short.returncode == 0 and len(p_short.stdout.strip()) > 0

    # 5. alis test list
    p_tlist = run_alis("test", "list")
    assert p_tlist.returncode == 0, p_tlist.stdout
    for suite in ("quick", "local", "validate", "rust", "qml", "docs", "integration", "companion"):
        assert suite in p_tlist.stdout, f"alis test list missing suite {suite}"


def test_shell_completions() -> None:
    comp_dir = ROOT / "scripts/completions"
    bash_comp = comp_dir / "alis.bash"
    zsh_comp = comp_dir / "alis.zsh"
    fish_comp = comp_dir / "alis.fish"

    p_b = subprocess.run(["bash", "-n", str(bash_comp)], capture_output=True, text=True)
    assert p_b.returncode == 0, p_b.stderr
    p_f = subprocess.run(["fish", "-n", str(fish_comp)], capture_output=True, text=True)
    assert p_f.returncode == 0, p_f.stderr

    for token in ("status", "test", "--errors", "--summary", "--diagnose", "--since-restart", "--fail-on-error", "--hide-noise"):
        for f in (bash_comp, zsh_comp):
            txt = f.read_text(encoding="utf-8")
            assert token in txt, f"{f.name} missing completion token {token!r}"

    fish_txt = fish_comp.read_text(encoding="utf-8")
    for token in ("status", "test", "-l errors", "-l summary", "-l diagnose", "-l since-restart", "-l fail-on-error", "-l hide-noise"):
        assert token in fish_txt, f"alis.fish missing completion token {token!r}"


def main() -> int:
    test_logs_parsing_filtering_and_formats()
    test_modern_parsers_and_diagnose()
    test_alis_cli_subcommands()
    test_shell_completions()
    print("PASS test-alis-logs-and-cli (logs parser/filters/diagnose/json/summary, alis status/test/--help, bash/zsh/fish completions)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
