#!/usr/bin/env python3
"""Runtime verification of Abyss Screen Edge Quick Actions mic meter bar."""
from __future__ import annotations

import json
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="alis-abyss-mic-meter-") as tmp:
        folder = Path(tmp)
        for entry in (
            "modules",
            "services",
            "GlobalStates.qml",
            "qmldir",
            "assets",
            "scripts",
            "defaults",
            "translations",
        ):
            (folder / entry).symlink_to(ROOT / entry)

        (folder / "shell.qml").write_text(
            r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.bar
import qs.modules.abyss.looks

ShellRoot {
    id: root
    property string edge: "top"
    property int checks: 0
    property int frames: 0
    Component.onCompleted: Quickshell.watchFiles = false

    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 960
        implicitHeight: 640
        color: "#111820"

        Item {
            id: scene
            anchors.fill: parent

            AbyssBarModule {
                id: module
                kind: "utilButtons"
                attachedEdge: root.edge
                vertical: root.edge === "left" || root.edge === "right"
                outputName: window.screen?.name ?? ""
                contentScale: 1
                width: contentVertical ? 32 * Appearance.fontSizeScale : Math.max(40, naturalSpan)
                height: contentVertical ? Math.max(40, naturalSpan) : 32 * Appearance.fontSizeScale
                x: (scene.width - width) / 2
                y: (scene.height - height) / 2
            }
        }
    }

    TestCase {
        id: test
        when: false
        optional: true

        SignalSpy {
            id: micClickSpy
            signalName: "micClicked"
        }

        function check(cond, msg) {
            root.checks++
            if (!cond)
                throw new Error(msg)
        }

        function findByAccessible(node, substr) {
            if (!node)
                return null
            const acc = String(node.Accessible?.name ?? "")
            if (acc.indexOf(substr) >= 0)
                return node
            const kids = node.children ?? []
            for (let i = 0; i < kids.length; ++i) {
                const found = findByAccessible(kids[i], substr)
                if (found)
                    return found
            }
            return null
        }

        function collectControlLoaders(grid, micLoader) {
            const out = []
            const kids = grid.children ?? []
            for (let i = 0; i < kids.length; ++i) {
                const child = kids[i]
                if (child && child !== micLoader && child.active !== undefined && child.active)
                    out.push(child)
            }
            return out
        }

        function run() {
            try {
                tryCompare(Config, "ready", true, 5000)
                Config.setNestedValues({
                    "performance.reduceAnimations": false,
                    "bar.utilButtons.showMicToggle": true,
                    "bar.utilButtons.showScreenSnip": true,
                    "bar.utilButtons.showScreenRecord": true,
                    "bar.utilButtons.showNotepad": true,
                    "bar.utilButtons.showDarkModeToggle": true,
                    "bar.utilButtons.showUtilitiesLauncher": true
                })

                tryVerify(() => module.feature !== null, 5000)
                const util = module.feature
                check(util.abyssMicMeterEnabled === true, "abyssMicMeterEnabled not enabled on AbyssBarModule")

                let micBtn = null
                tryVerify(() => {
                    micBtn = findByAccessible(util, "microphone")
                    const expectedMin = (util.visibleUtilityCount * 26 + Math.max(0, util.visibleUtilityCount - 1) * 4) * Appearance.sizes.barModuleScale - 2
                    return util.micSlotActive
                        && util.visibleUtilityCount === 7
                        && micBtn !== null
                        && micBtn.width > 0
                        && util.expandedMainAxisLength >= expectedMin
                        && Math.abs(module.naturalSpan - util.expandedMainAxisLength) < 0.01
                }, 4000)

                const meterLoader = findChild(util, "abyssMicMeterLoader")
                check(meterLoader !== null && meterLoader.item !== null, "abyssMicMeterLoader did not load")
                const meterBar = meterLoader.item
                // Prevent spawning live pw-cat in headless test environment during UI state checks
                meterBar.levelOverride = 0.0
                meterBar.peakOverride = 0.0

                const micLoader = micBtn.parent
                const controlsGrid = micLoader.parent
                const controlsStage = controlsGrid.parent
                const pill = findChild(meterBar, "abyssMicMeterPill")
                const track = findChild(meterBar, "abyssMicMeterTrack")
                const levelFill = findChild(meterBar, "abyssMicMeterLevelFill")
                const peakMarker = findChild(meterBar, "abyssMicMeterPeakMarker")
                const pinBtn = findChild(meterBar, "abyssMicMeterPinButton")
                const micBtnOnBar = findChild(meterBar, "abyssMicMeterMicButton")
                check(pill && track && levelFill && peakMarker && pinBtn && micBtnOnBar, "missing mic meter child objects")

                // Wait for Revealer's initial showMicToggle width transition to settle
                tryVerify(() => Math.abs(module.naturalSpan - util.expandedMainAxisLength) < 0.01 && module.naturalSpan >= 100, 2000)
                const baseSpan = module.naturalSpan
                const baseWidth = util.implicitWidth
                check(baseSpan >= 100, "unexpected compact naturalSpan: " + baseSpan)

                // 1. Check all 4 Screen Edges keep exact module footprint and expand/collapse cleanly
                for (const edge of ["top", "right", "bottom", "left", "top"]) {
                    root.edge = edge
                    wait(60)
                    check(Math.abs(module.naturalSpan - baseSpan) < 0.01, "naturalSpan drifted on edge " + edge + ": base=" + baseSpan + " cur=" + module.naturalSpan + " expanded=" + util.expandedMainAxisLength + " count=" + util.visibleUtilityCount)
                    check(Math.abs(util.implicitWidth - baseWidth) < 0.01, "util.implicitWidth drifted on edge " + edge + ": base=" + baseWidth + " cur=" + util.implicitWidth)

                    mouseMove(micBtn, micBtn.width / 2, micBtn.height / 2)
                    tryVerify(() => util.micMeterExpanded && meterBar.progress >= 0.9999, 3000)

                    check(Math.abs(module.naturalSpan - baseSpan) < 0.01, "naturalSpan changed while expanded on " + edge)
                    check(Math.abs(util.implicitWidth - baseWidth) < 0.01, "util.implicitWidth changed while expanded on " + edge)
                    check(Math.abs(pill.x) < 0.5, "pill.x did not reach 0 on " + edge + ": " + pill.x)
                    check(Math.abs(pill.width - controlsStage.width) < 0.5, "pill.width mismatch on " + edge)

                    const others = collectControlLoaders(controlsGrid, micLoader)
                    check(others.length >= 3, "expected >=3 other Quick Action icons")
                    check(others.every(l => l.opacity < 0.01 && !l.enabled), "non-mic icons remained visible/enabled on " + edge)

                    mouseMove(scene, 4, 4)
                    tryVerify(() => !util.micMeterExpanded && meterBar.progress < 0.001, 3000)
                    check(others.every(l => l.opacity > 0.99 && l.enabled), "non-mic icons failed to restore on " + edge)
                }

                // 2. Verify horizontal slide origin starts from micLoader.x/width before reaching 0/controlsStage.width
                mouseMove(micBtn, micBtn.width / 2, micBtn.height / 2)
                tryVerify(() => util.micMeterExpanded && meterBar.progress > 0.05 && meterBar.progress < 0.95, 1000)
                const midProgress = meterBar.progress
                const expectedMidX = micLoader.x * (1 - midProgress)
                const expectedMidW = micLoader.width + (controlsStage.width - micLoader.width) * midProgress
                check(Math.abs(pill.x - expectedMidX) < 1.5, "mid-slide x mismatch: " + pill.x + " vs " + expectedMidX)
                check(Math.abs(pill.width - expectedMidW) < 1.5, "mid-slide width mismatch: " + pill.width + " vs " + expectedMidW)
                tryVerify(() => meterBar.progress >= 0.9999, 3000)

                // 3. Pin keeps meter open after pointer leaves; unpin collapses and restores icons
                mouseMove(pinBtn, pinBtn.width / 2, pinBtn.height / 2)
                wait(20)
                mouseClick(pinBtn, pinBtn.width / 2, pinBtn.height / 2)
                check(util.micMeterPinned === true && meterBar.pinned === true, "pin click did not activate pin")
                mouseMove(scene, 4, 4)
                wait(20)
                mouseMove(scene, 6, 6)
                wait(240)
                check(util.micMeterExpanded === true && meterBar.progress >= 0.9999, "pinned meter collapsed after unhover")
                check(Math.abs(module.naturalSpan - baseSpan) < 0.01, "pinned meter altered naturalSpan")

                // 4. Loudness fill, Peak Hold marker, clipping color & muted zero state
                meterBar.levelOverride = 0.40
                meterBar.peakOverride = 0.72
                wait(30)
                const expectedFill40 = Math.round((track.width - 2) * 0.40)
                check(Math.abs(levelFill.width - expectedFill40) <= 1, "levelFill.width mismatch: " + levelFill.width + " vs " + expectedFill40)
                check(peakMarker.visible === true, "peakMarker hidden on active peak")
                check(peakMarker.x > levelFill.x + levelFill.width - 2, "peakMarker did not sit ahead of 0.40 level")
                check(!Qt.colorEqual(peakMarker.color, Appearance.colors.colError), "peakMarker turned error color before clipping")

                meterBar.levelOverride = 0.92
                meterBar.peakOverride = 0.95
                tryVerify(() => Qt.colorEqual(peakMarker.color, Appearance.colors.colError), 1000)

                micClickSpy.target = meterBar
                mouseClick(micBtnOnBar, micBtnOnBar.width / 2, micBtnOnBar.height / 2)
                tryCompare(micClickSpy, "count", 1, 1000)
                // Wait for mocked wpctl get-volume readback to finish, then verify muted UI deterministically
                wait(60)
                Audio._micMuted = true
                wait(30)
                check(util.micMeterExpanded === true, "muting collapsed pinned meter")
                check(levelFill.width === 0, "muted meter did not zero levelFill")
                check(peakMarker.visible === false, "muted meter kept peakMarker visible")

                Audio._micMuted = false
                wait(20)

                // Unpin -> collapses immediately since hover session already ended
                mouseMove(pinBtn, pinBtn.width / 2, pinBtn.height / 2)
                wait(20)
                mouseClick(pinBtn, pinBtn.width / 2, pinBtn.height / 2)
                tryVerify(() => !util.micMeterPinned && !util.micMeterExpanded && meterBar.progress < 0.001, 3000)

                // 5. Auto-unpin when showMicToggle === false and mic stops being accessed
                mouseMove(scene, 4, 4)
                wait(20)
                Audio.micBeingAccessed = true
                Config.setNestedValue("bar.utilButtons.showMicToggle", false)
                tryVerify(() => util.micSlotActive && util.micInUse, 2000)
                tryVerify(() => {
                    micBtn = findByAccessible(util, "microphone")
                    return micBtn !== null && micBtn.visible && micBtn.enabled
                }, 2000)
                const activeMeterBar = meterLoader.item
                const activePinBtn = findChild(activeMeterBar, "abyssMicMeterPinButton")
                check(activeMeterBar !== null && activePinBtn !== null, "missing active meter bar in Step 5")
                activeMeterBar.levelOverride = 0.0
                activeMeterBar.peakOverride = 0.0
                mouseMove(micBtn, micBtn.width / 2, micBtn.height / 2)
                tryVerify(() => util.micMeterExpanded && activeMeterBar.progress >= 0.9999, 3000)
                mouseMove(activePinBtn, activePinBtn.width / 2, activePinBtn.height / 2)
                wait(20)
                mouseClick(activePinBtn, activePinBtn.width / 2, activePinBtn.height / 2)
                check(util.micMeterPinned === true, "auto-show mic failed to pin")
                mouseMove(scene, 4, 4)
                wait(20)
                mouseMove(scene, 6, 6)
                wait(220)
                check(util.micMeterExpanded === true, "pinned auto-show mic collapsed early")

                Audio.micBeingAccessed = false
                Privacy.micActive = false
                tryVerify(() => !util.micMeterPinned && !util.micMeterExpanded, 2000)

                // 6. Self-exclusion checks in Audio & Privacy
                check(Audio.isInternalMicMonitorNode({ name: "alis-mic-meter", properties: {} }) === true, "Audio missed raw node.name exclusion")
                check(Audio.isInternalMicMonitorNode({ name: "pw-cat", properties: { "application.name": "alis-mic-meter" } }) === true, "Audio missed application.name exclusion")
                check(Audio.isInternalMicMonitorNode({ name: "x", properties: { "media.name": "Alis Mic Meter" } }) === true, "Audio missed media.name exclusion")
                check(Audio.isInternalMicMonitorNode({ name: "chromium", properties: { "application.name": "Chromium input" } }) === false, "Audio falsely excluded Chromium")

                check(Privacy._isInternalMicMonitorNode({ name: "alis-mic-meter", properties: {} }) === true, "Privacy missed raw node.name exclusion")
                check(Privacy._isInternalMicMonitorNode({ name: "pw-cat", properties: { "application.name": "alis-mic-meter" } }) === true, "Privacy missed application.name exclusion")
                check(Privacy._isInternalMicMonitorNode({ name: "x", properties: { "media.name": "Alis Mic Meter" } }) === true, "Privacy missed media.name exclusion")
                check(Privacy._isInternalMicMonitorNode({ name: "chromium", properties: { "application.name": "Chromium input" } }) === false, "Privacy falsely excluded Chromium")

                check(!MicLevelService.active, "MicLevelService leaked active subscription")

                console.info("ABYSS_QUICK_ACTIONS_MIC_METER_PASS", root.checks, "checks")
            } catch (e) {
                console.error("ABYSS_QUICK_ACTIONS_MIC_METER_FAIL", e.message, e.stack)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 100
        running: true
        onTriggered: test.run()
    }
}
''',
            encoding="utf-8",
        )

        with private_wayland(folder) as env:
            if env is None:
                raise SystemExit("SKIP: runtime test requires private_wayland")
            config_dir = folder / "config" / "alis"
            config_dir.mkdir(parents=True, exist_ok=True)
            data = json.loads((ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))
            data["panelFamily"] = "abyss"
            data["abyss"]["companion"]["enabled"] = False
            data["bar"]["utilButtons"]["showMicToggle"] = True
            (config_dir / "config.json").write_text(json.dumps(data), encoding="utf-8")

            result = run_qs(folder, env, timeout=45)
            bad = (
                "ABYSS_QUICK_ACTIONS_MIC_METER_FAIL",
                "TypeError:",
                "ReferenceError:",
                "Binding loop",
                "Unable to assign",
                "Failed to load configuration",
            )
            if result.returncode or "ABYSS_QUICK_ACTIONS_MIC_METER_PASS" not in result.stdout or any(
                token in result.stdout for token in bad
            ):
                print(result.stdout)
                raise SystemExit(1)

            for line in result.stdout.splitlines():
                if "ABYSS_QUICK_ACTIONS_MIC_METER_PASS" in line:
                    print(line)


if __name__ == "__main__":
    main()
