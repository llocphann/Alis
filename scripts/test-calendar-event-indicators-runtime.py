#!/usr/bin/env python3
"""Private-Niri QML event dot count and overflow regression (no owner calendar data)."""
import json
import shutil
import tempfile
from pathlib import Path
from native_test_session import private_wayland, run_qs

ROOT = Path(__file__).resolve().parents[1]
if not shutil.which("qs"):
    print("SKIP: Calendar dots require Quickshell")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="alis-calendar-indicators-") as name:
    folder = Path(name)
    for entry in ["modules","services","GlobalStates.qml","qmldir","assets","scripts","defaults","translations"]:
        (folder / entry).symlink_to(ROOT / entry)
    config = folder/"config/illogical-impulse"
    config.mkdir(parents=True)
    shutil.copy2(ROOT/"defaults/config.json",config/"config.json")
    (folder/"shell.qml").write_text(r"""
pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
ShellRoot {
 id:root
 property int maxDots:3
 property int checks:0
 property var cells: Array.from({length:42}, (_,i) => ({
  date:new Date(2026,9,i+1),day:(i%31)+1,currentMonth:true,today:i===3,
  eventCount:[0,1,3,9,5][i] ?? 0,
  eventColors:Array.from({length:9},(_,k)=>k%2 ? "#c978ce" : "#42b9a9")
 }))
 Component.onCompleted:Quickshell.watchFiles=false
 function all(item,pred) {
  let result=pred(item)?[item]:[]
  for(const child of item.children ?? [])result=result.concat(all(child,pred))
  return result
 }
 FloatingWindow {
  visible:true;implicitWidth:420;implicitHeight:450;color:"#18282b"
  ObsidianMonthCalendar {
   id:calendar;x:16;y:16;width:implicitWidth;height:implicitHeight
   viewingDate:new Date(2026,9,1);today:new Date(2026,9,4)
   calendarCells:root.cells
   countedEventDots:true;showEventDots:root.maxDots>0;maxEventDots:root.maxDots
  }
 }
 TestCase {
  id:test;when:false;optional:true
  function check(ok,msg){root.checks++;if(!ok)throw new Error(msg)}
  function inspect(limit) {
   root.maxDots=limit;wait(80)
   const allDays=root.all(calendar,item=>item.objectName==="calendarEventDayCell")
   check(allDays.length===42,"calendar must retain 42 day cells: "+allDays.length)
   const samples=[0,1,3,9,5]
   for(let i=0;i<samples.length;i++){
    const cell=allDays.find(day=>day.index===i)
    check(!!cell,"missing day "+i)
    const dots=root.all(cell,item=>item.objectName==="calendarEventDot")
    const overflow=root.all(cell,item=>item.objectName==="calendarEventOverflow")
    check(dots.length===Math.min(samples[i],limit),
      "wrong dots on day "+i+" at max "+limit+": "+dots.length)
    check(overflow.length===1 &&
      overflow[0].visible===(limit>0 && samples[i]>limit),
      "overflow cue wrong on day "+i+" at max "+limit)
   }
  }
  function runChecks(){try{
   tryCompare(Config,"ready",true,6000)
   for(const max of [0,1,3,5])inspect(max)
   console.info("CALENDAR_EVENT_DOTS_NATIVE_PASS",root.checks,"checks: 42 days, 0/1/3/5 dots, overflow")
  }catch(error){console.error("CALENDAR_EVENT_DOTS_NATIVE_FAIL",error.message,error.stack)}Qt.quit()}
 }
 Timer{interval:100;running:true;onTriggered:test.runChecks()}
}
""")
    with private_wayland(folder) as env:
        if env is None:
            print("SKIP: Calendar dots require a private Niri backend")
            raise SystemExit(0)
        result = run_qs(folder,env,timeout=25)
    bad = ["CALENDAR_EVENT_DOTS_NATIVE_FAIL","ReferenceError:","TypeError:",
           "Binding loop","Unable to assign","is not a type","Failed to load configuration"]
    if result.returncode or "CALENDAR_EVENT_DOTS_NATIVE_PASS" not in result.stdout or any(t in result.stdout for t in bad):
        print(result.stdout)
        raise SystemExit(1)
    for line in result.stdout.splitlines():
        if "CALENDAR_EVENT_DOTS_NATIVE_PASS" in line:
            print(line)
