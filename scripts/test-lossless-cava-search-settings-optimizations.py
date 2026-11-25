#!/usr/bin/env python3
"""Silent regression and contract verification for lossless Cava, Abyss Wave,
Search Applications, and Settings Tab Switching optimizations.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def test_source_and_node_contracts() -> None:
    page_host = (ROOT / "modules/settings/SettingsPageHost.qml").read_text(encoding="utf-8")
    assert "layer.enabled: root._transitionRunning" not in page_host, (
        "SettingsPageHost pageLoader must not allocate transient FBO layers during tab swaps"
    )
    assert "(Config.options?.performance?.lowPower ?? false) ? 2 : 6" in page_host
    assert "idleWarmupTimer" not in page_host, (
        "SettingsPageHost must not run background idle warmup when idle/closed"
    )

    for rel in (
        "modules/bar/BarCavaEqualizerModule.qml",
        "modules/common/widgets/CavaVisualizer.qml",
        "modules/common/widgets/WaveVisualizer.qml",
        "modules/common/widgets/BarCavaVisualizer.qml",
    ):
        text = (ROOT / rel).read_text(encoding="utf-8")
        assert "FrameAnimation" not in text, f"{rel} must not run a 120Hz JS FrameAnimation smoother"
        assert "root.visible" in text and "Behavior on " in text, (
            f"{rel} must gate C++ scene-graph Behavior animations on root.visible"
        )

    wave_ctrl = (ROOT / "modules/abyss/AbyssWaveController.qml").read_text(encoding="utf-8")
    assert "putImageData" not in wave_ctrl and "createImageData" not in wave_ctrl, (
        "AbyssWaveController Canvas must paint opaque fillRect pixels instead of Qt6 alpha-0 putImageData"
    )

    abyss_field = (ROOT / "modules/abyss/looks/AbyssField.frag").read_text(encoding="utf-8")
    assert "if(i>=activeRecords)" not in abyss_field, (
        "AbyssField.frag must keep its compile-time unrolled 40-record loop"
    )

    droplet_qml = (ROOT.parent / "Alis-Companion/modules/abyss/companion/WaterDropletBody.qml")
    if droplet_qml.exists():
        droplet_text = droplet_qml.read_text(encoding="utf-8")
        assert "sharedDropletSource" not in droplet_text, (
            "WaterDropletBody.qml must not allocate a live offscreen sharedDropletSource FBO"
        )

    app_search = (ROOT / "services/AppSearch.qml").read_text(encoding="utf-8")
    fuzzy_block = app_search.split("Fuzzy.go(search, root._ensurePreppedNames(), {", 1)[1].split("})", 1)[0]
    assert "all:" not in fuzzy_block, "AppSearch.fuzzyQuery must not pass all:true for non-empty search"

    # Batch 2 contracts: Cava multi-source gating, coarse DateTime/tnum, static AbyssField layer cache
    for rel in (
        "modules/bar/BarCavaEqualizerModule.qml",
        "modules/abyss/AbyssSpectrumController.qml",
        "modules/bar/BarContent.qml",
        "modules/background/widgets/visualizer/VisualizerWidget.qml",
        "modules/background/widgets/mediaControls/MediaControlsWidget.qml",
        "modules/mediaControls/MediaControls.qml",
    ):
        text = (ROOT / rel).read_text(encoding="utf-8")
        assert "MprisController.anyAudioPlaying" in text, (
            f"{rel} must gate Cava on MprisController.anyAudioPlaying"
        )

    dt_text = (ROOT / "services/DateTime.qml").read_text(encoding="utf-8")
    assert "property date minuteDate:" in dt_text and "property date todayDate:" in dt_text
    clock_text = (ROOT / "modules/bar/ClockWidget.qml").read_text(encoding="utf-8")
    assert 'font.features: ({ "tnum": 1 })' in clock_text
    assert "root.verticalContent\n        ? String(DateTime.timeDisplay" in clock_text

    perim_text = (ROOT / "modules/abyss/AbyssPerimeter.qml").read_text(encoding="utf-8")
    assert "layer.enabled: field.ready" in perim_text
    assert 'childType.startsWith("QQuickShaderEffectSource")' in perim_text

    # AbyssWave.js exact numerical parity & hidden _spectrumCache check in Node
    node = shutil.which("node")
    if node:
        js_test = r'''
const fs = require("fs");
const vm = require("vm");
const assert = require("assert");
const code = fs.readFileSync(process.argv[1], "utf8")
    .replace(/^\.pragma library\s*/m, "");
const ctx = { Math, Number, Array, Object, Int32Array, Uint8Array, Float64Array };
vm.createContext(ctx);
vm.runInContext(code, ctx);

function bounded(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }
function refSpectrum(state, edges, points, ceiling, strength) {
    var count = points?.length || 0, changed = false, active = false;
    var maximum = Math.min(96, Math.min(state.width, state.height) * .12) * bounded(strength, 0, 4);
    var limit = Math.min(192, Math.min(state.width, state.height) * .18);
    var normalizer = Math.max(20, Number(ceiling) || 100);
    for (var i = 0; i < state.count; i++) {
        var location = i * state.length / state.count, edge, along, length;
        if (location < state.width) { edge = "top"; along = location; length = state.width; }
        else if (location < state.width + state.height) { edge = "right"; along = location - state.width; length = state.height; }
        else if (location < 2 * state.width + state.height) { edge = "bottom"; along = 2 * state.width + state.height - location; length = state.width; }
        else { edge = "left"; along = state.length - location; length = state.height; }
        var t = along / Math.max(1, length), target = 0;
        if (count && edges.indexOf(edge) >= 0 && maximum > 0) {
            var position = t * (count - 1), carrier = position * .5, lobe = Math.floor(carrier / Math.PI);
            var low = Math.min(count - 1, Math.max(0, Math.floor(lobe * 2 * Math.PI)));
            var high = Math.min(count - 1, Math.max(low, Math.ceil((lobe + 1) * 2 * Math.PI)));
            var sum = 0, span = high - low + 1;
            for (var k = low; k <= high; k++) {
                var sample = Number(points[k]);
                if (Number.isFinite(sample) && sample > 0) sum += sample;
            }
            var level = Math.sqrt(Math.max(0, Math.min(1, sum / (span * normalizer))));
            if (level > .025) target = Math.min(limit, maximum * level) * Math.sin(carrier) * Math.pow(Math.sin(t * Math.PI), 2);
        }
        if (Math.abs(target - state.spectrumTargets[i]) > .005 || (target === 0 && state.spectrumTargets[i] !== 0)) {
            changed = true; state.spectrumTargets[i] = target;
        }
        active = active || Math.abs(state.spectrumTargets[i]) > .005;
    }
    state.hasSpectrum = active;
    return changed;
}

const s1 = ctx.create(128, 1920, 1080, {});
const s2 = ctx.create(128, 1920, 1080, {});
assert(!Object.keys(s1).includes("_spectrumCache"), "_spectrumCache must remain non-enumerable");

const frames = [
    [["top", "bottom"], Array.from({length: 48}, (_, i) => (i * 41) % 900), 1000, 1.2],
    [["top", "left"], Array.from({length: 48}, (_, i) => i % 2 ? 0 : 750), 800, 1.8],
    [["top", "bottom"], Array.from({length: 64}, (_, i) => i * 18), 950, 0.9],
    [["top", "bottom"], [], 1000, 1.0],
    [["right"], Array.from({length: 48}, () => 400), 1000, 0.0],
];
for (const [edges, pts, ceil, str] of frames) {
    const c1 = ctx.spectrum(s1, edges, pts, ceil, str, 0);
    const c2 = refSpectrum(s2, edges, pts, ceil, str);
    assert.strictEqual(c1, c2, "changed flag parity");
    assert.strictEqual(s1.hasSpectrum, s2.hasSpectrum, "hasSpectrum parity");
    assert.strictEqual(s1.spectrumLimit, (pts.length && Math.min(96, Math.min(s2.width, s2.height) * .12) * bounded(str, 0, 4) > 0) ? Math.min(192, Math.min(s2.width, s2.height) * .18) : 0);
    for (let i = 0; i < s1.spectrumTargets.length; i++) {
        assert(Math.abs(s1.spectrumTargets[i] - s2.spectrumTargets[i]) < 1e-12, `target mismatch at ${i}: ${s1.spectrumTargets[i]} vs ${s2.spectrumTargets[i]}`);
    }
}
console.log("PASS: AbyssWave.js LUT parity + non-enumerable cache");
'''
        res = subprocess.run([node, "-e", js_test, str(ROOT / "modules/abyss/looks/AbyssWave.js")], check=True, text=True, capture_output=True)
        print(res.stdout.strip())
    else:
        print("SKIP: node unavailable for AbyssWave JS parity check")


QML_HARNESS = r'''//@ pragma ShellId alis-lossless-opt-test
pragma ComponentBehavior: Bound

import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.overview
import qs.modules.settings
import qs.modules.bar
import qs.modules.abyss
import qs.modules.abyss.looks
import qs.services

ShellRoot {
    id: root
    property int checks: 0

    function check(cond, msg) {
        root.checks++
        if (!cond) throw new Error(msg)
    }

    function findByObjectName(item, name) {
        if (!item) return null
        if (item.objectName === name) return item
        for (const ch of (item.children ?? [])) {
            const hit = findByObjectName(ch, name)
            if (hit) return hit
        }
        return null
    }

    Window {
        id: win
        visible: true
        width: 800
        height: 600
        color: "#111820"

        Item {
            id: sandbox
            anchors.fill: parent

        SettingsCardSection {
            id: testSection
            moduleId: "opt:test-section"
            title: "Section"

            SettingsGroup {
                id: testGroup
            }
        }

        SettingsPageHost {
            id: pageHost
            width: 480
            height: 360
            pages: [
                { name: "Page 0", icon: "settings", component: Quickshell.shellPath("opt_pages/Page0.qml") },
                { name: "Page 1", icon: "tune", component: Quickshell.shellPath("opt_pages/Page1.qml") },
                { name: "Page 2", icon: "palette", component: Quickshell.shellPath("opt_pages/Page2.qml") }
            ]
            requestedIndex: 0
        }

        SearchWidget {
            id: searchWidget
            width: 480
            height: 400
        }

        SearchItem {
            id: searchItem
            width: 320
            height: 48
            entry: ({
                name: "Example",
                icon: "firefox",
                type: "Application",
                desktopEntryId: "firefox.desktop",
                execute: function() {}
            })
        }

        CavaSpectrum {
            id: spectrum
            width: 220
            height: 44
            active: true
            frequencyProfile: "warm"
            accentStrength: 0.75
            spectrumColors: ["#3388ff", "#ff6699"]
            points: [100, 300, 600, 800, 500, 200, 120, 60]
        }

        BarCavaEqualizerModule {
            id: barEq
            width: 140
            height: 28
            visible: true
        }

        CavaVisualizer {
            id: cavaVis
            width: 180
            height: 40
            barCount: 20
            live: true
            visible: true
            points: [200, 500, 800, 400, 100]
        }

        WaveVisualizer {
            id: waveVis
            width: 180
            height: 40
            live: true
            visible: true
            points: [150, 450, 750, 350, 90]
        }

        BarCavaVisualizer {
            id: barCavaVis
            width: 240
            height: 28
            active: true
            visualizerType: "bars"
            spectrumColors: ["#44aaee", "#ff88aa"]
            points: [120, 420, 720, 320, 80]
        }

        AbyssField {
            id: abyssField
            width: 400
            height: 300
            records: []
        }

        AbyssWaveController {
            id: waveCtrl
            outputWidth: 400
            outputHeight: 300
            wavesEnabled: true
            audioEnabled: true
        }

        DefaultAppsConfig {
            id: defaultAppsPage
            width: 720
            height: 520
        }
        }
    }

    TestCase {
        id: tc
        when: false
        optional: true

        function run() {
            try {
                tryCompare(Config, "ready", true, 4000)

                // 1. SettingsCardSection & SettingsGroup stay lightweight with inert SettingsLayoutManager facade
                root.check(SettingsLayoutManager.editMode === false, "SettingsLayoutManager.editMode must stay false (Edit Layout retired)")
                SettingsLayoutManager.beginEditMode()
                wait(20)
                root.check(SettingsLayoutManager.editMode === false, "SettingsLayoutManager.beginEditMode must remain inert")
                const secOverlayHidden = testSection.children.filter(c => c.item && c.hasOwnProperty("asynchronous"))
                root.check(secOverlayHidden.length === 0, "SettingsCardSection must not load edit reorder overlays")
                const grpOverlayHidden = testGroup.children.filter(c => c.item && c.hasOwnProperty("asynchronous"))
                root.check(grpOverlayHidden.length === 0, "SettingsGroup must not load edit reorder overlays")

                // 2. SettingsSearchRegistry lazy keywords + preparedSearch
                const id1 = SettingsSearchRegistry.registerOption({
                    control: testSection, pageIndex: 0, pageName: "General", section: "Quick",
                    label: "Animation Speed", description: "Control timing", keywords: ["fast", "motion"]
                })
                const id2 = SettingsSearchRegistry.registerOption({
                    control: testGroup, pageIndex: 1, pageName: "Audio", section: "Mix",
                    label: "Visualizer", description: "Cava settings", keywords: ["cava", "wave"]
                })
                const e1 = SettingsSearchRegistry._entryById[id1]
                const e2 = SettingsSearchRegistry._entryById[id2]
                root.check(e1 && e1._preparedSearch === null, "SettingsSearchRegistry eagerly prepared search entry")
                const kw = e1.keywords
                root.check(Array.isArray(kw) && kw.length >= 2, "SettingsSearchRegistry lazy keywords failed")
                const hits = SettingsSearchRegistry.buildResults("cava")
                root.check(hits.length >= 1 && hits.some(h => h.label === "Visualizer"), "SettingsSearchRegistry search result mismatch")
                const prepBefore = e2._preparedSearch
                root.check(prepBefore !== null, "SettingsSearchRegistry did not populate _preparedSearch")
                const hits2 = SettingsSearchRegistry.buildResults("wave")
                root.check(hits2.length >= 1 && e2._preparedSearch === prepBefore, "SettingsSearchRegistry did not reuse _preparedSearch")

                // 3. SettingsPageHost cacheLimit, deduped _updateCardTabs, no background warmup
                Config.setNestedValue("performance.lowPower", false)
                root.check(pageHost.cacheLimit === 6, "SettingsPageHost default cacheLimit should be 6, got " + pageHost.cacheLimit)
                Config.setNestedValue("performance.lowPower", true)
                root.check(pageHost.cacheLimit === 2, "SettingsPageHost lowPower cacheLimit should be 2, got " + pageHost.cacheLimit)
                Config.setNestedValue("performance.lowPower", false)

                tryVerify(() => pageHost.currentItem !== null, 3000)
                root.check(pageHost.currentItem.updateCardTabsCalls === 1, "SettingsPageHost duplicate _updateCardTabs call on load: " + pageHost.currentItem.updateCardTabsCalls)
                wait(300)
                root.check(pageHost._retainedIndices.length === 1, "SettingsPageHost must not warm additional pages in background")

                // 4. StringUtils.looksLikeMathExpression & SearchWidget.wantsMathResult
                for (const appQ of ["firefox", "code", "obs", "vlc", "mp3", "2048", "terminal"]) {
                    root.check(!StringUtils.looksLikeMathExpression(appQ), "False positive math expression on app query: " + appQ)
                }
                for (const mathQ of ["=2+2", "2+2", "15 * 4", "100 usd to vnd", "50 km in mi", "sqrt(144)"]) {
                    root.check(StringUtils.looksLikeMathExpression(mathQ), "Missed math expression: " + mathQ)
                }
                root.check(!searchWidget.wantsMathResult("firefox"), "SearchWidget should not spawn qalc for firefox")
                root.check(searchWidget.wantsMathResult("2+2"), "SearchWidget should enable qalc for 2+2")
                root.check(searchWidget.wantsMathResult("=10*5"), "SearchWidget should enable qalc for =10*5")
                root.check(!searchWidget.wantsMathResult(searchWidget.prefixAction + "2+2"), "SearchWidget action prefix bypass")
                root.check(!searchWidget.wantsMathResult(searchWidget.prefixClipboard + "2+2"), "SearchWidget clipboard prefix bypass")
                root.check(!searchWidget.wantsMathResult(searchWidget.prefixEmojis + "2+2"), "SearchWidget emoji prefix bypass")

                // 5. AppSearch caching & Fuzzy.go without all:true
                const mockA = { id: "alpha.desktop", name: "Alpha Browser", icon: "firefox", comment: "", genericName: "", runInTerminal: false, command: ["alpha", "--new"] }
                const mockB = { id: "beta.desktop", name: "Beta Editor", icon: "code", comment: "", genericName: "", runInTerminal: false, command: ["beta"] }
                AppSearch._cachedList = [mockA, mockB]
                AppSearch._cachedNameLowers = ["alpha browser", "beta editor"]
                AppSearch._cacheRevision++
                const d1 = AppSearch._decorateEntry(mockA)
                const d2 = AppSearch._decorateEntry(mockA)
                root.check(d1 === d2 && d1.command.length === 2, "AppSearch._decorateEntry must return cached object per revision")
                AppSearch._cacheRevision++
                const d3 = AppSearch._decorateEntry(mockA)
                root.check(d3 !== d1, "AppSearch._decorateEntry must refresh when _cacheRevision bumps")

                const prevSloppy = AppSearch.sloppySearch
                AppSearch.sloppySearch = false
                const fuzzyHits = AppSearch.fuzzyQuery("alpha", 5)
                root.check(fuzzyHits.length >= 1 && fuzzyHits[0].id === "alpha.desktop", "AppSearch.fuzzyQuery failed without all:true")
                AppSearch.sloppySearch = prevSloppy

                const g1 = AppSearch.guessIcon("firefox")
                root.check(AppSearch._lazyPrepared.iconGuesses["firefox"] === g1, "AppSearch.guessIcon did not memoize result")
                AppSearch._cacheRevision++
                const g2 = AppSearch.guessIcon("firefox")
                root.check(g2 === g1 && AppSearch._lazyPrepared.iconGuessesRevision === AppSearch._cacheRevision, "AppSearch.guessIcon cache did not roll cleanly with _cacheRevision")

                // 6. SearchItem urls fast-path & Drag.imageSource gating
                searchItem.entry = { name: "Firefox Browser", icon: "firefox", type: "Application", execute: function() {} }
                root.check(searchItem.urls.length === 0, "SearchItem non-URL string failed urls fast-path")
                searchItem.entry = { name: "Open https://example.com/a and https://bad…", icon: "firefox", type: "Application", execute: function() {} }
                root.check(searchItem.urls.length === 1 && searchItem.urls[0] === "https://example.com/a", "SearchItem urls extraction mismatch")
                const dragItem = searchItem.children.find(c => c.Drag && c.Drag.keys && c.Drag.keys.indexOf("application/x-alis-desktop-entry") >= 0)
                root.check(dragItem && dragItem.Drag.imageSource.toString() === "", "SearchItem Drag.imageSource must stay empty while idle")

                // 7. CavaSpectrum caches & Cava smoother convergence
                const ptsA = spectrum._selectedPoints()
                const cachedWeightsA = spectrum._profileCache.weights
                const ptsB = spectrum._selectedPoints()
                root.check(ptsB.length === 8 && spectrum._profileCache.weights === cachedWeightsA, "CavaSpectrum _profileCache did not reuse weights")
                spectrum.frequencyProfile = "bass"
                const ptsC = spectrum._selectedPoints()
                root.check(spectrum._profileCache.key.indexOf("bass") >= 0 && ptsC.length === 8, "CavaSpectrum _profileCache did not update on frequencyProfile change")

                const fakeCtx = {
                    calls: 0,
                    createLinearGradient: function(x0, y0, x1, y1) {
                        this.calls++
                        return { stops: [], addColorStop: function(r, c) { this.stops.push([r, c]) } }
                    }
                }
                const gr1 = spectrum._horizontalGradient(fakeCtx, 0, 220, 1)
                const gr2 = spectrum._horizontalGradient(fakeCtx, 0, 220, 1)
                root.check(gr1 === gr2 && fakeCtx.calls === 1, "CavaSpectrum _gradientCache did not reuse CanvasGradient")
                spectrum.spectrumColor = "#00ff88"
                const gr3 = spectrum._horizontalGradient(fakeCtx, 0, 220, 1)
                root.check(gr3 !== gr1 && fakeCtx.calls === 2, "CavaSpectrum _gradientCache did not invalidate on spectrumColor change")

                Config.setNestedValue("performance.reduceAnimations", false)
                cavaVis.points = [900, 100, 700, 300]
                waveVis.points = [900, 100, 700, 300]
                barCavaVis.points = [900, 100, 700, 300]
                root.check(cavaVis._targetNormalized.length === 20, "CavaVisualizer _targetNormalized length mismatch")
                root.check(waveVis.processedBars.length === waveVis.activeBars, "WaveVisualizer processedBars length mismatch")
                root.check(barCavaVis._levels.length > 0, "BarCavaVisualizer _levels empty")

                // 8. AbyssField unrolled viewport.z === 0 + AbyssWaveController impulse & spectrum crestPeak
                const passItem = abyssField.children.find(c => c.hasOwnProperty("viewport"))
                root.check(passItem !== undefined, "AbyssField ShaderEffect pass not found")
                root.check(passItem.viewport.z === 0, "AbyssField viewport.z expected 0, got " + passItem.viewport.z)

                waveCtrl.impulse("top", 200, 80, 1.0, 1.0, "press")
                waveCtrl.feedSpectrum(["top", "bottom"], [100, 80, 95, 65, 90, 75, 100, 80], 100, 1.0, 0)
                tryVerify(() => waveCtrl.crestPeak > 0.1, 2000)
                root.check(waveCtrl.crestPeak > 0.1, "AbyssWaveController crestPeak must be > 0.1 after impulse/spectrum, got " + waveCtrl.crestPeak)

                // 9. DefaultAppsConfig lazy loading of closed dropdowns (off-tab sections stay eager for layout parity)
                root.check(defaultAppsPage.activeSection === "primary" && defaultAppsPage.openPickerSlot === "", "DefaultAppsConfig initial state mismatch")
                root.check(root.findByObjectName(defaultAppsPage, "defaultAppSearch_browser") === null, "DefaultAppsConfig must not load closed browser picker")

                defaultAppsPage.openPickerSlot = "browser"
                root.check(root.findByObjectName(defaultAppsPage, "defaultAppSearch_browser") !== null, "DefaultAppsConfig failed to instantiate browser picker on open")
                defaultAppsPage.openPickerSlot = ""
                root.check(root.findByObjectName(defaultAppsPage, "autostartServicesListView") === null, "DefaultAppsConfig must lazy-load AutostartConfig when inactive")
                defaultAppsPage.activeSection = "utilities"
                root.check(root.findByObjectName(defaultAppsPage, "defaultAppsUtilitiesCard") !== null, "DefaultAppsConfig failed to instantiate utilities card on tab switch")
                defaultAppsPage.activeSection = "autostart"
                const autostartSvcs = root.findByObjectName(defaultAppsPage, "autostartServicesListView")
                root.check(autostartSvcs !== null, "DefaultAppsConfig failed to instantiate virtualized AutostartConfig services ListView on tab switch")

                // 10. Coarse DateTime stamps & idle Cava suspension
                root.check(DateTime.minuteDate instanceof Date && !isNaN(DateTime.minuteDate.getTime()), "DateTime.minuteDate invalid")
                root.check(DateTime.todayDate instanceof Date && !isNaN(DateTime.todayDate.getTime()), "DateTime.todayDate invalid")
                root.check(!MprisController.anyAudioPlaying, "MprisController.anyAudioPlaying should be false with no audio streams")

                console.info("LOSSLESS_OPT_PASS", "checks=" + root.checks)
            } catch (err) {
                console.error("LOSSLESS_OPT_FAIL", err.message, err.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        repeat: false
        onTriggered: tc.run()
    }
}
'''


def test_quickshell_runtime() -> None:
    if not shutil.which("qs"):
        print("SKIP: Quickshell runtime check (qs unavailable)")
        return

    with tempfile.TemporaryDirectory(prefix="alis-lossless-opt-") as tmp:
        root = Path(tmp)
        for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
            (root / entry).symlink_to(ROOT / entry)

        pages_dir = root / "opt_pages"
        pages_dir.mkdir()
        for idx in range(3):
            (pages_dir / f"Page{idx}.qml").write_text(
                "import QtQuick\nItem {\n"
                "    property bool embedded: false\n"
                "    property bool _initialCardTabsSynced: false\n"
                "    property int updateCardTabsCalls: 0\n"
                "    function _restorePersistedSection() { _updateCardTabs() }\n"
                "    function _updateCardTabs() { _initialCardTabsSynced = true; updateCardTabsCalls++ }\n"
                "}\n",
                encoding="utf-8",
            )

        for kind in ("config", "state", "cache", "data"):
            (root / kind).mkdir(parents=True, exist_ok=True)
        cfg_dir = root / "config/illogical-impulse"
        cfg_dir.mkdir(parents=True, exist_ok=True)
        (cfg_dir / "config.json").write_text((ROOT / "defaults/config.json").read_text(encoding="utf-8"), encoding="utf-8")

        (root / "shell.qml").write_text(QML_HARNESS, encoding="utf-8")

        with private_wayland(root) as env:
            if env is None:
                print("SKIP: Quickshell runtime check (private_wayland unavailable)")
                return
            env.update(
                QT_QUICK_BACKEND="software",
                XDG_DATA_HOME="/nonexistent",
                XDG_DATA_DIRS="/nonexistent",
            )
            res = run_qs(root, env, timeout=25)
            if (
                res.returncode != 0
                or "LOSSLESS_OPT_PASS" not in res.stdout
                or re.search(r"LOSSLESS_OPT_FAIL|ReferenceError:|TypeError:|Binding loop|Failed to load configuration", res.stdout)
            ):
                print(res.stdout)
                sys.exit(1)
            for line in res.stdout.splitlines():
                if "LOSSLESS_OPT_PASS" in line:
                    print(line.strip())


if __name__ == "__main__":
    test_source_and_node_contracts()
    test_quickshell_runtime()
