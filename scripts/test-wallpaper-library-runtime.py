#!/usr/bin/env python3
"""Exercise both wallpaper pickers and the shared catalog on private file trees."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

from native_test_session import private_wayland, run_qs

SCRIPTS = Path(__file__).resolve().parent


def create_catalog(folder):
    catalog = folder / "catalog"
    catalog.mkdir()
    still = folder / "still.png"
    animated = folder / "animated.gif"
    for path, color in ((still, "#76549c"), (animated, "#894c65")):
        subprocess.run(["magick", "-size", "30x20", "xc:" + color, str(path)], check=True)
    for i in range(320):
        os.link(still, catalog / f"frame {i:03d}.png")
    os.link(still, catalog / "Ảnh\nblue 'trăng' #1.png")
    os.link(animated, catalog / "BLUE đô thị.GIF")
    extra = folder / "extra"
    extra.mkdir()
    os.link(still, extra / "extra still.png")


def create_tag_helper(folder):
    helper = folder / "tag-helper" / "native-dispatch"
    helper.parent.mkdir()
    helper.write_text("""#!/usr/bin/python3
import json, sys, time
from pathlib import Path
assert sys.argv[1:3] == ["color-tags", "--roots"]
home = Path.home()
root = Path(sys.argv[3])
with (home / "requests").open("a") as log:
    print(root.name, file=log)
if root.name == "catalog":
    deadline = time.monotonic() + 10
    while not (home / "release").exists():
        if time.monotonic() > deadline:
            sys.exit(2)
        time.sleep(.025)
mode = (home / "mode").read_text().strip() if (home / "mode").exists() else "ok"
print("broken" if mode == "malformed" else json.dumps({str(root / (mode + ".png")): ["blue"]}))
sys.exit(1 if mode == "failed" else 0)
""")
    helper.chmod(0o755)


def run(root):
    with tempfile.TemporaryDirectory(prefix="alis-wallpaper-library-") as name:
        folder = Path(name)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "scripts", "assets", "defaults", "translations"):
            (folder / entry).symlink_to(root / entry)
        shutil.copyfile(SCRIPTS / "fixtures/wallpaper-library.qml", folder / "shell.qml")
        (folder / "home").mkdir()
        create_catalog(folder)
        create_tag_helper(folder)
        with private_wayland(folder) as env:
            if not env or env.get("QT_QPA_PLATFORM") != "wayland":
                raise RuntimeError("A private Wayland compositor is required")
            config = json.loads((root / "defaults/config.json").read_text())
            config.setdefault("wallpapers", {})["directory"] = str(folder / "catalog")
            config.setdefault("weather", {})["enable"] = False
            config.setdefault("background", {}).setdefault("transition", {})["type"] = "alisMelt"
            for app in ("alis", "illogical-impulse"):
                target = folder / "config" / app / "config.json"
                target.parent.mkdir(exist_ok=True, parents=True)
                target.write_text(json.dumps(config))
            env.update(HOME=str(folder / "home"), WALLPAPER_TEST_DIR=str(folder),
                       DBUS_SYSTEM_BUS_ADDRESS="unix:path=/nonexistent", ALIS_DISABLE_LIQUID_SHADER="1")
            result = run_qs(folder, env, timeout=55)
        if result.returncode or "WALLPAPER_LIBRARY_PASS" not in result.stdout or any(
            marker in result.stdout for marker in ("WALLPAPER_LIBRARY_FAIL", "ReferenceError:", "TypeError:", "Unable to assign")
        ):
            raise SystemExit(result.stdout)
        print(next(line for line in result.stdout.splitlines() if "WALLPAPER_LIBRARY_PASS" in line))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell-root", type=Path, default=SCRIPTS.parent)
    run(parser.parse_args().shell_root.resolve())
