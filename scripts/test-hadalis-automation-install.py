#!/usr/bin/env python3
"""Boot ordering and ordinary Desktop launches share the Automation endpoint."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("automation_installer", ROOT / "scripts/install-hadalis-automation.py")
assert spec and spec.loader
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        vendor = base / "vendor/applications/chatgpt.desktop"
        vendor.parent.mkdir(parents=True)
        original = ("[Desktop Entry]\nName=ChatGPT\nIcon=custom-icon\nExec=chatgpt %U\n"
                    "MimeType=x-scheme-handler/codex;\n[Desktop Action Help]\nExec=help-viewer\n")
        vendor.write_text(original)
        data_home = base / "user-data"
        with patch.dict(os.environ, {"XDG_DATA_HOME": str(data_home),
                                     "XDG_STATE_HOME": str(base/"state"),
                                     "XDG_CONFIG_HOME": str(base/".config"),
                                     "XDG_DATA_DIRS": str(base / "vendor")}), \
             patch.object(installer.Path, "home", return_value=base), \
             patch.object(sys, "argv", ["install-hadalis-automation.py"]), \
             patch.object(installer, "require_command", side_effect=lambda name: "/usr/bin/" + name), \
             patch.object(installer.shutil, "which", return_value=None), \
             patch.object(installer.subprocess, "run") as run:
            assert installer.main() == 0
            run.assert_called_once_with(["/usr/bin/systemctl", "--user", "daemon-reload"], check=True)
            desktop = data_home / "applications/chatgpt.desktop"
            text = desktop.read_text()
            assert 'Exec="/usr/bin/chatgpt" --remote-debugging-address=127.0.0.1 --remote-debugging-port=9222 %U' in text
            assert "Icon=custom-icon" in text
            assert "MimeType=x-scheme-handler/codex;" in text
            assert "[Desktop Action Help]\nExec=help-viewer" in text
            assert vendor.read_text() == original
            installer.install_desktop_launcher("/usr/bin/chatgpt")
            assert desktop.read_text() == text

        # A target starts its WantedBy units before reaching the target. The
        # host cannot also depend on that same target having already started.
        unit_dir = base / ".config/systemd/user"
        host = (unit_dir / "hadalis-chatgpt.service").read_text()
        assert "WantedBy=graphical-session.target" in host
        assert "After=graphical-session.target" not in host
        assert "PartOf=graphical-session.target" in host
        bridge=(unit_dir/"hadalis-chat-bridge.service").read_text()
        assert "WantedBy=default.target" in bridge
        assert "Requires=hadalis-chatgpt" not in bridge and "PartOf=" not in bridge
        worker=(unit_dir/"hadalis-worker.service").read_text()
        assert "TasksMax=" in worker and "MemoryMax=" in worker and "NoNewPrivileges=yes" in worker
        broker=(unit_dir/"hadalis-privilege.service").read_text()
        assert "NoNewPrivileges=yes" not in broker
        assert (data_home/"hadalis-automation/control.py").exists()
        # Verify the generated units using the real systemd dependency parser.
        if shutil.which("systemd-analyze"):
            result = subprocess.run(["systemd-analyze", "--user", "verify",
                                     *map(str, sorted(unit_dir.glob("*.service")))],
                                    capture_output=True, text=True)
            assert result.returncode == 0, result.stderr

    print("PASS: Automation boot ordering, CDP desktop override, metadata and repeat installation")


if __name__ == "__main__":
    main()
