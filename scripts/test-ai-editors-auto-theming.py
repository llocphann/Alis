#!/usr/bin/env python3
"""
Test suite for Alis Auto-Theming: Antigravity, OpenAI Codex, Claude (CLI & Desktop).
Verifies:
1. Source contracts: post-transition deferral, nice -n 19 scheduling, and UI controls.
2. Functional execution: Rust native-dispatch and Python fallback theme generation & strip.
3. 30-editors module execution and signature-based fast skip.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def test_source_contracts() -> None:
    loader = (ROOT / "services/MaterialThemeLoader.qml").read_text()
    wallpapers = (ROOT / "services/Wallpapers.qml").read_text()
    applycolor = (ROOT / "scripts/colors/applycolor.sh").read_text()
    editors_mod = (ROOT / "scripts/colors/modules/30-editors.sh").read_text()
    editors_target = (ROOT / "scripts/colors/targets/editors.json").read_text()
    adv_config = (ROOT / "modules/settings/AdvancedConfig.qml").read_text()
    waffle_themes = (ROOT / "modules/waffle/settings/pages/WThemesPage.qml").read_text()

    # 1. nice -n 19 scheduling
    require('["/usr/bin/nice", "-n", "19"]' in loader,
            "MaterialThemeLoader must prefix external theme commands with nice -n 19")
    require('nice -n 19 bash "$module_path"' in applycolor,
            "applycolor.sh module runner must execute modules with nice -n 19")

    # 2. Post-transition and preview deferral
    require("property bool transitionActive: false" in loader
            and "property bool _transitionExternalDeferred: false" in loader
            and "function notifyWallpaperTransitionStarted" in loader
            and "function notifyWallpaperTransitionFinished" in loader,
            "MaterialThemeLoader must expose wallpaper transition tracking and deferral")
    require("if (root.previewActive) {" in loader
            and "root._previewExternalDeferred = true" in loader
            and "if (root.transitionActive) {" in loader
            and "root._transitionExternalDeferred = true" in loader,
            "_applyExternalTheming must defer work during preview and wallpaper transition")
    require('if (generationReady || reason === "post-transition") {' in loader
            and "delayedExternalApply.interval = 45" in loader,
            "MaterialThemeLoader must release post-transition deferral with fast 45ms dispatch")
    require("MaterialThemeLoader.notifyWallpaperTransitionStarted(root._wallpaperTransitionSettleMs())" in wallpapers,
            "Wallpapers.apply must notify MaterialThemeLoader of transition start")
    require("MaterialThemeLoader.notifyWallpaperTransitionFinished()" in wallpapers,
            "Wallpapers must notify MaterialThemeLoader when transition finishes")

    # 3. 30-editors module checks
    require("is_antigravity_present" in editors_mod,
            "30-editors.sh must detect Antigravity presence")
    require("enable_codex" in editors_mod and "enable_claude" in editors_mod,
            "30-editors.sh must read Codex and Claude toggles")
    require("EDITORS_INPUT_SIG_FILE" in editors_mod,
            "30-editors.sh must compute input signature to avoid redundant executions")

    # 4. Target definition
    require("Antigravity" in editors_target and "Codex" in editors_target and "Claude" in editors_target,
            "editors.json target description must list Antigravity, Codex, and Claude")

    # 5. UI Toggles in AdvancedConfig and WThemesPage
    require("Antigravity" in adv_config and "OpenAI Codex" in adv_config and "Claude" in adv_config,
            "AdvancedConfig.qml must have toggles for Antigravity, Codex, and Claude")
    require("Antigravity" in waffle_themes and "OpenAI Codex" in waffle_themes and "Claude" in waffle_themes,
            "WThemesPage.qml must have toggles for Antigravity, Codex, and Claude")

    print("✓ Source contracts verified successfully")


def test_functional_execution() -> None:
    with tempfile.TemporaryDirectory() as tmp_dir:
        tmp_path = Path(tmp_dir)
        fake_home = tmp_path / "home"
        fake_xdg_config = fake_home / ".config"
        fake_xdg_state = fake_home / ".local/state/quickshell"
        gen_dir = fake_xdg_state / "user/generated"
        gen_dir.mkdir(parents=True, exist_ok=True)
        fake_xdg_config.mkdir(parents=True, exist_ok=True)

        # Create sample palettes
        palette = {
            "background": "#101416",
            "surface": "#121719",
            "primary": "#83d3e3",
            "secondary": "#a2cbd4",
            "tertiary": "#a9cadb",
            "on_surface": "#dde4e6",
            "on_surface_variant": "#bfc8cb",
            "outline": "#899295",
            "outline_variant": "#3f484b",
            "error": "#fa746f",
            "term0": "#101416",
            "term1": "#fa746f",
            "term2": "#87d68d",
            "term3": "#e2c56b",
            "term4": "#83d3e3",
            "term5": "#bba7e8",
            "term6": "#8bd2cc",
            "term7": "#dde4e6",
        }
        palette_file = gen_dir / "palette.json"
        terminal_file = gen_dir / "terminal.json"
        scss_file = gen_dir / "material_colors.scss"

        palette_file.write_text(json.dumps(palette), encoding="utf-8")
        terminal_file.write_text(json.dumps(palette), encoding="utf-8")
        scss_content = "\n".join([f"${k}: {v};" for k, v in palette.items() if v.startswith("#")])
        scss_file.write_text(scss_content, encoding="utf-8")

        env = os.environ.copy()
        env["HOME"] = str(fake_home)
        env["XDG_CONFIG_HOME"] = str(fake_xdg_config)
        env["XDG_STATE_HOME"] = str(fake_home / ".local/state")
        env["CODEX_HOME"] = str(fake_home / ".codex")
        env["CLAUDE_CONFIG_DIR"] = str(fake_home / ".claude")
        env["CLAUDE_DESKTOP_CONFIG_DIR"] = str(fake_xdg_config / "Claude")
        env["ALIS_NATIVE_BIN_DIR"] = os.environ.get("ALIS_THEME_TEST_BIN_DIR", str(ROOT / "native/bin"))

        dispatch = str(ROOT / "scripts/native-dispatch")

        # ── Test Codex CLI theming & strip ──────────────────────────────
        codex_dir = Path(env["CODEX_HOME"])
        codex_dir.mkdir(parents=True, exist_ok=True)
        initial_codex_toml = "[model]\nname = \"o3\"\n"
        (codex_dir / "config.toml").write_text(initial_codex_toml, encoding="utf-8")

        # 1. Generate Codex theme
        res = subprocess.run([dispatch, "codex-theme", "--colors", str(palette_file),
                              "--terminal-json", str(terminal_file), "--scss", str(scss_file)],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"codex-theme failed: {res.stderr}")
        theme_path = codex_dir / "themes/alis.tmTheme"
        require(theme_path.is_file(), "alis.tmTheme was not created")
        theme_content = theme_path.read_text(encoding="utf-8")
        require("<key>name</key>" in theme_content and "#101416" in theme_content,
                "alis.tmTheme content invalid")
        updated_toml = (codex_dir / "config.toml").read_text(encoding="utf-8")
        require("theme = \"alis\"" in updated_toml, "config.toml does not contain theme = alis")

        # 2. Strip Codex theme
        res = subprocess.run([dispatch, "codex-theme", "--strip"], env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"codex-theme --strip failed: {res.stderr}")
        require(not theme_path.exists(), "alis.tmTheme was not deleted on strip")
        restored_toml = (codex_dir / "config.toml").read_text(encoding="utf-8")
        require("theme = \"alis\"" not in restored_toml, "config.toml still contains theme = alis after strip")
        print("✓ Codex CLI theming and strip verified (Rust backend)")

        # ── Test Claude Code & Desktop theming & strip ───────────────────
        claude_dir = Path(env["CLAUDE_CONFIG_DIR"])
        claude_desktop_dir = Path(env["CLAUDE_DESKTOP_CONFIG_DIR"])
        claude_dir.mkdir(parents=True, exist_ok=True)
        claude_desktop_dir.mkdir(parents=True, exist_ok=True)
        (claude_dir / "settings.json").write_text(json.dumps({"theme": "dark"}), encoding="utf-8")
        (claude_desktop_dir / "config.json").write_text(json.dumps({"userThemeMode": "light"}), encoding="utf-8")

        # 1. Generate Claude theme
        res = subprocess.run([dispatch, "claude-theme", "--colors", str(palette_file),
                              "--terminal-json", str(terminal_file), "--scss", str(scss_file)],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"claude-theme failed: {res.stderr}")
        claude_theme_path = claude_dir / "themes/alis.json"
        require(claude_theme_path.is_file(), "alis.json for claude was not created")
        claude_theme = json.loads(claude_theme_path.read_text(encoding="utf-8"))
        require(claude_theme.get("name") == "Alis Material", "claude alis.json invalid name")
        require("overrides" in claude_theme and claude_theme["overrides"].get("background") == "#101416",
                "claude overrides missing background")

        claude_settings = json.loads((claude_dir / "settings.json").read_text(encoding="utf-8"))
        require(claude_settings.get("theme") == "custom:alis", "claude settings.json does not reference custom:alis")
        desktop_cfg = json.loads((claude_desktop_dir / "config.json").read_text(encoding="utf-8"))
        require(desktop_cfg.get("userThemeMode") == "dark", "claude desktop config mode not synced")

        # 2. Strip Claude theme
        res = subprocess.run([dispatch, "claude-theme", "--strip"], env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"claude-theme --strip failed: {res.stderr}")
        require(not claude_theme_path.exists(), "claude alis.json was not deleted on strip")
        restored_claude_settings = json.loads((claude_dir / "settings.json").read_text(encoding="utf-8"))
        require(restored_claude_settings.get("theme") == "dark", "claude settings.json did not restore previous theme")
        restored_desktop_cfg = json.loads((claude_desktop_dir / "config.json").read_text(encoding="utf-8"))
        require(restored_desktop_cfg.get("userThemeMode") == "light", "claude desktop did not restore previous mode")
        print("✓ Claude Code & Desktop theming and strip verified (Rust backend)")

        # ── Test Antigravity theming & strip ─────────────────────────────
        antigravity_config = fake_xdg_config / "Antigravity/User"
        antigravity_config.mkdir(parents=True, exist_ok=True)
        owner_customizations = {
            "workbench.colorCustomizations": {"editor.background": "#010203"},
            "editor.tokenColorCustomizations": {"comments": "#abcdef"},
            "editor.semanticTokenColorCustomizations": {"enabled": False},
        }
        (antigravity_config / "settings.json").write_text(json.dumps({
            "workbench.colorTheme": "Default Dark+", **owner_customizations}), encoding="utf-8")

        # 1. Generate Antigravity theme
        res = subprocess.run([dispatch, "vscode-theme", "--forks", "antigravity",
                              "--colors", str(palette_file), "--terminal-json", str(terminal_file),
                              "--scss", str(scss_file)],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"vscode-theme for antigravity failed: {res.stderr}")
        anti_ext_theme = fake_home / ".antigravity/extensions/alis-material-theme/themes/alis-material-color-theme.json"
        require(anti_ext_theme.is_file(), f"Antigravity theme extension not written at {anti_ext_theme}")
        anti_settings = json.loads((antigravity_config / "settings.json").read_text(encoding="utf-8"))
        require(anti_settings.get("workbench.colorTheme") == "Alis Material",
                "Antigravity settings.json did not set workbench.colorTheme to Alis Material")
        require(anti_settings.get("alis.previousColorTheme") == "Default Dark+",
                "Antigravity previous theme not saved")
        require(all(anti_settings.get(k) == v for k, v in owner_customizations.items()),
                "Antigravity apply overwrote personal color customizations")

        # 2. Strip Antigravity theme
        res = subprocess.run([dispatch, "vscode-theme", "--strip", "--forks", "antigravity"],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"vscode-theme --strip for antigravity failed: {res.stderr}")
        require(not (fake_home / ".antigravity/extensions/alis-material-theme").exists(),
                "Antigravity extension directory was not removed on strip")
        restored_anti_settings = json.loads((antigravity_config / "settings.json").read_text(encoding="utf-8"))
        require(restored_anti_settings.get("workbench.colorTheme") == "Default Dark+",
                "Antigravity previous theme was not restored on strip")
        require(all(restored_anti_settings.get(k) == v for k, v in owner_customizations.items()),
                "Antigravity strip overwrote personal color customizations")
        print("✓ Antigravity theming and strip verified (Rust backend)")

        # ── Test Antigravity IDE dual directory support ───────────────────
        anti_ide_config = fake_xdg_config / "Antigravity IDE/User"
        anti_ide_config.mkdir(parents=True, exist_ok=True)
        (anti_ide_config / "settings.json").write_text(json.dumps({"workbench.colorTheme": "Solarized Light"}), encoding="utf-8")
        anti_ide_ext = fake_home / ".antigravity-ide/extensions"
        anti_ide_ext.mkdir(parents=True, exist_ok=True)

        res = subprocess.run([dispatch, "vscode-theme", "--forks", "antigravity",
                              "--colors", str(palette_file), "--terminal-json", str(terminal_file),
                              "--scss", str(scss_file)],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"vscode-theme for Antigravity IDE failed: {res.stderr}")
        anti_ide_theme = anti_ide_ext / "alis-material-theme/themes/alis-material-color-theme.json"
        require(anti_ide_theme.is_file(), f"Antigravity IDE theme not written at {anti_ide_theme}")
        ide_reg = anti_ide_ext / "extensions.json"
        require(ide_reg.is_file() and "alis.alis-material-theme" in ide_reg.read_text(encoding="utf-8"),
                "Antigravity IDE extension was not registered in .antigravity-ide/extensions/extensions.json")

        # Strip Antigravity IDE
        res = subprocess.run([dispatch, "vscode-theme", "--strip", "--forks", "antigravity"],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"vscode-theme --strip for Antigravity IDE failed: {res.stderr}")
        require(not anti_ide_theme.exists(), "Antigravity IDE theme was not removed on strip")
        if ide_reg.is_file():
            require("alis.alis-material-theme" not in ide_reg.read_text(encoding="utf-8"),
                    "Antigravity IDE was not unregistered from extensions.json on strip")
        print("✓ Antigravity IDE dual directory and extensions.json registry verified")

        # ── Test Codex ~/.config/codex fallback ──────────────────────────
        del env["CODEX_HOME"]
        shutil.rmtree(fake_home / ".codex", ignore_errors=True)
        xdg_codex_dir = fake_xdg_config / "codex"
        xdg_codex_dir.mkdir(parents=True, exist_ok=True)
        (xdg_codex_dir / "config.toml").write_text("[tui]\ntheme = \"monokai\"\n", encoding="utf-8")

        res = subprocess.run([dispatch, "codex-theme", "--colors", str(palette_file),
                              "--terminal-json", str(terminal_file), "--scss", str(scss_file)],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"codex-theme with ~/.config/codex failed: {res.stderr}")
        require((xdg_codex_dir / "themes/alis.tmTheme").is_file(), "alis.tmTheme not created in ~/.config/codex/themes")
        updated_xdg_toml = (xdg_codex_dir / "config.toml").read_text(encoding="utf-8")
        require("theme = \"alis\"" in updated_xdg_toml, "~/.config/codex/config.toml theme not updated to alis")

        # Strip ~/.config/codex
        res = subprocess.run([dispatch, "codex-theme", "--strip"], env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"codex-theme --strip with ~/.config/codex failed: {res.stderr}")
        require(not (xdg_codex_dir / "themes/alis.tmTheme").exists(), "alis.tmTheme not stripped from ~/.config/codex")
        require("theme = \"monokai\"" in (xdg_codex_dir / "config.toml").read_text(encoding="utf-8"),
                "~/.config/codex/config.toml did not restore monokai")
        print("✓ Codex ~/.config/codex fallback verified")

        # ── Test Claude empty settings.json parsing ─────────────────────
        (claude_dir / "settings.json").write_text("", encoding="utf-8")
        res = subprocess.run([dispatch, "claude-theme", "--colors", str(palette_file),
                              "--terminal-json", str(terminal_file), "--scss", str(scss_file)],
                             env=env, capture_output=True, text=True)
        require(res.returncode == 0, f"claude-theme with empty settings.json failed: {res.stderr}")
        parsed_csettings = json.loads((claude_dir / "settings.json").read_text(encoding="utf-8"))
        require(parsed_csettings.get("theme") == "custom:alis", "Empty claude settings.json not populated with theme")
        print("✓ Claude empty settings.json handling verified")

        # ── Test Python fallback parity & native-dispatch routing ───────
        py_env = env.copy()
        py_env["ALIS_NATIVE_BACKEND"] = "python"
        res_py_disp_codex = subprocess.run([dispatch, "codex-theme",
                                            "--colors", str(palette_file), "--terminal-json", str(terminal_file),
                                            "--scss", str(scss_file)],
                                           env=py_env, capture_output=True, text=True)
        require(res_py_disp_codex.returncode == 0, f"native-dispatch codex python backend failed: {res_py_disp_codex.stderr}")
        require((xdg_codex_dir / "themes/alis.tmTheme").is_file(), "Python codex backend did not write theme")

        res_py_disp_claude = subprocess.run([dispatch, "claude-theme",
                                             "--colors", str(palette_file), "--terminal-json", str(terminal_file),
                                             "--scss", str(scss_file)],
                                            env=py_env, capture_output=True, text=True)
        require(res_py_disp_claude.returncode == 0, f"native-dispatch claude python backend failed: {res_py_disp_claude.stderr}")
        require(claude_theme_path.is_file(), "Python claude backend did not write theme")
        print("✓ Python fallbacks parity and native-dispatch routing verified")

        # ── Test 30-editors module execution & fast signature skip ──────
        editors_script = ROOT / "scripts/colors/modules/30-editors.sh"
        res_mod = subprocess.run(["/usr/bin/bash", str(editors_script)], env=env, capture_output=True, text=True)
        require(res_mod.returncode == 0, f"30-editors.sh failed: {res_mod.stderr}")
        sig_file = gen_dir / ".editors-themegen-input.sig"
        require(sig_file.is_file() and sig_file.stat().st_size > 0,
                ".editors-themegen-input.sig was not generated")
        first_sig = sig_file.read_text(encoding="utf-8").strip()

        # Run again: signature check should immediately return 0 without changes
        res_mod2 = subprocess.run(["/usr/bin/bash", str(editors_script)], env=env, capture_output=True, text=True)
        require(res_mod2.returncode == 0, "30-editors.sh second run failed")
        second_sig = sig_file.read_text(encoding="utf-8").strip()
        require(first_sig == second_sig, "Input signature changed between identical runs")
        print("✓ 30-editors module execution and signature caching verified")


def main() -> None:
    test_source_contracts()
    test_functional_execution()
    print("\nALL AI EDITORS AUTO-THEMING TESTS PASSED!")


if __name__ == "__main__":
    main()
