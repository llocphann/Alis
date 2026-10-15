#!/usr/bin/env python3
"""Read-only preflight never activates Alis UI mode or leaks identifiers."""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge import ui_preflight
from automation.manager import model, store


class Preflight(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        env = patch.dict(os.environ, {
            "XDG_CONFIG_HOME": self.temp.name + "/config",
            "XDG_STATE_HOME": self.temp.name + "/state",
        })
        env.start()
        self.addCleanup(env.stop)
        self.profile = model.default_profile()
        self.profile["enabled"] = True
        self.config = {"version": 1, "profiles": [self.profile]}
        self.state = {"profiles": {self.profile["id"]: store.profile_state()}}
        self.id = self.profile["id"]

    def view(self, **kwargs):
        return ui_preflight.examine(
            self.config, self.state, self.id,
            service_state=kwargs.get("service_state", "inactive"),
            service_mode=kwargs.get("service_mode", "native_mode"),
            journal_pending=kwargs.get("journal_pending", False))

    def test_clean_inactive_service_is_preflight_only(self):
        result = self.view()
        self.assertTrue(result["mode_change_preflight_clear"])
        self.assertFalse(result["submission_authorized"])
        self.assertFalse(result["service_modified"])
        self.assertFalse(result["ui_target_identity_checked"])
        self.assertNotIn(self.id, json.dumps(result))

    def test_active_native_scheduler_blocks_switch(self):
        result = self.view(service_state="active")
        self.assertFalse(result["mode_change_preflight_clear"])
        self.assertIn("NATIVE_SCHEDULER_ACTIVE", result["preflight_blockers"])

    def test_unsure_or_running_ui_also_blocks(self):
        for active, mode in (("active", "ui_mode"), ("unknown", "unknown"),
                             ("activating", "native_mode")):
            self.assertFalse(self.view(service_state=active,
                                       service_mode=mode)["mode_change_preflight_clear"])

    def test_all_unsettled_receipts_and_sessions_block(self):
        self.state["profiles"][self.id]["pending"] = {"user_message_id": "native"}
        self.assertIn("NATIVE_SESSION_REQUIRES_REVIEW", self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["pending"] = None
        self.state["profiles"][self.id]["session"] = {"conversation_id": "hidden"}
        self.assertIn("NATIVE_SESSION_REQUIRES_REVIEW", self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["session"] = None
        self.assertIn("UI_JOURNAL_UNRESOLVED",
                      self.view(journal_pending=True)["preflight_blockers"])
        self.state["profiles"][self.id]["pending"] = {"transport": "alis-ui-once"}
        self.assertIn("ORIGINAL_SEND_UNRESOLVED", self.view()["preflight_blockers"])

    def test_profile_scheduled_or_waiting_blocks_cutover(self):
        self.state["profiles"][self.id]["desired"] = "run"
        self.assertIn("PROFILE_SCHEDULED_REQUIRES_EXPLICIT_STOP",
                      self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["desired"] = "stopped"
        self.state["profiles"][self.id]["job_id"] = "JOB-EXISTING"
        self.assertIn("PROFILE_WAITING_ON_JOB", self.view()["preflight_blockers"])
        self.state["profiles"][self.id]["job_id"] = None
        self.state["profiles"][self.id]["run_active"] = True
        self.assertIn("PROFILE_SCHEDULED_REQUIRES_EXPLICIT_STOP",
                      self.view()["preflight_blockers"])

    def test_foreign_profile_and_unconfigured_block(self):
        self.state["profiles"]["other"] = {"desired": "run"}
        self.assertIn("FOREIGN_PROFILE_UNSETTLED", self.view()["preflight_blockers"])
        self.profile["enabled"] = False
        self.assertIn("PROFILE_NOT_ENABLED", self.view()["preflight_blockers"])

    def test_read_only_on_uninitialized_filesystem(self):
        original_state = store.state_dir()
        original_config = store.config_path()
        before = list(Path(self.temp.name).rglob("*"))
        with patch.object(ui_preflight, "_unit_state", return_value=("inactive", "native_mode")):
            result = ui_preflight.check(self.id)
        after = list(Path(self.temp.name).rglob("*"))
        self.assertFalse(result["profile_enabled"])
        self.assertEqual(before, after)
        self.assertFalse(original_state.exists())
        self.assertFalse(original_config.exists())

    def test_unit_parser_exposes_no_argv_or_credential(self):
        sample = "LoadState=loaded\nActiveState=inactive\nExecStart={ path=/usr/bin/python3 ; argv[]=/usr/bin/python3 -m automation.manager.daemon --ui-loop-profile sensitiveID ; }\n"
        with patch.object(ui_preflight.subprocess, "run",
                          return_value=SimpleNamespace(returncode=0, stdout=sample)):
            self.assertEqual(ui_preflight._unit_state(), ("inactive", "ui_mode"))


if __name__ == "__main__":
    unittest.main()
