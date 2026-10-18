#!/usr/bin/env python3
"""Retirement audit fixtures; no real systemd, keyring, worker or chat calls."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("retirement_audit", ROOT / "scripts/audit-retired-services.py")
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class RetiredServiceAuditTest(unittest.TestCase):
    def test_running_components_are_identified_without_importing_them(self):
        for argv in (
            ["python3", "/repo/automation/worker/daemon.py"],
            ["/usr/bin/python3", "-u", "-m", "automation.manager.daemon", "--ui-loop-queue"],
            ["python3", "-m", "automation.worker.privilege"],
            ["python3", "-m", "automation.chat_bridge.desktop_host"],
            ["node", "/repo/automation/chat_bridge/native_cli.mjs"],
        ):
            with self.subTest(argv=argv):
                self.assertIsNotNone(audit.process_component(argv))

    def test_searches_and_inline_diagnostics_are_not_workers(self):
        for argv in (
            ["rg", "automation/worker/daemon.py"],
            ["python3", "-c", "print('automation.manager.daemon')"],
            ["node", "--eval", "const s='automation/worker/daemon.py'"],
            ["python3", "scripts/audit-retired-services.py"],
            ["python3", "-m", "unrelated.automation.manager.daemon"],
        ):
            with self.subTest(argv=argv):
                self.assertIsNone(audit.process_component(argv))

    def test_inert_pending_history_does_not_claim_an_installed_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            state = root / "hadalis-automation"
            state.mkdir()
            original = json.dumps({"profiles": {"uncertain": {
                "desired": "stopped", "pending": {"attempt": "keep"},
                "request": {"private": "DO_NOT_OUTPUT"},
            }}}).encode()
            (state / "manager.json").write_bytes(original)
            empty_unit = {"loaded": "not-found", "active": "inactive",
                          "fragment_path": "", "main_pid": "0", "enabled": ""}
            desktop = {"suspected_automation_generated_exec": False}
            stdout = io.StringIO()
            with patch.dict(os.environ, {"XDG_STATE_HOME": str(root), "XDG_CONFIG_HOME": str(root)}), \
                    patch.object(audit, "unit_snapshot", return_value=empty_unit), \
                    patch.object(audit, "process_snapshot", return_value=[]), \
                    patch.object(audit, "desktop_launcher_snapshot", return_value=desktop), \
                    patch.object(audit.subprocess, "run", side_effect=AssertionError("No service action")), \
                    contextlib.redirect_stdout(stdout):
                exit_code = audit.main()
            report = json.loads(stdout.getvalue())
            self.assertEqual(exit_code, 2)  # Retention review remains unresolved.
            self.assertTrue(report["automation_units_and_processes_absent"])
            self.assertTrue(report["retained_manager_history_requires_owner_review"])
            self.assertFalse(report["safe_to_delete_state"])
            self.assertNotIn("DO_NOT_OUTPUT", stdout.getvalue())
            self.assertEqual((state / "manager.json").read_bytes(), original)
            self.assertEqual(sorted(p.name for p in state.iterdir()), ["manager.json"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
