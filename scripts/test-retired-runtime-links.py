#!/usr/bin/env python3
"""Guard against live Alis components referencing the retired Automation backend.

Historical receipts remain data. Neither their presence nor private retained
journals may bring back executable Automation code or a live caller.
"""

from pathlib import Path
import re
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {
    ".qml", ".js", ".mjs", ".cjs", ".py", ".sh", ".fish", ".kdl",
    ".yml", ".yaml", ".nix", ".toml", ".service", ".desktop", ".json",
}
TEXT_BASENAMES = {"qmldir", "setup", "Makefile", "PKGBUILD", "alis",
                  "native-backend", "native-dispatch"}
HISTORICAL_PREFIXES = ("docs/", "to-do/", "agent/")
RETAINED_RECEIPTS = {
    "automation/queue/pending/JOB-AUDIO-I01-BASELINE-20261015-01.json",
    "automation/results/JOB-AUTO-F01-SMOKE-20261015-01.json",
    "automation/results/JOB-C2F353CC-AQUARENDER-R57-20261006.json",
    "automation/results/JOB-C2F353CC-AQUAUNIFORMS-R56-20261006.json",
}
RETIREMENT_FILES = {
    "scripts/test-retired-settings-routes.py",
    "scripts/audit-retired-services.py",
    "sdata/runtime-exclusions.json",
    "scripts/test-retired-runtime-payload.py",
    "scripts/test-retired-runtime-links.py",
    "scripts/test-retired-service-audit.py",
}
RETIRED_SCRIPT = re.compile(
    r"^scripts/(?:AUTO-F01-|alis-automation-task\.|hadalis-automation-control\.|"
    r"install-hadalis-automation\.|hadalis-git-credential\.|"
    r"inspect-hadalis-native-scope\.|automation_test_helpers\.|"
    r"test-(?:AUTO-F01-|automation-|hadalis-(?:automation-|chat-bridge|"
    r"legacy-ui-|native-|receipt-|reconciliation-|static-helper-|transport-)))"
)

# Pin explicit imports/references, not English uses of 'automation' such as
# autostart, music automation, system package release automation, etc.
EXTERNAL_LINKS = re.compile(
    r"(?:from\s+automation(?:\.|\s+import)|"
    r"import\s+automation(?:\.|\s|$)|"
    r"\bautomation\.(?:worker|manager|chat_bridge)\b|"
    r"automation/(?:worker|manager|chat_bridge)/|"
    r"modules/settings/AutomationTaskConfig\.qml|"
    r"\bAutomationTaskConfig\b|"
    r"scripts/(?:alis-automation-task|hadalis-automation-control|"
    r"install-hadalis-automation|hadalis-git-credential)\.py|"
    r"scripts/inspect-hadalis-native-scope\.mjs|"
    r"hadalis-(?:worker|chat-bridge|privilege|chatgpt)\.service)"
)


def tracked_paths():
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True, check=True
    )
    return [p.decode("utf-8") for p in result.stdout.split(b"\0") if p]


class RetiredRuntimeLinkTest(unittest.TestCase):
    def test_only_historical_receipts_remain_in_backend_directory(self):
        paths = {p for p in tracked_paths() if p.startswith("automation/")}
        self.assertEqual(paths, RETAINED_RECEIPTS)
        for path in paths:
            self.assertTrue((ROOT / path).is_file(), path)

    def test_retired_entrypoints_and_dedicated_tests_cannot_return(self):
        self.assertEqual([p for p in tracked_paths() if RETIRED_SCRIPT.match(p)], [])

    def test_no_live_cross_component_link(self):
        matches = []
        scanned = 0
        for path in tracked_paths():
            if (path in RETIREMENT_FILES or path in RETAINED_RECEIPTS
                    or path.startswith(HISTORICAL_PREFIXES)):
                continue
            source = ROOT / path
            if not source.is_file():
                continue
            if source.suffix not in TEXT_SUFFIXES and source.name not in TEXT_BASENAMES:
                continue
            scanned += 1
            content = source.read_text(encoding="utf-8", errors="replace")
            for number, line in enumerate(content.splitlines(), 1):
                if EXTERNAL_LINKS.search(line):
                    matches.append(f"{path}:{number}")
        self.assertEqual(matches, [], "Retired runtime references: " + ", ".join(matches))
        self.assertGreater(scanned, 100, "source scan unexpectedly empty")


if __name__ == "__main__":
    unittest.main(verbosity=2)
