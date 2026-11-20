#!/usr/bin/env python3
"""Keep GitHub Issues as the only active task tracker (no network needed)."""

from pathlib import Path
import re
import json

ROOT = Path(__file__).resolve().parents[1]
ISSUES = "github.com/llocphann/Alis/issues"

# Retired Markdown task ledgers must remain absent; if any file appears under
# to-do/, verify it cannot carry active task checklists.
todo_dir = ROOT / "to-do"
assert not todo_dir.exists(), "Retired to-do/ ledger directory must not be reintroduced"

agent = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
for required in ("search", "Issues", "Awaiting Owner verification",
                 "close as completed", "Markdown"):
    assert required.lower() in agent.lower(), f"AGENTS.md missing {required}"

assert all(x in agent for x in ("`bug`", "`enhancement`", "`documentation`",
                               "complexity:high", "area:*", "status:awaiting-owner"))

palette = json.loads((ROOT / ".github/issue-label-palette.json").read_text(encoding="utf-8"))
assert {"complexity:high", "area:abyss", "area:performance",
        "status:blocked", "status:deferred", "status:awaiting-owner"} <= palette.keys()
for name, label in palette.items():
    assert name.startswith(("area:", "status:", "complexity:")), name
    assert re.fullmatch(r"[0-9a-fA-F]{6}", label["color"]), name

for name, expected_type in (
    (".github/ISSUE_TEMPLATE/bug_report.yml", "bug"),
    (".github/ISSUE_TEMPLATE/feature_request.yml", "enhancement"),
    (".github/ISSUE_TEMPLATE/rework_request.yml", "enhancement"),
):
    form = (ROOT / name).read_text(encoding="utf-8")
    assert ISSUES in form, f"{name}: duplicate-check link missing"
    assert f'labels: ["{expected_type}"]' in form, f"{name}: wrong type label"
    assert form.count("required: true") <= 2, f"{name}: issue intake too verbose"

print("ALIS_ISSUE_WORKFLOW_PASS (no retired to-do/, built-in labels, 3 forms, colored palette)")
