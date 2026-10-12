#!/usr/bin/env python3
"""Private offscreen Quickshell regression for one-write multi-date Agenda storage."""
import json
import os
import shutil
import tempfile
from pathlib import Path
from native_test_session import run_qs

ROOT = Path(__file__).resolve().parents[1]
if shutil.which("qs") is None:
    print("SKIP: planner multi-date storage runtime requires Quickshell")
    raise SystemExit(0)

QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.services
ShellRoot {
    id: root
    property int phase: 0
    property int checks: 0
    property int ticks: 0
    Component.onCompleted: Quickshell.watchFiles = false
    function check(value, message) {
        checks++
        if (!value) throw new Error(message)
    }
    Timer {
        interval: 30
        running: true
        repeat: true
        onTriggered: {
            try {
                root.ticks++
                if (root.ticks > 250) throw new Error("storage timeout phase " + root.phase)
                if (root.phase === 0 && Events.ready) {
                    root.check(Events.list.length === 0, "fixture not private")
                    const oldId = Events.nextId
                    const spans = [
                        {startDate:"2032-10-21T09:00:00Z",endDate:"2032-10-21T10:00:00Z"},
                        {startDate:"2032-10-18T09:00:00Z",endDate:"2032-10-18T10:00:00Z"},
                        {startDate:"2032-10-19T09:00:00Z",endDate:"2032-10-19T10:00:00Z"}
                    ]
                    const created=Events.addEvent("Multi-date private fixture","private",
                        "2032-10-21T09:00:00Z","meeting","normal",15,"none",
                        "2032-10-21T10:00:00Z",false,spans)
                    root.check(!!created && Events.list.length===1
                        && Events.nextId===oldId+1,
                        "a multi-date Add must create exactly one event id")
                    root.check(created.occurrences.length===3 && created.recurrence==="none",
                        "missing or repeating batch occurrences")
                    root.check(created.startDate==="2032-10-18T09:00:00.000Z",
                        "batch first occurrence not sorted/compatible")
                    root.check(!!created.todoLink && !!created.todoLink.key,
                        "one stable agenda-to-todo link was not generated")
                    const repeating=Events.addEvent("Weekly grouped fixture","private",
                        "2032-10-18T09:00:00Z","meeting","normal",15,"weekly",
                        "2032-10-18T10:00:00Z",false,spans)
                    root.check(!!repeating && repeating.occurrences.length===3
                        && repeating.repeatTemplate.length===3
                        && repeating.todoLink.key!==created.todoLink.key
                        && Events.list.length===2 && Events.nextId===oldId+2,
                        "compatible Weekly must persist one template and one ID")
                    const before=Events.nextId
                    const invalid=Events.addEvent("Invalid daily multi-day","",
                        "2032-10-18T09:00:00Z","general","normal",15,"daily",
                        "2032-10-18T10:00:00Z",false,spans)
                    root.check(invalid===null && Events.nextId===before
                        && Events.list.length===2,
                        "invalid Daily/group must reject before mutating storage")
                    // A past cycle should be advanced in one write with the
                    // original Todo identity and all three selected weekdays.
                    const today=new Date()
                    const monday=new Date(today.getFullYear(),today.getMonth(),today.getDate(),9)
                    monday.setDate(monday.getDate()-(monday.getDay()+6)%7-14)
                    const past=[0,1,3].map(delta=>{
                        const start=new Date(monday)
                        start.setDate(start.getDate()+delta)
                        const end=new Date(start);end.setHours(end.getHours()+1)
                        return {startDate:start.toISOString(),endDate:end.toISOString()}
                    })
                    const cyclic=Events.addEvent("Past weekly recurrence","private",
                        past[0].startDate,"meeting","normal",15,"weekly",
                        past[0].endDate,false,past)
                    root.check(!!cyclic && Events.list.length===3,
                        "past recurrence not created")
                    const originalLink=cyclic.todoLink.key
                    Events.checkDueEvents()
                    const advanced=Events.list.find(event=>event.id===cyclic.id)
                    root.check(!!advanced && advanced.todoLink.key===originalLink
                        && advanced.occurrences.length===6
                        && advanced.occurrences.slice(0,3).every(slot=>slot.notified)
                        && advanced.occurrences.slice(3).every(slot=>!slot.notified),
                        "recurring group was not advanced under the same ID")
                    root.check(advanced.occurrences.slice(3).every(slot=>
                        new Date(slot.startDate)>today),
                        "next recurring group was not scheduled in the future")
                    root.phase=1
                } else if(root.phase===1 && !Events.persistenceBusy) {
                    const saved=Events.getDurableEvents()
                    root.check(saved.length===3 && saved[0].occurrences.length===3
                        && saved[1].repeatTemplate.length===3
                        && saved[2].occurrences.length===6,
                        "grouped recurring and nonrecurring events not durably stored")
                    root.check(saved.every((event,index)=>
                        event.todoLink.key===Events.list[index].todoLink.key),
                        "recurring batch changed its Todo identity")
                    console.info("PLANNER_MULTIDATE_STORAGE_PASS",root.checks)
                    Qt.quit()
                }
            } catch(error) {
                console.error("PLANNER_MULTIDATE_STORAGE_FAIL",error.message,error.stack)
                Qt.quit()
            }
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix="alis-planner-multidate-") as temp:
    folder=Path(temp)
    for entry in ["modules","services","qmldir","GlobalStates.qml",
                  "assets","scripts","defaults","translations"]:
        (folder/entry).symlink_to(ROOT/entry)
    (folder/"shell.qml").write_text(QML)
    env=dict(os.environ,QT_QPA_PLATFORM="offscreen",QT_QUICK_BACKEND="software")
    for key in ["QS_CONFIG_NAME","QS_CONFIG_PATH","QS_MANIFEST","NIRI_SOCKET","WAYLAND_DISPLAY"]:
        env.pop(key,None)
    for kind in ["config","state","cache","data","runtime"]:
        location=folder/kind
        location.mkdir(mode=0o700)
        env["XDG_"+kind.upper()+("_DIR" if kind=="runtime" else "_HOME")]=str(location)
    config=folder/"config/illogical-impulse"
    config.mkdir()
    (config/"config.json").write_bytes((ROOT/"defaults/config.json").read_bytes())
    storage=folder/"state/quickshell/user/events.json"
    storage.parent.mkdir(parents=True)
    storage.write_text(json.dumps({"nextId":1,"events":[]}))
    result=run_qs(folder,env,timeout=18)
    if result.returncode or "PLANNER_MULTIDATE_STORAGE_PASS" not in result.stdout or any(
        token in result.stdout for token in [
            "PLANNER_MULTIDATE_STORAGE_FAIL","ReferenceError:","TypeError:",
            "Failed to load configuration","Unable to assign"
        ]
    ):
        print(result.stdout)
        raise SystemExit(1)
    saved=json.loads(storage.read_text())["events"]
    assert len(saved)==3 and len(saved[0]["occurrences"])==3
    assert saved[0]["recurrence"]=="none"
    assert saved[1]["recurrence"]=="weekly" and len(saved[1]["repeatTemplate"])==3
    assert len(saved[2]["occurrences"])==6
    assert len({row["todoLink"]["key"] for row in saved})==3
    print(next(line for line in result.stdout.splitlines()
               if "PLANNER_MULTIDATE_STORAGE_PASS" in line))
