#!/usr/bin/env python3
"""Crash injection at each config/state transaction boundary."""
import os
from pathlib import Path
import sys
import tempfile
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from automation.manager import control, store


def main():
    for broken in ("config", "state", "after-state"):
        with tempfile.TemporaryDirectory() as tmp, patch.dict(os.environ, {
                "XDG_STATE_HOME": tmp + "/state", "XDG_CONFIG_HOME": tmp + "/config"}):
            store.change(lambda c, s: None)
            real_write = store._write

            def crashing(path, payload):
                if broken == "config" and path == store.config_path():
                    raise OSError("power loss before config")
                if broken == "state" and path == store.state_path():
                    raise OSError("power loss before state")
                real_write(path, payload)
                if broken == "after-state" and path == store.state_path():
                    raise OSError("power loss before journal cleanup")

            with patch.object(store, "_write", side_effect=crashing):
                try:
                    control.create_profile("Atomic profile")
                except OSError:
                    pass
                else:
                    raise AssertionError("expected injected crash")
            config, state, issues = store.read_snapshot()
            assert not issues
            assert len(config["profiles"]) == len(state["profiles"]) == 2
            assert {p["id"] for p in config["profiles"]} == set(state["profiles"])
            assert not (store.state_dir() / "transaction.json").exists()
            for path in (store.config_path(), store.state_path()):
                assert path.stat().st_mode & 0o777 == 0o600
            # Recovery is idempotent, and preserves submitted legacy state.
            pending = {"response_action_count": 3, "counted": True}
            store.change_state(lambda c, s: s["profiles"][config["profiles"][0]["id"]].update(
                {"pending": pending}))
            assert store.read_snapshot()[1]["profiles"][config["profiles"][0]["id"]]["pending"] == pending
    print("PASS: config/state crash recovery and private durable storage")


if __name__ == "__main__":
    main()
