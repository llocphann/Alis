#!/usr/bin/env python3
"""Private Wayland proof for Waffle Win11 Fluent Settings and Waffle panel routes."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
QML = r'''
import QtQuick
import QtQuick.Layouts
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.models.quickToggles
import qs.modules.settings
import qs.modules.waffle.looks as Waffle
import qs.modules.waffle.onScreenDisplay as WaffleOsd
import qs.modules.waffle.startMenu as WaffleStart
import qs.modules.waffle.actionCenter.mainPage as WaffleAcMain
import qs.modules.waffle.actionCenter.toggles as WaffleAcToggles
import qs.services

Window {
    id: win
    visible: true; width: 1240; height: 900
    color: SettingsMaterialPreset.windowColor
    Component.onCompleted: Quickshell.watchFiles = false
    Rectangle { id: host; anchors.fill: parent; anchors.bottomMargin: 62; color: SettingsMaterialPreset.windowColor }
    SettingsOverlay { id: overlay; embeddedHost: host; settingsOpen: true }
    ConfigSwitch {
        id: row
        objectName: "testWaffleSettingsSwitchRow"
        anchors.bottom: parent.bottom; anchors.left: parent.left
        anchors.right: parent.right; anchors.margins: 12
        text: "Fixture preference"; description: "Keyboard and pointer input"
        checked: Config.options?.waffles?.tweaks?.switchHandlePositionFix ?? true
        autoToggle: false
        onToggledByUser: checked => { test.toggleCount++; Config.setNestedValue("waffles.tweaks.switchHandlePositionFix", checked) }
    }
    WaffleOsd.OSDValue {
        id: osdProbe
        visible: false
        iconName: "speaker-2-filled"
        value: 1.0
        showNumber: true
    }
    WaffleStart.StartPageContent {
        id: startProbe
        visible: false
        width: 640
        height: 680
    }
    WaffleAcMain.MainPageFooter {
        id: acFooterProbe
        visible: false
        width: 360
        height: 48
    }
    QuickToggleModel {
        id: dummyToggleModel
        name: "Test Toggle"
        hasMenu: true
    }
    WaffleAcToggles.ActionCenterToggleButton {
        id: acToggleProbe
        visible: false
        toggleModel: dummyToggleModel
        icon: "wifi-4"
    }
    TestCase {
        id: test
        when: false; optional: true
        property int checks: 0
        property int failures: 0
        property int toggleCount: 0
        function visibleChild(item, name) {
            if (!item) return null
            if (item.objectName === name && item.visible && item.width > 0 && item.height > 0) return item
            for (const child of item.children ?? []) {
                const match = visibleChild(child, name)
                if (match) return match
            }
            return null
        }
        function anyChild(item, name) {
            if (!item) return null
            if (item.objectName === name) return item
            for (const child of item.children ?? []) {
                const match = anyChild(child, name)
                if (match) return match
            }
            return null
        }
        function check(ok, label) {
            checks++
            console.info(ok ? "WAFFLE_SETTINGS_PASS" : "WAFFLE_SETTINGS_FAIL", label)
            if (!ok) failures++
        }
        function capture(item, name) {
            let done = false
            check(item.grabToImage(result => { result.saveToFile(Quickshell.env("PROOF_DIR") + "/" + name + ".png"); done = true }), "capture request " + name)
            tryVerify(() => done, 5000)
        }
        function run() {
            try {
                console.info("WAFFLE_SETTINGS_PHASE", "starting")
                tryCompare(Config, "ready", true, 7000)
                tryCompare(Persistent, "ready", true, 7000)
                tryCompare(overlay, "_navigationInitialized", true, 7000)
                overlay.showingHome = false
                overlay.overlayCurrentPage = 4
                tryVerify(() => overlay.pageHost && overlay.pageHost.currentIndex === 4 && overlay.pageHost.currentItem && !overlay.pageHost.loading, 12000)
                wait(600)

                // 1. Fluent tokens & Win11 card/rail metrics
                check(SettingsMaterialPreset.waffle, "Waffle family tokens active")
                check(SettingsMaterialPreset.cardRadius === 8 && SettingsMaterialPreset.searchRadius === 4 && SettingsMaterialPreset.navItemRadius === 6, "Win11 Fluent card/search/nav radii (8/4/6)")
                check(SettingsMaterialPreset.pageSpacing === 4, "Win11 4px stacked card spacing")
                check(SettingsMaterialPreset.cardColor.toString() === "#2b2b2b" && SettingsMaterialPreset.cardBorderColor.toString() === "#353535", "Win11 dark card #2B2B2B fill and #353535 border")
                check(!!findChild(row, "waffleSettingsSwitch"), "Waffle switch loaded")

                // 2. Left rail (~280px), User Account Header, "Find a setting" search + focus accent underline, 3px left accent bar
                const navRail = visibleChild(host, "settingsOverlayNavColumn")
                check(navRail && Math.abs(navRail.width - 280) <= 4, "Win11 left navigation rail ~280px (" + (navRail?.width ?? -1) + ")")
                const accountHeader = visibleChild(host, "waffleSettingsAccountHeader")
                const accountName = visibleChild(host, "waffleSettingsAccountName")
                const accountSub = visibleChild(host, "waffleSettingsAccountSubtitle")
                check(accountHeader && accountName && accountName.text.length > 0 && accountSub && accountSub.text.length > 0, "Win11 top user account header mounted")

                const searchBox = visibleChild(host, "waffleSettingsSearchBox")
                const searchInput = visibleChild(host, "waffleSettingsSearchInput")
                const searchUnderline = visibleChild(host, "waffleSettingsSearchUnderline")
                check(searchBox && searchInput && searchUnderline && searchUnderline.height === 1, "Win11 Find a setting search input mounted")
                win.requestActivate()
                wait(80)
                mouseClick(searchInput, 20, searchInput.height / 2)
                searchInput.forceActiveFocus()
                wait(200)
                if (win.active) {
                    check(searchInput.activeFocus && searchUnderline.height === 2 && searchUnderline.color.toString() === SettingsMaterialPreset.accentColor.toString(), "Win11 search bottom accent underline activates on focus")
                } else {
                    check(searchInput.focus, "Win11 search input accepts focus in headless QPA")
                }
                searchInput.text = "taskbar"
                wait(200)
                check(overlay.overlaySearchResults.length > 0, "Win11 search populates live results")
                searchInput.text = ""
                overlay.openOverlaySearchResult({})
                searchInput.focus = false
                wait(200)

                const selIndicator = visibleChild(host, "waffleSettingsSelectionIndicator")
                check(selIndicator && selIndicator.width === 3 && selIndicator.height >= 14 && selIndicator.color.toString() === SettingsMaterialPreset.accentColor.toString(), "Win11 3px vertical accent pill bar on selected nav item")
                const activeNavBtn = selIndicator ? selIndicator.parent : null
                check(activeNavBtn && activeNavBtn.height >= 36 && activeNavBtn.height <= 42 && activeNavBtn.buttonRadius === 6, "Win11 category item height (36-40px) and 6px radius")

                // 3. Win11 28px Semibold Breadcrumb Header + Left-aligned Sub-category Pivot
                const breadcrumb = visibleChild(host, "waffleSettingsBreadcrumbHeader")
                const breadcrumbLeaf = visibleChild(host, "waffleSettingsBreadcrumbLeaf")
                const breadcrumbRoot = visibleChild(host, "waffleSettingsBreadcrumbRoot")
                check(breadcrumb && breadcrumbLeaf && breadcrumbLeaf.font.pixelSize === 28 && breadcrumbLeaf.font.weight === Font.DemiBold, "Win11 28px Semibold page breadcrumb header")
                check(breadcrumb && breadcrumb.showSubPageCrumb && breadcrumbRoot && breadcrumb.fullBreadcrumbText.indexOf("Appearance >") === 0, "Win11 breadcrumb shows Category > Sub-tab: " + (breadcrumb?.fullBreadcrumbText ?? ""))

                const originalPage = overlay.pageHost.currentItem
                const firstTab = visibleChild(host, "settingsSubTab_0")
                const nextTab = visibleChild(host, "settingsSubTab_1")
                capture(host, "waffle-initial")
                check(firstTab && nextTab && visibleChild(host, "waffleSettingsTabIndicator"), "Fluent tab navigation mounted")
                const initialCrumb = breadcrumb.fullBreadcrumbText
                mouseClick(nextTab)
                tryVerify(() => overlay.pageHost.currentItem !== originalPage || !firstTab.isCurrent, 7000)
                wait(350)
                check(breadcrumb.fullBreadcrumbText !== initialCrumb, "Win11 breadcrumb updates when switching sub-tab")
                mouseClick(visibleChild(host, "waffleSettingsBreadcrumbRoot"))
                tryVerify(() => overlay.pageHost.currentIndex === 4 && overlay.pageHost.currentItem && !overlay.pageHost.loading, 12000)
                wait(400)
                check(breadcrumb.fullBreadcrumbText === initialCrumb, "Clicking Win11 breadcrumb root returns to category hub")

                // 4. ConfigSwitch & WSwitch behavioral checks
                const old = row.checked
                mouseClick(row, 100, row.height/2)
                tryCompare(row, "checked", !old, 1000)
                check(toggleCount === 1, "row click toggles once")
                const indicator = findChild(row, "waffleSettingsSwitch")
                mouseClick(indicator)
                tryCompare(row, "checked", old, 1000)
                check(toggleCount === 2, "indicator click toggles once")
                row.forceActiveFocus(); keyClick(Qt.Key_Space); wait(100)
                check(row.checked === !old && toggleCount === 3, "Space toggles once")
                row.enabled = false
                mouseClick(row, 100, row.height/2)
                check(toggleCount === 3, "disabled control never toggles")
                row.enabled = true
                mouseClick(row, 100, row.height/2)
                check(row.checked === old && toggleCount === 4, "preference restored")

                // 5. Light & Dark mode Win11 palettes (end on dark so full dark palette remains active)
                for (const dark of [false, true]) {
                    const palette = dark
                        ? {darkmode:true,m3background:"#15141b",m3surface:"#17161d",m3surfaceContainerLow:"#201f27",m3surfaceContainer:"#282731",m3onSurface:"#e8e0eb",m3onSurfaceVariant:"#ccc4d0",m3primary:"#60cdff",m3onPrimary:"#003549",m3primaryContainer:"#004d68",m3onPrimaryContainer:"#bce9ff"}
                        : {darkmode:false,m3background:"#f7f4f7",m3surface:"#faf7fa",m3surfaceContainerLow:"#f2eff2",m3surfaceContainer:"#ebe8ed",m3onSurface:"#1b1b20",m3onSurfaceVariant:"#49464e",m3primary:"#005fb8",m3onPrimary:"#ffffff",m3primaryContainer:"#d4e3ff",m3onPrimaryContainer:"#001c3a"}
                    for (const key in palette) Appearance.m3colors[key] = palette[key]
                    wait(350)
                    check(SettingsMaterialPreset.textColor.toString() === Waffle.Looks.colors.fg.toString(), "palette follows Waffle " + dark)
                    if (dark) {
                        check(SettingsMaterialPreset.cardColor.toString() === "#2b2b2b" && SettingsMaterialPreset.cardBorderColor.toString() === "#353535", "dark mode card tokens (#2B2B2B / #353535)")
                    } else {
                        check(SettingsMaterialPreset.cardColor.toString() === "#fbfbfb" && SettingsMaterialPreset.cardBorderColor.toString() === "#e5e5e5", "light mode card tokens (#FBFBFB / #E5E5E5)")
                    }
                    capture(host, dark ? "waffle-dark" : "waffle-light")
                }

                // 6. Narrow responsive rail check
                win.width = 900; win.height = 720
                wait(400)
                const nav = findChild(host, "settingsOverlayNavColumn")
                check(nav && nav.width > 0 && nav.width < host.width/2, "narrow navigation leaves content space")
                check(overlay.pageHost.currentItem.width > 0, "narrow page remains mounted")
                capture(host, "waffle-narrow")
                win.width = 1240; win.height = 900
                wait(250)

                // 7. Abyss round-trip preservation
                Config.setNestedValue("panelFamily", "abyss")
                wait(350)
                check(!SettingsMaterialPreset.waffle && !findChild(row, "waffleSettingsSwitch"), "Abyss restores original control")
                const before = row.checked
                mouseClick(row, 100, row.height/2); wait(100)
                check(row.checked !== before && toggleCount === 5, "Abyss click preserved")
                Config.setNestedValue("panelFamily", "waffle")
                wait(350)
                check(!!findChild(row, "waffleSettingsSwitch") && row.checked !== before, "family round trip keeps preference")
                mouseClick(row, 100, row.height/2); wait(100)

                // 8. Waffle surface Settings launch routes & non-clipping OSD/buttons
                Config.setNestedValue("settingsUi.overlayMode", true)
                GlobalStates.searchOpen = true
                GlobalStates.waffleActionCenterOpen = true
                GlobalStates.waffleWidgetsOpen = true
                Waffle.WaffleNavigation.openSettings("waffle-style", "taskbar")
                tryVerify(() => overlay.overlayCurrentPage === 11 && overlay.pageHost && overlay.pageHost.currentIndex === 11 && overlay.pageHost.currentItem && !overlay.pageHost.loading, 12000)
                check(!GlobalStates.searchOpen && !GlobalStates.waffleActionCenterOpen && !GlobalStates.waffleWidgetsOpen && GlobalStates.settingsOverlayOpen, "WaffleNavigation closes transient flyouts and opens Taskbar settings (page 11)")
                Waffle.WaffleNavigation.openSettings("about", "")
                tryVerify(() => overlay.overlayCurrentPage === 40 && overlay.pageHost && overlay.pageHost.currentIndex === 40 && overlay.pageHost.currentItem && !overlay.pageHost.loading, 12000)
                check(overlay.overlayCurrentPage === 40, "WaffleNavigation routes About quick link to page 40")
                if (Quickshell.env("QT_QPA_PLATFORM") !== "offscreen") {
                    Waffle.WaffleNavigation.openSettings("system", "Battery")
                    tryVerify(() => overlay.overlayCurrentPage === 1 && overlay.pageHost && overlay.pageHost.currentIndex === 1 && overlay.pageHost.currentItem && !overlay.pageHost.loading, 12000)
                    check(overlay.overlayCurrentPage === 1, "WaffleNavigation routes Battery button to System settings (page 1)")
                } else {
                    check(SettingsPageRegistry.pageIndexForKey("system") === 1, "System route resolves to page 1")
                }

                const osdLabel = anyChild(osdProbe, "osdValueLabel")
                check(osdLabel && osdLabel.text === "100" && osdLabel.implicitWidth >= 20 && !osdLabel.truncated, "Waffle OSD 100 value fits without clipping")
                check(!!anyChild(startProbe, "waffleStartSettingsButton") && !!anyChild(acFooterProbe, "waffleActionCenterSettingsButton"), "Start Menu and Action Center Settings buttons mounted")
                let menuCallSafe = true
                try { acToggleProbe.openMenu() } catch (err) { menuCallSafe = false }
                check(menuCallSafe, "ActionCenterToggleButton.openMenu executes without TypeError")

                // 9. Standalone settings.qml window uses identical Win11 Fluent chrome & waits for page load
                const component = Qt.createComponent(Qt.resolvedUrl("settings.qml"))
                tryVerify(() => component.status !== Component.Loading, 12000)
                check(component.status === Component.Ready, "standalone Settings compiles: " + component.errorString())
                if (component.status === Component.Ready) {
                    const standalone = component.createObject(null, {width: 1200, height: 820})
                    tryVerify(() => standalone && standalone.uiReady, 12000)
                    wait(900)
                    const rail = findChild(standalone.contentItem, "settingsWindowNavRail")
                    const winAccount = findChild(standalone.contentItem, "waffleSettingsAccountHeader")
                    const winSearch = findChild(standalone.contentItem, "waffleSettingsSearchBox")
                    const winCrumb = findChild(standalone.contentItem, "waffleSettingsBreadcrumbHeader")
                    check(rail && rail.width >= 260 && winAccount && winSearch && winCrumb, "standalone Win11 rail + account + search + breadcrumb mounted")
                    capture(rail.parent.parent, "waffle-window")
                    standalone.destroy()
                }
            } catch(e) { failures++; console.error("WAFFLE_SETTINGS_FAIL", e.message, e.stack) }
            console.info("WAFFLE_SETTINGS_DONE", checks, failures)
            Qt.quit()
        }
    }
    Timer { interval: 300; running: true; onTriggered: test.run() }
}
'''

@contextmanager
def headless_mutter_wayland(folder: Path):
    mutter = shutil.which('mutter')
    dbus_run = shutil.which('dbus-run-session')
    if not mutter or not dbus_run:
        yield None
        return
    rt = folder / '.mutter-runtime'
    rt.mkdir(mode=0o700, exist_ok=True)
    sock_name = 'wayland-waffle-headless-0'
    sock_path = rt / sock_name
    menv = {k: v for k, v in os.environ.items() if k not in ('WAYLAND_DISPLAY', 'DISPLAY', 'NIRI_SOCKET', 'HYPRLAND_INSTANCE_SIGNATURE', 'QT_QPA_PLATFORM', 'QT_QUICK_BACKEND')}
    menv.update(XDG_RUNTIME_DIR=str(rt), GVFS_DISABLE_FUSE='1', NO_AT_BRIDGE='1')
    proc = subprocess.Popen(
        [dbus_run, '--', mutter, '--wayland', '--headless', '--no-x11', '--virtual-monitor', '1920x1080', '--wayland-display', sock_name],
        env=menv,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 10.0
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                yield None
                return
            if sock_path.exists():
                break
            time.sleep(0.05)
        else:
            yield None
            return
        qenv = dict(menv, WAYLAND_DISPLAY=sock_name, ALIS_TEST_WAYLAND_SOCKET=str(sock_path), QT_QPA_PLATFORM='wayland')
        yield qenv
    finally:
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=3)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except Exception:
                    pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scale', default='1')
    args = parser.parse_args()
    folder = args.output.resolve(); folder.mkdir(parents=True, exist_ok=False)
    for name in ('modules', 'services', 'GlobalStates.qml', 'qmldir', 'assets', 'scripts', 'defaults', 'translations', 'settings.qml'):
        (folder/name).symlink_to(args.root.resolve()/name)
    (folder/'shell.qml').write_text(QML)
    saved_qpa_platform = os.environ.pop('QT_QPA_PLATFORM', None)
    saved_quick_backend = os.environ.pop('QT_QUICK_BACKEND', None)
    config = json.loads((args.root/'defaults/config.json').read_text())
    config['panelFamily'] = 'waffle'
    config.setdefault('waffles', {}).setdefault('theming', {})['useMaterialColors'] = False
    config.setdefault('abyss', {}).setdefault('companion', {})['enabled'] = False
    config.setdefault('weather', {})['enable'] = False
    for relative in ('config/alis/config.json', 'config/illogical-impulse/config.json'):
        p=folder/relative; p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(config))
    try:
        try:
            with private_wayland(folder) as env:
                if env is None: raise RuntimeError('Native private Wayland unavailable')
                run_env = dict(env, PROOF_DIR=str(folder), QT_SCALE_FACTOR=args.scale)
                result = run_qs(folder, run_env, timeout=90)
                native_used = True
        except RuntimeError:
            with headless_mutter_wayland(folder) as menv:
                if menv is not None:
                    run_env = dict(menv, PROOF_DIR=str(folder), QT_SCALE_FACTOR=args.scale)
                    result = run_qs(folder, run_env, timeout=90)
                    native_used = True
                else:
                    fallback_env = {k: v for k, v in os.environ.items() if k not in ('WAYLAND_DISPLAY', 'DISPLAY')}
                    fallback_env.update(QT_QPA_PLATFORM='offscreen', PROOF_DIR=str(folder), QT_SCALE_FACTOR=args.scale)
                    if saved_quick_backend:
                        fallback_env['QT_QUICK_BACKEND'] = saved_quick_backend
                    result = run_qs(folder, fallback_env, timeout=90)
                    native_used = False
    finally:
        if saved_qpa_platform is not None:
            os.environ['QT_QPA_PLATFORM'] = saved_qpa_platform
        if saved_quick_backend is not None:
            os.environ['QT_QUICK_BACKEND'] = saved_quick_backend
    (folder/'runtime.log').write_text(result.stdout)
    lines = [l for l in result.stdout.splitlines() if 'WAFFLE_SETTINGS_' in l or 'Error:' in l or 'caused by' in l]
    print('\n'.join(lines))
    passed = result.returncode == 0 and 'WAFFLE_SETTINGS_DONE' in result.stdout and 'WAFFLE_SETTINGS_FAIL' not in result.stdout
    (folder/'receipt.json').write_text(json.dumps({'passed':passed,'exitCode':result.returncode,'root':str(args.root),'nativeWayland':native_used,'scale':args.scale},indent=2))
    raise SystemExit(0 if passed else 1)

if __name__ == '__main__': main()
