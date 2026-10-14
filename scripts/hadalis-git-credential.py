#!/usr/bin/env python3
"""Git helper: secret output goes directly to Git's credential pipe only."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.manager.credentials import helper

if len(sys.argv) == 4:
    try: sys.stdout.write(helper(sys.argv[1], sys.argv[2], sys.argv[3], sys.stdin.read(8193)))
    except (ValueError, OSError): pass
