#!/usr/bin/env python3
"""End-to-end Python/Rust theme parity on a synthetic image and temp templates.

The fixture only writes under a TemporaryDirectory and sets
ALIS_THEME_SKIP_SDDM_SYNC=1 so a local ii-pixel installation is never touched.
It also asserts that switchwall and IconThemeService continue to route through
scripts/native-dispatch rather than binding directly to Rust binaries.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import Any

REPO = Path(__file__).resolve().parents[2]
PY_GENERATOR = REPO / "scripts" / "colors" / "generate_colors_material.py"
TERMSCHEME = REPO / "scripts" / "colors" / "terminal" / "scheme-base.json"


def python_candidates() -> list[Path]:
    result: list[Path] = []
    for raw in (
        os.environ.get("ALIS_VENV"),
        os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV"),
    ):
        if raw:
            result.append(Path(os.path.expanduser(raw)) / "bin" / "python3")
    result.append(Path.home() / ".local/state/quickshell/.venv/bin/python3")
    result.append(Path(sys.executable))
    dedup: list[Path] = []
    for path in result:
        if path not in dedup:
            dedup.append(path)
    return dedup


def choose_theme_python() -> Path:
    probe = "import PIL, numpy, materialyoucolor"
    errors: list[str] = []
    for candidate in python_candidates():
        if not candidate.is_file():
            continue
        result = subprocess.run(
            [str(candidate), "-c", probe],
            text=True,
            capture_output=True,
        )
        if result.returncode == 0:
            return candidate
        errors.append(f"{candidate}: {result.stderr.strip()[:180]}")
    raise AssertionError(
        "no Python interpreter with Pillow/numpy/materialyoucolor; "
        + "; ".join(errors)
    )


def python_site_path(python: Path) -> str:
    code = (
        "import os, site; "
        "paths=[]; "
        "paths.extend(getattr(site, 'getsitepackages', lambda: [])()); "
        "user=site.getusersitepackages(); "
        "paths.extend(user if isinstance(user, (list, tuple)) else [user]); "
        "print(os.pathsep.join(p for p in paths if p))"
    )
    result = subprocess.run(
        [str(python), "-c", code],
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def make_image(path: Path, python: Path) -> None:
    code = r"""
from PIL import Image
import sys
path = sys.argv[1]
img = Image.new("RGB", (32, 32), (42, 78, 140))
pixels = img.load()
for y in range(32):
    for x in range(32):
        if x >= 22:
            pixels[x, y] = (214, 92, 72)
        elif y >= 24:
            pixels[x, y] = (68, 156, 104)
        elif 10 <= x < 15 and 8 <= y < 18:
            pixels[x, y] = (232, 196, 88)
img.save(path, format="PNG")
"""
    subprocess.run([str(python), "-c", code, str(path)], check=True)


def make_templates(root: Path) -> None:
    templates = root / "templates"
    templates.mkdir(parents=True)
    (templates / "fixture.txt").write_text(
        "primary={{colors.primary.default.hex}}\n"
        "primary_dark={{ colors.primary.dark.hex_stripped }}\n"
        "accent={{colors.app_accent.default.hex}}\n"
        "rgb={{colors.on_surface.light.rgb}}\n"
        "image={{image}}\n"
    )
    manifest = {
        "templates": [
            {
                "name": "fixture",
                "input": "fixture.txt",
                "output": "~/.config/alis-native-theme-fixture/rendered.txt",
            }
        ]
    }
    (root / "templates.json").write_text(json.dumps(manifest, indent=2) + "\n")


def load_json(path: Path) -> Any:
    with path.open() as handle:
        return json.load(handle)


def normalize_meta(value: dict[str, Any]) -> dict[str, Any]:
    result = dict(value)
    result.pop("generated_by", None)
    return result


def scss_map(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        values[key.strip()] = value.strip()
    return values


def run_backend(
    kind: str,
    python: Path,
    rust_binary: Path,
    image: Path,
    template_dir: Path,
    root: Path,
    mode: str,
    hash_seed: str | None = None,
) -> dict[str, Any]:
    home = root / "home"
    out = root / "out"
    home.mkdir(parents=True)
    out.mkdir(parents=True)

    args = [
        "--path", str(image),
        "--mode", mode,
        "--scheme", "scheme-tonal-spot",
        "--termscheme", str(TERMSCHEME),
        "--json-output", str(out / "colors.json"),
        "--palette-output", str(out / "palette.json"),
        "--app-palette-output", str(out / "app.json"),
        "--terminal-output", str(out / "terminal.json"),
        "--meta-output", str(out / "meta.json"),
        "--scss-output", str(out / "colors.scss"),
        "--render-templates", str(template_dir),
    ]
    argv = (
        [str(python), str(PY_GENERATOR), *args]
        if kind == "python"
        else [str(rust_binary), *args]
    )
    env = os.environ.copy()
    preserved_site = python_site_path(python)
    existing_pythonpath = env.get("PYTHONPATH", "")
    if preserved_site:
        env["PYTHONPATH"] = (
            preserved_site
            if not existing_pythonpath
            else preserved_site + os.pathsep + existing_pythonpath
        )
    if hash_seed is not None:
        env["PYTHONHASHSEED"] = hash_seed
    env.update(
        {
            "HOME": str(home),
            "XDG_CONFIG_HOME": str(home / ".config"),
            "XDG_STATE_HOME": str(home / ".local/state"),
            "XDG_CACHE_HOME": str(home / ".cache"),
            "ALIS_THEME_SKIP_SDDM_SYNC": "1",
        }
    )
    result = subprocess.run(argv, env=env, text=True, capture_output=True)
    if result.returncode:
        raise AssertionError(
            f"{kind} theme fixture failed rc={result.returncode}\n"
            f"stdout={result.stdout[-1200:]}\nstderr={result.stderr[-2400:]}"
        )

    return {
        "colors": load_json(out / "colors.json"),
        "palette": load_json(out / "palette.json"),
        "app": load_json(out / "app.json"),
        "terminal": load_json(out / "terminal.json"),
        "meta": normalize_meta(load_json(out / "meta.json")),
        "scss": scss_map(out / "colors.scss"),
        "template": (
            home / ".config/alis-native-theme-fixture/rendered.txt"
        ).read_text(),
    }


def assert_consumers() -> None:
    dispatch = (REPO / "scripts/native-dispatch").read_text()
    switchwall = (REPO / "scripts/colors/switchwall.sh").read_text()
    icons = (REPO / "services/IconThemeService.qml").read_text()

    required = [
        ('native-dispatch theme route', 'theme) required_binary=alis-theme', dispatch),
        ('theme Python fallback', 'generate_colors_material.py', dispatch),
        ('switchwall selector route', '"$SCRIPT_DIR/../native-dispatch" theme', switchwall),
        ('icon selector path', 'Quickshell.shellPath("scripts/native-dispatch")', icons),
        ('icon native command', '"desktop-icons"', icons),
        ('icon fail-soft fallback', 'falling back to legacy path', icons),
    ]
    missing = [label for label, token, source in required if token not in source]
    if missing:
        raise AssertionError("native theme/icon consumer contract missing: " + ", ".join(missing))


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-theme-parity.py /path/to/alis-theme", file=sys.stderr)
        return 64

    rust_binary = Path(sys.argv[1]).resolve()
    if not rust_binary.is_file():
        print(f"Rust theme binary not found: {rust_binary}", file=sys.stderr)
        return 2

    assert_consumers()
    python = choose_theme_python()

    with tempfile.TemporaryDirectory(prefix="alis-theme-parity.") as temp_raw:
        temp = Path(temp_raw)
        image = temp / "fixture.png"
        template_dir = temp / "template-root"
        make_image(image, python)
        make_templates(template_dir)

        for mode in ("dark", "light"):
            py = run_backend(
                "python",
                python,
                rust_binary,
                image,
                template_dir,
                temp / f"py-{mode}-seed0",
                mode,
                "0",
            )
            py_other_seed = run_backend(
                "python",
                python,
                rust_binary,
                image,
                template_dir,
                temp / f"py-{mode}-seed123",
                mode,
                "123",
            )
            if py != py_other_seed:
                raise AssertionError(
                    f"Python theme outputs depend on PYTHONHASHSEED in {mode} mode"
                )

            rs = run_backend(
                "rust", python, rust_binary, image, template_dir, temp / f"rs-{mode}", mode
            )

            for key in ("colors", "palette", "app", "terminal", "meta", "scss", "template"):
                if py[key] != rs[key]:
                    if isinstance(py[key], (dict, list)):
                        left = json.dumps(py[key], ensure_ascii=False, sort_keys=True, indent=2)
                        right = json.dumps(rs[key], ensure_ascii=False, sort_keys=True, indent=2)
                    else:
                        left, right = str(py[key]), str(rs[key])
                    raise AssertionError(
                        f"theme {mode} {key} parity mismatch\n--- python ---\n{left[:5000]}"
                        f"\n--- rust ---\n{right[:5000]}"
                    )
                print(f"PASS theme image/template [{mode}]: {key}")

    print("PASS: dark/light image seed, palette, terminal, templates and selector consumers match")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
