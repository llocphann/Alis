#!/usr/bin/env python3
"""BRAND-R01 canonical namespace inventory; read-only, branch-independent.

Default: JSON report. --strict: exit 2 when any active executable identifier
is still named alis. Historical docs, attribution and migration descriptions
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
    "environment": re.compile(r"\bALIS_[A-Z0-9_]+\b"),
    "service": re.compile(r"\balis\.service\b"),
    "shell-id": re.compile(r"ShellId\s+alis\b"),
    "native": re.compile(r"\balis-(?:native|mpdd|inputd|theme|protocol)\b|\balis_protocol\b"),
    "polkit": re.compile(r"org\.alis\.|/alis-(?:thinkfan|battery|alis-intergration)"),
    "launcher": re.compile(r"""(?:^|[\s/"'])alis(?=[\s"'/]|$)|(?:scripts|bin)/alis\b"""),
    "runtime-path": re.compile(r"(?:quickshell|share|cache|config|state|data)/alis\b"),
    "nix": re.compile(r"programs\.alis\b|nixosModules\.alis\b|homeModules\.alis\b"),
}
EXCLUDED_PREFIXES = (
    "docs/", "to-do/", "CHANGELOG.md", "ARCHITECTURE.md", "CONTRIBUTING.md",
    "scripts/test-", ".github/", "sdata/migrations/", "scripts/brand-",
    "automation/",
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
        if "alis" in label.lower() and not label.startswith("docs/"):
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
                if (kind == "service" and label == "setup"
                        and source_line.strip() == 'local retired_path="${XDG_STATE_HOME:-$HOME/.local/state}/alis-cutover-backups/retired-alis.service"'):
                    # Verified recovery archive is not an executable unit.
                    continue
                if (kind == "launcher" and label in {"nix/home-module.nix", "nix/nixos-module.nix"}
                        and source_line.strip() == 'imports = [ common.optionsModule (lib.mkAliasOptionModule [ "programs" "alis" ] [ "programs" "alis" ]) ];'):
                    # Preserve declarative user configuration compatibility.
                    continue
                if (kind == "launcher" and label == "defaults/config.json"
                        and source_line.strip() == '"alis": 1,'):
                    # Persisted style enum is a configuration compatibility key.
                    continue
                if (kind == "environment" and label == "scripts/alis"
                        and source_line.strip() == '"${ALIS_RUNTIME_DIR:-${ALIS_RUNTIME_DIR:-}}/scripts/lib/brand-env-compat.sh" \\'):
                    # Read-only lookup for the reviewed environment bridge;
                    # executable/runtime ownership still uses canonical names.
                    continue
                if kind == "launcher" and (
                    "github.com/snowarch/alis" in source_line
                    or "github.com/snowarch/Alis" in source_line
                ):
                    continue
                if (
                    kind == "launcher"
                    and label in {
                        "scripts/colors/neovim_themegen.sh",
                        "scripts/colors/modules/30-editors.sh",
                    }
                    and (
                        "yukazakiri/alis.nvim" in source_line
                        or 'require("alis")' in source_line
                        or 'colorscheme = "alis"' in source_line
                        or "auto-generated by Alis" in source_line
                        or "alis-colorscheme.lua" in source_line
                        or "alis_theme.lua" in source_line
                        or "zz-alis-omarchy.lua" in source_line
                    )
                ):
                    # External third-party Neovim plugin identity and legacy header guard.
                    continue
                if (
                    kind == "launcher"
                    and label in {"scripts/companion-manager.py", "scripts/alis-companion-status.py"}
                    and source_line.strip() == '"native/bin/alis-companiond",'
                ):
                    # Source-pinned external Alis-Companion binary compatibility name.
                    continue
                if (
                    kind == "polkit"
                    and label == "translations/en_US.json"
                    and "/usr/libexec/alis-thinkfan is refreshed." in source_line
                ):
                    # Hash-pinned external Polkit helper path in Alis-Intergration.
                    continue
                if (
                    kind == "service"
                    and label in {
                        "distro/arch/alis-shell/alis-shell.install",
                        "distro/arch/alis-shell-git/alis-shell-git.install",
                    }
                    and source_line.strip().startswith(
                        "user home directories. If alis.service is still present,"
                    )
                ):
                    # Owner warning, not executable systemd setup. All actual
                    # service commands in these hooks remain audited.
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
