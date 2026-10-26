#!/usr/bin/env python3
"""Write package-managed Alis install metadata as valid JSON."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--installed-at", required=True)
    parser.add_argument("--update-hint", required=True)
    args = parser.parse_args()

    data = {
        "version": args.version,
        "commit": args.commit,
        "installed_at": args.installed_at,
        "installedAt": args.installed_at,
        "source": "make-install",
        "repo_path": "",
        "repoPath": "",
        "install_mode": "package-managed",
        "installMode": "package-managed",
        "update_strategy": "package-manager",
        "updateStrategy": "package-manager",
        "package_manager": "manual",
        "packageManager": "manual",
        "package_name": "source-install",
        "packageName": "source-install",
        "package_update_hint": args.update_hint,
        "packageUpdateHint": args.update_hint,
    }

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
