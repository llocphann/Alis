#!/usr/bin/env python3
"""Regression coverage for single-instance Niri clipboard-history watchers."""

from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLIPHIST = ROOT / "services/deferred/Cliphist.qml"
DEFAULT_STARTUP = ROOT / "defaults/niri/config.d/50-startup.kdl"
DOTS_NIRI = ROOT / "dots/.config/niri/config.kdl"
MIGRATION_SINGLE = ROOT / "sdata/migrations/051-cliphist-single-watchers.sh"
MIGRATION_NEWLINE = ROOT / "sdata/migrations/054-cliphist-no-synthetic-newline.sh"

TEXT_LINE = 'spawn-at-startup "bash" "-c" "exec wl-paste --no-newline --type text --watch ~/.config/quickshell/alis/scripts/native-dispatch clipboard-store"'
LEGACY_CANONICAL_TEXT_LINE = TEXT_LINE.replace("/quickshell/alis/", "/quickshell/inir/")
LEGACY_TEXT_LINE = 'spawn-at-startup "bash" "-c" "exec wl-paste --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store"'
IMAGE_LINE = 'spawn-at-startup "bash" "-c" "exec wl-paste --type image --watch cliphist store"'
WATCHER_RE = re.compile(
    r'^(?![ \t]*//)[ \t]*(?:spawn-at-startup|spawn-sh-at-startup)\b'
    r'.*\bwl-paste\b.*(?:cliphist[ \t]+store|native-dispatch[ \t]+clipboard-store|clipboard-store\.py).*$'
)


def active_watchers(text: str) -> list[str]:
    return [line.strip() for line in text.splitlines() if WATCHER_RE.match(line)]


def check_source_contract() -> None:
    defaults = DEFAULT_STARTUP.read_text(encoding="utf-8")
    dots = DOTS_NIRI.read_text(encoding="utf-8")
    migration_single = MIGRATION_SINGLE.read_text(encoding="utf-8")
    migration_newline = MIGRATION_NEWLINE.read_text(encoding="utf-8")

    assert active_watchers(defaults) == [TEXT_LINE, IMAGE_LINE], (
        "default Niri startup must own exactly one canonical text watcher and one image watcher"
    )
    assert active_watchers(dots) == [TEXT_LINE, IMAGE_LINE], (
        "legacy dots fallback must not resurrect the untyped clipboard watcher"
    )
    assert 'MIGRATION_ID="051-cliphist-single-watchers"' in migration_single
    assert "monolithic_cfg=" in migration_single and "startup_cfg=" in migration_single
    assert "not all_watchers" in migration_single
    assert "not other_watchers" in migration_single
    assert "exec wl-paste --no-newline --type text" in migration_single
    assert "exec wl-paste --type image" in migration_single
    assert 'MIGRATION_ID="054-cliphist-no-synthetic-newline"' in migration_newline
    assert "MIGRATION_SESSION_IMPACT=true" in migration_newline
    assert "--no-newline" in migration_newline


def run_migration(home: Path, migration: Path, command: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["XDG_CONFIG_HOME"] = str(home / ".config")
    return subprocess.run(
        ["bash", "-c", f'source "{migration}"; {command}'],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )


def check_duplicate_repair() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        niri = home / ".config/niri"
        startup = niri / "config.d/50-startup.kdl"
        root_cfg = niri / "config.kdl"
        startup.parent.mkdir(parents=True)

        startup.write_text(
            "// existing startup\n"
            'spawn-at-startup "bash" "-c" "wl-paste --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store &"\n'
            'spawn-at-startup "bash" "-c" "wl-paste --type text --watch ~/.config/quickshell/inir/scripts/native-dispatch clipboard-store &"\n'
            'spawn-at-startup "bash" "-c" "wl-paste --type image --watch cliphist store &"\n',
            encoding="utf-8",
        )
        root_cfg.write_text(
            'include "config.d/50-startup.kdl"\n'
            'spawn-at-startup "bash" "-c" "wl-paste --watch cliphist store &"\n',
            encoding="utf-8",
        )

        before = run_migration(home, MIGRATION_SINGLE, "migration_check")
        assert before.returncode == 0, before.stderr

        repaired = run_migration(home, MIGRATION_SINGLE, "migration_apply")
        assert repaired.returncode == 0, repaired.stderr

        assert active_watchers(startup.read_text(encoding="utf-8")) == [LEGACY_CANONICAL_TEXT_LINE, IMAGE_LINE]
        assert active_watchers(root_cfg.read_text(encoding="utf-8")) == []

        after = run_migration(home, MIGRATION_SINGLE, "migration_check")
        assert after.returncode == 1, after.stderr


def check_disabled_history_is_respected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        startup = home / ".config/niri/config.d/50-startup.kdl"
        startup.parent.mkdir(parents=True)
        startup.write_text(
            '// spawn-at-startup "bash" "-c" "wl-paste --watch cliphist store &"\n',
            encoding="utf-8",
        )

        status = run_migration(home, MIGRATION_SINGLE, "migration_check")
        assert status.returncode == 1, status.stderr


def check_no_newline_upgrade() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        startup = home / ".config/niri/config.d/50-startup.kdl"
        startup.parent.mkdir(parents=True)
        startup.write_text(
            LEGACY_TEXT_LINE + "\n" + IMAGE_LINE + "\n",
            encoding="utf-8",
        )

        before = run_migration(home, MIGRATION_NEWLINE, "migration_check")
        assert before.returncode == 0, before.stderr

        repaired = run_migration(home, MIGRATION_NEWLINE, "migration_apply")
        assert repaired.returncode == 0, repaired.stderr
        assert active_watchers(startup.read_text(encoding="utf-8")) == [LEGACY_CANONICAL_TEXT_LINE, IMAGE_LINE]

        after = run_migration(home, MIGRATION_NEWLINE, "migration_check")
        assert after.returncode == 1, after.stderr

    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        root_cfg = home / ".config/niri/config.kdl"
        root_cfg.parent.mkdir(parents=True)
        root_cfg.write_text(LEGACY_TEXT_LINE + "\n", encoding="utf-8")

        repaired = run_migration(home, MIGRATION_NEWLINE, "migration_apply")
        assert repaired.returncode == 0, repaired.stderr
        assert active_watchers(root_cfg.read_text(encoding="utf-8")) == [LEGACY_CANONICAL_TEXT_LINE]


def check_no_newline_disabled_history_is_respected() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        home = Path(tmp)
        startup = home / ".config/niri/config.d/50-startup.kdl"
        startup.parent.mkdir(parents=True)
        startup.write_text(
            '// spawn-at-startup "bash" "-c" "wl-paste --type text --watch cliphist store"\n',
            encoding="utf-8",
        )
        status = run_migration(home, MIGRATION_NEWLINE, "migration_check")
        assert status.returncode == 1, status.stderr


def main() -> None:

    cliphist = CLIPHIST.read_text(encoding="utf-8")
    for token in (
        "function filterEntries(): var",
        "root._filterEntriesRevision === root._entriesRevision",
        "function _ensurePreparedEntries(): var",
        "root._preparedEntriesRevision === root._entriesRevision",
        "Fuzzy.go(search, root._ensurePreparedEntries(),",
        "function _entriesEqual(nextEntries): bool",
        "if (!root._entriesEqual(nextEntries))",
    ):
        if token not in cliphist:
            raise AssertionError(f"Cliphist lazy search-index contract missing: {token}")
    check_source_contract()
    check_duplicate_repair()
    check_disabled_history_is_respected()
    check_no_newline_upgrade()
    check_no_newline_disabled_history_is_respected()
    print("clipboard watcher contract: ok")


if __name__ == "__main__":
    main()
