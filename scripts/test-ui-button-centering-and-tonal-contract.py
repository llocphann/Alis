#!/usr/bin/env python3
"""Contract + headless runtime guard for button centering, background-derived HSL
tonal gradients, active pill colBackgroundToggled/WCAG ink, Hourglass-only Timers,
and Edgebar/module Wayland window reservation parity.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
INTERGRATION_ROOT = ROOT.parent / "Alis-Intergration"
COMPANION_ROOT = ROOT.parent / "Alis-Companion"

QML_TARGETS = [
    ROOT / "modules/sidebarRight/pomodoro/PomodoroTimer.qml",
    ROOT / "modules/sidebarRight/pomodoro/CountdownTimer.qml",
    ROOT / "modules/dashboard/DashboardWeeklyPlanner.qml",
    ROOT / "modules/dashboard/DashboardYearlyPlanner.qml",
    ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
    INTERGRATION_ROOT / "modules/dashboard/DashboardExercisesTracker.qml",
]


def _extract_brace_block(src: str, open_brace_idx: int) -> str:
    """Return the QML block from `{` at open_brace_idx to its matching `}`."""
    depth = 0
    i = open_brace_idx
    n = len(src)
    in_str: str | None = None
    while i < n:
        ch = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_str is not None:
            if ch == "\\" and i + 1 < n:
                i += 2
                continue
            if ch == in_str:
                in_str = None
        else:
            if ch == "/" and nxt == "/":
                nl = src.find("\n", i)
                i = n if nl < 0 else nl + 1
                continue
            if ch == "/" and nxt == "*":
                end = src.find("*/", i + 2)
                i = n if end < 0 else end + 2
                continue
            if ch in ('"', "'", "`"):
                in_str = ch
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return src[open_brace_idx : i + 1]
        i += 1
    raise AssertionError(f"Unclosed QML block starting at offset {open_brace_idx}")


def check_static_contracts() -> None:
    toggled_pattern = re.compile(r"\btoggled\s*:")
    col_toggled_pattern = re.compile(r"\bcolBackgroundToggled\s*:")

    for path in QML_TARGETS:
        src = path.read_text(encoding="utf-8")
        # 1. Discover inline custom RippleButton subclasses that provide colBackgroundToggled
        custom_toggled_types: set[str] = set()
        for m in re.finditer(r"component\s+([A-Za-z_]\w*)\s*:\s*RippleButton\s*\{", src):
            comp_name = m.group(1)
            block = _extract_brace_block(src, m.end() - 1)
            if col_toggled_pattern.search(block):
                custom_toggled_types.add(comp_name)

        type_names = ["RippleButton"] + sorted(custom_toggled_types)
        btn_re = re.compile(r"\b(" + "|".join(re.escape(t) for t in type_names) + r")\s*\{")
        for m in btn_re.finditer(src):
            kind = m.group(1)
            block = _extract_brace_block(src, m.end() - 1)
            if toggled_pattern.search(block):
                has_explicit = bool(col_toggled_pattern.search(block)) or (kind in custom_toggled_types)
                assert has_explicit, (
                    f"{path.name}: toggled {kind} at line {src[:m.start()].count(chr(10)) + 1} "
                    f"must explicitly declare colBackgroundToggled"
                )

        # 2. Direct StyledText button contentItems must explicitly center horizontally
        for m in re.finditer(r"contentItem\s*:\s*StyledText\s*\{", src):
            block = _extract_brace_block(src, m.end() - 1)
            assert "Text.AlignHCenter" in block, (
                f"{path.name}: direct contentItem StyledText at line {src[:m.start()].count(chr(10)) + 1} "
                f"must set horizontalAlignment: Text.AlignHCenter"
            )

    # 3. Stepped solid tonal elevation invariant (Layer 1 matches Home Dashboard colLayer1Base, gentle steps, zero neutral washes / flat-card Gradients)
    tonal_synced_files = (
        ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
        ROOT / "modules/dashboard/DashboardYearlyPlanner.qml",
        ROOT / "modules/dashboard/DashboardWeeklyPlanner.qml",
        ROOT / "modules/dashboard/DashboardMusic.qml",
        ROOT / "modules/dashboard/DashboardHeader.qml",
        ROOT / "modules/dashboard/DashboardEditToolbar.qml",
        INTERGRATION_ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
        INTERGRATION_ROOT / "modules/dashboard/DashboardExercisesTracker.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaTalkCloud.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaSwarmPane.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaPocketPane.qml",
    )
    no_gradient_files = {
        ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
        INTERGRATION_ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
        INTERGRATION_ROOT / "modules/dashboard/DashboardExercisesTracker.qml",
        ROOT / "modules/dashboard/DashboardYearlyPlanner.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaSwarmPane.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaPocketPane.qml",
    }
    abyss_card_files = {
        ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
        INTERGRATION_ROOT / "modules/dashboard/DashboardSpacedRepetition.qml",
        INTERGRATION_ROOT / "modules/dashboard/DashboardExercisesTracker.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaSwarmPane.qml",
        COMPANION_ROOT / "modules/abyss/companion/AquaPocketPane.qml",
    }
    abyss_surface_re = re.compile(
        r"(?:^|[\s,{])(?:color|colBackground|colBackgroundHover)\s*:[^\n]*Qt\.alpha\(AbyssStyle\.textColor\b",
        re.M,
    )
    companion_btn_surface_re = re.compile(
        r"(?:^|[\s,{])(?:colBackground|colBackgroundHover)\s*:[^\n]*Qt\.alpha\(AbyssStyle\.textColor\b",
        re.M,
    )
    companion_low_alpha_fill_re = re.compile(
        r"(?:^|[\s,{])color\s*:[^\n]*Qt\.alpha\(AbyssStyle\.textColor,\s*0?\.0\d",
        re.M,
    )
    ink_alpha_re = re.compile(r"Qt\.alpha\((?:root\.)?ink\b")

    for tonal_path in tonal_synced_files:
        assert tonal_path.exists(), f"Missing synced QML target: {tonal_path}"
        tsrc = tonal_path.read_text(encoding="utf-8")
        assert "Appearance.colors.colLayer1Base" in tsrc, (
            f"{tonal_path.name} must anchor Layer 1 stepped surfaces on Home Dashboard Appearance.colors.colLayer1Base"
        )
        assert "ColorUtils.tonalStep(" in tsrc, f"{tonal_path.name} must derive elevation via ColorUtils.tonalStep"
        if tonal_path in no_gradient_files:
            assert "Gradient" not in tsrc and "gradient:" not in tsrc, (
                f"{tonal_path.name} must use stacked stepped solid layers, never internal per-box Gradient blocks"
            )
        if tonal_path.name == "DashboardMusic.qml":
            assert "Qt.rgba(1, 1, 1, 0.04)" not in tsrc and "Qt.rgba(1, 1, 1, 0.08)" not in tsrc, (
                "DashboardMusic.qml must not use neutral Qt.rgba(1, 1, 1, ...) surface washes"
            )
        if tonal_path.name == "DashboardYearlyPlanner.qml":
            assert not ink_alpha_re.search(tsrc), (
                "DashboardYearlyPlanner.qml must not use Qt.alpha(ink/root.ink, ...) washes"
            )
        if tonal_path.name == "DashboardHeader.qml":
            assert "Qt.alpha(root.colText, .08)" not in tsrc and "Qt.alpha(root.colText, 0.08)" not in tsrc, (
                "DashboardHeader.qml must not use Qt.alpha(root.colText, 0.08) neutral hover fills"
            )
        if tonal_path.name == "DashboardEditToolbar.qml":
            assert (
                "Qt.alpha(Appearance.colors.colOnLayer1, 0.10)" not in tsrc
                and "Qt.alpha(Appearance.colors.colOnLayer1, 0.08)" not in tsrc
            ), "DashboardEditToolbar.qml must not use Qt.alpha(colOnLayer1, ...) hover fills"
        if tonal_path in abyss_card_files:
            assert not abyss_surface_re.search(tsrc), (
                f"{tonal_path.name} must not use gray AbyssStyle.textColor alpha surface fills"
            )
            if tonal_path.name in ("DashboardSpacedRepetition.qml", "DashboardExercisesTracker.qml"):
                assert 'root.isDarkSurface ? "#ffffff" : "#000000"' not in tsrc, (
                    f"{tonal_path.name} must not wash elevated boxes with neutral #ffffff/#000000 mixes"
                )
        if tonal_path.name == "AquaTalkCloud.qml":
            assert not companion_btn_surface_re.search(tsrc), (
                "AquaTalkCloud.qml must not use Qt.alpha(AbyssStyle.textColor, ...) button fills"
            )
            assert not companion_low_alpha_fill_re.search(tsrc), (
                "AquaTalkCloud.qml must not use low-alpha Qt.alpha(AbyssStyle.textColor, 0.0x) box fills"
            )

    sr_marker = "property bool _captureLoaded: false"
    alis_sr_src = (ROOT / "modules/dashboard/DashboardSpacedRepetition.qml").read_text(encoding="utf-8")
    integ_sr_src = (INTERGRATION_ROOT / "modules/dashboard/DashboardSpacedRepetition.qml").read_text(encoding="utf-8")
    assert sr_marker in alis_sr_src and sr_marker in integ_sr_src, (
        "Both Alis and Alis-Intergration DashboardSpacedRepetition.qml must define _captureLoaded marker"
    )
    assert alis_sr_src.split(sr_marker, 1)[1] == integ_sr_src.split(sr_marker, 1)[1], (
        "DashboardSpacedRepetition.qml body diverged between Alis and Alis-Intergration"
    )

    # 4. Hourglass-only Timers (no classic arc style or Key_T shortcut)
    for timer_file in (
        ROOT / "services/TimerService.qml",
        ROOT / "modules/sidebarRight/pomodoro/PomodoroWidget.qml",
        ROOT / "modules/sidebarRight/pomodoro/PomodoroTimer.qml",
        ROOT / "modules/sidebarRight/pomodoro/CountdownTimer.qml",
    ):
        text = timer_file.read_text(encoding="utf-8")
        assert "Qt.Key_T" not in text, f"{timer_file.name} must not bind Qt.Key_T outside Customize"
        assert "PathAngleArc" not in text, f"{timer_file.name} must not include Classic PathAngleArc"
        assert 'styleKey === "classic"' not in text and "classicMode" not in text, (
            f"{timer_file.name} must not keep Classic visual style branches"
        )


OFFSCREEN_CONTEXT_MENU_STUB = """import QtQuick
Loader {
    id: root
    active: false
    property var model: []
    property Item anchorItem: parent
    property real padding: 4
    property bool noSmoothClosing: false
    property bool closeOnFocusLost: true
    property bool keyboardGrab: true
    property bool closeOnHoverLost: true
    property bool closeOnHoverLostAfterEntered: false
    property int closeOnHoverLostDelay: 500
    property bool anchorHovered: false
    property bool closeOnOutsideClick: false
    property var anchorRect: null
    property var popupAdjustment: null
    property bool scaleContent: false
    property bool cursorSlide: false
    property var cursorAnchorWindow: null
    property real cursorAnchorX: 0
    property real cursorAnchorY: 0
    property real visualMargin: 8
    property bool popupAbove: true
    property int popupSide: 0
    property real ambientShadowWidth: 1
    property color panelFallbackColor: "transparent"
    property real panelRadius: 8
    property real panelBorderWidth: 0
    property color panelBorderColor: "transparent"
    signal focusCleared()
    function grabFocus() {}
    function close() { root.active = false }
    function requestOpen() { root.active = true }
    function requestOpenAt(x, y, newModel) { if (newModel !== undefined) root.model = newModel; root.active = true }
}
"""


def _install_offscreen_modules_overlay(folder: Path, host_root: Path) -> None:
    mod_link = folder / "modules"
    if mod_link.is_symlink():
        mod_link.unlink()
    mod_link.mkdir(parents=True, exist_ok=True)
    for child in (host_root / "modules").iterdir():
        if child.name == "common":
            common_dir = mod_link / "common"
            common_dir.mkdir(parents=True, exist_ok=True)
            for cchild in child.iterdir():
                if cchild.name == "widgets":
                    w_dir = common_dir / "widgets"
                    w_dir.mkdir(parents=True, exist_ok=True)
                    for wchild in cchild.iterdir():
                        if wchild.name == "ContextMenu.qml":
                            (w_dir / "ContextMenu.qml").write_text(OFFSCREEN_CONTEXT_MENU_STUB, encoding="utf-8")
                        else:
                            (w_dir / wchild.name).symlink_to(wchild)
                else:
                    (common_dir / cchild.name).symlink_to(cchild)
        else:
            (mod_link / child.name).symlink_to(child)


def check_tonal_step_runtime() -> None:
    shell_qml = """
import QtQuick
import Quickshell
import qs.services
import qs.modules.common.functions

ShellRoot {
    Component.onCompleted: Quickshell.watchFiles = false
    QtObject {
        id: canvasStub
        property bool editMode: false
        property string gridStyle: "dots"
        property int gridSize: 24
        property bool snapToGrid: true
        property bool autoAdjustSize: false
        property string selectedId: ""
    }
    Window {
        id: probeWin
        visible: false
        width: 1200
        height: 800
        Item {
            id: probeHost
            anchors.fill: parent
        }
    }
    Timer {
        interval: 30
        running: true
        repeat: false
        onTriggered: {
            const base = Qt.color("#150e0e")
            const lifted = ColorUtils.tonalStep(base, 0.06, 1.12)
            const hueDiff = Math.abs(lifted.hslHue - base.hslHue)
            if (hueDiff >= 0.01) {
                console.error("TONAL_STEP_FAIL hue drift", base.hslHue, lifted.hslHue)
                Qt.exit(2)
                return
            }
            if (lifted.hslSaturation < base.hslSaturation * 0.95) {
                console.error("TONAL_STEP_FAIL sat drop", base.hslSaturation, lifted.hslSaturation)
                Qt.exit(3)
                return
            }
            if (lifted.hslLightness <= base.hslLightness + 0.04) {
                console.error("TONAL_STEP_FAIL lightness did not rise", base.hslLightness, lifted.hslLightness)
                Qt.exit(4)
                return
            }

            const lightBase = Qt.color("#e4eaf4")
            const lightStep = ColorUtils.tonalStep(lightBase, -0.06, 1.12)
            const lightHueDiff = Math.min(
                Math.abs(lightStep.hslHue - lightBase.hslHue),
                1 - Math.abs(lightStep.hslHue - lightBase.hslHue)
            )
            if (lightHueDiff >= 0.01 || lightStep.hslSaturation < lightBase.hslSaturation * 0.95 || lightStep.hslLightness >= lightBase.hslLightness) {
                console.error("TONAL_STEP_FAIL light shift invalid")
                Qt.exit(5)
                return
            }

            const modulesToCompile = [
                "modules/dashboard/DashboardHeader.qml",
                "modules/dashboard/DashboardEditToolbar.qml",
                "modules/dashboard/DashboardMusic.qml",
                "modules/dashboard/DashboardYearlyPlanner.qml",
                "modules/dashboard/DashboardWeeklyPlanner.qml",
                "modules/dashboard/DashboardSpacedRepetition.qml",
                "optional/alis-companion/modules/abyss/companion/AquaPocketPane.qml",
                "optional/alis-companion/modules/abyss/companion/AquaSwarmPane.qml",
                "optional/alis-companion/modules/abyss/companion/AquaTalkCloud.qml"
            ]
            const compiled = {}
            for (const rel of modulesToCompile) {
                const comp = Qt.createComponent(Qt.resolvedUrl(rel))
                if (comp.status !== Component.Ready) {
                    console.error("QML_COMPILE_FAIL", rel, comp.errorString())
                    Qt.exit(6)
                    return
                }
                compiled[rel] = comp
            }

            const instChecks = [
                { rel: "modules/dashboard/DashboardHeader.qml", props: ["colCardBase", "colHoverTonal"], args: {} },
                { rel: "modules/dashboard/DashboardEditToolbar.qml", props: ["colCardBase", "colHoverTonal"], args: { canvasController: canvasStub } },
                { rel: "modules/dashboard/DashboardMusic.qml", props: ["colCardBase", "colSurface", "colSurfaceHover"], args: { backend: LocalMusic } }
            ]
            for (const spec of instChecks) {
                const comp = compiled[spec.rel]
                const obj = comp.createObject(probeHost, spec.args)
                if (!obj) {
                    console.error("QML_INSTANTIATE_FAIL", spec.rel, comp.errorString())
                    Qt.exit(7)
                    return
                }
                for (const propName of spec.props) {
                    const c = Qt.color(obj[propName])
                    if (!c.valid) {
                        console.error("TONAL_PROP_INVALID", spec.rel, propName, obj[propName])
                        obj.destroy()
                        Qt.exit(8)
                        return
                    }
                }
                obj.destroy()
            }

            console.info("TONAL_STEP_RUNTIME_PASS", JSON.stringify({
                darkHue: Number(lifted.hslHue.toFixed(4)),
                darkSat: Number(lifted.hslSaturation.toFixed(4)),
                darkLight: Number(lifted.hslLightness.toFixed(4)),
                lightSat: Number(lightStep.hslSaturation.toFixed(4)),
                lightLight: Number(lightStep.hslLightness.toFixed(4)),
                compiledCount: modulesToCompile.length,
                instantiatedCount: instChecks.length
            }))
            Qt.quit()
        }
    }
}
"""
    with tempfile.TemporaryDirectory(prefix="alis-tonal-contract-") as tmp:
        folder = Path(tmp)
        for entry in ["services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
            (folder / entry).symlink_to(ROOT / entry)
        _install_offscreen_modules_overlay(folder, ROOT)
        (folder / "optional").mkdir(exist_ok=True)
        (folder / "optional" / "alis-companion").symlink_to(COMPANION_ROOT)
        (folder / "shell.qml").write_text(shell_qml, encoding="utf-8")
        config = folder / "config" / "alis"
        config.mkdir(parents=True, exist_ok=True)
        (config / "config.json").write_text((ROOT / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8")
        env = {
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QUICK_BACKEND": "software",
            "XDG_CONFIG_HOME": str(folder / "config"),
            "XDG_STATE_HOME": str(folder / "state"),
            "XDG_CACHE_HOME": str(folder / "cache"),
            "XDG_DATA_HOME": str(folder / "data"),
        }
        res = run_qs(folder, env, timeout=20)
        if res.returncode != 0 or "TONAL_STEP_RUNTIME_PASS" not in res.stdout:
            print(res.stdout)
            raise SystemExit("Headless Quickshell ColorUtils.tonalStep verification failed")


def check_abyss_reservation_parity() -> None:
    layout_path = json.dumps(str(ROOT / "modules/abyss/looks/AbyssLayout.js"))
    node_script = f"""
import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';

const layout = vm.createContext({{ Math, JSON, Number, Array, Set, Object, String, Boolean }});
const source = fs.readFileSync({layout_path}, 'utf8').replace(/^\\.pragma\\s+library\\s*$/m, '');
vm.runInContext(source, layout);

const edges = ['top', 'right', 'bottom', 'left'];
for (const edge of edges) {{
    const unified = layout.normalize([
        {{ id: 'nt', kind: 'notesTimers', edge, position: 0.22, showIcon: true }},
        {{ id: 'na', kind: 'notificationActivity', edge, position: 0.78, showIcon: true }},
    ], edge);
    const opts = {{
        edgeThickness: 10,
        edgeThicknesses: {{ top: 10, right: 10, bottom: 10, left: 10 }},
        edgeWidthAffectsModules: {{ top: true, right: true, bottom: true, left: true }},
    }};
    const paint = layout.edgeInsetsForModules(unified, opts, 1, 10, 48, false);
    const reserved = layout.edgeInsetsForModules(unified, opts, 1, 10, 48, true);
    const surfaces = layout.localSurfaces(layout.geometry(unified, 1920, 1080, opts, 1), 1920, 1080, opts, 1, 48);
    const edgeDepth = Math.max(...surfaces.filter(s => s.edge === edge).map(s => s.depth));
    for (const side of edges) {{
        assert.equal(paint[side], 10, `paint thickness stayed 10 on ${{side}}`);
        if (side === edge) {{
            assert.ok(reserved[side] >= Math.ceil(edgeDepth),
                `Module-Icon Edgebar on ${{edge}} reserved ${{reserved[side]}} < bump depth ${{edgeDepth}}`);
        }} else {{
            assert.equal(reserved[side], 10, `unrelated side ${{side}} remained 10`);
        }}
    }}

    const hoverReserved = layout.edgeInsetsForModules(unified, {{ ...opts, launcherMode: 'edgebar' }}, 1, 10, 48, true);
    for (const side of edges) {{
        assert.equal(hoverReserved[side], 10, `edgebar hover kept ${{side}} at 10`);
    }}

    const scaled = layout.normalize([
        {{ id: 'clk', kind: 'clock', edge, position: 0.5, size: 1.5 }},
    ], edge);
    const regOpts = {{
        edgeThickness: 0,
        edgeThicknesses: {{ top: 0, right: 0, bottom: 0, left: 0 }},
        edgeWidthAffectsModules: {{ top: false, right: false, bottom: false, left: false }},
    }};
    const regSurf = layout.localSurfaces(layout.geometry(scaled, 1920, 1080, regOpts, 1), 1920, 1080, regOpts, 1, 48);
    const regRes = layout.edgeInsetsForModules(scaled, regOpts, 1, 0, 48, true);
    const regDepth = Math.max(...regSurf.map(s => s.depth));
    assert.ok(regRes[edge] >= Math.ceil(regDepth),
        `scaled regular module on ${{edge}} reserved ${{regRes[edge]}} < ${{regDepth}}`);
}}
console.log('ABYSS_RESERVATION_PARITY_PASS');
"""
    res = subprocess.run(
        ["node", "--input-type=module", "-e", node_script],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0 or "ABYSS_RESERVATION_PARITY_PASS" not in res.stdout:
        print(res.stdout)
        print(res.stderr)
        raise SystemExit("AbyssLayout reservation parity Node check failed")


def main() -> None:
    check_static_contracts()
    check_tonal_step_runtime()
    check_abyss_reservation_parity()
    print("UI_BUTTON_CENTERING_AND_TONAL_CONTRACT_PASS")


if __name__ == "__main__":
    main()
