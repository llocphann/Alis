#!/usr/bin/env python3
"""Read-only local cutover checklist. Does not send, restart or dispatch."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.chat_bridge.ui_preflight import check, check_prepared_queue


def main() -> int:
    parser = argparse.ArgumentParser(description="Alis UI scheduler read-only cutover check")
    parser.add_argument("profile_id", nargs="?", help="exact existing Automation profile ID")
    parser.add_argument("--queue", action="store_true",
                        help="read-only readiness for the prepared AUTO-R01 task queue")
    args = parser.parse_args()
    if args.queue:
        if args.profile_id is not None:
            parser.error("--queue does not accept a profile ID")
        report = check_prepared_queue()
        print(json.dumps(report, sort_keys=True))
        return 0
    if args.profile_id is None:
        parser.error("specify a profile ID or --queue")
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
