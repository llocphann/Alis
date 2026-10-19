#!/usr/bin/env python3
"""DASH-I13: exercise real Events persistence/restart in isolated XDG storage."""
from datetime import datetime, timedelta
import json
import os
from pathlib import Path
import shutil
import tempfile

from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
if shutil.which("qs") is None:
    print("SKIP: recurring storage fixture requires Quickshell")
    raise SystemExit(0)

QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
import "modules/dashboard/WeeklyPlannerPolicy.js" as Planner
ShellRoot {
    id: root
    property int phase: 0
    property int ticks: 0
    function check(ok, message) { if (!ok) throw new Error(message) }
    Component.onCompleted: Quickshell.watchFiles = false
    Timer {
        interval: 30; running: true; repeat: true
        onTriggered: {
            try {
                if (++root.ticks>250) throw new Error("fixture timeout")
                if (!Events.ready) return
                root.check(Events.filePath===Quickshell.env("ALIS_PLANNER_TEST_EVENTS"),
                    "Events storage escaped the private fixture")
                if (root.phase===0) {
                    root.check(Events.list.length===4, "unexpected fixture records")
                    Events.checkDueEvents()
                    root.phase=1
                } else if (!Events.persistenceBusy) {
                    const rows=Events.getDurableEvents()
                    root.check(rows.length===4 && Events.nextId===50, "event IDs changed")
                    root.check(rows[0].occurrences.length===2
                        && rows[1].occurrences.length===4
                        && rows[2].occurrences.length===3
                        && rows[3].occurrences.length===1, "incorrect durable cycles")
                    root.check(rows[0].todoLink.key==="keep-fixture-link", "legacy metadata lost")
                    root.check(rows[2].repeatTemplate.length===1
                        && rows[2].repeatCycleStart===2, "history became the active pattern")
                    for (let i=0;i<3;i++) {
                        const event=rows[i]
                        root.check(event.occurrences.slice(event.repeatCycleStart).every(
                            slot=>!slot.notified && new Date(slot.startDate)>new Date()),
                            "missing future recurrence")
                    }
                    const date=new Date(rows[0].occurrences[1].startDate)
                    const projected=Planner.project(rows,[],date,1)
                        .reduce((all,day)=>all.concat(day.timed),[])
                    root.check(projected.length===4, "Planner lost or duplicated future dates")
                    console.info("PLANNER_RECURRING_STORAGE_PASS",Quickshell.env("ALIS_PLANNER_TEST_MODE"))
                    Qt.quit()
                }
            } catch (error) {
                console.error("PLANNER_RECURRING_STORAGE_FAIL",error.message)
                Qt.quit()
            }
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-planner-rollover-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "services", "qmldir", "GlobalStates.qml", "assets",
                 "scripts", "defaults", "translations"):
        (folder / name).symlink_to(ROOT / name)
    (folder / "shell.qml").write_text(QML)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software")
    for key in ("QS_CONFIG_NAME", "QS_CONFIG_PATH", "QS_MANIFEST", "NIRI_SOCKET", "WAYLAND_DISPLAY"):
        env.pop(key, None)
    for kind in ("config", "state", "cache", "data", "runtime"):
        location = folder / kind
        location.mkdir(mode=0o700)
        env["XDG_" + kind.upper() + ("_DIR" if kind == "runtime" else "_HOME")] = str(location)
    config = folder / "config/illogical-impulse"
    config.mkdir()
    (config / "config.json").write_bytes((ROOT / "defaults/config.json").read_bytes())
    storage = folder / "state/quickshell/user/events.json"
    storage.parent.mkdir(parents=True)
    monday = datetime.now().replace(hour=9, minute=0, second=0, microsecond=0)
    monday -= timedelta(days=monday.weekday() + 14)

    def slot(offset):
        start = monday + timedelta(days=offset)
        return {"startDate": start.isoformat(), "endDate": (start + timedelta(hours=1)).isoformat(),
                "notified": True, "reminderNotified": True}

    fixture = {"nextId": 50, "events": [
        {"id": 41, "title": "Single fixture", "recurrence": "weekly", "occurrences": [slot(1)],
         "todoLink": {"key": "keep-fixture-link"}},
        {"id": 42, "title": "Group fixture", "recurrence": "weekly", "occurrences": [slot(1), slot(3)]},
        {"id": 43, "title": "History fixture", "recurrence": "weekly", "occurrences": [slot(-6), slot(1)],
         "selectedTemplate": [slot(1)]},
        {"id": 44, "title": "One-time fixture", "recurrence": "none", "occurrences": [slot(1)]},
    ], "todoUnlinks": [{"key": "preserve-unlink"}], "futureMetadata": {"preserve": True}}
    storage.write_text(json.dumps(fixture))
    env["ALIS_PLANNER_TEST_EVENTS"] = str(storage)
    persisted = None
    for mode in ("initial", "restart"):
        env["ALIS_PLANNER_TEST_MODE"] = mode
        result = run_qs(folder, env, timeout=18)
        if result.returncode or "PLANNER_RECURRING_STORAGE_PASS" not in result.stdout or any(
            token in result.stdout for token in ("PLANNER_RECURRING_STORAGE_FAIL",
                                                 "ReferenceError:", "TypeError:",
                                                 "Failed to load configuration")
        ):
            print(result.stdout)
            raise SystemExit(1)
        raw = storage.read_bytes()
        data = json.loads(raw)
        assert data["nextId"] == fixture["nextId"]
        assert [row["id"] for row in data["events"]] == [41, 42, 43, 44]
        assert data["futureMetadata"] == fixture["futureMetadata"]
        assert data["todoUnlinks"] == fixture["todoUnlinks"]
        assert data["events"][3] == fixture["events"][3]
        if persisted is not None:
            assert raw == persisted, "restart or repeated tick rewrote/duplicated the saved cycles"
        persisted = raw
        print(next(line for line in result.stdout.splitlines() if "PLANNER_RECURRING_STORAGE_PASS" in line))
