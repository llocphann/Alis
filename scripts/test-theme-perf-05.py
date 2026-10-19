#!/usr/bin/env python3
"""Smoke test the one-shot diagnostic suite against a fake Rust generator.

No desktop services, real user files, or installed Alis instances are touched.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "scripts/collect-auto-theme-diagnostics.py"
WRAPPER = ROOT / "scripts/collect-auto-theme-diagnostics.sh"
SRC = RUNNER.read_text()

assert "ALIS_THEME_SKIP_SDDM_SYNC" in SRC
assert "TemporaryDirectory(prefix=" in SRC
assert "image.stat().st_size" in SRC
assert "def test_reuse_parity(" in SRC
assert "def image_size_matrix(" in SRC
assert "def template_benchmark(" in SRC
assert "def runtime_log_summary(" in SRC
assert "test_runner(binary, image" in SRC
assert "exec python3" in WRAPPER.read_text()

with tempfile.TemporaryDirectory(prefix="alis-theme-diag-test-") as folder:
    tmp = Path(folder)
    fake = tmp / "alis-theme"
    fake.write_text(
        "#!/usr/bin/env python3\n"
        "import json,os,pathlib,sys\n"
        "args=sys.argv[1:]\n"
        "def val(key,default=''):\n"
        "  return args[args.index(key)+1] if key in args else default\n"
        "mode=val('--mode','dark')\n"
        "size=int(val('--size','128'))\n"
        "seed=val('--color','#345678') if '--color' in args else "
        "('#345678' if size>=128 else '#345679')\n"
        "scheme=val('--scheme','auto')\n"
        "scheme='scheme-tonal-spot' if scheme=='auto' else scheme\n"
        "for i,arg in enumerate(args[:-1]):\n"
        "  if arg.endswith('-output'):\n"
        "    p=pathlib.Path(args[i+1]);p.parent.mkdir(parents=True,exist_ok=True)\n"
        "    if arg=='--meta-output':\n"
        "      data={'source':'image' if '--path' in args else 'color',"
        "'source_path':val('--path') or None,'seed_color':seed,'scheme':scheme}\n"
        "    else:data={'background':'#345678','primary':seed,'mode':mode,"
        "'scheme':scheme,'invert':'--invert-hue' in args,"
        "'soften':'--soften' in args,'strength':val('--color-strength','1.0')}\n"
        "    p.write_text('/*mock*/' if arg=='--scss-output' else json.dumps(data))\n"
        "print('[THEME-PERF-04] scope=rust stage=image_decode ms=1.000',file=sys.stderr)\n"
        "print('[THEME-PERF-04] scope=rust stage=image_resize ms=2.000',file=sys.stderr)\n"
        "print('[THEME-PERF-04] scope=rust stage=scheme_auto ms=3.000',file=sys.stderr)\n"
        "print('[THEME-PERF-04] scope=rust stage=seed_quantize_score ms=4.000',file=sys.stderr)\n"
        "print('[THEME-PERF-04] scope=rust stage=seed_extract ms=10.000',file=sys.stderr)\n"
        "print('[THEME-PERF-04] scope=rust stage=total ms=12.000',file=sys.stderr)\n"
    )
    fake.chmod(0o755)
    image = tmp / "synthetic-wallpaper.png"
    image.write_bytes(b"synthetic image; fake binary does not decode")
    logs = tmp / "readonly.log"
    logs.write_text(
        "[THEME-PERF-04] scope=qml stage=qml_palette_apply ms=5 epoch_ms=1\n"
        "Unrelated sensitive path: /home/user/private/secret\n"
    )
    report = tmp / "result.json"
    env = os.environ.copy()
    env["XDG_CONFIG_HOME"] = str(tmp / "xdg/config")
    env["XDG_STATE_HOME"] = str(tmp / "xdg/state")
    command = [
        sys.executable, str(RUNNER), "--image", str(image),
        "--binary", str(fake), "--out", str(report),
        "--runtime-log", str(logs), "--no-parity",
        "--runs", "2", "--warmup", "0", "--matrix-runs", "1",
    ]
    result = subprocess.run(command, cwd=ROOT, env=env, text=True,
                            capture_output=True, timeout=120)
    # Nonzero exit 1 is intentional when a pre-existing regression reports
    # FAIL. The collector must preserve that status while still creating the
    # complete report. Only missing reports or unexpected exit codes are bugs
    # in this offline orchestration smoke test.
    if result.returncode not in (0, 1) or not report.is_file():
        raise AssertionError(
            f"Collector failed to create a report (rc={result.returncode}):\n"
            f"{result.stdout[-900:]}\n{result.stderr[-900:]}"
        )
    data = json.loads(report.read_text())
    failed_regressions = [
        name for name, value in data["tests"].items()
        if value.get("status") == "FAIL"
    ]
    assert (result.returncode == 1) == bool(failed_regressions), (
        "Collector exit status must match the presence of failed regressions"
    )
    assert data["schema"] == "THEME-PERF-05-v1"
    assert data["source"]["available"] is True
    assert data["benchmarks"]["baseline"]["status"] == "PASS"
    assert data["benchmarks"]["baseline"]["wall"]["count"] == 2
    assert data["benchmarks"]["size_matrix"]["128"]["status"] == "PASS"
    assert data["benchmarks"]["template_matrix"]["8"]["status"] == "PASS"
    assert "production_seed_cache" in data["benchmarks"]
    assert "seed_cache_integration" in data["tests"]
    assert all(row["status"] == "PASS" for row in
               data["benchmarks"]["seed_reuse_parity"].values())
    assert data["runtime_log"]["stages"]["qml.qml_palette_apply"]["median_ms"] == 5
    payload = report.read_text()
    assert str(image) not in payload
    assert "private/secret" not in payload
    assert "synthetic-wallpaper.png" not in payload

print("THEME_PERF_05_PASS one-shot mock matrix, parity, trace collection and report privacy")
