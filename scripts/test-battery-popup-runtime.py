#!/usr/bin/env python3
"""Silent offscreen verification for BatteryPopup charge-limit line/presets and health history."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import native_test_session  # noqa: E402

TLP_STUB_QML = """pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.common

Singleton {
    id: root
    property bool available: true
    property bool supported: true
    property bool adjustable: true
    property bool stateKnown: true
    property bool active: false
    property bool managed: false
    property int currentLimit: 100
    property int currentStart: 0
    property string backend: "thinkpad"
    property string tlpVersion: "1.11.0"
    property string statusReason: ""
    property string limitKind: "continuous"
    property int minimumLimit: 1
    property int maximumLimit: 100
    property int limitStepSize: 1
    property var allowedLimits: []
    property int fixedLimit: -1
    property string configBattery: "BAT0"
    property string managedBattery: ""
    property int managedLimit: -1
    property bool busy: false
    readonly property int requestedLimit: Config.options?.battery?.chargeLimit?.threshold ?? 80
    readonly property int effectiveRequestedLimit: requestedLimit
    readonly property bool enabled: Config.options?.battery?.chargeLimit?.enable ?? false
    readonly property bool discrete: limitKind === "discrete"
    readonly property bool continuous: limitKind === "continuous"
    property int refreshCalls: 0
    property int applyCalls: 0
    function refresh(): void { refreshCalls += 1 }
    function apply(): void {
        applyCalls += 1
        active = enabled && requestedLimit < 100
        managed = enabled
        currentLimit = enabled ? requestedLimit : 100
    }
}
"""

TEST_SHELL_QML_TEMPLATE = """import QtQuick
import QtTest
import Quickshell
import qs
import qs.modules.common
import qs.modules.bar
import qs.services

FloatingWindow {
    id: win
    visible: true
    implicitWidth: 420
    implicitHeight: 540

    Item {
        id: host
        anchors.centerIn: parent
        width: 320
        height: 490
        visible: true
    }

    BatteryPopup {
        id: popup
        embeddedHost: host
    }

    MouseArea {
        id: lazyAnchor
        x: 8; y: 8; width: 40; height: 24
    }

    BatteryPopup {
        id: lazyPopup
        hoverTarget: lazyAnchor
        alternativeVisibleCondition: false
    }

    TestCase {
        id: test
        when: false
        optional: true
        property int checks: 0

        function check(cond, msg) {
            if (!cond)
                throw Error(msg)
            checks++
        }

        function findChild(item, objectName) {
            if (!item) return null
            if (item.objectName === objectName) return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; ++i) {
                const found = findChild(kids[i], objectName)
                if (found) return found
            }
            if (item.contentItem) {
                const found = findChild(item.contentItem, objectName)
                if (found) return found
            }
            return null
        }

        function seedFixture(historyPath, rawText, ueventOverride) {
            // Helper calls via FileView/direct properties
        }

        function runAll() {
            try {
                tryCompare(Config, "ready", true, 5000)

                // 1. Pure preset & normalization tests
                check(JSON.stringify(Battery.chargeLimitPresetsFor(true, false, "continuous", 1, 100, 1, [], -1))
                    === "[50,60,80,90,100]", "continuous presets ThinkPad")
                check(JSON.stringify(Battery.chargeLimitPresetsFor(true, false, "continuous", 55, 100, 1, [], -1))
                    === "[55,60,80,90,100]", "continuous presets clamped to hardware min")
                check(JSON.stringify(Battery.chargeLimitPresetsFor(true, false, "discrete", 50, 100, 1, [50, 80], -1))
                    === "[50,80,100]", "discrete presets include 100 reset point")
                check(JSON.stringify(Battery.chargeLimitPresetsFor(true, false, "mode", 1, 100, 1, [], 80))
                    === "[80,100]", "conservation mode presets [80, 100]")
                check(JSON.stringify(Battery.chargeLimitPresetsFor(false, false, "none", 1, 100, 1, [], -1))
                    === "[]", "unsupported exposes zero presets")

                check(Battery.normalizeChargeLimitFor(42, "continuous", 55, 100, 5, [55, 60, 80, 90, 100]) === 55, "clamp below hardware min")
                check(Battery.normalizeChargeLimitFor(73, "continuous", 55, 100, 5, [55, 60, 80, 90, 100]) === 75, "step snap continuous")
                check(Battery.normalizeChargeLimitFor(68, "discrete", 50, 100, 1, [50, 80, 100]) === 80, "nearest discrete preset")
                check(Battery.normalizeChargeLimitFor(92, "mode", 1, 100, 1, [80, 100]) === 100, "nearest mode preset 100")

                // 2. Pure history parser, migration, compaction, and summary tests
                const emptyParsed = Battery.parseHistoryDocument("", "BAT0:TEST")
                check(emptyParsed.ok && Object.keys(emptyParsed.db.batteries).length === 0, "empty history parse")

                const corruptParsed = Battery.parseHistoryDocument("{not valid json", "BAT0:TEST")
                check(!corruptParsed.ok && corruptParsed.db === null, "corrupt history rejected safely")

                const legacyParsed = Battery.parseHistoryDocument(JSON.stringify([
                    { t: 1700000000, h: 84.5, c: 120 },
                    { t: 1700500000, h: 83.25, c: 125 }
                ]), "BAT0:LGES:TEST:1")
                check(legacyParsed.ok
                    && legacyParsed.db.batteries["BAT0:LGES:TEST:1"].samples.length === 2
                    && legacyParsed.db.batteries["BAT0:LGES:TEST:1"].samples[0].h === 84.5
                    && legacyParsed.db.batteries["BAT0:LGES:TEST:1"].samples[1].c === 125,
                    "legacy flat array read-time migration preserves timestamps & counts")

                const multiV1Parsed = Battery.parseHistoryDocument(JSON.stringify({
                    version: 1,
                    ownerNote: "keep-top",
                    batteries: {
                        "BAT1:OTHER": {
                            customMeta: 42,
                            samples: [{ t: 1710000000, h: 92.0, c: 10, f: 45.2 }]
                        }
                    }
                }), "BAT0")
                check(multiV1Parsed.ok
                    && multiV1Parsed.db.ownerNote === "keep-top"
                    && multiV1Parsed.db.batteries["BAT1:OTHER"].customMeta === 42
                    && multiV1Parsed.db.batteries["BAT1:OTHER"].samples.length === 1,
                    "v1 parser preserves extra metadata and other batteries")

                const tEnd = 1795520000
                const tStart = tEnd - Math.round(6 * 30.4375 * 86400)
                const sixMonthSamples = [
                    { t: tStart, h: 80.5, c: 385, f: 31.6 },
                    { t: tStart + Math.round(90 * 86400), h: 79.2, c: 406, f: 31.1 },
                    { t: tEnd, h: 78.0, c: 428, f: 30.7 }
                ]
                const sixMonthSummary = Battery.computeHealthHistorySummary(sixMonthSamples, 78.0, 428)
                check(sixMonthSummary.summaryText === "-2.5% health over 6 months · +43 cycles",
                    "6-month summary mismatch: " + sixMonthSummary.summaryText)

                const day1Summary = Battery.computeHealthHistorySummary([{ t: tEnd, h: 98.4, c: 12 }], 98.4, 12)
                check(day1Summary.summaryText === "Baseline 98.4% health · 12 cycles",
                    "day-1 baseline mismatch: " + day1Summary.summaryText)

                check(!Battery.shouldRecordHealthSample(sixMonthSamples, tEnd + 60, 78.0, 428),
                    "should not duplicate unchanged reading after 60s")
                check(Battery.shouldRecordHealthSample(sixMonthSamples, tEnd + 86400, 78.0, 428),
                    "should record daily heartbeat after 24h")
                check(Battery.shouldRecordHealthSample(sixMonthSamples, tEnd + 21600, 77.9, 428),
                    "should record after 6h when health shifts by >= 0.05%")
                check(Battery.shouldRecordHealthSample(sixMonthSamples, tEnd + 1800, 78.0, 429),
                    "should record after 30m when cycle count advances")
                check(!Battery.shouldRecordHealthSample(sixMonthSamples, tEnd + 90000, 0, 429),
                    "reject invalid zero health")

                const dense = []
                for (let i = 0; i < 900; ++i)
                    dense.push({ t: 1700000000 + i * 86400, h: 95 - i * 0.01, c: 10 + i, f: 38.0 })
                const compacted = Battery.compactHealthSamples(dense, 730)
                check(compacted.length <= 730 && compacted[0].t === dense[0].t && compacted[compacted.length - 1].t === dense[899].t,
                    "compaction preserves first & last samples cleanly")

                // 3. Real file persistence & corrupt non-overwrite check on isolated XDG path
                const baseDir = Quickshell.env("BATTERY_TEST_DIR")
                Battery.historyFilePath = baseDir + "/corrupt-history.json"
                tryVerify(() => Battery._historyLoaded && Battery._historyCorrupt, 3000)

                Battery.historyFilePath = baseDir + "/live-history.json"
                tryVerify(() => Battery._historyLoaded && !Battery._historyCorrupt, 3000)

                // Inject parsed sysfs state into Battery singleton so live identity matches BAT0:LGES:5B11M90022:143
                Battery._applyParsedUevent(Battery.parseUeventText(
                    "POWER_SUPPLY_PRESENT=1\\n" +
                    "POWER_SUPPLY_STATUS=Not charging\\n" +
                    "POWER_SUPPLY_CAPACITY=80\\n" +
                    "POWER_SUPPLY_ENERGY_FULL_DESIGN=39300000\\n" +
                    "POWER_SUPPLY_ENERGY_FULL=30654000\\n" +
                    "POWER_SUPPLY_ENERGY_NOW=24523200\\n" +
                    "POWER_SUPPLY_VOLTAGE_MIN_DESIGN=11580000\\n" +
                    "POWER_SUPPLY_VOLTAGE_NOW=12900000\\n" +
                    "POWER_SUPPLY_MANUFACTURER=LGES\\n" +
                    "POWER_SUPPLY_MODEL_NAME=5B11M90022\\n" +
                    "POWER_SUPPLY_SERIAL_NUMBER=143\\n" +
                    "POWER_SUPPLY_CYCLE_COUNT=428\\n"
                ))
                wait(950)
                check(Battery.batteryIdentityKey === "BAT0:LGES:5B11M90022:143" || Battery.batteryIdentityKey.includes("LGES:5B11M90022:143"),
                    "unexpected batteryIdentityKey: " + Battery.batteryIdentityKey)
                check(Battery.healthHistory.length >= 2,
                    "live history did not load preserved OTHER/record sample cleanly: " + Battery.healthHistory.length)

                // Now check mounted BatteryPopup with canonical 6-month trend injected for clean UI assertions
                const key = Battery.batteryIdentityKey
                Battery._historyDb.batteries[key] = {
                    identity: key,
                    designWh: 39.3,
                    samples: sixMonthSamples
                }
                Battery._syncActiveHistoryView()
                wait(80)

                check(popup.presentationActive === true, "embedded BatteryPopup must be presentationActive")
                const body = findChild(host, "batteryPopupContent")
                const chargeBar = findChild(host, "batteryChargeBar")
                const limitLine = findChild(host, "batteryChargeLimitLine")
                const limitMouse = findChild(host, "batteryChargeLimitMouse")
                const limitLabel = findChild(host, "batteryChargeLimitLabel")
                const historyCard = findChild(host, "batteryHistoryCard")
                const historySummary = findChild(host, "batteryHistorySummaryText")
                const sparkline = findChild(host, "batteryHistorySparkline")

                check(body !== null && chargeBar !== null && limitLine !== null && limitMouse !== null,
                    "missing integrated charge limit UI nodes")
                check(historyCard !== null && historySummary !== null && sparkline !== null,
                    "missing history UI nodes")
                check(chargeBar.width > 150 && limitLine.visible === true,
                    "charge bar or limit line invisible: w=" + chargeBar.width + " vis=" + limitLine.visible)
                check(historyCard.visible === true && sparkline.width > 150 && sparkline.height >= 40,
                    "history card / sparkline invalid geometry: vis=" + historyCard.visible + " w=" + sparkline.width + " h=" + sparkline.height)
                check(historySummary.text === "-2.5% health over 6 months · +43 cycles",
                    "rendered history summary mismatch: " + historySummary.text)
                tryVerify(() => sparkline._plottedPoints && sparkline._plottedPoints.length === 3, 2000)

                // 4. Drag & release test on batteryChargeLimitMouse (must hold popup open while dragging and commit ONLY on release)
                Config.setNestedValue("battery.chargeLimit.enable", false)
                TlpService.apply()
                wait(40)

                const x60 = popup.percentToX(60, chargeBar.width)
                const yMid = limitMouse.height * 0.5
                mousePress(limitMouse, x60, yMid, Qt.LeftButton)
                check(popup._draggingLimit === true && popup._interactionHold === true,
                    "press on limit bar must engage dragging + interactionHold")
                check(Config.options.battery.chargeLimit.enable === false,
                    "dragging/pressing must NOT mutate Config before release")

                const x50 = popup.percentToX(50, chargeBar.width)
                mouseMove(limitMouse, x50, yMid)
                check(popup._dragLimit === 50 && limitLabel.text === "50%",
                    "drag move did not preview 50%: drag=" + popup._dragLimit + " label=" + limitLabel.text)
                check(Config.options.battery.chargeLimit.enable === false,
                    "drag move must NOT mutate Config mid-drag")

                const x80 = popup.percentToX(80, chargeBar.width)
                mouseMove(limitMouse, x80, yMid)
                mouseRelease(limitMouse, x80, yMid, Qt.LeftButton)
                check(popup._draggingLimit === false && popup._interactionHold === false,
                    "release must clear dragging + interactionHold")
                check(Config.options.battery.chargeLimit.enable === true && Config.options.battery.chargeLimit.threshold === 80,
                    "release at 80% preset must enable chargeLimit=80 (enable=" + Config.options.battery.chargeLimit.enable + " thr=" + Config.options.battery.chargeLimit.threshold + ")")

                // Click/release 100% preset disables charge limit cleanly
                const x100 = popup.percentToX(100, chargeBar.width)
                mousePress(limitMouse, x100, yMid, Qt.LeftButton)
                mouseRelease(limitMouse, x100, yMid, Qt.LeftButton)
                check(Config.options.battery.chargeLimit.enable === false,
                    "releasing on 100% preset must disable chargeLimit")

                // 5. Hover over sparkline inspects historical point
                mouseMove(sparkline, sparkline._plottedPoints[0].x, sparkline.height * 0.5)
                check(sparkline.hoveredIndex === 0 && historySummary.text === "80.5% health · 385 cycles",
                    "sparkline hover mismatch: idx=" + sparkline.hoveredIndex + " text=" + historySummary.text)

                // 6. Verify non-embedded LazyLoader BatteryPopup mounts & unmounts without reference errors
                check(!lazyPopup.active && !lazyPopup.presentationActive, "lazy BatteryPopup starts dormant")
                lazyPopup.alternativeVisibleCondition = true
                tryCompare(lazyPopup, "presentationActive", true, 3000)
                wait(80)
                lazyPopup.alternativeVisibleCondition = false
                tryCompare(lazyPopup, "presentationActive", false, 3000)

                console.info("BATTERY_POPUP_RUNTIME_PASS", checks)
            } catch (error) {
                console.error("BATTERY_POPUP_RUNTIME_FAIL", error.message, error.stack ?? "")
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 120
        running: true
        onTriggered: test.runAll()
    }
}
"""


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="alis-battery-popup-test-") as td:
        folder = Path(td)
        for entry in ("modules", "GlobalStates.qml", "qmldir", "scripts", "assets", "defaults", "translations"):
            src = ROOT / entry
            if src.exists():
                (folder / entry).symlink_to(src)

        svc_dir = folder / "services"
        svc_dir.mkdir()
        for item in (ROOT / "services").iterdir():
            if item.name == "TlpService.qml":
                continue
            (svc_dir / item.name).symlink_to(item)
        (svc_dir / "TlpService.qml").write_text(TLP_STUB_QML, encoding="utf-8")

        corrupt_path = folder / "corrupt-history.json"
        corrupt_bytes = "{broken json content untouched"
        corrupt_path.write_text(corrupt_bytes, encoding="utf-8")

        live_history_path = folder / "live-history.json"
        # Seed pre-existing multi-battery JSON + another cell to verify read-back preservation
        old_ts = 1779900000
        live_history_path.write_text(
            json.dumps(
                {
                    "version": 1,
                    "customTopKey": "preserve-me",
                    "batteries": {
                        "BAT0:LGES:5B11M90022:143": {
                            "identity": "BAT0:LGES:5B11M90022:143",
                            "customMeta": "keep-bat-meta",
                            "samples": [
                                {"t": old_ts, "h": 80.5, "c": 410, "f": 31.6},
                            ],
                        },
                        "BAT1:OTHER:99": {
                            "samples": [{"t": old_ts, "h": 95.0, "c": 12, "f": 48.0}],
                        },
                    },
                }
            ),
            encoding="utf-8",
        )

        (folder / "shell.qml").write_text(TEST_SHELL_QML_TEMPLATE, encoding="utf-8")

        with native_test_session.private_wayland(folder, isolate_xdg=True) as wl_env:
            if not wl_env:
                raise AssertionError("Silent private_wayland environment unavailable")
            env = {
                **wl_env,
                "BATTERY_TEST_DIR": str(folder),
                "XDG_CONFIG_HOME": str(folder / "config"),
                "XDG_STATE_HOME": str(folder / "state"),
                "XDG_CACHE_HOME": str(folder / "cache"),
                "XDG_DATA_HOME": str(folder / "data"),
            }
            res = native_test_session.run_qs(folder, env, timeout=30)
        out = res.stdout or ""
        if res.returncode != 0 or "BATTERY_POPUP_RUNTIME_PASS" not in out or "BATTERY_POPUP_RUNTIME_FAIL" in out:
            raise AssertionError(f"BatteryPopup runtime test failed (rc={res.returncode}):\n{out}")

        for bad in ("TypeError:", "ReferenceError:", "Binding loop", "Unable to assign"):
            if bad in out:
                raise AssertionError(f"QML runtime error ({bad}) detected:\n{out}")

        # Verify corrupt file remained untouched on disk
        assert corrupt_path.read_text(encoding="utf-8") == corrupt_bytes, "Corrupt JSON file was overwritten!"

        # Verify live-history.json preserved BAT1:OTHER, customTopKey, customMeta, and appended new snapshot
        # without writing partial intermediate batteryIdentityKey prefix entries.
        saved_live = json.loads(live_history_path.read_text(encoding="utf-8"))
        assert saved_live.get("customTopKey") == "preserve-me", f"Lost top-level metadata: {saved_live}"
        bats = saved_live.get("batteries", {})
        assert set(bats.keys()) == {"BAT0:LGES:5B11M90022:143", "BAT1:OTHER:99"}, (
            f"Unexpected battery identity keys written: {sorted(bats.keys())}"
        )
        bat0 = bats["BAT0:LGES:5B11M90022:143"]
        assert bat0.get("customMeta") == "keep-bat-meta", f"Lost per-battery metadata: {bat0}"
        assert len(bat0.get("samples", [])) >= 2, f"Expected appended health snapshot, got: {bat0}"

        pass_line = [line for line in out.splitlines() if "BATTERY_POPUP_RUNTIME_PASS" in line][-1]
        print(f"PASS: {pass_line.strip()}")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
