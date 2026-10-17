#!/usr/bin/env python3
"""AUTO-R02: new Alis payload excludes retired Automation; old worker is retained."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "sdata/lib/runtime-payload.py"
RETIRED = (
    "automation/worker/daemon.py",
    "automation/manager/daemon.py",
    "automation/chat_bridge/desktop_host.py",
    "scripts/AUTO-F01-service-probe.py",
    "scripts/alis-automation-task.py",
    "scripts/hadalis-automation-control.py",
    "scripts/hadalis-git-credential.py",
    "scripts/inspect-hadalis-native-scope.mjs",
    "scripts/install-hadalis-automation.py",
)
UNRELATED = (
    "modules/settings/CompanionConfig.qml",
    "modules/settings/IntegrationsConfig.qml",
    "modules/settings/ServicesConfig.qml",
    "scripts/alis",
    "assets/systemd/alis.service",
)

def policy():
    spec = importlib.util.spec_from_file_location("alis_runtime_payload", TOOL)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.Payload(ROOT)

class RetiredAutomationRuntimeTest(unittest.TestCase):
    def test_fresh_payload_does_not_ship_retired_backend(self):
        payload = policy()
        self.assertNotIn("automation", payload.dirs)
        contents = set(payload.paths())
        for path in RETIRED:
            with self.subTest(path=path):
                self.assertTrue(payload.excluded(path))
                self.assertNotIn(path, contents)
        for path in UNRELATED:
            with self.subTest(path=path):
                self.assertIn(path, contents)

    def test_old_installed_backend_is_preserved_until_safe_stop(self):
        payload = policy()
        protected = tuple(payload.policy["protectedRetiredPaths"])
        self.assertTrue(protected)
        self.assertTrue(set(protected).issubset(payload.policy["excludedPaths"]))
        fixtures = (*RETIRED, *UNRELATED, "scripts/test-local-private.sh",
                    "modules/settings/AutomationTaskConfig.qml")
        result = subprocess.run(
            [sys.executable, str(TOOL), "filter-installed", "--root", str(ROOT)],
            input="\n".join(fixtures)+"\n", text=True, capture_output=True, check=True
        )
        deleted = set(result.stdout.splitlines())
        for path in RETIRED:
            self.assertNotIn(path, deleted)
        for path in UNRELATED:
            self.assertIn(path, deleted)
        self.assertNotIn("scripts/test-local-private.sh", deleted)
        self.assertIn("modules/settings/AutomationTaskConfig.qml", deleted)

    def test_sync_exclusions_are_exact_and_keep_core_shell(self):
        payload = policy()
        filters = payload.filters()
        for path in payload.policy["protectedRetiredPaths"]:
            self.assertIn("--exclude=/" + path, filters)
        self.assertIn("modules", payload.dirs)
        self.assertIn("services", payload.dirs)
        self.assertIn("scripts", payload.dirs)

if __name__ == "__main__":
    unittest.main(verbosity=2)
