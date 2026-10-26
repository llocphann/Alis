#!/usr/bin/env python3
"""Regression suite for BRAND-R01/NVIM-01 Neovim / LazyVim wallpaper theming."""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
THEMEGEN = ROOT / "scripts/colors/neovim_themegen.sh"
EDITORS_MOD = ROOT / "scripts/colors/modules/30-editors.sh"
ADVANCED_QML = ROOT / "modules/settings/AdvancedConfig.qml"
WTHEMES_QML = ROOT / "modules/waffle/settings/pages/WThemesPage.qml"


def run_cmd(cmd: list[str], env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run(cmd, text=True, capture_output=True, env=merged, check=True)


def main() -> None:
    run_cmd(["bash", "-n", str(THEMEGEN), str(EDITORS_MOD)])

    adv_text = ADVANCED_QML.read_text(encoding="utf-8")
    wthemes_text = WTHEMES_QML.read_text(encoding="utf-8")
    expected_tip = 'Translation.tr("Generate Neovim/LazyVim theme at ~/.config/nvim/lua/plugins/neovim.lua.")'
    assert expected_tip in adv_text, "AdvancedConfig.qml tooltip must match canonical Neovim theme description"
    assert expected_tip in wthemes_text, "WThemesPage.qml tooltip must match canonical Neovim theme description"

    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        state_gen = base / "state/quickshell/user/generated"
        state_gen.mkdir(parents=True)
        palette_file = state_gen / "palette.json"
        terminal_file = state_gen / "terminal.json"
        scss_file = state_gen / "material_colors.scss"
        scss_file.write_text("$primary: #7aa2f7;\n", encoding="utf-8")

        palette_1 = {
            "background": "#1a1b26",
            "on_background": "#c0caf5",
            "surface_container_low": "#16161e",
            "surface_container_lowest": "#101014",
            "surface_container_high": "#292e42",
            "surface_container_highest": "#3b4261",
            "on_surface_variant": "#a9b1d6",
            "outline": "#565f89",
            "primary": "#7aa2f7",
            "secondary_container": "#3d59a1",
        }
        terminal_1 = {
            "term1": "#f7768e",
            "term2": "#9ece6a",
            "term4": "#7aa2f7",
            "term5": "#bb9af7",
            "term6": "#7dcfff",
            "term9": "#ff899d",
            "term10": "#b9f27c",
            "term11": "#e0af68",
            "term12": "#8db0ff",
            "term13": "#c7a9ff",
            "term14": "#a4daff",
        }
        palette_file.write_text(json.dumps(palette_1), encoding="utf-8")
        terminal_file.write_text(json.dumps(terminal_1), encoding="utf-8")

        # Prepare a mock lazy/alis.nvim git repo (using the real installed alis.nvim lua files if present,
        # or a faithful copy of the alis.nvim lua modules).
        lazy_root = base / "data/nvim/lazy"
        alis_repo = lazy_root / "alis.nvim"
        host_alis = Path.home() / ".local/share/nvim/lazy/alis.nvim"
        if (host_alis / "lua/alis/init.lua").is_file():
            shutil.copytree(host_alis, alis_repo, dirs_exist_ok=True)
        else:
            (alis_repo / "lua/alis").mkdir(parents=True)
            (alis_repo / "colors").mkdir(parents=True)
            (alis_repo / "colors/alis.lua").write_text('require("alis").load()\n', encoding="utf-8")
            (alis_repo / "lua/alis/init.lua").write_text(
                'local M = { opts = {} }\n'
                'function M.setup(o) M.opts = o or {} end\n'
                'function M.load()\n'
                '  local dir = M.opts.generated_dir or vim.fn.expand("~/.local/state/quickshell/user/generated")\n'
                '  local pal = vim.json.decode(table.concat(vim.fn.readfile(dir .. "/palette.json"), "\\n"))\n'
                '  vim.api.nvim_set_hl(0, "Normal", { fg = pal.on_background })\n'
                '  vim.api.nvim_set_hl(0, "FloatTitle", { fg = pal.primary, bold = true })\n'
                '  vim.g.colors_name = "alis"\n'
                'end\n'
                'return M\n',
                encoding="utf-8",
            )
            subprocess.run(["git", "init", "-q", str(alis_repo)], check=True)
            subprocess.run(["git", "-C", str(alis_repo), "config", "user.email", "test@example.com"], check=True)
            subprocess.run(["git", "-C", str(alis_repo), "config", "user.name", "Test"], check=True)
            subprocess.run(["git", "-C", str(alis_repo), "add", "."], check=True)
            subprocess.run(["git", "-C", str(alis_repo), "commit", "-q", "-m", "init"], check=True)

        expected_commit = subprocess.check_output(["git", "-C", str(alis_repo), "rev-parse", "HEAD"], text=True).strip()

        nvim_cfg = base / "config/nvim"
        plugin_dir = nvim_cfg / "lua/plugins"
        plugin_dir.mkdir(parents=True)

        # 1. Pre-populate broken alis.nvim spec and lazy-lock.json to verify safe migration & backup
        broken_spec = (
            '-- neovim.lua — auto-generated by Alis. Use 99-alis-user.lua for overrides.\n'
            'return {\n'
            '  { "yukazakiri/alis.nvim", priority = 1000, opts = {} },\n'
            '  { "LazyVim/LazyVim", opts = { colorscheme = "alis" } },\n'
            '}\n'
        )
        neovim_lua = plugin_dir / "neovim.lua"
        neovim_lua.write_text(broken_spec, encoding="utf-8")
        lock_file = nvim_cfg / "lazy-lock.json"
        lock_file.write_text(
            '{\n  "LazyVim": { "branch": "main", "commit": "1111111" },\n  "alis.nvim": { "branch": "main", "commit": "deadbeef" }\n}\n',
            encoding="utf-8",
        )

        env = {"NVIM_LAZY_ROOT": str(lazy_root)}
        run_cmd(["bash", str(THEMEGEN), str(palette_file), str(terminal_file), str(plugin_dir)], env=env)

        generated = neovim_lua.read_text(encoding="utf-8")
        assert '"yukazakiri/alis.nvim"' in generated
        assert 'colorscheme = "alis"' in generated
        assert 'package.preload["alis"]' in generated
        assert (nvim_cfg / "colors/alis.lua").is_file()
        assert (state_gen / "backups/neovim.lua.pre-nvim01.bak").read_text(encoding="utf-8") == broken_spec
        assert (state_gen / "backups/lazy-lock.json.pre-nvim01.bak").is_file()

        lock_data = json.loads(lock_file.read_text(encoding="utf-8"))
        assert "alis.nvim" not in lock_data
        assert "alis.nvim" in lock_data
        assert lock_data["LazyVim"]["commit"] == "1111111"

        # 2. Verify missing alis.nvim in lazy-lock.json is populated from local lazy/alis.nvim checkout
        lock_file.write_text('{\n  "LazyVim": { "branch": "main", "commit": "1111111" }\n}\n', encoding="utf-8")
        run_cmd(["bash", str(THEMEGEN), str(palette_file), str(terminal_file), str(plugin_dir)], env=env)
        lock_data = json.loads(lock_file.read_text(encoding="utf-8"))
        assert lock_data.get("alis.nvim", {}).get("commit") == expected_commit

        # 3. Verify Omarchy symlink handling and legacy zz-alis-omarchy.lua cleanup
        omarchy_target = base / "omarchy/current/theme/neovim.lua"
        omarchy_target.parent.mkdir(parents=True)
        omarchy_target.write_text("-- omarchy\n", encoding="utf-8")
        (plugin_dir / "theme.lua").symlink_to(omarchy_target)
        legacy_omarchy = plugin_dir / "zz-alis-omarchy.lua"
        legacy_omarchy.write_text("-- zz-alis-omarchy.lua — auto-generated by Alis.\nreturn {}\n", encoding="utf-8")

        run_cmd(["bash", str(THEMEGEN), str(palette_file), str(terminal_file), str(plugin_dir)], env=env)
        omarchy_override = plugin_dir / "zz-alis-omarchy.lua"
        assert omarchy_override.is_file()
        assert 'colorscheme = "alis"' in omarchy_override.read_text(encoding="utf-8")
        assert not legacy_omarchy.exists()

        # 4. Verify headlessly in real Neovim if installed
        if shutil.which("nvim"):
            probe_lua = base / "probe.lua"
            probe_lua.write_text(
                f"""
vim.opt.rtp:prepend({json.dumps(str(nvim_cfg))})
vim.opt.rtp:prepend({json.dumps(str(alis_repo))})
local spec = dofile({json.dumps(str(neovim_lua))})
assert(type(spec) == "table" and spec[1][1] == "yukazakiri/alis.nvim", "spec plugin mismatch")
assert(spec[2].opts.colorscheme == "alis", "spec colorscheme mismatch")
local alis = require("alis")
local alis = require("alis")
assert(alis == alis, "package.preload['alis'] must alias require('alis')")
alis.setup({{ generated_dir = {json.dumps(str(state_gen))}, live_reload = false }})
vim.cmd.colorscheme("alis")
assert(vim.g.colors_name == "alis", "colors_name must be alis")
local normal = vim.api.nvim_get_hl(0, {{ name = "Normal", link = false }})
local title = vim.api.nvim_get_hl(0, {{ name = "FloatTitle", link = false }})
assert(string.format("#%06x", normal.fg) == "#c0caf5", "Normal fg mismatch")
assert(string.format("#%06x", title.fg) == "#7aa2f7", "FloatTitle fg mismatch")
vim.cmd.colorscheme("alis")
assert(vim.g.colors_name == "alis", ":colorscheme alis must load alis palette")
print("NVIM_HEADLESS_OK_1")
""",
                encoding="utf-8",
            )
            res = run_cmd(["nvim", "--headless", "-u", "NONE", "-l", str(probe_lua)])
            assert "NVIM_HEADLESS_OK_1" in (res.stdout + res.stderr), res.stdout + res.stderr

            # Wallpaper change -> palette regeneration -> live reload check
            palette_2 = dict(palette_1, on_background="#e0def4", primary="#eb6f92")
            palette_file.write_text(json.dumps(palette_2), encoding="utf-8")
            probe_reload = base / "probe_reload.lua"
            probe_reload.write_text(
                f"""
vim.opt.rtp:prepend({json.dumps(str(nvim_cfg))})
vim.opt.rtp:prepend({json.dumps(str(alis_repo))})
local alis = require("alis")
alis.setup({{ generated_dir = {json.dumps(str(state_gen))}, live_reload = false }})
alis.load()
local normal = vim.api.nvim_get_hl(0, {{ name = "Normal", link = false }})
local title = vim.api.nvim_get_hl(0, {{ name = "FloatTitle", link = false }})
assert(string.format("#%06x", normal.fg) == "#e0def4", "Reloaded Normal fg mismatch")
assert(string.format("#%06x", title.fg) == "#eb6f92", "Reloaded FloatTitle fg mismatch")
print("NVIM_HEADLESS_RELOAD_OK")
""",
                encoding="utf-8",
            )
            res2 = run_cmd(["nvim", "--headless", "-u", "NONE", "-l", str(probe_reload)])
            assert "NVIM_HEADLESS_RELOAD_OK" in (res2.stdout + res2.stderr), res2.stdout + res2.stderr

        # 5. Disable via 30-editors.sh (enableNeovim = false) -> removes generated files
        alis_cfg_dir = base / "config/alis"
        alis_cfg_dir.mkdir(parents=True)
        (alis_cfg_dir / "config.json").write_text(
            json.dumps({"appearance": {"wallpaperTheming": {"enableNeovim": False, "enableVSCode": False}}}),
            encoding="utf-8",
        )
        mod_env = {
            "XDG_CONFIG_HOME": str(base / "config"),
            "XDG_STATE_HOME": str(base / "state"),
            "XDG_DATA_HOME": str(base / "data"),
            "HOME": str(base),
            "NVIM_LAZY_ROOT": str(lazy_root),
        }
        run_cmd(["bash", str(EDITORS_MOD)], env=mod_env)
        assert not neovim_lua.exists(), "Generated neovim.lua should be removed when enableNeovim=false"
        assert not (nvim_cfg / "colors/alis.lua").exists(), "Generated colors/alis.lua should be removed when enableNeovim=false"
        assert not omarchy_override.exists(), "Generated zz-alis-omarchy.lua should be removed when enableNeovim=false"

        # 6. User-owned neovim.lua (without auto-generated header) must NEVER be overwritten or deleted!
        custom_user_spec = (
            '-- Custom user LazyVim theme configuration\n'
            'return {\n'
            '  { "yukazakiri/alis.nvim", opts = { transparent = false } },\n'
            '  { "bjarneo/aether.nvim", enabled = false },\n'
            '}\n'
        )
        neovim_lua.write_text(custom_user_spec, encoding="utf-8")
        (alis_cfg_dir / "config.json").write_text(
            json.dumps({"appearance": {"wallpaperTheming": {"enableNeovim": True, "enableVSCode": False}}}),
            encoding="utf-8",
        )
        run_cmd(["bash", str(EDITORS_MOD)], env=mod_env)
        assert neovim_lua.read_text(encoding="utf-8") == custom_user_spec, "User-owned neovim.lua was overwritten!"

        (alis_cfg_dir / "config.json").write_text(
            json.dumps({"appearance": {"wallpaperTheming": {"enableNeovim": False, "enableVSCode": False}}}),
            encoding="utf-8",
        )
        run_cmd(["bash", str(EDITORS_MOD)], env=mod_env)
        assert neovim_lua.read_text(encoding="utf-8") == custom_user_spec, "User-owned neovim.lua was deleted by strip_neovim_spec!"

    print("BRAND_NEOVIM_THEMING_PASS")


if __name__ == "__main__":
    main()
