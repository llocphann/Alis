#!/usr/bin/env python3
"""Noninteractive sudo cache is primed only inside the existing UID broker."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.worker import privilege as p
from automation.manager.store import _write, state_dir


class SudoInput(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.temp.name + "/config",
            "XDG_STATE_HOME": self.temp.name + "/state",
        })
        env.start()
        self.addCleanup(env.stop)
        self.policy_path = (Path(self.temp.name) / "config" /
                            "hadalis" / "automation-privilege.json")
        _write(self.policy_path, {
            "units": ["test.service"], "authentication": "sudo-cache"})

    def test_password_auth_never_hits_argv_or_results(self):
        calls = []
        password = "private-example-password"
        def mock_run(argv, **kwargs):
            calls.append((argv, kwargs))
            self.assertEqual(argv, ["/usr/bin/sudo", "-S", "-p", "", "-v"])
            self.assertEqual(kwargs["input"], password + "\n")
            self.assertNotIn(password, json.dumps(argv))
            self.assertNotIn(password, json.dumps(kwargs["env"]))
            return SimpleNamespace(returncode=0, stdout="", stderr="")
        result = p._privilege_auth(
            {"control": "sudo-authenticate", "password": password},
            runner=mock_run)
        self.assertEqual(result, {"ok": True, "authenticated": True,
                                  "reason": "SUDO_CACHE_READY"})
        self.assertNotIn(password, json.dumps(result))
        # No password or test command was written to taskflow/worker receipt.
        self.assertFalse((state_dir() / "privilege").exists())
        self.assertEqual(len(calls), 1)

    def test_status_does_not_collect_password(self):
        def mock_run(argv, **kwargs):
            self.assertEqual(argv, ["/usr/bin/sudo", "-n", "-v"])
            self.assertIsNone(kwargs["input"])
            return SimpleNamespace(returncode=1, stdout="", stderr="")
        output = p._privilege_auth({"control": "sudo-status"}, runner=mock_run)
        self.assertFalse(output["authenticated"])
        self.assertEqual(output["reason"], "SUDO_AUTHENTICATION_FAILED")

    def test_wrong_mode_missing_allowlist_and_password_rejected(self):
        with patch.object(p, "_broker_control") as call:
            for value in ("", "x" * 1025, "a\nb", "a\x00b"):
                self.assertFalse(p.authenticate(value)["authenticated"])
            call.assert_not_called()
        _write(self.policy_path, {"units": [], "authentication": "sudo-cache"})
        self.assertEqual(p._privilege_auth({
            "control": "sudo-authenticate", "password": "example"},
            runner=lambda *_a, **_k: self.fail("sudo")),
            {"ok": False, "authenticated": False,
             "reason": "ADMINISTRATOR_ALLOWLIST_EMPTY"})
        _write(self.policy_path, {"units": ["test.service"],
                                  "authentication": "polkit"})
        self.assertEqual(p._privilege_auth({
            "control": "sudo-authenticate", "password": "example"},
            runner=lambda *_a, **_k: self.fail("sudo"))["reason"],
            "SUDO_CACHE_MODE_NOT_SELECTED")

    def test_no_unrestricted_root_job_or_password_field(self):
        for bad in ({"operation": "exec", "unit": "test.service", "reason": "unsafe"},
                    {"operation": "system-service-restart",
                     "unit": "test.service", "reason": "Review service failure",
                     "password": "example"}):
            with self.assertRaises(ValueError):
                p.validate(bad)
        qml = (Path(__file__).resolve().parents[1] /
               "modules/settings/AutomationTaskConfig.qml").read_text()
        self.assertIn('objectName: "automationSudoPassword"', qml)
        self.assertIn("echoMode: TextInput.Password", qml)
        self.assertIn('"sudo-credential-save"', qml)
        self.assertIn('"sudo-credential-clear"', qml)
        self.assertIn('"sudo-credential-status"', qml)
        self.assertIn('objectName: "automationClearQueue"', qml)
        self.assertIn('Translation.tr("Find tasks")', qml)
        self.assertIn("root.clearQueueConfirmation = false", qml)
        self.assertIn('"queue-clear", "--approve"', qml)
        self.assertIn('root.pendingSudoPassword = ""', qml)
        self.assertIn('sudoPasswordField.clear()', qml)
        self.assertIn('sudoAuthProcess.stdinEnabled = false', qml)
        self.assertIn('root.sudoCredentialSaved', qml)
        self.assertIn('Translation.tr("Save password")', qml)
        self.assertNotIn("password: sudoPasswordField.text", qml)


if __name__ == "__main__":
    unittest.main()
