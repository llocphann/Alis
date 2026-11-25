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
    for scoped_target in ("tlp", "thinkfan"):
        p_inst = subprocess.run(["bash", str(ROOT / "setup"), "integrations", "install", scoped_target, "--dry-run"],
                                cwd=ROOT, text=True, capture_output=True, check=True)
        doc_inst = json.loads(p_inst.stdout)
        assert doc_inst["stages"] == ["install-plugin", "helpers-ensure"] and doc_inst["scope"] == scoped_target
        p_rem = subprocess.run(["bash", str(ROOT / "setup"), "integrations", "remove", scoped_target, "--dry-run"],
                               cwd=ROOT, text=True, capture_output=True, check=True)
        doc_rem = json.loads(p_rem.stdout)
        assert doc_rem["stages"] == ["helpers-remove"] and doc_rem["scope"] == scoped_target
    setup_src = (ROOT / "setup").read_text(encoding="utf-8")
    assert 'alis-intergration-manager.py" install-base' in setup_src

    # Verify offline `./setup integrations install tlp` reuses UI-installed plugin payload and proceeds to helpers-ensure.
    interg_src = ROOT.parent / "Alis-Intergration"
    if interg_src.is_dir():
        offline_data = base / "offline-data"
        offline_home = offline_data / "alis-intergration"
        setup.manager.operate("install-base", offline_home, ROOT)
        setup.manager.operate("install-plugin", offline_home, ROOT, plugin_id="tlp", source_dir=interg_src)
        saved_urlopen = setup.manager.urllib.request.urlopen
        saved_sub_run = setup.manager.subprocess.run
        saved_operate = setup.manager.operate
        helper_scopes = []
        try:
            def _offline_net(*_a, **_kw):
                raise OSError("offline network disabled")
            def _offline_sub_run(cmd, *args, **kwargs):
                if isinstance(cmd, (list, tuple)) and any(tok in cmd for tok in ("clone", "fetch", "ls-remote")):
                    raise OSError("offline network disabled")
                return saved_sub_run(cmd, *args, **kwargs)
            def _fake_helper(action, pkg_dir, scope="all"):
                helper_scopes.append((action, scope))
                ready = (action == "helpers-install")
                return {"installed": ready, "provisionerAvailable": True, "diagnostic": ("ready" if ready else "not-installed"),
                        "plugins": {"tlp": {"installed": ready, "managed": ready, "diagnostic": ("ready" if ready else "not-installed")}}}
            def _fake_gw(action):
                return {"installed": True, "packageInstalled": True, "diagnostic": "ready"}
            setup.manager.urllib.request.urlopen = _offline_net
            setup.manager.subprocess.run = _offline_sub_run
            setup.manager.operate = lambda *a, **kw: saved_operate(*a, system_call=_fake_helper, gateway_call=_fake_gw, **kw)
            res_off = setup.execute("install", ROOT, offline_data, base / "offline-state", target="tlp")
            assert res_off["ok"] is True, res_off
            assert ("helpers-status", "tlp") in helper_scopes and ("helpers-install", "tlp") in helper_scopes, helper_scopes
        finally:
            setup.manager.urllib.request.urlopen = saved_urlopen
            setup.manager.subprocess.run = saved_sub_run
            setup.manager.operate = saved_operate
print("INTEGRATION_SETUP_PASS explicit lifecycle, private receipts, denial, reconciliation, no replay, no privileged commands")
