#!/usr/bin/env python3
"""Read-only Niri getters must ignore braces and values inside comments/strings."""

from contextlib import redirect_stdout
from importlib.util import module_from_spec, spec_from_file_location
from io import StringIO
import json
import os
from pathlib import Path
import tempfile


SOURCE = Path(__file__).with_name("niri-config.py")
spec = spec_from_file_location("niri_config", SOURCE)
module = module_from_spec(spec)
spec.loader.exec_module(module)


def read(command):
    output = StringIO()
    with redirect_stdout(output):
        assert command() == 0
    return json.loads(output.getvalue())


with tempfile.TemporaryDirectory(prefix="inir-niri-read-") as temporary:
    os.environ["XDG_CONFIG_HOME"] = temporary
    config = Path(temporary) / "niri"
    (config / "config.d").mkdir(parents=True)
    (config / "config.kdl").write_text(
        'include "config.d/20-layout-and-overview.kdl"\n'
        'include "config.d/60-animations.kdl"\n'
        'include "config.d/70-binds.kdl"\n'
    )
    (config / "config.d/20-layout-and-overview.kdl").write_text(
        "layout {\n    struts {\n        // left 64\n        // right 64\n"
        "        // top 64\n        // bottom 64\n    }\n}\n"
    )
    (config / "config.d/60-animations.kdl").write_text(
        "animations {\n    // slowdown 3.0\n}\n"
    )
    (config / "config.d/70-binds.kdl").write_text(
        "binds {\n"
        "    Mod+Tab { toggle-overview; }\n"
        "    XF86Favorites { spawn-sh \"echo '{ // }'\"; }\n"
        "    // { unmatched brace must not hide the next bind\n"
        "    Mod+Q { quit; }\n"
        "}\n"
    )

    binds = read(module.cmd_get_binds)["binds"]
    assert [item["key_combo"] for item in binds] == [
        "Mod+Tab", "XF86Favorites", "Mod+Q"
    ]
    assert [item["line_number"] for item in binds] == [2, 3, 5]
    assert read(module.cmd_get_layout)["struts"] == {
        "left": 0, "right": 0, "top": 0, "bottom": 0
    }
    assert read(module.cmd_get_animations)["slowdown"] == 1.0

    # Verify 90-user-extra.kdl active binds merge and Applications categorization
    (config / "config.d/90-user-extra.kdl").write_text(
        "binds {\n"
        '    Mod+T { spawn "/home/user/.local/bin/alis" "terminal"; }\n'
        '    Mod+Shift+T { spawn "/home/user/.local/bin/alis" "terminal" "--new"; }\n'
        '    Super+E { spawn "/home/user/.local/bin/alis" "terminal" "yazi"; }\n'
        '    Super+Shift+E { spawn "thunar"; }\n'
        '    Super+W { spawn "/home/user/.local/bin/alis" "browser"; }\n'
        '    Super+Shift+W { spawn "/home/user/.local/bin/alis" "browser" "--new"; }\n'
        '    Super+O { spawn "md.obsidian.Obsidian"; }\n'
        "}\n"
    )
    merged = read(module.cmd_get_binds)
    app_cat = next((c for c in merged["categories"] if c["name"] == "Applications"), None)
    assert app_cat is not None, merged["categories"]
    app_binds = {merged["binds"][i]["key_combo"]: merged["binds"][i]["description"] for i in app_cat["binds"]}
    assert app_binds == {
        "Mod+T": "Terminal",
        "Mod+Shift+T": "Terminal (new window)",
        "Super+E": "Terminal (yazi)",
        "Super+Shift+E": "File manager",
        "Super+W": "Browser",
        "Super+Shift+W": "Browser (new window)",
        "Super+O": "Obsidian",
    }, app_binds

print("PASS: Niri read-only getters ignore commented values and quoted braces")
