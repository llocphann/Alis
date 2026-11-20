#!/usr/bin/env python3
"""Measure the real Settings form and exercise it as its viewport changes."""
import argparse
import json
from pathlib import Path
import tempfile

from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
QML = r'''
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings

Window {
    id: win
    visible: true
    width: 1585; height: 1068
    Component.onCompleted: Quickshell.watchFiles = false
    Rectangle { id: host; anchors.fill: parent; color: SettingsMaterialPreset.windowColor }
    SettingsOverlay { id: overlay; embeddedHost: host; settingsOpen: true }
    TestCase {
        id: test
        when: false; optional: true
        property int checks: 0
        function check(ok, reason) {
            checks++
            if (!ok) throw new Error(reason)
        }
        function first(item, predicate) {
            if (!item || !item.visible) return null
            if (predicate(item)) return item
            for (const child of item.children ?? []) {
                const result = first(child, predicate)
                if (result) return result
            }
            return null
        }
        function named(item, name) {
            return first(item, item => item.objectName === name)
        }
        function bounds(item) {
            if (!item) throw new Error("Missing geometry item")
            const point = item.mapToItem(host, 0, 0)
            return {x: point.x, y: point.y, w: item.width, h: item.height}
        }
        function capture(name) {
            let saved = false
            check(host.grabToImage(img => {
                saved = img.saveToFile(Quickshell.env("DENSITY_OUTPUT") + "/" + name + ".png")
            }), "capture refused")
            tryVerify(() => saved, 6000)
        }
        function current(index) {
            overlay.showingHome = false
            overlay.overlayCurrentPage = index
            tryVerify(() => overlay.pageHost?.currentIndex === index
                && overlay.pageHost?.currentItem && !overlay.pageHost.loading, 12000)
            wait(400)
            return overlay.pageHost.currentItem
        }
        function sliderFor(row) {
            return first(row, item => item.customLength !== undefined
                && item.sliderLayoutId !== undefined)
        }
        function measure(label, width, height, page) {
            win.width = width; win.height = height
            tryVerify(() => Math.abs(host.width - width) < 1 && Math.abs(host.height - height) < 1, 3000)
            wait(240)
            const card = first(page, item => item.title === "Perimeter & Liquid Frame"
                && item.naturalCardImplicitHeight !== undefined)
            const waves = first(page, item => item.title === "Edge Waves & Organic Reactivity"
                && item.naturalCardImplicitHeight !== undefined)
            const rows = []
            function visit(item) {
                if (!item || !item.visible) return
                if (item.currentValue !== undefined && item.valueText !== undefined
                    && item.text && item.searchKeywords !== undefined) {
                    const slider = sliderFor(item)
                    if (slider) {
                        const value = item.children.find(child => child.visible && child.text === item.valueText)
                        const label = first(item, child => child !== item && child.text === item.text)
                        rows.push({name:item.text, box:bounds(item), slider:bounds(slider),
                            value:bounds(value), label:bounds(label), stored:slider.value})
                        return
                    }
                }
                for (const child of item.children ?? []) visit(child)
            }
            visit(card)
            const data = {case:label, viewport:bounds(host), rail:bounds(named(host,"settingsOverlayNavColumn")),
                page:bounds(page), card:bounds(card), track:bounds(named(page, "settingsSectionTabTrack")), firstTab:bounds(named(page, "settingsSubTab_0")),
                waves:bounds(waves), rows:rows}
            console.info("DENSITY_MEASURE", JSON.stringify(data))
            check(rows.length === 11 && new Set(rows.map(r=>r.name)).size === 11, "Expected 11 distinct surface controls")
            capture(label)
        }
        function testStandalone() {
            const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"))
            tryVerify(() => component.status !== Component.Loading, 8000)
            check(component.status === Component.Ready, "Standalone failed to load " + component.errorString())
            const standalone = component.createObject(null, {width:1585, height:1000})
            try {
                tryVerify(() => standalone && standalone.uiReady, 10000)
                standalone.showingHome = false
                standalone.currentPage = 2
                const scene = standalone.contentItem
                const card = () => first(scene, item => item.title === "Perimeter & Liquid Frame" && item.naturalCardImplicitHeight !== undefined)
                tryVerify(() => !!card(), 8000)
                wait(250)
                const start = item => item.mapToItem(scene, 0, 0).x
                const pageHeader = first(scene, item => item.activePageItem?.settingsPageIndex === 2 && item.activeTitle !== undefined)
                const titleIcon = first(pageHeader, item => item.text === pageHeader.activeIcon && item.iconSize === 15)
                const cardX = start(card()), tabX = start(named(scene,"settingsSubTab_0"))
                console.info("DENSITY_HEADER", !!pageHeader, pageHeader?.activeTitle, pageHeader?.activeIcon, !!titleIcon, titleIcon ? start(titleIcon) : -1, cardX, tabX)
                const track = named(scene, "settingsSectionTabTrack")
                const headerAligned = titleIcon && Math.abs(cardX - start(titleIcon)) <= 36
                    && Math.abs(start(track) + track.width / 2 - cardX - card().width / 2) <= 2
                const layout = named(scene,"settingsWindowNavRail").parent.parent
                let saved = false
                check(layout.grabToImage(img => { saved = img.saveToFile(Quickshell.env("DENSITY_OUTPUT")+"/standalone.png") }), "standalone capture refused")
                tryVerify(() => saved, 5000)
                standalone.hide()
                const themes = current(4)
                const row = () => first(themes, i => i.objectName === "settingsSliderRow" && i.text === "Global animation speed")
                tryVerify(() => !!row(), 8000)
                wait(250)
                const slider = sliderFor(row())
                const wide = slider.width
                win.width = 900
                tryCompare(host, "width", 900, 3000)
                wait(240)
                const narrow = slider.width
                check(narrow >= 95, "Narrow shared slider too short")
                themes.contentY += row().mapToItem(themes,0,0).y - themes.height/2
                wait(200)
                const tap = slider.mapToItem(host, slider.width/2, slider.height/2)
                check(tap.x > 0 && tap.x < host.width && tap.y > 0 && tap.y < host.height,
                    "Global animation speed unreachable")
                const before = Config.options.appearance.animationSpeed.movement
                win.requestActivate()
                wait(100)
                mouseClick(slider, slider.width * (before > 1.25 ? .16 : .84), slider.height/2)
                console.info("DENSITY_TAP", tap.x, tap.y, themes.contentY, themes.height, before, slider.value, Config.options.appearance.animationSpeed.movement)
                tryVerify(() => Math.abs(Config.options.appearance.animationSpeed.movement - before) > .15, 2500)
                const pref = Config.options.appearance.animationSpeed.movement
                for (const key of ["enterExit","clickBounce","scroll"])
                    check(Config.options.appearance.animationSpeed[key] === pref, "Motion speed group changed semantics")
                const id = slider.sliderLayoutId
                SettingsLayoutManager.updateSliderConfig(id,{length:167})
                tryVerify(() => Math.abs(slider.width-167) <= 1, 2500)
                SettingsLayoutManager.toggleSliderOrientation(id)
                tryVerify(() => slider.isVertical && slider.height >= 165, 2500)
                SettingsLayoutManager.resetSlider(id)
                win.width = 1585
                tryVerify(() => !slider.isVertical && Math.abs(slider.width-wide) <= 2, 3000)
                check(Config.options.appearance.animationSpeed.movement === pref, "Preference changed during shared-row layout edits")
                console.info("DENSITY_SHARED", JSON.stringify({wide:wide,narrow:narrow,cardX:cardX,tabX:tabX}))
                check(headerAligned, "Standalone page header or centered tabs misaligned")
                check(wide > narrow + 40 && wide >= 260, "Shared slider did not expand on wide viewport")
            } finally { if (standalone) standalone.destroy() }
        }
        function run() {
            try {
                tryCompare(Config, "ready", true, 8000)
                tryCompare(Persistent, "ready", true, 8000)
                tryCompare(overlay, "_navigationInitialized", true, 8000)
                if (Quickshell.env("DENSITY_ENTRY") === "standalone") {
                    testStandalone()
                    console.info("DENSITY_PASS", checks)
                    Qt.quit()
                    return
                }
                const page = current(2)
                measure("wide",1585,1068,page)
                const row = named(page, "abyssPanelOpacity"), slider = sliderFor(row)
                const initial = slider.value
                mouseClick(slider, slider.width * (initial > .5 ? .24 : .76), slider.height/2)
                tryVerify(() => Math.abs(Config.options.abyss.content.opacity - initial) > .15, 2000)
                const changed = Config.options.abyss.content.opacity
                measure("standard",1220,820,page)
                measure("narrow",760,650,page)
                check(Math.abs(slider.value-changed) < .011, "Resizing changed the material preference")
                const lastRow = named(page, "abyssShadowStrength")
                const lastSlider = sliderFor(lastRow)
                const lastPos = lastRow.mapToItem(page, 0, 0).y
                page.contentY += Math.max(0, lastPos - page.height/2)
                wait(120)
                const visiblePos = lastSlider.mapToItem(page, 0, lastSlider.height/2).y
                check(visiblePos > 0 && visiblePos < page.height, "Last control unreachable after scrolling")
                mouseClick(lastSlider, lastSlider.width * .52, lastSlider.height/2)
                tryVerify(() => Math.abs(Config.options.abyss.effects.shadowStrength - .26) < .03, 2000)
                page.contentY = 0
                measure("reopened-width",1585,1068,page)
                const key = slider.sliderLayoutId
                check(key.length > 0, "Slider lacks a customization id")
                SettingsLayoutManager.updateSliderConfig(key, {length:154})
                tryVerify(() => slider.customLength === 154, 3000)
                wait(100)
                check(Math.abs(slider.width-154) < 2, "Horizontal custom slider length lost")
                SettingsLayoutManager.toggleSliderOrientation(key)
                tryVerify(() => slider.isVertical, 3000)
                wait(100)
                check(slider.height > slider.width && slider.height >= 152, "Vertical slider dimensions lost")
                SettingsLayoutManager.resetSlider(key)
                tryVerify(() => !slider.isVertical && slider.customLength === 0, 3000)
                check(Math.abs(slider.value-changed) < .011, "Layout customization changed preference")
                Config.setNestedValue("panelFamily", "waffle")
                const appearance = current(4)
                check(!!named(host,"waffleSettingsBreadcrumbHeader") && !!named(appearance,"contentColumn"),
                    "Waffle route or breadcrumb missing after family change")
                capture("waffle")
                console.info("DENSITY_PASS", checks)
            } catch (error) { console.error("DENSITY_FAIL", error.message, error.stack) }
            Qt.quit()
        }
    }
    Timer { interval: 150; running: true; onTriggered: test.run() }
}
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--font-scale', type=float, default=1)
    parser.add_argument('--entry', choices=['overlay', 'standalone'], default='overlay')
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="alis-form-") as tmp:
        folder = Path(tmp)
        for name in ('modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'scripts', 'defaults', 'translations', 'settings.qml'):
            (folder/name).symlink_to(args.root.resolve()/name)
        (folder/'shell.qml').write_text(QML)
        with private_wayland(folder) as env:
            if not env or env.get('QT_QPA_PLATFORM') != 'wayland':
                raise RuntimeError('Requires private native Wayland')
            config = json.loads((args.root/'defaults/config.json').read_text())
            config['panelFamily'] = 'abyss'
            config.setdefault('appearance', {}).setdefault('typography', {})['sizeScale'] = args.font_scale
            config.setdefault('weather', {})['enable'] = False
            config.setdefault('abyss', {}).setdefault('companion', {})['enabled'] = False
            for name in ('alis','illogical-impulse'):
                path = folder/'config'/name/'config.json'
                path.parent.mkdir(exist_ok=True, parents=True)
                path.write_text(json.dumps(config))
            result = run_qs(folder, dict(env, DENSITY_OUTPUT=str(output), DENSITY_ENTRY=args.entry), timeout=85)
    (output/'runtime.log').write_text(result.stdout)
    records = [json.loads(line.split('DENSITY_MEASURE ',1)[1])
               for line in result.stdout.splitlines() if 'DENSITY_MEASURE ' in line]
    (output/'geometry.json').write_text(json.dumps(records, indent=2)+'\n')
    for sample in records:
        print(sample['case'], 'page', sample['page']['w'], 'card', sample['card']['w'],
              'first slider', sample['rows'][0]['slider']['w'])
    for line in result.stdout.splitlines():
        if 'DENSITY_PASS' in line or 'DENSITY_FAIL' in line:
            print(line)
    if args.entry == 'standalone':
        summary = [line.split('DENSITY_SHARED ',1)[1] for line in result.stdout.splitlines() if 'DENSITY_SHARED ' in line]
        warnings = [line for line in result.stdout.splitlines()
                    if 'SettingsSliderRow' in line and 'recursive rearrange' in line]
        (output/'standalone.json').write_text(json.dumps({
            'geometry': json.loads(summary[0]) if summary else None,
            'recursiveRearrangements': warnings,
        }, indent=2)+'\n')
        if warnings:
            print('FAIL: shared slider recursively rearranged during resize')
        if (result.returncode or len(summary) != 1 or 'DENSITY_PASS' not in result.stdout
                or 'DENSITY_FAIL' in result.stdout or warnings):
            raise SystemExit(1)
        return
    if result.returncode or len(records)!=4 or 'DENSITY_PASS' not in result.stdout or 'DENSITY_FAIL' in result.stdout:
        raise SystemExit(1)

    failures = []
    def expect(ok, description):
        if not ok:
            failures.append(description)

    def right(box):
        return box['x'] + box['w']

    by_case = {sample['case']: sample for sample in records}
    for case, sample in by_case.items():
        card, page = sample['card'], sample['page']
        expect(card['x'] - page['x'] <= 45 and right(page)-right(card) <= 50,
               f'{case}: excessive outer card gutter')
        track = sample['track']
        expect(abs(2 * track['x'] + track['w'] - 2 * card['x'] - card['w']) <= 4,
               f'{case}: section tabs not centered over content')
        expect(abs(sample['firstTab']['x'] - track['x']) <= 10, f'{case}: first tab outside track')
        for row in sample['rows']:
            label, track, value = row['label'], row['slider'], row['value']
            expect(right(label) <= track['x']+1 and right(track) <= value['x']+1,
                   f"{case}: overlapping label/slider/readout for {row['name']}")
            expect(track['w'] >= 64 and value['w'] >= 30,
                   f"{case}: narrow slider or readout for {row['name']}")
            expect(right(value) <= right(card) and label['x'] >= card['x'],
                   f"{case}: control outside card for {row['name']}")
        # The first five material controls each occupy a full row in the default form.
        for row in sample['rows'][:5]:
            expect(0 <= right(card)-right(row['value']) <= 36*args.font_scale,
                   f"{case}: readout leaves trailing void for {row['name']}")
        tuning = {row['name']:row['box'] for row in sample['rows'][5:]}
        paired = abs(tuning['Curvature']['y']-tuning['Fusion softness']['y']) < 1
        if case in ('wide','reopened-width'):
            expect(paired and tuning['Fusion softness']['x'] >= right(tuning['Curvature']),
                   f'{case}: tuning controls did not form two columns')
        if case == 'narrow':
            expect(not paired, f'{case}: tuning controls should stack')
    expect(abs(by_case['wide']['card']['h']-by_case['reopened-width']['card']['h']) <= 2,
           'Same viewport has different card height after resize')
    (output/'checks.json').write_text(json.dumps({'failures':failures}, indent=2)+'\n')
    if failures:
        print('FAIL layout:', '\n'.join(failures))
        raise SystemExit(1)
    print('PASS responsive layout')


if __name__ == '__main__':
    main()
