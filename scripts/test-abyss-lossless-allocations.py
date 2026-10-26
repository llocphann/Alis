#!/usr/bin/env python3
"""Compare production binding bodies with the frozen pre-change QV4 oracle.

--proposal evaluates unpublished local-array transformations before runtime edits.
The default always tests the actual current production declarations.
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
FIXTURE = ROOT / "scripts/fixtures/abyss-lossless-allocations.json"
PATHS = {
    "wave": "modules/common/widgets/WaveVisualizer.qml",
    "controller": "modules/abyss/AbyssSurfaceController.qml",
}
NAMES = ("processedBars", "placementRequests", "records", "inputBounds")


def declaration(source: str, name: str) -> str:
    start = source.index(f"    readonly property var {name}:")
    if name == "processedBars":
        end = source.index("\n\n    Row {", start)
    else:
        match = re.search(r"\n    (?://|(?:readonly )?property |function )", source[start + 1:])
        if match is None:
            raise ValueError(f"cannot bound {name}")
        end = start + 1 + match.start()
    return source[start:end].rstrip()


def proposal(declarations: dict[str, str]) -> dict[str, str]:
    result = dict(declarations)
    old = """            const next = new Array(count)
            for (let i = 0; i < count; ++i) {
                const prev = i > 0 ? out[i - 1] : out[i]
                const curr = out[i]
                const following = i < count - 1 ? out[i + 1] : out[i]
                next[i] = prev * 0.25 + curr * 0.5 + following * 0.25
            }
            out = next"""
    new = """            let prev = out[0]
            let curr = out[0]
            for (let i = 0; i < count; ++i) {
                const following = i < count - 1 ? out[i + 1] : curr
                out[i] = prev * 0.25 + curr * 0.5 + following * 0.25
                prev = curr
                curr = following
            }"""
    if old not in result["processedBars"]:
        raise ValueError("proposal requires the untouched baseline smoothing loop")
    result["processedBars"] = result["processedBars"].replace(old, new)
    for name, value, predicate in (
        ("placementRequests", "request", "request !== null && request !== undefined"),
        ("inputBounds", "rect", "rect && rect.width > 0 && rect.height > 0"),
        ("records", "rec", "rec && rec.surface.width > 0 && rec.surface.height > 0"),
    ):
        expression = result[name].split(":", 1)[1].strip()
        tail = f"\n        .filter({value} => {predicate})"
        if name == "records":
            tail += ")"
        if not expression.endswith(tail):
            raise ValueError(f"proposal requires baseline filter in {name}")
        mapped = expression[:-len(tail)]
        if name == "records":
            mapped = mapped.removeprefix("moduleRecords.concat(")
        body = (f"const mapped = {mapped}\n"
                "        let kept = 0\n"
                "        for (let i = 0; i < mapped.length; ++i) {\n"
                f"            const {value} = mapped[i]\n"
                f"            if ({predicate}) mapped[kept++] = {value}\n"
                "        }\n"
                "        mapped.length = kept\n"
                "        return mapped")
        if name == "records":
            expression = "moduleRecords.concat((() => {\n        " + body + "\n    })())"
        else:
            expression = "{\n        " + body + "\n    }"
        result[name] = f"    readonly property var {name}: {expression}"
    return result


def component(declarations: dict[str, str]) -> str:
    return """import QtQuick
QtObject {
    id: root
    property var participants: ({})
    property var moduleRecords: []
    property int activeBars: 4
    property bool live: true
    property list<var> points: []
    property real maxVisualizerValue: 1000
    property int smoothing: 2
    property var notifications: [0,0,0,0]
    function notify(index) { notifications[index]++ }
    onProcessedBarsChanged: notify(0)
    onPlacementRequestsChanged: notify(1)
    onRecordsChanged: notify(2)
    onInputBoundsChanged: notify(3)
""" + "\n".join(declarations.values()) + "\n}\n"


def functions(declarations: dict[str, str], suffix: str) -> str:
    result = []
    for name, decl in declarations.items():
        expression = decl.split(":", 1)[1].strip()
        body = expression[1:-1] if expression.startswith("{") else "return " + expression
        result.append(f"function {name}{suffix}(root,participants,moduleRecords) {{\n{body}\n}}")
    return "\n".join(result)


HARNESS = r'''//@ pragma ShellId alis-abyss-lossless-allocation-oracle
import QtQuick
import Quickshell
import "Oracle.js" as Oracle
ShellRoot {
    id: test
    property int cases: 0
    property int step: 0
    property QtObject participant: QtObject {
        property var placementRequest: ({id:"one",open:true})
        property var inputBounds: ({x:0,y:0,width:20,height:30})
        property var geometry: ({surface:{x:0,y:0,width:20,height:30},edge:"top"})
        property real mass: 2
    }
    Baseline { id: oldBinding; participants: ({one:test.participant}) }
    Candidate { id: newBinding; participants: ({one:test.participant}) }
    function assertSame(a,b,label) {
        if (Array.isArray(a) && Array.isArray(b)) {
            if (a.length !== b.length) throw new Error(label+": length")
            for (let i=0;i<a.length;i++) {
                if ((i in a)!==(i in b)) throw new Error(label+": hole")
                assertSame(a[i],b[i],label+"["+i+"]")
            }
        } else if (a && b && typeof a==="object" && typeof b==="object") {
            const keys=Object.keys(a)
            assertSame(keys,Object.keys(b),label+": keys")
            for (const key of keys) assertSame(a[key],b[key],label+"."+key)
        } else if (!Object.is(a,b)) throw new Error(label+": numeric/identity mismatch")
    }
    function outcome(fn,args) {
        try { return {value:fn.apply(null,args),error:""} }
        catch(error) { return {error:error.name+":"+error.message} }
    }
    function compare(name,args,makeArgs) {
        const a=makeArgs ? makeArgs() : {args:args,trace:[]}
        const b=makeArgs ? makeArgs() : {args:args,trace:[]}
        const before=outcome(Oracle[name+"Old"],a.args)
        const after=outcome(Oracle[name+"New"],b.args)
        assertSame(before,after,name)
        assertSame(a.trace,b.trace,name+": read order")
        if (!before.error) {
            const again=Oracle[name+"New"].apply(null,b.args)
            if (again===after.value) throw new Error(name+": reused publication")
        }
        cases++
    }
    function tracedParticipants(mode) {
        const trace=[]
        const pool={}
        function getter(object,key,value,label) {
            Object.defineProperty(object,key,{enumerable:true,get:function() {
                trace.push(label)
                if(mode==="throw" && label==="b.geometry") throw new Error("malformed geometry")
                return value
            }})
        }
        for(const id of ["10","2","a","b","é","e\u0301","__proto__"]) {
            const rect={}
            getter(rect,"width",id==="a" ? 0 : mode==="nan" ? NaN : 20,id+".width")
            getter(rect,"height",mode==="infinity" ? Infinity : 30,id+".height")
            const request= id==="a" ? null : id==="b" ? undefined : {id:id}
            const geometry={surface:rect,edge:"top"}
            const p={}
            getter(p,"placementRequest",request,id+".placementRequest")
            getter(p,"inputBounds",rect,id+".inputBounds")
            getter(p,"geometry",geometry,id+".geometry")
            getter(p,"mass",mode==="negativeZero" ? -0 : 2,id+".mass")
            getter(pool,id,p,id+".participant")
        }
        // Inherited and non-enumerable participants remain excluded by keys().
        Object.setPrototypeOf(pool,{inherited:{geometry:{surface:{width:1,height:1}}}})
        Object.defineProperty(pool,"hidden",{value:{},enumerable:false})
        const modules=[]
        Object.defineProperty(modules,"concat",{value:function(other) {
            trace.push("concat.call");return Array.prototype.concat.call(this,other)
        }})
        return {args:[null,pool,modules],trace:trace}
    }
    function runPureOracle() {
        const samples=[[],[0],[1],[1000],[Infinity],[-Infinity],[NaN],[-0],
            [null,undefined,"",false,"25","bad"],[1,NaN,Infinity,-0,250],
            [0,25,500,1000,2000,50]]
        const maxima=[1000,1,0,-1,NaN,Infinity,-Infinity]
        for(let count=0;count<=64;count++) {
            for(const points of samples) {
                for(const smoothing of [-3,0,1,2,3,7]) {
                    for(const max of maxima) {
                        compare("processedBars",[{activeBars:count,points:points,
                            smoothing:smoothing,maxVisualizerValue:max,live:true},null,null])
                    }
                }
            }
        }
        for(const live of [false,true]) compare("processedBars",[
            {activeBars:4,points:[],smoothing:2,maxVisualizerValue:1000,live:live},null,null])
        for(const name of ["placementRequests","records","inputBounds"]) {
            for(const mode of ["ordinary","throw","nan","infinity","negativeZero"])
                compare(name,null,()=>tracedParticipants(mode))
            for(const pool of [{},null,undefined,{a:null,b:undefined},
                    {a:{geometry:{surface:null},inputBounds:null}},
                    {a:{placementRequest:false,geometry:{surface:{width:-0,height:1}},inputBounds:{width:1,height:0}}}])
                compare(name,[null,pool,[]])
        }
    }
    function checkBindings() {
        for(const name of ["processedBars","placementRequests","records","inputBounds"])
            assertSame(oldBinding[name],newBinding[name],"binding "+name)
        assertSame(oldBinding.notifications,newBinding.notifications,"NOTIFY count")
    }
    Component.onCompleted: {
        try { runPureOracle();checkBindings() }
        catch(error) { console.error("ALLOCATION_ORACLE_FAIL",error.stack);Qt.quit() }
    }
    Timer {
        interval: 10;repeat:true;running:true
        onTriggered: {
            try {
                checkBindings()
                if(step===0) participant.inputBounds={x:1,y:2,width:0,height:30}
                if(step===1) participant.placementRequest=null
                if(step===2) participant.geometry={surface:{x:2,y:3,width:30,height:40}}
                if(step===3) participant.mass=3
                if(step===4) {
                    oldBinding.points=[0,250,500,1000];newBinding.points=[0,250,500,1000]
                }
                if(step===5) { oldBinding.smoothing=3;newBinding.smoothing=3 }
                if(step===6) { oldBinding.live=false;newBinding.live=false }
                if(step===7) { oldBinding.live=true;newBinding.live=true }
                if(step===8) {
                    oldBinding.activeBars=64;newBinding.activeBars=64
                    oldBinding.participants={one:participant,two:null}
                    newBinding.participants={one:participant,two:null}
                }
                if(step===9) {
                    const modules=[{surface:{x:4,y:5,width:10,height:10}}]
                    oldBinding.moduleRecords=modules;newBinding.moduleRecords=modules
                }
                if(step===10) {
                    console.info("ALLOCATION_ORACLE_PASS cases="+cases+" reactive_steps="+(step+1))
                    Qt.quit()
                }
                step++
            } catch(error) { console.error("ALLOCATION_ORACLE_FAIL",error.stack);Qt.quit() }
        }
    }
}
'''


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--proposal", action="store_true")
    args = parser.parse_args()
    if shutil.which("qs") is None:
        raise SystemExit("FAIL: QV4/Quickshell is required; parity cannot be skipped")
    fixture = json.loads(FIXTURE.read_text())
    sources = {key: (ROOT / path).read_text() for key, path in PATHS.items()}
    current = {name: declaration(sources["wave" if name == "processedBars" else "controller"], name)
               for name in NAMES}
    candidate = proposal(current) if args.proposal else current
    with tempfile.TemporaryDirectory(prefix="alis-abyss-allocation-oracle-") as temp:
        directory = Path(temp)
        baseline = fixture["declarations"]
        (directory / "Baseline.qml").write_text(component(baseline))
        (directory / "Candidate.qml").write_text(component(candidate))
        (directory / "Oracle.js").write_text(functions(baseline, "Old") + "\n" + functions(candidate, "New"))
        (directory / "shell.qml").write_text(HARNESS)
        environment = dict(os.environ)
        for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "WAYLAND_DISPLAY"):
            environment.pop(key, None)
        environment["QT_QPA_PLATFORM"] = "offscreen"
        result = subprocess.run(["qs", "-p", temp, "--no-color"], env=environment,
                                text=True, capture_output=True, timeout=60)
        output = result.stdout + result.stderr
        if (result.returncode != 0 or "ALLOCATION_ORACLE_PASS" not in output
                or re.search(r"ALLOCATION_ORACLE_FAIL|ReferenceError:|TypeError:|Binding loop|Unable to assign", output)):
            print(output)
            raise SystemExit("FAIL: native allocation parity oracle")
        marker = re.search(r"ALLOCATION_ORACLE_PASS[^\n]*", output)
        print("PASS: " + marker.group(0))
        print("Baseline: " + fixture["sha"] + "; native QV4 values/read order/errors/fresh identity/QObject dependencies/NOTIFY")


if __name__ == "__main__":
    main()
