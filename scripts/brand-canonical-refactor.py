#!/usr/bin/env python3
"""Canonicalize active Alis sources in an isolated Git worktree.

This is a source migration utility, NOT a user-data or service migrator.
Historical migrations, tests, third-party attribution and archived docs must
stay intact. Run only on the brand-r01-canonical-alis feature branch.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
BRANCH = "brand-r01-canonical-alis"
SOURCE_PREFIXES = (
    "modules/", "services/", "sdata/lib/", "sdata/subcmd-install/",
    "sdata/dist-arch/", "sdata/dist-fedora/", "sdata/dist-debian/",
    "sdata/dist-generic/", "defaults/niri/", "defaults/matugen/",
    "dots/.config/", "dots/sddm/", "scripts/", "assets/", "translations/",
    "defaults/widgets/", "sdata/uv/",
    "distro/arch/", "native/", "nix/",
)
ROOT_FILES = {
    "setup", "Makefile", "flake.nix", "shell.qml", "settings.qml",
    "welcome.qml", "GlobalStates.qml", "waffleSettings.qml",
    "killDialog.qml", "README.md", "SECURITY.md", "STRUCTURE.md",
    "CODE_OF_CONDUCT.md", "go.mod",
}
EXCLUDED_PREFIXES = (
    "scripts/test-", "scripts/brand-", "scripts/iris-corner-poc/",
    "sdata/migrations/", "native/target/", "docs/", "native/tests/",
    "defaults/plugins/", "assets/icons/fluent/",
)
BINARY_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".webp", ".gif", ".woff", ".ttf", ".otf",
    ".qsb", ".ico", ".mp3", ".wav", ".bin", ".dat", ".zip", ".svg",
    ".lockb",
}
SOURCE_HOLD = {
    "snowarch/iNiR": "@@UPSTREAM_SOURCE_I@@",
    "snowarch/inir": "@@UPSTREAM_SOURCE_L@@",
    "iNiR-Walls": "@@UPSTREAM_WALLPACK@@",
    "INIR-Walls": "@@UPSTREAM_WALLPACK2@@",
}
DIRS_TO_RENAME = (
    "distro/arch/inir-", "sdata/dist-arch/inir-",
    "scripts/completions/inir.", "assets/helpers/inir-",
    "assets/polkit/org.inir.", "defaults/niri/config.d/75-inir-",
    "dots/.config/vesktop/themes/inir-",
)


def included(path: str) -> bool:
    return (
        (path in ROOT_FILES or path.startswith(SOURCE_PREFIXES))
        and not path.startswith(EXCLUDED_PREFIXES)
    )


def rename_text(text: str) -> str:
    for old, temporary in SOURCE_HOLD.items():
        text = text.replace(old, temporary)
    text = (text.replace("INIR", "ALIS")
                .replace("Inir", "Alis")
                .replace("inir", "alis")
                .replace("iNiR", "Alis"))
    for old, temporary in SOURCE_HOLD.items():
        text = text.replace(temporary, old)
    return text


def rename_path(path: str) -> str:
    if any(path.startswith(prefix) for prefix in DIRS_TO_RENAME):
        return path.replace("INIR", "ALIS").replace("inir", "alis")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="Update the Git worktree; default is a dry run")
    args = parser.parse_args()
    branch = subprocess.check_output(
        ["git", "branch", "--show-current"], cwd=ROOT, text=True
    ).strip()
    if branch != BRANCH:
        print(f"Refusing branch {branch!r}; expected {BRANCH}", file=sys.stderr)
        return 2
    tracked = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT)
    items = [x.decode("utf-8") for x in tracked.split(b"\0") if x]
    changes: list[tuple[Path, Path, str]] = []
    renames: list[tuple[Path, Path]] = []
    for relative in items:
        if not included(relative):
            continue
        old_path = ROOT / relative
        if not old_path.is_file() or old_path.is_symlink():
            continue
        new_path = ROOT / rename_path(relative)
        if old_path.suffix in BINARY_EXTENSIONS:
            if new_path != old_path:
                renames.append((old_path, new_path))
            continue
        try:
            text = old_path.read_text("utf-8")
        except (UnicodeError, OSError):
            continue
        target_text = rename_text(text)
        if relative == "CODE_OF_CONDUCT.md":
            target_text = target_text.replace(
                "https://github.com/snowarch/inir/issues",
                "https://github.com/llocphann/Alis/issues",
            )
        if text != target_text or new_path != old_path:
            changes.append((old_path, new_path, target_text))
    collisions = [
        str(new) for old, new, _ in changes if old != new and new.exists()
    ]
    collisions += [
        str(new) for old, new in renames if old != new and new.exists()
    ]
    # Old public completion sources already have managed Alis equivalents.
    completions = [(o,n,s) for o,n,s in changes
                   if "/scripts/completions/inir." in str(o)
                   and n.exists()]
    if completions:
        for o,n,s in completions:
            changes.remove((o,n,s))
            # Drop obsolete completion source, never overwrite the new one.
            renames.append((o, o))
        collisions = [
            c for c in collisions
            if "/scripts/completions/alis." not in c
        ]
    if collisions:
        for collision in collisions:
            print("COLLISION: " + collision, file=sys.stderr)
        return 2
    print(f"Canonical source changes: {len(changes)}, obsolete/renamed assets: {len(renames)}")
    if not args.apply:
        for old, new, _ in changes:
            print(f"EDIT {old.relative_to(ROOT)} -> {new.relative_to(ROOT)}")
        return 0
    for old, new, text in changes:
        new.parent.mkdir(parents=True, exist_ok=True)
        new.write_text(text, encoding="utf-8")
        new.chmod(old.stat().st_mode & 0o777)
        if old != new:
            old.unlink()
    for old, new in renames:
        if old == new:
            old.unlink()
        else:
            new.parent.mkdir(parents=True, exist_ok=True)
            old.rename(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
