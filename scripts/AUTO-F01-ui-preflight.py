#!/usr/bin/env python3
"""Read-only local cutover checklist. Does not send, restart or dispatch."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge.ui_preflight import check


def main() -> int:
    parser = argparse.ArgumentParser(description="Alis UI scheduler read-only cutover check")
    parser.add_argument("profile_id", help="exact existing Automation profile ID")
    args = parser.parse_args()
    try:
        report = check(args.profile_id)
    except ValueError:
        report = {
            "purpose": "auto-f01-ui-cutover-preflight",
            "status": "read-only",
            "mode_change_preflight_clear": False,
            "preflight_blockers": ["INVALID_PROFILE_ID"],
            "ui_target_identity_checked": False,
            "submission_authorized": False,
            "service_modified": False,
        }
    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
