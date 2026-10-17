#!/usr/bin/env python3
"""Guard against live Alis components referencing the retired Automation backend.

This checks tracked text source; historical docs, evidence and the parked
Automation implementation are intentionally excluded until the host is safely
quiesced and the final source-removal stage can delete them.
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
OWNED_SOURCE_PREFIXES = (
    "automation/", "docs/", "to-do/", "agent/", "translations/",
    # Parked, standalone Automation entrypoints remain until host inspection.
    "scripts/alis-automation-task.py",
    "scripts/hadalis-automation-control.py",
    "scripts/install-hadalis-automation.py",
    "scripts/hadalis-git-credential.py",
    "scripts/inspect-hadalis-native-scope.mjs",
    "scripts/automation_test_helpers.py",
    "scripts/AUTO-F01-",
    "scripts/test-AUTO-F01-",
    "scripts/test-hadalis-automation-",
    "scripts/test-hadalis-chat-bridge",
    "scripts/test-hadalis-legacy-ui-",
    "scripts/test-hadalis-native-",
    "scripts/test-hadalis-receipt-",
    "scripts/test-hadalis-reconciliation-",
    "scripts/test-hadalis-static-helper-",
    "scripts/test-hadalis-transport-",
    # The dedicated retirement-route contract intentionally mentions old
    # identifiers as negative assertions; it is not a runtime consumer.
    "scripts/test-retired-settings-routes.py",
)
SKIP_SELF = "scripts/test-retired-runtime-links.py"

# Pin explicit imports/references, not English uses of 'automation' such as
# autostart, music automation, system package release automation, etc.
EXTERNAL_LINKS = re.compile(
    r"(?:from\s+automation(?:\.|\s+import)|"
    r"import\s+automation(?:\.|\s|$)|"
    r"automation/(?:worker|manager|chat_bridge)/|"
    r"modules/settings/AutomationTaskConfig\.qml|"
    r"\bAutomationTaskConfig\b|"
    r"scripts/(?:alis-automation-task|hadalis-automation-control|"
    r"install-hadalis-automation|hadalis-git-credential)\.py|"
    r"hadalis-(?:worker|chat-bridge|privilege)\.service)"
)


class RetiredRuntimeLinkTest(unittest.TestCase):
    def test_no_live_cross_component_link(self):
        result = subprocess.run(
            ["git", "ls-files", "-z"], cwd=ROOT, capture_output=True,
            check=True
        )
        matches = []
        scanned = 0
        for raw in result.stdout.split(b"\0"):
            if not raw:
                continue
            path = raw.decode("utf-8")
            if path == SKIP_SELF or path.startswith(OWNED_SOURCE_PREFIXES):
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
