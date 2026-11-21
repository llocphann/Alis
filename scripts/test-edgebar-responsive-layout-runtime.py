#!/usr/bin/env python3
"""Silent offscreen Quickshell runtime test for Edgebar responsive alignment & Timers."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]

QML_TEMPLATE = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.screenCorners
import qs.modules.notificationCenter
import qs.modules.sidebarRight.pomodoro

Window {
    id: root
    visible: true
    width: 820
    height: 940
    color: "#0e1214"

    Component.onCompleted: Quickshell.watchFiles = false

    Item {
        id: dummyLeftAnchor
        x: 0; y: root.height - 14; width: 14; height: 14
    }

    Item {
        id: dummyRightAnchor
        x: root.width - 14; y: root.height - 14; width: 14; height: 14
    }

    QuickNotesPopup {
        id: leftPopup
        anchorItem: dummyLeftAnchor
        hoverAllowed: false
        presentationActive: true
    }

    NotificationCenterPopup {
        id: rightPopup
        anchorItem: dummyRightAnchor
        outputName: "TEST-OUT"
        hoverAllowed: false
        presentationActive: true
    }

    // Host replicating StyledPopup's inner content envelope (_contentPadding = 14)
    Rectangle {
        id: leftStageFrame
        x: 20
        y: 20
        width: leftPopup.requestedPopupWidth
        height: leftPopup.requestedPopupHeight
        radius: 18
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: Appearance.colors.colLayer1

        Item {
            id: leftContentHost
            anchors.fill: parent
            anchors.margins: 14
        }
    }

    Rectangle {
        id: rightStageFrame
        x: 20
        y: 20
        visible: false
        width: rightPopup.requestedPopupWidth
        height: rightPopup.requestedPopupHeight
        radius: 18
        color: Appearance.colors.colLayer0Base
        border.width: 1
        border.color: Appearance.colors.colLayer1

        Item {
            id: rightContentHost
            anchors.fill: parent
            anchors.margins: 14
        }
    }

    // Standalone PillTabBar probe for 3-digit badge & narrow pill padding checks
    PillTabBar {
        id: badgeProbeTabs
        objectName: "pillTabBarBadgeProbe"
        x: 20
        y: 860
        width: 284
        pillHeight: 30
        currentIndex: 0
        tabs: [
            { icon: "notifications", label: "Notifications", count: 128 },
            { icon: "monitoring", label: "Activity" }
        ]
    }

    // Standalone Sidebar Right host (compactMode: false, showPinButton: true)
    Item {
        id: sidebarTimerHost
        x: 20
        y: 20
        width: 340
        height: 280
        visible: false

        PomodoroWidget {
            id: sidebarTimerWidget
            anchors.fill: parent
            compactMode: false
            showPinButton: true
        }
    }

    TestCase {
        id: test
        when: false
        optional: true
        name: "EdgebarResponsiveLayoutRuntime"

        property string dumpDir: "__DUMP_DIR__"

        function findByObjectName(item, targetName) {
            if (!item) return null
            if (item.objectName === targetName) return item
            const kids = item.children || []
            for (let i = 0; i < kids.length; i++) {
                const found = findByObjectName(kids[i], targetName)
                if (found) return found
            }
            const res = item.resources || []
            for (let j = 0; j < res.length; j++) {
                const found = findByObjectName(res[j], targetName)
                if (found) return found
            }
            return null
        }

        function check(cond, msg) {
            if (!cond) throw new Error(msg)
        }

        function waitFor(pred, timeoutMs) {
            const deadline = Date.now() + (timeoutMs || 4000)
            while (!pred()) {
                if (Date.now() > deadline)
                    throw new Error("Timed out waiting for readiness")
                wait(25)
            }
        }

        function rectIn(item, ancestor) {
            const pt = item.mapToItem(ancestor, 0, 0)
            return { x: pt.x, y: pt.y, w: item.width, h: item.height, right: pt.x + item.width, bottom: pt.y + item.height }
        }

        function assertInside(child, container, label, tol) {
            const t = tol === undefined ? 1.5 : tol
            const r = rectIn(child, container)
            check(r.w > 0 && r.h > 0, label + " must have positive size, got " + JSON.stringify(r))
            check(r.x >= -t, label + " overflows left: " + JSON.stringify(r) + " containerW=" + container.width)
            check(r.y >= -t, label + " overflows top: " + JSON.stringify(r) + " containerH=" + container.height)
            check(r.right <= container.width + t, label + " overflows right: " + JSON.stringify(r) + " containerW=" + container.width)
            check(r.bottom <= container.height + t, label + " overflows bottom: " + JSON.stringify(r) + " containerH=" + container.height)
            return r
        }

        function maybeGrab(targetItem, filename) {
            if (!dumpDir || dumpDir.length === 0) return
            let done = false
            targetItem.grabToImage(result => {
                result.saveToFile(dumpDir + "/" + filename)
                done = true
            })
            waitFor(() => done, 3000)
        }

        function settle(ms) {
            wait(ms || 70)
        }

        function run() {
            try {
                waitFor(() => Config.ready && Persistent.ready, 4000)
                Config.setNestedValue("performance.reduceAnimations", true)
                settle(40)

                // Reparent popup contentItem into our resizable Stage hosts (same pattern as AbyssBodyHost)
                leftPopup.contentItem.parent = leftContentHost
                leftPopup.contentItem.anchors.fill = leftContentHost
                rightPopup.contentItem.parent = rightContentHost
                rightPopup.contentItem.anchors.fill = rightContentHost
                settle(80)

                const leftProfiles = [
                    { name: "compact", w: 280, h: 300, expectStacked: false },
                    { name: "default", w: 420, h: 300, expectStacked: false },
                    { name: "square", w: 450, h: 450, expectStacked: false },
                    { name: "narrow_tall", w: 280, h: 640, expectStacked: true },
                    { name: "wide_short", w: 720, h: 300, expectStacked: false },
                    { name: "large", w: 720, h: 640, expectStacked: false }
                ]

                let pomodoroHgByProfile = {}
                let countdownHgByProfile = {}

                for (let idx = 0; idx < leftProfiles.length; idx++) {
                    const p = leftProfiles[idx]
                    Config.setNestedValue("quickNotes.popupWidth", p.w)
                    Config.setNestedValue("quickNotes.popupHeight", p.h)
                    settle(90)

                    check(leftPopup.requestedPopupWidth === p.w, p.name + ": requestedPopupWidth mismatch")
                    check(leftPopup.requestedPopupHeight === p.h, p.name + ": requestedPopupHeight mismatch")
                    check(Math.abs(leftContentHost.width - (p.w - 28)) < 1, p.name + ": leftContentHost width mismatch")
                    check(Math.abs(leftContentHost.height - (p.h - 28)) < 1, p.name + ": leftContentHost height mismatch")

                    // 1. Verify QuickNotesPopup top header tabs & pin never overlap
                    const mainTabs = findByObjectName(leftContentHost, "quickNotesMainTabs")
                    const pinBtn = findByObjectName(leftContentHost, "quickNotesPopupPin")
                    const traySlot = findByObjectName(leftContentHost, "quickNotesTraySlot")
                    check(!!mainTabs && !!pinBtn && !!traySlot, p.name + ": missing QuickNotesPopup header controls")

                    const rTabs = assertInside(mainTabs, leftContentHost, p.name + " mainTabs")
                    const rPin = assertInside(pinBtn, leftContentHost, p.name + " pinBtn")
                    check(rTabs.right + 6 <= rPin.x, p.name + ": mainTabs overlaps pinBtn (" + rTabs.right + " vs " + rPin.x + ")")
                    if (leftContentHost.width >= 300) {
                        const tabCenter = rTabs.x + rTabs.w / 2
                        check(Math.abs(tabCenter - leftContentHost.width / 2) <= 2.0,
                            p.name + ": mainTabs should be horizontally centered (" + tabCenter + " vs " + (leftContentHost.width / 2) + ")")
                    }

                    // Test Notes & To-do tabs briefly at each size
                    leftPopup.selectedMainTab = 0
                    leftPopup.selectedNotesTab = 0
                    leftPopup.notesTrayOpen = true
                    settle(70)
                    const rTray = assertInside(traySlot, leftContentHost, p.name + " notesTraySlot")
                    check(Math.abs((rTray.x + rTray.w / 2) - (rTabs.x + rTabs.w / 2)) <= 2.0,
                        p.name + ": notesTraySlot must align under mainTabs")
                    leftPopup.notesTrayOpen = false
                    leftPopup.selectedNotesTab = 1
                    settle(60)

                    // 2. Switch to Timers tab -> Pomodoro (subtab 0)
                    leftPopup.selectedMainTab = 1
                    settle(80)
                    const modeBar = findByObjectName(leftContentHost, "timerModeTabBar")
                    check(!!modeBar, p.name + ": timerModeTabBar missing")
                    const rModeBar = assertInside(modeBar, leftContentHost, p.name + " timerModeTabBar")
                    check(Math.abs((rModeBar.x + rModeBar.w / 2) - leftContentHost.width / 2) <= 2.0,
                        p.name + ": timerModeTabBar must stay centered")

                    // Locate PomodoroWidget and set subtab 0
                    const pomodoroWidget = modeBar.parent.parent.parent
                    pomodoroWidget.currentTab = 0
                    settle(80)

                    const pHeader = findByObjectName(leftContentHost, "pomodoroFocusHeader")
                    const pDial = findByObjectName(leftContentHost, "pomodoroFocusDial")
                    const pStage = findByObjectName(leftContentHost, "pomodoroHourglassStage")
                    const pHg = findByObjectName(leftContentHost, "pomodoroHourglass")
                    const pControls = findByObjectName(leftContentHost, "pomodoroControlsRow")
                    const pStart = findByObjectName(leftContentHost, "pomodoroStartButton")
                    const pReset = findByObjectName(leftContentHost, "pomodoroResetButton")
                    const pSkip = findByObjectName(leftContentHost, "pomodoroSkipButton")
                    const pCust = findByObjectName(leftContentHost, "pomodoroCustomizeButton")
                    check(!!pHeader && !!pDial && !!pStage && !!pHg && !!pControls && !!pStart && !!pReset && !!pSkip && !!pCust,
                        p.name + ": missing Pomodoro elements")

                    // Verify NO linear progressTrack exists
                    const progressTrack = findByObjectName(leftContentHost, "progressTrack")
                    check(!progressTrack, p.name + ": linear progress bar must not exist")

                    const rHeader = assertInside(pHeader, leftContentHost, p.name + " pomodoroHeader")
                    const rDial = assertInside(pDial, leftContentHost, p.name + " pomodoroDial")
                    const rStage = assertInside(pStage, pDial, p.name + " pomodoroStage")
                    const rHg = assertInside(pHg, pDial, p.name + " pomodoroHourglass")
                    const rControls = assertInside(pControls, leftContentHost, p.name + " pomodoroControls")

                    // Header sits cleanly near top of Pomodoro viewport (not floating in dead center!)
                    const rHeaderInTimer = rectIn(pHeader, pDial.parent)
                    check(rHeaderInTimer.y <= 16, p.name + ": FOCUS header drifted too far down: y=" + rHeaderInTimer.y)

                    // Vertical separation: header -> stage -> controls
                    const rStageInRoot = rectIn(pStage, leftContentHost)
                    check(rHeader.bottom <= rStageInRoot.y + 1, p.name + ": header overlaps stage")
                    check(rStageInRoot.bottom <= rControls.y + 1, p.name + ": stage overlaps controls")

                    // Optical centering of stage inside focusDial
                    const stageCenterX = rStage.x + rStage.w / 2
                    const stageCenterY = rStage.y + rStage.h / 2
                    check(Math.abs(stageCenterX - pDial.width / 2) <= 2.5,
                        p.name + ": pomodoro stage not horizontally centered (" + stageCenterX + " vs " + (pDial.width / 2) + ")")
                    check(Math.abs(stageCenterY - pDial.height / 2) <= 3.0,
                        p.name + ": pomodoro stage not vertically centered (" + stageCenterY + " vs " + (pDial.height / 2) + ")")

                    // Stacked mode check
                    check((pStage.columns === 1) === p.expectStacked,
                        p.name + ": expected pomodoro stacked=" + p.expectStacked + ", got columns=" + pStage.columns)

                    // Control buttons: non-overlapping & strictly inside controlsRow
                    const rStart = assertInside(pStart, pControls, p.name + " pStart")
                    const rReset = assertInside(pReset, pControls, p.name + " pReset")
                    const rSkip = assertInside(pSkip, pControls, p.name + " pSkip")
                    const rCust = assertInside(pCust, pControls, p.name + " pCust")
                    check(rStart.right + 2 <= rReset.x, p.name + ": Start overlaps Reset")
                    check(rReset.right + 2 <= rSkip.x, p.name + ": Reset overlaps Skip")
                    check(rSkip.right + 2 <= rCust.x, p.name + ": Skip overlaps Customize")
                    if (p.w === 280) {
                        const leftMargin = rStart.x
                        const rightMargin = pControls.width - rCust.right
                        check(Math.abs(leftMargin - rightMargin) <= 3.0,
                            p.name + ": narrow Pomodoro controls must be symmetrically centered (" + leftMargin + " vs " + rightMargin + ")")
                    }

                    pomodoroHgByProfile[p.name] = rHg.h
                    maybeGrab(leftStageFrame, "left_pomodoro_" + p.name + ".png")

                    // Exercise Customize & Tag drawers on compact and large
                    if (p.name === "compact" || p.name === "large") {
                        pCust.clicked()
                        settle(60)
                        assertInside(pControls, leftContentHost, p.name + " controls with settingsOpen")
                        const chipTurned = findByObjectName(leftContentHost, "pomodoroStyleChip_turned")
                        const chipMatrix = findByObjectName(leftContentHost, "pomodoroStyleChip_matrix")
                        const chipSquare = findByObjectName(leftContentHost, "pomodoroStyleChip_square")
                        check(!!chipTurned && !!chipMatrix && !!chipSquare, p.name + ": style chips missing in Customize")
                        check(Math.max(chipTurned.width, chipMatrix.width, chipSquare.width)
                            - Math.min(chipTurned.width, chipMatrix.width, chipSquare.width) <= 2.0,
                            p.name + ": Pomodoro style chips must have uniform widths (" + chipTurned.width + "/" + chipMatrix.width + "/" + chipSquare.width + ")")
                        check(String(chipMatrix.colBackground) !== String(pHeader.parent.parent.parent._colLayer),
                            p.name + ": unselected Pomodoro style chip must contrast with settings card surface")
                        pCust.clicked()
                        settle(50)

                        const tagPill = findByObjectName(leftContentHost, "pomodoroActiveTagPill")
                        check(!!tagPill, p.name + ": tagPill missing")
                    }

                    // 3. Subtab 1 -> CountdownTimer
                    pomodoroWidget.currentTab = 1
                    settle(80)
                    const cDeck = findByObjectName(leftContentHost, "countdownTimerDeck")
                    const cRow = findByObjectName(leftContentHost, "countdownDeckRow")
                    const cHg = findByObjectName(leftContentHost, "countdownHourglass")
                    const cStatus = findByObjectName(leftContentHost, "countdownStatusRow")
                    const cPresets = findByObjectName(leftContentHost, "countdownPresetsRow")
                    const cControls = findByObjectName(leftContentHost, "countdownControlsRow")
                    const cStart = findByObjectName(leftContentHost, "countdownStartButton")
                    const cReset = findByObjectName(leftContentHost, "countdownResetButton")
                    const cCust = findByObjectName(leftContentHost, "countdownCustomizeButton")
                    check(!!cDeck && !!cRow && !!cHg && !!cStatus && !!cPresets && !!cControls && !!cStart && !!cReset && !!cCust,
                        p.name + ": missing Countdown elements")

                    assertInside(cDeck, leftContentHost, p.name + " countdownDeck")
                    const rCRow = assertInside(cRow, cDeck, p.name + " countdownDeckRow")
                    const rCHg = assertInside(cHg, cDeck, p.name + " countdownHourglass")
                    const rCStatus = assertInside(cStatus, cDeck, p.name + " countdownStatusRow")
                    const rCPresets = assertInside(cPresets, leftContentHost, p.name + " countdownPresets")
                    const rCControls = assertInside(cControls, leftContentHost, p.name + " countdownControls")
                    check((cRow.columns === 1) === p.expectStacked,
                        p.name + ": expected countdown stacked=" + p.expectStacked + ", got columns=" + cRow.columns)
                    check(Math.abs((rCRow.x + rCRow.w / 2) - cDeck.width / 2) <= 2.5,
                        p.name + ": countdown stage not horizontally centered")
                    if (p.expectStacked) {
                        check(Math.abs((rCStatus.x + rCStatus.w / 2) - cDeck.width / 2) <= 2.5,
                            p.name + ": stacked countdown status not horizontally centered (" + (rCStatus.x + rCStatus.w / 2) + " vs " + (cDeck.width / 2) + ")")
                    }
                    check(rCPresets.bottom <= rCControls.y + 1, p.name + ": countdown presets overlap controls")
                    let presetWidths = []
                    for (let pi = 0; pi < cPresets.children.length; pi++) {
                        const ch = cPresets.children[pi]
                        if (ch && ch.visible && ch.width > 0) presetWidths.push(ch.width)
                    }
                    check(presetWidths.length === 5, p.name + ": expected 5 visible countdown preset pills, got " + presetWidths.length)
                    check(Math.max.apply(null, presetWidths) - Math.min.apply(null, presetWidths) <= 2.0,
                        p.name + ": countdown preset pills must share uniform widths, got " + JSON.stringify(presetWidths))

                    const rCStart = assertInside(cStart, cControls, p.name + " cStart")
                    const rCReset = assertInside(cReset, cControls, p.name + " cReset")
                    const rCCust = assertInside(cCust, cControls, p.name + " cCust")
                    check(rCStart.right + 2 <= rCReset.x, p.name + ": countdown Start overlaps Reset")
                    check(rCReset.right + 2 <= rCCust.x, p.name + ": countdown Reset overlaps Customize")
                    if (p.w === 280) {
                        const cLeft = rCStart.x
                        const cRight = cControls.width - rCCust.right
                        check(Math.abs(cLeft - cRight) <= 3.0,
                            p.name + ": narrow Countdown controls must be symmetrically centered (" + cLeft + " vs " + cRight + ")")
                    }

                    // Consistent bottom controls baseline with Pomodoro
                    check(Math.abs(rCControls.bottom - rControls.bottom) <= 4.0,
                        p.name + ": countdown controls bottom (" + rCControls.bottom + ") misaligned vs pomodoro (" + rControls.bottom + ")")

                    countdownHgByProfile[p.name] = rCHg.h
                    if (p.name === "compact" || p.name === "square" || p.name === "narrow_tall") {
                        maybeGrab(leftStageFrame, "left_countdown_" + p.name + ".png")
                    }

                    // 4. Subtab 2 -> Stopwatch
                    pomodoroWidget.currentTab = 2
                    settle(80)
                    const sStage = findByObjectName(leftContentHost, "stopwatchStage")
                    const sElapsed = findByObjectName(leftContentHost, "stopwatchElapsed")
                    const sControls = findByObjectName(leftContentHost, "stopwatchControlsRow")
                    check(!!sStage && !!sElapsed && !!sControls, p.name + ": missing Stopwatch elements")
                    const rSElapsed = assertInside(sElapsed, leftContentHost, p.name + " stopwatchElapsed")
                    const rSControls = assertInside(sControls, leftContentHost, p.name + " stopwatchControls")
                    check(rSElapsed.bottom + 4 <= rSControls.y,
                        p.name + ": stopwatch elapsed overlaps controls (" + rSElapsed.bottom + " vs " + rSControls.y + ")")
                    check(Math.abs((rSElapsed.x + rSElapsed.w / 2) - leftContentHost.width / 2) <= 2.5,
                        p.name + ": stopwatch elapsed not horizontally centered")
                    check(Math.abs(rSControls.bottom - rControls.bottom) <= 4.0,
                        p.name + ": stopwatch controls bottom misaligned vs pomodoro")

                    if (p.name === "square") {
                        TimerService.stopwatchRecordLap()
                        settle(60)
                        const rSElapsedLap = assertInside(sElapsed, leftContentHost, p.name + " stopwatchElapsed with lap")
                        check(rSElapsedLap.bottom + 4 <= rSControls.y, "stopwatch elapsed with lap overlaps controls")
                        TimerService.stopwatchReset()
                        settle(40)
                    }
                }

                // Verify responsive scaling: hourglass grows meaningfully with Edgebar size
                check(pomodoroHgByProfile["square"] > pomodoroHgByProfile["default"] + 25,
                    "Pomodoro hourglass should scale up on 450x450 vs 420x300: " + JSON.stringify(pomodoroHgByProfile))
                check(pomodoroHgByProfile["large"] >= pomodoroHgByProfile["square"],
                    "Pomodoro hourglass should scale up on 720x640 vs 450x450: " + JSON.stringify(pomodoroHgByProfile))
                check(countdownHgByProfile["square"] > countdownHgByProfile["default"] + 20,
                    "Countdown hourglass should scale up on 450x450 vs 420x300: " + JSON.stringify(countdownHgByProfile))

                // Verify monotonic jump-free mainTabs sweep from 280px to 420px
                let prevTabW = 0
                for (let sw = 280; sw <= 420; sw += 10) {
                    Config.setNestedValue("quickNotes.popupWidth", sw)
                    settle(25)
                    const mTabs = findByObjectName(leftContentHost, "quickNotesMainTabs")
                    const pBtn = findByObjectName(leftContentHost, "quickNotesPopupPin")
                    const rMT = assertInside(mTabs, leftContentHost, "sweep " + sw + " mainTabs")
                    const rPB = assertInside(pBtn, leftContentHost, "sweep " + sw + " pinBtn")
                    check(rMT.w >= prevTabW - 0.5, "mainTabs shrank when widening popup to " + sw + ": " + prevTabW + " -> " + rMT.w)
                    check(rMT.right + 6 <= rPB.x, "sweep " + sw + ": mainTabs overlaps pinBtn")
                    if (sw >= 320) {
                        check(Math.abs((rMT.x + rMT.w / 2) - leftContentHost.width / 2) <= 2.0,
                            "sweep " + sw + ": mainTabs should be centered once symmetric room exists")
                    }
                    prevTabW = rMT.w
                }

                // Stress test: 280x300 + fontSizeScale=1.3 + todayBadge + long tag + paused Resume + DashTodo + Stopwatch + 3-digit PillTabBar badge
                Config.setNestedValue("quickNotes.popupWidth", 280)
                Config.setNestedValue("quickNotes.popupHeight", 300)
                Config.setNestedValue("appearance.typography.sizeScale", 1.3)
                TimerService.addTag("Quantum Mechanics Research", "#ff6b6b")
                TimerService.setActiveTag("Quantum Mechanics Research")
                Persistent.states.timer.pomodoro.todayDate = TimerService._todayIsoDate()
                Persistent.states.timer.pomodoro.todaySessions = 5
                Persistent.states.timer.pomodoro.todayFocusSeconds = 7500
                TimerService.pomodoroLongBreak = true
                TimerService.pomodoroRunning = true
                TimerService.pomodoroPaused = true
                TimerService.pomodoroSecondsLeft = 890
                TimerService.pomodoroLapDuration = 900
                leftPopup.selectedMainTab = 1
                const modeBarStress = findByObjectName(leftContentHost, "timerModeTabBar")
                const pomoWidgetStress = modeBarStress.parent.parent.parent
                pomoWidgetStress.currentTab = 0
                settle(90)

                const sPHeader = findByObjectName(leftContentHost, "pomodoroFocusHeader")
                const sPControls = findByObjectName(leftContentHost, "pomodoroControlsRow")
                const sPStart = findByObjectName(leftContentHost, "pomodoroStartButton")
                const sPReset = findByObjectName(leftContentHost, "pomodoroResetButton")
                assertInside(sPHeader, leftContentHost, "stress 280 scale13 pomodoroHeader")
                check(sPHeader.implicitWidth <= sPHeader.width + 1.5,
                    "stress 280 scale13 header overflowed (" + sPHeader.implicitWidth + " > " + sPHeader.width + ")")
                assertInside(sPControls, leftContentHost, "stress 280 scale13 pomodoroControls")
                check(sPStart.contentItem.implicitWidth <= sPStart.width - 8,
                    "stress 280 scale13 Resume text overflows Start button (" + sPStart.contentItem.implicitWidth + " vs " + sPStart.width + ")")
                check(sPReset.contentItem.children[1].implicitWidth <= sPReset.width - 8,
                    "stress 280 scale13 Reset text overflows Reset button (" + sPReset.contentItem.children[1].implicitWidth + " vs " + sPReset.width + ")")

                // Stopwatch stress at 280x300 + scale=1.3 + 3-digit minutes + laps
                pomoWidgetStress.currentTab = 2
                TimerService.stopwatchTime = 754389
                TimerService.stopwatchLaps = [12034, 25089, 41200]
                settle(80)
                const sSwStart = findByObjectName(leftContentHost, "stopwatchStartButton")
                const sSwReset = findByObjectName(leftContentHost, "stopwatchResetButton")
                assertInside(findByObjectName(leftContentHost, "stopwatchElapsed"), leftContentHost, "stress 280 scale13 stopwatchElapsed")
                assertInside(sSwStart, leftContentHost, "stress 280 scale13 stopwatchStart")
                assertInside(sSwReset, leftContentHost, "stress 280 scale13 stopwatchReset")
                check(sSwStart.contentItem.implicitWidth <= sSwStart.width - 8,
                    "stress 280 scale13 Stopwatch Resume overflows button")
                TimerService.stopwatchReset()

                // PillTabBar 3-digit badge (count=128) at scale=1.3 must expand pill and avoid label collision
                const probeRow = badgeProbeTabs.children[2]
                const firstTab = probeRow.children[0]
                const firstLabelRow = firstTab.children[0]
                const firstBadge = firstTab.children[1]
                const firstBadgeText = firstBadge.children[0]
                const rFirstLabel = assertInside(firstLabelRow, firstTab, "scale13 PillTabBar badge label")
                const rFirstBadge = assertInside(firstBadge, firstTab, "scale13 PillTabBar badge pill")
                check(firstBadgeText.implicitWidth <= firstBadge.width - 4,
                    "scale13 3-digit badge text overflows pill (" + firstBadgeText.implicitWidth + " vs " + firstBadge.width + ")")
                check(rFirstLabel.right + 2 <= rFirstBadge.x,
                    "scale13 PillTabBar label collides with 3-digit badge (" + rFirstLabel.right + " vs " + rFirstBadge.x + ")")

                // DashTodo stress at 280x300 + scale=1.3: "Unfinished" icon+label must stay inside half-pill and clear count badge
                leftPopup.selectedMainTab = 0
                leftPopup.selectedNotesTab = 1
                settle(90)
                function findTextItem(node, wanted) {
                    if (!node) return null
                    if (node.text === wanted) return node
                    const ch = node.children || []
                    for (let i = 0; i < ch.length; i++) {
                        const hit = findTextItem(ch[i], wanted)
                        if (hit) return hit
                    }
                    return null
                }
                const unfinishedText = findTextItem(leftContentHost, "Unfinished")
                check(!!unfinishedText, "stress 280 scale13 DashTodo Unfinished label missing")
                const leftTabRow = unfinishedText.parent
                const leftHalfSlot = leftTabRow.parent
                const leftBadgeRect = leftHalfSlot.children[1]
                const rTodoLabel = assertInside(leftTabRow, leftHalfSlot, "stress 280 scale13 DashTodo leftTabLabel")
                const rTodoBadge = assertInside(leftBadgeRect, leftHalfSlot, "stress 280 scale13 DashTodo leftBadge")
                check(rTodoLabel.right + 2 <= rTodoBadge.x,
                    "stress 280 scale13 DashTodo Unfinished collides with badge (" + rTodoLabel.right + " vs " + rTodoBadge.x + ")")

                // Restore clean defaults before Right Edgebar checks
                Config.setNestedValue("appearance.typography.sizeScale", 1.0)
                TimerService.setActiveTag("Study")
                Persistent.states.timer.pomodoro.todaySessions = 0
                Persistent.states.timer.pomodoro.todayFocusSeconds = 0
                TimerService.pomodoroRunning = false
                TimerService.pomodoroPaused = false
                TimerService.pomodoroLongBreak = false
                TimerService.pomodoroSecondsLeft = TimerService.focusTime
                TimerService.pomodoroLapDuration = TimerService.focusTime
                settle(50)

                // 5. Right Edgebar (NotificationCenterPopup) across Settings size range (320..760 x 260..900)
                leftStageFrame.visible = false
                rightStageFrame.visible = true
                const rightProfiles = [
                    { name: "compact", w: 320, h: 260, minAppLimit: 2, maxAppLimit: 2 },
                    { name: "default", w: 420, h: 560, minAppLimit: 8, maxAppLimit: 12 },
                    { name: "wide_short", w: 760, h: 260, minAppLimit: 2, maxAppLimit: 2 },
                    { name: "large", w: 760, h: 900, minAppLimit: 14, maxAppLimit: 16 }
                ]

                for (let j = 0; j < rightProfiles.length; j++) {
                    const rp = rightProfiles[j]
                    Config.setNestedValue("notificationCenter.popupWidth", rp.w)
                    Config.setNestedValue("notificationCenter.popupHeight", rp.h)
                    settle(90)

                    check(rightPopup.requestedPopupWidth === rp.w, "right " + rp.name + ": width mismatch")
                    check(rightPopup.requestedPopupHeight === rp.h, "right " + rp.name + ": height mismatch")
                    check(rightPopup.visibleAppLimit >= rp.minAppLimit && rightPopup.visibleAppLimit <= rp.maxAppLimit,
                        "right " + rp.name + ": visibleAppLimit out of range (" + rightPopup.visibleAppLimit + ")")

                    const nTabs = findByObjectName(rightContentHost, "notificationCenterMainTabs")
                    check(!!nTabs, "right " + rp.name + ": main tabs missing")
                    const rNTabs = assertInside(nTabs, rightContentHost, "right " + rp.name + " mainTabs")
                    check(Math.abs((rNTabs.x + rNTabs.w / 2) - rightContentHost.width / 2) <= 2.0,
                        "right " + rp.name + ": tabs must stay horizontally centered")

                    rightPopup.selectedTab = 0
                    settle(50)
                    rightPopup.selectedTab = 1
                    settle(60)
                    const actPane = findByObjectName(rightContentHost, "notificationCenterActivityPane")
                    check(!!actPane, "right " + rp.name + ": activity pane missing")
                    assertInside(actPane, rightContentHost, "right " + rp.name + " activityPane")
                    const actEmpty = findByObjectName(rightContentHost, "notificationCenterActivityEmpty")
                    if (actEmpty && actEmpty.visible) {
                        const rEmpty = assertInside(actEmpty, actPane, "right " + rp.name + " activityEmpty")
                        check(Math.abs((rEmpty.x + rEmpty.w / 2) - actPane.width / 2) <= 2.5,
                            "right " + rp.name + ": activity empty state not centered (" + (rEmpty.x + rEmpty.w / 2) + " vs " + (actPane.width / 2) + ")")
                    }

                    if (rp.name === "compact" || rp.name === "large") {
                        maybeGrab(rightStageFrame, "right_activity_" + rp.name + ".png")
                    }
                }

                // Verify wide Right Edgebar allocates more width for app names
                Config.setNestedValue("notificationCenter.popupWidth", 320)
                settle(40)
                const narrowNameW = rightPopup._appNameWidth
                Config.setNestedValue("notificationCenter.popupWidth", 760)
                settle(40)
                const wideNameW = rightPopup._appNameWidth
                check(wideNameW > narrowNameW + 80,
                    "Right Edgebar app name column should widen responsively (" + narrowNameW + " -> " + wideNameW + ")")

                // 6. Verify populated Activity rows (12 synthetic apps) adapt without clipping
                const syntheticApps = {}
                for (let k = 1; k <= 12; k++) {
                    syntheticApps["app" + k] = {
                        name: "Application Number " + k,
                        seconds: (13 - k) * 600,
                        originalId: "app" + k
                    }
                }
                ScreenTime._todayData = { date: "2026-11-22", totalSeconds: 46800, hourly: new Array(24).fill(0), apps: syntheticApps }
                ScreenTime.dataChanged()
                settle(60)

                Config.setNestedValue("notificationCenter.popupWidth", 320)
                Config.setNestedValue("notificationCenter.popupHeight", 260)
                settle(70)
                check(rightPopup.visibleApps.length === 2 && rightPopup.hiddenAppCount === 10,
                    "320x260 populated Activity should show 2 apps +10 hidden, got " + rightPopup.visibleApps.length + "/" + rightPopup.hiddenAppCount)
                assertInside(findByObjectName(rightContentHost, "notificationCenterActivityPane"), rightContentHost, "populated 320x260 activityPane")

                Config.setNestedValue("notificationCenter.popupWidth", 420)
                Config.setNestedValue("notificationCenter.popupHeight", 560)
                settle(70)
                check(rightPopup.visibleApps.length >= 8 && rightPopup.visibleApps.length <= 12,
                    "420x560 populated Activity should fill available height (got " + rightPopup.visibleApps.length + ")")
                assertInside(findByObjectName(rightContentHost, "notificationCenterActivityPane"), rightContentHost, "populated 420x560 activityPane")

                Config.setNestedValue("notificationCenter.popupWidth", 760)
                Config.setNestedValue("notificationCenter.popupHeight", 900)
                settle(70)
                check(rightPopup.visibleApps.length === 12 && rightPopup.hiddenAppCount === 0,
                    "760x900 populated Activity should show all 12 apps, got " + rightPopup.visibleApps.length)
                assertInside(findByObjectName(rightContentHost, "notificationCenterActivityPane"), rightContentHost, "populated 760x900 activityPane")

                // Clamped tiny output height: visibleAppLimit hits 0 while todayApps > 0 -> empty state must NOT falsely show
                rightStageFrame.height = 140
                settle(60)
                check(rightPopup.visibleAppLimit === 0, "140px clamped height should yield visibleAppLimit=0, got " + rightPopup.visibleAppLimit)
                const clampedEmpty = findByObjectName(rightContentHost, "notificationCenterActivityEmpty")
                check(!clampedEmpty || !clampedEmpty.visible,
                    "Activity empty placeholder must stay hidden when apps exist even if clamped height hides rows")
                rightStageFrame.height = Qt.binding(() => rightPopup.requestedPopupHeight)
                settle(40)

                // 7. Verify standalone Sidebar Right PomodoroWidget (compactMode: false, showPinButton: true)
                // Also verify switching back from Stopwatch (tab 2) after resize re-layouts cleanly!
                rightStageFrame.visible = false
                sidebarTimerHost.visible = true
                sidebarTimerWidget.currentTab = 0
                for (const sz of [{ w: 320, h: 280 }, { w: 440, h: 360 }]) {
                    sidebarTimerHost.width = sz.w
                    sidebarTimerHost.height = sz.h
                    settle(80)
                    const sbBar = findByObjectName(sidebarTimerHost, "timerModeTabBar")
                    const sbDial = findByObjectName(sidebarTimerHost, "pomodoroFocusDial")
                    const sbCtrl = findByObjectName(sidebarTimerHost, "pomodoroControlsRow")
                    check(!!sbBar && !!sbDial && !!sbCtrl, "Sidebar PomodoroWidget elements missing")
                    const rSbBar = assertInside(sbBar, sidebarTimerHost, "sidebar tabBar " + sz.w)
                    check(Math.abs((rSbBar.x + rSbBar.w / 2) - sidebarTimerHost.width / 2) <= 2.0,
                        "sidebar tabBar must remain centered with showPinButton=true")
                    assertInside(sbDial, sidebarTimerHost, "sidebar focusDial " + sz.w)
                    assertInside(sbCtrl, sidebarTimerHost, "sidebar controls " + sz.w)
                }

                // Edge case: resize while on Stopwatch (tab 2), then switch back to Pomodoro (tab 0)
                sidebarTimerWidget.currentTab = 2
                settle(40)
                sidebarTimerHost.width = 300
                sidebarTimerHost.height = 260
                settle(40)
                sidebarTimerWidget.currentTab = 0
                settle(80)
                assertInside(findByObjectName(sidebarTimerHost, "pomodoroFocusDial"), sidebarTimerHost, "post-tab-switch focusDial")
                assertInside(findByObjectName(sidebarTimerHost, "pomodoroControlsRow"), sidebarTimerHost, "post-tab-switch controls")

                console.info("EDGEBAR_RESPONSIVE_LAYOUT_RUNTIME_PASS",
                    "pomodoroHg=" + JSON.stringify(pomodoroHgByProfile),
                    "countdownHg=" + JSON.stringify(countdownHgByProfile))
            } catch (e) {
                console.error("EDGEBAR_RESPONSIVE_LAYOUT_RUNTIME_FAIL:", e.message, e.stack || "")
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 80
        running: true
        onTriggered: test.run()
    }
}
'''


def check_static_contracts() -> None:
    pomodoro = (ROOT / "modules/sidebarRight/pomodoro/PomodoroTimer.qml").read_text(encoding="utf-8")
    assert "id: progressTrack" not in pomodoro, "PomodoroTimer must remove linear progressTrack above Start"
    assert "id: progressFill" not in pomodoro, "PomodoroTimer must remove linear progressFill above Start"


OFFSCREEN_STYLED_POPUP_STUB = r'''
import QtQuick

QtObject {
    id: root
    default property Item contentItem
    property Item hoverTarget: null
    property Item embeddedHost: null
    property string liquidPresentationKind: ""
    property var anchorRect: null
    property bool centerOnOutput: false
    property string tangentEdgeOverride: ""
    property string attachmentEdgeOverride: ""
    property real attachmentThicknessOverride: -1
    property bool hoverActivates: true
    property bool strictSourceHover: false
    property bool barAutoHideHoldEnabled: true
    property bool alternativeVisibleCondition: false
    property bool fifoAutoClosable: false
    property bool closeOnOutsideClick: false
    property bool outsideClickBackdropBelowPopup: false
    property bool keyboardFocus: false
    property bool keyboardFocusOnDemand: false
    property bool exclusiveKeyboardFocus: false
    property bool popupHovered: false
    property real popupBackgroundMargin: 0
    property bool connectAdjacentScreenEdge: false
    property bool presentationActive: true
    property bool _liquidDismissed: false
    property var _anchorHover: null
    readonly property real _contentPadding: 14
    signal requestClose()
    function retractPresentation(): void { requestClose() }
    function dismissPresentation(): void { _liquidDismissed = true; requestClose() }
}
'''


OFFSCREEN_CONTEXT_MENU_STUB = r'''
import QtQuick
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
'''


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dump-screenshots", default="", help="Optional dir for offscreen grabToImage PNGs")
    args = parser.parse_args()

    check_static_contracts()

    dump_dir = ""
    if args.dump_screenshots:
        p = Path(args.dump_screenshots).resolve()
        p.mkdir(parents=True, exist_ok=True)
        dump_dir = str(p)

    with tempfile.TemporaryDirectory(prefix="alis-edgebar-responsive-test-") as name:
        folder = Path(name)
        for entry in ["services", "qmldir", "GlobalStates.qml", "assets", "scripts", "defaults", "translations"]:
            (folder / entry).symlink_to(ROOT / entry)
        mod_dir = folder / "modules"
        mod_dir.mkdir()
        for child in (ROOT / "modules").iterdir():
            if child.name == "bar":
                bar_dir = mod_dir / "bar"
                bar_dir.mkdir()
                for bchild in child.iterdir():
                    if bchild.name == "StyledPopup.qml":
                        (bar_dir / "StyledPopup.qml").write_text(OFFSCREEN_STYLED_POPUP_STUB, encoding="utf-8")
                    else:
                        (bar_dir / bchild.name).symlink_to(bchild)
            elif child.name == "common":
                common_dir = mod_dir / "common"
                common_dir.mkdir()
                for cchild in child.iterdir():
                    if cchild.name == "widgets":
                        w_dir = common_dir / "widgets"
                        w_dir.mkdir()
                        for wchild in cchild.iterdir():
                            if wchild.name == "ContextMenu.qml":
                                (w_dir / "ContextMenu.qml").write_text(OFFSCREEN_CONTEXT_MENU_STUB, encoding="utf-8")
                            else:
                                (w_dir / wchild.name).symlink_to(wchild)
                    else:
                        (common_dir / cchild.name).symlink_to(cchild)
            else:
                (mod_dir / child.name).symlink_to(child)

        (folder / "shell.qml").write_text(QML_TEMPLATE.replace("__DUMP_DIR__", dump_dir), encoding="utf-8")
        config = folder / "config" / "alis"
        config.mkdir(parents=True, exist_ok=True)
        raw = json.loads((ROOT / "defaults" / "config.json").read_text(encoding="utf-8"))
        raw["panelFamily"] = "abyss"
        (config / "config.json").write_text(json.dumps(raw), encoding="utf-8")

        env = {
            "QT_QPA_PLATFORM": "offscreen",
            "XDG_CONFIG_HOME": str(folder / "config"),
            "XDG_STATE_HOME": str(folder / "state"),
            "XDG_CACHE_HOME": str(folder / "cache"),
            "XDG_DATA_HOME": str(folder / "data"),
        }
        if not dump_dir:
            env["QT_QUICK_BACKEND"] = "software"
        else:
            os.environ.pop("QT_QUICK_BACKEND", None)

        res = run_qs(folder, env, timeout=45)
        print(res.stdout.strip())
        bad = [
            "EDGEBAR_RESPONSIVE_LAYOUT_RUNTIME_FAIL",
            "ReferenceError:",
            "TypeError:",
            "Unable to assign",
            "Cannot assign",
            "Binding loop detected",
        ]
        if res.returncode != 0 or "EDGEBAR_RESPONSIVE_LAYOUT_RUNTIME_PASS" not in res.stdout or any(b in res.stdout for b in bad):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
