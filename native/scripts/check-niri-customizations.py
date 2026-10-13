#!/usr/bin/env python3
"""Compare read-only Niri customization reports in an isolated config home."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RUST = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "native/target/release/alis-native"


def report(command, home):
    env = os.environ.copy()
    env["XDG_CONFIG_HOME"] = str(home)
    result = subprocess.run(command, cwd=ROOT, env=env, text=True, capture_output=True, check=True)
    return json.loads(result.stdout)


def compare(label, home):
    python = report([sys.executable, str(ROOT / "scripts/niri-config.py"), "detect-customizations"], home)
    rust = report([str(RUST), "niri", "detect-customizations"], home)
    if python != rust:
        for left, right in zip(python["files"], rust["files"]):
            if left != right:
                raise AssertionError(f"{label}: {left['path']}: Python {left!r}; Rust {right!r}")
        raise AssertionError(f"{label}: Python {python!r}; Rust {rust!r}")
    print(f"PASS {label}: {len(python['files'])} customization(s)")


def main():
    if not RUST.is_file():
        raise SystemExit(f"Rust binary missing: {RUST}")
    with tempfile.TemporaryDirectory(prefix="alis-niri-parity-") as temporary:
        home = Path(temporary)
        compare("missing config", home)
        config = home / "niri"
        shutil.copytree(ROOT / "defaults/niri", config)
        compare("shipped defaults", home)

        environment = config / "config.d/40-environment.kdl"
        environment.write_text(
            'environment {\n    XMODIFIERS "@im=fcitx"\n'
            '    QT_IM_MODULE "fcitx"\n    XMODIFIERS "@im=fcitx"\n}\n'
        )
        (config / "config.d/15-outputs.kdl").write_text('output "TEST" { scale 1 }\n')
        (config / "config.d/90-user-extra.kdl").write_text("window-rule {\n    opacity 0.9\n}\n")
        compare("reordered, repeated and extra lines", home)

        environment.write_text("environment {\n" + "    XMODIFIERS \"@im=fcitx\"\n" * 220 + "}\n")
        compare("long repeated override", home)


if __name__ == "__main__":
    main()
