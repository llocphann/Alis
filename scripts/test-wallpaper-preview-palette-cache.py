#!/usr/bin/env python3
"""Actual preview worker cache reuse, invalidation, bounded storage and isolation."""
import json
import os
import subprocess
import tempfile
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="alis-palette-cache-") as name:
    folder = Path(name)
    env = dict(os.environ, XDG_CONFIG_HOME=str(folder / "config"), XDG_CACHE_HOME=str(folder / "cache"),
               XDG_STATE_HOME=str(folder / "state"))
    for kind in ["config", "state"]:
        (folder / kind).mkdir()
        (folder / kind / "preserve").write_text("existing user data\n")
    worker = ROOT / "scripts/colors/preview-palette.py"
    source = folder / "quoted ' $HOME `false`.png"
    Image.new("RGB", (320, 180), "#a42847").save(source)
    cache = folder / "cache/quickshell/palette-preview"

    def palette(path=source, **options):
        result = subprocess.run(["python3", str(worker), str(path), json.dumps(options)], env=env,
                                text=True, capture_output=True, timeout=25, check=True)
        return json.loads(result.stdout)

    first = palette()
    entries = list(cache.glob("*.json"))
    assert len(entries) == 1
    original_key = entries[0]
    before = original_key.stat().st_mtime_ns
    assert palette() == first and len(list(cache.glob("*.json"))) == 1, "cache hit regenerated another palette"
    assert original_key.stat().st_mtime_ns >= before, "cache hit did not refresh its reuse order"
    original_key.write_text('{"background":"#broken","primary":"#abcdef","on_surface":"#abcdef"}')
    assert palette() == first, "invalid cached colors were returned instead of regenerating"
    Image.new("RGB", (320, 180), "#276fad").save(source)
    changed = palette()
    assert changed["primary"] != first["primary"], "rewriting the same wallpaper kept the old seed"
    inverted = palette(**{"invert-hue": True})
    assert inverted["primary"] != changed["primary"], "a changed generation option reused old colors"
    light = palette(mode="light")
    assert light["background"] != changed["background"], "mode selection reused the dark palette"
    (cache / "keep.note").write_text("unrelated cache data\n")
    for index in range(34):
        fixture = folder / (str(index) + ".png")
        Image.new("RGB", (24, 24), (60 + index, 100, 180)).save(fixture)
        palette(fixture)
    assert len(list(cache.glob("*.json"))) <= 32, "preview cache exceeded its storage budget"
    assert (cache / "keep.note").read_text() == "unrelated cache data\n", "cache pruning removed an unrelated file"
    assert not any(item.is_dir() for item in cache.iterdir()), "temporary generation directories leaked"
    for kind in ["config", "state"]:
        assert list((folder / kind).iterdir()) == [folder / kind / "preserve"], "preview wrote a durable theme or configuration"
        assert (folder / kind / "preserve").read_text() == "existing user data\n"
    print("PREVIEW_PALETTE_CACHE_PASS real generator reuse, corruption recovery, image/option/mode invalidation, 32-entry bound and durable-state isolation")
