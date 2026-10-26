#!/usr/bin/env python3
"""Validate the *actual* SHA-pinned Companion source, not a hand-authored fixture.

Git fetches a single source commit into a private temp directory; package
lifecycle runs with a synthetic native binary, without affecting user HOME.
This is a networked CI contract, separate from the hermetic fixture tests.
"""
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PIN = (ROOT / "sdata/companion-revision.txt").read_text().strip()
REMOTE = "https://github.com/llocphann/Alis-Companion.git"
assert re.fullmatch(r"[0-9a-f]{40}", PIN), "Companion pin must be an exact source SHA"

spec = importlib.util.spec_from_file_location("managed_companion", ROOT / "scripts/companion-manager.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)
spec = importlib.util.spec_from_file_location("host_companion", ROOT / "scripts/alis-companion-status.py")
host = importlib.util.module_from_spec(spec)
spec.loader.exec_module(host)
assert manager.COMPATIBLE_BINARIES == host.COMPATIBLE_BINARIES

with tempfile.TemporaryDirectory(prefix="alis-external-companion-pin-") as temp:
    root = Path(temp)
    checkout = manager.source_checkout(root, REMOTE, PIN)
    manifest = json.loads((checkout / "manifest.json").read_text())
    assert manifest["binary"] in manager.COMPATIBLE_BINARIES, (
        "Pinned upstream daemon name is not recognized by Alis"
    )
    for field in ("session", "output", "settings"):
        assert (checkout / manifest[field]).is_file(), "Pinned source missing " + field
    assert (checkout / "scripts/install.py").is_file(), "Missing immutable release installer"
    assert (checkout / "scripts/test-package-lifecycle.py").is_file(), "Missing package lifecycle test"
    env = os.environ.copy()
    env["ALIS_COMPANION_SOURCE"] = str(checkout)
    env["ALIS_COMPANION_TEST_HOST"] = str(ROOT)
    env["XDG_DATA_HOME"] = str(root / "owned-data")
    env["XDG_CONFIG_HOME"] = str(root / "owned-config")
    env["XDG_CACHE_HOME"] = str(root / "owned-cache")
    # The pinned upstream source's real installer and fixture native binary
    # prove exact source SHA, atomic publication, preserve-on-failure, and user
    # data integrity without compiling Rust or running any desktop process.
    subprocess.run(
        [sys.executable, str(checkout / "scripts/test-package-lifecycle.py")],
        cwd=checkout, env=env, check=True, timeout=75
    )
    print(f"PASS: pinned Companion {PIN} entrypoint {manifest['binary']}; "
          "actual upstream immutable package lifecycle and host ABI")
