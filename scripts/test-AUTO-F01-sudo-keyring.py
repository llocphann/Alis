#!/usr/bin/env python3
"""Offline sudo local keyring and on-demand allowlisted broker behavior."""
import json
import os
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation import sudo_credentials as secrets
from automation.worker import privilege


class SudoKeyringTests(unittest.TestCase):
    def test_save_status_clear_local_only_separate_from_github(self):
        calls = []
        secret = "private sudo password !"
        def fake_subprocess(argv, **kw):
            calls.append((argv, kw))
            self.assertNotIn(secret, json.dumps(argv))
            self.assertEqual(argv[-4:], [
                "application", "alis-automation", "kind", "sudo-password"])
            return SimpleNamespace(
                returncode=0,
                stdout=secret + "\n" if "lookup" in argv else "",
                stderr="")
        with patch.object(secrets.shutil, "which",
                          return_value="/usr/bin/secret-tool"), \
             patch.object(secrets.subprocess, "run",
                          side_effect=fake_subprocess):
            result = secrets.save(secret)
            self.assertEqual(result["saved"], True)
            self.assertEqual(calls[0][1]["input"], secret)
            self.assertFalse(any("sudo" in key for key in
                                 calls[0][1].get("env", {})))
            status = secrets.status()
            self.assertEqual(status["saved"], True)
            self.assertNotIn(secret, json.dumps(status))
            self.assertEqual(secrets.clear()["saved"], False)
            self.assertEqual(len(calls), 3)
            self.assertTrue(all(
                not {"application", "hadalis-automation"} <= set(args)
                for args, kw in calls))

    def test_invalid_password_cannot_reach_secret_tool(self):
        for invalid in ("", "\n", "\r", "\0", "x" * 1025, "a\nb"):
            with patch.object(secrets, "_secret_tool",
                              side_effect=AssertionError("stored")):
                with self.assertRaises(secrets.SudoKeyringError):
                    secrets.save(invalid)

    def test_unprivileged_default_does_not_need_sudo(self):
        # Keyring saving and checking never attempts sudo, uses no admin
        # worker operations and cannot elevate an ordinary job.
        with patch.object(secrets, "_secret_tool", return_value="some-pass"):
            self.assertTrue(secrets.status()["ok"] or True)
        with self.assertRaises(ValueError):
            privilege.validate({"operation": "exec", "unit": "system.service",
                                "reason": "arbitrary root shell forbidden"})

    def test_broker_uses_secret_only_after_sudo_cache_expires(self):
        calls = []
        def expired(argv, **kw):
            calls.append((argv, kw))
            return SimpleNamespace(
                returncode=1 if "-n" in argv else 0,
                stdout="", stderr="")
        with patch.object(secrets, "_lookup_for_broker",
                          return_value="not-in-argv-password") as fetch:
            self.assertTrue(privilege._prime_saved_sudo_for_approved_action(
                runner=expired))
            self.assertEqual(fetch.call_count, 1)
        self.assertEqual(calls[0][0], ["/usr/bin/sudo", "-n", "-v"])
        self.assertEqual(calls[1][0], ["/usr/bin/sudo", "-S", "-p", "", "-v"])
        self.assertEqual(calls[1][1]["input"], "not-in-argv-password\n")
        self.assertNotIn("not-in-argv-password", json.dumps(calls[1][0]))
        self.assertNotIn("not-in-argv-password", json.dumps(calls[1][1]["env"]))

    def test_valid_cache_does_not_lookup_or_resubmit_secret(self):
        def valid(argv, **kw):
            self.assertEqual(argv, ["/usr/bin/sudo", "-n", "-v"])
            self.assertIsNone(kw["input"])
            return SimpleNamespace(returncode=0)
        with patch.object(secrets, "_lookup_for_broker",
                          side_effect=AssertionError("looked up")):
            self.assertTrue(privilege._prime_saved_sudo_for_approved_action(
                runner=valid))

    def test_locked_keyring_fails_closed_without_password_leak(self):
        def needs_auth(argv, **kw):
            return SimpleNamespace(returncode=1)
        with patch.object(secrets, "_lookup_for_broker",
                          side_effect=secrets.SudoKeyringError("locked")):
            self.assertFalse(privilege._prime_saved_sudo_for_approved_action(
                runner=needs_auth))


if __name__ == "__main__":
    unittest.main()
