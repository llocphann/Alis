#!/usr/bin/env python3
"""Guard shared light-mode semantics adapted from snowarch/Alis."""

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def require(path: str, *needles: str) -> None:
    content = read(path)
    missing = [needle for needle in needles if needle not in content]
    if missing:
        raise AssertionError(f"{path}: missing light-mode contract: {missing}")


def main() -> int:
    require(
        "services/MaterialThemeLoader.qml",
        'Config.setNestedValue("appearance.wallpaperTheming.autoDarkLightMode", false)',
        "Appearance.m3colors.darkmode",
        "ColorUtils.quietSelection(accentContainer, l0, false)",
        "layer1Active, 4.5",
    )
    require(
        "modules/common/ThemePresets.qml",
        "c.darkmode",
        "tintLightSurfaces(c)",
        "themed.m3background = surface(0.77, 1.00)",
        "surfaceChromaProxy >= 0.06 ? originalSurface : primary",
        "signedHueDelta(anchor.hslHue, primary.hslHue)",
        "ColorUtils.quietSelection(primaryContainer, layer0, false)",
        "ColorUtils.semanticStatus(primary, layer0, 145.0, 0.48)",
        "app_success: success",
        "layer1Active, 4.5",
    )
    require(
        "scripts/colors/switchwall.sh",
        'lum_source="$imgpath"',
        '-alpha off -resize 64x64',
        'generate_colors_material_args+=(--mode "$mode_flag")',
    )
    require(
        "scripts/colors/generate_colors_material.py",
        "layer1_active, 4.5",
        "tint_light_surfaces(material_colors, args.scheme, hct)",
        '"background": (77.0, 1.00)',
        "def _surface_theme_anchor(",
        "_shortest_hue_delta(theme_seed.hue, primary.hue)",
        "selection_tone",
        "min(container_hct.chroma, 20.0)",
        '"app_success": success',
        '"app_warning": warning',
        '"app_error": error',
        'if args.scheme != "scheme-monochrome":',
        '("term7", 75.0 if darkmode else 35.0, 4.5)',
        "current.update(material_colors)",
        "current.update(app_palette_json)",
    )
    require(
        "scripts/colors/generate_terminal_configs.py",
        "def contrast_hex(a, b):",
        'colors.setdefault("selectionBg"',
        'selection_foreground    {colors.get("term15"',
        'contrast_hex(colors.get("term7"',
    )
    require(
        "native/alis-theme/src/palette.rs",
        "scheme.primary_palette",
        "tint_light_surfaces(&mut palette, scheme_name, seed)",
        '("background", 77.0, 1.00)',
        "fn surface_theme_anchor(",
        "shortest_hue_delta(seed.hue(), primary.hue())",
        "layer0_is_light",
        "let selection_tone",
        "container_hct.chroma().min(20.0)",
        '("app_success", success)',
        '("app_warning", warning)',
        '("app_error", error)',
        '("term7", if dark { 75.0 } else { 35.0 }, 4.5)',
    )
    require(
        "scripts/colors/apply-gtk-theme.sh",
        "theme-meta.json",
        "APPLIED_ICON_THEME",
        'bash "$SCRIPT_DIR/icon-theme-for-mode.sh"',
        "APP_SUCCESS=",
        "APP_WARNING=",
        "APP_ERROR=",
        'FG_POSITIVE="${APP_SUCCESS:-$SECONDARY}"',
        "KDE_SELECTION_FG_INACTIVE",
        "@define-color success_color",
        "--success-color:",
        ".app_foreground // .on_surface",
    )
    require(
        "scripts/colors/vscode_themegen/main.go",
        'themeNameLight   = "Alis Material Light"',
        'themeFileLight   = "alis-material-light-color-theme.json"',
        '{"label": themeNameLight, "uiTheme": "vs"',
        "func mutedInk(",
        "func lightenEdges(",
        "manifestHasLight(",
        "activeName, activeFile := themeIdentity(colors)",
        "syntaxColor(termColors, primary, editorBg",
    )
    require(
        "modules/common/Appearance.qml",
        "m3colors.m3onSurface, m3colors.m3surface, 4.5",
        "m3colors.m3onSurfaceVariant, m3colors.m3surfaceContainer, 4.5",
        "m3colors.m3onPrimaryContainer, colPrimaryContainer, 4.5",
        "m3colors.m3onErrorContainer, colErrorContainer, 4.5",
    )
    require(
        "modules/common/Appearance.qml",
        'readonly property color _lightInk: "#000000"',
        'readonly property color _lightInkVariant: "#1a1a1a"',
        "property color colOnSurface: m3colors.darkmode",
        ": _lightInk",
        "property color colSubtext: m3colors.darkmode",
    )
    require(
        "modules/abyss/looks/AbyssLabel.qml",
        'Appearance.m3colors.darkmode ? AbyssStyle.textColor : "#000000"',
    )
    require(
        "modules/abyss/looks/AbyssButton.qml",
        'readonly property color baseInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.textColor : "#000000"',
        'readonly property color activeInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.accent : "#000000"',
        "root.activeInk : root.baseInk",
    )
    require(
        "modules/abyss/looks/AbyssCheckBox.qml",
        'readonly property color labelInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.textColor : "#000000"',
    )
    require(
        "modules/abyss/looks/AbyssSearchField.qml",
        'readonly property color fieldInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.textColor : "#000000"',
        '? AbyssStyle.textColorMuted : "#1a1a1a"',
    )
    require(
        "modules/abyss/looks/AbyssSlider.qml",
        'readonly property color sliderInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.textColor : "#000000"',
        '? AbyssStyle.textColorMuted : "#1a1a1a"',
    )
    require(
        "modules/abyss/content/AbyssUtilitiesPopup.qml",
        'readonly property color utilityInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.textColor : "#000000"',
        'readonly property color utilityMutedInk: Appearance.m3colors.darkmode',
        '? AbyssStyle.textColorMuted : "#1a1a1a"',
    )
    require(
        "modules/bar/weather/OrbitalWeather.qml",
        "readonly property color orbitInk: Appearance.colors.colOnLayer1",
        "readonly property color orbitSubInk: Appearance.colors.colSubtext",
        "readonly property color orbitTimeInk: Appearance.m3colors.darkmode",
        '? root.orbitSubInk : "#000000"',
        "color: root.orbitTimeInk",
        "readonly property color orbitAccent: ColorUtils.ensureReadable(",
    )
    require(
        "services/IconThemeService.qml",
        "function _apply(themeName: string, skipRestart: bool): void",
        "id: variantProc",
        "icon-theme-for-mode.sh",
    )
    legacy_abyss_ink = re.compile(
        r"(?:color|placeholderTextColor)\s*:\s*AbyssStyle\.textColor(?:Muted)?\b"
    )
    offenders = []
    for path in (ROOT / "modules/abyss").rglob("*.qml"):
        if path.name == "AbyssStyle.qml":
            continue
        for line_no, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if legacy_abyss_ink.search(line):
                offenders.append(f"{path.relative_to(ROOT)}:{line_no}:{line.strip()}")
    if offenders:
        raise AssertionError(
            "Abyss light-mode ink bypasses remain:\n" + "\n".join(offenders)
        )

    if not (ROOT / "scripts/colors/icon-theme-for-mode.sh").is_file():
        raise AssertionError("scripts/colors/icon-theme-for-mode.sh is missing")

    print("light-mode upstream contract: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
