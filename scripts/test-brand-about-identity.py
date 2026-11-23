#!/usr/bin/env python3
"""Verify Alis About identity and canonical service registration."""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
about = (root / "modules/settings/AboutConfig.qml").read_text()
assert 'text: "Alis"' in about
assert 'title: Translation.tr("Alis Desktop Shell")' in about
assert 'title: Translation.tr("Optional Integrations")' in about
assert 'Translation.tr("Connected Quickshell desktop environment with Abyss & Waffle families")' in about
assert "QuickShell" not in about  # keeps canonical naming consistent

shell = (root / "shell.qml").read_text()
assert "//@ pragma ShellId alis" in shell, "Canonical ShellId must remain alis"
assert (root / "assets/systemd/alis.service").is_file(), "Canonical user unit missing"
print("PASS: Alis About identity, ShellId, and systemd service contract")
