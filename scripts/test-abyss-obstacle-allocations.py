#!/usr/bin/env python3
"""Native QV4 parity for production Perimeter obstacle bindings.

--proposal checks an in-memory candidate before any runtime edit. Default mode
extracts the actual current production bindings. No shell/service is restarted.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "scripts/fixtures/abyss-obstacle-bindings.json"
SOURCE = ROOT / "modules/abyss/AbyssPerimeter.qml"

PROPOSAL = {
    "sideObstacles": """{
                // Keep the filter phase before either selected record read.
                const leftVisible = leftPanel.progress > 0.001
                const rightVisible = rightPanel.progress > 0.001
                const result = []
                if (leftVisible) result.push(leftPanel.record)
                if (rightVisible) result.push(rightPanel.record)
                return result
            }""",
    "dockObstacles": """{
                    // Keep the first concat's evaluation/copy phase intact.
                    const result = window.sideObstacles.concat(notification.progress > 0.001 ? [notification.record] : [])
                    if (popup.progress > 0.001) result.push(popup.record)
                    return result
                }""",
}


def expressions(source: str) -> dict[str, str]:
    start = source.index("readonly property var sideObstacles:")
    end = source.index("\n            AbyssSpectrumController", start)
    side = source[start:end].split(":", 1)[1].strip()
    start = source.index("                id: dock\n")
    start = source.index("                obstacles:", start)
    end = source.index("\n                source:", start)
    dock = source[start:end].split(":", 1)[1].strip()
    return {"sideObstacles": side, "dockObstacles": dock}


def component(values: dict[str, str]) -> str:
    return """import QtQuick
QtObject {
    id: window
    property QtObject leftPanel
    property QtObject rightPanel
    property QtObject notification
    property QtObject popup
    property var signals: [0,0]
    onSideObstaclesChanged: signals[0]++
    onDockObstaclesChanged: signals[1]++
""" + "\n".join(f"    readonly property var {name}: {value}"
                    for name, value in values.items()) + "\n}\n"


def functions(values: dict[str, str], suffix: str) -> str:
    result = []
    for name, expression in values.items():
        body = expression[1:-1] if expression.startswith("{") else "return " + expression
        result.append(f"function {name}{suffix}(window,leftPanel,rightPanel,notification,popup) {{\n{body}\n}}")
    return "\n".join(result)


HARNESS = r'''//@ pragma ShellId alis-abyss-obstacle-allocation-oracle
import QtQuick
import Quickshell
import "Oracle.js" as Oracle
ShellRoot {
    id: test
    property int cases: 0
    property int step: 0
    property var publications: null
    property QtObject left: QtObject { property real progress: 0; property var record: ({id:"left"}) }
    property QtObject right: QtObject { property real progress: 0; property var record: ({id:"right"}) }
    property QtObject notice: QtObject { property real progress: 0; property var record: ({id:"notice"}) }
    property QtObject floating: QtObject { property real progress: 0; property var record: ({id:"popup"}) }
    Baseline { id: before; leftPanel:test.left; rightPanel:test.right; notification:test.notice; popup:test.floating }
    Candidate { id: after; leftPanel:test.left; rightPanel:test.right; notification:test.notice; popup:test.floating }
    function check(ok,label) { if (!ok) throw new Error(label) }
    function sameArray(a,b,label) {
        check(Array.isArray(a) && Array.isArray(b),label+": array")
        check(a.length===b.length,label+": length")
        for (let i=0;i<a.length;i++) {
            check((i in a)===(i in b),label+": hole")
            check(Object.is(a[i],b[i]),label+": record identity/order "+i)
        }
    }
    function outcome(fn,args) {
        try { return {value:fn.apply(null,args),error:""} }
        catch(error) { return {error:error.name+":"+error.message} }
    }
    function compare(name,make) {
        const a=make(),b=make()
        const oldValue=outcome(Oracle[name+"Old"],a.args)
        const newValue=outcome(Oracle[name+"New"],b.args)
        check(oldValue.error===newValue.error,name+": first error")
        sameArray(a.trace,b.trace,name+": read/coercion order")
        if (!oldValue.error) {
            sameArray(oldValue.value,newValue.value,name)
            check(newValue.value!==b.sides,name+": input identity")
            const snapshot=newValue.value.slice()
            const again=Oracle[name+"New"].apply(null,b.args)
            check(again!==newValue.value,name+": fresh publication")
            sameArray(snapshot,newValue.value,name+": retained publication unchanged")
        }
        cases++
    }
    function inputs(progress,records,sides,throwAt,coerce) {
        const trace=[]
        function read(object,key,label,value) {
            Object.defineProperty(object,key,{get:function() {
                trace.push(label)
                if (label===throwAt) throw new Error("bad "+label)
                if (coerce && key==="progress") return {valueOf:function() {
                    trace.push(label+".valueOf");return value
                }}
                return value
            }})
        }
        const bodies=[{},{},{},{}]
        for (let i=0;i<4;i++) {
            read(bodies[i],"progress",["left","right","notice","popup"][i]+".progress",progress[i])
            read(bodies[i],"record",["left","right","notice","popup"][i]+".record",records[i])
        }
        const window={}
        read(window,"sideObstacles","sides",sides)
        return {args:[window,...bodies],trace:trace,sides:sides}
    }
    function pure() {
        const levels=[undefined,null,false,true,"bad","0.001","0.0011",-0,0,.0009,.001,.0011,1,NaN,Infinity,-Infinity]
        const marker={id:"same"},other={id:"other"}
        const records=[marker,other,marker,["nested",marker]]
        for (const l of levels) for (const r of levels) {
            compare("sideObstacles",()=>inputs([l,r,0,0],records,[],"",false))
            compare("sideObstacles",()=>inputs([l,r,0,0],records,[],"",true))
        }
        const sparse=new Array(3);sparse[1]=marker
        const sets=[[],[marker],[marker,marker],sparse,[null,undefined,NaN,-0],[[marker],other]]
        for (const n of levels) for (const p of levels) for (const sides of sets)
            compare("dockObstacles",()=>inputs([0,0,n,p],records,sides,"",false))
        for (let bits=0;bits<16;bits++) {
            const levels=[0,1,2,3].map(i=>(bits>>i)&1)
            for (const throwAt of ["left.progress","right.progress","left.record","right.record",
                    "sides","notice.progress","notice.record","popup.progress","popup.record"])
                for (const name of ["sideObstacles","dockObstacles"])
                    compare(name,()=>inputs(levels,records,[marker,other],throwAt,false))
        }
        for (const malformed of [null,undefined,false,NaN,-0,"",[],{},test.left]) {
            const rs=[malformed,malformed,malformed,malformed]
            compare("sideObstacles",()=>inputs([1,1,1,1],rs,[],"",false))
            compare("dockObstacles",()=>inputs([1,1,1,1],rs,[marker,marker],"",false))
        }
        // Reads/coercions can reenter; all progress tests must finish first.
        for (const name of ["sideObstacles","dockObstacles"]) compare(name,()=>{
            const trace=[],window={sideObstacles:[]},left={},right={progress:1,record:marker}
            Object.defineProperty(left,"progress",{get:()=>{trace.push("left.progress");return 1}})
            Object.defineProperty(left,"record",{get:()=>{
                trace.push("left.record");right.progress=0;return other
            }})
            return {args:[window,left,right,{progress:1,record:marker},{progress:1,record:other}],trace:trace}
        })
    }
    function bindings() {
        sameArray(before.sideObstacles,after.sideObstacles,"reactive side")
        sameArray(before.dockObstacles,after.dockObstacles,"reactive dock")
        sameArray(before.signals,after.signals,"NOTIFY count")
        check(after.sideObstacles!==after.dockObstacles,"independent output arrays")
        if (publications) {
            sameArray(publications.side,publications.sideCopy,"retained side array")
            sameArray(publications.dock,publications.dockCopy,"retained dock array")
        }
        publications={side:after.sideObstacles,sideCopy:after.sideObstacles.slice(),
            dock:after.dockObstacles,dockCopy:after.dockObstacles.slice()}
    }
    Component.onCompleted: {
        try { pure();bindings() }
        catch(error) { console.error("OBSTACLE_ORACLE_FAIL",error.message,error.stack);Qt.callLater(()=>Qt.quit()) }
    }
    Timer {
        interval:10;repeat:true;running:true
        onTriggered: {
            try {
                bindings()
                if (step===0) left.progress=.001
                if (step===1) left.record={id:"left-hidden"}
                if (step===2) left.progress=.0011
                if (step===3) right.progress=.5
                if (step===4) right.record=left.record
                if (step===5) notice.progress=1
                if (step===6) floating.progress=1
                if (step===7) left.progress=.0009
                if (step===8) floating.record=null
                if (step===9) floating.progress=0
                if (step===10) floating.record={id:"popup-hidden"}
                if (step===11) notice.progress=0
                if (step===12) notice.record={id:"notice-hidden"}
                if (step===13) notice.progress=.0011
                if (step===14) right.progress=NaN
                if (step===15) right.progress=Infinity
                if (step===16) left.progress=-0
                if (step===17) left.progress=1
                if (step===18) { floating.progress=.2;notice.progress=.4;left.progress=.5;right.progress=.6 }
                if (step===19) { left.record=["nested"];notice.record=undefined }
                if (step===20) {
                    console.info("OBSTACLE_ORACLE_PASS cases="+cases+" reactive_steps="+(step+1))
                    Qt.quit()
                }
                step++
            } catch(error) { console.error("OBSTACLE_ORACLE_FAIL",error.message,error.stack);Qt.quit() }
        }
    }
}
'''


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--proposal", action="store_true")
    args = parser.parse_args()
    if shutil.which("qs") is None:
        raise SystemExit("FAIL: native QV4/Quickshell required")
    fixture = json.loads(FIXTURE.read_text())
    current = expressions(SOURCE.read_text())
    if args.proposal and current != fixture["expressions"]:
        raise SystemExit("FAIL: proposal baseline changed; re-audit current source")
    candidate = PROPOSAL if args.proposal else current
    with tempfile.TemporaryDirectory(prefix="alis-abyss-obstacle-oracle-") as temp:
        directory = Path(temp)
        (directory / "Baseline.qml").write_text(component(fixture["expressions"]))
        (directory / "Candidate.qml").write_text(component(candidate))
        (directory / "Oracle.js").write_text(functions(fixture["expressions"], "Old") + "\n" + functions(candidate, "New"))
        (directory / "shell.qml").write_text(HARNESS)
        environment = dict(os.environ)
        for name in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "WAYLAND_DISPLAY"):
            environment.pop(name, None)
        environment["QT_QPA_PLATFORM"] = "offscreen"
        result = subprocess.run(["qs", "-p", temp, "--no-color"], env=environment,
                                text=True, capture_output=True, timeout=45)
        output = result.stdout + result.stderr
        marker = re.search(r"OBSTACLE_ORACLE_PASS[^\n]*", output)
        if result.returncode or not marker or re.search(
                r"OBSTACLE_ORACLE_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign", output):
            print(output)
            raise SystemExit("FAIL: native Perimeter obstacle parity")
        print("PASS: " + marker.group())
        print("Baseline: " + fixture["sha"] + "; actual bindings, reference identity, read/error order, fresh arrays, QObject dependencies/NOTIFY")


if __name__ == "__main__":
    main()
