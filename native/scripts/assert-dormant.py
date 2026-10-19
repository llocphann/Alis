#!/usr/bin/env python3
"""Guard the production Rust selector boundary.

Runtime call sites must route through scripts/native-dispatch rather than invoke
Rust helpers directly. Build and packaging recipes are allowed to name/copy the
compiled binaries because they are responsible for shipping native/bin.
"""

from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]

NATIVE_BINARY_MARKERS = (
    "alis-inputd",
    "alis-native",
    "alis-mpdd",
    "alis-theme",
    "alis-mega",
)

RUNTIME_ROOTS = (
    ROOT / "services",
    ROOT / "modules",
    ROOT / "defaults",
    ROOT / "assets" / "systemd",
)

RUNTIME_FILES = (
    ROOT / "shell.qml",
    ROOT / "settings.qml",
    ROOT / "setup",
    ROOT / "Makefile",
)

# The launcher lifecycle code must name native processes so it can identify and
# clean orphaned trial helpers after a KillMode=process shell restart. It is
# separately covered by test-native-selector-contract.sh; it is not a runtime
# call site for those binaries.
LIFECYCLE_REFERENCE_FILES = {
    ROOT / "scripts" / "alis",
}

TEXT_SUFFIXES = {
    ".qml",
    ".service",
    ".socket",
    ".timer",
    ".kdl",
    ".sh",
    ".py",
    ".nix",
    ".toml",
    ".json",
    ".md",
    ".install",
}


def iter_runtime_files():
    for path in RUNTIME_FILES:
        if path.is_file():
            yield path
    for root in RUNTIME_ROOTS:
        if not root.exists():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix in TEXT_SUFFIXES or path.name in {"PKGBUILD", "Makefile"}:
                yield path


def main() -> int:
    violations: list[str] = []
    for path in iter_runtime_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            for marker in NATIVE_BINARY_MARKERS:
                if marker not in line:
                    continue

                # The selector can expose binary readiness as metadata (for
                # example `alis-mpdd=ready`). That is not a direct runtime
                # binding. Reject executable/path contexts instead of any
                # harmless mention of a binary name.
                # Match a complete binary basename. Profiling/state paths
                # like "/alis-theme-perf08" are *not* an alis-theme
                # executable and must not fail the production boundary.
                direct_path = re.search(
                    rf"/{re.escape(marker)}(?![A-Za-z0-9_.-])", line
                ) is not None
                direct_command = any(
                    token in line
                    for token in (
                        "ExecStart=",
                        "command:",
                        "execDetached(",
                        "exec ",
                        "command ",
                        "install ",
                        "cp ",
                        "ln ",
                    )
                )
                if direct_path or direct_command:
                    violations.append(
                        f"{path.relative_to(ROOT)}:{line_number} binds directly to {marker}"
                    )

    if violations:
        print("Native production-boundary guard failed:")
        for violation in violations:
            print(f"  - {violation}")
        print(
            "Runtime call sites must use scripts/native-dispatch rather than "
            "binding directly to Rust binaries."
        )
        return 1

    print("Native production-boundary guard: PASS (runtime call sites do not bind directly to Rust binaries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
