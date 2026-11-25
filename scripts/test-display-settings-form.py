#!/usr/bin/env python3
"""Check real Display & Windows layouts on private Wayland with synthetic outputs."""
import argparse
import json
from pathlib import Path
import tempfile
from native_test_session import private_wayland, run_qs

QML = r"""
import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings
Window {
 id: win; width: 1585; height: 1068; visible: true
 Component.onCompleted: Quickshell.watchFiles = false
 Rectangle { id: host; anchors.fill: parent; color: Appearance.colors.colLayer0 }
 SettingsOverlay { id: overlay; embeddedHost: host; settingsOpen: true }
 TestCase {
  id: test; when: false; optional: true
  function first(item, predicate) {
    if (!item || !item.visible) return null
    if (predicate(item)) return item
    for (const c of item.children ?? []) { const f = first(c,predicate); if(f) return f }
    return null
  }
  function subsection(page,name) { return first(page,i=>i.subsectionLayoutId !== undefined && i.title===name) }
  function track(s) { return first(s,i=>i.sliderLayoutId !== undefined) }
  function box(i) { const p=i.mapToItem(host,0,0);return [p.x,p.y,i.width,i.height] }
  function snap(name) { let saved=false; verify(host.grabToImage(r=>saved=r.saveToFile(Quickshell.env("FORM_OUT")+"/"+name+".png")));tryVerify(()=>saved,5000) }
  function run() {try {
    tryVerify(()=>Config.ready && Persistent.ready && overlay._navigationInitialized,8000)
    overlay.showingHome=false;overlay.overlayCurrentPage=12
    tryVerify(()=>overlay.pageHost?.currentIndex===12 && overlay.pageHost.currentItem && !overlay.pageHost.loading,10000)
    const page=overlay.pageHost.currentItem
    page.activeSection="windows"; wait(450)
    const metrics={}
    for(const w of [1585,760,1585]) {
      win.width=w; wait(270)
      const a=subsection(page,"Corner radius"), b=subsection(page,"Inactive window opacity")
      const s=track(a), q=track(b)
      metrics[w]=[box(a),box(b),box(s),box(q),s.sliderLayoutId,q.sliderLayoutId]
      snap("windows-"+w)
    }
    page.activeSection="input";wait(280)
    metrics.mouse=box(track(subsection(page,"Mouse acceleration & speed")))
    page.activeSection="displays";wait(280)
    CompositorService.isNiri=true;wait(180)
    const map=first(page,i=>i.embeddedArrangementOnly===true); verify(!!map)
    const monitor={x:0,y:0,width:1920,height:1200}
    const canvas=first(map,i=>i.objectName==="monitorArrangementCanvas")
    for(const n of [1,2]) {
      const layout=n===1?{Laptop:monitor}:{Laptop:monitor,External:{x:1920,y:0,width:3840,height:2160}}
      map.monitorLayoutSnapshot=layout;map.monitorLayoutViewportBounds=map.boundsForLayout(layout);wait(250)
      const primary=subsection(page,"Primary monitor");metrics["map"+n]=[box(canvas),box(primary),canvas.canvasScale]
      const zoomIn=first(canvas,i=>i.objectName==="monitorViewportAction2")
      verify(!!zoomIn);const before=canvas.zoomFactor;mouseClick(zoomIn);tryVerify(()=>canvas.zoomFactor>before,1200)
      const reset=first(canvas,i=>i.objectName==="monitorViewportAction1");mouseClick(reset);tryCompare(canvas,"zoomFactor",1,1200)
      snap("displays-"+n)
    }
    console.info("DISPLAY_FORM",JSON.stringify(metrics))
  } catch(e) {console.error("DISPLAY_FORM_FAIL",e.message,e.stack)} Qt.quit()}
 }
 Timer { interval:160; running:true; onTriggered:test.run() }
}
"""
def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[1])
    p.add_argument('--out', type=Path, required=True)
    args = p.parse_args()
    src = args.root.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='alis-display-') as tmp:
        folder = Path(tmp)
        for name in ('modules','services','defaults','translations','assets','GlobalStates.qml','qmldir'):
            (folder/name).symlink_to(src/name)
        (folder/'shell.qml').write_text(QML)
        # The native backend is replaced before launching. No Niri command
        # can reach a real output even when the fixture selects the Niri UI.
        scripts=folder/'scripts'
        scripts.mkdir()
        for f in (src/'scripts').iterdir():
            if f.name != 'native-dispatch': (scripts/f.name).symlink_to(f)
        fake=scripts/'native-dispatch';fake.write_text('#!/bin/sh\necho "{}"\n');fake.chmod(0o755)
        with private_wayland(folder) as env:
            assert env and env.get('QT_QPA_PLATFORM')=='wayland'
            config=json.loads((src/'defaults/config.json').read_text())
            config['panelFamily']='abyss'
            config.setdefault('weather',{})['enable']=False
            for name in ('alis','illogical-impulse'):
                path=folder/'config'/name/'config.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(config))
            res=run_qs(folder,dict(env, FORM_OUT=str(out)),timeout=55)
    (out/'runtime.log').write_text(res.stdout)
    lines=[l for l in res.stdout.splitlines() if 'DISPLAY_FORM ' in l]
    assert not res.returncode and lines and 'DISPLAY_FORM_FAIL' not in res.stdout, res.stdout[-2500:]
    m=json.loads(lines[-1].split('DISPLAY_FORM ',1)[1]);(out/'geometry.json').write_text(json.dumps(m,indent=2))
    a,b,x,y,*_=m['1585'];n,k,*_=m['760']
    assert abs(a[1]-b[1])<3 and b[0]>=a[0]+a[2], 'wide window rules remain stacked'
    assert k[1]>=n[1]+n[3]-1, 'narrow window rules overlap'
    assert x[2]>=270 and y[2]>=270 and m['mouse'][2]>=270, 'desktop tracks too short'
    assert m['map1'][0][3] < m['map2'][0][3], 'multi-output arrangement canvas should grow taller'
    assert m['map1'][0][2] >= 600, f"arrangement canvas should span full card width, got {m['map1'][0][2]}"
    assert m['map1'][1][1] >= m['map1'][0][1] + m['map1'][0][3] - 1, 'primary monitor row should sit cleanly below arrangement canvas'
    assert abs((m['map1'][1][0] + m['map1'][1][2]) - (m['map1'][0][0] + m['map1'][0][2])) <= 4, 'primary monitor row right edge must align flush with arrangement canvas'
    print('PASS: window rules resize, mouse settings, single/multi-output arrangement and native zoom/reset')
if __name__ == '__main__': main()
