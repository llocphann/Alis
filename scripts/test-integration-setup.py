#!/usr/bin/env python3
"""Setup transactions use only injected operations and private receipt stores."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("integration_setup", ROOT / "scripts/integration-setup.py")
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)

with tempfile.TemporaryDirectory(prefix="alis-integration-setup-") as name:
    base = Path(name)
    calls = []
    def good(stage):
        calls.append(stage)
        return {"ok": True, "systemHelpersInstalled": stage == "helpers-ensure"}
    for action, expected in setup.PLANS.items():
        calls.clear()
        report = setup.execute(action, ROOT, base / "data", base / action, call=good)
        assert report["ok"] is True and calls == list(expected)
        receipt = Path(report["receiptPath"])
        assert json.loads(receipt.read_text())["status"] == "passed"
        assert receipt.stat().st_mode & 0o077 == 0
    calls.clear()
    def denied(stage):
        calls.append(stage)
        if stage == "helpers-ensure":
            raise ValueError("Synthetic Polkit denial")
        return {"ok": True}
    report = setup.execute("install", ROOT, base / "data", base / "denied", call=denied)
    assert report["ok"] is False and report["receipt"]["status"] == "uncertain"
    before = Path(report["receiptPath"]).read_bytes()
    calls.clear()
    try:
        setup.execute("install", ROOT, base / "data", base / "denied", call=good)
        raise AssertionError("Uncertain system operation replayed")
    except ValueError:
        pass
    assert not calls and Path(report["receiptPath"]).read_bytes() == before
    observed = setup.execute("status", ROOT, base / "data", base / "denied", call=good)
    assert calls == ["status", "system-status"] and observed["receipt"]["status"] == "uncertain"
    setup.execute("status", ROOT, base / "data", base / "denied", call=good, acknowledge=True)
    setup.execute("reinstall", ROOT, base / "data", base / "denied", call=good)
    archives = list((base / "denied/alis/integrations").glob("*.json"))
    assert len(archives) == 2 and any(json.loads(p.read_text())["status"] == "acknowledged" for p in archives)
    for index, invalid in enumerate((None, [], {"ok": "true"}, {"ok": True})):
        report = setup.execute("install", ROOT, base / "data", base / str(index), call=lambda _: invalid)
        assert report["ok"] is False, invalid
    # Run the real setup dispatcher in preview mode, never the core install.
    preview = subprocess.run(["bash", str(ROOT / "setup"), "integrations", "install", "--dry-run"],
                             cwd=ROOT, text=True, capture_output=True, check=True)
    assert json.loads(preview.stdout)["stages"] == ["install", "helpers-ensure"]
print("INTEGRATION_SETUP_PASS explicit lifecycle, private receipts, denial, reconciliation, no replay, no privileged commands")
