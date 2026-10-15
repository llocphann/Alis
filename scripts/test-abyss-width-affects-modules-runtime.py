#!/usr/bin/env python3
"""Native R11 regression: real module/field geometry, identity and width-mode reversal."""
import argparse
import gzip
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--source-root", type=Path, default=REPO,
                    help="explicit frozen runtime git-archive for a negative control")
parser.add_argument("--output", type=Path, help="fresh directory retaining native logs, trace and captures")
parser.add_argument("--prepare-only", action="store_true", help="validate fixture metadata without starting native processes")
args = parser.parse_args()
ROOT = args.source_root.resolve()
helper_spec = importlib.util.spec_from_file_location("alis_r11_native_session", ROOT / "scripts/native_test_session.py")
helper = importlib.util.module_from_spec(helper_spec)
helper_spec.loader.exec_module(helper)
private_wayland, run_qs = helper.private_wayland, helper.run_qs
SOURCES = ["modules/abyss/bar/AbyssBar.qml", "modules/abyss/bar/AbyssBarModule.qml",
           "modules/abyss/looks/AbyssLayout.js", "modules/abyss/AbyssPerimeter.qml",
           "modules/abyss/looks/AbyssField.qml", "modules/abyss/looks/AbyssField.frag",
           "modules/abyss/looks/AbyssField.frag.qsb", "scripts/native_test_session.py",
           "defaults/config.json"]

def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in SOURCES}

frozen_file = ROOT / ".r11-frozen-source.json"
if frozen_file.is_file():
    frozen = json.loads(frozen_file.read_text())
    identity = {"source_sha": frozen["source_sha"], "source_kind": "frozen-git-archive"}
    if hashes() != frozen["selected_sha256"]:
        raise SystemExit("STOP: frozen runtime bytes differ from their source receipt")
else:
    identity = {"source_sha": subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"], text=True).strip(),
                "source_kind": "working-tree",
                "working_tree": subprocess.check_output(["git", "-C", str(ROOT), "status", "--short"], text=True)}

SHELL_QML = r'''
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.abyss.bar
import qs.modules.abyss.looks
import "modules/abyss/looks/AbyssLayout.js" as Layout

ShellRoot {
    id: root
    property string edge: "top"
    property real configuredWidth: 32
    property bool affects: false
    property bool sampling: false
    property string phase: ""
    property int checks: 0
    property int frames: 0
    property var failures: []
    property var traces: []
    property var references: ({})
    property var samples: []
    readonly property var ids: ["first", "custom", "last"]
    Component.onCompleted: Quickshell.watchFiles=false

    FloatingWindow {
        visible: true; implicitWidth: 1000; implicitHeight: 740; color: "#111820"
        Item {
            id: scene; anchors.fill: parent; clip: true
            AbyssField {
                id: field; anchors.fill: parent; boundInterior: true
                renderScale: Window.window?.screen?.devicePixelRatio ?? 1
                records: bar.deformations
                edgeInsets: Layout.edgeInsetsForModules(bar.placements,bar.layoutOptions,
                    Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
                cornerWidthInsets: Layout.edgeInsetsForModules([],bar.layoutOptions,
                    Appearance.fontSizeScale,AbyssStyle.perimeterThickness,AbyssStyle.barThickness,false)
                roundZeroCorners: bar.layoutOptions.edgeRoundZeroCorners ?? {}
            }
            AbyssBar {
                id: bar; anchors.fill: parent; outputName: "R11-private"; edge: root.edge
                draftPlacements: Layout.normalize([
                    {id:"first",kind:"clock",edge:root.edge,position:.22},
                    {id:"custom",kind:"clock",edge:root.edge,position:.50,customSize:true,size:1.15},
                    {id:"last",kind:"clock",edge:root.edge,position:.78}
                ],root.edge)
                draftOptions: ({edgeThicknesses:{[root.edge]:root.configuredWidth},
                    edgeWidthAffectsModules:{[root.edge]:root.affects},
                    edgeRoundZeroCorners:{[root.edge]:true}})
            }
        }
    }
    FrameAnimation {
        running: root.sampling
        onTriggered: root.samples=root.samples.concat([test.snapshot()])
    }
    TestCase {
        id: test; when: false; optional: true
        function check(value,label) {
            root.checks++
            if(!value) root.failures=root.failures.concat([root.phase+": "+label])
            return !!value
        }
        function close(a,b,tolerance=.6) { return Math.abs(a-b)<=tolerance }
        function visual(item) {
            const x=Math.max(0,item.x), y=Math.max(0,item.y)
            const right=Math.min(scene.width,item.x+item.width)
            const bottom=Math.min(scene.height,item.y+item.height)
            const visible=item.visible && right>x && bottom>y
            return {x:x,y:y,w:visible?right-x:0,h:visible?bottom-y:0,visible:visible,
                    cross:visible?(["top","bottom"].includes(root.edge)?bottom-y:right-x):0}
        }
        function snapshot() {
            const edgeIndex=["top","right","bottom","left"].indexOf(root.edge)
            const result={ms:Date.now(),items:{},
                field:{paintInset:field.edgeInsets[root.edge],configuredInset:field.cornerWidthInsets[root.edge],
                       zeroContact:field.physicalContactEdges[edgeIndex]}}
            for(const id of root.ids) {
                const item=bar.itemForId(id)
                if(!item) {result.items[id]=null;continue}
                const r=item.inputRegion
                result.items[id]={visual:visual(item),x:item.x,y:item.y,w:item.width,h:item.height,
                    visible:item.visible,opacity:item.opacity,attachedEdge:item.attachedEdge,
                    region:{x:r.x,y:r.y,w:r.width,h:r.height},
                    sameDelegate:item===root.references[id]?.item,
                    sameFeature:item.feature===root.references[id]?.feature,
                    rendered:bar.renderedRecords.find(record=>record.id===id)?.content ?? null,
                    backing:bar.deformations.some(body=>body.edge===root.edge && body.surface.x<=item.x+.1
                        && body.surface.y<=item.y+.1 && body.surface.x+body.surface.width>=item.x+item.width-.1
                        && body.surface.y+body.surface.height>=item.y+item.height-.1)}
            }
            return result
        }
        function sameVisual(a,b,tolerance=.6) {
            if(!a || !b || a.visible!==b.visible) return false
            if(!a.visible) return true
            return ["x","y","w","h"].every(k=>close(a[k],b[k],tolerance))
        }
        function auditSample(sample) {
            check(sample.field.configuredInset===root.configuredWidth,"configured physical width became animation geometry")
            check(sample.field.zeroContact===(root.configuredWidth===0),"configured zero-corner contact gate changed")
            for(const id of root.ids) {
                const item=sample.items[id]
                check(item!==null,"delegate disappeared "+id)
                if(!item) continue
                check(item.sameDelegate && item.sameFeature,"resident identity changed "+id)
                check(item.attachedEdge===root.edge,"attachment changed "+id)
                check([item.x,item.y,item.w,item.h].every(Number.isFinite),"non-finite bounds "+id)
                check(item.w>=0 && item.h>=0,"negative dimensions "+id)
                const v=item.visual
                if(id==="custom") {
                    const horizontal=["top","bottom"].includes(root.edge)
                    check(v.visible,"custom-size module blinked during inherited toggle")
                    check(close(horizontal?item.h:item.w,32*Appearance.fontSizeScale*1.15),
                          "inherited toggle changed custom cross size")
                }
                if(v.visible) {
                    const rendered=item.rendered
                    check(rendered!==null,"visible foreground lost its shared-field record "+id)
                    if(rendered) check(close(rendered.x,item.x,.1) && close(rendered.y,item.y,.1)
                        && close(rendered.width,item.w,.1) && close(rendered.height,item.h,.1),
                        "shared-field record differs from displayed bounds "+id)
                    if(root.configuredWidth===0) check(item.backing,"visible zero-width module lost its backing "+id)
                    check(close(item.opacity,1,.001),"fade substituted for geometry motion "+id)
                    const edgeHalf=root.edge==="top"?v.y+v.h<=scene.height/2
                        :root.edge==="bottom"?v.y>=scene.height/2
                        :root.edge==="left"?v.x+v.w<=scene.width/2:v.x>=scene.width/2
                    check(edgeHalf,"module crossed the workspace instead of its physical Edge "+id)
                }
                const region=item.region
                const expectedW=item.visible?Math.max(0,Math.ceil(item.x+item.w)-Math.floor(item.x)):0
                const expectedH=item.visible?Math.max(0,Math.ceil(item.y+item.h)-Math.floor(item.y)):0
                check(region.x===Math.floor(item.x) && region.y===Math.floor(item.y)
                      && region.w===expectedW && region.h===expectedH,"Region property trails current bounds "+id)
            }
        }
        function endpoint(affects) {
            for(const id of root.ids) {
                const item=bar.itemForId(id),custom=id==="custom"
                const scale=custom?1.15:affects?root.configuredWidth/16:1
                check(item===root.references[id]?.item && item.feature===root.references[id]?.feature,
                      "endpoint replaced resident "+id)
                if(!custom && scale===0) {
                    check(!item.visible && item.inputRegion.width===0 && item.inputRegion.height===0,
                          "configured zero ON must finally hide inherited modules "+id)
                    continue
                }
                check(item.visible,"expected visible endpoint "+id)
                const horizontal=["top","bottom"].includes(root.edge)
                const cross=horizontal?item.height:item.width
                const span=horizontal?item.width:item.height
                check(close(cross,32*Appearance.fontSizeScale*scale),"wrong final cross size "+id)
                check(close(span,item.naturalSpan*scale),"wrong final natural span "+id)
                const gap=root.edge==="top"?item.y:root.edge==="bottom"?scene.height-item.y-item.height
                    :root.edge==="left"?item.x:scene.width-item.x-item.width
                check(close(gap,8),"wrong final physical-edge inset "+id)
            }
        }
        function atEndpoint(affects) {
            for(const id of ["first","last"]) {
                const item=bar.itemForId(id)
                if(!item) return false
                const target=affects?root.configuredWidth/16:1
                if(target===0) { if(item.visible) return false;continue }
                const cross=["top","bottom"].includes(root.edge)?item.height:item.width
                if(!item.visible || !close(cross,32*Appearance.fontSizeScale*target,.1)) return false
            }
            return true
        }
        function capture(label) {
            let finished=false
            check(scene.grabToImage(result=>{
                root.frames++
                check(result.saveToFile(Quickshell.env("ALIS_R11_CAPTURE_DIR")+"/"+label+".png"),"capture save")
                finished=true
            }),"capture refused")
            tryVerify(()=>finished,3000)
        }
        function endTrace(before,to,requireIntermediate=true) {
            const started=Date.now()
            let capturedDuring=false
            while(Date.now()-started<1500 && (Date.now()-started<100 || !atEndpoint(to))) {
                wait(8)
                const current=snapshot().items.first.visual
                if(!capturedDuring && current.visible
                        && !sameVisual(current,before.items.first.visual) && !atEndpoint(to)) {
                    capture(root.phase+"-during")
                    capturedDuring=true
                }
            }
            root.sampling=false
            const after=snapshot()
            root.samples=root.samples.concat([after])
            for(const sample of root.samples) auditSample(sample)
            for(const id of ["first","last"]) {
                const a=before.items[id].visual,b=after.items[id].visual
                const middle=root.samples.filter(s=>s.items[id] && s.items[id].visual.visible
                    && s.items[id].visual.cross>Math.min(a.cross,b.cross)+.6
                    && s.items[id].visual.cross<Math.max(a.cross,b.cross)-.6)
                if(requireIntermediate) {
                    check(middle.length>=2,"no two rendered intermediate bounds "+id)
                    check(middle.some(s=>!close(s.items[id].visual.cross,middle[0].items[id].visual.cross,.1)),
                          "intermediate geometry never advanced "+id)
                }
            }
            if(Math.abs(before.field.paintInset-after.field.paintInset)>1) {
                const middleInsets=root.samples.filter(s=>s.field.paintInset>Math.min(before.field.paintInset,after.field.paintInset)+.2
                    && s.field.paintInset<Math.max(before.field.paintInset,after.field.paintInset)-.2)
                check(middleInsets.length>=2,"painted Edge inset snapped while foreground moved")
            }
            endpoint(to)
            root.traces=root.traces.concat([{phase:root.phase,before:before,samples:root.samples,after:after}])
            return after
        }
        function transition(to,label) {
            root.phase=label
            const before=snapshot()
            root.samples=[];root.sampling=true
            root.affects=to
            const immediate=snapshot()
            check(close(immediate.field.paintInset,before.field.paintInset,.01),"synchronous field-inset snap")
            for(const id of ["first","last"])
                check(sameVisual(before.items[id].visual,immediate.items[id].visual),"synchronous geometry snap "+id)
            return endTrace(before,to)
        }
        function reverse(label) {
            root.phase=label
            const before=snapshot()
            root.samples=[];root.sampling=true;root.affects=true
            const deadline=Date.now()+1000
            while(Date.now()<deadline && !root.samples.some(s=>{
                const v=s.items.first?.visual
                return v?.visible && !close(v.cross,before.items.first.visual.cross,.6)
                    && !atEndpoint(true)
            })) wait(8)
            const pivot=snapshot()
            check(!atEndpoint(true),"reversal was not reached during live motion")
            root.traces=root.traces.concat([{phase:root.phase+"-outbound",before:before,
                                           samples:root.samples,after:pivot}])
            root.samples=[]
            root.affects=false
            const immediate=snapshot()
            for(const id of ["first","last"])
                check(sameVisual(pivot.items[id].visual,immediate.items[id].visual),"reversal reset/jumped bounds "+id)
            endTrace(pivot,false)
        }
        function run() {
            try {
                tryCompare(Config,"ready",true,6000)
                Config.setNestedValues({"panelFamily":"abyss","bar.verbose":false,
                    "abyss.perimeter.thickness":16,"performance.reduceAnimations":true})
                tryVerify(()=>field.ready,6000)
                for(const edge of ["top","right","bottom","left"]) for(const width of [0,32]) {
                    root.phase=edge+"-"+width+"-setup"
                    Config.setNestedValue("performance.reduceAnimations",true)
                    root.edge=edge;root.configuredWidth=width;root.affects=false
                    tryVerify(()=>root.ids.every(id=>{
                        const item=bar.itemForId(id)
                        return item!==null && item!==undefined && item.feature!==null
                    }),4000)
                    wait(100)
                    root.references={}
                    for(const id of root.ids) {
                        const item=bar.itemForId(id)
                        root.references[id]={item:item,feature:item.feature}
                    }
                    endpoint(false)
                    capture(edge+"-"+width+"-before")
                    Config.setNestedValue("performance.reduceAnimations",false)
                    tryCompare(Appearance,"animationsEnabled",true,1000)
                    transition(true,edge+"-"+width+"-off-on")
                    transition(false,edge+"-"+width+"-on-off")
                    reverse(edge+"-"+width+"-reversal")
                    capture(edge+"-"+width+"-after")
                    root.phase=edge+"-"+width+"-reduced-motion"
                    Config.setNestedValue("performance.reduceAnimations",true)
                    tryCompare(Appearance,"animationsEnabled",false,1000)
                    root.affects=true;endpoint(true)
                    root.affects=false;endpoint(false)
                }
                console.info("ABYSS_R11_TRACE",JSON.stringify({checks:root.checks,traces:root.traces,failures:root.failures}))
                if(root.failures.length) console.error("ABYSS_R11_WIDTH_TOGGLE_NATIVE_FAIL",root.failures.length,
                                                       JSON.stringify(root.failures.slice(0,32)))
                else console.info("ABYSS_R11_WIDTH_TOGGLE_NATIVE_PASS",root.checks,"checks",root.frames,"captures")
            } catch(error) {
                console.error("ABYSS_R11_WIDTH_TOGGLE_NATIVE_FAIL",error.message,error.stack)
            }
            Qt.quit()
        }
    }
    Timer {interval:100;running:true;onTriggered:test.run()}
}
'''

manifest = {**identity, "source_root": str(ROOT), "source_sha256": hashes(),
            "fixture_sha256": hashlib.sha256(SHELL_QML.encode()).hexdigest(),
            "test_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
            "classification": "PREPARED_ONLY_NATIVE_UNRUN",
            "scope": "Actual AbyssBar and AbyssField frame properties; not composed Perimeter, compositor input mask or Owner acceptance"}
if args.prepare_only:
    print(json.dumps(manifest, indent=2))
    raise SystemExit(0)

temporary = tempfile.TemporaryDirectory(prefix="alis-width-mode-result-") if args.output is None else None
output = Path(temporary.name) if temporary else args.output.resolve()
if not temporary:
    output.mkdir(parents=True, exist_ok=False)
with tempfile.TemporaryDirectory(prefix="alis-width-mode-native-") as name:
    folder = Path(name)
    for entry in ("modules", "services", "GlobalStates.qml", "qmldir", "assets", "scripts", "defaults", "translations"):
        (folder / entry).symlink_to(ROOT / entry)
    (folder / "shell.qml").write_text(SHELL_QML)
    config = folder / "config/alis"
    config.mkdir(parents=True)
    data = json.loads((ROOT / "defaults/config.json").read_text())
    data["panelFamily"] = "abyss"
    data["abyss"]["companion"]["enabled"] = False
    data["abyss"]["spectrum"]["enabled"] = False
    data["abyss"]["waves"]["enabled"] = False
    (config / "config.json").write_text(json.dumps(data))
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    with private_wayland(folder, capture_focus=False) as env:
        if env is None:
            raise SystemExit("SKIP: width-mode native regression requires private Niri")
        env["ALIS_R11_CAPTURE_DIR"] = str(output)
        result = run_qs(folder, env, timeout=90)
    (output / "native.log").write_text(result.stdout)
    for log in ("native-test-niri.log",):
        source = folder / log
        if source.exists():
            (output / log).write_bytes(source.read_bytes())
    for line in result.stdout.splitlines():
        if "ABYSS_R11_TRACE " in line:
            with gzip.open(output / "trace.json.gz", "wt") as stream:
                json.dump(json.loads(line.split("ABYSS_R11_TRACE ", 1)[1]), stream, separators=(",", ":"))
    bad = ["ABYSS_R11_WIDTH_TOGGLE_NATIVE_FAIL", "TypeError:", "ReferenceError:",
           "Binding loop", "Unable to assign", "Failed to load configuration", "is not a type"]
    passed = result.returncode == 0 and "ABYSS_R11_WIDTH_TOGGLE_NATIVE_PASS" in result.stdout and not any(t in result.stdout for t in bad)
    manifest.update(process_exit=result.returncode, source_after_sha256=hashes())
    if manifest["source_after_sha256"] != manifest["source_sha256"]:
        passed = False
        manifest["classification"] = "SOURCE_CHANGED_DURING_RUN_UNQUALIFIED"
    else:
        manifest["classification"] = "FOCUSED_NATIVE_PASS_NOT_OWNER_ACCEPTANCE" if passed else "NATIVE_REGRESSION_FAIL"
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    for line in result.stdout.splitlines():
        if "ABYSS_R11_WIDTH_TOGGLE_NATIVE_" in line:
            print(line)
    if not passed:
        print("\n".join(line for line in result.stdout.splitlines() if "ABYSS_R11_TRACE " not in line)[-5000:])
        raise SystemExit(1)
