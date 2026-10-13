#!/usr/bin/env python3
"""BRAND-R01 canonical namespace inventory; read-only, branch-independent.

Default: JSON report. --strict: exit 2 when any active executable identifier
is still named inir. Historical docs, attribution and migration descriptions
are intentionally not used as runtime cutover evidence.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = {
    "environment": re.compile(r"\bINIR_[A-Z0-9_]+\b"),
    "service": re.compile(r"\binir\.service\b"),
    "shell-id": re.compile(r"ShellId\s+inir\b"),
    "native": re.compile(r"\binir-(?:native|mpdd|inputd|theme|protocol)\b|\binir_protocol\b"),
    "polkit": re.compile(r"org\.inir\.|/inir-(?:thinkfan|battery|hadalird)"),
    "launcher": re.compile(r"""(?:^|[\s/])inir(?=[\s"'/]|$)|(?:scripts|bin)/inir\b"""),
    "runtime-path": re.compile(r"(?:quickshell|share|cache|config|state|data)/inir\b"),
    "nix": re.compile(r"programs\.inir\b|nixosModules\.inir\b|homeModules\.inir\b"),
}
EXCLUDED_PREFIXES = (
    "docs/", "to-do/", "CHANGELOG.md", "ARCHITECTURE.md", "CONTRIBUTING.md",
    "scripts/test-", ".github/", "sdata/migrations/", "scripts/brand-",
)
TEXT_EXTENSIONS = {
    ".sh", ".py", ".rs", ".qml", ".js", ".mjs", ".ts", ".kdl", ".nix",
    ".toml", ".lock", ".fish", ".zsh", ".bash", ".service", ".policy",
    ".desktop", ".install", ".xml", ".json", ".yml", ".yaml", ".c", ".h",
    ".md", ".conf",
}
SPECIAL_NAMES = {"Makefile", "setup", "PKGBUILD", ".SRCINFO", "flake.nix", "VERSION"}


def files() -> list[Path]:
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).split(b"\0")
    return [Path(x.decode("utf-8", "replace")) for x in paths if x]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--strict", action="store_true", help="Return 2 when active legacy names remain")
    parser.add_argument("--limit", type=int, default=100, help="Maximum displayed matches per category")
    args = parser.parse_args()
    total_by_kind = {key: 0 for key in PATTERNS}
    examples = {key: [] for key in PATTERNS}
    names = []
    scanned = 0
    for rel in files():
        label = rel.as_posix()
        if label.startswith(EXCLUDED_PREFIXES):
            continue
        if "inir" in label.lower() and not label.startswith("docs/"):
            names.append(label)
        if rel.suffix not in TEXT_EXTENSIONS and rel.name not in SPECIAL_NAMES:
            continue
        try:
            text = (ROOT / rel).read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        scanned += 1
        for kind, regex in PATTERNS.items():
            for match in regex.finditer(text):
                # Citations to historical upstream source code are deliberately
                # retained; they are not executable runtime identifiers.
                line_start = text.rfind("\n", 0, match.start()) + 1
                line_end = text.find("\n", match.end())
                source_line = text[line_start:line_end if line_end >= 0 else None]
                if kind == "launcher" and (
                    "github.com/snowarch/inir" in source_line
                    or "github.com/snowarch/iNiR" in source_line
                ):
                    continue
                total_by_kind[kind] += 1
                if len(examples[kind]) < args.limit:
                    line = text.count("\n", 0, match.start()) + 1
                    examples[kind].append({"path": label, "line": line, "match": match.group()})
    pending = sum(total_by_kind.values()) + len(names)
    result = {
        "scope": "active source only (excludes docs, history, migration and tests)",
        "files_scanned": scanned,
        "remaining_active_references": pending,
        "remaining_legacy_paths": names[: args.limit],
        "remaining_legacy_path_count": len(names),
        "by_kind": total_by_kind,
        "examples": examples,
    }
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if args.strict and pending:
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
